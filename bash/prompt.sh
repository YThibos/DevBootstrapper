# shellcheck shell=bash
# Prompt: starship when installed (config/starship.toml), otherwise a plain prompt with the
# git branch and the active gitid context.
if command -v starship >/dev/null 2>&1; then
  eval "$(starship init bash)"
  return 0
fi

__devboot_ps1_git() {
  local branch ctx
  branch=$(git symbolic-ref --short -q HEAD 2>/dev/null) || return 0
  ctx=$(gitid prompt 2>/dev/null)
  printf ' (%s%s)' "$branch" "${ctx:+ @$ctx}"
}
PS1='\[\e[34m\]\w\[\e[35m\]$(__devboot_ps1_git)\[\e[0m\]\n\$ '
