import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:turtle_king/app_version.dart';
import 'package:turtle_king/home_screen.dart';
import 'package:turtle_king/settings.dart';
import 'package:turtle_king/settings_screen.dart';
import 'package:turtle_king/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('versionLabel', () {
    test('formats a semantic version as vX.Y.Z', () {
      expect(versionLabel('1.2.0'), 'v1.2.0');
      expect(versionLabel('2.0.1'), 'v2.0.1');
    });

    test('trims surrounding whitespace', () {
      expect(versionLabel(' 1.2.0 '), 'v1.2.0');
    });

    test('returns empty for a blank version', () {
      expect(versionLabel(''), '');
      expect(versionLabel('   '), '');
    });
  });

  group('AppVersionText', () {
    testWidgets('renders the version from platform package metadata', (
      tester,
    ) async {
      PackageInfo.setMockInitialValues(
        appName: 'Turtle King',
        packageName: 'com.turtleking.turtle_king',
        version: '1.2.0',
        buildNumber: '1',
        buildSignature: '',
      );
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: const AppVersionText())),
      );
      await tester.pump();

      // The build number is deliberately not displayed.
      expect(find.text('Version v1.2.0'), findsOneWidget);
      expect(find.textContaining('+1'), findsNothing);
    });

    testWidgets('renders the version from an injected loader', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppVersionText(loadVersion: () async => '3.4.5'),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Version v3.4.5'), findsOneWidget);
    });

    testWidgets('renders nothing when no version is available', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AppVersionText(loadVersion: () async => '')),
        ),
      );
      await tester.pump();

      expect(find.textContaining('Version'), findsNothing);
    });
  });

  group('Settings About section', () {
    testWidgets('shows the About section with the current app version', (
      tester,
    ) async {
      PackageInfo.setMockInitialValues(
        appName: 'Turtle King',
        packageName: 'com.turtleking.turtle_king',
        version: '1.2.0',
        buildNumber: '1',
        buildSignature: '',
      );
      await tester.pumpWidget(
        SettingsScope(
          store: SettingsStore.inMemory(),
          child: MaterialApp(theme: buildTheme(), home: const SettingsScreen()),
        ),
      );
      await tester.pump();

      // The About section sits at the bottom of the scrollable settings.
      await tester.scrollUntilVisible(find.text('About'), 200);
      await tester.pumpAndSettle();

      expect(find.text('About'), findsOneWidget);
      expect(find.text('Version v1.2.0'), findsOneWidget);
    });
  });

  group('Home screen version caption', () {
    testWidgets('shows the current app version under the tagline', (
      tester,
    ) async {
      PackageInfo.setMockInitialValues(
        appName: 'Turtle King',
        packageName: 'com.turtleking.turtle_king',
        version: '1.2.0',
        buildNumber: '1',
        buildSignature: '',
      );
      await tester.pumpWidget(
        MaterialApp(theme: buildTheme(), home: const HomeScreen()),
      );
      await tester.pump();

      expect(find.text('Version v1.2.0'), findsOneWidget);
      // Still reads from package metadata — no hardcoded constant.
      expect(find.textContaining('1.2.0'), findsWidgets);
    });
  });
}
