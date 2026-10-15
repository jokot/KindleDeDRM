# Installs KindleDeDRM for the current user: copy app, add to PATH, add Start-menu shortcut.
#
#   irm https://raw.githubusercontent.com/jokot/KindleDeDRM/main/install.ps1 | iex
#
# Run from a clone, it installs that copy. Run through iex, it downloads the latest main branch first.
# Running it again updates the app. Your books, keys and settings are never touched.
# Wrapped in & { } so iex leaves no variables or preferences behind in your session.
& {
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$source = $PSScriptRoot
$tmp = $null
try {
    if (-not $source -or -not (Test-Path (Join-Path $source 'lib\Setup.ps1'))) {
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ('KindleDeDRM-' + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory $tmp | Out-Null
        Write-Host 'Downloading KindleDeDRM from github.com/jokot/KindleDeDRM...'
        $zip = Join-Path $tmp 'KindleDeDRM.zip'
        Invoke-WebRequest -UseBasicParsing 'https://github.com/jokot/KindleDeDRM/archive/refs/heads/main.zip' -OutFile $zip
        Expand-Archive $zip $tmp
        $source = Join-Path $tmp 'KindleDeDRM-main'
    }
    # Loaded as a script block rather than dot-sourced, so a Restricted execution policy can't block it.
    . ([scriptblock]::Create((Get-Content -Raw (Join-Path $source 'lib\Setup.ps1'))))

    Write-Host "Installing KindleDeDRM to $InstallDir"
    New-Item -ItemType Directory -Force $InstallDir | Out-Null
    $installedLib = Join-Path $InstallDir 'lib'
    if (Test-Path $installedLib) { Remove-Item $installedLib -Recurse -Force }
    foreach ($item in 'KindleDeDRM.cmd', 'KindleDeDRM.ps1', 'uninstall.ps1', 'README.md', 'lib') {
        $src = Join-Path $source $item
        if (Test-Path $src) { Copy-Item $src $InstallDir -Recurse -Force }
    }
    Write-Host '  [ok]   files copied'

    $oldPath = Get-UserPath
    $newPath = Add-PathEntry -PathValue $oldPath -Dir $InstallDir
    if ($newPath -ne $oldPath) { Set-UserPath $newPath; Write-Host '  [ok]   added to your PATH' }
    else { Write-Host '  [ok]   already on your PATH' }

    $shell = New-Object -ComObject WScript.Shell
    $link = $shell.CreateShortcut($ShortcutPath)
    $link.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $link.Arguments = "-NoProfile -ExecutionPolicy Bypass -NoExit -File `"$InstallDir\KindleDeDRM.ps1`""
    $link.WorkingDirectory = $env:USERPROFILE
    $link.Description = 'KindleDeDRM - Kindle books to DRM-free EPUB'
    $link.Save()
    Write-Host '  [ok]   Start-menu shortcut created'

    Write-Host "`nInstalled. Open a new terminal and run: KindleDeDRM" -ForegroundColor Green
} finally {
    if ($tmp) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
}
