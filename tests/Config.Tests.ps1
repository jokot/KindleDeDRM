$lib = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..\lib'
. "$lib\Config.ps1"

Describe 'Get-Settings / Save-Settings' {
    It 'returns defaults when the file is missing' {
        $s = Get-Settings -Path 'TestDrive:\none.json'
        $s.StallSeconds | Should Be 300
        $s.OutDir | Should Be (Join-Path $env:USERPROFILE 'Documents\Kindle EPUBs')
    }

    It 'round-trips saved values' {
        $path = 'TestDrive:\rt.json'
        $s = Get-DefaultSettings
        $s.OutDir = 'C:\x'
        $s.StallSeconds = 60
        Save-Settings -Settings $s -Path $path
        $r = Get-Settings -Path $path
        $r.OutDir | Should Be 'C:\x'
        $r.StallSeconds | Should Be 60
    }

    It 'fills missing keys with defaults' {
        $path = 'TestDrive:\partial.json'
        Set-Content $path '{"OutDir":"C:\\y"}'
        $r = Get-Settings -Path $path
        $r.OutDir | Should Be 'C:\y'
        $r.Library | Should Be (Join-Path $env:USERPROFILE 'Calibre Library')
    }

    It 'renames a corrupt file to .bad and returns defaults' {
        $path = 'TestDrive:\bad.json'
        Set-Content $path '{nope'
        $r = Get-Settings -Path $path
        Test-Path "$path.bad" | Should Be $true
        $r.StallSeconds | Should Be 300
    }
}
