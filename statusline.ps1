# claude-code-statusline - Custom status line for Claude Code CLI (PowerShell)
# https://github.com/ueki-interpark/claude-code-statusline

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$input = $Input | Out-String
$data = $input | ConvertFrom-Json

$Model = if ($data.model.display_name) { $data.model.display_name } else { "unknown" }
$Cost = if ($data.cost.total_cost_usd) { $data.cost.total_cost_usd } else { 0 }
$UsedPct = if ($data.context_window.used_percentage) { $data.context_window.used_percentage } else { 0 }
$RemainingPct = if ($data.context_window.remaining_percentage) { $data.context_window.remaining_percentage } else { 0 }
$Cwd = if ($data.cwd) { $data.cwd } else { "" }

$CostFmt = '$' + '{0:F4}' -f [double]$Cost

# Calculate adjusted percentages based on auto-compact threshold
# threshold = used + remaining (e.g. 95 if auto-compact at 95%)
$CompactThreshold = [double]$UsedPct + [double]$RemainingPct
if ($CompactThreshold -gt 0) {
    $AdjustedUsed = ([double]$UsedPct / $CompactThreshold) * 100
    $AdjustedRemaining = ([double]$RemainingPct / $CompactThreshold) * 100
} else {
    $AdjustedUsed = 0.0
    $AdjustedRemaining = 100.0
}
$AdjustedUsedFmt = '{0:F1}' -f $AdjustedUsed
$AdjustedRemainingFmt = '{0:F1}' -f $AdjustedRemaining
$AdjustedUsedInt = [math]::Round($AdjustedUsed)

# Emoji definitions (use codepoints to avoid encoding issues)
$ICON_SHUFFLE = [char]::ConvertFromUtf32(0x1F500)  # 🔀
$ICON_FOLDER  = [char]::ConvertFromUtf32(0x1F4C2)  # 📂
$ICON_BRANCH  = [char]::ConvertFromUtf32(0x1F33F)  # 🌿
$ICON_ROBOT   = [char]::ConvertFromUtf32(0x1F916)  # 🤖
$ICON_MONEY   = [char]::ConvertFromUtf32(0x1F4B0)  # 💰
$ICON_BRAIN   = [char]::ConvertFromUtf32(0x1F9E0)  # 🧠
$ICON_RECYCLE = [char]::ConvertFromUtf32(0x1F504)  # 🔄

# Color definitions (ANSI escape sequences)
$ESC = [char]27
$CYAN = "$ESC[36m"
$GREEN = "$ESC[32m"
$YELLOW = "$ESC[33m"
$RED = "$ESC[31m"
$MAGENTA = "$ESC[35m"
$DIM = "$ESC[2m"
$RESET = "$ESC[0m"

# Context usage color coding (based on adjusted percentage)
if ($AdjustedUsedInt -ge 80) {
    $CtxColor = $RED
} elseif ($AdjustedUsedInt -ge 50) {
    $CtxColor = $YELLOW
} else {
    $CtxColor = $GREEN
}

# Context usage progress bar (based on adjusted percentage)
$Filled = [math]::Floor($AdjustedUsedInt / 5)
$Empty = 20 - $Filled
$Bar = ('#' * $Filled) + ('-' * $Empty)

# Shorten path (replace $HOME with ~)
# Normalize to forward slashes before comparison
$HomeDir = ($env:USERPROFILE) -replace '\\', '/'
$CwdNorm = $Cwd -replace '\\', '/'
if ($CwdNorm -and $HomeDir -and $CwdNorm.StartsWith($HomeDir)) {
    $Dir = '~' + $CwdNorm.Substring($HomeDir.Length)
} else {
    $Dir = $CwdNorm
}

$Parts = $Dir -split '/'
if ($Parts.Count -gt 3) {
    $ShortDir = $Parts[0] + '/.../' + ($Parts[-2..-1] -join '/')
} else {
    $ShortDir = $Dir
}

# Get current Git branch
$Branch = ""
if ($Cwd -and (Get-Command git -ErrorAction SilentlyContinue)) {
    try {
        $Branch = git -C $Cwd branch --show-current 2>$null
    } catch {
        $Branch = ""
    }
}

# Line 1: Location and branch (with icons)
if ($Branch) {
    $Line1 = "${ICON_SHUFFLE} ${CYAN}${ShortDir}${RESET} ${DIM}on${RESET} ${ICON_BRANCH} ${MAGENTA}${Branch}${RESET}"
} else {
    $Line1 = "${ICON_FOLDER} ${CYAN}${ShortDir}${RESET}"
}

# Line 2: Model, cost, and context usage
$Line2 = "${ICON_ROBOT} ${DIM}${Model}${RESET} | ${ICON_MONEY} ${GREEN}${CostFmt}${RESET} | ${ICON_BRAIN} ${CtxColor}[${Bar}] ${AdjustedUsedFmt}%${RESET} | ${ICON_RECYCLE} ${CtxColor}${AdjustedRemainingFmt}%${RESET}"

Write-Host $Line1
Write-Host $Line2
