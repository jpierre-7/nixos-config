# claude-session-diff: show the changes one Claude Code session made, in hunk,
# in a split beside the session's herdr pane. Packaged in modules/home/claude.nix.
#
#   claude-session-diff hook          Claude Code hook (config/claude/settings.json);
#                                     reads the event JSON on stdin
#   claude-session-diff toggle        herdr prefix+d (config/herdr/config.toml)
#   claude-session-diff view <id>     what runs in the split pane
#   claude-session-diff notes [<id>]  the user's unanswered notes in that pane,
#                                     for the diff-notes skill
#
# At the session's first event the hook saves the repo's work tree as a git
# tree object (the baseline). After each tool call it records the files that
# changed: the path for Edit/Write, and a before/after tree comparison for
# Bash, which also catches sed, formatters and generators. The view diffs the
# baseline against the current state of those files only, so other sessions
# in the same repo stay out of it. User edits to the same files do show up.
#
# hunk's own `hunk diff <rev>` treats files that were untracked at the
# baseline as deleted + untracked, so the view builds the patch itself and
# runs `hunk patch --watch` on it.

state_root=${XDG_STATE_HOME:-$HOME/.local/state}/claude-session-diff

# Print a tree object of the whole work tree: tracked and untracked files,
# minus ignored ones. A throwaway index leaves the real one (and whatever is
# staged) alone; starting from a copy of it reuses its stat cache, so only
# changed files get hashed.
snapshot() {
  local repo=$1 tmp tree
  tmp=$(mktemp -d)
  cp "$(git -C "$repo" rev-parse --path-format=absolute --git-path index)" "$tmp/index" 2>/dev/null || true
  if GIT_INDEX_FILE=$tmp/index git -C "$repo" add -A &&
    tree=$(GIT_INDEX_FILE=$tmp/index git -C "$repo" write-tree); then
    rm -rf "$tmp"
    echo "$tree"
  else
    rm -rf "$tmp"
    return 1
  fi
}

# Start tracking a session. Sessions that were already running when the hooks
# were added get their baseline at their first tool call.
init() {
  local dir=$1 cwd=$2 repo base
  repo=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || return 1
  base=$(snapshot "$repo") || return 1
  mkdir -p "$dir/pre"
  echo "$repo" >"$dir/repo"
  echo "$base" >"$dir/base"
  touch "$dir/files"
  # Forget sessions that changed nothing for a month.
  find "$state_root" -mindepth 2 -maxdepth 2 -name files -mtime +30 -printf '%h\0' |
    xargs -0 -r rm -rf
}

hook() {
  local input sid dir repo tool id path pre post
  input=$(cat)
  sid=$(jq -r '.session_id // empty' <<<"$input")
  [[ -n $sid ]] || return 0
  dir=$state_root/$sid
  # resume and compact keep the session ID, and with it the first baseline.
  if [[ ! -f $dir/base ]]; then
    init "$dir" "$(jq -r .cwd <<<"$input")" || return 0
  fi
  repo=$(<"$dir/repo")
  tool=$(jq -r '.tool_name // empty' <<<"$input")
  id=$(jq -r '.tool_use_id // empty' <<<"$input")

  case $(jq -r .hook_event_name <<<"$input") in
  PreToolUse)
    [[ $tool == Bash && -n $id ]] || return 0
    snapshot "$repo" >"$dir/pre/$id" || rm -f "$dir/pre/$id"
    ;;
  PostToolUse | PostToolUseFailure)
    if [[ $tool == Bash ]]; then
      pre=$dir/pre/$id
      [[ -n $id && -s $pre ]] || return 0
      if post=$(snapshot "$repo"); then
        git -C "$repo" diff --name-only --no-renames "$(<"$pre")" "$post" >>"$dir/files"
      fi
      rm -f "$pre"
    else
      path=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$input")
      [[ -n $path ]] || return 0
      # Resolving symlinks maps the live config links (~/.config/... ->
      # this repo) to their repo paths.
      path=$(realpath -m --relative-to="$repo" "$path")
      [[ $path != .. && $path != ../* ]] && echo "$path" >>"$dir/files"
    fi
    ;;
  esac
  return 0
}

# Print the session's patch: baseline vs. now, for the files it touched.
render() {
  local dir=$1 repo base tmp cur p
  local -a paths=()
  repo=$(<"$dir/repo") || return 1
  base=$(<"$dir/base") || return 1
  # A path can be gone by now (created, then deleted); keep it only if it
  # exists on one side, or git add fails on the pathspec.
  while IFS= read -r p; do
    if [[ -e $repo/$p || -L $repo/$p ]] || git -C "$repo" cat-file -e "$base:$p" 2>/dev/null; then
      paths+=("$p")
    fi
  done < <(sort -u "$dir/files")
  ((${#paths[@]})) || return 0

  tmp=$(mktemp -d)
  # --force: a file Claude edited by name shows up even when gitignored.
  if GIT_INDEX_FILE=$tmp/index git -C "$repo" read-tree "$base" &&
    GIT_INDEX_FILE=$tmp/index git -C "$repo" add --force -A -- "${paths[@]}" &&
    cur=$(GIT_INDEX_FILE=$tmp/index git -C "$repo" write-tree); then
    rm -rf "$tmp"
    git -C "$repo" diff --no-color --no-ext-diff "$base" "$cur" -- "${paths[@]}"
  else
    rm -rf "$tmp"
    return 1
  fi
}

view() {
  local sid=$1 dir patch next
  dir=$state_root/$sid
  if [[ ! -f $dir/base ]]; then
    echo "Nothing tracked for this Claude session yet (it isn't in a git repo, or hasn't run a tool)."
    read -rsn1 -p "Press a key to close."
    return 0
  fi
  patch=$dir/session.patch
  next=$dir/session.patch.next
  render "$dir" >"$patch" || true
  # hunk --watch reloads when the file changes. Rewrite it in place, and only
  # when the patch differs, so it doesn't redraw every second.
  (
    while sleep 1; do
      if render "$dir" >"$next" && ! cmp -s "$next" "$patch"; then
        cat "$next" >"$patch"
      fi
    done
  ) &
  trap 'kill $! 2>/dev/null; rm -f "$next"' EXIT
  cd "$(<"$dir/repo")"
  # --agent-notes: the agent's replies to the user's notes show up without
  # pressing `a`.
  hunk patch --watch --agent-notes "$patch"
}

# Print the hunk session showing a Claude session's diff, and the note threads
# in it whose last message is the user's: new notes, and follow-ups to replies.
# Notes live only in the running hunk window, and anchor by line number, so
# they can drift when the file changes under them.
notes() {
  local sid=${1:-${CLAUDE_CODE_SESSION_ID:-}} hunk_id
  [[ -n $sid ]] || {
    echo "Not in a Claude Code session; pass its session ID." >&2
    return 1
  }
  # The patch path names the Claude session. For patch input hunk knows no
  # repo, so `--repo .` can't find the window.
  hunk_id=$(hunk session list --json |
    jq -r --arg p "$state_root/$sid/session.patch" \
      'first(.sessions[] | select(.sourceLabel == $p) | .sessionId) // empty')
  [[ -n $hunk_id ]] || {
    echo "No diff window is open for this session. Ask the user to press Ctrl+Space d in herdr." >&2
    return 1
  }
  hunk session comment list "$hunk_id" --type all --json |
    jq --arg id "$hunk_id" --arg repo "$(<"$state_root/$sid/repo")" '
      def root($by): if .parentId and $by[.parentId] then $by[.parentId] | root($by) else . end;
      (.comments | map({key: .noteId, value: .}) | from_entries) as $by
      | {
          hunkSession: $id,
          repo: $repo,
          threads: [
            .comments | map({root: (root($by) | .noteId), note: .}) | group_by(.root)[]
            | map(.note) | sort_by(.createdAt) | select(last.source == "user")
          ]
        }'
}

# prefix+d: open the diff of the focused pane's Claude session, or close it if
# it is already open. Pressed inside the diff pane, it closes that pane.
toggle() {
  local pane=${HERDR_ACTIVE_PANE_ID:?run from a herdr key binding} sid dir viewer new f
  sid=$(herdr pane get "$pane" |
    jq -r '.result.pane.agent_session | select(.agent == "claude") | .value // empty')

  if [[ -z $sid ]]; then
    for f in "$state_root"/*/viewer; do
      if [[ -f $f && $(<"$f") == "$pane" ]]; then
        rm -f "$f"
        herdr pane close "$pane" >/dev/null
        return 0
      fi
    done
    herdr notification show "No Claude session in this pane" --sound none >/dev/null
    return 0
  fi

  dir=$state_root/$sid
  mkdir -p "$dir"
  if [[ -f $dir/viewer ]]; then
    viewer=$(<"$dir/viewer")
    rm -f "$dir/viewer"
    if herdr pane get "$viewer" >/dev/null 2>&1; then
      herdr pane close "$viewer" >/dev/null
      return 0
    fi
  fi

  # The ratio is the Claude pane's share; the diff gets the rest.
  new=$(herdr pane split "$pane" --direction right --ratio 0.45 \
    --cwd "${HERDR_ACTIVE_PANE_CWD:-$HOME}" --focus | jq -r .result.pane.pane_id)
  echo "$new" >"$dir/viewer"
  # Typed into the new pane's shell. The leading space keeps it out of fish's
  # history, and exec makes the pane close when hunk quits.
  herdr pane run "$new" " exec claude-session-diff view $sid" >/dev/null
}

case ${1:-} in
hook) hook ;;
view) view "${2:?session ID}" ;;
toggle) toggle ;;
notes) notes "${2:-}" ;;
*)
  echo "usage: claude-session-diff hook | toggle | view <session-id> | notes [<session-id>]" >&2
  exit 2
  ;;
esac
