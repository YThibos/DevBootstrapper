# Shell history: large, shared between tabs, without duplicates.
HISTFILE=~/.zsh_history
HISTSIZE=50000
SAVEHIST=100000
setopt histignorealldups sharehistory
