#!/bin/bash
# claude-code-statusline - Custom status line for Claude Code CLI
# https://github.com/ueki-interpark/claude-code-statusline

input=$(cat)

# JSON parser using sed/grep (no external dependencies like jq)
get_json_value() {
  echo "$input" | sed 's/,/\n/g; s/[{}]//g; s/\[//g; s/\]//g' | sed 's/^ *//' | \
    grep "\"$1\"" | sed 's/.*"'"$1"'" *: *//; s/^ *"//; s/" *$//; s/ *$//' | \
    sed 's/\\\\/\\/g'
}

MODEL=$(get_json_value 'display_name')
MODEL="${MODEL:-unknown}"
COST=$(get_json_value 'total_cost_usd')
COST="${COST:-0}"
CWD=$(get_json_value 'cwd')

COST_FMT=$(printf '$%.4f' "$COST")

# Token-based context usage calculation (with fallback to integer percentages)
INPUT_TOKENS=$(get_json_value 'input_tokens')
OUTPUT_TOKENS=$(get_json_value 'output_tokens')
CACHE_CREATE=$(get_json_value 'cache_creation_input_tokens')
CACHE_READ=$(get_json_value 'cache_read_input_tokens')
CTX_WINDOW=$(get_json_value 'context_window_size')

if [ -n "$INPUT_TOKENS" ] && [ -n "$CTX_WINDOW" ] && [ "$CTX_WINDOW" -gt 0 ] 2>/dev/null; then
  USED_TOKENS=$(( ${INPUT_TOKENS:-0} + ${OUTPUT_TOKENS:-0} + ${CACHE_CREATE:-0} + ${CACHE_READ:-0} ))
  USED_PCT=$(awk "BEGIN {printf \"%.1f\", ($USED_TOKENS / $CTX_WINDOW) * 100}")
  REMAINING_PCT=$(awk "BEGIN {printf \"%.1f\", 100 - ($USED_TOKENS / $CTX_WINDOW) * 100}")
else
  # Fallback: use integer percentages from JSON
  USED_PCT=$(get_json_value 'used_percentage')
  USED_PCT="${USED_PCT:-0}.0"
  REMAINING_PCT=$(get_json_value 'remaining_percentage')
  REMAINING_PCT="${REMAINING_PCT:-0}.0"
fi
USED_PCT_INT=$(printf "%.0f" "$USED_PCT")

# Color definitions (use $'...' to embed actual escape characters)
CYAN=$'\033[36m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
RED=$'\033[31m'
MAGENTA=$'\033[35m'
DIM=$'\033[2m'
RESET=$'\033[0m'

# Context usage color coding
if [ "$USED_PCT_INT" -ge 80 ]; then
  CTX_COLOR="$RED"
elif [ "$USED_PCT_INT" -ge 50 ]; then
  CTX_COLOR="$YELLOW"
else
  CTX_COLOR="$GREEN"
fi

# Context usage progress bar
FILLED=$((USED_PCT_INT / 5))
EMPTY=$((20 - FILLED))
BAR=$(printf "%${FILLED}s" | tr ' ' '#')$(printf "%${EMPTY}s" | tr ' ' '-')

# Normalize backslashes to forward slashes (for Windows paths)
CWD=$(printf '%s' "$CWD" | tr '\\' '/')

# Normalize Windows drive letter (C:/Users/... -> /c/Users/...)
if [[ "$CWD" =~ ^([A-Za-z]):/ ]]; then
  CWD="/${BASH_REMATCH[1],,}${CWD:2}"
fi

# Shorten path to max 2 levels deep (replace $HOME with ~)
DIR="${CWD/#$HOME/\~}"
# Count slash-separated components
COMP_COUNT=$(printf '%s' "$DIR" | tr -cd '/' | wc -c)
if [ "$COMP_COUNT" -gt 3 ]; then
  LAST_TWO=$(printf '%s' "$DIR" | awk -F'/' '{print $(NF-1)"/"$NF}')
  if [[ "$DIR" == \~/* ]]; then
    SHORT_DIR="~/.../${LAST_TWO}"
  else
    SHORT_DIR="/.../${LAST_TWO}"
  fi
else
  SHORT_DIR="$DIR"
fi

# Get current Git branch
BRANCH=""
if [ -n "$CWD" ] && git -C "$CWD" rev-parse --git-dir >/dev/null 2>&1; then
  BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null)
fi

# Line 1: Location and branch (with icons)
if [ -n "$BRANCH" ]; then
  LINE1="🔀 ${CYAN}${SHORT_DIR}${RESET} ${DIM}on${RESET} 🌿 ${MAGENTA}${BRANCH}${RESET}"
else
  LINE1="📂 ${CYAN}${SHORT_DIR}${RESET}"
fi

# Line 2: Model, cost, and context usage
LINE2="🤖 ${DIM}${MODEL}${RESET} | 💰 ${GREEN}${COST_FMT}${RESET} | 🧠 ${CTX_COLOR}[${BAR}] ${USED_PCT}%${RESET} | 🔄 ${CTX_COLOR}${REMAINING_PCT}%${RESET}"

printf '%s\n' "$LINE1"
printf '%s\n' "$LINE2"
