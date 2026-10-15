$lib = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..\lib'
. "$lib\Config.ps1"; . "$lib\Ui.ps1"; . "$lib\Native.ps1"; . "$lib\Prereqs.ps1"

Describe 'Find-Archiver' {
    $tools = Join-Path $TestDrive 'tools'
    New-Item -ItemType Directory $tools | Out-Null
    New-Item -ItemType File (Join-Path $tools 'MSIXKFXArchiver_x64_1_25218.exe') | Out-Null
    New-Item -ItemType File (Join-Path $tools 'MSIXKFXArchiver1_23620_final.exe') | Out-Null

    It 'matches the x64 build' { (Find-Archiver -Build 25218 -Dir $tools).Name | Should Be 'MSIXKFXArchiver_x64_1_25218.exe' }
    It 'matches a build with a suffix' { (Find-Archiver -Build 23620 -Dir $tools).Name | Should Be 'MSIXKFXArchiver1_23620_final.exe' }
    It 'does not match a partial build number' { Find-Archiver -Build 2521 -Dir $tools | Should BeNullOrEmpty }
    It 'returns nothing for an unknown build' { Find-Archiver -Build 99999 -Dir $tools | Should BeNullOrEmpty }
}
