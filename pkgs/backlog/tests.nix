# backlog's behavior against fakes of gh, notify-send, vicinae, fuzzel and wl-paste.
# Run by `nix flake check` (flake.nix). Adapted from HefKer/nixos-config's tests.
{
  age,
  callPackage,
  jq,
  openssh,
  runCommandLocal,
  writeShellScriptBin,
}:
let
  # Fake GitHub: $FAKE/offline drops the network, $FAKE/broken fails a label, $FAKE/{public,missing}/<owner>_<repo>.
  # Each issue is one JSON line in $FAKE/creates; uploads, labels and repos go to $LOG.
  fakeGh = writeShellScriptBin "gh" ''
    net() { echo "error connecting to api.github.com" >&2; exit 1; }
    case "$1 $2" in
      "api repos/"*/contents/*)
        [ -e "$FAKE/offline" ] && net
        p=''${2#repos/}
        f=$FAKE/uploads/''${p/\/contents\//\/}
        url="https://github.com/''${p%%/contents/*}/blob/main/''${p#*/contents/}"
        if [ "$3 $4" = "-X PUT" ]; then
          [ -e "$f" ] && { cat >/dev/null; echo "gh: sha wasn't supplied (HTTP 422)" >&2; exit 1; }
          mkdir -p "$(dirname "$f")"
          jq -r .content | base64 -d >"$f"
          echo "upload $p" >>"$LOG"
        else
          [ -e "$f" ] || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
        fi
        echo "$url"
        ;;
      "api "*)
        [ -e "$FAKE/offline" ] && net
        r=''${2#repos/}
        [ -e "$FAKE/missing/''${r//\//_}" ] && { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
        if [ -e "$FAKE/public/''${r//\//_}" ]; then echo false; else echo true; fi
        echo "api $r" >>"$FAKE/api-calls"
        ;;
      "issue create")
        [ -e "$FAKE/offline" ] && net
        [ -e "$FAKE/broken" ] && { echo "could not add label: 'capture' not found" >&2; exit 1; }
        shift 2
        repo="" title="" body="" labels=()
        while [ $# -gt 0 ]; do
          case $1 in
            --repo) repo=$2 ;;
            --title) title=$2 ;;
            --body) body=$2 ;;
            --label) labels+=("$2") ;;
          esac
          shift 2
        done
        jq -nc --arg r "$repo" --arg t "$title" --arg b "$body" \
          '{repo: $r, title: $t, body: $b, labels: $ARGS.positional}' --args "''${labels[@]}" >>"$FAKE/creates"
        n=$(($(cat "$FAKE/n" 2>/dev/null || echo 0) + 1))
        echo "$n" >"$FAKE/n"
        echo "Creating issue in $repo"
        echo "https://github.com/$repo/issues/$n"
        ;;
      "label list") cat "$FAKE/labels" 2>/dev/null || true ;;
      "label create") echo "label $3 $5" >>"$LOG" ;;
      "repo create") echo "repo create $3 $4" >>"$LOG" ;;
      *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
    esac
  '';

  fakeNotify = writeShellScriptBin "notify-send" ''
    echo "notify $*" >>"$FAKE/notes"
  '';

  # The picker and the box answer in turn with the next line of $FAKE/answers; $FAKE/ui-n counts them.
  next = ''
    n=$(($(cat "$FAKE/ui-n" 2>/dev/null || echo 0) + 1))
    echo "$n" >"$FAKE/ui-n"
    a=$(sed -n "''${n}p" "$FAKE/answers")
  '';

  # The picker: ESC cancels (Vicinae exits 1, printing nothing); anything else is printed as the picked row.
  fakeVicinae = writeShellScriptBin "vicinae" ''
    echo "$*" >>"$FAKE/vicinae-args"
    cat >"$FAKE/vicinae-list"
    ${next}
    case $a in
      ESC) exit 1 ;;
      *) echo "$a" ;;
    esac
  '';

  # The box: ESC and CTRLG print the refill, ESC:TEXT and SHIFT:TEXT print TEXT, RCLICK prints nothing.
  fakeFuzzel = writeShellScriptBin "fuzzel" ''
    prev="" search=""
    echo "$*" >>"$FAKE/fuzzel-args"
    for a; do
      [ "$prev" = --prompt-only ] && echo "$a" >>"$FAKE/fuzzel-prompts"
      [ "$prev" = --config ] && cp "$a" "$FAKE/fuzzel.ini"
      if [ "$prev" = --search ]; then echo "$a" >>"$FAKE/fuzzel-search" && search=$a; fi
      prev=$a
    done
    ${next}
    case $a in
      CTRLG) echo "$search" && exit 12 ;;
      RCLICK) exit 2 ;;
      ESC) echo "$search" && exit 11 ;;
      ESC:*) echo "''${a#ESC:}" && exit 11 ;;
      SHIFT:*) echo "''${a#SHIFT:}" && exit 10 ;;
      *) echo "$a" ;;
    esac
  '';

  # Noctalia: templates-apply renders the fuzzel colors, unless $FAKE/no-noctalia.
  fakeNoctalia = writeShellScriptBin "noctalia" ''
    [ -e "$FAKE/no-noctalia" ] && exit 1
    echo "$*" >>"$FAKE/noctalia-args"
    mkdir -p "$HOME/.config/fuzzel/themes"
    printf '[colors]\nbackground=112233ff\n' >"$HOME/.config/fuzzel/themes/noctalia"
  '';

  # The clipboard: $FAKE/clip-types lists its types, $FAKE/clip holds the bytes.
  fakeWlPaste = writeShellScriptBin "wl-paste" ''
    case $1 in
      --list-types) cat "$FAKE/clip-types" 2>/dev/null || true ;;
      *) echo "$*" >>"$FAKE/wl-paste-args" && cat "$FAKE/clip" ;;
    esac
  '';

  backlog = callPackage ./. {
    gh = fakeGh;
    libnotify = fakeNotify;
    fuzzel = fakeFuzzel;
    wl-clipboard = fakeWlPaste;
    secretFile = "/nonexistent/backlog-projects.age";
  };
in
runCommandLocal "backlog-tests"
  {
    nativeBuildInputs = [
      age
      backlog
      fakeNoctalia
      fakeVicinae
      jq
      openssh
    ];
  }
  ''
    export HOME=$PWD/home FAKE=$PWD/fake LOG=$PWD/log
    export BACKLOG_CONFIG=$PWD/projects.yaml
    mkdir -p "$HOME" "$FAKE/public"
    touch "$LOG" "$FAKE/creates"
    queue=$HOME/.local/state/backlog/queue.jsonl
    cat >"$BACKLOG_CONFIG" <<'EOF'
    prefix_labels:
      "Add:": type:feature
      "Fix:": type:bug
    projects:
      - name: nixos
        repo: o/nixos-issues
        match: [homelab]
      - name: dots
        repo: o/dots-issues
      - name: open
        repo: o/open
      - name: openok
        repo: o/openok
        public_ok: true
        labels: [idea]
    EOF
    touch "$FAKE/public/o_open" "$FAKE/public/o_openok"
    fail=0
    expect() {
      if [ "$1" != "$2" ]; then
        printf 'FAIL %s:\n  got      %s\n  expected %s\n' "$3" "$1" "$2"
        fail=1
      fi
    }
    # The last filed issue's field, and the ticket body a What section makes.
    created() { tail -n 1 "$FAKE/creates" | jq -r "$1"; }
    ticket() { printf '## What\n%s\n\n## Notes\n\n## Done when' "$1"; }

    expect "$(backlog add nixos 'img viewer // see https://x.y/z' </dev/null)" \
      "https://github.com/o/nixos-issues/issues/1" "add prints the issue URL"
    expect "$(created '[.repo, .title] | join("|")')" "o/nixos-issues|img viewer" "text before // is the title"
    expect "$(created .body)" "$(ticket 'see https://x.y/z')" "text after // is the What section of the ticket layout"
    expect "$(created '.labels | join(" ")')" "capture" "the default label is capture"

    backlog add dots 'see https://a.b/c' </dev/null >/dev/null
    expect "$(created .title)" "see https://a.b/c" "a URL's :// stays in the title"
    expect "$(created .body)" "$(ticket 'see https://a.b/c')" "with no body, What repeats the title"

    echo "from stdin" | backlog add dots 'one // two' >/dev/null
    expect "$(created .body)" "$(ticket "two"$'\n\n'"from stdin")" "stdin is appended to the body"

    backlog add dots 'Fix: the clock' </dev/null >/dev/null
    expect "$(created '.labels | join(" ")')" "capture type:bug" "a title's prefix adds its label"
    backlog add dots 'add: lowercase' </dev/null >/dev/null
    expect "$(created '.labels | join(" ")')" "capture type:feature" "prefixes match in any case"
    backlog add dots 'Fixed nothing' </dev/null >/dev/null
    expect "$(created '.labels | join(" ")')" "capture" "a prefix needs its colon"

    mkdir -p "$PWD/dev/homelab-thing"
    (cd "$PWD/dev/homelab-thing" && backlog add 'guessed' </dev/null >/dev/null)
    expect "$(created .repo)" "o/nixos-issues" "the cwd picks the project by its match words"
    expect "$(cd "$PWD/dev/homelab-thing" && backlog projects | head -n 2 | tr '\n' ' ')" "nixos dots " \
      "projects lists the guess, then the most recent"

    before=$(wc -l <"$FAKE/creates")
    expect "$(backlog add open 'leak' </dev/null 2>&1 || echo "rc=$?")" \
      "backlog: refused: o/open is public; set public_ok: true in $BACKLOG_CONFIG to allow it"$'\n'"rc=1" \
      "a public repo without public_ok is refused"
    expect "$(wc -l <"$FAKE/creates")" "$before" "a refused idea files nothing"
    expect "$([ -e "$queue" ] && echo queued || echo none)" none "a refused idea is not queued"

    backlog add openok 'fine' </dev/null >/dev/null
    expect "$(created '[.repo, (.labels | join(" "))] | join("|")')" "o/openok|idea" \
      "public_ok allows a public repo, and labels override the default"

    printf 'projects:\n  - name: x\n    repo: xo/dots-issues\n' >"$PWD/x.yaml"
    touch "$FAKE/public/xo_dots-issues"
    expect "$(BACKLOG_CONFIG=$PWD/x.yaml backlog add x 'leak' </dev/null 2>&1 | cut -d' ' -f1-3 || true)" \
      "backlog: refused: xo/dots-issues" "a cached private repo doesn't vouch for one whose name ends the same"

    mkdir -p "$PWD/elsewhere"
    expect "$(cd "$PWD/elsewhere" && backlog add 'fallback' </dev/null 2>&1 >/dev/null)" \
      "backlog: nothing matches $PWD/elsewhere; using the most recent project, openok" \
      "with no match the CLI falls back to the most recent project and says so"

    calls=$(wc -l <"$FAKE/api-calls")
    backlog add nixos 'again' </dev/null >/dev/null
    expect "$(wc -l <"$FAKE/api-calls")" "$calls" "a repo's visibility is cached"

    # The project list as an age file, decrypted with an SSH key, as on the machines.
    ssh-keygen -q -t ed25519 -N "" -f "$PWD/id_ed25519"
    age -R "$PWD/id_ed25519.pub" -o "$PWD/projects.age" "$BACKLOG_CONFIG"
    expect "$(env -u BACKLOG_CONFIG BACKLOG_SECRET=$PWD/projects.age BACKLOG_IDENTITY=$PWD/id_ed25519 backlog projects | sort | tr '\n' ' ')" \
      "dots nixos open openok " "the encrypted project list is decrypted with the SSH key"
    expect "$(env -u BACKLOG_CONFIG backlog projects 2>&1 || true)" \
      "backlog: no project list at /nonexistent/backlog-projects.age (SECURITY.md: add a secret)" \
      "a missing project list says where it should be"
    ssh-keygen -q -t ed25519 -N "" -f "$PWD/other"
    expect "$(env -u BACKLOG_CONFIG BACKLOG_SECRET=$PWD/projects.age BACKLOG_IDENTITY=$PWD/other backlog projects 2>&1 | tail -n 1 || true)" \
      "backlog: can't decrypt $PWD/projects.age with $PWD/other" "a key the list isn't encrypted to is refused"

    touch "$FAKE/offline"
    expect "$(backlog add --notify nixos 'offline idea // b' </dev/null 2>/dev/null; echo "rc=$?")" "rc=0" \
      "an offline add succeeds by queueing"
    expect "$(jq -r '"\(.repo) \(.title) \(.body)"' "$queue")" "o/nixos-issues offline idea b" "the idea is queued"
    expect "$(tail -n 1 "$FAKE/notes")" "notify -a backlog -u normal backlog: queued (offline) offline idea" \
      "offline is a normal-urgency notification"
    backlog flush
    expect "$(wc -l <"$queue")" 1 "a flush while offline keeps the line"
    rm "$FAKE/offline"
    expect "$(backlog flush)" "https://github.com/o/nixos-issues/issues/$(cat "$FAKE/n")" "a flush back online files it"
    expect "$(created .body)" "$(ticket b)" "in the ticket layout"
    expect "$([ -e "$queue" ] && echo queued || echo none)" none "and empties the queue"

    touch "$FAKE/broken"
    backlog add --notify dots 'broken' </dev/null >/dev/null 2>&1 || true
    expect "$(tail -n 1 "$FAKE/notes" | cut -d' ' -f1-6)" "notify -a backlog -u critical backlog:" \
      "any other failure is critical"
    backlog flush 2>/dev/null
    backlog flush 2>/dev/null
    expect "$(jq -r .fails "$queue")" 3 "each failed flush counts against the line"
    expect "$(grep -c 'failed' "$FAKE/notes" || true)" 0 "a quiet flush can't raise the notification"
    backlog flush --notify 2>/dev/null
    expect "$(grep -c 'failed 4 times' "$FAKE/notes")" 1 "the next notifying run past the limit raises it"
    backlog flush --notify 2>/dev/null
    expect "$(grep -c 'failed' "$FAKE/notes")" 1 "and only once"
    expect "$(backlog queue | cut -d' ' -f3-)" "o/dots-issues  broken  (failed 5x)" "queue lists the line"
    rm "$FAKE/broken"
    backlog add dots 'next' </dev/null >/dev/null
    expect "$(tail -n 2 "$FAKE/creates" | jq -r .title | tr '\n' ' ')" "broken next " "a capture flushes the queue first"

    printf 'capture\ntype:bug\n' >"$FAKE/labels"
    : >"$LOG"
    backlog setup >/dev/null
    expect "$(sort "$LOG" | tr '\n' ' ')" \
      "label idea o/openok label type:feature o/dots-issues label type:feature o/nixos-issues label type:feature o/open label type:feature o/openok " \
      "setup creates only the missing labels, prefix labels included, in each repo"

    printf 'PNG1' >"$PWD/shot.png"
    : >"$LOG"
    before=$(wc -l <"$FAKE/creates")
    expect "$(backlog add --image "$PWD/shot.png" nixos 'x' </dev/null 2>&1 || echo "rc=$?")" \
      "backlog: --image needs attachments_repo: OWNER/NAME in $BACKLOG_CONFIG"$'\n'"rc=1" \
      "--image without attachments_repo is refused"
    expect "$(cat "$LOG")$(wc -l <"$FAKE/creates")" "$before" "and nothing is uploaded or filed"

    echo 'attachments_repo: o/attach' >>"$BACKLOG_CONFIG"
    day=$(date -u +%Y-%m-%d)
    raw() { echo "https://github.com/o/attach/blob/main/$day/$(sha256sum "$1" | cut -c1-16).png?raw=true"; }
    url1=$(raw "$PWD/shot.png")
    backlog add --image "$PWD/shot.png" nixos 'shot // look' </dev/null >/dev/null
    expect "$(cat "$FAKE/uploads/o/attach/$day/"*.png)" PNG1 "the image is committed to the attachments repo"
    expect "$(created .body)" "$(ticket "look"$'\n\n'"![image]($url1)")" \
      "and embedded at the end of the What section by its raw URL"

    backlog add --image "$PWD/shot.png" dots 'again' </dev/null >/dev/null
    expect "$(created .body)" "$(ticket "again"$'\n\n'"![image]($url1)")" "an image already uploaded is reused"

    printf 'PNG2' >"$PWD/two.png"
    url2=$(raw "$PWD/two.png")
    touch "$FAKE/offline"
    backlog add --image "$PWD/two.png" nixos 'later' </dev/null 2>/dev/null
    expect "$(cat "$(jq -r .image "$queue")")" PNG2 "offline, the image is copied into the state dir beside the queued line"
    rm "$PWD/two.png" "$FAKE/offline"
    backlog flush >/dev/null
    expect "$(created .body)" "$(ticket "later"$'\n\n'"![image]($url2)")" \
      "a flush uploads the copy and files the line with it, after the original is gone"
    expect "$(ls -A "$HOME/.local/state/backlog/images")" "" "and removes the copy"

    touch "$FAKE/public/o_attach"
    rm "$HOME/.local/state/backlog/visibility"
    before=$(wc -l <"$FAKE/creates")
    expect "$(backlog add --image "$PWD/shot.png" dots 'leak' </dev/null 2>&1 >/dev/null || true)" \
      "backlog: queued after an error: o/attach is public; attachments_repo must be private" \
      "a public attachments repo is never uploaded to"
    expect "$(wc -l <"$FAKE/creates")" "$before" "nor is the issue filed without its image"
    rm "$FAKE/public/o_attach" "$queue" "$HOME/.local/state/backlog/visibility"
    rm -r "$HOME/.local/state/backlog/images"

    mkdir -p "$FAKE/missing"
    touch "$FAKE/missing/o_attach"
    : >"$LOG"
    expect "$(backlog setup | grep o/attach)" "o/attach: created (private)" "setup creates a missing attachments repo"
    expect "$(grep '^repo' "$LOG")" "repo create o/attach --private" "as private"
    rm "$FAKE/missing/o_attach"
    expect "$(backlog setup | grep o/attach)" "o/attach: exists" "and leaves an existing one"

    # The prompt runs last: the add it starts is backgrounded, so its issues land late.
    filed() {
      for _ in $(seq 100); do grep -q "\"title\":\"$1\"" "$FAKE/creates" && return 0; sleep 0.1; done
    }
    drafts=$HOME/.local/state/backlog/drafts
    # box PROJECT ANSWERS...: an empty PROJECT opens the picker first.
    box() {
      rm -f "$FAKE/ui-n" "$FAKE/fuzzel-search" "$FAKE/fuzzel-prompts" "$FAKE/vicinae-list" "$FAKE/fuzzel-args"
      printf '%s\n' "''${@:2}" >"$FAKE/answers"
      backlog prompt ''${1:+"$1"}
    }
    draft() { if [ -e "$drafts/$1" ]; then cat "$drafts/$1"; else echo none; fi; }

    box "" ESC
    expect "$([ -e "$FAKE/fuzzel-prompts" ] && echo opened || echo none)" none "Esc in the picker opens no box"
    box "" "no such project"
    expect "$([ -e "$FAKE/fuzzel-prompts" ] && echo opened || echo none)" none "a row that isn't a project opens no box"

    touch "$FAKE/no-noctalia"
    box "" dots 'from the picker'
    filed "from the picker"
    expect "$(cat "$FAKE/fuzzel-prompts")" "dots> " "the picked project's box opens"
    expect "$(created .repo)" "o/dots-issues" "and its line is filed there"
    expect "$(grep -c '^\[key-bindings\]' "$FAKE/fuzzel.ini")" 1 "the box gets its key bindings"
    expect "$(grep -c '^\[colors\]' "$FAKE/fuzzel.ini" || true)" 0 "and no colors while Noctalia can't render them"

    rm "$FAKE/no-noctalia"
    box dots ESC
    expect "$(cat "$FAKE/noctalia-args")" "msg templates-apply" "colors not rendered yet are rendered by Noctalia"
    expect "$(tail -n 2 "$FAKE/fuzzel.ini" | tr '\n' ' ')" "[colors] background=112233ff " "and used in the box"
    box dots ESC
    expect "$(wc -l <"$FAKE/noctalia-args")" 1 "once: rendered colors are reused"

    : >"$FAKE/notes"
    box removed
    expect "$(cat "$FAKE/notes")" "notify -a backlog backlog: no project removed it is no longer in $BACKLOG_CONFIG" \
      "a project gone from the config notifies and does nothing else"
    expect "$([ -e "$FAKE/ui-n" ] && echo opened || echo none)" none "and opens no box"

    # Shift+Enter: with no attachments_repo, then no image, the box reopens with the text; then the image is filed.
    : >"$FAKE/notes"
    BACKLOG_CONFIG=$PWD/x.yaml box x 'SHIFT:pic // see' ESC
    expect "$(grep "can't attach" "$FAKE/notes")" "notify -a backlog backlog: can't attach an image set attachments_repo: OWNER/NAME in $PWD/x.yaml" \
      "Shift+Enter without attachments_repo says so"
    expect "$(cat "$FAKE/fuzzel-search")" "pic // see" "and reopens the box with the text kept"

    : >"$FAKE/notes"
    printf 'text/plain\n' >"$FAKE/clip-types"
    box nixos 'SHIFT:nopic // see' ESC
    expect "$(grep "can't attach" "$FAKE/notes")" "notify -a backlog backlog: can't attach an image no image on the clipboard" \
      "Shift+Enter with no image on the clipboard says so"
    expect "$(cat "$FAKE/fuzzel-search")" "nopic // see" "and reopens the box with the text kept"
    rm "$drafts/nixos"

    printf 'image/jpeg\nimage/png\n' >"$FAKE/clip-types"
    printf 'PNG3' >"$FAKE/clip"
    box nixos 'SHIFT:pic // see'
    filed pic
    expect "$(cat "$FAKE/wl-paste-args")" "--no-newline --type image/png" "PNG is preferred among the offered types"
    expect "$(grep '"title":"pic"' "$FAKE/creates" | jq -r .body)" "$(ticket "see"$'\n\n'"![image]($(raw "$FAKE/clip"))")" \
      "the second Shift+Enter files the line with the clipboard's image"
    # find, not a glob: stdenv sets nullglob, so an unmatched glob would list the cwd.
    clips() { find "$HOME/.local/state/backlog" -maxdepth 1 -name 'clip.*'; }
    for _ in $(seq 100); do [ -z "$(clips)" ] && break; sleep 0.1; done
    expect "$(clips)" "" "and removes the clipboard's copy"

    # Drafts: Esc keeps the box's text per project, reopened in the box and marked in the picker.
    text='foo // bar "q" ✓  '
    box openok "ESC:$text"
    expect "$(draft openok)" "$text" "Esc keeps the text, byte for byte, as the project's draft"
    expect "$(grep -c -- --no-exit-on-keyboard-focus-loss "$FAKE/fuzzel-args")" 1 "the box stays open on focus loss"

    box "" "openok ✎" ESC
    expect "$(tr '\n' '|' <"$FAKE/vicinae-list")" "openok ✎|$(backlog projects | grep -vx openok | tr '\n' '|')" \
      "a project with a draft leads the picker, marked"
    expect "$(cat "$FAKE/fuzzel-prompts")" "openok> " "picking it opens its box by its bare name"
    expect "$(cat "$FAKE/fuzzel-search")" "$text" "with the draft in it"
    expect "$(draft openok)" "$text" "Esc on the untouched box keeps the draft"

    box "" "openok ✎" 'drafted // filed'
    filed drafted
    expect "$(draft openok)" none "Enter files it and clears the draft"
    box "" ESC
    expect "$(grep -c '✎' "$FAKE/vicinae-list" || true)" 0 "the next picker marks nothing"
    box openok ESC
    expect "$([ -e "$FAKE/fuzzel-search" ] && echo refilled || echo empty)" empty "and the next box is empty"

    box dots "ESC:keep"
    box nixos "ESC:mine"
    box dots CTRLG
    expect "$(cat "$FAKE/fuzzel-search")" keep "the box reopens with its own project's draft"
    expect "$(draft dots)" none "Ctrl+G discards the draft"
    expect "$(draft nixos)" mine "and leaves another project's"
    box nixos RCLICK
    expect "$(draft nixos)" mine "a right-click, which prints nothing, leaves the draft"
    box nixos "ESC:   "
    expect "$(draft nixos)" none "Esc on an emptied box clears the draft"

    box dots "ESC:cli"
    backlog add dots 'from the cli' </dev/null >/dev/null
    expect "$(draft dots)" cli "the CLI's add leaves drafts alone"
    rm "$drafts/dots"

    box open 'secret // s'
    for _ in $(seq 100); do [ -e "$drafts/open" ] && break; sleep 0.1; done
    expect "$(draft open)" "secret // s" "a line the repo refuses becomes the draft again"

    box dots ' // no title'
    for _ in $(seq 100); do [ -e "$drafts/dots" ] && break; sleep 0.1; done
    expect "$(draft dots)" " // no title" "a line add rejects before filing becomes the draft again"
    rm "$drafts/dots"

    touch "$FAKE/offline"
    box nixos "ESC:later"
    box nixos 'queued draft'
    for _ in $(seq 100); do grep -q 'queued draft' "$queue" 2>/dev/null && break; sleep 0.1; done
    expect "$(jq -r .title "$queue")" "queued draft" "an offline line is queued"
    expect "$(draft nixos)" none "and clears the draft, as filing does"
    rm "$FAKE/offline"

    if [ "$fail" != 0 ]; then exit 1; fi
    touch $out
  ''
