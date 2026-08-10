$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$src = Join-Path (Split-Path -Parent $dir) 'test/m14_preview'

function Hex([System.Drawing.Color]$c) {
  return ('#{0:X2}{1:X2}{2:X2}' -f $c.R, $c.G, $c.B)
}

function Sample($file, $fx, $fy) {
  $img = [System.Drawing.Bitmap]::FromFile((Join-Path $src $file))
  $x = [int]($img.Width * $fx)
  $y = [int]($img.Height * $fy)
  $c = $img.GetPixel($x, $y)
  $img.Dispose()
  return (Hex $c)
}

# Corner (felt edge) samples for each game theme.
$gameFiles = @(
  @('06_game_dark_gold.png',    'dark gold corner',    0.02, 0.02),
  @('07_game_dark_emerald.png', 'dark emerald corner', 0.02, 0.02),
  @('08_game_dark_ocean.png',   'dark ocean corner',   0.02, 0.02),
  @('09_game_dark_purple.png',  'dark purple corner',  0.02, 0.02),
  @('10_game_dark_crimson.png', 'dark crimson corner', 0.02, 0.02),
  @('11_game_light_gold.png',   'light gold corner',   0.02, 0.02)
)
foreach ($g in $gameFiles) {
  Write-Host ("{0,-24} {1}" -f $g[1], (Sample $g[0] $g[2] $g[3]))
}

# Surface samples for settings/home light vs dark.
Write-Host ("{0,-24} {1}" -f 'settings light surface', (Sample '01_settings_light.png' 0.5 0.06))
Write-Host ("{0,-24} {1}" -f 'settings dark surface',  (Sample '02_settings_dark.png' 0.5 0.06))
Write-Host ("{0,-24} {1}" -f 'home light surface',     (Sample '03_home_light.png' 0.5 0.04))
Write-Host ("{0,-24} {1}" -f 'home dark surface',      (Sample '04_home_dark.png' 0.5 0.04))

# Cards row: scan for presence of a white (classic) card and dark (noir) card.
$img = [System.Drawing.Bitmap]::FromFile((Join-Path $src '05_cards.png'))
$white = 0; $dark = 0
for ($y = 0; $y -lt $img.Height; $y += 3) {
  for ($x = 0; $x -lt $img.Width; $x += 3) {
    $c = $img.GetPixel($x, $y)
    if ($c.R -gt 240 -and $c.G -gt 240 -and $c.B -gt 240) { $white++ }
    if ($c.R -lt 80 -and $c.G -lt 80 -and $c.B -lt 90 -and ($c.R + $c.G + $c.B) -lt 150) { $dark++ }
  }
}
$img.Dispose()
Write-Host ("cards preview: white-card pixels={0}, dark-card pixels={1}" -f $white, $dark)
