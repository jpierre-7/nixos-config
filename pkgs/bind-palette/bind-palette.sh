# One fuzzy search over every scope's binds: niri (Noctalia's rows tagged), qutebrowser, nvim,
# kanata, herdr and WezTerm. Each row shows the trigger beside its action, so searching teaches
# the bind. niri and Noctalia rows run; app rows copy their trigger.
# Adapted from HefKer/nixos-config's bind-palette.
#   bind-palette        pick in Vicinae
#   bind-palette list   print the rows as TSV: scope, trigger, action, command
#
# Each source reads the config its app runs now (the store copies niri and kanata load, the
# cache qutebrowser writes on load, the running nvim/WezTerm config), so a bind shows exactly
# when it works.

config_home=${XDG_CONFIG_HOME:-$HOME/.config}

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

list() {
  # Each source fails alone, so one broken reader drops one scope, not the palette.
  niri_rows || true
  qutebrowser_rows || true
  nvim_rows || true
  kanata_rows || true
  herdr_rows || true
  wezterm_rows || true
}

pick() {
  local rows shown picked row scope trigger action cmd
  rows=$(list)
  shown=$(awk -F'\t' '{ printf "%-13s %-28s %s\n", "[" $1 "]", $2, $3 }' <<<"$rows")
  picked=$(vicinae dmenu --no-quick-look --no-footer -n "Keybinds" -p "e.g. workspace · split · screenshot · find files  (Ctrl+J/K: move)" <<<"$shown") || return 0
  # Vicinae prints the picked row, never typed text; its line number finds the row. Compared with
  # runs of spaces squeezed, so the column padding needn't come back byte for byte.
  row=$(awk -v p="$picked" '
    function norm(s) { gsub(/[ \t]+/, " ", s); gsub(/^ | $/, "", s); return s }
    BEGIN { p = norm(p) }
    NR == FNR { if (norm($0) == p && !n) n = FNR; next }
    FNR == n' <(printf '%s\n' "$shown") <(printf '%s\n' "$rows"))
  [[ -n $row ]] || return 0
  # cut, not read: read collapses runs of tabs, which shifts an empty field.
  scope=$(cut -f1 <<<"$row")
  trigger=$(cut -f2 <<<"$row")
  action=$(cut -f3 <<<"$row")
  cmd=$(cut -f4 <<<"$row")
  if [[ -n $cmd ]]; then
    # Detached, as niri's own spawn runs it.
    setsid -f sh -c "$cmd" >/dev/null 2>&1
  else
    printf '%s' "$trigger" | wl-copy
    notify-send -a "Bind palette" "$scope: $trigger" "$action (trigger copied)"
  fi
}

case "${1:-pick}" in
  pick) pick ;;
  list) list ;;
  *)
    echo "usage: bind-palette [pick|list]" >&2
    exit 2
    ;;
esac
