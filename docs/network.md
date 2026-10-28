# Network: profile, proxy, certificates, mirrors

Everything machine-specific lives in `.local/profile.env` (not in git), created by `devup --first-run` from `.local.example/profile.env`.
Values are `KEY=value` lines loaded by the shell; quote a value that contains characters such as `&`, `?` or spaces: `KEY='https://host/path?a=1&b=2'`.

| Setting | Effect |
|---|---|
| `DEV_PROFILE` | `home` or `work`; the default git context outside `sources/`. |
| `DEV_PROXY_URL`, `DEV_NO_PROXY` | Proxy for the shell environment (curl, git, mise, npm, uv, pip), apt, Maven (`settings.xml`) and Java (`JAVA_TOOL_OPTIONS`). |
| `DEV_CA_CERT` | Corporate root certificate (PEM): added to Ubuntu's trust store and every JDK by devup, and used by Node, Python and other tools. |
| `DEV_MAVEN_MIRROR_URL`, `DEV_MAVEN_MIRROR_OF` | A Maven mirror; its credentials go in `.secrets` as `MAVEN_MIRROR_USERNAME` and `MAVEN_MIRROR_PASSWORD`. |
| `DEV_NPM_REGISTRY` | An npm registry mirror; its token goes in `.secrets` as `NPM_REGISTRY_TOKEN`. |
| `DEV_WINDOWS_TOOLS` | The Windows tools folder as seen from WSL (default `/mnt/c/development/tools`). |

After changing it, run `devup` (or at least `devup --only certs,apt,render,links,certs-java`) and open a new shell.
With no proxy and no certificate, all of this does nothing, which is the home setup.

Maven and npm settings are rendered from `config/maven/settings.xml` and `config/npm/npmrc` into `.local/`, and `~/.m2/settings.xml` and `~/.npmrc` link there.
A previous `~/.m2/settings.xml` or `~/.npmrc` is kept in `tmp/backup-<date>/`; move its mirrors into the profile and its credentials into `.secrets`.

The installer's optional `.wslconfig` tuning (mirrored networking, `autoProxy`, DNS tunnelling) usually makes WSL follow the Windows proxy and VPN.
`dev doctor` reports whether github.com is reachable.
