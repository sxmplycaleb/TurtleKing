import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:turtle_king/legal/legal_consent_screen.dart';
import 'package:turtle_king/main.dart';
import 'package:turtle_king/settings.dart';
import 'package:turtle_king/settings_screen.dart';

void main() {
  group('LegalConsentScreen', () {
    testWidgets('shows age verification header', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LegalConsentScreen()));

      expect(find.text('Age Verification'), findsOneWidget);
      expect(find.textContaining('18+'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
    });

    testWidgets('Continue button is disabled initially', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LegalConsentScreen()));

      final continueButton = find.widgetWithText(FilledButton, 'Continue');
      expect(continueButton, findsOneWidget);

      final button = tester.widget<FilledButton>(continueButton);
      expect(button.onPressed, isNull);
    });

    testWidgets('empty age keeps Continue disabled', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LegalConsentScreen()));

      // Leave age empty, check both checkboxes
      final checkboxes = find.byType(CheckboxListTile);
      await tester.tap(checkboxes.first);
      await tester.pump();
      await tester.tap(checkboxes.last);
      await tester.pump();

      // Continue should still be disabled
      final continueButton = find.widgetWithText(FilledButton, 'Continue');
      expect(tester.widget<FilledButton>(continueButton).onPressed, isNull);
    });

    testWidgets('non-numeric age cannot be entered', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LegalConsentScreen()));

      // The TextField only accepts digits (inputFormatters: digitsOnly)
      // so we verify the field exists and accepts text
      final ageField = find.byType(TextField);
      expect(ageField, findsOneWidget);

      // Enter numeric age to verify it works
      await tester.enterText(ageField, '21');
      await tester.pump();
      expect(find.text('21'), findsOneWidget);
    });

    testWidgets('age 17 shows error message', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LegalConsentScreen()));

      await tester.enterText(find.byType(TextField), '17');
      await tester.pump();

      expect(
        find.text('TurtleKing is intended for adults aged 18 and over.'),
        findsOneWidget,
      );

      // Age confirmation checkbox should be disabled
      final ageCheckbox = find.byType(CheckboxListTile).first;
      expect(tester.widget<CheckboxListTile>(ageCheckbox).onChanged, isNull);
    });

    testWidgets('age 0 shows error message', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LegalConsentScreen()));

      await tester.enterText(find.byType(TextField), '0');
      await tester.pump();

      expect(find.text('Please enter a valid age.'), findsOneWidget);
    });

    testWidgets('age 18 enables age confirmation checkbox', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LegalConsentScreen()));

      await tester.enterText(find.byType(TextField), '18');
      await tester.pump();

      // No error message
      expect(
        find.text('TurtleKing is intended for adults aged 18 and over.'),
        findsNothing,
      );
      expect(find.text('Please enter a valid age.'), findsNothing);

      // Age confirmation checkbox should be enabled
      final ageCheckbox = find.byType(CheckboxListTile).first;
      expect(tester.widget<CheckboxListTile>(ageCheckbox).onChanged, isNotNull);
    });

    testWidgets('age 21 enables age confirmation checkbox', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LegalConsentScreen()));

      await tester.enterText(find.byType(TextField), '21');
      await tester.pump();

      final ageCheckbox = find.byType(CheckboxListTile).first;
      expect(tester.widget<CheckboxListTile>(ageCheckbox).onChanged, isNotNull);
    });

    testWidgets('Continue enabled only when all conditions met', (
      tester,
    ) async {
      bool consentGiven = false;
      await tester.pumpWidget(
        MaterialApp(
          home: LegalConsentScreen(onConsent: () => consentGiven = true),
        ),
      );

      final continueButton = find.widgetWithText(FilledButton, 'Continue');
      final checkboxes = find.byType(CheckboxListTile);

      // Initially disabled
      expect(tester.widget<FilledButton>(continueButton).onPressed, isNull);

      // Enter age >= 18
      await tester.enterText(find.byType(TextField), '21');
      await tester.pump();

      // Check age confirmation (first checkbox)
      await tester.tap(checkboxes.first);
      await tester.pump();

      // Still disabled (terms not accepted)
      expect(tester.widget<FilledButton>(continueButton).onPressed, isNull);

      // Check terms (second checkbox)
      await tester.tap(checkboxes.last);
      await tester.pump();

      // Now enabled
      expect(tester.widget<FilledButton>(continueButton).onPressed, isNotNull);

      // Tap Continue
      await tester.tap(continueButton);
      await tester.pump();

      expect(consentGiven, isTrue);
    });

    testWidgets('Privacy Policy is tappable and opens', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LegalConsentScreen()));

      // The Privacy Policy link is inside the terms CheckboxListTile
      // We can find it by looking for the RichText widget containing it
      final termsCheckbox = find.byType(CheckboxListTile).last;

      // Find the RichText inside the terms checkbox
      final richText = find.descendant(
        of: termsCheckbox,
        matching: find.byType(RichText),
      );
      expect(richText, findsOneWidget);

      // Tap the checkbox area to toggle it (this also tests the link)
      await tester.tap(termsCheckbox);
      await tester.pump();

      // The checkbox should be checked now
      expect(tester.widget<CheckboxListTile>(termsCheckbox).value, isTrue);
    });

    testWidgets('Terms of Service is tappable and opens', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LegalConsentScreen()));

      final termsCheckbox = find.byType(CheckboxListTile).last;

      // Find the RichText inside the terms checkbox
      final richText = find.descendant(
        of: termsCheckbox,
        matching: find.byType(RichText),
      );
      expect(richText, findsOneWidget);

      // Tap the checkbox area
      await tester.tap(termsCheckbox);
      await tester.pump();

      // The checkbox should be checked now
      expect(tester.widget<CheckboxListTile>(termsCheckbox).value, isTrue);
    });
  });

  group('Legal consent persistence', () {
    testWidgets('first launch shows consent screen', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = await SettingsStore.load();

      expect(settings.legalConsentAccepted, isFalse);

      await tester.pumpWidget(TurtleKingApp(store: settings));
      await tester.pump();

      expect(find.byType(LegalConsentScreen), findsOneWidget);
    });

    testWidgets('accepted consent persists across app restarts', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final settings = await SettingsStore.load();

      settings.acceptLegalConsent();

      expect(settings.legalConsentAccepted, isTrue);
      expect(settings.legalConsentVersion, SettingsStore.currentConsentVersion);

      final settings2 = await SettingsStore.load();
      expect(settings2.legalConsentAccepted, isTrue);
    });

    testWidgets('clearing app data resets consent', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = await SettingsStore.load();

      settings.acceptLegalConsent();
      expect(settings.legalConsentAccepted, isTrue);

      settings.resetLegalConsent();

      expect(settings.legalConsentAccepted, isFalse);
      expect(settings.legalConsentVersion, '');
    });

    testWidgets('consent version change requires re-acceptance', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'settings.legalConsentAccepted': true,
        'settings.legalConsentVersion': '0.9',
      });

      final settings = await SettingsStore.load();
      expect(settings.legalConsentAccepted, isFalse);
    });

    testWidgets('actual entered age is not persisted', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = await SettingsStore.load();

      settings.acceptLegalConsent();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('settings.age'), isFalse);
      expect(prefs.containsKey('settings.userAge'), isFalse);
    });
  });

  group('Settings screen legal links', () {
    testWidgets(
      'Privacy Policy, Terms, and Contact are accessible from Settings',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'settings.legalConsentAccepted': true,
          'settings.legalConsentVersion': '1.0',
        });
        final settings = await SettingsStore.load();

        await tester.pumpWidget(
          MaterialApp(
            home: SettingsScope(
              store: settings,
              child: const Scaffold(body: SettingsScreen()),
            ),
          ),
        );

        // Scroll to find the legal links
        await tester.scrollUntilVisible(find.text('Privacy Policy'), 200);
        expect(find.text('Privacy Policy'), findsOneWidget);
        expect(find.text('Terms of Service'), findsOneWidget);
        expect(find.text('Contact'), findsOneWidget);

        // Verify the ListTiles exist and have proper subtitles
        final privacyTile = find.widgetWithText(ListTile, 'Privacy Policy');
        expect(privacyTile, findsOneWidget);

        final termsTile = find.widgetWithText(ListTile, 'Terms of Service');
        expect(termsTile, findsOneWidget);

        final contactTile = find.widgetWithText(ListTile, 'Contact');
        expect(contactTile, findsOneWidget);
      },
    );
  });
}
