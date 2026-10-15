$lib = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..\lib'
. "$lib\Banner.ps1"

Describe 'Banner art' {
    It 'has six wide lines and five narrow lines' {
        $script:BannerWide.Count | Should Be 6
        $script:BannerNarrow.Count | Should Be 5
    }
    It 'expands the wide art to blocks and box-drawing characters only' {
        $allowed = @(' ') + @($script:BannerGlyphs.Values | ForEach-Object { "$_" })
        $chars = ($script:BannerWide | ForEach-Object { Expand-BannerLine $_ }) -join '' -split '' | Where-Object { $_ }
        @($chars | Where-Object { $allowed -notcontains $_ }).Count | Should Be 0
    }
    It 'leaves the narrow art untouched when given no glyph map' {
        Expand-BannerLine $script:BannerNarrow[2] @{} | Should Be $script:BannerNarrow[2]
    }
    It 'fits a 92-column window with the two-space indent' {
        ($script:BannerWide | Measure-Object -Property Length -Maximum).Maximum | Should BeLessThan 91
    }
}

Describe 'Get-GradientColor' {
    It 'returns the first stop at 0 and the last stop at 1' {
        (Get-GradientColor 0) -join ',' | Should Be ($script:BannerStops[0] -join ',')
        (Get-GradientColor 1) -join ',' | Should Be ($script:BannerStops[-1] -join ',')
    }
    It 'blends halfway between two stops' {
        (Get-GradientColor 0.5 @(@(0, 0, 0), @(200, 100, 50))) -join ',' | Should Be '100,50,25'
    }
    It 'clamps values outside 0..1' {
        (Get-GradientColor 5) -join ',' | Should Be ($script:BannerStops[-1] -join ',')
    }
}

Describe 'Format-BannerLine' {
    $esc = [char]27
    It 'colours each glyph with a 24-bit code and resets at the end' {
        $out = Format-BannerLine '#]' 2
        $out | Should Match "^$esc\[38;2;255;195;0m$([char]0x2588)"
        $out.EndsWith("$esc[0m") | Should Be $true
    }
    It 'draws shadow characters darker than solid blocks' {
        $out = Format-BannerLine '##' 1
        $shadow = Format-BannerLine ']]' 1
        $out | Should Match '38;2;255;195;0m'
        $shadow | Should Match '38;2;115;88;0m'
    }
    It 'leaves spaces uncoloured' {
        Format-BannerLine ' ' 1 | Should Be " $esc[0m"
    }
}
