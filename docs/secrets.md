# Secrets

`~/development/.secrets` holds credentials, API keys and tokens.
It is never committed (the repository's `.gitignore` is an allow-list), is created with mode 600, and `dev doctor` warns if it becomes readable by others.

- Format: `KEY=value` lines, loaded into every shell and also usable as a Docker `--env-file`.
- `.secrets.example` lists the expected keys; `gitid add-account` adds a line for each new account's token.
- Edit it with `secrets`, which reloads it into the current shell.
- Configuration files only reference secrets by name (`${env.MAVEN_MIRROR_PASSWORD}`, `${NPM_REGISTRY_TOKEN}`), never by value.
