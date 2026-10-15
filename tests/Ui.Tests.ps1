$lib = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..\lib'
. "$lib\Ui.ps1"

Describe 'Read-Line' {
    It 'returns what was typed' {
        Mock Read-Host { 'abc' }
        Read-Line 'prompt' | Should Be 'abc'
    }
    It 'throws when input is closed instead of looping on empty answers' {
        Mock Read-Host { $null }
        { Read-Line 'prompt' } | Should Throw 'input closed'
    }
}

Describe 'Read-MenuChoice' {
    It 'accepts a blank answer when blank is a valid choice' {
        Mock Read-Host { '' }
        Read-MenuChoice -Valid '', '0', '1' | Should Be ''
    }
    It 'normalises case and spaces' {
        Mock Read-Host { ' A ' }
        Read-MenuChoice -Valid '0', 'a' | Should Be 'a'
    }
}

Describe 'ConvertFrom-Selection' {
    It 'parses a list' { (ConvertFrom-Selection -Text '1,3' -Count 5) -join ',' | Should Be '1,3' }
    It 'parses a range' { (ConvertFrom-Selection -Text '2-5' -Count 5) -join ',' | Should Be '2,3,4,5' }
    It 'ignores spaces' { (ConvertFrom-Selection -Text ' 1 , 2-3 ' -Count 5) -join ',' | Should Be '1,2,3' }
    It 'sorts and removes duplicates' { (ConvertFrom-Selection -Text '3,1,3' -Count 5) -join ',' | Should Be '1,3' }
    It 'accepts all in any case' { (ConvertFrom-Selection -Text 'ALL' -Count 4) -join ',' | Should Be '1,2,3,4' }
    It 'accepts new' { (ConvertFrom-Selection -Text 'new' -Count 5 -NewIndexes 2, 4) -join ',' | Should Be '2,4' }
    It 'returns nothing for blank input' { @(ConvertFrom-Selection -Text '' -Count 5).Count | Should Be 0 }

    It 'rejects 0' { { ConvertFrom-Selection -Text '0' -Count 5 } | Should Throw 'out of range' }
    It 'rejects numbers past the end' { { ConvertFrom-Selection -Text '6' -Count 5 } | Should Throw 'out of range' }
    It 'rejects garbage' { { ConvertFrom-Selection -Text 'abc' -Count 5 } | Should Throw 'not understood' }
    It 'rejects reversed ranges' { { ConvertFrom-Selection -Text '5-2' -Count 5 } | Should Throw 'reversed' }
    It 'rejects new when there are no new books' { { ConvertFrom-Selection -Text 'new' -Count 5 -NewIndexes @() } | Should Throw 'no new books' }
}

Describe 'Resolve-BooksInput' {
    function Resolve($text, $count = 5, $new = @(2)) { Resolve-BooksInput -Text $text -Count $count -NewIndexes $new }

    It 'treats blank as clear search' { (Resolve '  ').Kind | Should Be 'clear' }
    It 'treats 0 as back' { (Resolve '0').Kind | Should Be 'back' }
    It 'treats a as the Calibre-only toggle in any case' { (Resolve 'A').Kind | Should Be 'toggle' }
    It 'picks books by number, range, all and new' {
        $r = Resolve '1,3-4'
        $r.Kind | Should Be 'pick'
        $r.Value -join ',' | Should Be '1,3,4'
        (Resolve 'all').Value -join ',' | Should Be '1,2,3,4,5'
        (Resolve 'new').Value -join ',' | Should Be '2'
    }
    It 'searches for anything that is not a pick' {
        $r = Resolve ' harry potter '
        $r.Kind | Should Be 'search'
        $r.Value | Should Be 'harry potter'
    }
    It 'searches for text after a slash, even numbers and keywords' {
        (Resolve '/1984').Value | Should Be '1984'
        (Resolve '/new').Kind | Should Be 'search'
        (Resolve '/a').Value | Should Be 'a'
    }
    It 'clears the search for a lone slash' { (Resolve '/').Kind | Should Be 'clear' }
    It 'reports a bad pick instead of searching for it' {
        $r = Resolve '9'
        $r.Kind | Should Be 'error'
        $r.Value | Should Match 'out of range'
        (Resolve '2-1').Kind | Should Be 'error'
    }
    It 'reports new when nothing is new' { (Resolve 'new' 5 @()).Kind | Should Be 'error' }
}
