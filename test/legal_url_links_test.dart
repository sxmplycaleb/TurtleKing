import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

import 'package:turtle_king/legal/legal_urls.dart';
import 'package:turtle_king/legal/onboarding_store.dart';
import 'package:turtle_king/legal/screens/terms_privacy_screen.dart';
import 'package:turtle_king/main.dart';
import 'package:turtle_king/settings.dart';

/// Tracks the last URL passed to launchUrl.
String? lastLaunchedUrl;
bool launchResult = true;

/// A function-type variable so tests can override launch behavior.
Future<bool> Function(Uri uri, {launcher.LaunchMode mode})? mockLauncher;

/// Our custom launch function that records calls.
Future<bool> _testLaunch(
  Uri uri, {
  launcher.LaunchMode mode = launcher.LaunchMode.platformDefault,
}) async {
  if (mockLauncher != null) {
    return mockLauncher!(uri, mode: mode);
  }
  lastLaunchedUrl = uri.toString();
  return launchResult;
}

/// Pumps the full app and advances past the splash screen to Terms screen.
Future<void> pumpTermsScreen(
  WidgetTester tester, {
  launcher.LaunchMode mode = launcher.LaunchMode.platformDefault,
}) async {
  SharedPreferences.setMockInitialValues({
    'settings.legalConsentAccepted': true,
    'settings.legalConsentVersion': '1.0',
  });
  final settings = await SettingsStore.load();
  final onboarding = OnboardingStore.inMemory();
  onboarding.setDobSelected(true);
  onboarding.advanceStep(); // → adultConfirmation
  onboarding.advanceStep(); // → drinkingDisclosure
  onboarding.advanceStep(); // → termsPrivacy
  onboarding.setAgeConfirmed(true);
  onboarding.setDrinkingAcknowledged(true);

  await tester.pumpWidget(
    TurtleKingApp(store: settings, onboarding: onboarding),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('LegalUrls', () {
    test('privacy URL is a valid HTTPS URL', () {
      final uri = Uri.parse(LegalUrls.privacyPolicy);
      expect(uri.isAbsolute, isTrue);
      expect(uri.scheme, 'https');
      expect(uri.host, isNotEmpty);
      expect(uri.path, contains('privacy.html'));
    });

    test('terms URL is a valid HTTPS URL', () {
      final uri = Uri.parse(LegalUrls.termsOfService);
      expect(uri.isAbsolute, isTrue);
      expect(uri.scheme, 'https');
      expect(uri.host, isNotEmpty);
      expect(uri.path, contains('terms.html'));
    });

    test('contact URL is a valid HTTPS URL', () {
      final uri = Uri.parse(LegalUrls.contact);
      expect(uri.isAbsolute, isTrue);
      expect(uri.scheme, 'https');
      expect(uri.host, isNotEmpty);
      expect(uri.path, contains('contact.html'));
    });

    test('all URLs are configured (not placeholders)', () {
      expect(LegalUrls.isConfigured, isTrue);
    });
  });

  group('UrlLauncherHelper', () {
    setUp(() {
      lastLaunchedUrl = null;
      launchResult = true;
      mockLauncher = null;
    });

    testWidgets('tapping Terms of Service invokes URL launcher', (
      tester,
    ) async {
      mockLauncher = _testLaunch;
      await pumpTermsScreen(tester);

      await tester.ensureVisible(find.text('Terms of Service'));
      await tester.tap(find.text('Terms of Service'));
      await tester.pump();

      expect(lastLaunchedUrl, LegalUrls.termsOfService);
    });

    testWidgets('tapping Privacy Policy invokes URL launcher', (tester) async {
      mockLauncher = _testLaunch;
      await pumpTermsScreen(tester);

      await tester.ensureVisible(find.text('Privacy Policy'));
      await tester.tap(find.text('Privacy Policy'));
      await tester.pump();

      expect(lastLaunchedUrl, LegalUrls.privacyPolicy);
    });

    testWidgets('opening Terms does not complete onboarding', (tester) async {
      mockLauncher = _testLaunch;
      await pumpTermsScreen(tester);

      // Tap Terms.
      await tester.ensureVisible(find.text('Terms of Service'));
      await tester.tap(find.text('Terms of Service'));
      await tester.pump();

      // We should still be on the Terms screen.
      expect(find.byType(TermsPrivacyScreen), findsOneWidget);
      // Button should still be disabled (checkbox not checked).
      final acceptButton = find.widgetWithText(
        FilledButton,
        'Accept & Continue',
      );
      expect(tester.widget<FilledButton>(acceptButton).onPressed, isNull);
    });

    testWidgets('opening Privacy does not complete onboarding', (tester) async {
      mockLauncher = _testLaunch;
      await pumpTermsScreen(tester);

      await tester.ensureVisible(find.text('Privacy Policy'));
      await tester.tap(find.text('Privacy Policy'));
      await tester.pump();

      expect(find.byType(TermsPrivacyScreen), findsOneWidget);
      final acceptButton = find.widgetWithText(
        FilledButton,
        'Accept & Continue',
      );
      expect(tester.widget<FilledButton>(acceptButton).onPressed, isNull);
    });

    testWidgets('failed URL launch shows correct error for Privacy', (
      tester,
    ) async {
      launchResult = false;
      mockLauncher = _testLaunch;
      await pumpTermsScreen(tester);

      await tester.ensureVisible(find.text('Privacy Policy'));
      await tester.tap(find.text('Privacy Policy'));
      await tester.pump();

      expect(
        find.text('Unable to open the Privacy Policy. Please try again.'),
        findsOneWidget,
      );
      // Should NOT mention internet connection.
      expect(find.textContaining('internet connection'), findsNothing);
    });

    testWidgets('failed URL launch shows correct error for Terms', (
      tester,
    ) async {
      launchResult = false;
      mockLauncher = _testLaunch;
      await pumpTermsScreen(tester);

      await tester.ensureVisible(find.text('Terms of Service'));
      await tester.tap(find.text('Terms of Service'));
      await tester.pump();

      expect(
        find.text('Unable to open the Terms of Service. Please try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('internet connection'), findsNothing);
    });

    testWidgets('checkbox state preserved after opening link', (tester) async {
      mockLauncher = _testLaunch;
      await pumpTermsScreen(tester);

      // Check the checkbox first.
      final checkbox = find.byType(CheckboxListTile);
      await tester.scrollUntilVisible(checkbox, 200);
      await tester.tap(checkbox);
      await tester.pump();

      // Verify it's checked.
      expect(tester.widget<CheckboxListTile>(checkbox).value, isTrue);

      // Now tap Terms.
      await tester.ensureVisible(find.text('Terms of Service'));
      await tester.tap(find.text('Terms of Service'));
      await tester.pump();

      // Checkbox should still be checked.
      expect(tester.widget<CheckboxListTile>(checkbox).value, isTrue);

      // Button should still be enabled.
      final acceptButton = find.widgetWithText(
        FilledButton,
        'Accept & Continue',
      );
      expect(tester.widget<FilledButton>(acceptButton).onPressed, isNotNull);
    });
  });
}
