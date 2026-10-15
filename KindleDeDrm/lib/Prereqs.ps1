# Detecting and installing the prerequisites. Depends on: Config, Ui, Native.

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
    param([int]$Build = (Get-KindleBuild), [string]$Dir = $ToolsDir)
    if (-not $Build -or -not (Test-Path $Dir)) { return }
    Get-ChildItem $Dir -Filter 'MSIXKFXArchiver*.exe' |
        Where-Object { $_.Name -match "_$Build(\D|$)" } | Select-Object -First 1
}

function Test-StoreUpdatesOff {
    $v = Get-ItemProperty $StorePolicy -Name AutoDownload -ErrorAction SilentlyContinue
    $v -and $v.AutoDownload -eq 2
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
                           Have = (Show-Value $vc); Ok = [bool]($vc -and $vc -ge [version]'14.20') }
        [pscustomobject]@{ Name = 'Calibre'; Component = 'calibre'; Need = "$($Pinned.Calibre) (min 6.0)"
                           Have = (Show-Value $calibre); Ok = [bool]($calibre -and $calibre -ge [version]'6.0') }
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

function Get-MissingRequirements { @(Get-Requirements | Where-Object { -not $_.Ok -and $_.Component -ne '-' }) }

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
        Warn "tested with build $($Pinned.KindleBuild); 'Check prerequisites' shows whether an extractor matches yours"
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
    if (-not (Test-Path $cc)) { throw 'Calibre is not installed - install it first' }
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
        Label = 'Microsoft Visual C++ runtime (x64)'; Install = { Install-VcRedist }
        Why = 'The book extractor needs it (otherwise: "VCRUNTIME140_1.dll was not found").'
        Source = $VcRedistUrl; Manual = "download $VcRedistUrl and run it"
    }
    'calibre' = @{
        Label = "Calibre $($Pinned.Calibre)"; Install = { Install-Calibre }
        Why = 'E-book manager that imports the books and converts them to EPUB.'
        Source = "https://github.com/kovidgoyal/calibre/releases/tag/v$($Pinned.Calibre)"
        Manual = 'install from https://calibre-ebook.com/download_windows'
    }
    'kindle' = @{
        Label = 'Kindle for Windows (Microsoft Store)'; Install = { Install-Kindle }
        Why = 'Downloads your books from Amazon. Its build number must match the extractor.'
        Source = "Microsoft Store, product ID $KindleStoreId"
        Manual = 'Microsoft Store -> search "Amazon Kindle" -> Install, then sign in'
    }
    'dedrm-tools' = @{
        Label = "DeDRM tools $($Pinned.DeDrmTag) (Satsuoni)"; Install = { Install-DeDrmTools }
        Why = 'Contains the extractor (MSIXKFXArchiver) and the DeDRM Calibre plugin.'
        Source = "https://github.com/$DeDrmRepo/releases/tag/$($Pinned.DeDrmTag)"
        Manual = "download DeDRM_tools.zip from the release page and unzip it to $ToolsDir"
    }
    'dedrm-plugin' = @{
        Label = 'DeDRM Calibre plugin'; Install = { Install-DeDrmPlugin }
        Why = 'Removes any DRM still present when books are imported into Calibre.'
        Source = "DeDRM_plugin.zip inside the DeDRM tools ($ToolsDir)"
        Manual = 'Calibre -> Preferences -> Plugins -> Load plugin from file -> DeDRM_plugin.zip'
    }
    'kfx-input' = @{
        Label = 'KFX Input Calibre plugin'; Install = { Install-KfxInput }
        Why = 'Lets Calibre read Kindle KFX books and convert them to EPUB.'
        Source = $KfxInputUrl
        Manual = 'Calibre -> Preferences -> Plugins -> Get new plugins -> "KFX Input" -> Install'
    }
}
$RequirementFor = @{
    'vcredist' = 'Visual C++ runtime (x64)'; 'calibre' = 'Calibre'; 'kindle' = 'Kindle for Windows'
    'dedrm-tools' = 'DeDRM tools (Satsuoni)'; 'dedrm-plugin' = 'DeDRM Calibre plugin'; 'kfx-input' = 'KFX Input Calibre plugin'
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
    Say "`n  Microsoft Store auto-updates: $updates  (turning them off keeps Kindle on a supported build)"

    $missing = @($reqs | Where-Object { -not $_.Ok -and $_.Component -ne '-' } | ForEach-Object Component | Select-Object -Unique)
    if ($missing) {
        Say "`n  Next: choose 2) Install prerequisites   (or: KindleDeDrm install $($missing -join ' '))"
    } else {
        Say ''
        Ok 'everything is installed'
    }
    if (-not ($reqs | Where-Object Name -eq 'Windows 11').Ok) { Warn 'Kindle for Windows needs Windows 11' }
}

# Installs components one by one: explains each, skips what is present, asks before installing.
function Invoke-Install([string[]]$names, [switch]$Force) {
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
}
