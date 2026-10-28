# shellcheck shell=bash
# Shell history: large, shared between tabs, without duplicates.
HISTSIZE=50000
HISTFILESIZE=100000
HISTCONTROL=ignoreboth:erasedups
HISTTIMEFORMAT='%F %T '
shopt -s histappend cmdhist checkwinsize
case ";${PROMPT_COMMAND:-};" in
  *";history -a;"*) ;;
  *) PROMPT_COMMAND="history -a${PROMPT_COMMAND:+;$PROMPT_COMMAND}" ;;
esac
