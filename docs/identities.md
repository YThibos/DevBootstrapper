# Git identities

Any number of forge accounts can be used side by side, several per forge.

## Concepts

- **Account**: one login on one forge host, e.g. `github-personal` and `github-work` on github.com, `gitlab-work` on your work GitLab.
  It authenticates with an HTTPS token from `.secrets` (default, works through corporate proxies) or with an SSH key.
- **Context**: a folder under `sources/` (`home`, `work`, and any you add).
  It sets the commit name and email, an optional signing key, and which account to use for each host (at most one per host).

## Which identity applies

1. A repository pinned with `gitid use <context>`.
2. Otherwise the folder: anything under `sources/<context>/`.
3. Otherwise this machine's default context (`gitid default`), e.g. `work` on the work laptop.

Within that context the remote's host picks the account.
This covers commits, `git clone`, fetch and push (HTTPS and SSH), and the `gh` and `glab` CLIs, also when started by other programs.

## Commands

```bash
gitid                               # what applies here and why
gitid list                          # every account and context (also: dev ids)
gitid add-account github-personal   # guided; or --forge --host --user --auth --token-var --ssh-key
gitid add-context client-x          # creates sources/client-x/
gitid link work gitlab-work         # use an account in a context
gitid default work                  # this machine's default context
gitid use home                      # pin the current repository (gitid use --clear)
gitid as github-personal -- gh repo create my-tool --private
gitid doctor                        # tokens, keys and generated config
clone https://github.com/me/tool    # clones into the current context's folder and cd's into it
```

Example: to work on your own tooling from the work laptop, clone it under `sources/home/`; commits use your private email and pushes use your personal account.

## Where it is stored

`.local/git/identities.gitconfig` holds accounts and contexts; it is machine-local because the repository is public.
`gitid` generates `.local/git/routing.gitconfig` and one file per context from it; `~/.gitconfig` includes them.
Tokens live only in `.secrets`.
