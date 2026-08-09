# Generates all Turtle King branding derivatives from the source artwork.
#
# Source: assets/branding/turtle_king_splash.png (1024x1536 transparent-PNG:
# square emblem circle on top + TURTLE/KING shield banner below).
# Emblem square region: x 0..1023, y 82..1105 (1024x1024, no banner).

param(
  [string]$Source = 'assets/branding/turtle_king_splash.png'
)

Add-Type -AssemblyName System.Drawing

function Resize-To($img, $size) {
  $out = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($out)
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
  $g.DrawImage($img, 0, 0, $size, $size)
  $g.Dispose()
  return $out
}

function Save-Png($img, $path) {
  $dir = Split-Path $path -Parent
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $img.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
}

$src = New-Object System.Drawing.Bitmap($Source)
Write-Host ("source: {0}x{1}" -f $src.Width, $src.Height)

# Navy field color sampled from the emblem interior (median of dark-blue
# pixels): #0B263C. Used so the icon background blends seamlessly with the
# emblem's own navy circle.
$navy = [System.Drawing.Color]::FromArgb(255, 0x0B, 0x26, 0x3C)
Write-Host ("navy background: #{0:X2}{1:X2}{2:X2}" -f $navy.R, $navy.G, $navy.B)

# ---- 1. Emblem: crop the complete emblem circle region (no banner) and
#         scale it to 84% inside a 1024x1024 transparent canvas.
# Ring bounds (measured): x 11..1010, y 100..890. Cards poke past the ring to
# the artwork edges (x 0..1023), so the crop takes the full width. The
# TURTLE/KING shield starts at y ~895+, so the crop stops at y 890.
#
# SAFE-AREA: the content is scaled to 84% of the canvas, leaving ~8% margin
# left/right and ~17% top/bottom so the ring and fanned cards are never flush
# against the canvas edge. Downstream scales assume this padding:
#   - legacy/iOS icon base draws the emblem at 88%  -> content at ~74%
#   - Android adaptive foreground draws it at 70%   -> content at ~59% of the
#     108dp canvas, inside the 66dp safe zone.
$emblemContentScale = 0.84
$emblemRaw = New-Object System.Drawing.Bitmap(1024, 809, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($emblemRaw)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.DrawImage($src, (New-Object System.Drawing.Rectangle(0, 0, 1024, 809)),
             (New-Object System.Drawing.Rectangle(0, 82, 1024, 809)), [System.Drawing.GraphicsUnit]::Pixel)
$g.Dispose()
$emblem = New-Object System.Drawing.Bitmap(1024, 1024, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($emblem)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
$cw = [int](1024 * $emblemContentScale)
$ch = [int](809 * $emblemContentScale)
$cx = [int]((1024 - $cw) / 2)
$cy = [int]((1024 - $ch) / 2)
$g.DrawImage($emblemRaw, (New-Object System.Drawing.Rectangle($cx, $cy, $cw, $ch)))
$g.Dispose()
$emblemRaw.Dispose()
Save-Png $emblem 'assets/branding/turtle_king_emblem.png'

# ---- 2. Icon base: emblem at 88% on a navy square (opaque) ----
$icon = New-Object System.Drawing.Bitmap(1024, 1024, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($icon)
$g.Clear($navy)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
$size = [int](1024 * 0.88)
$pad = [int]((1024 - $size) / 2)
$g.DrawImage($emblem, (New-Object System.Drawing.Rectangle($pad, $pad, $size, $size)))
$g.Dispose()
Save-Png $icon 'assets/branding/turtle_king_icon.png'

# ---- 3. Android legacy launcher icons (opaque navy, no alpha) ----
$legacy = New-Object System.Drawing.Bitmap(1024, 1024, [System.Drawing.Imaging.PixelFormat]::Format32bppRgb)
$g = [System.Drawing.Graphics]::FromImage($legacy)
$g.Clear($navy)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.DrawImage($emblem, (New-Object System.Drawing.Rectangle($pad, $pad, $size, $size)))
$g.Dispose()

$mipDensities = @{
  'mipmap-mdpi' = 48; 'mipmap-hdpi' = 72; 'mipmap-xhdpi' = 96
  'mipmap-xxhdpi' = 144; 'mipmap-xxxhdpi' = 192
}
foreach ($dir in $mipDensities.Keys) {
  $sz = $mipDensities[$dir]
  $res = Resize-To $legacy $sz
  Save-Png $res "android/app/src/main/res/$dir/ic_launcher.png"
  $res.Dispose()
}

# ---- 4. Android adaptive icon foreground (transparent canvas, emblem at
#         70%). With the emblem's built-in 84% padding, the artwork lands at
#         70% * 84% = ~59% of the 108dp canvas - inside the 66dp safe zone -
#         while the emblem itself reads as a comfortable 70% of the canvas.
$fgCanvas = @{ 'mipmap-mdpi' = 108; 'mipmap-hdpi' = 162; 'mipmap-xhdpi' = 216
               'mipmap-xxhdpi' = 324; 'mipmap-xxxhdpi' = 432 }
$fgScale = 0.70
foreach ($dir in $fgCanvas.Keys) {
  $canvas = $fgCanvas[$dir]
  $fg = New-Object System.Drawing.Bitmap($canvas, $canvas, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($fg)
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
  $sz = [int]($canvas * $fgScale)
  $p = [int]((($canvas - $sz) / 2))
  $g.DrawImage($emblem, (New-Object System.Drawing.Rectangle($p, $p, $sz, $sz)))
  $g.Dispose()
  Save-Png $fg "android/app/src/main/res/$dir/ic_launcher_foreground.png"
  $fg.Dispose()
}

# ---- 5. Android splash drawable (full artwork, natural size) ----
$splashDir = 'android/app/src/main/res/drawable-nodpi'
New-Item -ItemType Directory -Force -Path $splashDir | Out-Null
Copy-Item $Source "$splashDir/turtle_king_splash.png" -Force

# ---- 6. iOS AppIcon PNGs (opaque navy, no alpha) ----
$iosSizes = @{
  'Icon-App-20x20@1x.png' = 20; 'Icon-App-20x20@2x.png' = 40; 'Icon-App-20x20@3x.png' = 60
  'Icon-App-29x29@1x.png' = 29; 'Icon-App-29x29@2x.png' = 58; 'Icon-App-29x29@3x.png' = 87
  'Icon-App-40x40@1x.png' = 40; 'Icon-App-40x40@2x.png' = 80; 'Icon-App-40x40@3x.png' = 120
  'Icon-App-60x60@2x.png' = 120; 'Icon-App-60x60@3x.png' = 180
  'Icon-App-76x76@1x.png' = 76; 'Icon-App-76x76@2x.png' = 152
  'Icon-App-83.5x83.5@2x.png' = 167
  'Icon-App-1024x1024@1x.png' = 1024
}
$iosDir = 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
foreach ($f in $iosSizes.Keys) {
  $res = Resize-To $legacy $iosSizes[$f]
  Save-Png $res "$iosDir/$f"
  $res.Dispose()
}

# ---- 7. iOS splash imageset (full artwork) ----
$iosSplashDir = 'ios/Runner/Assets.xcassets/TurtleKingSplash.imageset'
New-Item -ItemType Directory -Force -Path $iosSplashDir | Out-Null
Copy-Item $Source "$iosSplashDir/turtle_king_splash.png" -Force

$legacy.Dispose()
$icon.Dispose()
$emblem.Dispose()
$src.Dispose()
Write-Host 'Branding assets generated.'
