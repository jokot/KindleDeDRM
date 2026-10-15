# Interactive numbered menus. Depends on: every other lib file.

function Clear-Screen { try { Clear-Host } catch { } }
function Wait-Return { $null = Read-Host '  Press Enter to return to the menu' }

function Get-MenuStatus {
    $kindle = Get-KindlePackage
    $kindleText = if ($kindle) { "Kindle $($kindle.Version -replace '\.0$')" } else { 'Kindle not installed' }
    $books = @(Get-KindleBooks).Count
    $missing = @(Get-MissingRequirements).Count
    $prereq = if ($missing) { "$missing missing - choose 2" } else { 'all prerequisites OK' }
    "$kindleText  .  $books books  .  $prereq"
}

function Start-MainMenu {
    param([Parameter(Mandatory)]$Settings)
    $status = $null
    while ($true) {
        if (-not $status) { $status = Get-MenuStatus }
        Clear-Screen
        Write-Host ''
        Write-Host ("  KindleDeDrm {0,-12} {1}" -f $AppVersion, $status) -ForegroundColor Cyan
        Say '  ------------------------------------------------------------'
        Say '  1) Check prerequisites'
        Say '  2) Install prerequisites'
        Say '  3) DeDRM books'
        Say '  4) Settings'
        Say '  5) Clean temp files'
        Say '  0) Exit'
        $choice = Read-MenuChoice -Valid '0', '1', '2', '3', '4', '5'
        if ($choice -eq '0') { return }
        try {
            switch ($choice) {
                '1' { Show-Requirements }
                '2' { Show-PrereqMenu; $status = $null }
                '3' { Show-BooksMenu -Settings $Settings; $status = $null }
                '4' { $Settings = Show-SettingsMenu -Settings $Settings; $status = $null }
                '5' { Invoke-Clean }
            }
        } catch {
            Fail "Error: $($_.Exception.Message)"
        }
        if ($choice -ne '3') { Wait-Return }
    }
}

function Show-PrereqMenu {
    $missing = @(Get-MissingRequirements | ForEach-Object Component | Select-Object -Unique)
    if ($missing) {
        Step 'Missing prerequisites'
        for ($i = 0; $i -lt $missing.Count; $i++) { Say "  $($i + 1)) $($Components[$missing[$i]].Label)  [$($missing[$i])]" }
        Say '  a) install all missing'
        Say '  0) back'
        $valid = @('0', 'a') + @(1..$missing.Count | ForEach-Object { "$_" })
        $choice = Read-MenuChoice -Valid $valid
        if ($choice -eq '0') { return }
        $names = if ($choice -eq 'a') { $missing } else { @($missing[[int]$choice - 1]) }
        Invoke-Install $names
        Show-Requirements
        return
    }

    Ok 'everything is installed'
    $updates = if (Test-StoreUpdatesOff) { 'off' } else { 'on' }
    Say '  f) force reinstall a part'
    Say "  s) Store auto-updates (now $updates) - switch them $(if ($updates -eq 'on') { 'off' } else { 'on' })"
    Say '  0) back'
    switch (Read-MenuChoice -Valid '0', 'f', 's') {
        'f' {
            $names = @($Components.Keys)
            for ($i = 0; $i -lt $names.Count; $i++) { Say "  $($i + 1)) $($Components[$names[$i]].Label)  [$($names[$i])]" }
            Say '  0) back'
            $choice = Read-MenuChoice -Valid (@('0') + @(1..$names.Count | ForEach-Object { "$_" }))
            if ($choice -ne '0') { Invoke-Install @($names[[int]$choice - 1]) -Force }
        }
        's' {
            $turnOn = $updates -eq 'off'
            if (Confirm-Step "Switch Microsoft Store automatic updates $(if ($turnOn) { 'on' } else { 'off' }) for all Store apps?") {
                Set-StoreAutoUpdate $turnOn
            }
        }
    }
}

function Read-Folder($label, $current) {
    $answer = "$(Read-Host "  $label [$current]")".Trim().Trim('"')
    if (-not $answer) { return $current }
    if (-not (Test-Path $answer)) {
        if (-not (Confirm-Step "$answer does not exist. Create it?")) { return $current }
        New-Item -ItemType Directory -Force $answer | Out-Null
    }
    (Resolve-Path $answer).Path
}

function Show-SettingsMenu {
    param([Parameter(Mandatory)]$Settings)
    while ($true) {
        $updates = if (Test-StoreUpdatesOff) { 'off' } else { 'on' }
        Step 'Settings'
        Say "  1) EPUB folder              $($Settings.OutDir)"
        Say "  2) Calibre library          $($Settings.Library)"
        Say "  3) Stall timeout (seconds)  $($Settings.StallSeconds)"
        Say "  4) Store auto-updates       $updates"
        Say '  0) back'
        switch (Read-MenuChoice -Valid '0', '1', '2', '3', '4') {
            '0' { return $Settings }
            '1' { $Settings.OutDir = Read-Folder 'EPUB folder' $Settings.OutDir }
            '2' { $Settings.Library = Read-Folder 'Calibre library' $Settings.Library }
            '3' {
                $answer = "$(Read-Host "  Stall timeout in seconds, 30 or more [$($Settings.StallSeconds)]")".Trim()
                if ($answer -match '^\d+$' -and [int]$answer -ge 30) { $Settings.StallSeconds = [int]$answer }
                elseif ($answer) { Warn 'must be a whole number of 30 or more - unchanged' }
            }
            '4' { Set-StoreAutoUpdate ($updates -eq 'off') }
        }
        Save-Settings -Settings $Settings
        Ok 'saved'
    }
}

function Show-BooksMenu {
    param([Parameter(Mandatory)]$Settings)
    Say 'books menu coming in Task 8'
}
