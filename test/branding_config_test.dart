// Verifies the Turtle King branding is actually wired into the project:
// asset files exist, pubspec declares them, and the Android/iOS native
// configuration references the Turtle King artwork and icon. Also checks
// that generated artwork has safe-area padding so nothing is clipped.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

/// Decodes a PNG and returns the bounding box of "content" pixels
/// (top/left/right/bottom margins in pixels). [isContent] decides whether a
/// pixel counts as artwork.
Future<({int left, int top, int right, int bottom})> contentMargins(
  String path, {
  required bool Function(int r, int g, int b, int a) isContent,
}) async {
  final bytes = File(path).readAsBytesSync();
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final data = await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  );
  final width = image.width;
  final height = image.height;
  var minX = width;
  var maxX = -1;
  var minY = height;
  var maxY = -1;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      final r = data!.getUint8(i);
      final g = data.getUint8(i + 1);
      final b = data.getUint8(i + 2);
      final a = data.getUint8(i + 3);
      if (isContent(r, g, b, a)) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  image.dispose();
  codec.dispose();
  return (
    left: minX,
    top: minY,
    right: width - 1 - maxX,
    bottom: height - 1 - maxY,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('branding assets', () {
    for (final asset in [
      'assets/branding/turtle_king_splash.png',
      'assets/branding/turtle_king_emblem.png',
      'assets/branding/turtle_king_icon.png',
    ]) {
      test('$asset exists', () {
        expect(File(asset).existsSync(), isTrue, reason: '$asset missing');
      });
    }

    test('pubspec.yaml declares the branding assets folder', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('assets/branding/'));
    });
  });

  group('Android branding configuration', () {
    test('launch background uses the navy color and Turtle King artwork', () {
      for (final file in [
        'android/app/src/main/res/drawable/launch_background.xml',
        'android/app/src/main/res/drawable-v21/launch_background.xml',
      ]) {
        final xml = File(file).readAsStringSync();
        expect(xml, contains('@color/launch_background'));
        expect(xml, contains('@drawable/turtle_king_splash'));
      }
    });

    test('splash artwork exists in drawable-nodpi', () {
      expect(
        File(
          'android/app/src/main/res/drawable-nodpi/turtle_king_splash.png',
        ).existsSync(),
        isTrue,
      );
    });

    test('brand colors are defined in values/colors.xml', () {
      final xml = File(
        'android/app/src/main/res/values/colors.xml',
      ).readAsStringSync();
      expect(xml, contains('launch_background'));
      expect(xml, contains('#0B263C'));
      expect(xml, contains('ic_launcher_background'));
    });

    test('Android 12+ splash is configured', () {
      final xml = File(
        'android/app/src/main/res/values-v31/styles.xml',
      ).readAsStringSync();
      expect(xml, contains('windowSplashScreenBackground'));
      expect(xml, contains('windowSplashScreenAnimatedIcon'));
    });

    test('adaptive launcher icon uses the Turtle King foreground', () {
      final xml = File(
        'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
      ).readAsStringSync();
      expect(xml, contains('ic_launcher_background'));
      expect(xml, contains('ic_launcher_foreground'));
    });

    test('launcher icons exist at all densities', () {
      for (final density in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
        expect(
          File(
            'android/app/src/main/res/mipmap-$density/ic_launcher.png',
          ).existsSync(),
          isTrue,
          reason: 'mipmap-$density icon missing',
        );
        expect(
          File(
            'android/app/src/main/res/mipmap-$density/ic_launcher_foreground.png',
          ).existsSync(),
          isTrue,
          reason: 'mipmap-$density foreground missing',
        );
      }
    });

    test('manifest points at the Turtle King launcher icon', () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      expect(manifest, contains('@mipmap/ic_launcher'));
    });
  });

  group('iOS branding configuration', () {
    test('every AppIcon slot has a PNG', () {
      const iconDir = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
      final contents = File('$iconDir/Contents.json').readAsStringSync();
      // Every image entry in Contents.json has a filename that exists.
      final names = RegExp(
        r'"filename"\s*:\s*"([^"]+)"',
      ).allMatches(contents).map((m) => m.group(1)!).toList();
      expect(names, isNotEmpty);
      for (final name in names) {
        expect(
          File('$iconDir/$name').existsSync(),
          isTrue,
          reason: 'AppIcon PNG $name missing',
        );
      }
    });

    test('iOS launch screen references the Turtle King artwork', () {
      final storyboard = File(
        'ios/Runner/Base.lproj/LaunchScreen.storyboard',
      ).readAsStringSync();
      expect(storyboard, contains('TurtleKingSplash'));
      expect(storyboard, contains('scaleAspectFit'));
    });

    test('iOS splash image set exists', () {
      const dir = 'ios/Runner/Assets.xcassets/TurtleKingSplash.imageset';
      expect(File('$dir/Contents.json').existsSync(), isTrue);
      expect(File('$dir/turtle_king_splash.png').existsSync(), isTrue);
    });
  });

  group('artwork safe-area (no clipping)', () {
    test('splash keeps the full uncropped artwork dimensions', () async {
      final bytes = File(
        'assets/branding/turtle_king_splash.png',
      ).readAsBytesSync();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 1024);
      expect(frame.image.height, 1536);
      frame.image.dispose();
      codec.dispose();
    });

    test('emblem artwork has breathing room on every side', () async {
      // Content = any non-transparent pixel (the canvas background is
      // transparent). The fanned cards and ring must not touch the edges.
      final margins = await contentMargins(
        'assets/branding/turtle_king_emblem.png',
        isContent: (r, g, b, a) => a > 10,
      );
      for (final side in [
        margins.left,
        margins.top,
        margins.right,
        margins.bottom,
      ]) {
        expect(
          side,
          greaterThanOrEqualTo(60),
          reason: 'emblem artwork must not be flush against the canvas edge',
        );
      }
    });

    test(
      'launcher icon artwork is comfortably inside the navy field',
      () async {
        // Content = pixels clearly different from the flat navy background
        // (#0B263C), i.e. the actual artwork rather than the padding.
        final margins = await contentMargins(
          'assets/branding/turtle_king_icon.png',
          isContent: (r, g, b, a) {
            final distance =
                (r - 0x0B).abs() + (g - 0x26).abs() + (b - 0x3C).abs();
            return a > 200 && distance > 60;
          },
        );
        for (final side in [
          margins.left,
          margins.top,
          margins.right,
          margins.bottom,
        ]) {
          expect(
            side,
            greaterThanOrEqualTo(100),
            reason: 'icon artwork must sit inside the navy padding',
          );
        }
      },
    );

    test('adaptive icon foreground fits the Android safe zone', () async {
      // 108dp foreground canvas: artwork must stay within the central 66dp
      // safe zone (with margin) so launcher masking cannot clip it.
      final margins = await contentMargins(
        'android/app/src/main/res/mipmap-mdpi/ic_launcher_foreground.png',
        isContent: (r, g, b, a) => a > 10,
      );
      final contentWidth = 108 - margins.left - margins.right;
      expect(contentWidth, lessThanOrEqualTo(66));
      expect(margins.left, greaterThanOrEqualTo(18));
      expect(margins.right, greaterThanOrEqualTo(18));
      expect(margins.top, greaterThanOrEqualTo(18));
      expect(margins.bottom, greaterThanOrEqualTo(18));
    });
  });
}
