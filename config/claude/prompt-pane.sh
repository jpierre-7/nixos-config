# claude-prompt: opens the prompt pane (config/nvim/lua/config/prompt.lua) beside the
# active herdr pane, moving Claude's unsent prompt into it. Run by herdr's prefix+i.
# Once the tab has a prompt pane, prefix+i jumps between it and the tab's Claude.
# With --fresh PANE [DRAFT], by claude-prompt-tab (prompt-tab.sh), over a Claude just
# started, which has no prompt to move; DRAFT's text goes in the prompt instead.
# Ported from github.com/HefKer/dots (scripts/claude-prompt).
pane="${HERDR_ACTIVE_PANE_ID:-}"
fresh=""
if [ "${1:-}" = --fresh ]; then
  pane=$2 fresh=1
fi
# Focused by id through herdr's socket: the CLI focuses only by direction.
if [ -z "$fresh" ]; then
  panes=$(herdr pane list | jq -c --arg p "$pane" '.result.panes as $all
    | [$all[] | select(.tab_id == ($all[] | select(.pane_id == $p) | .tab_id))]')
  prompt=$(jq -r 'map(select(.label == "prompt"))[0].pane_id // empty' <<<"$panes")
  if [ -n "$prompt" ]; then
    target=$prompt
    if [ "$pane" = "$prompt" ]; then
      target=$(jq -r 'map(select(.agent == "claude"))[0].pane_id // empty' <<<"$panes")
    fi
    if [ -n "$target" ]; then
      jq -nc --arg p "$target" '{id: "claude-prompt", method: "pane.focus", params: {pane_id: $p}}' |
        socat - "UNIX-CONNECT:${HERDR_SOCKET_PATH:-$HOME/.config/herdr/herdr.sock}" >/dev/null
    fi
    exit 0
  fi
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

new=$(herdr pane split "$pane" --direction right --ratio 0.6 --focus | jq -r .result.pane.pane_id)
herdr pane rename "$new" prompt >/dev/null
herdr pane run "$new" "exec nvim $draft -c 'lua require(\"config.prompt\").open()'" >/dev/null
