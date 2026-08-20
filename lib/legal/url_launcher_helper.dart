import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

/// Helper for launching URLs with proper error handling.
///
/// Handles cases where:
/// - No browser is available
/// - URL is invalid
/// - Launch fails for any reason
class UrlLauncherHelper {
  UrlLauncherHelper._();

  /// Attempts to launch the given URL.
  ///
  /// Shows a SnackBar with an error message if the launch fails.
  /// Returns true if the URL was launched successfully, false otherwise.
  static Future<bool> openUrl(
    BuildContext context,
    String url, {
    String? errorMessage,
  }) async {
    final uri = Uri.parse(url);

    if (!await launcher.canLaunchUrl(uri)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              errorMessage ??
                  'Could not open the link. '
                      'Please check your internet connection and try again.',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return false;
    }

    try {
      final launched = await launcher.launchUrl(
        uri,
        mode: launcher.LaunchMode.externalApplication,
      );

      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              errorMessage ??
                  'Could not open the link. '
                      'Please try again later.',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }

      return launched;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              errorMessage ?? 'An error occurred while opening the link.',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return false;
    }
  }

  /// Convenience method to open the Privacy Policy.
  static Future<bool> openPrivacyPolicy(BuildContext context, String url) {
    return openUrl(
      context,
      url,
      errorMessage:
          'Could not open the Privacy Policy. '
          'Please check your internet connection and try again.',
    );
  }

  /// Convenience method to open the Terms of Service.
  static Future<bool> openTermsOfService(BuildContext context, String url) {
    return openUrl(
      context,
      url,
      errorMessage:
          'Could not open the Terms of Service. '
          'Please check your internet connection and try again.',
    );
  }

  /// Convenience method to open the Contact page.
  static Future<bool> openContact(BuildContext context, String url) {
    return openUrl(
      context,
      url,
      errorMessage:
          'Could not open the Contact page. '
          'Please check your internet connection and try again.',
    );
  }
}
