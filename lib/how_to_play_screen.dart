import 'package:flutter/material.dart';

import 'rules.dart';

/// How to play Turtle King per the authoritative rules.
///
/// Pure documentation/UI: the screen is stateless, takes no [GameState], and
/// never mutates gameplay state. The rules text is not duplicated here — it
/// comes from the single source of truth [RulesContent.sections], which is
/// also used by the in-game rules reference and verified by contract tests.
/// Where the authoritative rules are silent, the implemented choice is
/// clearly labeled as a project rule/assumption in the "Current Project
/// Rules" section.
class HowToPlayScreen extends StatelessWidget {
  const HowToPlayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('How to Play')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final section in RulesContent.sections)
                _Section(section: section),
            ],
          ),
        ),
      ),
    );
  }
}

/// One titled block of the How to Play screen rendered from [RulesSection]:
/// a heading, optional body text, optional bullet list, and an optional
/// highlighted example box.
class _Section extends StatelessWidget {
  const _Section({required this.section});

  final RulesSection section;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final heading = Text(
      section.title,
      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
    );
    final bodyText = Text(
      section.body,
      style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
    );
    final bulletText = section.bullets.isEmpty
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final bullet in section.bullets)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '• $bullet',
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                  ),
                ),
            ],
          );
    final exampleBox = section.example == null
        ? null
        : Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              section.example!,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
            ),
          );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heading,
        const SizedBox(height: 8),
        bodyText,
        if (bulletText != null) ...[const SizedBox(height: 8), bulletText],
        if (exampleBox != null) ...[const SizedBox(height: 12), exampleBox],
      ],
    );

    if (!section.highlighted) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: content,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: content,
      ),
    );
  }
}
