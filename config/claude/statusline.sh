#!/bin/bash
# Statusline wrapper: caveman badge + vim mode indicator
# Reads Claude Code statusline JSON on stdin.

INPUT=$(cat)

# Noctalia's palette, the same roles as the Starship prompt. Noctalia renders
# the colors file from statusline-colors.sh (modules/home/noctalia.nix). Until
# it has, the terminal's own ANSI colors stand in.
C_PRIMARY=$'\033[32m'
C_SECONDARY=$'\033[34m'
C_TERTIARY=$'\033[33m'
C_ERROR=$'\033[31m'
C_MUTED=$'\033[90m'
COLORS="${XDG_CACHE_HOME:-$HOME/.cache}/noctalia/claude-statusline-colors.sh"
# shellcheck source=statusline-colors.sh
[ -f "$COLORS" ] && . "$COLORS"
C_RESET=$'\033[0m'

CAVEMAN=""
if [ -x "$CAVEMAN_SCRIPT" ] || [ -f "$CAVEMAN_SCRIPT" ]; then
  CAVEMAN=$(printf '%s' "$INPUT" | bash "$CAVEMAN_SCRIPT" 2>/dev/null | sed $'s/\x1b\\[[0-9;]*m//g')
  [ -n "$CAVEMAN" ] && CAVEMAN="${C_MUTED}${CAVEMAN}${C_RESET}"
fi

MODE=$(printf '%s' "$INPUT" | jq -r '.vim.mode // .editor.mode // empty' 2>/dev/null)

VIM_BADGE=""
case "$MODE" in
insert | INSERT | i) VIM_BADGE="${C_PRIMARY}[INSERT]${C_RESET}" ;;
normal | NORMAL | n) VIM_BADGE="${C_SECONDARY}[NORMAL]${C_RESET}" ;;
visual | VISUAL | v) VIM_BADGE="${C_TERTIARY}[VISUAL]${C_RESET}" ;;
replace | REPLACE | r) VIM_BADGE="${C_ERROR}[REPLACE]${C_RESET}" ;;
esac

# Current dir as parent/name, e.g. "dev/SeatWatch"
DIR_BADGE=""
CWD=$(printf '%s' "$INPUT" | jq -r '.workspace.current_dir // .cwd // empty' 2>/dev/null)
if [ -n "$CWD" ]; then
  DIR_BADGE="${C_MUTED}$(basename "$(dirname "$CWD")")/$(basename "$CWD")${C_RESET}"
fi

# Idle time: how long since this conversation last had activity. Non-redundant
# with the tab title (which shows *what*, not *when*). Uses transcript mtime.
IDLE_BADGE=""
TP=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
if [ -n "$TP" ] && [ -f "$TP" ]; then
  MT=$(stat -c %Y "$TP" 2>/dev/null)
  if [ -n "$MT" ]; then
    AGO=$(($(date +%s) - MT))
    [ "$AGO" -lt 0 ] && AGO=0
    D=$((AGO / 86400))
    H=$(((AGO % 86400) / 3600))
    M=$(((AGO % 3600) / 60))
    if [ "$AGO" -lt 60 ]; then
      IDLE="now"
    elif [ "$D" -gt 0 ]; then
      IDLE="${D}d${H}h"
    elif [ "$H" -gt 0 ]; then
      IDLE="${H}h${M}m"
    else IDLE="${M}m"; fi
    IDLE_BADGE="${C_MUTED}◷ ${IDLE}${C_RESET}"
  fi
fi

# Git branch of current dir
BRANCH_BADGE=""
if [ -n "$CWD" ]; then
  BRANCH=$(git -C "$CWD" symbolic-ref --short HEAD 2>/dev/null ||
    git -C "$CWD" rev-parse --short HEAD 2>/dev/null)
  [ -n "$BRANCH" ] && BRANCH_BADGE="${C_PRIMARY}${BRANCH}${C_RESET}"
fi

# $2 (default primary) under 50%, tertiary under 80%, error above
pct_color() {
  local p=${1%.*}
  if [ "${p:-0}" -ge 80 ]; then
    printf '%s' "$C_ERROR"
  elif [ "${p:-0}" -ge 50 ]; then
    printf '%s' "$C_TERTIARY"
  else printf '%s' "${2:-$C_PRIMARY}"; fi
}

# Context window usage: tokens used + percent, e.g. "45.2k (5.0%)"
CTX_BADGE=""
read -r USED PCT < <(printf '%s' "$INPUT" | jq -r \
  '.context_window | select(.used_percentage != null) |
   "\(.total_input_tokens + .total_output_tokens) \(.used_percentage)"' 2>/dev/null)
if [ -n "$USED" ]; then
  CTX_BADGE=$(awk -v u="$USED" -v p="$PCT" 'BEGIN { printf "%.1fk (%.1f%%)", u/1000, p }')
  CTX_BADGE="$(pct_color "$PCT")${CTX_BADGE}${C_RESET}"
fi

# Format seconds-from-now into a compact "2d3h" / "2h13m" / "47m" countdown.
fmt_reset() {
  local reset="$1" now target diff d h m
  [ -z "$reset" ] || [ "$reset" = "null" ] && return
  case "$reset" in
  *[!0-9]*) target=$(date -d "$reset" +%s 2>/dev/null) || return ;; # ISO8601
  *) target="$reset" ;;                                             # Unix epoch
  esac
  now=$(date +%s)
  diff=$((target - now))
  [ "$diff" -lt 0 ] && diff=0
  d=$((diff / 86400))
  h=$(((diff % 86400) / 3600))
  m=$(((diff % 3600) / 60))
  if [ "$d" -gt 0 ]; then
    printf '%dd%dh' "$d" "$h"
  elif [ "$h" -gt 0 ]; then
    printf '%dh%02dm' "$h" "$m"
  else printf '%dm' "$m"; fi
}

# Rate limit usage: session (5h) + week, e.g. "5h:19%(2h13m) wk:17%"
USAGE_BADGE=""
read -r FIVE_H FIVE_RESET SEVEN_D SEVEN_RESET < <(printf '%s' "$INPUT" | jq -r \
  '.rate_limits | select(. != null) |
   "\(.five_hour.used_percentage // "-") \(.five_hour.resets_at // "-") \(.seven_day.used_percentage // "-") \(.seven_day.resets_at // "-")"' 2>/dev/null)
if [ -n "$FIVE_H" ] && [ "$FIVE_H" != "-" ]; then
  FIVE_LEFT=""
  [ "$FIVE_RESET" != "-" ] && FIVE_LEFT="$(fmt_reset "$FIVE_RESET")"
  USAGE_BADGE="$(pct_color "$FIVE_H" "$C_MUTED")5h:${FIVE_H%.*}%${FIVE_LEFT:+($FIVE_LEFT)}${C_RESET}"
fi
if [ -n "$SEVEN_D" ] && [ "$SEVEN_D" != "-" ]; then
  SEVEN_LEFT=""
  [ "$SEVEN_RESET" != "-" ] && SEVEN_LEFT="$(fmt_reset "$SEVEN_RESET")"
  [ -n "$USAGE_BADGE" ] && USAGE_BADGE="$USAGE_BADGE "
  USAGE_BADGE="$USAGE_BADGE$(pct_color "$SEVEN_D" "$C_MUTED")wk:${SEVEN_D%.*}%${SEVEN_LEFT:+($SEVEN_LEFT)}${C_RESET}"
fi

# terminal-browser windows open anywhere, e.g. "browsers:2". Hidden if the
# count can't be read.
BROWSER_BADGE=""
BROWSERS=$(timeout 1 terminal-browser ls --all --json 2>/dev/null | jq -r '.browsers | length' 2>/dev/null)
[ -n "$BROWSERS" ] && BROWSER_BADGE="${C_MUTED}browsers:${BROWSERS}${C_RESET}"

OUT=""
for SEG in "$VIM_BADGE" "$DIR_BADGE" "$BRANCH_BADGE" "$CAVEMAN" "$CTX_BADGE" "$IDLE_BADGE" "$USAGE_BADGE" "$BROWSER_BADGE"; do
  [ -z "$SEG" ] && continue
  [ -n "$OUT" ] && OUT="$OUT "
  OUT="$OUT$SEG"
done
printf '%s' "$OUT"
