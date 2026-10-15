<#
.SYNOPSIS
    kindle-dedrm - turn Kindle books you own into DRM-free EPUB files (Windows 11).

.DESCRIPTION
    Pipeline: Kindle for Windows -> Satsuoni's MSIXKFXArchiver (extract + decrypt)
              -> Calibre (DeDRM + KFX Input plugins) -> EPUB.
    Run "kindle-dedrm help" for commands.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('check', 'install', 'prepare', 'convert', 'clean', 'help')]
    [string]$Command = 'help',

    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [string[]]$Component,

    [string]$Library = (Join-Path $env:USERPROFILE 'Calibre Library'),
    [string]$OutDir = (Join-Path $env:USERPROFILE 'Documents\Kindle EPUBs'),
    [int]$StallSeconds = 300,
    [switch]$Yes,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ---------------------------------------------------------------------------
# Versions known to work together (October 2026). Bump these for new releases.
# ---------------------------------------------------------------------------
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

$AppDir      = Join-Path $env:LOCALAPPDATA 'kindle-dedrm'
$DownloadDir = Join-Path $AppDir 'downloads'
$ToolsDir    = Join-Path $AppDir "tools\$($Pinned.DeDrmTag)"
$WorkDir     = Join-Path $AppDir 'work'
$ArchiveDir  = Join-Path $WorkDir 'archived_kfx'
$CalibreDir  = Join-Path $env:ProgramFiles 'Calibre2'
$Calibredb   = Join-Path $CalibreDir 'calibredb.exe'

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
function Say($msg)  { Write-Host $msg }
function Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Ok($msg)   { Write-Host "  [ok]   $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "  [warn] $msg" -ForegroundColor Yellow }
function Fail($msg) { Write-Host "  [fail] $msg" -ForegroundColor Red }
function Show-Value($v) { if ($v) { "$v" } else { '-' } }

function Confirm-Step($question) {
    if ($Yes) { return $true }
    $answer = Read-Host "  $question [Y/n]"
    return ($answer -eq '' -or $answer -match '^[Yy]')
}

# Runs a native exe without PowerShell 5.1 turning its stderr into terminating errors.
function Invoke-Native {
    param([string]$Exe, [string[]]$Arguments, [switch]$StdoutOnly)
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $lines = & $Exe @Arguments 2>&1
        if ($StdoutOnly) { $lines = $lines | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] } }
        $text = ($lines | ForEach-Object { "$_" }) -join "`n"
    } finally { $ErrorActionPreference = $old }
    [pscustomobject]@{ Output = $text; Code = $LASTEXITCODE }
}

function Invoke-Elevated($file, $arguments) {
    $p = Start-Process $file -ArgumentList $arguments -Verb RunAs -Wait -PassThru
    $p.ExitCode
}

function Stop-AppIfRunning($process, $label) {
    $p = Get-Process $process -ErrorAction SilentlyContinue
    if (-not $p) { return }
    if (-not (Confirm-Step "$label is running and must be closed. Close it now?")) {
        throw "close $label and run the command again"
    }
    $p | Stop-Process -Force
    Start-Sleep -Seconds 2
    Ok "closed $label"
}

# ---------------------------------------------------------------------------
# Detection
# ---------------------------------------------------------------------------
function Get-WindowsBuild { [int](Get-CimInstance Win32_OperatingSystem).BuildNumber }

function Get-VcRedistVersion {
    $k = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\X64' -ErrorAction SilentlyContinue
    if ($k -and $k.Installed -eq 1) { [version]($k.Version.TrimStart('v')) }
}

function Get-KindlePackage { Get-AppxPackage -Name $KindlePkgName -ErrorAction SilentlyContinue | Select-Object -First 1 }

function Get-KindleBuild {
    $p = Get-KindlePackage
    if ($p) { ([version]$p.Version).Build }
}

function Get-KindleContentDir {
    $p = Get-KindlePackage
    if ($p) { Join-Path $env:LOCALAPPDATA "Packages\$($p.PackageFamilyName)\LocalState\Classic\Content" }
}

function Get-CalibreVersion {
    $exe = Join-Path $CalibreDir 'calibre.exe'
    if (Test-Path $exe) { [version](Get-Item $exe).VersionInfo.ProductVersion }
}

$script:PluginCache = $null
function Get-CalibrePlugins {
    if ($null -eq $script:PluginCache) {
        $script:PluginCache = @{}
        $cc = Join-Path $CalibreDir 'calibre-customize.exe'
        if (Test-Path $cc) {
            foreach ($line in ((Invoke-Native $cc @('-l') -StdoutOnly).Output -split "`n")) {
                if ($line -match '^\S.*?\s{2,}(DeDRM|KFX Input)\s+\((\d+), (\d+), (\d+)\)') {
                    $script:PluginCache[$Matches[1]] = "$($Matches[2]).$($Matches[3]).$($Matches[4])"
                }
            }
        }
    }
    $script:PluginCache
}

# Each extractor build only works with one Kindle build, e.g. MSIXKFXArchiver_x64_1_25218.exe
function Find-Archiver {
    $build = Get-KindleBuild
    if (-not $build -or -not (Test-Path $ToolsDir)) { return }
    Get-ChildItem $ToolsDir -Filter 'MSIXKFXArchiver*.exe' |
        Where-Object { $_.Name -match "_$build(\D|$)" } | Select-Object -First 1
}

function Test-StoreUpdatesOff {
    $v = Get-ItemProperty $StorePolicy -Name AutoDownload -ErrorAction SilentlyContinue
    $v -and $v.AutoDownload -eq 2
}

function Get-KindleBooks {
    $content = Get-KindleContentDir
    if (-not $content -or -not (Test-Path $content)) { return }
    Get-ChildItem $content -Directory -Filter '*_EBOK' | ForEach-Object {
        $size = (Get-ChildItem $_.FullName -File | Measure-Object Length -Sum).Sum
        [pscustomobject]@{
            Name     = $_.Name
            Asin     = $_.Name -replace '_EBOK$'
            FullName = $_.FullName
            Complete = Test-Path (Join-Path $_.FullName "$($_.Name).azw")
            SizeMB   = [math]::Round($size / 1MB, 1)
        }
    }
}

function Get-LibraryBooks {
    if (-not (Test-Path (Join-Path $Library 'metadata.db'))) { return }
    $r = Invoke-Native $Calibredb @('list', '--with-library', $Library, '--fields', 'title,authors,formats,identifiers', '--for-machine') -StdoutOnly
    if (-not $r.Output.Trim()) { return }
    $books = $r.Output | ConvertFrom-Json
    $books
}

function Get-Requirements {
    $plugins  = Get-CalibrePlugins
    $kindle   = Get-KindlePackage
    $calibre  = Get-CalibreVersion
    $winBuild = Get-WindowsBuild
    $vc       = Get-VcRedistVersion
    $archiver = Find-Archiver
    $hasTools = Test-Path (Join-Path $ToolsDir 'DeDRM_plugin.zip')
    $dedrmWant = $Pinned.DeDrmTag.TrimStart('v')
    $archiverHave = if ($archiver) { $archiver.Name } elseif ($kindle -and $hasTools) { "none for build $(Get-KindleBuild)" } else { $null }

    @(
        [pscustomobject]@{ Name = 'Windows 11'; Component = '-'; Need = 'build 22000+'
                           Have = "build $winBuild"; Ok = ($winBuild -ge 22000) }
        [pscustomobject]@{ Name = 'Visual C++ runtime (x64)'; Component = 'vcredist'; Need = '14.20+'
                           Have = (Show-Value $vc); Ok = ($vc -and $vc -ge [version]'14.20') }
        [pscustomobject]@{ Name = 'Calibre'; Component = 'calibre'; Need = "$($Pinned.Calibre) (min 6.0)"
                           Have = (Show-Value $calibre); Ok = ($calibre -and $calibre -ge [version]'6.0') }
        [pscustomobject]@{ Name = 'Kindle for Windows'; Component = 'kindle'; Need = "1.0.$($Pinned.KindleBuild) (tested)"
                           Have = (Show-Value $(if ($kindle) { $kindle.Version })); Ok = [bool]$kindle }
        [pscustomobject]@{ Name = 'DeDRM tools (Satsuoni)'; Component = 'dedrm-tools'; Need = $Pinned.DeDrmTag
                           Have = (Show-Value $(if ($hasTools) { $Pinned.DeDrmTag })); Ok = $hasTools }
        [pscustomobject]@{ Name = 'Extractor for your Kindle'; Component = 'dedrm-tools'; Need = 'same build as Kindle'
                           Have = (Show-Value $archiverHave); Ok = [bool]$archiver }
        [pscustomobject]@{ Name = 'DeDRM Calibre plugin'; Component = 'dedrm-plugin'; Need = $dedrmWant
                           Have = (Show-Value $plugins['DeDRM']); Ok = ($plugins['DeDRM'] -eq $dedrmWant) }
        [pscustomobject]@{ Name = 'KFX Input Calibre plugin'; Component = 'kfx-input'; Need = "$($Pinned.KfxInput)+"
                           Have = (Show-Value $plugins['KFX Input']); Ok = [bool]$plugins['KFX Input'] }
    )
}

# ---------------------------------------------------------------------------
# Downloads
# ---------------------------------------------------------------------------
function Save-File($url, $dest) {
    New-Item -ItemType Directory -Force (Split-Path $dest) | Out-Null
    Say "  downloading $url"
    Invoke-WebRequest $url -OutFile $dest -UseBasicParsing -Headers @{ 'User-Agent' = 'kindle-dedrm' }
}

# Downloads a GitHub release asset and checks it against the SHA-256 GitHub publishes.
function Save-GitHubAsset($repo, $tag, $assetName) {
    $release = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/tags/$tag" -Headers @{ 'User-Agent' = 'kindle-dedrm' }
    $asset = $release.assets | Where-Object name -eq $assetName
    if (-not $asset) { throw "$assetName not found in $repo release $tag" }
    $dest = Join-Path $DownloadDir "$($repo -replace '/', '_')\$tag\$assetName"
    Save-File $asset.browser_download_url $dest
    if ($asset.digest -match '^sha256:([0-9a-f]+)$') {
        $expected = $Matches[1]
        if ((Get-FileHash $dest -Algorithm SHA256).Hash -ne $expected) {
            Remove-Item $dest
            throw "checksum mismatch for $assetName - download deleted"
        }
        Ok 'checksum verified (SHA-256 from GitHub)'
    } else {
        Warn "GitHub lists no checksum for $assetName - not verified"
    }
    $dest
}

# ---------------------------------------------------------------------------
# Installers
# ---------------------------------------------------------------------------
function Install-VcRedist {
    $exe = Join-Path $DownloadDir 'vc_redist.x64.exe'
    Save-File $VcRedistUrl $exe
    $sig = Get-AuthenticodeSignature $exe
    if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
        throw 'vc_redist.x64.exe is not validly signed by Microsoft - not running it'
    }
    Ok 'signature verified (Microsoft Corporation)'
    Say '  installing - approve the Windows admin prompt...'
    $code = Invoke-Elevated $exe '/install /passive /norestart'
    if ($code -notin 0, 1638, 3010) { throw "installer exited with code $code" }
    Ok "installed $(Get-VcRedistVersion)"
}

function Install-Calibre {
    Stop-AppIfRunning 'calibre' 'Calibre'
    $msi = Save-GitHubAsset 'kovidgoyal/calibre' "v$($Pinned.Calibre)" "calibre-64bit-$($Pinned.Calibre).msi"
    Say '  installing - approve the Windows admin prompt...'
    $code = Invoke-Elevated 'msiexec.exe' "/i `"$msi`" /passive /norestart"
    if ($code -notin 0, 3010) { throw "msiexec exited with code $code" }
    Ok "installed Calibre $(Get-CalibreVersion)"
}

function Install-Kindle {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        & winget install --id $KindleStoreId --source msstore --accept-package-agreements --accept-source-agreements
    }
    $pkg = Get-KindlePackage
    if (-not $pkg) {
        Warn 'could not install automatically - opening the Microsoft Store. Install "Amazon Kindle" there.'
        Start-Process "ms-windows-store://pdp/?ProductId=$KindleStoreId"
        return
    }
    Ok "installed Kindle for Windows $($pkg.Version)"
    if ((Get-KindleBuild) -ne $Pinned.KindleBuild) {
        Warn "this guide was tested with build $($Pinned.KindleBuild); 'kindle-dedrm check' shows whether an extractor matches yours"
    }
    Say '  Next: open Kindle and sign in to your Amazon account.'
}

function Install-DeDrmTools {
    $zip = Save-GitHubAsset $DeDrmRepo $Pinned.DeDrmTag 'DeDRM_tools.zip'
    if (Test-Path $ToolsDir) { Remove-Item $ToolsDir -Recurse -Force }
    Expand-Archive $zip -DestinationPath $ToolsDir
    Ok "unpacked to $ToolsDir"
    $archiver = Find-Archiver
    if ($archiver) { Ok "extractor for your Kindle: $($archiver.Name)" }
    elseif (Get-KindlePackage) { Warn "no extractor in $($Pinned.DeDrmTag) matches Kindle $((Get-KindlePackage).Version) - check $DeDrmRepo for a newer release" }
}

function Install-CalibrePlugin($zip, $label) {
    $cc = Join-Path $CalibreDir 'calibre-customize.exe'
    if (-not (Test-Path $cc)) { throw 'Calibre is not installed - run: kindle-dedrm install calibre' }
    Stop-AppIfRunning 'calibre' 'Calibre'
    $r = Invoke-Native $cc @('-a', $zip)
    $script:PluginCache = $null
    if ($r.Output -notmatch 'Plugin added') { throw "could not add $label`n$($r.Output)" }
    Ok ($r.Output -split "`n" | Where-Object { $_ -match 'Plugin added' } | Select-Object -First 1)
}

function Install-DeDrmPlugin {
    $zip = Join-Path $ToolsDir 'DeDRM_plugin.zip'
    if (-not (Test-Path $zip)) { Install-DeDrmTools }
    Install-CalibrePlugin $zip 'DeDRM'
}

function Install-KfxInput {
    $zip = Join-Path $DownloadDir 'KFX Input.zip'
    Save-File $KfxInputUrl $zip
    Install-CalibrePlugin $zip 'KFX Input'
}

function Set-StoreAutoUpdate([bool]$enabled) {
    $regKey = 'HKLM\SOFTWARE\Policies\Microsoft\WindowsStore'
    $regArgs = if ($enabled) { "delete $regKey /v AutoDownload /f" } else { "add $regKey /v AutoDownload /t REG_DWORD /d 2 /f" }
    Say '  approve the Windows admin prompt...'
    $code = Invoke-Elevated 'reg.exe' $regArgs
    if ($code -ne 0 -and -not ($enabled -and $code -eq 1)) { throw "reg.exe exited with code $code" }
    if ($enabled) { Ok 'Microsoft Store automatic app updates restored' }
    else { Ok 'Microsoft Store automatic app updates turned off (affects all Store apps)' }
}

$Components = [ordered]@{
    'vcredist' = @{
        Label   = 'Microsoft Visual C++ runtime (x64)'
        Why     = 'The book extractor needs it (otherwise: "VCRUNTIME140_1.dll was not found").'
        Source  = $VcRedistUrl
        Manual  = "download $VcRedistUrl and run it"
        Install = { Install-VcRedist }
    }
    'calibre' = @{
        Label   = "Calibre $($Pinned.Calibre)"
        Why     = 'E-book manager that imports the books and converts them to EPUB.'
        Source  = "https://github.com/kovidgoyal/calibre/releases/tag/v$($Pinned.Calibre)"
        Manual  = 'install from https://calibre-ebook.com/download_windows'
        Install = { Install-Calibre }
    }
    'kindle' = @{
        Label   = 'Kindle for Windows (Microsoft Store)'
        Why     = 'Downloads your books from Amazon. Its build number must match the extractor.'
        Source  = "Microsoft Store, product ID $KindleStoreId"
        Manual  = 'Microsoft Store -> search "Amazon Kindle" -> Install, then sign in'
        Install = { Install-Kindle }
    }
    'dedrm-tools' = @{
        Label   = "DeDRM tools $($Pinned.DeDrmTag) (Satsuoni)"
        Why     = 'Contains the extractor (MSIXKFXArchiver) and the DeDRM Calibre plugin.'
        Source  = "https://github.com/$DeDrmRepo/releases/tag/$($Pinned.DeDrmTag)"
        Manual  = "download DeDRM_tools.zip from the release page and unzip it to $ToolsDir"
        Install = { Install-DeDrmTools }
    }
    'dedrm-plugin' = @{
        Label   = 'DeDRM Calibre plugin'
        Why     = 'Removes any DRM still present when books are imported into Calibre.'
        Source  = "DeDRM_plugin.zip inside the DeDRM tools ($ToolsDir)"
        Manual  = 'Calibre -> Preferences -> Plugins -> Load plugin from file -> DeDRM_plugin.zip'
        Install = { Install-DeDrmPlugin }
    }
    'kfx-input' = @{
        Label   = 'KFX Input Calibre plugin'
        Why     = 'Lets Calibre read Kindle KFX books and convert them to EPUB.'
        Source  = $KfxInputUrl
        Manual  = 'Calibre -> Preferences -> Plugins -> Get new plugins -> "KFX Input" -> Install'
        Install = { Install-KfxInput }
    }
}
$RequirementFor = @{
    'vcredist' = 'Visual C++ runtime (x64)'; 'calibre' = 'Calibre'; 'kindle' = 'Kindle for Windows'
    'dedrm-tools' = 'DeDRM tools (Satsuoni)'; 'dedrm-plugin' = 'DeDRM Calibre plugin'; 'kfx-input' = 'KFX Input Calibre plugin'
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------
function Show-Help {
    Say @"

kindle-dedrm - turn Kindle books you own into DRM-free EPUB files (Windows 11)

USAGE
  kindle-dedrm <command> [options]

COMMANDS
  check                  1. Show what is required and what is already installed
  install [component..]  2. Install the requirements one by one (default: all)
                            components: vcredist, calibre, kindle, dedrm-tools,
                                        dedrm-plugin, kfx-input
                            optional:   store-updates-off, store-updates-on
  prepare                3. Check your downloaded Kindle books before converting
  convert                4. Extract, remove DRM, convert to EPUB and export
  clean                  Delete temporary files left by the extractor
  help                   Show this help

OPTIONS
  -OutDir <path>         Where EPUBs are saved   (default: Documents\Kindle EPUBs)
  -Library <path>        Calibre library to use  (default: ~\Calibre Library)
  -StallSeconds <n>      Skip a book whose extraction hangs this long (default: 300)
  -Yes                   Answer yes to every question
  -Force                 Reinstall components that are already installed

TYPICAL RUN
  kindle-dedrm check
  kindle-dedrm install
  (open Kindle, sign in, download your books, open each one once, close Kindle)
  kindle-dedrm prepare
  kindle-dedrm convert
"@
}

function Show-Requirements {
    Step 'Requirements'
    $reqs = @(Get-Requirements)
    $fmt = '  {0,-8} {1,-28} {2,-22} {3}'
    Write-Host ($fmt -f 'STATUS', 'REQUIREMENT', 'NEEDED', 'INSTALLED')
    foreach ($r in $reqs) {
        $status = if ($r.Ok) { 'OK' } else { 'MISSING' }
        $color = if ($r.Ok) { 'Green' } elseif ($r.Component -eq '-') { 'Yellow' } else { 'Red' }
        Write-Host ($fmt -f $status, $r.Name, $r.Need, $r.Have) -ForegroundColor $color
    }
    $updates = if (Test-StoreUpdatesOff) { 'off' } else { 'on' }
    Say "`n  Microsoft Store auto-updates: $updates  (optional: 'kindle-dedrm install store-updates-off' keeps Kindle on a supported build)"

    $missing = @($reqs | Where-Object { -not $_.Ok -and $_.Component -ne '-' } | ForEach-Object Component | Select-Object -Unique)
    if ($missing) {
        Say "`n  Next: kindle-dedrm install          (or just: kindle-dedrm install $($missing -join ' '))"
    } else {
        Say ''
        Ok 'everything is installed. Next: kindle-dedrm prepare'
    }
    if (-not ($reqs | Where-Object Name -eq 'Windows 11').Ok) { Warn 'Kindle for Windows needs Windows 11' }
}

function Invoke-Install([string[]]$names) {
    if (-not $names -or $names -contains 'all') { $names = @($Components.Keys) }
    $reqs = @(Get-Requirements)
    foreach ($n in $names) {
        if ($n -eq 'store-updates-off' -or $n -eq 'store-updates-on') {
            Step "Microsoft Store automatic updates  [$n]"
            Say '  why:  a Store update can move Kindle to a build no extractor supports yet.'
            Set-StoreAutoUpdate ($n -eq 'store-updates-on')
            continue
        }
        if (-not $Components.Contains($n)) {
            throw "unknown component '$n'. Choose from: $(@($Components.Keys) -join ', '), store-updates-off, store-updates-on"
        }
        $c = $Components[$n]
        Step "$($c.Label)  [$n]"
        Say "  why:  $($c.Why)"
        Say "  from: $($c.Source)"
        $req = $reqs | Where-Object Name -eq $RequirementFor[$n]
        if ($req.Ok -and -not $Force) { Ok "already installed ($($req.Have))"; continue }
        if (-not (Confirm-Step 'Install it now?')) { Warn "skipped. To do it yourself: $($c.Manual)"; continue }
        & $c.Install
        $reqs = @(Get-Requirements)
    }
    Show-Requirements
}

function Invoke-Prepare {
    Step 'Checking requirements'
    $missing = @(Get-Requirements | Where-Object { -not $_.Ok -and $_.Component -ne '-' })
    if ($missing) {
        $missing | ForEach-Object { Fail "$($_.Name) - run: kindle-dedrm install $($_.Component)" }
        return
    }
    Ok 'all requirements installed'

    Step 'Kindle for Windows'
    Ok "version $((Get-KindlePackage).Version), extractor $((Find-Archiver).Name)"
    if (-not (Test-StoreUpdatesOff)) {
        Warn 'Store auto-updates are on: a Kindle update can break the extractor until a new DeDRM release appears.'
        Say  '         To prevent that: kindle-dedrm install store-updates-off'
    }
    if (Get-Process Kindle -ErrorAction SilentlyContinue) { Say '  Kindle is running (convert will offer to close it).' }

    Step 'Downloaded books'
    $books = @(Get-KindleBooks)
    if ($books.Count -eq 0) {
        Warn 'no downloaded books found. Open Kindle, sign in and download your books first.'
        return
    }
    $done = @(Get-ChildItem $ArchiveDir -Filter *.kfx-zip -ErrorAction SilentlyContinue | ForEach-Object BaseName)
    $new = @($books | Where-Object { $_.Complete -and $done -notcontains $_.Name })
    $incomplete = @($books | Where-Object { -not $_.Complete })
    Ok "$($books.Count) book(s) downloaded in Kindle"
    Ok "$($books.Count - $new.Count - $incomplete.Count) already extracted by an earlier run"
    if ($new) {
        Say "  $($new.Count) new book(s) ready to convert:"
        $new | ForEach-Object { Say ("     {0,-12} {1,6} MB   https://www.amazon.com/dp/{0}" -f $_.Asin, $_.SizeMB) }
    }
    if ($incomplete) {
        Warn "$($incomplete.Count) book(s) look incomplete (no .azw file) and will be skipped:"
        $incomplete | ForEach-Object { Say "     $($_.Asin)  -> in Kindle: Remove download, download again, open it" }
    }

    Step 'Before you convert'
    Say '  1. In Kindle, download every book you want - a few at a time (bulk downloads can miss images).'
    Say '  2. Open each new book once and page to the end, so its keys are loaded.'
    Say '  3. Close Kindle (convert can do this for you).'
    Say "`n  Then run: kindle-dedrm convert"
}

function Reset-JunctionDir($dir) {
    if (Test-Path $dir) {
        foreach ($item in Get-ChildItem $dir -Force) {
            if (-not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "unexpected item in $dir : $($item.Name)" }
            $item.Delete()   # removes the junction only, never the Kindle folder it points to
        }
        [IO.Directory]::Delete($dir)
    }
}

# Runs the extractor; if a book hangs for $StallSeconds it is skipped and the rest retried.
function Invoke-Archiver($archiver) {
    $junctions = Join-Path $WorkDir 'books'
    New-Item -ItemType Directory -Force $ArchiveDir, (Join-Path $WorkDir 'logs') | Out-Null
    $skipped = @()
    try {
        for ($run = 1; $run -le 50; $run++) {
            $done = @(Get-ChildItem $ArchiveDir -Filter *.kfx-zip | ForEach-Object BaseName)
            $pending = @(Get-KindleBooks | Where-Object { $_.Complete -and $done -notcontains $_.Name -and $skipped -notcontains $_.Name })
            if ($pending.Count -eq 0) { break }

            Reset-JunctionDir $junctions
            New-Item -ItemType Directory $junctions | Out-Null
            foreach ($b in $pending) { New-Item -ItemType Junction -Path (Join-Path $junctions $b.Name) -Target $b.FullName | Out-Null }

            Say "  extracting $($pending.Count) book(s) with $($archiver.Name)..."
            $log = Join-Path $WorkDir "logs\archiver-$(Get-Date -Format yyyyMMdd-HHmmss).log"
            $p = Start-Process $archiver.FullName -WorkingDirectory $WorkDir -NoNewWindow -PassThru `
                -ArgumentList "`"$junctions`"", "`"$ArchiveDir`"", "`"$(Join-Path $WorkDir 'oldbooks.k4i')`"" `
                -RedirectStandardOutput $log -RedirectStandardError "$log.err"
            $null = $p.Handle

            $stuck = $null; $lastSize = -1; $lastCount = @(Get-ChildItem $ArchiveDir -Filter *.kfx-zip).Count; $lastChange = Get-Date
            while (-not $p.HasExited) {
                Start-Sleep -Seconds 5
                $size = (Get-Item $log -ErrorAction SilentlyContinue).Length
                $count = @(Get-ChildItem $ArchiveDir -Filter *.kfx-zip).Count
                if ($count -ne $lastCount) { Say "    $($count - $done.Count) of $($pending.Count) extracted" }
                if ($size -ne $lastSize -or $count -ne $lastCount) {
                    $lastSize = $size; $lastCount = $count; $lastChange = Get-Date
                } elseif (((Get-Date) - $lastChange).TotalSeconds -gt $StallSeconds) {
                    $p | Stop-Process -Force
                    $m = Select-String -Path $log -Pattern 'Trying to open\s+(\S+)' | Select-Object -Last 1
                    $stuck = if ($m) { $m.Matches[0].Groups[1].Value } else { '?' }
                    break
                }
            }
            if (-not $stuck) { break }
            if ($stuck -eq '?') { Warn "extractor stalled and the book could not be identified - see $log"; break }
            $skipped += $stuck
            Warn "$stuck hung for $StallSeconds s and was skipped. In Kindle: Remove download, download again, open it, then rerun convert."
        }
    } finally {
        Reset-JunctionDir $junctions
    }
    $skipped
}

# Imports extracted books whose Amazon ASIN is not in the Calibre library yet
# (matching on ASIN, so edited titles/authors don't cause duplicates).
function Import-Books {
    $inLibrary = @(Get-LibraryBooks | ForEach-Object { $_.identifiers.'mobi-asin' } | Where-Object { $_ })
    $new = @(Get-ChildItem $ArchiveDir -Filter *.kfx-zip -ErrorAction SilentlyContinue |
        Where-Object { $inLibrary -notcontains ($_.BaseName -replace '_EBOK$') })
    if ($new.Count -eq 0) { Ok "all extracted books are already in the library ($($inLibrary.Count) by ASIN)"; return }

    New-Item -ItemType Directory -Force $Library | Out-Null
    $r = Invoke-Native $Calibredb (@('add', '--with-library', $Library) + @($new | ForEach-Object FullName))
    $ids = @()
    if ($r.Output -match 'Added book ids: ([\d, ]+)') { $ids = @($Matches[1] -split ',\s*' | Where-Object { $_ } | ForEach-Object { [int]$_ }) }
    if ($r.Output -match 'already exist') { Warn 'some books were already in the Calibre library and were skipped' }
    Ok "imported $($ids.Count) book(s) into $Library"

    foreach ($b in @(Get-LibraryBooks | Where-Object { $ids -contains $_.id })) {
        if (-not ($b.formats -like '*.kfx')) { Fail "$($b.title): imported as KFX-ZIP - DRM was not removed" }
    }
    $ids
}

function Convert-Books {
    $todo = @(Get-LibraryBooks | Where-Object { ($_.formats -like '*.kfx') -and -not ($_.formats -like '*.epub') })
    if ($todo.Count -eq 0) { Ok 'every KFX book in the library already has an EPUB'; return }
    $tmp = Join-Path $WorkDir 'epub'
    New-Item -ItemType Directory -Force $tmp | Out-Null
    $convert = Join-Path $CalibreDir 'ebook-convert.exe'
    $i = 0
    foreach ($b in $todo) {
        $i++
        $kfx = @($b.formats -like '*.kfx')[0]
        $epub = Join-Path $tmp "$($b.id).epub"
        Remove-Item $epub -ErrorAction SilentlyContinue
        Write-Host ("  [{0}/{1}] {2}" -f $i, $todo.Count, $b.title) -NoNewline
        $r = Invoke-Native $convert @($kfx, $epub)
        $r.Output | Set-Content (Join-Path $WorkDir "logs\convert-$($b.id).log")
        if (Test-Path $epub) {
            Invoke-Native $Calibredb @('add_format', '--with-library', $Library, "$($b.id)", $epub) | Out-Null
            Remove-Item $epub
            Write-Host '  ok' -ForegroundColor Green
            $b.id
        } else {
            Write-Host "  FAILED (log: $WorkDir\logs\convert-$($b.id).log)" -ForegroundColor Red
        }
    }
}

function Export-Epubs([int[]]$ids) {
    if (-not $ids) { Ok 'nothing new to export'; return }
    New-Item -ItemType Directory -Force $OutDir | Out-Null
    $exportArgs = @('export', '--with-library', $Library) + @($ids | ForEach-Object { "$_" }) +
                  @('--formats', 'epub', '--dont-save-cover', '--dont-write-opf', '--single-dir', '--to-dir', $OutDir)
    Invoke-Native $Calibredb $exportArgs | Out-Null
    Ok "$($ids.Count) EPUB(s) saved to $OutDir"
}

function Invoke-Convert {
    Step 'Checking requirements'
    $missing = @(Get-Requirements | Where-Object { -not $_.Ok -and $_.Component -ne '-' })
    if ($missing) {
        $missing | ForEach-Object { Fail "$($_.Name) - run: kindle-dedrm install $($_.Component)" }
        throw 'requirements missing'
    }
    $books = @(Get-KindleBooks)
    if ($books.Count -eq 0) { throw 'no downloaded Kindle books found - download them in Kindle first (see: kindle-dedrm prepare)' }
    Ok "$($books.Count) downloaded book(s), extractor $((Find-Archiver).Name)"
    Stop-AppIfRunning 'Kindle' 'Kindle'
    Stop-AppIfRunning 'calibre' 'Calibre'

    Step '1/4 Extracting and decrypting books from Kindle'
    $skipped = @(Invoke-Archiver (Find-Archiver))
    $extracted = @(Get-ChildItem $ArchiveDir -Filter *.kfx-zip).Count
    Ok "$extracted book(s) extracted to $ArchiveDir"

    Step '2/4 Importing into Calibre (DeDRM runs on import)'
    $null = Import-Books

    Step '3/4 Converting to EPUB'
    $converted = @(Convert-Books)

    Step '4/4 Exporting EPUBs'
    Export-Epubs $converted

    Step 'Summary'
    $incomplete = @($books | Where-Object { -not $_.Complete })
    Say "  Kindle books found:   $($books.Count)"
    Say "  Converted this run:   $($converted.Count)"
    if ($skipped) { Warn "Hung and skipped:     $($skipped -join ', ')" }
    if ($incomplete) { Warn "Incomplete download:  $(($incomplete | ForEach-Object Asin) -join ', ')" }
    Say "  EPUB folder:          $OutDir"
    Say "  Calibre library:      $Library   (pick this folder when Calibre first asks)"
}

function Invoke-Clean {
    Step 'Cleaning temporary files'
    $data = 'C:\Data'
    if ((Test-Path $data) -and (Get-ChildItem $data -Directory -Filter 'AMZNKindle*')) {
        if (Get-ChildItem $data -Recurse -Force -Attributes ReparsePoint -ErrorAction SilentlyContinue) {
            Warn "$data contains links - not deleting it automatically"
        } else {
            $mb = [math]::Round((Get-ChildItem $data -Recurse -File -Force | Measure-Object Length -Sum).Sum / 1MB)
            if (Confirm-Step "Delete the extractor's temporary folder $data ($mb MB)?") {
                Remove-Item $data -Recurse -Force
                Ok "deleted $data"
            }
        }
    } else { Ok "no extractor folder at $data" }
    Reset-JunctionDir (Join-Path $WorkDir 'books')
    Remove-Item (Join-Path $WorkDir 'epub') -Recurse -Force -ErrorAction SilentlyContinue
    Ok 'removed work-in-progress files'
    Say "  Kept: $ArchiveDir (extracted books) and the key files in $WorkDir."
    Say '  The .k4i / .keyfile files unlock your Amazon books - keep them private.'
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
try {
    try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
    $env:PYTHONIOENCODING = 'utf-8'
    New-Item -ItemType Directory -Force $AppDir, $DownloadDir, $WorkDir | Out-Null
    switch ($Command) {
        'check'   { Show-Requirements }
        'install' { Invoke-Install $Component }
        'prepare' { Invoke-Prepare }
        'convert' { Invoke-Convert }
        'clean'   { Invoke-Clean }
        default   { Show-Help }
    }
} catch {
    Write-Host "`nError: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
