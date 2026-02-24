#!/bin/bash
# claude-code-statusline - Custom status line for Claude Code CLI
# https://github.com/ueki-interpark/claude-code-statusline

input=$(cat)

MODEL=$(echo "$input" | jq -r '.model.display_name // "unknown"')
COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
USED_PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0')
CWD=$(echo "$input" | jq -r '.cwd // ""')

COST_FMT=$(printf '$%.4f' "$COST")
USED_INT=$(printf "%.0f" "$USED_PCT")

# Color definitions
CYAN='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
MAGENTA='\033[35m'
DIM='\033[2m'
RESET='\033[0m'

# Context usage color coding
if [ "$USED_INT" -ge 80 ]; then
  CTX_COLOR="$RED"
elif [ "$USED_INT" -ge 50 ]; then
  CTX_COLOR="$YELLOW"
else
  CTX_COLOR="$GREEN"
fi

# Context usage progress bar
FILLED=$((USED_INT / 5))
EMPTY=$((20 - FILLED))
BAR=$(printf "%${FILLED}s" | tr ' ' '#')$(printf "%${EMPTY}s" | tr ' ' '-')

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
  LINE1="\U0001F500 ${CYAN}${SHORT_DIR}${RESET} ${DIM}on${RESET} \U0001F33F ${MAGENTA}${BRANCH}${RESET}"
else
  LINE1="\U0001F4C2 ${CYAN}${SHORT_DIR}${RESET}"
fi

# Line 2: Model, cost, and context usage
LINE2="\U0001F916 ${DIM}${MODEL}${RESET} | \U0001F4B0 ${GREEN}${COST_FMT}${RESET} | \U0001F9E0 ${CTX_COLOR}[${BAR}] ${USED_INT}%${RESET}"

echo -e "$LINE1"
echo -e "$LINE2"
