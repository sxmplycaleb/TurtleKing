import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tracks the user's progress through the multi-step onboarding flow.
///
/// Persists each step's completion state so the user does not have to
/// redo the entire flow on app restart. Raw DOB is never persisted.
enum OnboardingStep {
  dob, // Step 1: Date of birth
  adultConfirmation, // Step 2: Explicit 18+ confirmation
  drinkingDisclosure, // Step 3: Drinking game acknowledgement
  termsPrivacy, // Step 4: Terms & Privacy acceptance
}

/// The single source of truth for onboarding state.
///
/// Separate from [SettingsStore] because onboarding has richer step-level
/// tracking and versioning. The final completion flag is mirrored into
/// [SettingsStore.legalConsentAccepted] so the existing app-level guard
/// continues to work.
class OnboardingStore extends ChangeNotifier {
  OnboardingStore._({
    required SharedPreferences? prefs,
    required OnboardingStep currentStep,
    required this.dobSelected,
    required this.ageConfirmed,
    required this.drinkingAcknowledged,
    required this.termsAccepted,
    required this.privacyAcknowledged,
    required this.underageBlocked,
    required this.termsVersion,
    required this.privacyVersion,
  }) : _prefs = prefs,
       _currentStep = currentStep;

  // ---------------------------------------------------------------------------
  // Persistence keys
  // ---------------------------------------------------------------------------

  static const _completedKey = 'onboarding.completed';
  static const _dobSelectedKey = 'onboarding.dobSelected';
  static const _ageConfirmedKey = 'onboarding.ageConfirmed';
  static const _drinkingAcknowledgedKey = 'onboarding.drinkingAcknowledged';
  static const _termsAcceptedKey = 'onboarding.termsAccepted';
  static const _privacyAcknowledgedKey = 'onboarding.privacyAcknowledged';
  static const _underageBlockedKey = 'onboarding.underageBlocked';
  static const _termsVersionKey = 'onboarding.termsVersion';
  static const _privacyVersionKey = 'onboarding.privacyVersion';
  static const _currentStepKey = 'onboarding.currentStep';

  /// Current Terms of Service version. Bump when the document changes.
  static const currentTermsVersion = '1.0';

  /// Current Privacy Policy version. Bump when the document changes.
  static const currentPrivacyVersion = '1.0';

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  final SharedPreferences? _prefs;

  OnboardingStep _currentStep;
  OnboardingStep get currentStep => _currentStep;

  /// Whether a valid DOB has been selected.
  bool dobSelected;

  /// Whether the user has explicitly confirmed they are 18+.
  bool ageConfirmed;

  /// Whether the drinking-game disclosure has been acknowledged.
  bool drinkingAcknowledged;

  /// Whether the Terms of Service have been accepted.
  bool termsAccepted;

  /// Whether the Privacy Policy has been acknowledged.
  bool privacyAcknowledged;

  /// Whether the user is underage (< 18).
  bool underageBlocked;

  /// Stored Terms version at time of acceptance.
  String termsVersion;

  /// Stored Privacy version at time of acceptance.
  String privacyVersion;

  /// Whether the entire onboarding flow is complete.
  bool get isComplete =>
      dobSelected &&
      ageConfirmed &&
      drinkingAcknowledged &&
      termsAccepted &&
      privacyAcknowledged &&
      !underageBlocked;

  // ---------------------------------------------------------------------------
  // Loading
  // ---------------------------------------------------------------------------

  /// Loads persisted onboarding state. If already completed, returns a
  /// completed store immediately.
  static Future<OnboardingStore> load() async {
    final prefs = await SharedPreferences.getInstance();

    final completed = prefs.getBool(_completedKey) ?? false;
    final underageBlocked = prefs.getBool(_underageBlockedKey) ?? false;

    if (completed && !underageBlocked) {
      // Check version freshness even when completed.
      final storedTermsVersion = prefs.getString(_termsVersionKey) ?? '';
      final storedPrivacyVersion = prefs.getString(_privacyVersionKey) ?? '';
      final termsFresh =
          storedTermsVersion == currentTermsVersion &&
          storedTermsVersion.isNotEmpty;
      final privacyFresh =
          storedPrivacyVersion == currentPrivacyVersion &&
          storedPrivacyVersion.isNotEmpty;

      if (termsFresh && privacyFresh) {
        // All steps already accepted with matching versions — fast path.
        return OnboardingStore._(
          prefs: prefs,
          currentStep: OnboardingStep.termsPrivacy,
          dobSelected: true,
          ageConfirmed: true,
          drinkingAcknowledged: true,
          termsAccepted: true,
          privacyAcknowledged: true,
          underageBlocked: false,
          termsVersion: storedTermsVersion,
          privacyVersion: storedPrivacyVersion,
        );
      }
    }

    // Check version freshness.
    final storedTermsVersion = prefs.getString(_termsVersionKey) ?? '';
    final storedPrivacyVersion = prefs.getString(_privacyVersionKey) ?? '';

    final termsFresh =
        storedTermsVersion == currentTermsVersion &&
        storedTermsVersion.isNotEmpty;
    final privacyFresh =
        storedPrivacyVersion == currentPrivacyVersion &&
        storedPrivacyVersion.isNotEmpty;

    return OnboardingStore._(
      prefs: prefs,
      currentStep: _readStep(prefs.getString(_currentStepKey)),
      dobSelected: prefs.getBool(_dobSelectedKey) ?? false,
      ageConfirmed: (prefs.getBool(_ageConfirmedKey) ?? false) && termsFresh,
      drinkingAcknowledged: (prefs.getBool(_drinkingAcknowledgedKey) ?? false),
      termsAccepted: (prefs.getBool(_termsAcceptedKey) ?? false) && termsFresh,
      privacyAcknowledged:
          (prefs.getBool(_privacyAcknowledgedKey) ?? false) && privacyFresh,
      underageBlocked: underageBlocked,
      termsVersion: termsFresh ? storedTermsVersion : '',
      privacyVersion: privacyFresh ? storedPrivacyVersion : '',
    );
  }

  /// In-memory store for tests and previews.
  static OnboardingStore inMemory() => OnboardingStore._(
    prefs: null,
    currentStep: OnboardingStep.dob,
    dobSelected: false,
    ageConfirmed: false,
    drinkingAcknowledged: false,
    termsAccepted: false,
    privacyAcknowledged: false,
    underageBlocked: false,
    termsVersion: '',
    privacyVersion: '',
  );

  // ---------------------------------------------------------------------------
  // Step navigation
  // ---------------------------------------------------------------------------

  /// Advances to the next onboarding step. Called after each step's
  /// validation passes.
  void advanceStep() {
    switch (_currentStep) {
      case OnboardingStep.dob:
        _currentStep = OnboardingStep.adultConfirmation;
      case OnboardingStep.adultConfirmation:
        _currentStep = OnboardingStep.drinkingDisclosure;
      case OnboardingStep.drinkingDisclosure:
        _currentStep = OnboardingStep.termsPrivacy;
      case OnboardingStep.termsPrivacy:
        // Already at the last step; nothing to do.
        break;
    }
    _persist(_currentStepKey, _currentStep.name);
    notifyListeners();
  }

  /// Goes back to the previous step (if possible).
  void goBack() {
    switch (_currentStep) {
      case OnboardingStep.adultConfirmation:
        _currentStep = OnboardingStep.dob;
      case OnboardingStep.drinkingDisclosure:
        _currentStep = OnboardingStep.adultConfirmation;
      case OnboardingStep.termsPrivacy:
        _currentStep = OnboardingStep.drinkingDisclosure;
      case OnboardingStep.dob:
        break;
    }
    _persist(_currentStepKey, _currentStep.name);
    notifyListeners();
  }

  /// Jumps directly to the DOB step (used when returning from the
  /// underage block screen).
  void goToDob() {
    _currentStep = OnboardingStep.dob;
    _persist(_currentStepKey, _currentStep.name);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Step setters
  // ---------------------------------------------------------------------------

  /// Records that a valid DOB has been selected.
  void setDobSelected(bool value) {
    if (dobSelected == value) return;
    dobSelected = value;
    _persistBool(_dobSelectedKey, value);
    notifyListeners();
  }

  /// Records the explicit age confirmation.
  void setAgeConfirmed(bool value) {
    if (ageConfirmed == value) return;
    ageConfirmed = value;
    _persistBool(_ageConfirmedKey, value);
    notifyListeners();
  }

  /// Records the drinking-game disclosure acknowledgement.
  void setDrinkingAcknowledged(bool value) {
    if (drinkingAcknowledged == value) return;
    drinkingAcknowledged = value;
    _persistBool(_drinkingAcknowledgedKey, value);
    notifyListeners();
  }

  /// Records the Terms of Service acceptance.
  void setTermsAccepted(bool value) {
    if (termsAccepted == value) return;
    termsAccepted = value;
    _persistBool(_termsAcceptedKey, value);
    if (value) {
      _persist(_termsVersionKey, currentTermsVersion);
      termsVersion = currentTermsVersion;
    }
    notifyListeners();
  }

  /// Records the Privacy Policy acknowledgement.
  void setPrivacyAcknowledged(bool value) {
    if (privacyAcknowledged == value) return;
    privacyAcknowledged = value;
    _persistBool(_privacyAcknowledgedKey, value);
    if (value) {
      _persist(_privacyVersionKey, currentPrivacyVersion);
      privacyVersion = currentPrivacyVersion;
    }
    notifyListeners();
  }

  /// Records that the user is underage and blocks them.
  void setUnderageBlocked(bool value) {
    if (underageBlocked == value) return;
    underageBlocked = value;
    _persistBool(_underageBlockedKey, value);
    // If underage, reset all dependent confirmations.
    if (value) {
      ageConfirmed = false;
      drinkingAcknowledged = false;
      termsAccepted = false;
      privacyAcknowledged = false;
      _persistBool(_ageConfirmedKey, false);
      _persistBool(_drinkingAcknowledgedKey, false);
      _persistBool(_termsAcceptedKey, false);
      _persistBool(_privacyAcknowledgedKey, false);
    }
    notifyListeners();
  }

  /// Resets all confirmations when the DOB changes, forcing the user
  /// to re-confirm from the adult confirmation step onward.
  void resetConfirmations() {
    ageConfirmed = false;
    drinkingAcknowledged = false;
    termsAccepted = false;
    privacyAcknowledged = false;
    _persistBool(_ageConfirmedKey, false);
    _persistBool(_drinkingAcknowledgedKey, false);
    _persistBool(_termsAcceptedKey, false);
    _persistBool(_privacyAcknowledgedKey, false);
    notifyListeners();
  }

  /// Marks onboarding as complete and persists the final state.
  void completeOnboarding() {
    dobSelected = true;
    ageConfirmed = true;
    drinkingAcknowledged = true;
    termsAccepted = true;
    privacyAcknowledged = true;
    underageBlocked = false;
    _persistBool(_completedKey, true);
    _persistBool(_dobSelectedKey, true);
    _persistBool(_ageConfirmedKey, true);
    _persistBool(_drinkingAcknowledgedKey, true);
    _persistBool(_termsAcceptedKey, true);
    _persistBool(_privacyAcknowledgedKey, true);
    _persistBool(_underageBlockedKey, false);
    _persist(_termsVersionKey, currentTermsVersion);
    _persist(_privacyVersionKey, currentPrivacyVersion);
    termsVersion = currentTermsVersion;
    privacyVersion = currentPrivacyVersion;
    notifyListeners();
  }

  /// Resets the entire onboarding state (for testing or privacy compliance).
  void resetAll() {
    _currentStep = OnboardingStep.dob;
    dobSelected = false;
    ageConfirmed = false;
    drinkingAcknowledged = false;
    termsAccepted = false;
    privacyAcknowledged = false;
    underageBlocked = false;
    termsVersion = '';
    privacyVersion = '';
    _persistBool(_completedKey, false);
    _persist(_currentStepKey, OnboardingStep.dob.name);
    _persistBool(_dobSelectedKey, false);
    _persistBool(_ageConfirmedKey, false);
    _persistBool(_drinkingAcknowledgedKey, false);
    _persistBool(_termsAcceptedKey, false);
    _persistBool(_privacyAcknowledgedKey, false);
    _persistBool(_underageBlockedKey, false);
    _persist(_termsVersionKey, '');
    _persist(_privacyVersionKey, '');
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  static OnboardingStep _readStep(String? stored) {
    if (stored == null) return OnboardingStep.dob;
    for (final step in OnboardingStep.values) {
      if (step.name == stored) return step;
    }
    return OnboardingStep.dob;
  }

  void _persistBool(String key, bool value) {
    _prefs?.setBool(key, value);
  }

  void _persist(String key, String value) {
    _prefs?.setString(key, value);
  }
}
