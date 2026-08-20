import 'package:flutter/material.dart';

import '../legal_urls.dart';
import '../onboarding_store.dart';
import '../url_launcher_helper.dart';

/// Screen 4 of the onboarding flow: Terms of Service & Privacy Policy.
///
/// The user must review and acknowledge both documents before completing
/// onboarding. The documents are accessible via tappable links.
class TermsPrivacyScreen extends StatefulWidget {
  const TermsPrivacyScreen({super.key, required this.store});

  final OnboardingStore store;

  @override
  State<TermsPrivacyScreen> createState() => _TermsPrivacyScreenState();
}

class _TermsPrivacyScreenState extends State<TermsPrivacyScreen> {
  bool _accepted = false;

  void _onAcceptChanged(bool? value) {
    setState(() {
      _accepted = value ?? false;
    });
    // Do NOT persist to the store here — only update local UI state.
    // Persistence happens in _onComplete when the user presses the button.
  }

  void _onComplete() {
    if (!_accepted) return;
    // Persist consent to the store only when the user explicitly presses
    // "Accept & Continue".
    widget.store.setTermsAccepted(true);
    widget.store.setPrivacyAcknowledged(true);
    widget.store.completeOnboarding();
  }

  void _openTerms() {
    UrlLauncherHelper.openTermsOfService(context, LegalUrls.termsOfService);
  }

  void _openPrivacy() {
    UrlLauncherHelper.openPrivacyPolicy(context, LegalUrls.privacyPolicy);
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
                        'Terms & Privacy',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: Text(
                        'Please review and accept the following documents\nto continue.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Terms of Service link
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.description_outlined),
                        title: const Text('Terms of Service'),
                        subtitle: Text(
                          'Version ${OnboardingStore.currentTermsVersion}',
                          style: theme.textTheme.bodySmall,
                        ),
                        trailing: const Icon(Icons.open_in_new),
                        onTap: _openTerms,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Privacy Policy link
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.privacy_tip_outlined),
                        title: const Text('Privacy Policy'),
                        subtitle: Text(
                          'Version ${OnboardingStore.currentPrivacyVersion}',
                          style: theme.textTheme.bodySmall,
                        ),
                        trailing: const Icon(Icons.open_in_new),
                        onTap: _openPrivacy,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Acceptance checkbox
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _accepted,
                      onChanged: _onAcceptChanged,
                      title: const Text(
                        'I have read and agree to the Terms of Service '
                        'and acknowledge the Privacy Policy.',
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Accept & Continue button
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _accepted ? _onComplete : null,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 48,
                      vertical: 16,
                    ),
                    textStyle: theme.textTheme.titleMedium,
                  ),
                  child: const Text('Accept & Continue'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
