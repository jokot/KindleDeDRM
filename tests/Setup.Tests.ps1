$lib = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..\lib'
. "$lib\Setup.ps1"

Describe 'Add-PathEntry' {
    It 'appends a new folder' { Add-PathEntry -PathValue 'C:\a;C:\b' -Dir 'C:\k' | Should Be 'C:\a;C:\b;C:\k' }
    It 'leaves PATH unchanged when the folder is already there in another case or with a trailing slash' {
        Add-PathEntry -PathValue 'C:\a;c:\K\;C:\b' -Dir 'C:\k' | Should Be 'C:\a;c:\K\;C:\b'
    }
    It 'handles an empty PATH' { Add-PathEntry -PathValue '' -Dir 'C:\k' | Should Be 'C:\k' }
    It 'drops empty entries' { Add-PathEntry -PathValue 'C:\a;;C:\b' -Dir 'C:\k' | Should Be 'C:\a;C:\b;C:\k' }
}

Describe 'Remove-PathEntry' {
    It 'removes the folder in any case or slash form' { Remove-PathEntry -PathValue 'C:\a;c:\k\;C:\b' -Dir 'C:\k' | Should Be 'C:\a;C:\b' }
    It 'leaves PATH unchanged when the folder is absent' { Remove-PathEntry -PathValue 'C:\a;C:\b' -Dir 'C:\k' | Should Be 'C:\a;C:\b' }
}
