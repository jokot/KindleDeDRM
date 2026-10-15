# One merged list of books from Kindle, the extractor output, the title index and Calibre.
# Depends on: Config, Ui, Native, Prereqs (Get-KindleContentDir).

$StatusOrder = @{ 'incomplete' = 1; 'new' = 2; 'extracted' = 3; 'in Calibre' = 4; 'EPUB done' = 5; 'not downloaded' = 6; 'other format' = 7 }

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
    param([Parameter(Mandatory)][string]$Library)
    if (-not (Test-Path (Join-Path $Library 'metadata.db'))) { return }
    $r = Invoke-Native $Calibredb @('list', '--with-library', $Library, '--fields', 'title,authors,formats,identifiers', '--for-machine') -StdoutOnly
    if ($r.Code -ne 0) { throw "could not read the Calibre library at $Library - close Calibre and try again" }
    if (-not "$($r.Output)".Trim()) { return }
    $books = $r.Output | ConvertFrom-Json
    $books
}

function Get-ExtractedBooks {
    $map = @{}
    Get-ChildItem $ArchiveDir -Filter *.kfx-zip -ErrorAction SilentlyContinue |
        ForEach-Object { $map[$_.BaseName -replace '_EBOK$'] = $_.FullName }
    $map
}

# index.json: ASIN -> @{ Title; Authors; Exported }. Missing -> empty; corrupt -> renamed to .bad.
function Read-TitleIndex {
    param([string]$Path = $IndexPath)
    $index = @{}
    if (-not (Test-Path $Path)) { return $index }
    try {
        $saved = Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        Move-Item $Path "$Path.bad" -Force
        Warn "title index was unreadable - renamed to $Path.bad, titles will be read again"
        return $index
    }
    foreach ($p in $saved.PSObject.Properties) {
        $index[$p.Name] = @{ Title = $p.Value.Title; Authors = $p.Value.Authors; Exported = $p.Value.Exported }
    }
    $index
}

function Save-TitleIndex {
    param([Parameter(Mandatory)][hashtable]$Index, [string]$Path = $IndexPath)
    $ordered = [ordered]@{}
    foreach ($k in ($Index.Keys | Sort-Object)) { $ordered[$k] = $Index[$k] }
    [IO.File]::WriteAllText($Path, ($ordered | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding $false))
}

# Reads title/author from each extracted book that has no index entry yet (~2 s per book).
function Update-TitleIndex {
    param([Parameter(Mandatory)][hashtable]$Index, [string[]]$Asins)
    $todo = @($Asins | Where-Object { $_ -and -not $Index.ContainsKey($_) -and (Test-Path (Join-Path $ArchiveDir "${_}_EBOK.kfx-zip")) })
    $meta = Join-Path $CalibreDir 'ebook-meta.exe'
    $i = 0
    foreach ($asin in $todo) {
        $i++
        Write-Host "`r  reading titles $i/$($todo.Count)" -NoNewline
        $out = (Invoke-Native $meta @((Join-Path $ArchiveDir "${asin}_EBOK.kfx-zip")) -StdoutOnly).Output
        $entry = @{ Title = $null; Authors = $null; Exported = $null }
        foreach ($line in $out -split "`n") {
            if ($line -match '^Title\s*:\s*(.+?)\s*$') { $entry.Title = $Matches[1] }
            elseif ($line -match '^Author\(s\)\s*:\s*(.+?)(\s*\[.*\])?\s*$') { $entry.Authors = $Matches[1] }
        }
        $Index[$asin] = $entry
        Save-TitleIndex -Index $Index
    }
    if ($todo.Count) { Write-Host '' }
}

function Get-FirstFormat($formats, $ext) {
    @($formats | Where-Object { $_ -like "*.$ext" })[0]
}

# Pure: merges the four sources on ASIN and assigns each book one status (spec 5.1).
function Merge-BookIndex {
    param([object[]]$Kindle = @(), [hashtable]$Extracted = @{}, [hashtable]$Titles = @{}, [object[]]$Calibre = @())
    $records = [ordered]@{}
    function Get-Record($key, $asin) {
        if (-not $records.Contains($key)) {
            $records[$key] = [pscustomobject]@{
                Key = $key; Asin = $asin; Title = $null; Authors = $null; Status = $null; StatusOrder = 0
                Downloaded = $false; Complete = $false; KindlePath = $null; Extracted = $false; KfxZipPath = $null
                CalibreId = $null; HasKfx = $false; HasEpub = $false; KfxPath = $null; EpubPath = $null; Exported = $null
            }
        }
        $records[$key]
    }
    foreach ($k in $Kindle) {
        $r = Get-Record $k.Asin $k.Asin
        $r.Downloaded = $true; $r.Complete = [bool]$k.Complete; $r.KindlePath = $k.FullName
    }
    foreach ($asin in $Extracted.Keys) {
        $r = Get-Record $asin $asin
        $r.Extracted = $true; $r.KfxZipPath = $Extracted[$asin]
    }
    foreach ($c in $Calibre) {
        $asin = $null
        if ($c.identifiers) { $asin = $c.identifiers.'mobi-asin' }
        $r = if ($asin) { Get-Record $asin $asin } else { Get-Record "calibre:$($c.id)" $null }
        $r.CalibreId = [int]$c.id; $r.Title = $c.title; $r.Authors = $c.authors
        $r.KfxPath = Get-FirstFormat $c.formats 'kfx'; $r.EpubPath = Get-FirstFormat $c.formats 'epub'
        $r.HasKfx = [bool]$r.KfxPath; $r.HasEpub = [bool]$r.EpubPath
    }
    foreach ($r in $records.Values) {
        if ($Titles.ContainsKey($r.Key)) {
            $t = $Titles[$r.Key]
            if (-not $r.Title) { $r.Title = $t.Title }
            if (-not $r.Authors) { $r.Authors = $t.Authors }
            $r.Exported = $t.Exported
        }
        if (-not $r.Title) { $r.Title = $r.Asin }
        $r.Status =
            if ($r.Downloaded -and -not $r.Complete) { 'incomplete' }
            elseif ($r.Downloaded -and -not $r.Extracted -and -not $r.CalibreId) { 'new' }
            elseif ($r.Extracted -and -not $r.CalibreId) { 'extracted' }
            elseif ($r.HasEpub -and $r.Downloaded) { 'EPUB done' }
            elseif ($r.HasEpub) { 'not downloaded' }
            elseif ($r.HasKfx) { 'in Calibre' }
            else { 'other format' }   # e.g. PDF-only, or a KFX-ZIP whose DRM was not removed
        $r.StatusOrder = $StatusOrder[$r.Status]
    }
    @($records.Values)
}

function Get-BookIndex {
    param([Parameter(Mandatory)][string]$Library)
    Merge-BookIndex -Kindle @(Get-KindleBooks) -Extracted (Get-ExtractedBooks) -Titles (Read-TitleIndex) -Calibre @(Get-LibraryBooks -Library $Library)
}

# Case-insensitive substring match on title or author; unconverted books first.
function Find-Books {
    param([object[]]$Books, [string]$Query)
    $q = "$Query".Trim()
    $hits = if ($q) {
        $Books | Where-Object {
            "$($_.Title)".IndexOf($q, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            "$($_.Authors)".IndexOf($q, [StringComparison]::OrdinalIgnoreCase) -ge 0
        }
    } else { $Books }
    @($hits | Sort-Object StatusOrder, Title)
}
