# Adds a dot-source line for cc.ps1 to your PowerShell $PROFILE (idempotent).
# Run with:  pwsh -File install.ps1

$cc = Join-Path $PSScriptRoot 'cc.ps1'
if (-not (Test-Path $cc)) { throw "cc.ps1 not found next to this installer: $cc" }

$line = ". `"$cc`""
$profileDir = Split-Path $PROFILE
if (-not (Test-Path $profileDir)) { New-Item -ItemType Directory -Force -Path $profileDir | Out-Null }
if (-not (Test-Path $PROFILE)) { New-Item -ItemType File -Force -Path $PROFILE | Out-Null }

if ((Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue) -match [regex]::Escape($cc)) {
    "cc3x3 already sourced in $PROFILE"
} else {
    Add-Content $PROFILE "`n# cc3x3`n$line"
    "Added to $PROFILE : $line"
}
"Open a new Terminal window (or run `. `$PROFILE`) and type `cc`."
