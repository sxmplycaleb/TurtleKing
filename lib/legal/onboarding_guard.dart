import 'package:flutter/material.dart';

import 'onboarding_store.dart';
import 'screens/onboarding_screen.dart';

/// A centralized onboarding guard that wraps the entire app's protected
/// navigation.
///
/// If onboarding has not been completed, the user is redirected to the
/// onboarding flow. Once completed, the [builder] is invoked with the
/// app's root widget.
///
/// This guard must be the outermost wrapper around all gameplay-capable
/// routes. There is no route that can bypass this check.
class OnboardingGuard extends StatefulWidget {
  const OnboardingGuard({
    super.key,
    required this.store,
    required this.builder,
  });

  /// The onboarding store. Provides the current completion state.
  final OnboardingStore store;

  /// Builds the protected app content (home screen, etc.).
  final WidgetBuilder builder;

  @override
  State<OnboardingGuard> createState() => _OnboardingGuardState();
}

class _OnboardingGuardState extends State<OnboardingGuard> {
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

  void _onOnboardingComplete() {
    // After onboarding completes, rebuild to show the protected content.
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.store.isComplete) {
      return OnboardingScreen(
        store: widget.store,
        onComplete: _onOnboardingComplete,
      );
    }
    return widget.builder(context);
  }
}
