import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/how_to_play_screen.dart';
import 'package:turtle_king/rules.dart';

/// Every authoritative concept that must stay present in the rules source.
/// The list maps a stable semantic id to the phrases that must appear in the
/// section with that id (title or body or bullets or example).
const Map<String, List<String>> _requiredConcepts = {
  'goal': ['hold out until the end', 'Turtle King'],
  'settingUp': ['single phone', 'players'],
  'twoCards': ['two cards', 'only look', 'ONE', 'hidden'],
  'passThePhone': ['pass the phone', 'Continue'],
  'pouringCup': ['water cup', 'poured', 'YAMADA'],
  'yamada': ['admit defeat', 'drink the water', 'two new cards'],
  'holdOut': ['hold out', 'reveal their cards together'],
  'reveal': ['drink a full cup', 'extra cup', 'smallest'],
  'cupSizes': ['normal cup', 'large cup', 'extra-large cup'],
  'drinkingCounts': ['drinking event', 'six'],
  'multipleRounds': ['new round', '52 cards'],
  'elimination': ['eliminated', 'fewer than two active players'],
  'turtleKing': ['last player remaining', 'crown'],
  'projectRules': ['project rules', 'assumption'],
};

void main() {
  group('RulesContent single source', () {
    test('has the expected sections in order', () {
      expect(
        [for (final section in RulesContent.sections) section.id],
        [
          'goal',
          'settingUp',
          'twoCards',
          'passThePhone',
          'pouringCup',
          'yamada',
          'holdOut',
          'reveal',
          'cupSizes',
          'drinkingCounts',
          'multipleRounds',
          'elimination',
          'turtleKing',
          'projectRules',
        ],
      );
    });

    test('every required concept is present in the right section', () {
      final byId = {
        for (final section in RulesContent.sections) section.id: section,
      };
      _requiredConcepts.forEach((id, phrases) {
        final section = byId[id];
        expect(section, isNotNull, reason: 'missing section $id');
        final haystack = [
          section!.title,
          section.body,
          ...section.bullets,
          if (section.example != null) section.example!,
        ].join(' ').toLowerCase();
        for (final phrase in phrases) {
          expect(
            haystack,
            contains(phrase.toLowerCase()),
            reason: 'section $id must explain "$phrase"',
          );
        }
      });
    });

    test('sections carry stable non-empty ids', () {
      for (final section in RulesContent.sections) {
        expect(section.id, isNotEmpty);
        expect(section.id, matches(RegExp(r'^[a-zA-Z0-9]+$')));
      }
    });

    test('only the project-rules section is highlighted as an assumption', () {
      final highlighted = [
        for (final section in RulesContent.sections)
          if (section.highlighted) section.id,
      ];
      expect(highlighted, ['projectRules']);
    });
  });

  group('HowToPlayScreen renders the shared source', () {
    testWidgets('renders every section title from the shared source', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: HowToPlayScreen()));

      for (final section in RulesContent.sections) {
        expect(
          find.text(section.title),
          findsOneWidget,
          reason: 'missing rendered section ${section.id}',
        );
      }
    });

    testWidgets('there is exactly one copy of the rules in the widget tree', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: HowToPlayScreen()));

      // The screen consumes the shared source; no other widget holds its own
      // rules text. Rendered body of the YAMADA section appears exactly once.
      final yamada = RulesContent.sections.firstWhere((s) => s.id == 'yamada');
      expect(find.text(yamada.body), findsOneWidget);
    });
  });
}
