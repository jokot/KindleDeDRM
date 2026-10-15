$lib = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..\lib'
. "$lib\Ui.ps1"; . "$lib\Rename.ps1"

Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

# Writes a minimal EPUB: container.xml pointing at OEBPS/content.opf with the given title and creators.
# Each creator is 'Name' or 'Name|role'. -Epub3 puts roles in <meta refines> instead of opf:role.
function New-TestEpub {
    param([string]$Path, [string]$Title, [string[]]$Creators = @(), [switch]$Epub3, [switch]$NoMetadata)
    $dir = Split-Path $Path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory $dir | Out-Null }
    if (Test-Path $Path) { Remove-Item $Path }
    $zip = [IO.Compression.ZipFile]::Open($Path, 'Create')
    try {
        $write = {
            param($name, $text)
            $w = New-Object IO.StreamWriter($zip.CreateEntry($name).Open())
            try { $w.Write($text) } finally { $w.Dispose() }
        }
        & $write 'mimetype' 'application/epub+zip'
        if ($NoMetadata) { return }
        & $write 'META-INF/container.xml' @'
<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>
'@
        $meta = @()
        if ($Title) { $meta += "<dc:title>$([Security.SecurityElement]::Escape($Title))</dc:title>" }
        $i = 0
        foreach ($c in $Creators) {
            $i++
            $name, $role = $c -split '\|'
            $name = [Security.SecurityElement]::Escape($name)
            if ($Epub3) {
                $meta += "<dc:creator id=`"c$i`">$name</dc:creator>"
                if ($role) { $meta += "<meta refines=`"#c$i`" property=`"role`" scheme=`"marc:relators`">$role</meta>" }
            } elseif ($role) {
                $meta += "<dc:creator opf:role=`"$role`">$name</dc:creator>"
            } else {
                $meta += "<dc:creator>$name</dc:creator>"
            }
        }
        & $write 'OEBPS/content.opf' @"
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">
    $($meta -join "`n    ")
  </metadata>
</package>
"@
    } finally { $zip.Dispose() }
}

Describe 'ConvertTo-SafeFileStem' {
    It 'turns a colon into a dash' {
        ConvertTo-SafeFileStem 'The Simple Path to Wealth: Your Road Map' | Should Be 'The Simple Path to Wealth - Your Road Map'
    }
    It 'removes characters Windows does not allow and collapses spaces' {
        ConvertTo-SafeFileStem 'What? "Quotes" <x>|y*  z' | Should Be 'What Quotes x y z'
    }
    It 'keeps other symbols in normal mode' {
        ConvertTo-SafeFileStem 'Book #1 - 100% Done!' | Should Be 'Book #1 - 100% Done!'
    }
    It 'replaces symbols with spaces in strict mode' {
        ConvertTo-SafeFileStem 'my#weird@@file!!' -Strict | Should Be 'my weird file'
        ConvertTo-SafeFileStem 'book_final~v2' -Strict | Should Be 'book final v2'
    }
    It 'keeps letters with accents, numbers and basic punctuation in strict mode' {
        $name = "Saint-Exup$([char]0xE9)ry's Prince, Vol. 1 & 2 (x)"
        ConvertTo-SafeFileStem $name -Strict | Should Be $name
    }
    It 'trims spaces, dots and dashes from the ends' {
        ConvertTo-SafeFileStem ' - Title...  ' | Should Be 'Title'
    }
    It 'shortens very long names' {
        (ConvertTo-SafeFileStem ('a' * 300)).Length | Should Be 150
    }
}

Describe 'Get-EpubMetadata' {
    It 'reads the title and authors' {
        $p = Join-Path $TestDrive 'm1.epub'
        New-TestEpub $p 'Atomic Habits' 'James Clear'
        $m = Get-EpubMetadata $p
        $m.Title | Should Be 'Atomic Habits'
        $m.Authors -join '|' | Should Be 'James Clear'
    }
    It 'skips EPUB2 creators whose role is not author' {
        $p = Join-Path $TestDrive 'm2.epub'
        New-TestEpub $p 'Book' 'Ann Author|aut', 'Tim Translator|trl', 'Bob Writer'
        (Get-EpubMetadata $p).Authors -join '|' | Should Be 'Ann Author|Bob Writer'
    }
    It 'skips EPUB3 creators refined with a non-author role' {
        $p = Join-Path $TestDrive 'm3.epub'
        New-TestEpub $p 'Book' 'Ann Author|aut', 'Ed Editor|edt' -Epub3
        (Get-EpubMetadata $p).Authors -join '|' | Should Be 'Ann Author'
    }
    It 'returns nothing when there is no title' {
        $p = Join-Path $TestDrive 'm4.epub'
        New-TestEpub $p '' 'Someone'
        Get-EpubMetadata $p | Should BeNullOrEmpty
    }
    It 'returns nothing for a file that is not an EPUB' {
        $p = Join-Path $TestDrive 'm5.epub'
        Set-Content $p 'not a zip'
        Get-EpubMetadata $p | Should BeNullOrEmpty
    }
    It 'returns nothing for an EPUB without container.xml' {
        $p = Join-Path $TestDrive 'm6.epub'
        New-TestEpub $p -NoMetadata
        Get-EpubMetadata $p | Should BeNullOrEmpty
    }
}

Describe 'Get-EpubTargetName' {
    It 'builds Title - Author from metadata, joining authors with &' {
        $p = Join-Path $TestDrive 't1.epub'
        New-TestEpub $p 'Make It Stick: The Science' 'Peter Brown', 'Henry Roediger'
        $t = Get-EpubTargetName $p
        $t.Name | Should Be 'Make It Stick - The Science - Peter Brown & Henry Roediger.epub'
        $t.Source | Should Be 'metadata'
    }
    It 'uses the title alone when there is no author' {
        $p = Join-Path $TestDrive 't2.epub'
        New-TestEpub $p 'Lonely Title'
        (Get-EpubTargetName $p).Name | Should Be 'Lonely Title.epub'
    }
    It 'ignores the placeholder author Unknown that Calibre writes' {
        $p = Join-Path $TestDrive 't3.epub'
        New-TestEpub $p 'The Intelligent Investor' 'Unknown'
        (Get-EpubTargetName $p).Name | Should Be 'The Intelligent Investor.epub'
    }
    It 'cleans the current name when there is no metadata' {
        $p = Join-Path $TestDrive 'my#weird@@file!!.epub'
        New-TestEpub $p -NoMetadata
        $t = Get-EpubTargetName $p
        $t.Name | Should Be 'my weird file.epub'
        $t.Source | Should Be 'cleaned'
    }
    It 'gives no name when nothing is left after cleaning' {
        $p = Join-Path $TestDrive '###.epub'
        New-TestEpub $p -NoMetadata
        (Get-EpubTargetName $p).Name | Should BeNullOrEmpty
    }
}

Describe 'Get-RenamePlan and Invoke-RenamePlan' {
    It 'renames, keeps correct names, and never overwrites' {
        $dir = Join-Path $TestDrive 'plan1'
        New-TestEpub (Join-Path $dir 'a.epub') 'Same Book' 'X'
        New-TestEpub (Join-Path $dir 'b.epub') 'Same Book' 'X'
        New-TestEpub (Join-Path $dir 'Kept - Y.epub') 'Kept' 'Y'
        New-TestEpub (Join-Path $dir 'Taken - Z.epub') 'Other' 'Q'
        New-TestEpub (Join-Path $dir 'c.epub') 'Taken' 'Z'
        $plan = @(Get-RenamePlan (Get-ChildItem $dir -Filter *.epub | Sort-Object Name | ForEach-Object FullName))
        $by = @{}; foreach ($p in $plan) { $by[$p.Current] = $p }
        $by['a.epub'].New | Should Be 'Same Book - X.epub'
        $by['b.epub'].New | Should Be 'Same Book - X (2).epub'
        $by['Kept - Y.epub'].Action | Should Be 'same'
        $by['c.epub'].New | Should Be 'Taken - Z (2).epub'
        $by['Taken - Z.epub'].New | Should Be 'Other - Q.epub'

        $results = @(Invoke-RenamePlan $plan)
        @($results | Where-Object { -not $_.Ok }).Count | Should Be 0
        (Get-ChildItem $dir -Name | Sort-Object) -join '|' |
            Should Be 'Kept - Y.epub|Other - Q.epub|Same Book - X (2).epub|Same Book - X.epub|Taken - Z (2).epub'
    }
    It 'renames when only the letter case differs' {
        $dir = Join-Path $TestDrive 'plan2'
        New-TestEpub (Join-Path $dir 'animal farm - george orwell.epub') 'Animal Farm' 'George Orwell'
        $plan = @(Get-RenamePlan @(Join-Path $dir 'animal farm - george orwell.epub'))
        $plan[0].Action | Should Be 'rename'
        $null = Invoke-RenamePlan $plan
        Get-ChildItem $dir -Name | Should BeExactly 'Animal Farm - George Orwell.epub'
    }
    It 'skips a file whose name would be empty' {
        $dir = Join-Path $TestDrive 'plan3'
        New-TestEpub (Join-Path $dir '@@.epub') -NoMetadata
        (Get-RenamePlan @(Join-Path $dir '@@.epub'))[0].Action | Should Be 'skip'
    }
    It 'handles names with [ and ] literally' {
        $dir = Join-Path $TestDrive 'plan4'
        $p = Join-Path $dir 'Saga [Vol 1].epub'
        New-TestEpub $p 'Saga' 'Z'
        $null = Invoke-RenamePlan @(Get-RenamePlan @($p))
        Get-ChildItem $dir -Name | Should Be 'Saga - Z.epub'
    }
}

Describe 'Update-IndexForRenames' {
    It 'points exported paths at the renamed files, ignoring case' {
        $index = @{
            'B1' = @{ Title = 'One'; Authors = 'A'; Exported = 'C:\Out\Old One.epub' }
            'B2' = @{ Title = 'Two'; Authors = 'B'; Exported = 'C:\Out\Two.epub' }
        }
        $n = Update-IndexForRenames -Index $index -Map @{ 'c:\out\old one.epub' = 'C:\Out\One - A.epub' }
        $n | Should Be 1
        $index['B1'].Exported | Should Be 'C:\Out\One - A.epub'
        $index['B2'].Exported | Should Be 'C:\Out\Two.epub'
    }
}
