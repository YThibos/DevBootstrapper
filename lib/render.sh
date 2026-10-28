# shellcheck shell=bash
# Template rendering for machine-local configuration files.
#
# Template syntax, one directive per line:
#   @@if VAR        keep the following lines only when $VAR is non-empty
#   @@endif         end of the block (blocks do not nest)
#   {{VAR}}         replaced by the value of $VAR (XML-escaped for .xml targets)
# Lines starting with "##" are template comments and are dropped.

# render_template TEMPLATE TARGET - writes TARGET only when its content changes.
# Prints "changed" or "unchanged".
render_template() {
  local template=$1 target=$2 xml=0 tmp
  case $target in *.xml) xml=1 ;; esac
  tmp=$(mktemp)
  awk -v xml="$xml" '
    function esc(s) {
      if (xml == 1) { gsub(/&/, "\\&amp;", s); gsub(/</, "\\&lt;", s); gsub(/>/, "\\&gt;", s) }
      return s
    }
    /^##/ { next }
    /^@@if / { keep = (ENVIRON[$2] != ""); inblock = 1; next }
    /^@@endif/ { inblock = 0; keep = 1; next }
    {
      if (inblock && !keep) next
      line = $0
      while (match(line, /\{\{[A-Za-z_][A-Za-z0-9_]*\}\}/)) {
        name = substr(line, RSTART + 2, RLENGTH - 4)
        line = substr(line, 1, RSTART - 1) esc(ENVIRON[name]) substr(line, RSTART + RLENGTH)
      }
      print line
    }
    BEGIN { keep = 1; inblock = 0 }
  ' "$template" >"$tmp"
  mkdir -p "$(dirname "$target")"
  if [ -f "$target" ] && cmp -s "$tmp" "$target"; then
    rm -f "$tmp"
    echo unchanged
  else
    cat "$tmp" >"$target"
    rm -f "$tmp"
    echo changed
  fi
}
