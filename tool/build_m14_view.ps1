$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$src = Join-Path (Split-Path -Parent $dir) 'test/m14_preview'
$labels = @(
  @('01_settings_light.png', 'Settings - light'),
  @('02_settings_dark.png', 'Settings - dark'),
  @('03_home_light.png', 'Home - light'),
  @('04_home_dark.png', 'Home - dark'),
  @('05_cards.png', 'Card designs (faces + backs)'),
  @('06_game_dark_gold.png', 'Game dark - Turtle King Gold'),
  @('07_game_dark_emerald.png', 'Game dark - Emerald'),
  @('08_game_dark_ocean.png', 'Game dark - Ocean Blue'),
  @('09_game_dark_purple.png', 'Game dark - Royal Purple'),
  @('10_game_dark_crimson.png', 'Game dark - Crimson'),
  @('11_game_light_gold.png', 'Game light - Turtle King Gold')
)
$cards = @()
foreach ($item in $labels) {
  $path = Join-Path $src $item[0]
  $img = [System.Drawing.Image]::FromFile($path)
  $w = 240
  $h = [int]($img.Height * ($w / $img.Width))
  $bmp = New-Object System.Drawing.Bitmap($w, $h)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.InterpolationMode = 'HighQualityBicubic'
  $g.DrawImage($img, 0, 0, $w, $h)
  $ms = New-Object System.IO.MemoryStream
  $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Jpeg)
  $b64 = [System.Convert]::ToBase64String($ms.ToArray())
  $g.Dispose(); $bmp.Dispose(); $img.Dispose(); $ms.Dispose()
  $cards += "<div><h2>$($item[1])</h2><img src=""data:image/jpeg;base64,$b64""></div>"
}
$html = @"
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>Turtle King M14 preview</title>
<style>
  body { background: #0b2118; color: #eee; font-family: sans-serif; margin: 0; padding: 24px; }
  h1 { color: #fff; }
  h2 { color: #D4AF37; margin: 8px 0; font-size: 15px; }
  .row { display: flex; flex-wrap: wrap; gap: 24px; align-items: flex-start; }
  img { border: 1px solid #444; border-radius: 10px; }
</style></head>
<body><h1>Turtle King &mdash; Milestone 14 preview</h1>
<div class="row">$($cards -join '')</div>
</body></html>
"@
[System.IO.File]::WriteAllText((Join-Path $dir 'm14_view.html'), $html)
Write-Host "built m14_view.html"
