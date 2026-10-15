# Renames EPUB files to "Title - Author.epub" from the metadata inside each file, or cleans the
# current name when there is none. Depends on: Ui (and Library's title index for Invoke-RenameEpubs).

Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

$script:MaxStemLength = 150

# Makes text safe as a file name (without extension). A colon becomes " - ", characters Windows
# forbids become spaces; -Strict also turns every symbol except - ' , . & ( ) into a space.
function ConvertTo-SafeFileStem([string]$Text, [switch]$Strict) {
    $s = "$Text" -replace '\s*:\s*', ' - '
    $s = $s -replace '[\\/*?"<>|\x00-\x1F]', ' '
    if ($Strict) { $s = $s -replace "[^\p{L}\p{M}\p{N} \-',.&()]", ' ' }
    $s = ($s -replace '\s+', ' ').Trim(' ', '.', '-')
    if ($s.Length -gt $script:MaxStemLength) { $s = $s.Substring(0, $script:MaxStemLength).TrimEnd(' ', '.', '-') }
    $s
}

function Read-ZipText($Zip, [string]$Name) {
    $entry = $Zip.GetEntry($Name)
    if (-not $entry) { $entry = $Zip.Entries | Where-Object { $_.FullName -eq $Name } | Select-Object -First 1 }
    if (-not $entry) { return $null }
    $reader = New-Object IO.StreamReader($entry.Open())
    try { $reader.ReadToEnd() } finally { $reader.Dispose() }
}

function Get-CollapsedText($node) { if ($node) { ("$($node.InnerText)" -replace '\s+', ' ').Trim() } }

# Returns @{ Title; Authors } from the EPUB's OPF file, or $null when the file is unreadable or has no title.
# Creators with a role other than author (translator, editor...) and Calibre's "Unknown" are left out.
function Get-EpubMetadata([string]$Path) {
    try { $zip = [IO.Compression.ZipFile]::OpenRead($Path) } catch { return $null }
    try {
        $container = Read-ZipText $zip 'META-INF/container.xml'
        if (-not $container) { return $null }
        $rootfile = ([xml]$container).SelectSingleNode("//*[local-name()='rootfile']")
        if (-not $rootfile) { return $null }
        $opfText = Read-ZipText $zip ([Uri]::UnescapeDataString($rootfile.GetAttribute('full-path')))
        if (-not $opfText) { return $null }
        $opf = [xml]$opfText
        $title = Get-CollapsedText $opf.SelectSingleNode("//*[local-name()='metadata']/*[local-name()='title']")
        if (-not $title) { return $null }
        $roles = @{}
        foreach ($m in $opf.SelectNodes("//*[local-name()='metadata']/*[local-name()='meta']")) {
            if ($m.GetAttribute('property') -eq 'role' -and $m.GetAttribute('refines')) {
                $roles[$m.GetAttribute('refines').TrimStart('#')] = "$($m.InnerText)".Trim()
            }
        }
        $authors = @()
        foreach ($c in $opf.SelectNodes("//*[local-name()='metadata']/*[local-name()='creator']")) {
            $role = $c.GetAttribute('role', 'http://www.idpf.org/2007/opf')
            if (-not $role -and $c.GetAttribute('id')) { $role = $roles[$c.GetAttribute('id')] }
            if ($role -and $role -ne 'aut') { continue }
            $name = Get-CollapsedText $c
            if ($name -and $name -ne 'Unknown') { $authors += $name }   # "Unknown" is Calibre's placeholder
        }
        [pscustomobject]@{ Title = $title; Authors = $authors }
    } catch {
        $null
    } finally {
        $zip.Dispose()
    }
}

# The name a file should have: @{ Name = 'Title - A & B.epub' or $null; Source = metadata|cleaned }.
function Get-EpubTargetName([string]$Path) {
    $m = Get-EpubMetadata $Path
    $stem = $null
    if ($m) {
        $authors = @($m.Authors | ForEach-Object { ConvertTo-SafeFileStem $_ } | Where-Object { $_ }) -join ' & '
        $title = ConvertTo-SafeFileStem $m.Title
        if ($title) { $stem = ConvertTo-SafeFileStem $(if ($authors) { "$title - $authors" } else { $title }) }
    }
    if ($stem) { $source = 'metadata' }
    else {
        $stem = ConvertTo-SafeFileStem ([IO.Path]::GetFileNameWithoutExtension($Path)) -Strict
        $source = 'cleaned'
    }
    [pscustomobject]@{ Name = $(if ($stem) { "$stem.epub" }); Source = $source }
}

# Works out every file's new name without touching anything. Action = rename | same | skip.
# A name already used in the folder (by another file, or earlier in the plan) gets " (2)", " (3)"...
function Get-RenamePlan([string[]]$Paths) {
    $takenByFolder = @{}
    foreach ($path in $Paths) {
        $folder = [IO.Path]::GetDirectoryName($path)
        $current = [IO.Path]::GetFileName($path)
        if (-not $takenByFolder.ContainsKey($folder)) {
            $set = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
            Get-ChildItem -LiteralPath $folder -Force | ForEach-Object { $null = $set.Add($_.Name) }
            $takenByFolder[$folder] = $set
        }
        $taken = $takenByFolder[$folder]
        $null = $taken.Remove($current)
        $target = Get-EpubTargetName $path
        $item = [pscustomobject]@{ Path = $path; Folder = $folder; Current = $current; New = $target.Name
                                   Source = $target.Source; Action = 'rename'; Note = $null }
        if (-not $target.Name) {
            $item.Action = 'skip'; $item.Note = 'no title inside and nothing left after removing symbols'
            $item.New = $current
        } elseif ($target.Name -ne $current) {
            $stem = [IO.Path]::GetFileNameWithoutExtension($target.Name)
            $n = 2
            while ($taken.Contains($item.New)) { $item.New = "$stem ($n).epub"; $n++ }
        }
        if ($item.New -ceq $current) { $item.Action = if ($item.Action -eq 'skip') { 'skip' } else { 'same' } }
        $null = $taken.Add($item.New)
        $item
    }
}

# Renames the plan's 'rename' items in order. Never overwrites: a clash fails that one file.
function Invoke-RenamePlan($Plan) {
    foreach ($item in @($Plan | Where-Object Action -eq 'rename')) {
        $dest = Join-Path $item.Folder $item.New
        try {
            if ($item.New -eq $item.Current) {
                # Only the letter case changes; Windows needs a detour through a temporary name.
                $tmp = Join-Path $item.Folder ([Guid]::NewGuid().ToString('N') + '.tmp')
                [IO.File]::Move($item.Path, $tmp)
                [IO.File]::Move($tmp, $dest)
            } else {
                [IO.File]::Move($item.Path, $dest)
            }
            [pscustomobject]@{ Current = $item.Current; New = $item.New; OldPath = $item.Path; NewPath = $dest; Ok = $true; Message = $null }
        } catch {
            [pscustomobject]@{ Current = $item.Current; New = $item.New; OldPath = $item.Path; NewPath = $null; Ok = $false
                               Message = $(if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }) }
        }
    }
}

# Points the title index's exported paths at renamed files. $Map: old path -> new path. Returns the count.
function Update-IndexForRenames([hashtable]$Index, [hashtable]$Map) {
    $n = 0
    foreach ($entry in $Index.Values) {
        if ($entry.Exported -and $Map.ContainsKey($entry.Exported)) { $entry.Exported = $Map[$entry.Exported]; $n++ }
    }
    $n
}

function Write-RenamePlan($Items) {
    $room = (Get-ConsoleWidth) - 4 - 5 - 9 - 3
    $curWidth = [math]::Max(12, [int]($room * 0.42))
    $newWidth = [math]::Max(12, $room - $curWidth)
    $fmt = "  {0,3}  {1,-$curWidth} {2,-$newWidth} {3}"
    Write-Host ($fmt -f '#', 'Current name', 'New name', 'Source')
    $i = 0
    foreach ($p in $Items) {
        $i++
        if ($p.Action -eq 'skip') {
            Write-Host ($fmt -f $i, (Limit-Text $p.Current $curWidth), '(skipped)', '') -ForegroundColor DarkGray
        } else {
            $color = if ($p.Source -eq 'cleaned') { 'Yellow' } else { 'White' }
            Write-Host ($fmt -f $i, (Limit-Text $p.Current $curWidth), (Limit-Text $p.New $newWidth), $p.Source) -ForegroundColor $color
        }
    }
}

# Lists .epub files at a path (a file or a folder), sorted by name.
function Get-EpubFiles([string]$Path, [switch]$Recurse) {
    $item = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $item) { throw "not found: $Path" }
    if (-not $item.PSIsContainer) {
        if ($item.Extension -ne '.epub') { throw "$($item.Name) is not an .epub file" }
        return @($item.FullName)
    }
    @(Get-ChildItem -LiteralPath $Path -Filter *.epub -File -Recurse:$Recurse | Sort-Object DirectoryName, Name | ForEach-Object FullName)
}

# Preview, confirm, rename, then keep the title index pointing at renamed exports.
function Invoke-RenameEpubs([string]$Path, [switch]$Recurse) {
    $files = @(Get-EpubFiles -Path $Path -Recurse:$Recurse)
    if (-not $files) { Warn "no .epub files in $Path"; return }
    Step "Reading $($files.Count) EPUB file(s) in $Path"
    $plan = @(Get-RenamePlan $files)
    $toRename = @($plan | Where-Object Action -eq 'rename')
    $skipped = @($plan | Where-Object Action -eq 'skip')
    $same = $plan.Count - $toRename.Count - $skipped.Count
    if ($toRename -or $skipped) { Write-Host ''; Write-RenamePlan @($toRename + $skipped) }
    Say "`n  $($toRename.Count) to rename, $same already correct, $($skipped.Count) skipped."
    if ($skipped) { Say '  Skipped files have no title inside and only symbols in their name.' }
    if (-not $toRename) { Ok 'nothing to rename'; return }
    if (-not (Confirm-Step "Rename $($toRename.Count) file(s)?")) { Say '  Nothing renamed.'; return }

    $map = @{}
    foreach ($r in @(Invoke-RenamePlan $plan)) {
        if ($r.Ok) { Ok "$($r.New)"; $map[$r.OldPath] = $r.NewPath }
        else { Fail "$($r.Current) - $($r.Message)" }
    }
    if ($map.Count -and (Test-Path $IndexPath)) {
        $index = Read-TitleIndex
        if ((Update-IndexForRenames -Index $index -Map $map) -gt 0) { Save-TitleIndex -Index $index }
    }
    Say "  Renamed $($map.Count) of $($toRename.Count)."
}
