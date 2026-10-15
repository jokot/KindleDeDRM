<#
.SYNOPSIS
    KindleDeDRM - turn Kindle books you own into DRM-free EPUB files (Windows 11).

.DESCRIPTION
    Run with no arguments for the interactive menu, or with a command:
    check | install [parts] | convert | clean | help
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Command = '',

    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [string[]]$Component,

    [string]$OutDir,
    [string]$Library,
    [int]$StallSeconds,
    [switch]$Yes,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

foreach ($file in 'Config', 'Ui', 'Native', 'Prereqs', 'Library', 'Pipeline', 'Menu') { . (Join-Path $PSScriptRoot "lib\$file.ps1") }

function Show-Help {
    Say @"

KindleDeDRM $AppVersion - turn Kindle books you own into DRM-free EPUB files (Windows 11)

USAGE
  KindleDeDRM                    open the menu
  KindleDeDRM <command> [options]

COMMANDS
  check                  show what is required and what is already installed
  install [component..]  install missing requirements (default: all)
                            components: vcredist, calibre, kindle, dedrm-tools,
                                        dedrm-plugin, kfx-input
                            optional:   store-updates-off, store-updates-on
  convert                convert every new book to EPUB
  clean                  delete temporary files left by the extractor
  help                   show this help

OPTIONS (this run only; use the Settings menu to change them permanently)
  -OutDir <path>         where EPUBs are saved
  -Library <path>        Calibre library to use
  -StallSeconds <n>      skip a book whose extraction hangs this long
  -Yes                   answer yes to every question
  -Force                 reinstall components that are already installed
"@
}

function Invoke-ConvertAll($settings) {
    $missing = @(Get-MissingRequirements)
    if ($missing) {
        $missing | ForEach-Object { Fail "$($_.Name) - run: KindleDeDRM install $($_.Component)" }
        throw 'requirements missing'
    }
    Stop-AppIfRunning 'calibre' 'Calibre'
    $pending = @(Get-BookIndex -Library $settings.Library | Where-Object { 'new', 'extracted', 'in Calibre' -contains $_.Status })
    if ($pending.Count -eq 0) { Ok 'nothing new to convert'; return }
    Step "Converting $($pending.Count) book(s)"
    $results = @(Invoke-BookAction -Books $pending -Action Convert -Settings $settings)
    Step 'Summary'
    foreach ($r in $results) {
        if ($r.Ok) { Ok "$($r.Title)" } else { Fail "$($r.Title) - $($r.Message)" }
    }
    Say "  EPUB folder: $($settings.OutDir)"
}

try {
    try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
    $env:PYTHONIOENCODING = 'utf-8'
    $script:AssumeYes = [bool]$Yes
    New-Item -ItemType Directory -Force $AppDir, $DownloadDir, $WorkDir | Out-Null

    $settings = Get-Settings
    if ($OutDir) { $settings.OutDir = $OutDir }
    if ($Library) { $settings.Library = $Library }
    if ($StallSeconds) { $settings.StallSeconds = $StallSeconds }

    switch ($Command.ToLower()) {
        ''        { Start-MainMenu -Settings $settings }
        'check'   { Show-Requirements }
        'install' { Invoke-Install $Component -Force:$Force; Show-Requirements }
        'convert' { Invoke-ConvertAll $settings }
        'clean'   { Invoke-Clean }
        'help'    { Show-Help }
        default   { throw "unknown command '$Command' - run: KindleDeDRM help" }
    }
} catch {
    Write-Host "`nError: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
