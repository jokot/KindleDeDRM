# Title banner for the main menu. No dependencies.
# Art generated with FIGlet: "ANSI Shadow" for wide windows, "Slant" for narrow ones.
# ANSI Shadow is stored as ASCII so this file stays safe for PowerShell 5.1 (which reads BOM-less files as ANSI):
#   # = full block    - = double line    ! = double bar    [ ] < > = double-line corners

$script:BannerWide = @'
##]  ##]##]###]   ##]######] ##]     #######]######] #######]######] ######] ###]   ###]
##! ##[>##!####]  ##!##[--##]##!     ##[---->##[--##]##[---->##[--##]##[--##]####] ####!
#####[> ##!##[##] ##!##!  ##!##!     #####]  ##!  ##!#####]  ##!  ##!######[>##[####[##!
##[-##] ##!##!<##]##!##!  ##!##!     ##[-->  ##!  ##!##[-->  ##!  ##!##[--##]##!<##[>##!
##!  ##]##!##! <####!######[>#######]#######]######[>#######]######[>##!  ##!##! <-> ##!
<->  <-><-><->  <---><-----> <------><------><-----> <------><-----> <->  <-><->     <->
'@ -split "`r?`n"

$script:BannerNarrow = @'
    __ __ _           ____     ____       ____  ____  __  ___
   / //_/(_)___  ____/ / /__  / __ \___  / __ \/ __ \/  |/  /
  / ,<  / / __ \/ __  / / _ \/ / / / _ \/ / / / /_/ / /|_/ /
 / /| |/ / / / / /_/ / /  __/ /_/ /  __/ /_/ / _, _/ /  / /
/_/ |_/_/_/ /_/\__,_/_/\___/_____/\___/_____/_/ |_/_/  /_/
'@ -split "`r?`n"

$script:BannerGlyphs = @{
    '#' = [char]0x2588; '-' = [char]0x2550; '!' = [char]0x2551
    '[' = [char]0x2554; ']' = [char]0x2557; '<' = [char]0x255A; '>' = [char]0x255D
}

# Sunset gradient, left to right: gold, orange, pink, violet.
$script:BannerStops = @(@(255, 195, 0), @(255, 122, 24), @(255, 61, 127), @(162, 59, 255))

function Expand-BannerLine([string]$Line, [hashtable]$Glyphs = $script:BannerGlyphs) {
    -join ($Line.ToCharArray() | ForEach-Object { $g = $Glyphs["$_"]; if ($g) { $g } else { $_ } })
}

# Returns @(r, g, b) at position $T (0..1) along the gradient stops.
function Get-GradientColor([double]$T, $Stops = $script:BannerStops) {
    $T = [math]::Min(1.0, [math]::Max(0.0, $T))
    $segments = $Stops.Count - 1
    $i = [math]::Min($segments - 1, [math]::Floor($T * $segments))
    $f = $T * $segments - $i
    $a = $Stops[$i]; $b = $Stops[$i + 1]
    @(0..2 | ForEach-Object { [int][math]::Round($a[$_] + ($b[$_] - $a[$_]) * $f) })
}

# Colours each character by its column with 24-bit ANSI codes. Solid blocks get the full colour,
# the box-drawing "shadow" a darker shade, which gives the letters depth.
function Format-BannerLine([string]$Line, [int]$Width, [hashtable]$Glyphs = $script:BannerGlyphs) {
    $esc = [char]27
    $sb = New-Object System.Text.StringBuilder
    for ($x = 0; $x -lt $Line.Length; $x++) {
        $c = $Line[$x]
        if ($c -eq ' ') { $null = $sb.Append(' '); continue }
        $rgb = Get-GradientColor ($x / [math]::Max(1, $Width - 1))
        if ($c -ne '#' -and $Glyphs.ContainsKey("$c")) { $rgb = @($rgb | ForEach-Object { [int]($_ * 0.45) }) }
        $glyph = $Glyphs["$c"]; if (-not $glyph) { $glyph = $c }
        $null = $sb.Append("$esc[38;2;$($rgb[0]);$($rgb[1]);$($rgb[2])m$glyph")
    }
    $sb.Append("$esc[0m").ToString()
}

function Show-Banner {
    $width = try { $Host.UI.RawUI.WindowSize.Width } catch { 80 }
    $vt = $Host.UI.SupportsVirtualTerminal -and -not $env:NO_COLOR
    $wide = $width -ge 92
    $art = if ($wide) { $script:BannerWide } else { $script:BannerNarrow }
    $glyphs = if ($wide) { $script:BannerGlyphs } else { @{} }
    $artWidth = ($art | Measure-Object -Property Length -Maximum).Maximum
    $fallback = 'Yellow', 'Yellow', 'DarkYellow', 'Red', 'Magenta', 'DarkMagenta'
    for ($y = 0; $y -lt $art.Count; $y++) {
        if ($vt) { Write-Host ('  ' + (Format-BannerLine $art[$y] $artWidth $glyphs)) }
        else { Write-Host ('  ' + (Expand-BannerLine $art[$y] $glyphs)) -ForegroundColor $fallback[$y] }
    }
    Write-Host ''
    Write-Host '  Unlock the Kindle books you own  ' -NoNewline -ForegroundColor DarkGray
    Write-Host "v$AppVersion" -NoNewline -ForegroundColor Yellow
    Write-Host '  github.com/jokot/KindleDeDRM' -ForegroundColor DarkGray
}
