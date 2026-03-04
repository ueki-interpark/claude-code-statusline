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
CWD=$(get_json_value 'cwd')

# Auto-compact threshold from env var (default 95%)
COMPACT_THRESHOLD="${CLAUDE_AUTOCOMPACT_PCT_OVERRIDE:-95}"

# Token-based precise usage, normalized to auto-compact threshold
INPUT_TOKENS=$(get_json_value 'input_tokens')
OUTPUT_TOKENS=$(get_json_value 'output_tokens')
CACHE_CREATE=$(get_json_value 'cache_creation_input_tokens')
CACHE_READ=$(get_json_value 'cache_read_input_tokens')
CTX_WINDOW=$(get_json_value 'context_window_size')
[[ -z "$INPUT_TOKENS" || "$INPUT_TOKENS" == "null" ]] && INPUT_TOKENS=0
[[ -z "$OUTPUT_TOKENS" || "$OUTPUT_TOKENS" == "null" ]] && OUTPUT_TOKENS=0
[[ -z "$CACHE_CREATE" || "$CACHE_CREATE" == "null" ]] && CACHE_CREATE=0
[[ -z "$CACHE_READ" || "$CACHE_READ" == "null" ]] && CACHE_READ=0
[[ -z "$CTX_WINDOW" || "$CTX_WINDOW" == "null" ]] && CTX_WINDOW=0

USED_TOKENS=$(( INPUT_TOKENS + OUTPUT_TOKENS + CACHE_CREATE + CACHE_READ ))

if [ "$CTX_WINDOW" -gt 0 ] 2>/dev/null && awk "BEGIN {exit !($COMPACT_THRESHOLD > 0)}"; then
  RAW_PCT=$(awk "BEGIN {printf \"%.4f\", ($USED_TOKENS / $CTX_WINDOW) * 100}")
  ADJUSTED_USED=$(awk "BEGIN {printf \"%.1f\", ($RAW_PCT / $COMPACT_THRESHOLD) * 100}")
  ADJUSTED_REMAINING=$(awk "BEGIN {printf \"%.1f\", 100 - ($RAW_PCT / $COMPACT_THRESHOLD) * 100}")
else
  ADJUSTED_USED="0.0"
  ADJUSTED_REMAINING="100.0"
fi

# Format token counts for display (e.g. 15234 -> "15.2K", 1234567 -> "1.2M")
fmt_tokens() {
  local n=$1
  if [ "$n" -ge 1000000 ] 2>/dev/null; then
    awk "BEGIN {printf \"%.1fM\", $n / 1000000}"
  elif [ "$n" -ge 1000 ] 2>/dev/null; then
    awk "BEGIN {printf \"%.1fK\", $n / 1000}"
  else
    printf '%s' "$n"
  fi
}
USED_FMT=$(fmt_tokens "$USED_TOKENS")
ADJUSTED_USED_INT=$(printf "%.0f" "$ADJUSTED_USED")

# Color definitions (use $'...' to embed actual escape characters)
CYAN=$'\033[36m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
RED=$'\033[31m'
MAGENTA=$'\033[35m'
DIM=$'\033[2m'
RESET=$'\033[0m'

# Context usage color coding (based on adjusted percentage)
if [ "$ADJUSTED_USED_INT" -ge 80 ]; then
  CTX_COLOR="$RED"
elif [ "$ADJUSTED_USED_INT" -ge 50 ]; then
  CTX_COLOR="$YELLOW"
else
  CTX_COLOR="$GREEN"
fi

# Context usage progress bar (based on adjusted percentage)
FILLED=$((ADJUSTED_USED_INT / 5))
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

# Line 2: Model, tokens, and context usage
LINE2="🤖 ${DIM}${MODEL}${RESET} | 📊 ${GREEN}${USED_FMT}${RESET} | 🧠 ${CTX_COLOR}[${BAR}] ${ADJUSTED_USED}%${RESET} | 🔄 ${CTX_COLOR}${ADJUSTED_REMAINING}%${RESET}"

printf '%s\n' "$LINE1"
printf '%s\n' "$LINE2"
