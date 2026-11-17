# claude-prompt-editor: Claude's $VISUAL (config/claude/settings.json env). While
# claude-prompt (prompt-pane.sh) has a capture pending, moves the prompt out instead of
# editing it: Ctrl+G is the only way to read Claude's input exactly, collapsed pastes
# included, and emptying the file is what clears the input. Otherwise a normal editor.
marker="${XDG_RUNTIME_DIR:-/tmp}/claude-prompt-capture"

if [ -e "$marker" ]; then
  cp "$1" "$(cat "$marker")"
  : >"$1"
  rm "$marker"
  exit 0
fi

exec "${EDITOR:-nvim}" "$@"
