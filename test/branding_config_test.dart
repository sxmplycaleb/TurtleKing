import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Verifies the Turtle King branding is actually wired into the project:
/// asset files exist, pubspec declares them, and the Android/iOS native
/// configuration references the Turtle King artwork and icon.
void main() {
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
}
