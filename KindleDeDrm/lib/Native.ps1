# Running external programs, elevation and verified downloads. Depends on: Ui, Config.

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
        throw "close $label and try again"
    }
    $p | Stop-Process -Force
    Start-Sleep -Seconds 2
    Ok "closed $label"
}

function Save-File($url, $dest) {
    New-Item -ItemType Directory -Force (Split-Path $dest) | Out-Null
    Say "  downloading $url"
    Invoke-WebRequest $url -OutFile $dest -UseBasicParsing -Headers @{ 'User-Agent' = 'KindleDeDrm' }
}

# Downloads a GitHub release asset and checks it against the SHA-256 GitHub publishes.
function Save-GitHubAsset($repo, $tag, $assetName) {
    $release = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/tags/$tag" -Headers @{ 'User-Agent' = 'KindleDeDrm' }
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
