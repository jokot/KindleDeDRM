$lib = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..\lib'
. "$lib\Config.ps1"; . "$lib\Ui.ps1"; . "$lib\Native.ps1"; . "$lib\Prereqs.ps1"; . "$lib\Library.ps1"

function New-KindleBook($asin, [bool]$complete = $true) {
    [pscustomobject]@{ Name = "${asin}_EBOK"; Asin = $asin; FullName = "C:\k\${asin}_EBOK"; Complete = $complete; SizeMB = 1 }
}
function New-CalibreBook($id, $asin, $title, $authors, [string[]]$formats) {
    $ids = if ($asin) { [pscustomobject]@{ 'mobi-asin' = $asin } } else { [pscustomobject]@{} }
    [pscustomobject]@{ id = $id; title = $title; authors = $authors; formats = $formats; identifiers = $ids }
}

Describe 'Merge-BookIndex' {
    $kindle = @(
        (New-KindleBook 'B1' $false), (New-KindleBook 'B2'), (New-KindleBook 'B3'),
        (New-KindleBook 'B4'), (New-KindleBook 'B5')
    )
    $extracted = @{ 'B3' = 'C:\a\B3_EBOK.kfx-zip'; 'B4' = 'C:\a\B4_EBOK.kfx-zip'; 'B5' = 'C:\a\B5_EBOK.kfx-zip' }
    $titles = @{
        'B3' = @{ Title = 'Index Three'; Authors = 'Idx Author' }
        'B5' = @{ Title = 'Old Index Title'; Authors = 'Old'; Exported = 'C:\out\Five.epub' }
    }
    $calibre = @(
        (New-CalibreBook 4 'B4' 'Four' 'Author Four' @('C:\lib\4.kfx')),
        (New-CalibreBook 5 'B5' 'Five' 'Author Five' @('C:\lib\5.kfx', 'C:\lib\5.epub')),
        (New-CalibreBook 6 'B6' 'Six' 'Author Six' @('C:\lib\6.kfx', 'C:\lib\6.epub')),
        (New-CalibreBook 7 $null 'Sideloaded' 'Someone' @('C:\lib\7.epub'))
    )
    $books = @(Merge-BookIndex -Kindle $kindle -Extracted $extracted -Titles $titles -Calibre $calibre)
    $byKey = @{}; foreach ($b in $books) { $byKey[$b.Key] = $b }

    It 'marks a download without .azw as incomplete' { $byKey['B1'].Status | Should Be 'incomplete' }
    It 'marks a complete, unextracted download as new' { $byKey['B2'].Status | Should Be 'new' }
    It 'marks an extracted book not in Calibre as extracted' { $byKey['B3'].Status | Should Be 'extracted' }
    It 'marks a KFX-only Calibre book as in Calibre' { $byKey['B4'].Status | Should Be 'in Calibre' }
    It 'marks a downloaded book with EPUB as EPUB done' { $byKey['B5'].Status | Should Be 'EPUB done' }
    It 'marks a Calibre book missing from Kindle as not downloaded' { $byKey['B6'].Status | Should Be 'not downloaded' }

    It 'prefers the Calibre title over the index title' {
        $byKey['B5'].Title | Should Be 'Five'
        $byKey['B5'].Exported | Should Be 'C:\out\Five.epub'
        $byKey['B3'].Title | Should Be 'Index Three'
    }
    It 'falls back to the ASIN when there is no title' { $byKey['B2'].Title | Should Be 'B2' }
    It 'lists Calibre books without an ASIN' {
        $byKey['calibre:7'].Asin | Should BeNullOrEmpty
        $byKey['calibre:7'].Status | Should Be 'not downloaded'
        $byKey['calibre:7'].HasEpub | Should Be $true
    }
    It 'returns nothing for empty inputs' {
        @(Merge-BookIndex -Kindle @() -Extracted @{} -Titles @{} -Calibre @()).Count | Should Be 0
    }

    It 'finds books by author regardless of case' {
        $found = @(Find-Books -Books $books -Query 'AUTHOR FOUR')
        $found.Count | Should Be 1
        $found[0].Key | Should Be 'B4'
    }
    It 'returns everything for a blank query, unconverted books first' {
        $found = @(Find-Books -Books $books -Query '')
        $found.Count | Should Be 7
        ($found | ForEach-Object Status) -join '|' |
            Should Be 'incomplete|new|extracted|in Calibre|EPUB done|not downloaded|not downloaded'
        $found[5].Title | Should Be 'Sideloaded'
    }
}
