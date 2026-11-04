# DevBootstrapper entry point for zsh, the opt-in counterpart of bash/bootstrap.sh (docs/shell.md).
# Sourced from two marked blocks that devup adds when .local/profile.env says DEV_SHELL=zsh:
#   . bootstrap.zsh env   ~/.zshenv: environment layer for every zsh, also non-interactive
#   . bootstrap.zsh       ~/.zshrc: interactive layer, after the user's own settings

__devboot_zsh=${0:A:h}
__devboot_bash=${__devboot_zsh:h}/bash
__devboot_shell=zsh

# The environment layer is the one bash uses, and loads once per shell process.
if [[ ${__devboot_env_loaded:-} != $$ ]]; then
  . "$__devboot_bash/env.sh"
  __devboot_env_loaded=$$
fi

if [[ ${1:-} == env ]]; then
  skip_global_compinit=1
  unset __devboot_zsh __devboot_bash
  return 0
fi
if [[ ! -o interactive ]]; then
  unset __devboot_zsh __devboot_bash
  return 0
fi

# Interactive layer, in this order. Each file skips silently when its tool is missing.
# Completion comes before the tools, so fzf and zoxide find compdef.
for __devboot_f in \
  $__devboot_zsh/history.zsh \
  $__devboot_zsh/keybindings.zsh \
  $__devboot_zsh/completion.zsh \
  $__devboot_bash/tools/mise.sh \
  $__devboot_bash/tools/git.sh \
  $__devboot_bash/tools/java.sh \
  $__devboot_bash/tools/node.sh \
  $__devboot_bash/tools/docker.sh \
  $__devboot_bash/tools/fzf.sh \
  $__devboot_bash/tools/zoxide.sh \
  $__devboot_bash/tools/wsl.sh \
  $__devboot_bash/tools/wezterm.sh \
  $__devboot_bash/aliases.sh \
  $__devboot_bash/functions.sh \
  $__devboot_zsh/prompt.zsh \
  $__devboot_zsh/local.zsh; do
  [[ -r $__devboot_f ]] && . "$__devboot_f"
done
. "$__devboot_bash/update-reminder.sh"
unset __devboot_f __devboot_zsh __devboot_bash

reload() {
  __devboot_env_loaded=''
  . "$DEV_HOME/zsh/bootstrap.zsh"
}
