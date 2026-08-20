import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'legal_urls.dart';
import 'url_launcher_helper.dart';

/// First-launch legal consent screen.
///
/// Requires the user to enter their age, confirm they are 18+, and agree
/// to the Terms of Service and acknowledge the Privacy Policy.
class LegalConsentScreen extends StatefulWidget {
  const LegalConsentScreen({super.key, this.onConsent});

  /// Called when the user completes consent. The parent should persist
  /// the consent state and navigate to the home screen.
  final VoidCallback? onConsent;

  @override
  State<LegalConsentScreen> createState() => _LegalConsentScreenState();
}

class _LegalConsentScreenState extends State<LegalConsentScreen> {
  final _ageController = TextEditingController();
  final _ageFocusNode = FocusNode();
  bool _ageConfirmed = false;
  bool _termsAccepted = false;
  int? _parsedAge;
  String? _ageError;

  /// Whether the entered age is valid (>= 18).
  bool get _isValidAge => _parsedAge != null && _parsedAge! >= 18;

  /// Whether all conditions are met to enable Continue.
  bool get _canContinue => _isValidAge && _ageConfirmed && _termsAccepted;

  @override
  void dispose() {
    _ageController.dispose();
    _ageFocusNode.dispose();
    super.dispose();
  }

  void _onAgeChanged(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _parsedAge = null;
        _ageError = null;
        _ageConfirmed = false;
      });
      return;
    }

    // Reject non-numeric input.
    final parsed = int.tryParse(trimmed);
    if (parsed == null) {
      setState(() {
        _parsedAge = null;
        _ageError = 'Please enter a valid whole number.';
        _ageConfirmed = false;
      });
      return;
    }

    // Reject negative values, zero, and unreasonable ages.
    if (parsed <= 0 || parsed > 150) {
      setState(() {
        _parsedAge = null;
        _ageError = 'Please enter a valid age.';
        _ageConfirmed = false;
      });
      return;
    }

    // Valid numeric age entered.
    setState(() {
      _parsedAge = parsed;
      _ageError = parsed < 18
          ? 'TurtleKing is intended for adults aged 18 and over.'
          : null;
      // Reset age confirmation if age dropped below 18.
      if (parsed < 18) {
        _ageConfirmed = false;
      }
    });
  }

  void _openPrivacyPolicy() {
    UrlLauncherHelper.openPrivacyPolicy(context, LegalUrls.privacyPolicy);
  }

  void _openTermsOfService() {
    UrlLauncherHelper.openTermsOfService(context, LegalUrls.termsOfService);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header area
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 32,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // App branding
                    Center(
                      child: Image.asset(
                        'assets/branding/turtle_king_emblem.png',
                        width: 100,
                        height: 100,
                        fit: BoxFit.contain,
                        semanticLabel: 'Turtle King logo',
                      ),
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: Text(
                        'Age Verification',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        'TurtleKing is intended\nfor adults aged 18+.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Age input field
                    Text(
                      'Enter your age',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _ageController,
                      focusNode: _ageFocusNode,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall,
                      decoration: InputDecoration(
                        hintText: 'Age',
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        errorText: _ageError,
                      ),
                      inputFormatters: [
                        // Allow only digits.
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      onChanged: _onAgeChanged,
                    ),
                    const SizedBox(height: 24),

                    // Age confirmation checkbox (only enabled when age >= 18)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _ageConfirmed,
                      onChanged: _isValidAge
                          ? (value) {
                              setState(() {
                                _ageConfirmed = value ?? false;
                              });
                            }
                          : null,
                      title: const Text(
                        'I confirm that I am 18 years or older.',
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Terms and Privacy acceptance
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _termsAccepted,
                      onChanged: (value) {
                        setState(() {
                          _termsAccepted = value ?? false;
                        });
                      },
                      title: RichText(
                        text: TextSpan(
                          style: theme.textTheme.bodyMedium,
                          children: [
                            const TextSpan(text: 'I agree to the '),
                            TextSpan(
                              text: 'Terms of Service',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                                decoration: TextDecoration.underline,
                              ),
                              recognizer: TapGestureRecognizer()
                                ..onTap = _openTermsOfService,
                            ),
                            const TextSpan(text: ' and acknowledge the '),
                            TextSpan(
                              text: 'Privacy Policy',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                                decoration: TextDecoration.underline,
                              ),
                              recognizer: TapGestureRecognizer()
                                ..onTap = _openPrivacyPolicy,
                            ),
                            const TextSpan(text: '.'),
                          ],
                        ),
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
                  onPressed: _canContinue ? widget.onConsent : null,
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
