$lib = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..\lib'
. "$lib\Ui.ps1"

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
