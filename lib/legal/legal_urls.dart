/// Centralized legal document URLs for TurtleKing.
///
/// All legal links in the app should reference these constants.
/// This ensures consistency and makes URL updates a single-point change.
///
/// The base URL should point to your GitHub Pages deployment or custom domain.
/// For GitHub Pages, the format is:
///   `https://username.github.io/repo-name/legal/`
///
/// For a custom domain, use:
///   `https://your-domain/legal/`
class LegalUrls {
  LegalUrls._();

  /// Base URL for the legal website.
  ///
  /// Update this to your actual deployed URL before publishing.
  /// For GitHub Pages: `https://username.github.io/turtle_king/legal/`
  /// For custom domain: `https://your-domain/legal/`
  static const String baseUrl = 'YOUR_GITHUB_PAGES_URL_HERE';

  /// Privacy Policy URL.
  static const String privacyPolicy = '$baseUrl/privacy.html';

  /// Terms of Service URL.
  static const String termsOfService = '$baseUrl/terms.html';

  /// Contact page URL.
  static const String contact = '$baseUrl/contact.html';

  /// Whether the URLs are configured (not placeholders).
  ///
  /// Returns false if any URL still contains 'YOUR_GITHUB_PAGES_URL_HERE'.
  static bool get isConfigured =>
      !baseUrl.contains('YOUR_GITHUB_PAGES_URL_HERE') &&
      !privacyPolicy.contains('YOUR_GITHUB_PAGES_URL_HERE') &&
      !termsOfService.contains('YOUR_GITHUB_PAGES_URL_HERE') &&
      !contact.contains('YOUR_GITHUB_PAGES_URL_HERE');
}
