# claude-prompt: opens the prompt pane (config/nvim/lua/config/prompt.lua) beside the
# active herdr pane, moving Claude's unsent prompt into it. Run by herdr's prefix+i.
# Once the tab has a prompt pane, prefix+i from Claude goes to it, and from the prompt
# pane restarts its nvim over the tab's Claude, to load config changes; the draft is
# saved on exit and loaded again.
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
  if [ -n "$prompt" ] && [ "$pane" != "$prompt" ]; then
    jq -nc --arg p "$prompt" '{id: "claude-prompt", method: "pane.focus", params: {pane_id: $p}}' |
      socat - "UNIX-CONNECT:${HERDR_SOCKET_PATH:-$HOME/.config/herdr/herdr.sock}" >/dev/null
    exit 0
  fi
  if [ -n "$prompt" ]; then
    pane=$(jq -r 'map(select(.agent == "claude"))[0].pane_id // empty' <<<"$panes")
    [ -n "$pane" ] || exit 0
    # Quit over nvim's socket (--listen below) so VimLeavePre saves the draft. :qa, not
    # :qa!: the draft and reply are nofile and don't stop it, but a file edited over
    # the reply and not saved does, and the pane stays up showing why.
    nvim --server "${XDG_RUNTIME_DIR:-/tmp}/claude-prompt-${prompt//:/-}.sock" \
      --remote-send '<C-\><C-N>:qa<CR>' 2>/dev/null || true
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
      herdr pane get "$prompt" >/dev/null 2>&1 || break
      sleep 0.1
    done
    if herdr pane get "$prompt" >/dev/null 2>&1; then
      herdr notification show "Prompt pane" \
        --body "nvim didn't quit (an unsaved file?), so it wasn't restarted" >/dev/null
      exit 0
    fi
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
sock="${XDG_RUNTIME_DIR:-/tmp}/claude-prompt-${new//:/-}.sock"
rm -f "$sock" # left by a crashed nvim, it would stop --listen
herdr pane run "$new" "exec nvim --listen $sock $draft -c 'lua require(\"config.prompt\").open()'" >/dev/null
