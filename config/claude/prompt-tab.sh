# claude-prompt-tab --resume ID CWD [DRAFT]: a new tab in the focused pane's workspace,
# in CWD, with Claude resuming session ID and the prompt pane (claude-prompt) already
# open over it, DRAFT's text in the prompt. Run by the prompt pane's sessions picker
# (config/nvim/lua/config/prompt_stash.lua). If no Claude shows up, the tab is left on
# Claude's pane with a notification. Ported from github.com/HefKer/dots
# (scripts/claude-prompt-tab).
fail() {
  herdr notification show "New Claude tab" --body "$1" >/dev/null
  exit 1
}

[ "${1:-}" = --resume ] && [ $# -ge 3 ] || fail "Usage: claude-prompt-tab --resume ID CWD [DRAFT]"
session=$2 cwd=$3 draft=${4:-}

info=$(herdr pane get "${HERDR_ACTIVE_PANE_ID:-}" | jq -c .result.pane)
[ -n "$info" ] || fail "Can't read the focused pane"
ws=$(printf '%s' "$info" | jq -r .workspace_id)

pane=$(herdr tab create --workspace "$ws" --cwd "$cwd" --focus | jq -r '.result.root_pane.pane_id // empty')
[ -n "$pane" ] || fail "Couldn't create the tab"
herdr pane run "$pane" "claude --resume $session" >/dev/null

i=0
until [ "$(herdr pane get "$pane" | jq -r .result.pane.agent)" = claude ]; do
  i=$((i + 1))
  [ "$i" -le 50 ] || fail "Claude didn't start within 10s"
  sleep 0.2
done

exec claude-prompt --fresh "$pane" ${draft:+"$draft"}
