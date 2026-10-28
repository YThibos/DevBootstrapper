# shellcheck shell=bash
# Docker (Docker Desktop's WSL integration provides the CLI).
command -v docker >/dev/null 2>&1 || return 0
#: dc | docker compose
#: dps | running containers, compact
#: lzd | lazydocker
alias dc='docker compose'
alias dps='docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"'
command -v lazydocker >/dev/null 2>&1 && alias lzd='lazydocker'
