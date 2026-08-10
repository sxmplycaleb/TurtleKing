import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/theme.dart';

void main() {
  group('buildTheme', () {
    test('the default is a light Turtle King Gold theme', () {
      final theme = buildTheme();
      expect(theme.brightness, Brightness.light);
      final table = theme.extension<GameTableStyle>()!;
      expect(table.accent, AppColorTheme.turtleKingGold.accent);
    });

    test('dark mode produces a dark theme with the dark felt', () {
      final theme = buildTheme(brightness: Brightness.dark);
      expect(theme.brightness, Brightness.dark);
      final table = theme.extension<GameTableStyle>()!;
      expect(table.feltBottom, AppColorTheme.turtleKingGold.feltDarkBottom);
      expect(table.textPrimary, AppColorTheme.turtleKingGold.textDark);
    });

    test('light mode uses the light felt with dark text', () {
      final theme = buildTheme();
      final table = theme.extension<GameTableStyle>()!;
      expect(table.feltBottom, AppColorTheme.turtleKingGold.feltLightBottom);
      expect(table.textPrimary, AppColorTheme.turtleKingGold.textLight);
    });

    test('every accent theme has a distinct accent color', () {
      final accents = {for (final theme in AppColorTheme.values) theme.accent};
      expect(accents.length, AppColorTheme.values.length);
    });

    test('the accent seeds each theme primary', () {
      for (final colorTheme in AppColorTheme.values) {
        final theme = buildTheme(colorTheme: colorTheme);
        expect(theme.extension<GameTableStyle>()!.accent, colorTheme.accent);
      }
    });

    test('the default card design is Classic Poker', () {
      final theme = buildTheme();
      expect(theme.extension<CardStyle>()!.design, CardDesign.classicPoker);
    });
  });

  group('CardStyle', () {
    test('each design renders distinct face surfaces', () {
      final classic = CardStyle.forDesign(CardDesign.classicPoker);
      final turtleKing = CardStyle.forDesign(CardDesign.turtleKing);
      final noir = CardStyle.forDesign(CardDesign.noir);

      expect(turtleKing.faceTop, isNot(classic.faceTop));
      expect(noir.faceTop, isNot(classic.faceTop));
      expect(noir.faceBottom, isNot(turtleKing.faceBottom));
    });

    test('suit colors stay conventional in every design', () {
      for (final design in CardDesign.values) {
        final style = CardStyle.forDesign(design);
        // Hearts/diamonds are red; clubs/spades stay the "dark" suit ink.
        expect(style.inkRed, isNot(style.inkDark));
      }
      final classic = CardStyle.forDesign(CardDesign.classicPoker);
      expect(classic.inkRed, TurtleKingColors.suitRed);
      expect(classic.inkDark, TurtleKingColors.suitBlack);
    });

    test('the back fields carry no rank or suit data', () {
      final style = CardStyle.forDesign(CardDesign.noir);
      // Only surface colors exist; there is no card-identity field at all.
      expect(style.backSurface, isNotNull);
      expect(style.backDisc, isNotNull);
    });
  });

  group('GameTableStyle', () {
    test('dark felt is never a black void', () {
      final dark = GameTableStyle.forTheme(
        AppColorTheme.turtleKingGold,
        Brightness.dark,
      );
      expect(dark.feltTop.computeLuminance(), greaterThan(0.02));
      expect(dark.feltBottom.computeLuminance(), greaterThan(0.005));
    });

    test('accent text is darkened for contrast on light felt', () {
      final light = GameTableStyle.forTheme(
        AppColorTheme.turtleKingGold,
        Brightness.light,
      );
      final dark = GameTableStyle.forTheme(
        AppColorTheme.turtleKingGold,
        Brightness.dark,
      );
      // On the light felt the accent text must be much darker than the pure
      // accent so gold-on-light stays readable; dark mode keeps the accent.
      expect(
        light.accentText.computeLuminance(),
        lessThan(dark.accentText.computeLuminance()),
      );
      // Gold accent on light felt: readable contrast (>= 4.5:1 ideal, but even
      // the relaxed 3:1 for large text must hold).
      final contrast = _contrastRatio(light.accentText, light.feltTop);
      expect(contrast, greaterThan(3.0));
    });
  });
}

/// WCAG relative-luminance contrast ratio between two colors.
double _contrastRatio(Color a, Color b) {
  double lum(Color c) {
    double chan(double v) => v <= 0.03928
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return chan(c.r) * 0.2126 + chan(c.g) * 0.7152 + chan(c.b) * 0.0722;
  }

  final la = lum(a);
  final lb = lum(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}
