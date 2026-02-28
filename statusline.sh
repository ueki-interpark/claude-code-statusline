#!/bin/bash
# claude-code-statusline - Custom status line for Claude Code CLI
# https://github.com/ueki-interpark/claude-code-statusline

input=$(cat)

MODEL=$(echo "$input" | jq -r '.model.display_name // "unknown"')
COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
USED_PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0')
REMAINING_PCT=$(echo "$input" | jq -r '.context_window.remaining_percentage // 0')
CWD=$(echo "$input" | jq -r '.cwd // ""')

COST_FMT=$(printf '$%.4f' "$COST")

# Calculate adjusted percentages based on auto-compact threshold
# threshold = used + remaining (e.g. 95 if auto-compact at 95%)
COMPACT_THRESHOLD=$(awk "BEGIN {printf \"%.0f\", $USED_PCT + $REMAINING_PCT}")
if [ "$COMPACT_THRESHOLD" -gt 0 ]; then
  ADJUSTED_USED=$(awk "BEGIN {printf \"%.1f\", ($USED_PCT / $COMPACT_THRESHOLD) * 100}")
  ADJUSTED_REMAINING=$(awk "BEGIN {printf \"%.1f\", ($REMAINING_PCT / $COMPACT_THRESHOLD) * 100}")
else
  ADJUSTED_USED="0.0"
  ADJUSTED_REMAINING="100.0"
fi
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
CWD="${CWD//\\//}"

# Shorten path to max 2 levels deep (replace $HOME with ~)
DIR="${CWD/#$HOME/~}"
IFS='/' read -ra PARTS <<< "$DIR"
DEPTH=${#PARTS[@]}
if [ "$DEPTH" -gt 3 ]; then
  SHORT_DIR="${PARTS[0]}/.../$(IFS='/'; echo "${PARTS[*]: -2:2}")"
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
LINE2="🤖 ${DIM}${MODEL}${RESET} | 💰 ${GREEN}${COST_FMT}${RESET} | 🧠 ${CTX_COLOR}[${BAR}] ${ADJUSTED_USED}%${RESET} | 🔄 ${CTX_COLOR}${ADJUSTED_REMAINING}%${RESET}"

printf '%s\n' "$LINE1"
printf '%s\n' "$LINE2"
