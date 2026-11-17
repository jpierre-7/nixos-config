# claude-prompt: opens the prompt pane (config/nvim/lua/config/prompt.lua) zoomed over
# the active herdr pane, moving Claude's unsent prompt into it. Run by herdr's prefix+i.
# Ported from github.com/HefKer/dots (scripts/claude-prompt).
pane="$HERDR_ACTIVE_PANE_ID"
marker="${XDG_RUNTIME_DIR:-/tmp}/claude-prompt-capture"
draft=$(mktemp --suffix=.md)

# Ctrl+G runs Claude's $VISUAL, claude-prompt-editor (config/claude/settings.json env),
# which sees the marker and moves the input into $draft.
# shortcut: no check that this Claude has that VISUAL (settings env isn't in
# /proc/<pid>/environ), so a Claude started before it was set opens nvim in its own
# pane instead; restart such a Claude.
echo "$draft" >"$marker"
herdr pane send-keys "$pane" ctrl+g >/dev/null
# Claude ignores Ctrl+G behind a dialog, so don't wait for it, and don't leave the
# marker to swallow the next real Ctrl+G.
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -e "$marker" ] || break
  sleep 0.1
done
rm -f "$marker"

new=$(herdr pane split "$pane" --direction right --ratio 0.4 --focus | jq -r .result.pane.pane_id)
herdr pane zoom "$new" --on >/dev/null
herdr pane rename "$new" prompt >/dev/null
herdr pane run "$new" "exec nvim $draft -c 'lua require(\"config.prompt\").open()'" >/dev/null
