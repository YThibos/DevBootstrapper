# shellcheck shell=bash
# Windows integration inside WSL. Windows programs are called by full path: appendWindowsPath
# is off in /etc/wsl.conf, so they are not on PATH.
[ -n "${DEV_IS_WSL:-}" ] || return 0
#: open <file|url> | open with the Windows default application (winopen)
#: explorer | open the current folder in Windows Explorer
#: clip | copy stdin to the Windows clipboard
alias open='winopen'
alias explorer='winopen .'
alias clip='"${DEV_WINDOWS_ROOT:-/mnt/c/Windows}/System32/clip.exe"'
