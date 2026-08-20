import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:turtle_king/legal/age_calculator.dart';
import 'package:turtle_king/legal/onboarding_store.dart';
import 'package:turtle_king/legal/screens/adult_confirmation_screen.dart';
import 'package:turtle_king/legal/screens/dob_entry_screen.dart';
import 'package:turtle_king/legal/screens/drinking_disclosure_screen.dart';
import 'package:turtle_king/legal/screens/onboarding_screen.dart';
import 'package:turtle_king/legal/screens/terms_privacy_screen.dart';
import 'package:turtle_king/main.dart';
import 'package:turtle_king/settings.dart';

// ---------------------------------------------------------------------------
// Age calculation tests
// ---------------------------------------------------------------------------
void main() {
  group('AgeCalculator', () {
    test('exactly 18 years old today', () {
      final today = DateTime(2026, 8, 20);
      final dob = DateTime(2008, 8, 20);
      expect(AgeCalculator.calculateAge(dob, today: today), 18);
    });

    test('one day before turning 18', () {
      final today = DateTime(2026, 8, 19);
      final dob = DateTime(2008, 8, 20);
      expect(AgeCalculator.calculateAge(dob, today: today), 17);
    });

    test('birthday tomorrow (not yet 18)', () {
      final today = DateTime(2026, 8, 19);
      final dob = DateTime(2008, 8, 20);
      expect(AgeCalculator.calculateAge(dob, today: today), 17);
    });

    test('birthday yesterday (just turned 18)', () {
      final today = DateTime(2026, 8, 21);
      final dob = DateTime(2008, 8, 20);
      expect(AgeCalculator.calculateAge(dob, today: today), 18);
    });

    test('leap year birth date — Feb 29 born, non-leap year today', () {
      final today = DateTime(2025, 3, 1); // 2025 is not a leap year
      final dob = DateTime(2008, 2, 29);
      // Born Feb 29 2008. On March 1 2025, birthday has passed → 17
      expect(AgeCalculator.calculateAge(dob, today: today), 17);
    });

    test('leap year birth date — Feb 29 born, leap year today', () {
      final today = DateTime(2028, 3, 1); // 2028 is a leap year
      final dob = DateTime(2008, 2, 29);
      // Born Feb 29 2008. On March 1 2028, birthday has passed → 20
      expect(AgeCalculator.calculateAge(dob, today: today), 20);
    });

    test('future DOB returns null', () {
      final today = DateTime(2026, 8, 20);
      final dob = DateTime(2030, 1, 1);
      expect(AgeCalculator.calculateAge(dob, today: today), isNull);
    });

    test('null DOB returns null', () {
      expect(AgeCalculator.calculateAge(null), isNull);
    });

    test('different months — older month', () {
      final today = DateTime(2026, 12, 15);
      final dob = DateTime(2008, 3, 10);
      expect(AgeCalculator.calculateAge(dob, today: today), 18);
    });

    test('different months — younger month', () {
      final today = DateTime(2026, 3, 10);
      final dob = DateTime(2008, 12, 25);
      expect(AgeCalculator.calculateAge(dob, today: today), 17);
    });

    test('different years — age 25', () {
      final today = DateTime(2026, 8, 20);
      final dob = DateTime(2001, 8, 20);
      expect(AgeCalculator.calculateAge(dob, today: today), 25);
    });

    test('isEligible returns true for 18+', () {
      expect(AgeCalculator.isEligible(18), isTrue);
      expect(AgeCalculator.isEligible(21), isTrue);
    });

    test('isEligible returns false for <18', () {
      expect(AgeCalculator.isEligible(17), isFalse);
      expect(AgeCalculator.isEligible(0), isFalse);
    });

    test('isEligible returns false for null', () {
      expect(AgeCalculator.isEligible(null), isFalse);
    });

    test('isValidDob rejects future dates', () {
      expect(AgeCalculator.isValidDob(DateTime(2030, 1, 1)), isFalse);
    });

    test('isValidDob accepts past dates', () {
      expect(AgeCalculator.isValidDob(DateTime(2000, 1, 1)), isTrue);
    });

    // -----------------------------------------------------------------------
    // maxEligibleDate tests
    // -----------------------------------------------------------------------
    group('maxEligibleDate', () {
      test('today as maximum eligible DOB', () {
        final today = DateTime(2026, 8, 20);
        final max = AgeCalculator.maxEligibleDate(today: today);
        expect(max, DateTime(2008, 8, 20));
      });

      test('exactly 18 years old is at the boundary', () {
        final today = DateTime(2026, 8, 20);
        final max = AgeCalculator.maxEligibleDate(today: today);
        final age = AgeCalculator.calculateAge(max, today: today);
        expect(age, 18);
      });

      test('one day after the boundary is not selectable', () {
        final today = DateTime(2026, 8, 20);
        final max = AgeCalculator.maxEligibleDate(today: today);
        final dayAfter = max.add(const Duration(days: 1));
        // 21 Aug 2008 → age 17 on 20 Aug 2026
        final age = AgeCalculator.calculateAge(dayAfter, today: today);
        expect(age, 17);
      });

      test('maximum date changes when current date changes', () {
        final today1 = DateTime(2026, 8, 20);
        final today2 = DateTime(2026, 8, 21);
        expect(
          AgeCalculator.maxEligibleDate(today: today1),
          DateTime(2008, 8, 20),
        );
        expect(
          AgeCalculator.maxEligibleDate(today: today2),
          DateTime(2008, 8, 21),
        );
      });

      test('leap year — Feb 29 boundary', () {
        // Today is Feb 29 2028 (leap year). Max DOB = Feb 29 2010.
        final today = DateTime(2028, 2, 29);
        final max = AgeCalculator.maxEligibleDate(today: today, minimumAge: 18);
        expect(max, DateTime(2010, 2, 29));
      });

      test('leap year — today is Feb 28, max is Feb 28', () {
        final today = DateTime(2027, 2, 28); // 2027 is not a leap year
        final max = AgeCalculator.maxEligibleDate(today: today, minimumAge: 18);
        expect(max, DateTime(2009, 2, 28));
      });

      test('year boundary — Jan 1', () {
        final today = DateTime(2027, 1, 1);
        final max = AgeCalculator.maxEligibleDate(today: today, minimumAge: 18);
        expect(max, DateTime(2009, 1, 1));
      });

      test('year boundary — Dec 31', () {
        final today = DateTime(2026, 12, 31);
        final max = AgeCalculator.maxEligibleDate(today: today, minimumAge: 18);
        expect(max, DateTime(2008, 12, 31));
      });

      test('month boundary — Mar 1 (leap year edge)', () {
        // Today is Mar 1 2028. Max DOB = Mar 1 2010.
        final today = DateTime(2028, 3, 1);
        final max = AgeCalculator.maxEligibleDate(today: today, minimumAge: 18);
        expect(max, DateTime(2010, 3, 1));
      });

      test('configurable minimum age', () {
        final today = DateTime(2026, 8, 20);
        final max21 = AgeCalculator.maxEligibleDate(
          today: today,
          minimumAge: 21,
        );
        expect(max21, DateTime(2005, 8, 20));
      });
    });

    // -----------------------------------------------------------------------
    // defaultDob tests
    // -----------------------------------------------------------------------
    group('defaultDob', () {
      test('default is approximately 25 years ago', () {
        final today = DateTime(2026, 8, 20);
        final def = AgeCalculator.defaultDob(today: today);
        expect(def, DateTime(2001, 8, 20));
      });

      test('default is always within the eligible range', () {
        final today = DateTime(2026, 8, 20);
        final def = AgeCalculator.defaultDob(today: today);
        final max = AgeCalculator.maxEligibleDate(today: today);
        expect(def.isAfter(max), isFalse);
      });

      test('default clamps when defaultYearsAgo < minimumAge', () {
        final today = DateTime(2026, 8, 20);
        // If defaultYearsAgo is less than minimumAge, clamp to max.
        final def = AgeCalculator.defaultDob(
          today: today,
          minimumAge: 18,
          defaultYearsAgo: 10,
        );
        final max = AgeCalculator.maxEligibleDate(today: today, minimumAge: 18);
        expect(def, max);
      });

      test('default age is always eligible', () {
        final today = DateTime(2026, 8, 20);
        final def = AgeCalculator.defaultDob(today: today);
        final age = AgeCalculator.calculateAge(def, today: today);
        expect(age, greaterThanOrEqualTo(18));
      });
    });
  });

  // ---------------------------------------------------------------------------
  // OnboardingStore tests
  // ---------------------------------------------------------------------------
  group('OnboardingStore', () {
    test('inMemory starts incomplete', () {
      final store = OnboardingStore.inMemory();
      expect(store.isComplete, isFalse);
      expect(store.currentStep, OnboardingStep.dob);
    });

    test('completing all steps makes store complete', () {
      final store = OnboardingStore.inMemory();
      store.setDobSelected(true);
      store.setAgeConfirmed(true);
      store.setDrinkingAcknowledged(true);
      store.setTermsAccepted(true);
      store.setPrivacyAcknowledged(true);
      expect(store.isComplete, isTrue);
    });

    test('resetConfirmations clears all confirmations', () {
      final store = OnboardingStore.inMemory();
      store.setDobSelected(true);
      store.setAgeConfirmed(true);
      store.setDrinkingAcknowledged(true);
      store.setTermsAccepted(true);
      store.setPrivacyAcknowledged(true);
      expect(store.isComplete, isTrue);

      store.resetConfirmations();
      expect(store.ageConfirmed, isFalse);
      expect(store.drinkingAcknowledged, isFalse);
      expect(store.termsAccepted, isFalse);
      expect(store.privacyAcknowledged, isFalse);
      expect(store.isComplete, isFalse);
    });

    test('setUnderageBlocked resets confirmations', () {
      final store = OnboardingStore.inMemory();
      store.setAgeConfirmed(true);
      store.setDrinkingAcknowledged(true);
      store.setTermsAccepted(true);
      store.setPrivacyAcknowledged(true);

      store.setUnderageBlocked(true);
      expect(store.ageConfirmed, isFalse);
      expect(store.drinkingAcknowledged, isFalse);
      expect(store.termsAccepted, isFalse);
      expect(store.privacyAcknowledged, isFalse);
      expect(store.isComplete, isFalse);
    });

    test('advanceStep navigates through steps', () {
      final store = OnboardingStore.inMemory();
      expect(store.currentStep, OnboardingStep.dob);

      store.advanceStep();
      expect(store.currentStep, OnboardingStep.adultConfirmation);

      store.advanceStep();
      expect(store.currentStep, OnboardingStep.drinkingDisclosure);

      store.advanceStep();
      expect(store.currentStep, OnboardingStep.termsPrivacy);
    });

    test('goBack navigates backward', () {
      final store = OnboardingStore.inMemory();
      store.advanceStep(); // → adultConfirmation
      store.advanceStep(); // → drinkingDisclosure

      store.goBack();
      expect(store.currentStep, OnboardingStep.adultConfirmation);

      store.goBack();
      expect(store.currentStep, OnboardingStep.dob);
    });

    test('goToDob jumps to DOB step', () {
      final store = OnboardingStore.inMemory();
      store.advanceStep();
      store.advanceStep();
      store.goToDob();
      expect(store.currentStep, OnboardingStep.dob);
    });

    test('DOB is not persisted in the store', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await OnboardingStore.load();
      store.setDobSelected(true);
      // No DOB key should exist.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('onboarding.dob'), isFalse);
      expect(prefs.containsKey('onboarding.dobDate'), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Onboarding UI flow tests
  // ---------------------------------------------------------------------------
  group('OnboardingScreen', () {
    testWidgets('shows DOB entry screen initially', (tester) async {
      final store = OnboardingStore.inMemory();
      await tester.pumpWidget(
        MaterialApp(home: OnboardingScreen(store: store)),
      );

      expect(find.text('Before You Play'), findsOneWidget);
      expect(find.text('Date of Birth'), findsOneWidget);
      expect(find.byType(DobEntryScreen), findsOneWidget);
    });

    testWidgets('progress indicator shows current step', (tester) async {
      final store = OnboardingStore.inMemory();
      await tester.pumpWidget(
        MaterialApp(home: OnboardingScreen(store: store)),
      );

      expect(find.text('Age'), findsOneWidget);
      expect(find.text('Confirm'), findsOneWidget);
      expect(find.text('Drinking'), findsOneWidget);
      expect(find.text('Terms'), findsOneWidget);
    });

    testWidgets('DOB entry has a date picker button', (tester) async {
      final store = OnboardingStore.inMemory();
      await tester.pumpWidget(
        MaterialApp(home: OnboardingScreen(store: store)),
      );

      // The date picker button should show a formatted date.
      expect(find.byIcon(Icons.calendar_today), findsOneWidget);
    });

    testWidgets('DOB screen shows underage block when store signals block', (
      tester,
    ) async {
      final store = OnboardingStore.inMemory();
      store.setUnderageBlocked(true);
      await tester.pumpWidget(
        MaterialApp(home: OnboardingScreen(store: store)),
      );

      expect(find.text('Sorry, You Can\'t Play Yet'), findsOneWidget);
    });

    testWidgets(
      'DOB screen initially has no selected date and Continue is disabled',
      (tester) async {
        final store = OnboardingStore.inMemory();
        await tester.pumpWidget(
          MaterialApp(home: OnboardingScreen(store: store)),
        );

        // Placeholder text should be shown.
        expect(find.text('Select your date of birth'), findsOneWidget);

        // Continue button should be disabled (no DOB selected).
        final continueButton = find.widgetWithText(FilledButton, 'Continue');
        expect(continueButton, findsOneWidget);
        expect(tester.widget<FilledButton>(continueButton).onPressed, isNull);
      },
    );

    testWidgets('August 20, 2001 is NOT automatically selected', (
      tester,
    ) async {
      final store = OnboardingStore.inMemory();
      await tester.pumpWidget(
        MaterialApp(home: OnboardingScreen(store: store)),
      );

      // The old prefilled date should not appear.
      expect(find.textContaining('August 20, 2001'), findsNothing);
      // The placeholder should be shown instead.
      expect(find.text('Select your date of birth'), findsOneWidget);
    });

    testWidgets('store.dobSelected is false when no DOB picked', (
      tester,
    ) async {
      final store = OnboardingStore.inMemory();
      await tester.pumpWidget(
        MaterialApp(home: OnboardingScreen(store: store)),
      );

      // The store should not have dobSelected set.
      expect(store.dobSelected, isFalse);
    });

    testWidgets('adult confirmation requires checkbox', (tester) async {
      final store = OnboardingStore.inMemory();
      // Advance to adult confirmation step.
      store.setDobSelected(true);
      store.advanceStep();

      await tester.pumpWidget(
        MaterialApp(home: OnboardingScreen(store: store)),
      );

      expect(find.text('Age Confirmation'), findsOneWidget);
      expect(find.byType(AdultConfirmationScreen), findsOneWidget);

      // Continue should be disabled without checkbox.
      final continueButton = find.widgetWithText(FilledButton, 'Continue');
      expect(continueButton, findsOneWidget);
      expect(tester.widget<FilledButton>(continueButton).onPressed, isNull);

      // Check the checkbox.
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();

      // Continue should now be enabled.
      expect(tester.widget<FilledButton>(continueButton).onPressed, isNotNull);
    });

    testWidgets('drinking disclosure requires acknowledgement', (tester) async {
      final store = OnboardingStore.inMemory();
      store.setDobSelected(true);
      store.advanceStep(); // → adultConfirmation
      store.advanceStep(); // → drinkingDisclosure

      await tester.pumpWidget(
        MaterialApp(home: OnboardingScreen(store: store)),
      );

      expect(find.text('Important: Drinking Game'), findsOneWidget);
      expect(find.byType(DrinkingDisclosureScreen), findsOneWidget);

      final continueButton = find.widgetWithText(FilledButton, 'Continue');
      expect(continueButton, findsOneWidget);
      expect(tester.widget<FilledButton>(continueButton).onPressed, isNull);

      // Scroll to the checkbox and check it.
      final checkbox = find.byType(CheckboxListTile);
      await tester.scrollUntilVisible(checkbox, 200);
      await tester.tap(checkbox);
      await tester.pump();

      expect(tester.widget<FilledButton>(continueButton).onPressed, isNotNull);
    });

    testWidgets('terms screen: checkbox unchecked → button disabled', (
      tester,
    ) async {
      final store = OnboardingStore.inMemory();
      store.setDobSelected(true);
      store.advanceStep(); // → adultConfirmation
      store.advanceStep(); // → drinkingDisclosure
      store.advanceStep(); // → termsPrivacy

      await tester.pumpWidget(
        MaterialApp(home: OnboardingScreen(store: store)),
      );

      expect(find.text('Terms & Privacy'), findsOneWidget);
      expect(find.byType(TermsPrivacyScreen), findsOneWidget);

      final acceptButton = find.widgetWithText(
        FilledButton,
        'Accept & Continue',
      );
      expect(acceptButton, findsOneWidget);
      expect(tester.widget<FilledButton>(acceptButton).onPressed, isNull);

      // Store should not have terms accepted yet.
      expect(store.termsAccepted, isFalse);
      expect(store.privacyAcknowledged, isFalse);
    });

    testWidgets('terms screen: tapping checkbox enables button', (
      tester,
    ) async {
      final store = OnboardingStore.inMemory();
      store.setDobSelected(true);
      store.advanceStep();
      store.advanceStep();
      store.advanceStep();
      // Pre-set the previous steps so isComplete would work if all were done.
      store.setAgeConfirmed(true);
      store.setDrinkingAcknowledged(true);

      await tester.pumpWidget(
        MaterialApp(home: OnboardingScreen(store: store)),
      );

      final acceptButton = find.widgetWithText(
        FilledButton,
        'Accept & Continue',
      );

      // Initially disabled.
      expect(tester.widget<FilledButton>(acceptButton).onPressed, isNull);

      // Tap the checkbox.
      final checkbox = find.byType(CheckboxListTile);
      await tester.scrollUntilVisible(checkbox, 200);
      await tester.tap(checkbox);
      await tester.pump();

      // Button should now be enabled.
      expect(tester.widget<FilledButton>(acceptButton).onPressed, isNotNull);

      // But store should NOT be updated yet (only on button press).
      expect(store.termsAccepted, isFalse);
      expect(store.privacyAcknowledged, isFalse);
    });

    testWidgets('terms screen: Accept & Continue completes onboarding', (
      tester,
    ) async {
      final store = OnboardingStore.inMemory();
      store.setDobSelected(true);
      store.setAgeConfirmed(true);
      store.setDrinkingAcknowledged(true);
      store.advanceStep();
      store.advanceStep();
      store.advanceStep();
      // We are on termsPrivacy step.

      await tester.pumpWidget(
        MaterialApp(home: OnboardingScreen(store: store)),
      );

      // Tap the checkbox.
      final checkbox = find.byType(CheckboxListTile);
      await tester.scrollUntilVisible(checkbox, 200);
      await tester.tap(checkbox);
      await tester.pump();

      // Tap Accept & Continue.
      final acceptButton = find.widgetWithText(
        FilledButton,
        'Accept & Continue',
      );
      await tester.tap(acceptButton);
      await tester.pumpAndSettle();

      // Onboarding should now be complete.
      expect(store.isComplete, isTrue);
      expect(store.termsAccepted, isTrue);
      expect(store.privacyAcknowledged, isTrue);
    });

    testWidgets('terms screen: user proceeds to home after completion', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'settings.legalConsentAccepted': true,
        'settings.legalConsentVersion': '1.0',
      });
      final settings = await SettingsStore.load();
      final store = OnboardingStore.inMemory();
      store.setDobSelected(true);
      store.setAgeConfirmed(true);
      store.setDrinkingAcknowledged(true);
      store.advanceStep();
      store.advanceStep();
      store.advanceStep();

      await tester.pumpWidget(
        TurtleKingApp(store: settings, onboarding: store),
      );

      // We should see the onboarding screen.
      expect(find.byType(OnboardingScreen), findsOneWidget);

      // Complete the terms step.
      final checkbox = find.byType(CheckboxListTile);
      await tester.scrollUntilVisible(checkbox, 200);
      await tester.tap(checkbox);
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Accept & Continue'));
      await tester.pumpAndSettle();

      // The onboarding guard should now show the splash/home.
      expect(find.byType(OnboardingScreen), findsNothing);
    });

    testWidgets('full onboarding flow completes via store-driven steps', (
      tester,
    ) async {
      final store = OnboardingStore.inMemory();

      // Step 1: DOB — simulate a valid DOB selection via the store.
      await tester.pumpWidget(
        MaterialApp(home: OnboardingScreen(store: store)),
      );
      expect(find.text('Before You Play'), findsOneWidget);
      store.setDobSelected(true);
      store.advanceStep();
      await tester.pumpAndSettle();

      // Step 2: Adult confirmation.
      expect(find.text('Age Confirmation'), findsOneWidget);
      final step2Checkbox = find.byType(CheckboxListTile);
      await tester.scrollUntilVisible(step2Checkbox, 200);
      await tester.tap(step2Checkbox);
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await tester.pumpAndSettle();

      // Step 3: Drinking disclosure.
      expect(find.text('Important: Drinking Game'), findsOneWidget);
      final step3Checkbox = find.byType(CheckboxListTile);
      await tester.scrollUntilVisible(step3Checkbox, 200);
      await tester.tap(step3Checkbox);
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await tester.pumpAndSettle();

      // Step 4: Terms & Privacy.
      expect(find.text('Terms & Privacy'), findsOneWidget);
      final step4Checkbox = find.byType(CheckboxListTile);
      await tester.scrollUntilVisible(step4Checkbox, 200);
      await tester.tap(step4Checkbox);
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Accept & Continue'));
      await tester.pumpAndSettle();

      expect(store.isComplete, isTrue);
    });

    testWidgets('back button returns to previous step', (tester) async {
      final store = OnboardingStore.inMemory();
      store.setDobSelected(true);
      store.advanceStep(); // → adultConfirmation

      await tester.pumpWidget(
        MaterialApp(home: OnboardingScreen(store: store)),
      );

      expect(find.text('Age Confirmation'), findsOneWidget);

      // Tap back.
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(find.text('Before You Play'), findsOneWidget);
      expect(store.currentStep, OnboardingStep.dob);
    });
  });

  // ---------------------------------------------------------------------------
  // Onboarding persistence tests
  // ---------------------------------------------------------------------------
  group('Onboarding persistence', () {
    testWidgets('first launch shows onboarding', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = await SettingsStore.load();
      final onboarding = await OnboardingStore.load();

      expect(onboarding.isComplete, isFalse);

      await tester.pumpWidget(
        TurtleKingApp(store: settings, onboarding: onboarding),
      );
      await tester.pump();

      expect(find.byType(OnboardingScreen), findsOneWidget);
    });

    testWidgets('completed onboarding persists across restart', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final onboarding = await OnboardingStore.load();

      onboarding.completeOnboarding();
      expect(onboarding.isComplete, isTrue);

      final onboarding2 = await OnboardingStore.load();
      expect(onboarding2.isComplete, isTrue);
    });

    testWidgets('clearing data resets onboarding', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final onboarding = await OnboardingStore.load();

      onboarding.completeOnboarding();
      expect(onboarding.isComplete, isTrue);

      onboarding.resetAll();
      expect(onboarding.isComplete, isFalse);
    });

    testWidgets('version change requires re-acceptance', (tester) async {
      SharedPreferences.setMockInitialValues({
        'onboarding.completed': true,
        'onboarding.termsVersion': '0.9',
        'onboarding.privacyVersion': '0.9',
      });

      final onboarding = await OnboardingStore.load();
      expect(onboarding.isComplete, isFalse);
    });

    testWidgets('underage user cannot reach gameplay', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final onboarding = OnboardingStore.inMemory();

      onboarding.setUnderageBlocked(true);

      await tester.pumpWidget(TurtleKingApp(onboarding: onboarding));
      await tester.pump();

      // Should show the onboarding screen, not the home screen.
      expect(find.byType(OnboardingScreen), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Navigation guard tests
  // ---------------------------------------------------------------------------
  group('Navigation guard', () {
    testWidgets('incomplete onboarding blocks access to home', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = await SettingsStore.load();
      final onboarding = OnboardingStore.inMemory();

      await tester.pumpWidget(
        TurtleKingApp(store: settings, onboarding: onboarding),
      );
      await tester.pump();

      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.text('New Game'), findsNothing);
    });

    testWidgets('completed onboarding shows home', (tester) async {
      SharedPreferences.setMockInitialValues({
        'settings.legalConsentAccepted': true,
        'settings.legalConsentVersion': '1.0',
      });
      final settings = await SettingsStore.load();
      final onboarding = OnboardingStore.inMemory()..completeOnboarding();

      await tester.pumpWidget(
        TurtleKingApp(store: settings, onboarding: onboarding),
      );
      await tester.pump(const Duration(milliseconds: 1300));
      await tester.pumpAndSettle();

      expect(find.text('New Game'), findsOneWidget);
    });

    testWidgets('changing DOB resets dependent confirmations', (tester) async {
      final store = OnboardingStore.inMemory();
      store.setDobSelected(true);
      store.setAgeConfirmed(true);
      store.setDrinkingAcknowledged(true);
      store.setTermsAccepted(true);
      store.setPrivacyAcknowledged(true);
      expect(store.isComplete, isTrue);

      // Simulate changing DOB by resetting confirmations.
      store.resetConfirmations();
      expect(store.ageConfirmed, isFalse);
      expect(store.isComplete, isFalse);
    });
  });
}
