# Console output, prompts and the book-selection parser. No dependencies.

$script:AssumeYes = $false

function Say($msg)  { Write-Host $msg }
function Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Ok($msg)   { Write-Host "  [ok]   $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "  [warn] $msg" -ForegroundColor Yellow }
function Fail($msg) { Write-Host "  [fail] $msg" -ForegroundColor Red }
function Show-Value($v) { if ($v) { "$v" } else { '-' } }

# Read-Host returns $null once piped input runs out; stop instead of looping on empty answers.
function Read-Line($prompt) {
    $answer = Read-Host $prompt
    if ($null -eq $answer) { throw 'input closed - no more answers to read' }
    "$answer"
}

function Confirm-Step($question) {
    if ($script:AssumeYes) { return $true }
    $answer = Read-Line "  $question [Y/n]"
    return ($answer -eq '' -or $answer -match '^[Yy]')
}

function Read-MenuChoice {
    param([string]$Prompt = '  >', [Parameter(Mandatory)][AllowEmptyString()][string[]]$Valid)
    while ($true) {
        $answer = (Read-Line $Prompt).Trim().ToLower()
        if ($Valid -contains $answer) { return $answer }
        Say "  Choose one of: $($Valid -join ', ')"
    }
}

function Get-ConsoleWidth {
    try { $w = [Console]::WindowWidth } catch { $w = 0 }
    if ($w -lt 60) { 100 } else { $w }
}

function Limit-Text([string]$text, [int]$width) {
    if ($text.Length -le $width) { return $text }
    $text.Substring(0, [math]::Max(1, $width - 1)) + '~'
}

# Prints the numbered book list; title and author share the space left by # and Status.
function Write-BookTable {
    param([object[]]$Books)
    $room = (Get-ConsoleWidth) - 4 - 5 - 16 - 4
    $titleWidth = [math]::Max(10, [int]($room * 0.6))
    $authorWidth = [math]::Max(8, $room - $titleWidth)
    $fmt = "  {0,3}  {1,-$titleWidth} {2,-$authorWidth} {3}"
    Write-Host ($fmt -f '#', 'Title', 'Author', 'Status')
    $i = 0
    foreach ($b in $Books) {
        $i++
        $color = switch ($b.Status) {
            'EPUB done'      { 'Green' }
            'incomplete'     { 'Yellow' }
            'not downloaded' { 'DarkGray' }
            default          { 'White' }
        }
        $line = $fmt -f $i, (Limit-Text "$($b.Title)" $titleWidth), (Limit-Text "$($b.Authors)" $authorWidth), $b.Status
        Write-Host $line -ForegroundColor $color
    }
}

# Turns "1,3  2-5  all  new" into 1-based row numbers, unique and ascending.
function ConvertFrom-Selection {
    param([string]$Text, [Parameter(Mandatory)][int]$Count, [int[]]$NewIndexes = @())
    $text = "$Text".Trim().ToLower()
    if ($text -eq '') { return @() }
    if ($text -eq 'all') { return @(1..$Count) }
    if ($text -eq 'new') {
        if (-not $NewIndexes) { throw 'no new books to pick - all listed books are already converted' }
        return @($NewIndexes | Sort-Object -Unique)
    }
    $picked = @()
    foreach ($part in $text -split ',') {
        $part = $part.Trim()
        if ($part -eq '') { continue }
        if ($part -match '^\d+$') {
            $from = [int]$part; $to = $from
        } elseif ($part -match '^(\d+)\s*-\s*(\d+)$') {
            $from = [int]$Matches[1]; $to = [int]$Matches[2]
            if ($from -gt $to) { throw "'$part' is reversed - write it as $to-$from" }
        } else {
            throw "'$part' not understood - use numbers like 1,3 or 2-5, or all / new"
        }
        if ($from -lt 1 -or $to -gt $Count) { throw "'$part' is out of range - pick between 1 and $Count" }
        $picked += $from..$to
    }
    @($picked | Sort-Object -Unique)
}
