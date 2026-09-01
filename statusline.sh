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

# Flattened copy of the input, used to read nested objects safely
# (e.g. "used_percentage" exists under both context_window and rate_limits)
FLAT=$(printf '%s' "$input" | tr -d ' \t\n')

# Extract "key": value from a nested object block (pure bash, no jq)
# $1: object block, $2: key name
get_block_value() {
  local seg="$1"
  case "$seg" in
    *"\"$2\":"*) seg="${seg#*\"$2\":}" ;;
    *) return ;;
  esac
  seg="${seg%%,*}"
  seg="${seg%%\}*}"
  seg="${seg%\"}"
  seg="${seg#\"}"
  printf '%s' "$seg"
}

# Extract a nested object block by key ("key":{...})
# $1: parent block, $2: key name
get_block() {
  local seg="$1"
  case "$seg" in
    *"\"$2\":{"*) seg="${seg#*\"$2\":\{}" ;;
    *) return ;;
  esac
  printf '%s' "${seg%%\}*}"
}

# Reasoning effort level (only present when the model supports it)
EFFORT=$(get_block_value "$(get_block "$FLAT" 'effort')" 'level')

# Claude.ai subscription usage limits (only present for subscribers
# after the first API response)
RATE_BLOCK=$(get_block "$FLAT" 'rate_limits')
FIVE_PCT=""
WEEK_PCT=""
if [ -n "$RATE_BLOCK" ]; then
  # get_block stops at the first "}", so re-scan the raw flat input per window
  FIVE_BLOCK=$(get_block "$FLAT" 'five_hour')
  WEEK_BLOCK=$(get_block "$FLAT" 'seven_day')
  FIVE_PCT=$(get_block_value "$FIVE_BLOCK" 'used_percentage')
  FIVE_RESET=$(get_block_value "$FIVE_BLOCK" 'resets_at')
  WEEK_PCT=$(get_block_value "$WEEK_BLOCK" 'used_percentage')
  WEEK_RESET=$(get_block_value "$WEEK_BLOCK" 'resets_at')
fi

# Prompt cache stats (added in Claude Code 2.1.251)
CACHE_BLOCK=$(get_block "$FLAT" 'prompt_cache')
CACHE_OBSERVED=$(get_block_value "$CACHE_BLOCK" 'caching_observed')
CACHE_WARM=$(get_block_value "$CACHE_BLOCK" 'warm')
CACHE_RATIO=$(get_block_value "$CACHE_BLOCK" 'hit_ratio')
CACHE_RECACHE=$(get_block_value "$CACHE_BLOCK" 'recache_tokens_if_cold')
CACHE_REQUESTS=$(get_block_value "$CACHE_BLOCK" 'requests')

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

# Usage color coding by percentage (green < 50 <= yellow < 80 <= red)
pct_color() {
  local p
  p=$(printf "%.0f" "$1" 2>/dev/null) || p=0
  if [ "$p" -ge 80 ] 2>/dev/null; then
    printf '%s' "$RED"
  elif [ "$p" -ge 50 ] 2>/dev/null; then
    printf '%s' "$YELLOW"
  else
    printf '%s' "$GREEN"
  fi
}

# Hours left until a Unix epoch timestamp (e.g. "101h", "<1h")
fmt_hours() {
  local target=$1 now diff h
  now=$(date +%s)
  diff=$(( target - now ))
  [ "$diff" -lt 0 ] && diff=0
  h=$(( diff / 3600 ))
  if [ "$h" -lt 1 ]; then
    printf '<1h'
  else
    printf '%dh' "$h"
  fi
}

# Box meter for a percentage (e.g. "████░░░░░░")
# tr can choke on multibyte chars, so build the string in bash
repeat_char() {
  local n=$1 c=$2 out="" i
  for (( i = 0; i < n; i++ )); do
    out="${out}${c}"
  done
  printf '%s' "$out"
}

make_meter() {
  local p w filled
  p=$(printf "%.0f" "$1" 2>/dev/null) || p=0
  w=$2
  [ "$p" -lt 0 ] 2>/dev/null && p=0
  [ "$p" -gt 100 ] 2>/dev/null && p=100
  filled=$(( p * w / 100 ))
  # Keep a single cell lit for any non-zero usage
  [ "$filled" -eq 0 ] && [ "$p" -gt 0 ] && filled=1
  printf '%s%s' "$(repeat_char "$filled" '█')" "$(repeat_char $(( w - filled )) '░')"
}

# Context usage color coding (based on adjusted percentage)
if [ "$ADJUSTED_USED_INT" -ge 80 ]; then
  CTX_COLOR="$RED"
elif [ "$ADJUSTED_USED_INT" -ge 50 ]; then
  CTX_COLOR="$YELLOW"
else
  CTX_COLOR="$GREEN"
fi

# Context usage progress bar (based on adjusted percentage)
# 10 cells = 10% per cell
CTX_BAR_WIDTH="${CLAUDE_CTX_BAR_WIDTH:-10}"
FILLED=$(( ADJUSTED_USED_INT * CTX_BAR_WIDTH / 100 ))
[ "$FILLED" -gt "$CTX_BAR_WIDTH" ] && FILLED="$CTX_BAR_WIDTH"
[ "$FILLED" -lt 0 ] && FILLED=0
EMPTY=$(( CTX_BAR_WIDTH - FILLED ))
BAR=$(printf "%${FILLED}s" | tr ' ' '#')$(printf "%${EMPTY}s" | tr ' ' '-')

# Normalize backslashes to forward slashes (for Windows paths)
CWD=$(printf '%s' "$CWD" | tr '\\' '/')

# Normalize Windows drive letter (C:/Users/... -> /c/Users/...)
if [[ "$CWD" =~ ^([A-Za-z]):/ ]]; then
  CWD="/${BASH_REMATCH[1],,}${CWD:2}"
fi

# Shorten path to max 2 levels deep (replace $HOME with ~)
DIR="${CWD/#$HOME/~}"
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

# Effort level segment (higher effort stands out)
EFFORT_SEG=""
if [ -n "$EFFORT" ]; then
  case "$EFFORT" in
    xhigh|max) EFFORT_COLOR="$MAGENTA" ;;
    high)      EFFORT_COLOR="$YELLOW" ;;
    *)         EFFORT_COLOR="$GREEN" ;;
  esac
  EFFORT_SEG=" | ⚡ ${EFFORT_COLOR}${EFFORT}${RESET}"
fi

# Line 2: Model, effort, tokens, and context usage
LINE2="🤖 ${DIM}${MODEL}${RESET}${EFFORT_SEG} | 📊 ${GREEN}${USED_FMT}${RESET} | 🧠 ${CTX_COLOR}[${BAR}] ${ADJUSTED_USED}%${RESET} | 🔄 ${CTX_COLOR}${ADJUSTED_REMAINING}%${RESET}"

# Line 3: Subscription usage limits, compact (omitted when not available)
# Meter width in cells; 8 cells = 12.5% per cell
RATE_METER_WIDTH="${CLAUDE_RATE_METER_WIDTH:-8}"
RATE_SEG=""
if [ -n "$FIVE_PCT" ]; then
  FIVE_COLOR=$(pct_color "$FIVE_PCT")
  FIVE_METER=$(make_meter "$FIVE_PCT" "$RATE_METER_WIDTH")
  FIVE_PCT_INT=$(printf "%.0f" "$FIVE_PCT" 2>/dev/null) || FIVE_PCT_INT=0
  RATE_SEG=$(printf '5h %s[%s] %3d%%%s' "$FIVE_COLOR" "$FIVE_METER" "$FIVE_PCT_INT" "$RESET")
fi
if [ -n "$WEEK_PCT" ]; then
  WEEK_COLOR=$(pct_color "$WEEK_PCT")
  WEEK_METER=$(make_meter "$WEEK_PCT" "$RATE_METER_WIDTH")
  WEEK_PCT_INT=$(printf "%.0f" "$WEEK_PCT" 2>/dev/null) || WEEK_PCT_INT=0
  [ -n "$RATE_SEG" ] && RATE_SEG="${RATE_SEG} ${DIM}·${RESET} "
  RATE_SEG="${RATE_SEG}$(printf '7d %s[%s] %3d%%%s' "$WEEK_COLOR" "$WEEK_METER" "$WEEK_PCT_INT" "$RESET")"
  if [ -n "$WEEK_RESET" ]; then
    RATE_SEG="${RATE_SEG} ${DIM}($(fmt_hours "$WEEK_RESET"))${RESET}"
  fi
fi

# Prompt cache warning (Claude Code 2.1.251+, "prompt_cache" field).
# Shown only when something is actually wrong: stays silent while the cache is
# warm and hitting, so it costs no space in the common case.
# The hit-ratio warning needs a minimum number of requests, because a ratio
# below the threshold is normal for the first few turns of any session.
CACHE_WARN_PCT="${CLAUDE_CACHE_WARN_PCT:-50}"
CACHE_WARN_MIN_REQUESTS="${CLAUDE_CACHE_WARN_MIN_REQUESTS:-5}"
CACHE_SEG=""
if [ "$CACHE_OBSERVED" = "true" ]; then
  CACHE_PCT=$(awk "BEGIN {printf \"%.0f\", ${CACHE_RATIO:-0} * 100}")
  if [ "$CACHE_WARM" != "true" ]; then
    # Cache expired (idle past its TTL): the next request rebuilds the whole
    # prefix no matter how small the message, so batching pays off here.
    CACHE_SEG="${YELLOW}⚠️  キャッシュ切れ${RESET} ${DIM}次の1回に +$(fmt_tokens "${CACHE_RECACHE:-0}") · まとめて送る${RESET}"
  elif [ "${CACHE_REQUESTS:-0}" -ge "$CACHE_WARN_MIN_REQUESTS" ] 2>/dev/null \
    && [ "$CACHE_PCT" -lt "$CACHE_WARN_PCT" ] 2>/dev/null; then
    # Hitting poorly well into a session: something keeps invalidating the
    # prefix. The cause is not knowable from here, so point at /cost, which
    # breaks down the misses (Claude Code 2.1.251+).
    CACHE_SEG="${RED}⚠️  キャッシュ低下 ${CACHE_PCT}%${RESET} ${DIM}毎回ほぼ全量を再送中 · /cost で確認${RESET}"
  fi
fi

LINE3=""
[ -n "$RATE_SEG" ] && LINE3="⏱️  ${RATE_SEG}"
if [ -n "$CACHE_SEG" ]; then
  if [ -n "$LINE3" ]; then
    LINE3="${LINE3} ${DIM}·${RESET} ${CACHE_SEG}"
  else
    LINE3="$CACHE_SEG"
  fi
fi

printf '%s\n' "$LINE1"
printf '%s\n' "$LINE2"
[ -n "$LINE3" ] && printf '%s\n' "$LINE3"

exit 0
