import 'package:flutter/material.dart';

import '../age_calculator.dart';
import '../onboarding_progress.dart';
import '../onboarding_store.dart';
import 'adult_confirmation_screen.dart';
import 'dob_entry_screen.dart';
import 'drinking_disclosure_screen.dart';
import 'terms_privacy_screen.dart';

/// Orchestrates the multi-step onboarding flow.
///
/// Displays a progress indicator and the appropriate screen for the
/// current onboarding step. Manages forward/backward navigation between
/// steps and handles the final completion callback.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.store,
    this.minimumAge = AgeCalculator.defaultMinimumAge,
    this.onComplete,
  });

  final OnboardingStore store;

  /// The minimum age required.
  final int minimumAge;

  /// Called when the entire onboarding flow is complete.
  final VoidCallback? onComplete;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  void _onComplete() {
    widget.onComplete?.call();
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.store.currentStep;

    Widget body;
    switch (step) {
      case OnboardingStep.dob:
        body = DobEntryScreen(
          store: widget.store,
          minimumAge: widget.minimumAge,
        );
      case OnboardingStep.adultConfirmation:
        body = AdultConfirmationScreen(store: widget.store);
      case OnboardingStep.drinkingDisclosure:
        body = DrinkingDisclosureScreen(store: widget.store);
      case OnboardingStep.termsPrivacy:
        body = _TermsPrivacyWithCallback(
          store: widget.store,
          onComplete: _onComplete,
        );
    }

    // For the DOB step, we don't show the back button.
    final showBack = step != OnboardingStep.dob;

    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        // Check completion after rebuild.
        if (widget.store.isComplete) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _onComplete();
          });
        }

        return PopScope(
          canPop: !showBack,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && showBack) {
              widget.store.goBack();
            }
          },
          child: Scaffold(
            appBar: showBack
                ? AppBar(
                    leading: IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => widget.store.goBack(),
                    ),
                    title: const Text('TurtleKing'),
                  )
                : null,
            body: Column(
              children: [
                OnboardingProgress(currentStep: step),
                Expanded(child: body),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Wrapper that calls the onComplete callback when the TermsPrivacyScreen
/// finishes the onboarding flow.
class _TermsPrivacyWithCallback extends StatelessWidget {
  const _TermsPrivacyWithCallback({
    required this.store,
    required this.onComplete,
  });

  final OnboardingStore store;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    return TermsPrivacyScreen(store: store);
  }
}
