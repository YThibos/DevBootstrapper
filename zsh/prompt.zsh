# The prompt:  user(WSL2) ~/dir git:[branch*] $   or   user(:host) ~/dir $   outside WSL.
#
# Colours run from dark to light teal: user #008787, label #00afaf, directory #00d7d7, and the
# git: prefix with its brackets #5fffff. The branch shows the state of the workspace:
# green clean, yellow staged or unstaged changes, red untracked files (which take priority).

__devboot_prompt_host_label() {
  if [[ -n ${DEV_IS_WSL:-} ]]; then
    print -n WSL2
  else
    print -n ":${HOST%%.*}"
  fi
}

# On WSL2's /mnt/c every file stat crosses the Linux and Windows boundary, so git status costs
# seconds there. git diff-index --quiet answers "staged or unstaged changes?" by exit code and
# stops at the first changed file; the untracked check stops at the first result.
__devboot_prompt_git() {
  local GIT_OPTIONAL_LOCKS=0
  local branch color=green dirty=''
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || return
  [[ $branch == HEAD ]] && branch='(detached)'

  if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    color=yellow dirty='*'
  elif [[ -n $(git ls-files --others --exclude-standard --directory --no-empty-directory 2>/dev/null | head -1) ]]; then
    color=red dirty='*'
  fi
  print -n " %F{87}git:[%F{$color}${branch}${dirty}%F{87}]%f"
}

# A prompt theme from promptinit, such as the one the zsh new-user wizard picks, would rewrite
# PROMPT at every prompt.
(( $+functions[prompt] )) && prompt off 2>/dev/null

setopt PROMPT_SUBST
PROMPT='%F{30}%n%F{37}($(__devboot_prompt_host_label))%f %F{44}%~%f$(__devboot_prompt_git) %F{30}$%f '
