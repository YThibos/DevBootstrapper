# Key bindings for the emacs keymap, and for Ctrl+arrow, Ctrl+Home and Ctrl+End.
#
# Terminals (WezTerm, and tmux) send these keys as xterm-style CSI sequences such as ESC[1;5D
# for Ctrl+Left. Zsh has no binding for them, so the line editor gives up halfway through the
# sequence and types the leftover ";5D". Binding the sequences gives the expected navigation.
#: Ctrl+Left / Ctrl+Right | jump a whitespace-delimited word, so --flag=value is one word
#: Ctrl+Home / Ctrl+End | start / end of the whole input, also when it spans lines
#: Ctrl+Up / Ctrl+Down | previous / next line of the input, otherwise history

bindkey -e

# Ctrl+Left and Ctrl+Right jump over "--flag=value" or "path/to/file" in one go. The word style
# is set for these two widgets only; Ctrl+W, Alt+B and friends keep zsh's default word rules.
autoload -Uz backward-word-match forward-word-match
zle -N backward-whitespace-word backward-word-match
zle -N forward-whitespace-word forward-word-match
zstyle ':zle:backward-whitespace-word' word-style whitespace
zstyle ':zle:forward-whitespace-word' word-style whitespace

# beginning-of-line and end-of-line stop at the current line of a multi-line buffer.
__devboot_beginning_of_buffer() { CURSOR=0 }
__devboot_end_of_buffer() { CURSOR=${#BUFFER} }
zle -N beginning-of-buffer __devboot_beginning_of_buffer
zle -N end-of-buffer __devboot_end_of_buffer

# Also bound in the vi insert keymap, for a vi mode picked in zsh/local.zsh (bindkey -e above
# overrides one picked earlier in ~/.zshrc).
() {
  local keymap
  for keymap in emacs viins; do
    bindkey -M "$keymap" '^[[1;5D' backward-whitespace-word
    bindkey -M "$keymap" '^[[1;5C' forward-whitespace-word
    bindkey -M "$keymap" '^[[1;5H' beginning-of-buffer
    bindkey -M "$keymap" '^[[1;5F' end-of-buffer
    bindkey -M "$keymap" '^[[1;5A' up-line-or-history
    bindkey -M "$keymap" '^[[1;5B' down-line-or-history
  done
}
