$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$destDir = $PSScriptRoot
$scratch = $env:TEMP
New-Item -ItemType Directory -Force $destDir | Out-Null

$bg = [System.Drawing.Color]::FromArgb(255, 51, 65, 85)    # slate-700
$fg = [System.Drawing.Color]::White

function New-DigitBitmap([int]$size, [string]$text) {
    $s = $size / 256.0
    $bmp = New-Object System.Drawing.Bitmap $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $g.Clear([System.Drawing.Color]::Transparent)

    $m = 8 * $s; $w = 240 * $s; $r = 52 * $s; $d = 2 * $r
    $sq = New-Object System.Drawing.Drawing2D.GraphicsPath
    $sq.AddArc([single]$m, [single]$m, [single]$d, [single]$d, 180, 90)
    $sq.AddArc([single]($m + $w - $d), [single]$m, [single]$d, [single]$d, 270, 90)
    $sq.AddArc([single]($m + $w - $d), [single]($m + $w - $d), [single]$d, [single]$d, 0, 90)
    $sq.AddArc([single]$m, [single]($m + $w - $d), [single]$d, [single]$d, 90, 90)
    $sq.CloseFigure()
    $bBg = New-Object System.Drawing.SolidBrush $bg
    $g.FillPath($bBg, $sq)

    $em = if ($text.Length -ge 2) { 140 } else { 180 }
    $font = New-Object System.Drawing.Font 'Segoe UI', ([single]($em * $s)), ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment = [System.Drawing.StringAlignment]::Center
    $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
    $rect = New-Object System.Drawing.RectangleF 0, ([single](10 * $s)), $size, $size
    $bFg = New-Object System.Drawing.SolidBrush $fg
    $g.DrawString($text, $font, $bFg, $rect, $sf)

    $g.Dispose(); $bBg.Dispose(); $bFg.Dispose(); $font.Dispose()
    return $bmp
}

function New-ArrowBitmap([int]$size, [string]$dir) {
    $s = $size / 256.0
    $bmp = New-Object System.Drawing.Bitmap $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    $m = 8 * $s; $w = 240 * $s; $r = 52 * $s; $d = 2 * $r
    $sq = New-Object System.Drawing.Drawing2D.GraphicsPath
    $sq.AddArc([single]$m, [single]$m, [single]$d, [single]$d, 180, 90)
    $sq.AddArc([single]($m + $w - $d), [single]$m, [single]$d, [single]$d, 270, 90)
    $sq.AddArc([single]($m + $w - $d), [single]($m + $w - $d), [single]$d, [single]$d, 0, 90)
    $sq.AddArc([single]$m, [single]($m + $w - $d), [single]$d, [single]$d, 90, 90)
    $sq.CloseFigure()
    $bBg = New-Object System.Drawing.SolidBrush $bg
    $g.FillPath($bBg, $sq)
    $bFg = New-Object System.Drawing.SolidBrush $fg
    if ($dir -eq 'ho') { $px = @(100, 188, 100) } else { $px = @(156, 68, 156) }
    $py = @(68, 128, 188)
    $pts = @()
    for ($i = 0; $i -lt 3; $i++) {
        $pts += New-Object System.Drawing.PointF ([single]($px[$i] * $s)), ([single]($py[$i] * $s))
    }
    $g.FillPolygon($bFg, [System.Drawing.PointF[]]$pts)
    $g.Dispose(); $bBg.Dispose(); $bFg.Dispose()
    return $bmp
}

function Write-Ico([string]$path, [string]$text, [string]$typ = 'digit') {
    $sizes = 16, 20, 24, 32, 48, 64, 128, 256
    $pngs = New-Object System.Collections.ArrayList
    foreach ($sz in $sizes) {
        $bmp = if ($typ -eq 'arrow') { New-ArrowBitmap $sz $text } else { New-DigitBitmap $sz $text }
        $ms = New-Object System.IO.MemoryStream
        $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        [void]$pngs.Add($ms.ToArray())
        $ms.Dispose(); $bmp.Dispose()
    }
    $count = $sizes.Count
    $offset = 6 + 16 * $count
    $out = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter $out
    $bw.Write([UInt16]0); $bw.Write([UInt16]1); $bw.Write([UInt16]$count)
    for ($i = 0; $i -lt $count; $i++) {
        $sz = $sizes[$i]; $bytes = $pngs[$i]
        $dim = if ($sz -ge 256) { 0 } else { $sz }
        $bw.Write([Byte]$dim); $bw.Write([Byte]$dim)
        $bw.Write([Byte]0); $bw.Write([Byte]0)
        $bw.Write([UInt16]1); $bw.Write([UInt16]32)
        $bw.Write([UInt32]$bytes.Length); $bw.Write([UInt32]$offset)
        $offset += $bytes.Length
    }
    foreach ($bytes in $pngs) { $bw.Write([byte[]]$bytes) }
    $bw.Flush()
    [System.IO.File]::WriteAllBytes($path, $out.ToArray())
    $bw.Dispose(); $out.Dispose()
}

foreach ($n in 1..9) { Write-Ico "$destDir\d$n.ico" "$n" }
Write-Ico "$destDir\d_more.ico" '9+'
Write-Ico "$destDir\d_unknown.ico" '?'
Write-Ico "$destDir\pil_va.ico" 'va' 'arrow'
Write-Ico "$destDir\pil_ho.ico" 'ho' 'arrow'
Write-Ico "$destDir\app.ico" 'DP'

# previews for inspection
$p = New-DigitBitmap 256 '3'; $p.Save("$scratch\vd_icon_256.png", [System.Drawing.Imaging.ImageFormat]::Png); $p.Dispose()
$p16 = New-DigitBitmap 16 '3'
$big = New-Object System.Drawing.Bitmap 128, 128
$gg = [System.Drawing.Graphics]::FromImage($big)
$gg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
$gg.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
$gg.DrawImage($p16, 0, 0, 128, 128)
$gg.Dispose(); $big.Save("$scratch\vd_icon_16_zoom.png", [System.Drawing.Imaging.ImageFormat]::Png)
$big.Dispose(); $p16.Dispose()
"Wrote $((Get-ChildItem $destDir).Count) icons to $destDir"
