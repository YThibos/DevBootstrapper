#!/usr/bin/env bash
# Tests compare against literal "$VAR" and "~/" strings on purpose.
# shellcheck disable=SC2016,SC2088
# gitid: contexts, accounts, commit identity per folder, credential helper, SSH wrapper,
# gh/glab wrappers, pinning, one-off accounts and listing.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
new_sandbox

g() { run "$DEV/bin/gitid" "$@"; }

g add-context home --name "Home Me" --email home@example.com >/dev/null 2>&1
g add-context work --name "Work Me" --email work@example.com >/dev/null 2>&1
g add-account github-personal --forge github --host github.com --user me-personal --auth https --token-var GITHUB_PERSONAL_TOKEN >/dev/null 2>&1
g add-account github-work --forge github --host github.com --user me-work --auth https >/dev/null 2>&1
g add-account gitlab-work --forge gitlab --host gitlab.example.org --user me-gl --auth ssh --ssh-key '~/.ssh/id_test_gitlab' >/dev/null 2>&1
g link home github-personal >/dev/null 2>&1
g link work github-work >/dev/null 2>&1
g link work gitlab-work >/dev/null 2>&1
g default work >/dev/null 2>&1
mkdir -p "$HOME/.ssh" && touch "$HOME/.ssh/id_test_gitlab"

secrets=$(cat "$DEV/.secrets")
assert_contains "$secrets" "GITHUB_PERSONAL_TOKEN=" "add-account adds a token line to .secrets"
assert_contains "$secrets" "GITHUB_WORK_TOKEN=" "default token variable is derived from the account name"
assert_eq "$(stat -c %a "$DEV/.secrets")" 600 ".secrets is created private"
sed -i -e 's/^GITHUB_PERSONAL_TOKEN=$/GITHUB_PERSONAL_TOKEN=tok-personal/' \
  -e 's/^GITHUB_WORK_TOKEN=$/GITHUB_WORK_TOKEN=tok-work/' \
  -e 's/^GITLAB_WORK_TOKEN=$/GITLAB_WORK_TOKEN=tok-gitlab/' "$DEV/.secrets"

run bash "$DEV/install/devup.sh" --only links,identities >/dev/null 2>&1
assert_eq "$(readlink "$HOME/.gitconfig")" "$DEV/config/git/gitconfig" "devup links ~/.gitconfig"

mkrepo() { mkdir -p "$1" && git -C "$1" init -q && git -C "$1" remote add origin "$2"; }
mkrepo "$DEV/sources/home/tooling" https://github.com/me-personal/tooling.git
mkrepo "$DEV/sources/work/service" https://github.com/work-org/service.git
mkrepo "$DEV/sources/work/sub/deep" https://github.com/work-org/deep.git
mkrepo "$HOME/elsewhere" https://github.com/someone/else.git

email() { (cd "$1" && run bash -c 'git config user.email'); }
assert_eq "$(email "$DEV/sources/home/tooling")" home@example.com "sources/home uses the home identity (non-interactive shell)"
assert_eq "$(email "$DEV/sources/work/service")" work@example.com "sources/work uses the work identity"
assert_eq "$(email "$DEV/sources/work/sub/deep")" work@example.com "nested folders keep their context"
assert_eq "$(email "$HOME/elsewhere")" work@example.com "outside sources/ the machine default applies"

cred() { (cd "$1" && printf 'protocol=https\nhost=%s\n\n' "$2" | run git credential fill 2>/dev/null | sed -n 's/^password=//p'); }
assert_eq "$(cred "$DEV/sources/home/tooling" github.com)" tok-personal "git credentials in sources/home: personal GitHub account"
assert_eq "$(cred "$DEV/sources/work/service" github.com)" tok-work "git credentials in sources/work: work GitHub account"
assert_eq "$(cred "$DEV/sources/home" github.com)" tok-personal "clone into sources/home (no repo yet) uses the personal account"
assert_eq "$(cred "$DEV/sources/work" github.com)" tok-work "clone into sources/work uses the work account"
assert_eq "$(cred "$HOME/elsewhere" github.com)" tok-work "outside sources/: the default context's account"
assert_eq "$(cred "$DEV/sources/home/tooling" gitlab.example.org)" "" "no account for a host in a context: helper stays silent"
user=$(cd "$DEV/sources/home" && printf 'protocol=https\nhost=github.com\n\n' | run git credential fill 2>/dev/null | sed -n 's/^username=//p')
assert_eq "$user" me-personal "the credential username is the account's user"

(cd "$DEV/sources/work/service" && run "$DEV/bin/gitid" use home >/dev/null 2>&1)
assert_eq "$(email "$DEV/sources/work/service")" home@example.com "gitid use pins a repository's commit identity"
assert_eq "$(cred "$DEV/sources/work/service" github.com)" tok-personal "gitid use pins a repository's account"
(cd "$DEV/sources/work/service" && run "$DEV/bin/gitid" use --clear >/dev/null 2>&1)
assert_eq "$(email "$DEV/sources/work/service")" work@example.com "gitid use --clear restores the folder context"

asout=$(cd "$DEV/sources/work/service" && printf 'protocol=https\nhost=github.com\n\n' | run "$DEV/bin/gitid" as github-personal -- git credential fill 2>/dev/null | sed -n 's/^password=//p')
assert_eq "$asout" tok-personal "gitid as runs one command as another account"

# SSH: a stand-in ssh records its arguments.
cat >"$FAKEBIN/ssh" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$HOME/ssh-args"
exit 1
FAKE
chmod +x "$FAKEBIN/ssh"
(cd "$DEV/sources/work/service" && run git ls-remote git@gitlab.example.org:grp/x.git >/dev/null 2>&1)
assert_contains "$(cat "$HOME/ssh-args" 2>/dev/null)" "-i $HOME/.ssh/id_test_gitlab" "git over SSH in sources/work uses the work GitLab key"
(cd "$DEV/sources/home/tooling" && run git ls-remote git@gitlab.example.org:grp/x.git >/dev/null 2>&1)
assert_not_contains "$(cat "$HOME/ssh-args" 2>/dev/null)" "-i " "git over SSH without an SSH account uses plain ssh"

# gh and glab wrappers: stand-ins print the credentials they receive.
printf '#!/usr/bin/env bash\necho "token=${GH_TOKEN:-}"\n' >"$FAKEBIN/gh"
printf '#!/usr/bin/env bash\necho "host=${GITLAB_HOST:-} token=${GITLAB_TOKEN:-}"\n' >"$FAKEBIN/glab"
chmod +x "$FAKEBIN/gh" "$FAKEBIN/glab"
assert_eq "$(cd "$DEV/sources/home/tooling" && run gh)" token=tok-personal "gh in sources/home runs as the personal account"
assert_eq "$(cd "$DEV/sources/work/service" && run gh)" token=tok-work "gh in sources/work runs as the work account"
assert_eq "$(cd "$DEV/sources/work/service" && run "$DEV/bin/gitid" as github-personal -- gh)" token=tok-personal "gitid as works for gh"
assert_eq "$(cd "$DEV/sources/work/service" && run glab)" "host=gitlab.example.org token=tok-gitlab" "glab in sources/work runs as the work GitLab account"
assert_eq "$(cd "$DEV/sources/home/tooling" && run glab)" "host= token=" "glab where no GitLab account applies gets no token"

# One account per host per context.
g link work github-personal >/dev/null 2>&1
assert_eq "$(run git config -f "$DEV/.local/git/identities.gitconfig" --get-all context.work.account | sort | paste -sd, -)" \
  "github-personal,gitlab-work" "linking a second account for a host replaces the first"
g link work github-work >/dev/null 2>&1

# Listing.
list=$(g list)
assert_contains "$list" "github-personal" "gitid list shows accounts"
assert_not_contains "$list" "tok-personal" "gitid list never prints token values"
assert_contains "$list" "(set)" "gitid list reports which tokens are set"
assert_contains "$(printf '%s\n' "$list" | grep '^  work ')" "github-work" "context table shows work -> github-work"
assert_contains "$(printf '%s\n' "$list" | grep '^  work ')" "gitlab-work" "context table shows work -> gitlab-work"
assert_contains "$list" "-> work (machine default)" "gitid list shows the machine default"
assert_eq "$(run "$DEV/bin/dev" ids)" "$list" "dev ids prints the same table"
status=$(cd "$DEV/sources/home/tooling" && g)
assert_contains "$status" "home (folder sources/home/)" "gitid status explains why a context applies"
assert_contains "$status" "github.com (https) -> github-personal" "gitid status shows the account per remote"

# A third context works without editing tracked files.
g add-context client --name "Client Me" --email me@client.example --account github-personal >/dev/null 2>&1
assert_true "add-context creates its sources folder" test -d "$DEV/sources/client"
mkrepo "$DEV/sources/client/app" https://github.com/client/app.git
assert_eq "$(email "$DEV/sources/client/app")" me@client.example "a new context's folder gets its identity"
assert_eq "$(cred "$DEV/sources/client/app" github.com)" tok-personal "a new context uses its linked account"

doctor=$(g doctor 2>&1)
assert_contains "$doctor" "git identities look good" "gitid doctor passes with tokens and keys present"

finish
