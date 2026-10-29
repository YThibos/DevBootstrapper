# Tools and versions

## Where tools come from

1. **mise**, whenever it offers a prebuilt binary: Java (Temurin 8, 11, 17, 21, 25), Maven 3.10, mvnd, Gradle, Node LTS with npm, the Angular CLI, Python, uv, Claude Code, gh, glab, jq, yq, ripgrep, fd, fzf, bat, eza, zoxide, delta, lazygit, lazydocker, starship, xh, glow, shellcheck, shfmt and tmux.
   They install into `~/development/tools/mise`.
2. **apt**, for the rest: git (from the git-core PPA when it has a build for your Ubuntu release), build tools, curl and a few basics.
   See `install/apt-packages.txt`; a package your Ubuntu release no longer offers is skipped with a warning.
   Opening links and files in Windows needs no package: `winopen` (also `open`) calls Windows directly and is the `BROWSER` inside WSL.
3. **Their own platform**: Docker comes from Docker Desktop's WSL integration; WezTerm from its nightly zip via the launcher.

The shared list is `config/mise/config.toml`.
To add a tool, add a line there (one tool per line) and run `devup`.

## Versions

- Runtimes stay on their line: each Java LTS gets patch updates, Node follows LTS, Maven follows 3.10.
- Everything else follows the latest release.
- For a list such as `java = ["temurin-25", "temurin-21"]`, every entry is installed and the first is the default.
- Maven 4 joins the shared list once 4.0.0 is released: a line such as `"4"` never matches its release candidates.
  Until then, `mvnuse 4.0.0-rc-7` installs a candidate on one machine.
- A project pins its own versions with a `.mise.toml` or `.java-version` in its folder; that always wins inside the project.

## Switching the default on this machine

```bash
mvnuse            # list Maven versions, * marks the default
mvnuse 4.0.0-rc-7 # a Maven 4 candidate becomes this machine's default
mvnuse --reset    # back to the shared default (3.10)
jdkuse 21         # JDK 21 as default
use-version       # every tool with several versions
```

The switch is written to `.local/mise/config.toml`, which mise layers over the shared manifest.
It applies to new shells and to programs straight away, never changes the shared manifest and never affects your other machines.
The Windows-native side will get the same commands in a later phase.
