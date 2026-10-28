# shellcheck shell=bash
# Windows integration inside WSL.
[ -n "${DEV_IS_WSL:-}" ] || return 0
#: open <file|url> | open with the Windows default application
#: explorer | open the current folder in Windows Explorer
#: clip | copy stdin to the Windows clipboard
command -v wslview >/dev/null 2>&1 && alias open='wslview'
alias explorer='explorer.exe .'
alias clip='clip.exe'
