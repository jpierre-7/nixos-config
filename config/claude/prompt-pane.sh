# claude-prompt: opens the prompt pane (config/nvim/lua/config/prompt.lua) above the
# active herdr pane, moving Claude's unsent prompt into it. Run by herdr's prefix+i.
# With --fresh PANE [DRAFT], by claude-prompt-tab (prompt-tab.sh), over a Claude just
# started, which has no prompt to move; DRAFT's text goes in the prompt instead.
# Ported from github.com/HefKer/dots (scripts/claude-prompt).
pane="${HERDR_ACTIVE_PANE_ID:-}"
fresh=""
if [ "${1:-}" = --fresh ]; then
  pane=$2 fresh=1
fi
marker="${XDG_RUNTIME_DIR:-/tmp}/claude-prompt-capture"
draft=$(mktemp --suffix=.md)
if [ -n "$fresh" ] && [ -f "${3:-}" ]; then
  mv -f "$3" "$draft"
fi

# Ctrl+G runs Claude's $VISUAL, claude-prompt-editor (config/claude/settings.json env),
# which sees the marker and moves the input into $draft.
# shortcut: no check that this Claude has that VISUAL (settings env isn't in
# /proc/<pid>/environ), so a Claude started before it was set opens nvim in its own
# pane instead; restart such a Claude.
if [ -z "$fresh" ]; then
  echo "$draft" >"$marker"
  herdr pane send-keys "$pane" ctrl+g >/dev/null
  # Claude ignores Ctrl+G behind a dialog, so don't wait for it, and don't leave the
  # marker to swallow the next real Ctrl+G.
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ -e "$marker" ] || break
    sleep 0.1
  done
  rm -f "$marker"
fi

# Claude shrinks to a strip at the bottom, enough for the bands its plugins draw under
# the chat (cost, tokens, cache) and its input; Claude drops them below 22 rows. Not
# zoom, which would cover the agent cards pane. herdr splits only right or down, and
# --ratio is the top pane's share, so the split leaves Claude on top and the swap
# moves it down, keeping the sizes.
strip=22
rows=$(herdr pane get "$pane" | jq -r '.result.pane.scroll.viewport_rows // 0')
ratio=$(awk -v r="$rows" -v s="$strip" 'BEGIN { x = r > 0 ? (r - s) / r : 0; print (x < 0.5 ? 0.5 : x) }')
new=$(herdr pane split "$pane" --direction down --ratio "$ratio" --focus | jq -r .result.pane.pane_id)
herdr pane swap --pane "$new" --direction up >/dev/null
herdr pane rename "$new" prompt >/dev/null
herdr pane run "$new" "exec nvim $draft -c 'lua require(\"config.prompt\").open()'" >/dev/null
