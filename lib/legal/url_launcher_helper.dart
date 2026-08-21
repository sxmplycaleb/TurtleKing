import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

/// Helper for launching URLs with proper error handling.
///
/// Handles cases where:
/// - No browser is available
/// - URL is invalid
/// - Launch fails for any reason
///
/// Note: On Android 11+ (API 30+), `canLaunchUrl` may return false for
/// HTTPS URLs even when launching can work, because of package visibility
/// rules. We therefore try `launchUrl` directly and only show an error
/// if that also fails.
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

    // On Android 11+ (API 30+), canLaunchUrl may return false even for
    // valid HTTPS URLs due to package visibility rules. The official
    // url_launcher docs recommend trying launchUrl directly rather than
    // gating on canLaunchUrl.
    try {
      final launched = await launcher.launchUrl(
        uri,
        mode: launcher.LaunchMode.externalApplication,
      );

      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              errorMessage ?? 'Unable to open this link. Please try again.',
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
              errorMessage ?? 'Unable to open this link. Please try again.',
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
      errorMessage: 'Unable to open the Privacy Policy. Please try again.',
    );
  }

  /// Convenience method to open the Terms of Service.
  static Future<bool> openTermsOfService(BuildContext context, String url) {
    return openUrl(
      context,
      url,
      errorMessage: 'Unable to open the Terms of Service. Please try again.',
    );
  }

  /// Convenience method to open the Contact page.
  static Future<bool> openContact(BuildContext context, String url) {
    return openUrl(
      context,
      url,
      errorMessage: 'Unable to open the Contact page. Please try again.',
    );
  }
}
