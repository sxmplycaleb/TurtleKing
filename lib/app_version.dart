import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Formats a semantic version string as the user-facing `vX.Y.Z` label
/// (e.g. `1.2.0` → `v1.2.0`).
///
/// Returns an empty string for a blank value — used when no package metadata
/// is available (e.g. bare widget tests), so the UI simply omits the label.
String versionLabel(String version) {
  final trimmed = version.trim();
  return trimmed.isEmpty ? '' : 'v$trimmed';
}

/// Renders the app version as `Version vX.Y.Z`.
///
/// The version is never hardcoded or duplicated in Dart: it is read at
/// runtime from the platform package metadata, which the Flutter build
/// populates from `pubspec.yaml`'s `version:` field (`versionName` on
/// Android, `CFBundleShortVersionString` on iOS). The displayed label
/// therefore always matches `pubspec.yaml` automatically — there is no
/// second version constant to keep in sync.
class AppVersionText extends StatefulWidget {
  const AppVersionText({super.key, this.loadVersion});

  /// Test seam: how the semantic version string is obtained. Defaults to
  /// reading `PackageInfo.version` from the platform metadata.
  final Future<String> Function()? loadVersion;

  @override
  State<AppVersionText> createState() => _AppVersionTextState();
}

class _AppVersionTextState extends State<AppVersionText> {
  late final Future<String> _version = (widget.loadVersion ?? _readVersion)();

  static Future<String> _readVersion() async =>
      (await PackageInfo.fromPlatform()).version;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<String>(
      future: _version,
      builder: (context, snapshot) {
        // Unavailable metadata (e.g. no package info in a bare test
        // environment) renders nothing instead of a broken label.
        final label = versionLabel(snapshot.data ?? '');
        if (label.isEmpty) return const SizedBox.shrink();
        return Text(
          'Version $label',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        );
      },
    );
  }
}
