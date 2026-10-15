# Removes the KindleDeDrm app, its PATH entry and shortcut. Never touches books, keys or Calibre.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Setup.ps1')

$oldPath = Get-UserPath
$newPath = Remove-PathEntry -PathValue $oldPath -Dir $InstallDir
if ($newPath -ne $oldPath) { Set-UserPath $newPath; Write-Host '  [ok]   removed from your PATH' }
if (Test-Path $ShortcutPath) { Remove-Item $ShortcutPath -Force; Write-Host '  [ok]   Start-menu shortcut removed' }
if (Test-Path $InstallDir) { Remove-Item $InstallDir -Recurse -Force; Write-Host "  [ok]   deleted $InstallDir" }

Write-Host "`nUninstalled. Kept your data in $(Join-Path $env:LOCALAPPDATA 'kindle-dedrm'), your Calibre library, Calibre and Kindle." -ForegroundColor Green
