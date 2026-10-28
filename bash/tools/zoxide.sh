# shellcheck shell=bash
# zoxide: "z part-of-a-path" jumps to a frequently used folder.
command -v zoxide >/dev/null 2>&1 || return 0
#: z <part> | jump to a frequently used folder
#: zi | pick a frequent folder interactively
eval "$(zoxide init bash)"
