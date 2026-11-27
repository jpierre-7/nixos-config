# One fuzzy search over every scope's binds: niri (Noctalia's rows tagged), qutebrowser, nvim,
# kanata, herdr, the herdr desktop app and WezTerm. Each row shows the trigger beside its action, so searching teaches
# the bind. niri and Noctalia rows run; app rows copy their trigger. Rows the ignore file
# names are hidden. Vicinae's dmenu can't bind extra keys, so hiding is its own list, reached
# from the palette's "Hide binds" and "Hidden binds" rows.
# Adapted from HefKer/nixos-config's bind-palette.
#   bind-palette                 pick in Vicinae
#   bind-palette hide            pick rows to hide, one after another
#   bind-palette hidden          pick hidden rows to show again
#   bind-palette list            print the shown rows as TSV: scope, trigger, action, command
#   bind-palette list --all      every row, ignoring the ignore file
#   bind-palette list --hidden   the hidden rows, each with what hides it as a fifth field
#
# Each source reads the config its app runs now (the store copies niri and kanata load, the
# cache qutebrowser writes on load, the running nvim/WezTerm config), so a bind shows exactly
# when it works.

config_home=${XDG_CONFIG_HOME:-$HOME/.config}
# config/bind-palette/ignore, linked live (modules/home/bind-palette.nix) so hiding writes into
# the checkout. Blank lines and # comments aside, each line is a scope and a trigger joined by a
# tab, hiding that row, or ~ and an extended regex matched against the row's scope, trigger and
# action joined by tabs.
ignore_file=$config_home/bind-palette/ignore

# Every reader's rows go through this: tabs and newlines inside a field become spaces, and no escaping, which @tsv adds and the shell would keep.
tsv='map(. // "" | tostring | gsub("[\t\n]"; " ")) | join("\t")'

# niri's binds blocks (the main one and recent-windows'), one bind per line as config.kdl writes
# them. A spawn runs its arguments (already shell-quoted the KDL way); spawn-sh its script; any
# other action goes through `niri msg action`, properties as flags (focus=false: --focus false).
niri_rows() {
  local cfg=$config_home/niri/config.kdl
  [[ -r $cfg ]] || return 0
  awk '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    function unquote(s) { if (s ~ /^".*"$/) { s = substr(s, 2, length(s) - 2); gsub(/\\"/, "\"", s) } return s }
    function squote(s) { gsub(/\047/, "\047\\\047\047", s); return "\047" s "\047" }
    /^[ \t]*\/\// { next }
    # A nested binds block (recent-windows) holds switcher actions `niri msg` lacks: copy those.
    /^[ \t]*binds[ \t]*\{/ { inb = 1; nested = /^[ \t]/; next }
    inb && /^[ \t]*\}/ { inb = 0; next }
    inb && /\{.*\}/ {
      head = trim(substr($0, 1, index($0, "{") - 1))
      body = substr($0, index($0, "{") + 1)
      sub(/\}[^}]*$/, "", body)
      body = trim(body); sub(/;$/, "", body); body = trim(body)
      split(head, hf, /[ \t]+/)
      key = hf[1]
      title = ""
      if (match(head, /hotkey-overlay-title="[^"]*"/)) title = substr(head, RSTART + 22, RLENGTH - 23)
      if (nested) {
        cmd = ""
      } else if (body ~ /^spawn-sh /) {
        cmd = unquote(trim(substr(body, 10)))
      } else if (body ~ /^spawn /) {
        cmd = trim(substr(body, 7))
      } else {
        n = split(body, tok, /[ \t]+/)
        cmd = "niri msg action " tok[1]; pos = ""
        for (i = 2; i <= n; i++) {
          if (tok[i] ~ /^[a-z-]+=/) {
            eq = index(tok[i], "=")
            cmd = cmd " --" substr(tok[i], 1, eq - 1) " " squote(unquote(substr(tok[i], eq + 1)))
          } else {
            pos = pos " " squote(unquote(tok[i]))
          }
        }
        if (pos != "") cmd = cmd " --" pos
      }
      scope = (body ~ /^spawn "noctalia"/) ? "noctalia" : "niri"
      printf "%s\t%s\t%s\t%s\n", scope, key, (title != "" ? title : body), cmd
    }' "$cfg"
}

# qutebrowser's effective binds, which its config.py writes on every load (config/qutebrowser/bindsdump.py); asking the running browser over IPC would raise its window.
qutebrowser_rows() {
  local binds="${XDG_CACHE_HOME:-$HOME/.cache}/qutebrowser/binds.json"
  [[ -r $binds ]] || return 0
  jq -r 'to_entries[] | .key as $m | .value | to_entries[]
    | ["qutebrowser", (if $m == "normal" then .key else "\($m): \(.key)" end), .value, ""] | '"$tsv" "$binds"
}

# nvim's global maps with a description (LazyVim's, which-key groups included); buffer-local ones stay on <leader>sk.
nvim_rows() {
  command -v nvim >/dev/null || return 0
  nvim --headless -i NONE +'lua
    local rows = {}
    for _, m in ipairs({ "n", "x", "i", "o", "t", "c" }) do
      for _, k in ipairs(vim.api.nvim_get_keymap(m)) do
        if k.desc and k.desc ~= "" then
          local lhs = vim.fn.keytrans(k.lhs)
          rows[#rows + 1] = table.concat({ "nvim", m == "n" and lhs or (m .. ": " .. lhs), (k.desc:gsub("[\t\n]", " ")), "" }, "\t")
        end
      end
    end
    io.stdout:write(table.concat(rows, "\n") .. "\n")' +qa 2>/dev/null
}

# kanata's home-row mods and base-layer remaps (config/kanata/keymap.kbd). Aliases (@...) and keys mapped to themselves are skipped.
kanata_rows() {
  [[ -r $kanata_keymap ]] || return 0
  awk '
    BEGIN {
      split("bspc Backspace del Delete ret Enter esc Escape grv Grave ins Insert pgup PageUp pgdn PageDown " \
            "home Home end End lft Left left Left rght Right up Up down Down prnt PrintScreen caps CapsLock " \
            "menu Menu tab Tab spc Space ralt RightAlt rmet RightSuper rctl RightCtrl " \
            "lmet Super lalt Alt lctl Ctrl lsft Shift rsft Shift", pairs, " ")
      for (i = 1; i < length(pairs); i += 2) name[pairs[i]] = pairs[i + 1]
    }
    function key(k) { return (k in name) ? name[k] : toupper(k) }
    # A home-row mod alias: hra (t! hrm a lmet $left-mods), several per line.
    /\(t! hrm / {
      line = $0
      while (match(line, /\(t! hrm [^ ]+ [^ ]+/)) {
        split(substr(line, RSTART + 8, RLENGTH - 8), hr, " ")
        printf "kanata\tHold %s\t%s\t\n", key(hr[1]), key(hr[2])
        line = substr(line, RSTART + RLENGTH)
      }
      next
    }
    /^\(deflayermap \(base\)/ { layer = 1; next }
    /^\(/ { layer = 0; next }
    !layer || /^[[:space:]]*;/ { next }
    {
      sub(/\)[[:space:]]*$/, "")
      for (i = 1; i < NF; i += 2) {
        src = $i; dst = $(i + 1)
        if (dst ~ /^@/ || src == dst) continue
        printf "kanata\t%s\t%s\t\n", key(src), key(dst)
      }
    }' "$kanata_keymap"
}

# herdr's keys set in config.toml (herdr can't list its defaults): [keys] actions by name, and
# [[keys.command]] by description. "prefix" is written as the prefix's own keys.
herdr_rows() {
  local cfg=$config_home/herdr/config.toml
  [[ -r $cfg ]] || return 0
  yq -p toml -o json '.keys // {}' "$cfg" | jq -r '
    (.prefix // "ctrl+space") as $p
    | def cap: if length > 1 then (.[0:1] | ascii_upcase) + .[1:] else . end;
      def keys: split("+") | map(cap) | join("+");
      def trig: if startswith("prefix+") then ($p | keys) + " " + (.[7:] | keys) else keys end;
    ( (to_entries[] | select(.key != "prefix" and (.value | type) == "string")
        | ["herdr", (.value | trig), (.key | gsub("_"; " ")), ""]),
      ((.command // [])[] | ["herdr", (.key | trig), (.description // .command), ""]) )
    | '"$tsv"
}

# The herdr desktop app's keys.json, which the app writes in full (defaults included) and rewrites
# when a bind changes there. Context "global" rows show bare, others as "terminal: ...". Control
# characters a send: action types are shown in caret notation (^W).
herdr_app_rows() {
  local keys=$config_home/herdr-app/keys.json
  [[ -r $keys ]] || return 0
  jq -r '
    def cap: if length > 1 then (.[0:1] | ascii_upcase) + .[1:] else . end;
    # "ctrl--" is Ctrl and "-", so modifiers are matched by name, not by splitting on "-".
    def trig: capture("^(?<m>((ctrl|alt|shift|super|cmd|meta|fn)-)*)(?<k>.+)$")
      | (.m | split("-") | map(select(. != "") | cap)) + [.k | cap] | join("+");
    to_entries[] | .key as $ctx | .value | to_entries[]
    | ["herdr-app",
       (if $ctx == "global" then "" else "\($ctx): " end) + (.key | trig),
       (.value | gsub("(?<c>[\u0000-\u001f])"; "^" + ([(.c | explode[0]) + 64] | implode)) | gsub("[._:]"; " ")),
       ""]
    | '"$tsv" "$keys"
}

# WezTerm's keys that differ from its defaults: `show-keys` with the config, minus `-n show-keys`
# without it, default key table only. Callbacks are named events in keys.lua, so they read as actions.
wezterm_rows() {
  command -v wezterm >/dev/null || return 0
  local defaults
  defaults=$(wezterm -n show-keys 2>/dev/null | awk '/^(Key Table|Mouse)/ { exit } / -> /')
  wezterm show-keys 2>/dev/null | awk '/^(Key Table|Mouse)/ { exit } / -> /' |
    defaults=$defaults awk '
      function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
      BEGIN { n = split(ENVIRON["defaults"], d, "\n"); for (i = 1; i <= n; i++) seen[d[i]] }
      $0 in seen { next }
      {
        arrow = index($0, " -> ")
        left = trim(substr($0, 1, arrow - 1)); action = trim(substr($0, arrow + 4))
        if (split(left, f, /   +/) > 1) { mods = f[1]; k = f[2] } else { mods = ""; k = f[1] }
        sub(/ \(Physical\)$/, "", k)
        gsub(/ \| /, "+", mods)
        mods = tolower(mods)
        out = ""
        m = split(mods, mp, "+")
        for (i = 1; i <= m; i++) out = out toupper(substr(mp[i], 1, 1)) substr(mp[i], 2) "+"
        if (match(action, /^EmitEvent\("[^"]*"\)$/)) action = substr(action, 12, length(action) - 13)
        printf "wezterm\t%s%s\t%s\t\n", out, k, action
      }'
}

all_rows() {
  # Each source fails alone, so one broken reader drops one scope, not the palette.
  niri_rows || true
  qutebrowser_rows || true
  nvim_rows || true
  kanata_rows || true
  herdr_rows || true
  herdr_app_rows || true
  wezterm_rows || true
}

# The ignore file's lines that apply. A pattern that doesn't compile is reported on stderr and
# skipped, so it hides nothing rather than ending the filter.
ignore_lines() {
  [[ -r $ignore_file ]] || return 0
  local line
  while IFS= read -r line || [[ -n $line ]]; do
    line=${line%$'\r'}
    [[ -z $line || $line == '#'* ]] && continue
    # Through the environment, as classify reads it, so the backslashes mean the same.
    if [[ $line == '~'* ]] && ! re=${line:1} gawk 'BEGIN { if ("" ~ ENVIRON["re"]) {} }' 2>/dev/null; then
      echo "bind-palette: invalid pattern skipped: $line" >&2
      continue
    fi
    printf '%s\n' "$line"
  done <"$ignore_file"
}

# Rows on stdin. shown prints those no line hides; hidden prints the others, with a fifth field:
# "row" for an exact-row line, or the ~pattern.
classify() {
  local rules
  rules=$(ignore_lines)
  rules=$rules gawk -F'\t' -v OFS='\t' -v view="$1" '
    BEGIN {
      n = split(ENVIRON["rules"], r, "\n")
      for (i = 1; i <= n; i++)
        if (substr(r[i], 1, 1) == "~") pat[++np] = substr(r[i], 2)
        else if (r[i] != "") exact[r[i]]
    }
    {
      by = ""
      if (($1 "\t" $2) in exact) by = "row"
      else for (i = 1; i <= np; i++) if (($1 "\t" $2 "\t" $3) ~ pat[i]) { by = "~" pat[i]; break }
    }
    view == "shown" && by == "" { print; next }
    view == "hidden" && by != "" { print $1, $2, $3, $4, by }'
}

list() {
  case "${1:-}" in
    "") all_rows | classify shown ;;
    --all) all_rows ;;
    --hidden) all_rows | classify hidden ;;
    *) usage ;;
  esac
}

hide() {
  mkdir -p "$(dirname "$ignore_file")"
  # A last line without its newline would swallow the new one.
  if [[ -s $ignore_file && -n $(tail -c1 "$ignore_file") ]]; then echo >>"$ignore_file"; fi
  printf '%s\t%s\n' "$1" "$2" >>"$ignore_file"
}

unhide() {
  local rest
  rest=$(line="$1"$'\t'"$2" gawk '{ l = $0; sub(/\r$/, "", l) } l != ENVIRON["line"]' "$ignore_file")
  # Rewritten in place, not replaced, so the live link keeps pointing at the checkout.
  if [[ -n $rest ]]; then printf '%s\n' "$rest" >"$ignore_file"; else : >"$ignore_file"; fi
}

# Shows ROWS (TSV) in Vicinae and prints the picked row; nothing on Esc.
choose() {
  local rows=$1 title=$2 hint=$3 shown picked
  [[ -n $rows ]] || return 0
  shown=$(awk -F'\t' '{ printf "%-13s %-28s %s%s\n", "[" $1 "]", $2, $3, ($5 ~ /^~/ ? "   ⟵ " $5 : "") }' <<<"$rows")
  picked=$(vicinae dmenu --no-quick-look --no-footer -n "$title" -p "$hint" <<<"$shown") || return 0
  # Vicinae prints the picked row, never typed text; its line number finds the row. Compared with
  # runs of spaces squeezed, so the column padding needn't come back byte for byte.
  awk -v p="$picked" '
    function norm(s) { gsub(/[ \t]+/, " ", s); gsub(/^ | $/, "", s); return s }
    BEGIN { p = norm(p) }
    NR == FNR { if (norm($0) == p && !n) n = FNR; next }
    FNR == n' <(printf '%s\n' "$shown") <(printf '%s\n' "$rows")
}

report_bad_patterns() {
  local errs
  errs=$(ignore_lines 2>&1 >/dev/null)
  [[ -z $errs ]] || notify-send -a "Bind palette" "Ignore file: pattern skipped" "$errs"
}

pick() {
  local rows row scope trigger action cmd
  report_bad_patterns
  rows=$(list)
  # The hide lists' way in, last so they don't crowd the binds when nothing is typed yet.
  rows+=$'\n'$'palette\t\tHide binds (ones already learned)\thide_rows'
  rows+=$'\n'$'palette\t\tHidden binds (show one again)\thidden_rows'
  row=$(choose "$rows" "Keybinds" "e.g. workspace · split · screenshot · find files  (Ctrl+J/K: move)")
  [[ -n $row ]] || return 0
  # cut, not read: read collapses runs of tabs, which shifts an empty field.
  scope=$(cut -f1 <<<"$row")
  trigger=$(cut -f2 <<<"$row")
  action=$(cut -f3 <<<"$row")
  cmd=$(cut -f4 <<<"$row")
  if [[ $scope == palette ]]; then
    "$cmd"
  elif [[ -n $cmd ]]; then
    # Detached, as niri's own spawn runs it.
    setsid -f sh -c "$cmd" >/dev/null 2>&1
    # The repeat key (pkgs/repeat/) runs the row again without the palette. Not the repeat row
    # itself: its replay would replay itself forever.
    [[ ${cmd//\"/} == repeat ]] || repeat record sh -c "$cmd"
  else
    printf '%s' "$trigger" | wl-copy
    notify-send -a "Bind palette" "$scope: $trigger" "$action (trigger copied)"
  fi
}

# Enter hides the row and reopens the list without it, so several can go one after another.
# Esc ends. Vicinae takes no starting query, so the search starts over each time.
hide_rows() {
  local all row
  report_bad_patterns
  # Read once: the readers are the slow part, and a hide only reclassifies.
  all=$(all_rows)
  while row=$(choose "$(classify shown <<<"$all")" "Hide binds" "Enter hides the row · Esc done") && [[ -n $row ]]; do
    hide "$(cut -f1 <<<"$row")" "$(cut -f2 <<<"$row")"
  done
}

# Enter shows the row again and reopens the list, until nothing's hidden or Esc.
hidden_rows() {
  local all hidden row
  report_bad_patterns
  all=$(all_rows)
  hidden=$(classify hidden <<<"$all")
  if [[ -z $hidden ]]; then
    notify-send -a "Bind palette" "Nothing hidden" "Pick \"Hide binds\" in the palette to hide some"
    return 0
  fi
  while [[ -n $hidden ]]; do
    row=$(choose "$hidden" "Hidden binds" "Enter shows the row again · Esc done")
    [[ -n $row ]] || return 0
    if [[ $(cut -f5 <<<"$row") == row ]]; then
      unhide "$(cut -f1 <<<"$row")" "$(cut -f2 <<<"$row")"
    else
      notify-send -a "Bind palette" "Hidden by a pattern" "$(cut -f5 <<<"$row")"$'\n'"Edit $ignore_file to show it"
    fi
    hidden=$(classify hidden <<<"$all")
  done
}

usage() {
  echo "usage: bind-palette [pick | hide | hidden | list [--all | --hidden]]" >&2
  exit 2
}

case "${1:-pick}" in
  pick) pick ;;
  hide) hide_rows ;;
  hidden) hidden_rows ;;
  list) list "${2:-}" ;;
  *) usage ;;
esac
