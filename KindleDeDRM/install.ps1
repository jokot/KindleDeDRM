# Installs KindleDeDRM for the current user: copy app, add to PATH, add Start-menu shortcut.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Setup.ps1')

Write-Host "Installing KindleDeDRM to $InstallDir"
New-Item -ItemType Directory -Force $InstallDir | Out-Null
$installedLib = Join-Path $InstallDir 'lib'
if (Test-Path $installedLib) { Remove-Item $installedLib -Recurse -Force }
foreach ($item in 'KindleDeDRM.cmd', 'KindleDeDRM.ps1', 'README.md', 'lib') {
    $src = Join-Path $PSScriptRoot $item
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
