# Idle screensaver modeled on Omarchy's (bin/omarchy-launch-screensaver and
# bin/omarchy-screensaver in basecamp/omarchy): terminaltexteffects animates a
# logo in a fullscreen terminal on every monitor, a random effect each round.
# Packaged as `nixos-screensaver` in modules/home/screensaver.nix.
#
#   start  Noctalia's idle service runs this after the idle timeout
#          (modules/home/noctalia.nix). Opens one WezTerm per monitor.
#   stop   Noctalia runs this on the next input. Locks, then closes them.
#   run    What each WezTerm shows.
#
# The screensaver plays in the unlocked session, so every way out of it locks
# first, and its windows close only once the lock screen is up.

app_id=org.nixos.screensaver

locked() {
  [[ $(noctalia msg status 2>/dev/null | jq -r .locked) == true ]]
}

# Noctalia reports `locked` as soon as it asks for the lock, but niri keeps
# sending input to windows for up to a second after that, until the lock screen
# has drawn. A screensaver window that closed in that time would hand the input
# to the desktop behind it, so wait this long after `locked` first.
lock_settle=1.5

screensaver_windows() {
  niri msg --json windows | jq -r --arg app_id "$app_id" '.[] | select(.app_id == $app_id) | .id'
}

start() {
  # Nothing would show behind the lock screen, and one set is enough.
  if locked || [[ -n $(screensaver_windows) ]]; then
    return
  fi

  # A new window opens on the focused monitor, so focus each one in turn and
  # wait for its window before moving on, as Omarchy does with hyprctl.
  local focused output count
  focused=$(niri msg --json focused-output | jq -r .name)
  for output in $(niri msg --json outputs | jq -r 'to_entries[] | select(.value.logical) | .key'); do
    niri msg action focus-monitor "$output"
    count=$(screensaver_windows | wc -l)
    # Overrides on top of wezterm.lua, which supplies Noctalia's colors.
    # Closing must not ask for confirmation, or `stop` would leave the window up.
    niri msg action spawn -- wezterm \
      --config font_size=18 \
      --config window_background_opacity=1.0 \
      --config enable_tab_bar=false \
      --config 'window_padding={left=0,right=0,top=0,bottom=0}' \
      --config 'window_close_confirmation="NeverPrompt"' \
      --config 'exit_behavior="Close"' \
      start --always-new-process --class "$app_id" -- "$0" run
    for _ in $(seq 50); do
      (($(screensaver_windows | wc -l) > count)) && break
      sleep 0.1
    done
  done
  niri msg action focus-monitor "$focused"
}

stop() {
  noctalia msg session lock >/dev/null 2>&1 || true
  # Without Noctalia there is no lock screen to wait for, so give up after five
  # seconds instead of trapping the user behind the screensaver.
  for _ in $(seq 50); do
    if locked; then
      sleep "$lock_settle"
      break
    fi
    sleep 0.1
  done
  for id in $(screensaver_windows); do
    niri msg action close-window --id "$id"
  done
}

run() {
  # Palette roles as RRGGBB, rendered by Noctalia from config/screensaver/colors.sh.
  # Until its first render, the NixOS logo's blues on WezTerm's default black.
  local primary=7ebae4 secondary=5277c3 tertiary=a9d1ee on_surface=ffffff outline=808080 background=000000
  local colors="${XDG_CACHE_HOME:-$HOME/.cache}/noctalia/screensaver-colors.sh"
  # shellcheck source=/dev/null
  [[ -r $colors ]] && source "$colors"

  # Effects whose look comes from colors given here. Each takes the logo's
  # final gradient below; these are their other colors.
  local effects=(
    "beams --beam-gradient-stops $on_surface $primary"
    "burn --starting-color $outline --burn-colors $tertiary $secondary $primary"
    "decrypt --ciphertext-colors $secondary $tertiary $outline"
    "expand"
    "highlight --highlight-brightness 1.5"
    "laseretch --laser-gradient-stops $on_surface $primary --spark-gradient-stops $tertiary $secondary --cool-gradient-stops $secondary $primary"
    "middleout --starting-color $on_surface"
    "rain --rain-colors $primary $secondary $tertiary"
    "slide --merge"
    "sweep --sweep-symbols ░ ▒ ▓"
    "waves --wave-gradient-stops $primary $secondary $tertiary"
  )

  local tte stopping=0 held effect
  trap '[[ -n ${tte:-} ]] && kill "$tte" 2>/dev/null; exit 0' HUP TERM INT
  # Hide the cursor, and have WezTerm report mouse clicks as input. Not moves
  # (mode 1003): on the laptop, WezTerm reported a move a few seconds in with
  # nobody touching it, which locked the session at once. Noctalia's resume
  # command still catches real moves.
  printf '\e[?25l\e[?1000h'
  clear

  while true; do
    effect=${effects[RANDOM % ${#effects[@]}]}
    # shellcheck disable=SC2086 # $effect is the effect name and its options
    tte --input-file "$SCREENSAVER_LOGO" \
      --frame-rate 60 --canvas-width 0 --canvas-height 0 \
      --anchor-canvas c --anchor-text c --reuse-canvas --no-eol --no-restore-cursor \
      --terminal-background-color "$background" \
      $effect \
      --final-gradient-stops "$primary" "$secondary" "$tertiary" \
      --final-gradient-direction diagonal &
    tte=$!

    # Check for input every second, and keep the finished logo up for three
    # more. Noctalia's resume command calls `stop` on input too; this covers
    # the case where it doesn't. `stop` runs on its own, because closing this
    # window hangs up everything started from it.
    held=0
    while kill -0 "$tte" 2>/dev/null || ((held++ < 3)); do
      if read -rsn1 -t 1 && ((!stopping)); then
        stopping=1
        setsid -f "$0" stop
      fi
      # `stop`, or the idle lock in noctalia.nix: nobody sees this behind the
      # lock screen.
      if locked; then
        sleep "$lock_settle"
        exit 0
      fi
    done
  done
}

case ${1:-} in
start | stop | run) "$1" ;;
*)
  echo "usage: nixos-screensaver start|stop|run" >&2
  exit 1
  ;;
esac
