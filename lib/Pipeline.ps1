# Extract -> import -> EPUB -> export, for a chosen set of books.
# Depends on: Config, Ui, Native, Prereqs, Library.

function Reset-JunctionDir($dir) {
    if (Test-Path $dir) {
        foreach ($item in Get-ChildItem $dir -Force) {
            if (-not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "unexpected item in $dir : $($item.Name)" }
            $item.Delete()   # removes the junction only, never the Kindle folder it points to
        }
        [IO.Directory]::Delete($dir)
    }
}

# Runs the extractor on -Books (Kindle records with Name/FullName). A book that hangs for
# -StallSeconds is skipped and the rest retried. Returns the Names of skipped books.
function Invoke-Archiver {
    param([Parameter(Mandatory)]$Archiver, [object[]]$Books, [int]$StallSeconds = 300)
    $junctions = Join-Path $WorkDir 'books'
    New-Item -ItemType Directory -Force $ArchiveDir, (Join-Path $WorkDir 'logs') | Out-Null
    $skipped = @()
    try {
        for ($run = 1; $run -le 50; $run++) {
            $done = @(Get-ChildItem $ArchiveDir -Filter *.kfx-zip | ForEach-Object BaseName)
            $pending = @($Books | Where-Object { $done -notcontains $_.Name -and $skipped -notcontains $_.Name })
            if ($pending.Count -eq 0) { break }

            Reset-JunctionDir $junctions
            New-Item -ItemType Directory $junctions | Out-Null
            foreach ($b in $pending) { New-Item -ItemType Junction -Path (Join-Path $junctions $b.Name) -Target $b.FullName | Out-Null }

            Say "  extracting $($pending.Count) book(s) with $($Archiver.Name)..."
            $log = Join-Path $WorkDir "logs\archiver-$(Get-Date -Format yyyyMMdd-HHmmss).log"
            $p = Start-Process $Archiver.FullName -WorkingDirectory $WorkDir -NoNewWindow -PassThru `
                -ArgumentList "`"$junctions`"", "`"$ArchiveDir`"", "`"$(Join-Path $WorkDir 'oldbooks.k4i')`"" `
                -RedirectStandardOutput $log -RedirectStandardError "$log.err"
            $null = $p.Handle

            $stuck = $null; $lastSize = -1; $startCount = $done.Count; $lastCount = $startCount; $lastChange = Get-Date
            while (-not $p.HasExited) {
                Start-Sleep -Seconds 5
                $size = (Get-Item $log -ErrorAction SilentlyContinue).Length
                $count = @(Get-ChildItem $ArchiveDir -Filter *.kfx-zip).Count
                if ($count -ne $lastCount) { Say "    $($count - $startCount) of $($pending.Count) extracted" }
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
            Warn "$stuck hung for $StallSeconds s and was skipped. In Kindle: Remove download, download again, open it."
        }
    } finally {
        Reset-JunctionDir $junctions
    }
    $skipped
}

# Imports the extracted books for -Asins; returns the new Calibre ids.
function Import-Books {
    param([Parameter(Mandatory)][string]$Library, [string[]]$Asins)
    $files = @($Asins | ForEach-Object { Join-Path $ArchiveDir "${_}_EBOK.kfx-zip" } | Where-Object { Test-Path $_ })
    if ($files.Count -eq 0) { return }
    New-Item -ItemType Directory -Force $Library | Out-Null
    $r = Invoke-Native $Calibredb (@('add', '--with-library', $Library) + $files)
    $ids = @()
    if ($r.Output -match 'Added book ids: ([\d, ]+)') { $ids = @($Matches[1] -split ',\s*' | Where-Object { $_ } | ForEach-Object { [int]$_ }) }
    if ($r.Output -match 'already exist') { Warn 'some books were already in the Calibre library and were skipped' }
    foreach ($b in @(Get-LibraryBooks -Library $Library | Where-Object { $ids -contains $_.id })) {
        if (-not ($b.formats -like '*.kfx')) { Fail "$($b.title): imported as KFX-ZIP - DRM was not removed" }
    }
    $ids
}

# Converts the KFX of each id to EPUB and stores it in Calibre. Without -Replace,
# ids that already have an EPUB are skipped. Returns the converted ids.
function Convert-Books {
    param([Parameter(Mandatory)][string]$Library, [int[]]$CalibreIds, [switch]$Replace)
    $todo = @(Get-LibraryBooks -Library $Library | Where-Object {
        $CalibreIds -contains $_.id -and ($_.formats -like '*.kfx') -and ($Replace -or -not ($_.formats -like '*.epub'))
    })
    if ($todo.Count -eq 0) { return }
    $tmp = Join-Path $WorkDir 'epub'
    New-Item -ItemType Directory -Force $tmp, (Join-Path $WorkDir 'logs') | Out-Null
    $convert = Join-Path $CalibreDir 'ebook-convert.exe'
    $i = 0
    foreach ($b in $todo) {
        $i++
        $kfx = @($b.formats -like '*.kfx')[0]
        $epub = Join-Path $tmp "$($b.id).epub"
        Remove-Item $epub -ErrorAction SilentlyContinue
        Write-Host ("  [{0}/{1}] converting {2}" -f $i, $todo.Count, $b.title) -NoNewline
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

# Exports each id's EPUB one at a time through a temp folder, overwriting the copy in -OutDir.
# Returns @{ id = final path }.
function Export-Epubs {
    param([Parameter(Mandatory)][string]$Library, [Parameter(Mandatory)][string]$OutDir, [int[]]$CalibreIds)
    $result = @{}
    if (-not $CalibreIds) { return $result }
    New-Item -ItemType Directory -Force $OutDir | Out-Null
    $tmp = Join-Path $WorkDir 'export-tmp'
    foreach ($id in $CalibreIds) {
        if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
        New-Item -ItemType Directory $tmp | Out-Null
        Invoke-Native $Calibredb @('export', '--with-library', $Library, "$id", '--formats', 'epub',
            '--dont-save-cover', '--dont-write-opf', '--single-dir', '--to-dir', $tmp) | Out-Null
        $file = Get-ChildItem $tmp -Filter *.epub | Select-Object -First 1
        if ($file) {
            $dest = Join-Path $OutDir $file.Name
            Move-Item $file.FullName $dest -Force
            $result[$id] = $dest
        }
    }
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    $result
}

function New-Result($book, [bool]$ok, $message) {
    [pscustomobject]@{ Key = $book.Key; Title = $book.Title; Ok = $ok; Message = $message }
}

# Runs Convert / Reconvert / Reexport on merged book records; returns one result per book.
function Invoke-BookAction {
    param([object[]]$Books, [ValidateSet('Convert', 'Reconvert', 'Reexport')][string]$Action, [Parameter(Mandatory)]$Settings)
    $lib = $Settings.Library
    $results = @{}
    $index = Read-TitleIndex
    $work = @()
    foreach ($b in $Books) {
        $why = $null
        if ($b.Status -eq 'incomplete') { $why = 'incomplete download - re-download it in Kindle' }
        elseif ($Action -eq 'Reconvert' -and -not $b.HasKfx) { $why = 'not in Calibre as KFX - use Convert first' }
        elseif ($Action -eq 'Reexport' -and -not $b.HasEpub) { $why = 'has no EPUB yet - use Convert first' }
        if ($why) { $results[$b.Key] = New-Result $b $false $why } else { $work += $b }
    }

    if ($Action -eq 'Convert') {
        $toExtract = @($work | Where-Object { $_.Status -eq 'new' })
        if ($toExtract) {
            $archiver = Find-Archiver
            if (-not $archiver) { throw 'no extractor matches your Kindle version - see Check prerequisites' }
            Stop-AppIfRunning 'Kindle' 'Kindle'
            $kindleBooks = @($toExtract | ForEach-Object { [pscustomobject]@{ Name = "$($_.Asin)_EBOK"; FullName = $_.KindlePath } })
            $null = Invoke-Archiver -Archiver $archiver -Books $kindleBooks -StallSeconds $Settings.StallSeconds
            Update-TitleIndex -Index $index -Asins @($toExtract | ForEach-Object Asin)
        }
    }
    if ($work) { Stop-AppIfRunning 'calibre' 'Calibre' }

    if ($Action -eq 'Convert') {
        $extracted = Get-ExtractedBooks
        $toImport = @($work | Where-Object { $_.Asin -and -not $_.CalibreId -and $extracted.ContainsKey($_.Asin) } | ForEach-Object Asin)
        if ($toImport) { $null = Import-Books -Library $lib -Asins $toImport }
    }

    # Refresh records so freshly imported books have Calibre ids and formats.
    $current = @{}
    foreach ($r in (Get-BookIndex -Library $lib)) { $current[$r.Key] = $r }
    $work = @($work | ForEach-Object { if ($current.ContainsKey($_.Key)) { $current[$_.Key] } else { $_ } })

    $ids = @($work | Where-Object CalibreId | ForEach-Object CalibreId)
    $converted = @()
    if ($Action -eq 'Convert') { $converted = @(Convert-Books -Library $lib -CalibreIds $ids) }
    if ($Action -eq 'Reconvert') { $converted = @(Convert-Books -Library $lib -CalibreIds $ids -Replace) }

    $toExport = @($work | Where-Object {
        $_.CalibreId -and (($converted -contains $_.CalibreId) -or $Action -eq 'Reexport' -or
            ($Action -eq 'Convert' -and $_.HasEpub -and -not ($_.Exported -and (Test-Path $_.Exported))))
    } | ForEach-Object CalibreId)
    $exported = Export-Epubs -Library $lib -OutDir $Settings.OutDir -CalibreIds $toExport

    foreach ($b in $work) {
        if ($b.CalibreId -and $exported.ContainsKey($b.CalibreId)) {
            if (-not $index.ContainsKey($b.Key)) { $index[$b.Key] = @{ Title = $b.Title; Authors = $b.Authors; Exported = $null } }
            $index[$b.Key].Exported = $exported[$b.CalibreId]
            $results[$b.Key] = New-Result $b $true $exported[$b.CalibreId]
        } elseif ($Action -eq 'Convert' -and $b.HasEpub -and $b.Exported -and (Test-Path $b.Exported)) {
            $results[$b.Key] = New-Result $b $true "already done: $($b.Exported)"
        } elseif ($Action -eq 'Convert' -and -not $b.CalibreId) {
            $results[$b.Key] = New-Result $b $false 'extraction or import failed - see logs in work\logs'
        } else {
            $results[$b.Key] = New-Result $b $false "conversion or export failed - see $WorkDir\logs"
        }
    }
    Save-TitleIndex -Index $index
    @($Books | ForEach-Object { $results[$_.Key] })
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
    foreach ($d in 'epub', 'export-tmp') { Remove-Item (Join-Path $WorkDir $d) -Recurse -Force -ErrorAction SilentlyContinue }
    Ok 'removed work-in-progress files'
    Say "  Kept: $ArchiveDir (extracted books) and the key files in $WorkDir."
    Say '  The .k4i / .keyfile files unlock your Amazon books - keep them private.'
}
