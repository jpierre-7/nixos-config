#!/bin/bash
# Statusline wrapper: caveman badge + vim mode indicator
# Reads Claude Code statusline JSON on stdin.

INPUT=$(cat)

# Gruvbox palette (dark, bright variants)
GB_RED=$'\033[38;2;251;73;52m'     # #fb4934
GB_GREEN=$'\033[38;2;184;187;38m'  # #b8bb26
GB_YELLOW=$'\033[38;2;250;189;47m' # #fabd2f
GB_BLUE=$'\033[38;2;131;165;152m'  # #83a598
GB_AQUA=$'\033[38;2;142;192;124m'  # #8ec07c
GB_GREY=$'\033[38;2;146;131;116m'  # #928374
GB_RESET=$'\033[0m'

CAVEMAN=""
if [ -x "$CAVEMAN_SCRIPT" ] || [ -f "$CAVEMAN_SCRIPT" ]; then
  CAVEMAN=$(printf '%s' "$INPUT" | bash "$CAVEMAN_SCRIPT" 2>/dev/null | sed $'s/\x1b\\[[0-9;]*m//g')
  [ -n "$CAVEMAN" ] && CAVEMAN="${GB_GREY}${CAVEMAN}${GB_RESET}"
fi

MODE=$(printf '%s' "$INPUT" | jq -r '.vim.mode // .editor.mode // empty' 2>/dev/null)

VIM_BADGE=""
case "$MODE" in
insert | INSERT | i) VIM_BADGE="${GB_GREEN}[INSERT]${GB_RESET}" ;;
normal | NORMAL | n) VIM_BADGE="${GB_BLUE}[NORMAL]${GB_RESET}" ;;
visual | VISUAL | v) VIM_BADGE="${GB_YELLOW}[VISUAL]${GB_RESET}" ;;
replace | REPLACE | r) VIM_BADGE="${GB_RED}[REPLACE]${GB_RESET}" ;;
esac

# Current dir as parent/name, e.g. "dev/SeatWatch"
DIR_BADGE=""
CWD=$(printf '%s' "$INPUT" | jq -r '.workspace.current_dir // .cwd // empty' 2>/dev/null)
if [ -n "$CWD" ]; then
  DIR_BADGE="${GB_GREY}$(basename "$(dirname "$CWD")")/$(basename "$CWD")${GB_RESET}"
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
    IDLE_BADGE="${GB_GREY}◷ ${IDLE}${GB_RESET}"
  fi
fi

# Git branch of current dir
BRANCH_BADGE=""
if [ -n "$CWD" ]; then
  BRANCH=$(git -C "$CWD" symbolic-ref --short HEAD 2>/dev/null ||
    git -C "$CWD" rev-parse --short HEAD 2>/dev/null)
  [ -n "$BRANCH" ] && BRANCH_BADGE="${GB_GREEN}${BRANCH}${GB_RESET}"
fi

# $2 (default green) under 50%, yellow under 80%, red above
pct_color() {
  local p=${1%.*}
  if [ "${p:-0}" -ge 80 ]; then
    printf '%s' "$GB_RED"
  elif [ "${p:-0}" -ge 50 ]; then
    printf '%s' "$GB_YELLOW"
  else printf '%s' "${2:-$GB_GREEN}"; fi
}

# Context window usage: tokens used + percent, e.g. "45.2k (5.0%)"
CTX_BADGE=""
read -r USED PCT < <(printf '%s' "$INPUT" | jq -r \
  '.context_window | select(.used_percentage != null) |
   "\(.total_input_tokens + .total_output_tokens) \(.used_percentage)"' 2>/dev/null)
if [ -n "$USED" ]; then
  CTX_BADGE=$(awk -v u="$USED" -v p="$PCT" 'BEGIN { printf "%.1fk (%.1f%%)", u/1000, p }')
  CTX_BADGE="$(pct_color "$PCT")${CTX_BADGE}${GB_RESET}"
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
  USAGE_BADGE="$(pct_color "$FIVE_H" "$GB_GREY")5h:${FIVE_H%.*}%${FIVE_LEFT:+($FIVE_LEFT)}${GB_RESET}"
fi
if [ -n "$SEVEN_D" ] && [ "$SEVEN_D" != "-" ]; then
  SEVEN_LEFT=""
  [ "$SEVEN_RESET" != "-" ] && SEVEN_LEFT="$(fmt_reset "$SEVEN_RESET")"
  [ -n "$USAGE_BADGE" ] && USAGE_BADGE="$USAGE_BADGE "
  USAGE_BADGE="$USAGE_BADGE$(pct_color "$SEVEN_D" "$GB_GREY")wk:${SEVEN_D%.*}%${SEVEN_LEFT:+($SEVEN_LEFT)}${GB_RESET}"
fi

OUT=""
for SEG in "$VIM_BADGE" "$DIR_BADGE" "$BRANCH_BADGE" "$CAVEMAN" "$CTX_BADGE" "$IDLE_BADGE" "$USAGE_BADGE"; do
  [ -z "$SEG" ] && continue
  [ -n "$OUT" ] && OUT="$OUT "
  OUT="$OUT$SEG"
done
printf '%s' "$OUT"
