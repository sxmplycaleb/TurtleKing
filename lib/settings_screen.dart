import 'package:flutter/material.dart' hide Card;

import 'app_version.dart';
import 'card.dart';
import 'card_widgets.dart';
import 'legal/legal_urls.dart';
import 'legal/url_launcher_helper.dart';
import 'settings.dart';
import 'theme.dart';

/// The personalization screen.
///
/// Reads and writes the app-wide [SettingsStore] (theme mode, accent color
/// theme, card design). Purely presentational — it never touches gameplay
/// state. Every change applies immediately and persists.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _SectionTitle(title: 'Appearance'),
            const _ThemeModeSelector(),
            const SizedBox(height: 24),
            _SectionTitle(title: 'Color Theme'),
            const _ColorThemeSelector(),
            const SizedBox(height: 24),
            _SectionTitle(title: 'Cards'),
            const _CardDesignSelector(),
            const SizedBox(height: 24),
            _SectionTitle(title: 'Feedback'),
            const _FeedbackToggles(),
            const SizedBox(height: 16),
            Text(
              'These settings only change how the game looks and sounds — '
              'they never affect cards, hands, rounds, drinks, '
              'eliminations, or the winner.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            _SectionTitle(title: 'About'),
            const AppVersionText(),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('Privacy Policy'),
              subtitle: const Text('How we handle your data'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                UrlLauncherHelper.openPrivacyPolicy(
                  context,
                  LegalUrls.privacyPolicy,
                );
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.description_outlined),
              title: const Text('Terms of Service'),
              subtitle: const Text('Usage terms and conditions'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                UrlLauncherHelper.openTermsOfService(
                  context,
                  LegalUrls.termsOfService,
                );
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.contact_mail_outlined),
              title: const Text('Contact'),
              subtitle: const Text('Get in touch with us'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                UrlLauncherHelper.openContact(context, LegalUrls.contact);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// A small uppercase heading for a settings section.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

/// The System / Light / Dark radio group.
class _ThemeModeSelector extends StatelessWidget {
  const _ThemeModeSelector();

  @override
  Widget build(BuildContext context) {
    final store = SettingsScope.of(context);
    final entries = <(ThemeModePref, IconData, String)>[
      (
        ThemeModePref.system,
        Icons.brightness_auto_outlined,
        'Follow the device',
      ),
      (ThemeModePref.light, Icons.light_mode_outlined, 'Always light'),
      (ThemeModePref.dark, Icons.dark_mode_outlined, 'Always dark'),
    ];
    return RadioGroup<ThemeModePref>(
      groupValue: store.themeMode,
      onChanged: (v) {
        if (v != null) store.setThemeMode(v);
      },
      child: Column(
        children: [
          for (final (value, icon, subtitle) in entries)
            RadioListTile<ThemeModePref>(
              value: value,
              contentPadding: EdgeInsets.zero,
              secondary: Icon(icon),
              title: Text(value.label),
              subtitle: Text(subtitle),
            ),
        ],
      ),
    );
  }
}

/// The accent color-theme swatch selector.
class _ColorThemeSelector extends StatelessWidget {
  const _ColorThemeSelector();

  @override
  Widget build(BuildContext context) {
    final store = SettingsScope.of(context);
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final colorTheme in AppColorTheme.values)
          _SwatchTile(
            colorTheme: colorTheme,
            selected: store.colorTheme == colorTheme,
            onTap: () => store.setColorTheme(colorTheme),
          ),
      ],
    );
  }
}

/// One selectable accent-color swatch with a label and a check marker.
class _SwatchTile extends StatelessWidget {
  const _SwatchTile({
    required this.colorTheme,
    required this.selected,
    required this.onTap,
  });

  final AppColorTheme colorTheme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: 'Color theme ${colorTheme.label}',
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: colorTheme.accent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.outlineVariant,
                    width: selected ? 3 : 1,
                  ),
                ),
                child: selected
                    ? Icon(Icons.check, color: colorTheme.onAccent)
                    : null,
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: 72,
                child: Text(
                  colorTheme.label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The sound/haptic feedback switches.
class _FeedbackToggles extends StatelessWidget {
  const _FeedbackToggles();

  @override
  Widget build(BuildContext context) {
    final store = SettingsScope.of(context);
    return Column(
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.volume_up_outlined),
          title: const Text('Sound Effects'),
          subtitle: const Text(
            'Play sounds for card reveals, YAMADA, '
            'eliminations, and the Turtle King victory',
          ),
          value: store.soundEnabled,
          onChanged: (value) => store.setSoundEnabled(value),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.vibration_outlined),
          title: const Text('Haptic Feedback'),
          subtitle: const Text('Vibrate on important game moments'),
          value: store.hapticsEnabled,
          onChanged: (value) => store.setHapticsEnabled(value),
        ),
      ],
    );
  }
}

/// The card-design selector with live previews.
class _CardDesignSelector extends StatelessWidget {
  const _CardDesignSelector();

  static const Card _sample = Card(suit: Suit.spades, rank: Rank.ace);

  @override
  Widget build(BuildContext context) {
    final store = SettingsScope.of(context);
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final design in CardDesign.values)
          _CardDesignTile(
            design: design,
            style: CardStyle.forDesign(design, accent: store.colorTheme.accent),
            selected: store.cardDesign == design,
            onTap: () => store.setCardDesign(design),
          ),
      ],
    );
  }
}

/// One selectable card-design tile: a face-up preview, a back preview, and a
/// label with a check marker when selected.
class _CardDesignTile extends StatelessWidget {
  const _CardDesignTile({
    required this.design,
    required this.style,
    required this.selected,
    required this.onTap,
  });

  final CardDesign design;
  final CardStyle style;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: 'Card design ${design.label}',
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
              width: selected ? 2.5 : 1,
            ),
            color: theme.colorScheme.surfaceContainerHighest,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PlayingCard(
                    card: _CardDesignSelector._sample,
                    width: 54,
                    style: style,
                  ),
                  const SizedBox(width: 6),
                  CardBack(width: 54, style: style),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (selected) ...[
                    Icon(
                      Icons.check,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    design.label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: selected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
