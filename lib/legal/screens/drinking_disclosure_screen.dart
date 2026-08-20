import 'package:flutter/material.dart';

import '../onboarding_store.dart';

/// Screen 3 of the onboarding flow: drinking-game disclosure.
///
/// Clearly explains that TurtleKing is a drinking game and requires
/// explicit acknowledgement before proceeding.
class DrinkingDisclosureScreen extends StatefulWidget {
  const DrinkingDisclosureScreen({super.key, required this.store});

  final OnboardingStore store;

  @override
  State<DrinkingDisclosureScreen> createState() =>
      _DrinkingDisclosureScreenState();
}

class _DrinkingDisclosureScreenState extends State<DrinkingDisclosureScreen> {
  bool _acknowledged = false;

  void _onAckChanged(bool? value) {
    setState(() {
      _acknowledged = value ?? false;
    });
    widget.store.setDrinkingAcknowledged(_acknowledged);
  }

  void _onContinue() {
    if (!_acknowledged) return;
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
                        'Important: Drinking Game',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Disclosure content
                    _DisclosureItem(
                      icon: Icons.local_bar,
                      text:
                          'TurtleKing is a drinking game. Gameplay may '
                          'involve alcohol consumption.',
                    ),
                    const SizedBox(height: 12),
                    _DisclosureItem(
                      icon: Icons.volunteer_activism,
                      text:
                          'Alcohol consumption is optional. You can '
                          'participate with non-alcoholic drinks.',
                    ),
                    const SizedBox(height: 12),
                    _DisclosureItem(
                      icon: Icons.warning_amber,
                      text:
                          'Players should drink responsibly and never '
                          'drink and drive or operate machinery.',
                    ),
                    const SizedBox(height: 12),
                    _DisclosureItem(
                      icon: Icons.gavel,
                      text:
                          'Users should follow applicable laws and '
                          'regulations where they live.',
                    ),
                    const SizedBox(height: 12),
                    _DisclosureItem(
                      icon: Icons.medical_services_outlined,
                      text: 'This game is not medical or health advice.',
                    ),
                    const SizedBox(height: 12),
                    _DisclosureItem(
                      icon: Icons.health_and_safety,
                      text:
                          'People for whom alcohol consumption is unsafe '
                          'or inappropriate should not participate in '
                          'drinking activities.',
                    ),
                    const SizedBox(height: 32),

                    // Acknowledgement checkbox
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _acknowledged,
                      onChanged: _onAckChanged,
                      title: const Text(
                        'I understand that TurtleKing is a drinking game '
                        'and may involve alcohol consumption.',
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
                  onPressed: _acknowledged ? _onContinue : null,
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

class _DisclosureItem extends StatelessWidget {
  const _DisclosureItem({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
      ],
    );
  }
}
