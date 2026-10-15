# Interactive numbered menus. Depends on: every other lib file.

function Clear-Screen { try { Clear-Host } catch { } }
function Wait-Return { $null = Read-Line '  Press Enter to return to the menu' }

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
        Write-Host ("  KindleDeDRM {0,-12} {1}" -f $AppVersion, $status) -ForegroundColor Cyan
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
            if ($choice -eq '3') { Wait-Return }
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
    $answer = (Read-Line "  $label [$current]").Trim().Trim('"')
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
                $answer = (Read-Line "  Stall timeout in seconds, 30 or more [$($Settings.StallSeconds)]").Trim()
                if ($answer -match '^\d+$' -and [int]$answer -ge 30) { $Settings.StallSeconds = [int]$answer }
                elseif ($answer) { Warn 'must be a whole number of 30 or more - unchanged' }
            }
            '4' { Set-StoreAutoUpdate ($updates -eq 'off') }
        }
        Save-Settings -Settings $Settings
        Ok 'saved'
    }
}

# Extracts newly downloaded books and reads their titles, so the list is current.
function Update-Books($settings) {
    Step 'Refreshing Kindle books'
    $new = @(Get-BookIndex -Library $settings.Library | Where-Object Status -eq 'new')
    if ($new) {
        $archiver = Find-Archiver
        if (-not $archiver) { throw 'no extractor matches your Kindle version - see Check prerequisites' }
        Stop-AppIfRunning 'Kindle' 'Kindle'
        $kindleBooks = @($new | ForEach-Object { [pscustomobject]@{ Name = "$($_.Asin)_EBOK"; FullName = $_.KindlePath } })
        $null = Invoke-Archiver -Archiver $archiver -Books $kindleBooks -StallSeconds $settings.StallSeconds
    }
    $index = Read-TitleIndex
    Update-TitleIndex -Index $index -Asins @((Get-ExtractedBooks).Keys)
    Ok "$($new.Count) new book(s) extracted"
}

function Open-BookFolder($book) {
    if ($book.Exported -and (Test-Path $book.Exported)) {
        Start-Process explorer.exe "/select,`"$($book.Exported)`""
        return
    }
    $path = if ($book.EpubPath) { $book.EpubPath } else { $book.KfxPath }
    if ($path) { Start-Process explorer.exe "`"$(Split-Path ($path -replace '/', '\'))`"" }
    else { Warn "$($book.Title): nothing to open yet - convert it first" }
}

function Show-BooksMenu {
    param([Parameter(Mandatory)]$Settings)
    $missing = @(Get-MissingRequirements)
    if ($missing) {
        $missing | ForEach-Object { Fail "$($_.Name) is missing" }
        Say '  Choose 2) Install prerequisites first.'
        Wait-Return
        return
    }
    # calibredb cannot read the library while the Calibre app is open.
    Stop-AppIfRunning 'calibre' 'Calibre'
    if ((Read-Line '  Refresh Kindle books now? [Y/s]') -notmatch '^[Ss]') {
        try { Update-Books $Settings } catch { Fail "Error: $($_.Exception.Message)" }
    }

    $query = $null
    while ($true) {
        if ($null -eq $query) {
            $query = (Read-Line "`n  Search (title/author, blank = all, 0 = back)").Trim()
            if ($query -eq '0') { return }
        }
        $books = @(Find-Books (Get-BookIndex -Library $Settings.Library) $query)
        if ($books.Count -eq 0) { Warn 'no books match'; $query = $null; continue }
        Write-Host ''
        Write-BookTable $books
        $newIndexes = @(for ($i = 0; $i -lt $books.Count; $i++) {
            if ('new', 'extracted', 'in Calibre' -contains $books[$i].Status) { $i + 1 }
        })

        $text = Read-Line "`n  Pick books (e.g. 1,3  2-5  all  new; blank = new search)"
        try {
            $picked = @(ConvertFrom-Selection -Text $text -Count $books.Count -NewIndexes $newIndexes)
        } catch { Warn $_.Exception.Message; continue }
        if ($picked.Count -eq 0) { $query = $null; continue }
        $chosen = @($picked | ForEach-Object { $books[$_ - 1] })

        Say '  Action: 1) Convert  2) Re-convert  3) Re-export  4) Open folder  0) Back'
        $action = Read-MenuChoice -Prompt '  > (Enter = 1)' -Valid '', '0', '1', '2', '3', '4'
        if ($action -eq '0') { continue }
        if ($action -eq '4') { $chosen | ForEach-Object { Open-BookFolder $_ }; continue }
        $name = switch ($action) { '2' { 'Reconvert' } '3' { 'Reexport' } default { 'Convert' } }
        try {
            Step "$name $($chosen.Count) book(s)"
            foreach ($r in @(Invoke-BookAction -Books $chosen -Action $name -Settings $Settings)) {
                if ($r.Ok) { Write-Host "  ok      $($r.Title)" -ForegroundColor Green }
                else { Write-Host "  FAILED  $($r.Title) - $($r.Message)" -ForegroundColor Red }
            }
        } catch { Fail "Error: $($_.Exception.Message)" }
    }
}
