# Pure helpers for editing a PATH string, plus registry/shortcut helpers used by install/uninstall.

function ConvertTo-PathKey([string]$entry) { $entry.Trim().TrimEnd('\').ToLowerInvariant() }

function Add-PathEntry {
    param([AllowEmptyString()][string]$PathValue, [Parameter(Mandatory)][string]$Dir)
    $entries = @("$PathValue" -split ';' | Where-Object { $_.Trim() })
    $key = ConvertTo-PathKey $Dir
    if (-not ($entries | Where-Object { (ConvertTo-PathKey $_) -eq $key })) { $entries += $Dir }
    $entries -join ';'
}

function Remove-PathEntry {
    param([AllowEmptyString()][string]$PathValue, [Parameter(Mandatory)][string]$Dir)
    $key = ConvertTo-PathKey $Dir
    @("$PathValue" -split ';' | Where-Object { $_.Trim() -and (ConvertTo-PathKey $_) -ne $key }) -join ';'
}

# Reads/writes the user PATH as REG_EXPAND_SZ so entries like %USERPROFILE%\bin stay unexpanded.
function Get-UserPath {
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment')
    try { "$($key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames))" } finally { $key.Close() }
}

function Set-UserPath([string]$value) {
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
    try { $key.SetValue('Path', $value, [Microsoft.Win32.RegistryValueKind]::ExpandString) } finally { $key.Close() }
    # Tell Explorer and new terminals that the environment changed.
    if (-not ('KindleDeDrm.EnvNotify' -as [type])) {
        Add-Type -Namespace KindleDeDrm -Name EnvNotify -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@
    }
    $result = [UIntPtr]::Zero
    $null = [KindleDeDrm.EnvNotify]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$result)
}

$InstallDir   = Join-Path $env:LOCALAPPDATA 'Programs\KindleDeDrm'
$ShortcutPath = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\KindleDeDrm.lnk'
