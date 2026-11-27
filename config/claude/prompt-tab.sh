# claude-prompt-tab --resume ID CWD [DRAFT]: a new tab in CWD, with Claude resuming
# session ID and the prompt pane (claude-prompt) already open over it, DRAFT's text in
# the prompt. The tab goes to the herdr space named for CWD's repo or worktree, made if
# missing; outside any repo, to the catch-all space misc. Run by the prompt pane's sessions picker
# (config/nvim/lua/config/prompt_stash.lua). If no Claude shows up, the tab is left on
# Claude's pane with a notification. Ported from github.com/HefKer/dots
# (scripts/claude-prompt-tab).
fail() {
  herdr notification show "New Claude tab" --body "$1" >/dev/null
  exit 1
}

[ "${1:-}" = --resume ] && [ $# -ge 3 ] || fail "Usage: claude-prompt-tab --resume ID CWD [DRAFT]"
session=$2 cwd=$3 draft=${4:-}

# A repo's own checkout is named for the repo (nixos-config); a linked worktree adds its
# directory (nixos-config/feature), so two repos' main worktrees stay apart. Repo is the
# directory holding .git, or .bare for a bare repo with its worktrees beside it.
space=misc
if top=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null); then
  common=$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir)
  case $common in */.git | */.bare) repo=${common%/*} ;; *) repo=${common%.git} ;; esac
  space=${repo##*/}
  [ "$top" = "$repo" ] || space=$space/${top##*/}
fi
# By label, as a space's directory isn't recorded and its tabs may have moved since.
space_id=$(herdr workspace list | jq -r --arg l "$space" \
  'first(.result.workspaces[] | select(.label == $l) | .workspace_id) // empty')
# A new space's first tab is the one Claude goes in.
pane=$(if [ -n "$space_id" ]; then
  herdr tab create --workspace "$space_id" --cwd "$cwd" --focus
else
  herdr workspace create --label "$space" --cwd "$cwd" --focus
fi | jq -r '.result.root_pane.pane_id // empty')
[ -n "$pane" ] || fail "Couldn't create the tab in space $space"
herdr pane run "$pane" "claude --resume $session" >/dev/null

i=0
until [ "$(herdr pane get "$pane" | jq -r .result.pane.agent)" = claude ]; do
  i=$((i + 1))
  [ "$i" -le 50 ] || fail "Claude didn't start within 10s"
  sleep 0.2
done

exec claude-prompt --fresh "$pane" ${draft:+"$draft"}
