# Files an idea as an issue in a project's GitHub tracker, queueing it locally when filing fails.
# Adapted from HefKer/nixos-config's backlog: the picker is Vicinae, the project list is an agenix
# secret this script decrypts itself, and issues follow the planning tracker's ticket layout.

self=$(readlink -f "$0")
# The project list names a private tracker, and this repo is public, so it is kept encrypted in
# secrets/ (SECURITY.md). BACKLOG_CONFIG, a plain YAML file, replaces it (the tests use it).
secret=${BACKLOG_SECRET:-$backlog_secret}
identity=${BACKLOG_IDENTITY:-$HOME/.ssh/id_ed25519}
state=${XDG_STATE_HOME:-$HOME/.local/state}/backlog
queue=$state/queue.jsonl
images=$state/images
recent=$state/recent
visibility=$state/visibility
drafts=$state/drafts
# A queued line failing this many times for a reason other than the network raises one notification.
max_fails=3
# How long a repo's private/public answer is trusted before gh is asked again.
visibility_ttl=86400
notify=0
config_yaml=""

usage() {
  cat <<'EOF'
backlog add [--image FILE] [PROJECT] "TITLE // BODY"
                                        file an idea; " //" splits title from body (a URL's :// doesn't);
                                        stdin, if not a terminal, is appended to the body; --image embeds FILE,
                                        uploaded to the config's attachments_repo
backlog prompt [PROJECT]                pick a project in Vicinae (or take PROJECT), type a line in fuzzel,
                                        file it in the background; Shift+Enter attaches the clipboard's image;
                                        Esc keeps the text as the project's draft, reopened next time;
                                        Ctrl+G discards it
backlog flush [--notify]                re-send the offline queue
backlog queue                           list what is queued
backlog setup                           create the configured labels in every configured repo, and the
                                        attachments_repo (private) if missing
backlog projects                        list the configured projects, best guess first
backlog config                          print the decrypted project list (edit: agenix -e backlog-projects.age)
EOF
}

die() {
  echo "backlog: $*" >&2
  exit 1
}

# Where the project list comes from, for messages.
config_name() {
  if [ -n "${BACKLOG_CONFIG:-}" ]; then echo "$BACKLOG_CONFIG"; else echo "$secret"; fi
}

# Reads the project list once per run, in the main shell, so every later subshell sees it.
load_config() {
  if [ -n "${BACKLOG_CONFIG:-}" ]; then
    [ -f "$BACKLOG_CONFIG" ] || die "no config at $BACKLOG_CONFIG"
    config_yaml=$(<"$BACKLOG_CONFIG")
    return 0
  fi
  [ -f "$secret" ] || die "no project list at $secret (SECURITY.md: add a secret)"
  [ -r "$identity" ] || die "can't read $identity to decrypt $secret"
  config_yaml=$(age -d -i "$identity" "$secret") || die "can't decrypt $secret with $identity"
}

# The config as JSON, with each project's defaults filled in.
projects_json() {
  yq -o=json '.' <<<"$config_yaml" | jq -c '[(.projects // [])[] | {
    name, repo,
    match: ([.name] + (.match // []) | map(ascii_downcase)),
    labels: (.labels // ["capture"]),
    public_ok: (.public_ok // false)
  }]'
}

# The private repo images are uploaded to, or nothing.
attachments_repo() {
  yq -r '.attachments_repo // ""' <<<"$config_yaml"
}

# prefix_labels: a title starting with a key (e.g. "Fix:") also gets that label (e.g. type:bug).
prefix_labels() {
  yq -o=json '.prefix_labels // {}' <<<"$config_yaml" | jq -c .
}

project() {
  projects_json | jq -ce --arg n "$1" '.[] | select(.name == $n)' || die "no project '$1' (see: backlog projects)"
}

# Names of the projects whose match words appear in $1, in config order.
guess() {
  projects_json | jq -r --arg h "${1,,}" '.[] | select(any(.match[]; . as $w | $h | contains($w))) | .name'
}

# Every project name once: the guesses for $1, then the most recently used, then the rest.
ordered() {
  {
    guess "$1"
    [ -f "$recent" ] && cat "$recent"
    projects_json | jq -r '.[].name'
  } | awk 'NF && !seen[$0]++' | grep -Fxf <(projects_json | jq -r '.[].name')
}

remember() {
  mkdir -p "$state"
  { echo "$1"; [ -f "$recent" ] && grep -Fxv -- "$1" "$recent"; } | head -n 20 >"$recent.tmp" || true
  mv -f "$recent.tmp" "$recent"
}

# A project's draft file; % and / are escaped so any name is one file.
draft_file() {
  local n=${1//%/%25}
  echo "$drafts/${n//\//%2F}"
}

# A blank $2 clears project $1's draft rather than saving it.
save_draft() {
  local f
  if [ -z "$(trim "$2")" ]; then
    clear_draft "$1"
    return 0
  fi
  f=$(draft_file "$1")
  mkdir -p "$drafts"
  printf '%s' "$2" >"$f.tmp"
  mv -f "$f.tmp" "$f"
}

clear_draft() {
  rm -f "$(draft_file "$1")"
}

has_draft() {
  [ -s "$(draft_file "$1")" ]
}

read_draft() {
  printf '%s' "$(<"$(draft_file "$1")")"
}

focused_window() {
  niri msg -j focused-window 2>/dev/null | jq -r '"\(.title // "") \(.app_id // "")"' 2>/dev/null || true
}

# Splits $1 at the first " //" followed by a space or the end, so a URL's "://" stays in the title.
split_line() {
  local s=$1 pre=""
  title=$1 body=""
  while [[ $s == *" //"* ]]; do
    pre+=${s%%" //"*}
    s=${s#*" //"}
    if [[ -z $s || $s == [[:space:]]* ]]; then
      title=$pre body=$s
      break
    fi
    pre+=" //"
  done
  title=$(trim "$title")
  body=$(trim "$body")
}

trim() {
  local s=$1
  s=${s#"${s%%[![:space:]]*}"}
  printf '%s\n' "${s%"${s##*[![:space:]]}"}"
}

# The planning tracker's ticket layout. What holds the idea (the title when there is no body) and
# its image; Notes and Done when are left for triage.
ticket_body() {
  local title=$1 body=$2 image=$3 what
  what=${body:-$title}
  [ -z "$image" ] || what+=$'\n\n'"$image"
  printf '## What\n%s\n\n## Notes\n\n## Done when\n' "$what"
}

# gh's message for a failure that retrying with a network would fix.
is_network() {
  grep -qiE 'error connecting|dial tcp|connection refused|no such host|i/o timeout|TLS handshake|network is unreachable|temporary failure in name resolution|context deadline exceeded|could not resolve host' <<<"$1"
}

note() {
  [ "$notify" = 1 ] || return 0
  notify-send -a backlog "$@" || true
}

# Low urgency, with an action that opens the issue; waits for the action, so callers background it.
note_filed() {
  local repo=$1 url=$2
  echo "$url"
  [ "$notify" = 1 ] || return 0
  [ "$(notify-send -a backlog -u low -A open="Open" "$repo#${url##*/} filed" 2>/dev/null)" = open ] &&
    qutebrowser "$url" >/dev/null 2>&1
  return 0
}

# Prints true or false for whether $1 is private, from the cache when fresh; fails with gh's error.
is_private() {
  local repo=$1 now line answer at
  now=$(date +%s)
  mkdir -p "$state"
  if [ -f "$visibility" ] && line=$(awk -F'\t' -v r="$repo" '$1 == r' "$visibility" | tail -n 1) && [ -n "$line" ]; then
    IFS=$'\t' read -r _ answer at <<<"$line"
    if ((now - at < visibility_ttl)); then
      echo "$answer"
      return 0
    fi
  fi
  if ! answer=$(gh api "repos/$repo" --jq .private 2>"$state/gh.err"); then
    cat "$state/gh.err"
    return 1
  fi
  { [ -f "$visibility" ] && awk -F'\t' -v r="$repo" '$1 != r' "$visibility"; printf '%s\t%s\t%s\n' "$repo" "$answer" "$now"; } >"$visibility.tmp" || true
  mv -f "$visibility.tmp" "$visibility"
  echo "$answer"
}

# The extension an image is stored under, from its name.
ext_of() {
  local base=${1##*/} ext=png
  [[ $base == *.* ]] && ext=${base##*.}
  echo "${ext,,}"
}

# Commits $1 to the attachments repo at its content hash, so a retry reuses it; prints the embed URL or the failure.
upload() {
  local file=$1 repo private path out url
  repo=$(attachments_repo)
  if [ -z "$repo" ]; then
    echo "no attachments_repo in $(config_name)"
    return 1
  fi
  if [ ! -f "$file" ]; then
    echo "the image $file is gone"
    return 1
  fi
  private=$(is_private "$repo") || {
    echo "$private"
    return 1
  }
  if [ "$private" != true ]; then
    echo "$repo is public; attachments_repo must be private"
    return 1
  fi
  path=$(date -u +%Y-%m-%d)/$(sha256sum "$file" | cut -c1-16).$(ext_of "$file")
  if out=$(base64 -w0 "$file" | jq -Rsc --arg m "backlog: $path" '{message: $m, content: .}' |
    gh api "repos/$repo/contents/$path" -X PUT --input - --jq .content.html_url 2>&1); then
    echo "$out?raw=true"
    return 0
  fi
  if url=$(gh api "repos/$repo/contents/$path" --jq .html_url 2>/dev/null); then
    echo "$url?raw=true"
    return 0
  fi
  echo "$out"
  return 1
}

# Files one issue, image $6 embedded. Exit 0 filed (URL on stdout), 2 refused as public, 3 network, 4 other (message).
send() {
  local repo=$1 title=$2 body=$3 labels=$4 public_ok=$5 image=${6:-} private out url embed=""
  if ! private=$(is_private "$repo"); then
    echo "$private"
    is_network "$private" && return 3
    return 4
  fi
  if [ "$private" != true ] && [ "$public_ok" != true ]; then
    echo "$repo is public; set public_ok: true in $(config_name) to allow it"
    return 2
  fi
  if [ -n "$image" ]; then
    if ! url=$(upload "$image"); then
      echo "$url"
      is_network "$url" && return 3
      return 4
    fi
    embed="![image]($url)"
  fi
  local -a args=(issue create --repo "$repo" --title "$title" --body "$(ticket_body "$title" "$body" "$embed")")
  while read -r l; do args+=(--label "$l"); done < <(jq -r '.[]' <<<"$labels")
  if out=$(gh "${args[@]}" 2>&1); then
    tail -n 1 <<<"$out"
    return 0
  fi
  echo "$out"
  is_network "$out" && return 3
  return 4
}

# Queues one idea; image $7, if given, is copied into the state dir, since the original may not outlive the queue.
enqueue() {
  local copy=""
  mkdir -p "$state"
  if [ -n "${7:-}" ]; then
    mkdir -p "$images"
    copy=$(mktemp --suffix=".$(ext_of "$7")" "$images/XXXXXXXX")
    cp -f "$7" "$copy"
  fi
  jq -nc --arg repo "$1" --arg title "$2" --arg body "$3" --argjson labels "$4" --argjson public_ok "$5" --argjson fails "$6" \
    --arg image "$copy" \
    '{repo: $repo, title: $title, body: $body, labels: $labels, public_ok: $public_ok, at: (now | todate), fails: $fails}
      + (if $image == "" then {} else {image: $image} end)' >>"$queue"
}

lock() {
  mkdir -p "$state"
  exec 9>"$state/lock"
  flock -w 120 9 || die "another backlog run holds $state/lock"
}

flush_locked() {
  local line repo title body labels public_ok image fails out rc offline=0 pending=()
  [ -s "$queue" ] || return 0
  while IFS= read -r -u 3 line; do
    [ -n "$line" ] || continue
    if [ "$offline" = 1 ]; then
      pending+=("$line")
      continue
    fi
    repo=$(jq -r .repo <<<"$line")
    title=$(jq -r .title <<<"$line")
    body=$(jq -r .body <<<"$line")
    labels=$(jq -c .labels <<<"$line")
    public_ok=$(jq -r '.public_ok // false' <<<"$line")
    image=$(jq -r '.image // ""' <<<"$line")
    rc=0
    out=$(send "$repo" "$title" "$body" "$labels" "$public_ok" "$image") || rc=$?
    case $rc in
      0)
        [ -z "$image" ] || rm -f "$image"
        note_filed "$repo" "$out" 9>&- &
        ;;
      2)
        [ -z "$image" ] || rm -f "$image"
        echo "backlog: dropped '$title': $out" >&2
        note -u critical "backlog: dropped from queue" "$title — $out"
        ;;
      3)
        offline=1
        pending+=("$line")
        ;;
      *)
        fails=$(($(jq -r '.fails // 0' <<<"$line") + 1))
        echo "backlog: '$title' failed ($fails): $out" >&2
        line=$(jq -c --argjson f "$fails" '.fails = $f' <<<"$line")
        # Raised by the first notifying run at or past the limit, so a quiet CLI flush can't use it up.
        if ((fails >= max_fails)) && [ "$notify" = 1 ] && [ "$(jq -r '.notified // false' <<<"$line")" != true ]; then
          note -u critical "backlog: '$title' failed $fails times" "$repo: $out"
          line=$(jq -c '.notified = true' <<<"$line")
        fi
        pending+=("$line")
        ;;
    esac
  done 3<"$queue"
  if [ ${#pending[@]} -gt 0 ]; then printf '%s\n' "${pending[@]}"; fi >"$queue.tmp"
  mv -f "$queue.tmp" "$queue"
  [ -s "$queue" ] || rm -f "$queue"
}

cmd_flush() {
  [ "${1:-}" = --notify ] && notify=1
  [ -s "$queue" ] || return 0
  load_config
  lock
  flush_locked
}

cmd_add() {
  local p name repo labels public_ok out rc=0 extra="" image="" from_box=0
  while :; do
    case ${1:-} in
      --notify) notify=1 && shift ;;
      --from-box) from_box=1 && shift ;;
      --image)
        [ $# -ge 2 ] || die "usage: backlog add [--image FILE] [PROJECT] \"TITLE // BODY\""
        image=$2 && shift 2
        ;;
      *) break ;;
    esac
  done
  # The box cleared its draft on Enter, so a line exiting unfiled and unqueued goes back, unless a newer draft was typed meanwhile.
  if [ "$from_box" = 1 ] && [ $# = 2 ]; then
    box_name=$1 box_line=$2
    trap 'has_draft "$box_name" || save_draft "$box_name" "$box_line"' EXIT
  fi
  load_config
  if [ -n "$image" ]; then
    [ -f "$image" ] && [ -r "$image" ] || die "no readable image at $image"
    [ -n "$(attachments_repo)" ] || die "--image needs attachments_repo: OWNER/NAME in $(config_name)"
  fi
  case $# in
    1)
      name=$(ordered "$PWD" | head -n 1)
      [ -n "$(guess "$PWD")" ] || echo "backlog: nothing matches $PWD; using the most recent project, $name" >&2
      ;;
    2) name=$1 && shift ;;
    *) die "usage: backlog add [--image FILE] [PROJECT] \"TITLE // BODY\"" ;;
  esac
  [ -n "$name" ] || die "no projects in $(config_name)"
  p=$(project "$name")
  split_line "$1"
  [ -t 0 ] || extra=$(cat)
  if [ -n "$extra" ]; then body=${body:+$body$'\n\n'}$extra; fi
  [ -n "$title" ] || die "empty title"
  repo=$(jq -r .repo <<<"$p")
  # The project's labels, plus the label of the title's prefix (case-insensitive), once each.
  labels=$(jq -c --arg t "${title,,}" --argjson pl "$(prefix_labels)" \
    '(.labels + [$pl | to_entries[] | select(.key | ascii_downcase as $k | $t | startswith($k)) | .value]) | unique' <<<"$p")
  public_ok=$(jq -r .public_ok <<<"$p")
  lock
  remember "$name"
  flush_locked
  out=$(send "$repo" "$title" "$body" "$labels" "$public_ok" "$image") || rc=$?
  case $rc in
    3) enqueue "$repo" "$title" "$body" "$labels" "$public_ok" 0 "$image" ;;
    4) enqueue "$repo" "$title" "$body" "$labels" "$public_ok" 1 "$image" ;;
  esac
  case $rc in 0 | 3 | 4) trap - EXIT ;; esac
  # Released before any notification waits on its action, so the next capture needn't wait for it.
  exec 9>&-
  case $rc in
    0) note_filed "$repo" "$out" ;;
    2)
      note -u critical "backlog: refused" "$out"
      die "refused: $out"
      ;;
    3)
      note -u normal "backlog: queued (offline)" "$title"
      echo "backlog: queued (offline): $title" >&2
      ;;
    *)
      note -u critical "backlog: queued after an error" "$repo: $out"
      echo "backlog: queued after an error: $out" >&2
      wait
      exit 1
      ;;
  esac
  wait
}

# Saves the clipboard's image (PNG when offered) to a new file in the state dir and prints its path; fails without one.
clipboard_image() {
  local types type file sub
  types=$(wl-paste --list-types 2>/dev/null) || return 1
  type=$(grep -x 'image/png' <<<"$types") || type=$(grep '^image/' <<<"$types" | head -n 1) || return 1
  [ -n "$type" ] || return 1
  sub=${type#image/}
  mkdir -p "$state"
  file=$(mktemp --suffix=".${sub%%+*}" "$state/clip.XXXXXXXX") || return 1
  if ! wl-paste --no-newline --type "$type" >"$file" || [ ! -s "$file" ]; then
    rm -f "$file"
    return 1
  fi
  echo "$file"
}

# The box's fuzzel config: its keys, then Noctalia's colors (modules/home/noctalia.nix) once rendered.
# Rewritten each run: fuzzel 1.14 has no --override, and fails on an include whose file is missing.
fuzzel_config() {
  local theme=${XDG_CONFIG_HOME:-$HOME/.config}/fuzzel/themes/noctalia
  mkdir -p "$state"
  {
    printf '[key-bindings]\ncancel=none\nexecute-input=none\n'
    printf 'custom-1=Shift+Return Shift+KP_Enter\ncustom-2=Escape Control+bracketleft\ncustom-3=Control+g\n'
    [ -r "$theme" ] && cat "$theme"
  } >"$state/fuzzel.ini.tmp" || true
  mv -f "$state/fuzzel.ini.tmp" "$state/fuzzel.ini"
}

cmd_prompt() {
  local name pick line rc image="" problem n mark=" ✎"
  local -a refill=() names=() shown=() rest=()
  load_config
  if [ $# -gt 0 ]; then
    name=$1
    if ! projects_json | jq -e --arg n "$name" 'any(.[]; .name == $n)' >/dev/null; then
      notify-send -a backlog "backlog: no project $name" "it is no longer in $(config_name)" || true
      exit 0
    fi
  else
    # Projects with a draft first, marked. Vicinae prints the picked row, so the mark is stripped
    # and the rest checked against the list: typed text matching no row prints nothing.
    while IFS= read -r n; do
      if has_draft "$n"; then
        names+=("$n") shown+=("$n$mark")
      else
        rest+=("$n")
      fi
    done < <(ordered "$(focused_window)")
    names+=("${rest[@]}") shown+=("${rest[@]}")
    [ ${#names[@]} -gt 0 ] || die "no projects in $(config_name)"
    pick=$(printf '%s\n' "${shown[@]}" |
      vicinae dmenu --no-quick-look --no-footer -n "backlog" -p "project") || exit 0
    name=${pick%"$mark"}
    printf '%s\n' "${names[@]}" | grep -Fxq -- "$name" || exit 0
  fi
  if has_draft "$name"; then refill=(--search "$(read_draft "$name")"); fi
  fuzzel_config
  # Vicinae's dmenu returns only a picked row, never typed text, so the line itself is typed in fuzzel.
  # Shift+Enter (custom-1, exit 10) attaches the clipboard's image, else reopens the box; Esc (custom-2, exit 11) keeps a draft; Ctrl+G (custom-3, exit 12) drops it.
  while :; do
    rc=0
    line=$(fuzzel --config "$state/fuzzel.ini" --dmenu --prompt-only "$name> " \
      --placeholder "Fix: short title // details  ·  Add: / Change:  ·  Shift+Enter: +image" \
      --width 80 "${refill[@]}" --no-exit-on-keyboard-focus-loss </dev/null) || rc=$?
    case $rc in
      0 | 10) ;;
      11) save_draft "$name" "$line"; exit 0 ;;
      12) clear_draft "$name"; exit 0 ;;
      # A right-click still cancels, printing nothing: the draft stays as it was.
      *) exit 0 ;;
    esac
    if [ -z "$(trim "$line")" ]; then
      clear_draft "$name"
      exit 0
    fi
    [ "$rc" = 10 ] || break
    if [ -z "$(attachments_repo)" ]; then
      problem="set attachments_repo: OWNER/NAME in $(config_name)"
    elif image=$(clipboard_image); then
      break
    else
      problem="no image on the clipboard"
    fi
    notify-send -a backlog "backlog: can't attach an image" "$problem" || true
    refill=(--search "$line")
  done
  # Filed or queued, the line needs no draft; add restores it if the repo refuses it.
  clear_draft "$name"
  if [ -n "$image" ]; then
    # shellcheck disable=SC2016 # expanded by the inner shell, which removes the clipboard's copy once add is done
    setsid -f "$BASH" -c '"$0" add --notify --from-box --image "$1" "$2" "$3"; rm -f "$1"' "$self" "$image" "$name" "$line" \
      </dev/null >/dev/null 2>&1
  else
    setsid -f "$self" add --notify --from-box "$name" "$line" </dev/null >/dev/null 2>&1
  fi
}

cmd_queue() {
  [ -s "$queue" ] || {
    echo "queue empty"
    return 0
  }
  jq -r '"\(.at)  \(.repo)  \(.title)\(if (.fails // 0) > 0 then "  (failed \(.fails)x)" else "" end)"' "$queue"
}

# Labels gh doesn't know get these; any other label gets a plain grey.
label_spec() {
  case $1 in
    capture) echo "C2E0C6|Raw idea from backlog quick capture, not yet triaged" ;;
    *) echo "EDEDED|" ;;
  esac
}

cmd_setup() {
  local repo labels label have spec out
  load_config
  while IFS=$'\t' read -r repo labels; do
    have=$(gh label list --repo "$repo" --limit 500 --json name --jq '.[].name') || die "can't list labels in $repo"
    while read -r label; do
      if grep -Fxq -- "$label" <<<"$have"; then
        echo "$repo: $label exists"
        continue
      fi
      spec=$(label_spec "$label")
      gh label create "$label" --repo "$repo" --color "${spec%%|*}" --description "${spec#*|}" >/dev/null
      echo "$repo: $label created"
    done < <(jq -r '.[]' <<<"$labels")
  done < <(projects_json | jq -r --argjson pl "$(prefix_labels)" \
    'group_by(.repo)[] | [.[0].repo, (map(.labels[]) + [$pl[]] | unique | tojson)] | @tsv')
  repo=$(attachments_repo)
  if [ -n "$repo" ]; then
    if out=$(gh api "repos/$repo" --jq .private 2>&1); then
      [ "$out" = true ] || die "$repo is public; attachments_repo must be private"
      echo "$repo: exists"
    elif [[ $out == *"Not Found"* ]]; then
      gh repo create "$repo" --private --description "Images embedded in backlog issues" >/dev/null
      echo "$repo: created (private)"
    else
      die "can't check $repo: $out"
    fi
  fi
}

case ${1:-} in
  add) shift && cmd_add "$@" ;;
  prompt) shift && cmd_prompt "$@" ;;
  flush) shift && cmd_flush "$@" ;;
  queue) cmd_queue ;;
  setup) cmd_setup ;;
  projects) load_config && ordered "$PWD" ;;
  config) load_config && printf '%s\n' "$config_yaml" ;;
  -h | --help | help) usage ;;
  *) usage >&2 && exit 1 ;;
esac
