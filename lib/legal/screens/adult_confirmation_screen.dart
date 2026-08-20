import 'package:flutter/material.dart';

import '../onboarding_store.dart';

/// Screen 2 of the onboarding flow: explicit adult confirmation.
///
/// After a valid DOB has been selected and the calculated age is >= 18,
/// the user must explicitly confirm they are 18 or older.
/// DOB alone is NOT sufficient — an explicit checkbox is required.
class AdultConfirmationScreen extends StatefulWidget {
  const AdultConfirmationScreen({super.key, required this.store});

  final OnboardingStore store;

  @override
  State<AdultConfirmationScreen> createState() =>
      _AdultConfirmationScreenState();
}

class _AdultConfirmationScreenState extends State<AdultConfirmationScreen> {
  bool _confirmed = false;

  void _onConfirmChanged(bool? value) {
    setState(() {
      _confirmed = value ?? false;
    });
    widget.store.setAgeConfirmed(_confirmed);
  }

  void _onContinue() {
    if (!_confirmed) return;
    widget.store.advanceStep();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 32,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Branding
                    Center(
                      child: Image.asset(
                        'assets/branding/turtle_king_emblem.png',
                        width: 80,
                        height: 80,
                        fit: BoxFit.contain,
                        semanticLabel: 'Turtle King logo',
                      ),
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: Text(
                        'Age Confirmation',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: Text(
                        'You have indicated that you are 18 or older.\nPlease confirm to continue.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 32),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _confirmed,
                      onChanged: _onConfirmChanged,
                      title: const Text(
                        'I confirm that I am 18 years of age or older.',
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Continue button
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _confirmed ? _onContinue : null,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 48,
                      vertical: 16,
                    ),
                    textStyle: theme.textTheme.titleMedium,
                  ),
                  child: const Text('Continue'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
