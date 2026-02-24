# claude-code-statusline installer (PowerShell)
# Copies statusline.ps1 to ~/.claude/ and configures settings.json

$ErrorActionPreference = "Stop"

$ClaudeDir = Join-Path $env:USERPROFILE ".claude"
$SettingsFile = Join-Path $ClaudeDir "settings.json"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SourceScript = Join-Path $ScriptDir "statusline.ps1"
$DestScript = Join-Path $ClaudeDir "statusline.ps1"

# Check source file exists
if (-not (Test-Path $SourceScript)) {
    Write-Error "Error: statusline.ps1 not found at $SourceScript"
    exit 1
}

# Ensure ~/.claude directory exists
if (-not (Test-Path $ClaudeDir)) {
    New-Item -ItemType Directory -Path $ClaudeDir -Force | Out-Null
}

# Copy statusline.ps1
Copy-Item -Path $SourceScript -Destination $DestScript -Force
Write-Host "Copied statusline.ps1 to $DestScript"

# statusLine command
$StatusLineCommand = 'powershell -NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $env:USERPROFILE '.claude\statusline.ps1') + '"'
$StatusLineConfig = @{
    type    = "command"
    command = $StatusLineCommand
}

# Update settings.json
if (Test-Path $SettingsFile) {
    # Backup existing settings
    $BackupFile = "$SettingsFile.bak"
    Copy-Item -Path $SettingsFile -Destination $BackupFile -Force
    Write-Host "Backed up settings.json to $BackupFile"

    # Read and update settings
    $Settings = Get-Content -Path $SettingsFile -Raw | ConvertFrom-Json
    # Remove existing statusLine property if present, then add new one
    if ($Settings.PSObject.Properties['statusLine']) {
        $Settings.PSObject.Properties.Remove('statusLine')
    }
    $Settings | Add-Member -NotePropertyName 'statusLine' -NotePropertyValue $StatusLineConfig
    $Settings | ConvertTo-Json -Depth 10 | Set-Content -Path $SettingsFile -Encoding UTF8
} else {
    # Create new settings.json
    $Settings = @{
        statusLine = $StatusLineConfig
    }
    $Settings | ConvertTo-Json -Depth 10 | Set-Content -Path $SettingsFile -Encoding UTF8
}

Write-Host "Updated $SettingsFile with statusLine configuration"
Write-Host ""
Write-Host "Installation complete! Restart Claude Code to see the status line."
