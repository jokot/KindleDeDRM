# Pinned versions, paths and persisted settings. No dependencies.

$AppVersion = '1.0'

# Versions known to work together (October 2026). Bump these for new releases.
$Pinned = @{
    Calibre     = '9.16.0'     # https://calibre-ebook.com/download_windows
    DeDrmTag    = 'v10.0.32'   # https://github.com/Satsuoni/DeDRM_tools/releases
    KindleBuild = 25218        # Kindle for Windows 1.0.25218 (tested)
    KfxInput    = '2.34.2'     # https://www.mobileread.com/forums/showthread.php?t=291290
}
$DeDrmRepo     = 'Satsuoni/DeDRM_tools'
$KindleStoreId = '9P8JQ0JJSTLL'
$KindlePkgName = 'AMZNKindle.AmazonKindleReadingApp'
$KfxInputUrl   = 'https://plugins.calibre-ebook.com/291290.zip'
$VcRedistUrl   = 'https://aka.ms/vs/17/release/vc_redist.x64.exe'
$StorePolicy   = 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore'

$AppDir       = Join-Path $env:LOCALAPPDATA 'kindle-dedrm'
$DownloadDir  = Join-Path $AppDir 'downloads'
$ToolsDir     = Join-Path $AppDir "tools\$($Pinned.DeDrmTag)"
$WorkDir      = Join-Path $AppDir 'work'
$ArchiveDir   = Join-Path $WorkDir 'archived_kfx'
$CalibreDir   = Join-Path $env:ProgramFiles 'Calibre2'
$Calibredb    = Join-Path $CalibreDir 'calibredb.exe'
$SettingsPath = Join-Path $AppDir 'settings.json'
$IndexPath    = Join-Path $AppDir 'index.json'

function Get-DefaultSettings {
    [pscustomobject]@{
        OutDir       = Join-Path $env:USERPROFILE 'Documents\Kindle EPUBs'
        Library      = Join-Path $env:USERPROFILE 'Calibre Library'
        StallSeconds = 300
    }
}

# Missing file or keys fall back to defaults; a corrupt file is renamed to .bad.
function Get-Settings {
    param([string]$Path = $SettingsPath)
    $settings = Get-DefaultSettings
    if (-not (Test-Path $Path)) { return $settings }
    try {
        $saved = Get-Content $Path -Raw | ConvertFrom-Json
    } catch {
        Move-Item $Path "$Path.bad" -Force
        if (Get-Command Warn -ErrorAction SilentlyContinue) { Warn "settings file was unreadable - renamed to $Path.bad, using defaults" }
        return $settings
    }
    foreach ($name in 'OutDir', 'Library', 'StallSeconds') {
        if ($saved.PSObject.Properties[$name] -and $saved.$name) { $settings.$name = $saved.$name }
    }
    $settings.StallSeconds = [int]$settings.StallSeconds
    $settings
}

function Save-Settings {
    param([Parameter(Mandatory)]$Settings, [string]$Path = $SettingsPath)
    $dir = Split-Path $Path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
    $Settings | Select-Object OutDir, Library, StallSeconds | ConvertTo-Json | Set-Content $Path
}
