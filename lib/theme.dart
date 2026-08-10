import 'package:flutter/material.dart';

/// The Turtle King brand palette, shared across screens.
///
/// Navy/gold is the product identity (splash, launcher, logo); the deep
/// greens are the card-table felt used by the game screen. These are the
/// defaults — the user-chosen [AppColorTheme] refines the accents and felt
/// while keeping the identity coherent.
abstract final class TurtleKingColors {
  /// Brand navy (splash background, card-back emblem disc).
  static const navy = Color(0xFF0B263C);

  /// Brand gold (crowns, rims, highlights).
  static const gold = Color(0xFFD4AF37);

  /// Darker gold for outlines on light backgrounds.
  static const goldDark = Color(0xFFB8860B);

  /// The felt green at the center of the table light (dark mode).
  static const felt = Color(0xFF1C5C43);

  /// The deep green at the table edges (dark mode).
  static const feltDark = Color(0xFF08211A);

  /// The cream surface of a card face.
  static const cardCream = Color(0xFFFDFBF4);

  /// The red used for hearts/diamonds (semantic suit color, never themed).
  static const suitRed = Color(0xFFC62828);

  /// The near-black used for spades/clubs (semantic suit color).
  static const suitBlack = Color(0xFF212121);
}

/// The user-selectable accent/color themes.
///
/// Each theme intentionally defines its own accent, felt palette (light and
/// dark), and on-felt text colors so both theme modes stay readable and keep
/// the card-table identity. Suit colors are deliberately NOT part of the
/// accent themes — they stay conventional (see [TurtleKingColors.suitRed]).
enum AppColorTheme {
  turtleKingGold(
    'Turtle King Gold',
    accent: Color(0xFFD4AF37),
    onAccent: Color(0xFF33290A),
    accentSoft: Color(0xFFF0D987),
    feltLightTop: Color(0xFF4C9A6E),
    feltLightMid: Color(0xFF2F7D52),
    feltLightBottom: Color(0xFF1C4A33),
    feltDarkTop: Color(0xFF1C5C43),
    feltDarkMid: Color(0xFF11402F),
    feltDarkBottom: Color(0xFF08211A),
    textLight: Color(0xFF0B2118),
    textLightSecondary: Color(0xFF1F3B2E),
    textDark: Color(0xFFFFFFFF),
    textDarkSecondary: Color(0xFFD5E5DC),
  ),
  emerald(
    'Emerald',
    accent: Color(0xFF00A86B),
    onAccent: Color(0xFF00281A),
    accentSoft: Color(0xFF7ED9B5),
    feltLightTop: Color(0xFF3FA06B),
    feltLightMid: Color(0xFF2A7A50),
    feltLightBottom: Color(0xFF17442E),
    feltDarkTop: Color(0xFF17694A),
    feltDarkMid: Color(0xFF0F4733),
    feltDarkBottom: Color(0xFF062B1E),
    textLight: Color(0xFF0A2014),
    textLightSecondary: Color(0xFF1E3A2A),
    textDark: Color(0xFFFFFFFF),
    textDarkSecondary: Color(0xFFCFE8DC),
  ),
  royalPurple(
    'Royal Purple',
    accent: Color(0xFF8E5BD9),
    onAccent: Color(0xFF1C0B33),
    accentSoft: Color(0xFFC9A8F2),
    feltLightTop: Color(0xFF8A6BB8),
    feltLightMid: Color(0xFF6B4FA0),
    feltLightBottom: Color(0xFF3E2A63),
    feltDarkTop: Color(0xFF4A3580),
    feltDarkMid: Color(0xFF33245C),
    feltDarkBottom: Color(0xFF1A1030),
    textLight: Color(0xFF160B26),
    textLightSecondary: Color(0xFF32204D),
    textDark: Color(0xFFFFFFFF),
    textDarkSecondary: Color(0xFFE0D6F0),
  ),
  oceanBlue(
    'Ocean Blue',
    accent: Color(0xFF1E88E5),
    onAccent: Color(0xFF06213B),
    accentSoft: Color(0xFF90CAF9),
    feltLightTop: Color(0xFF3E8FB8),
    feltLightMid: Color(0xFF2C6E94),
    feltLightBottom: Color(0xFF174057),
    feltDarkTop: Color(0xFF1E5A80),
    feltDarkMid: Color(0xFF123F5C),
    feltDarkBottom: Color(0xFF082438),
    textLight: Color(0xFF071A26),
    textLightSecondary: Color(0xFF1C3A4D),
    textDark: Color(0xFFFFFFFF),
    textDarkSecondary: Color(0xFFCFE3F0),
  ),
  crimson(
    'Crimson',
    accent: Color(0xFFA93226),
    onAccent: Color(0xFFFFFFFF),
    accentSoft: Color(0xFFE57373),
    feltLightTop: Color(0xFFB0504C),
    feltLightMid: Color(0xFF8C3333),
    feltLightBottom: Color(0xFF4A1A1A),
    feltDarkTop: Color(0xFF6E2328),
    feltDarkMid: Color(0xFF4A1619),
    feltDarkBottom: Color(0xFF1F090B),
    textLight: Color(0xFF200A0A),
    textLightSecondary: Color(0xFF3D1B1B),
    textDark: Color(0xFFFFFFFF),
    textDarkSecondary: Color(0xFFF0D9D9),
  );

  const AppColorTheme(
    this.label, {
    required this.accent,
    required this.onAccent,
    required this.accentSoft,
    required this.feltLightTop,
    required this.feltLightMid,
    required this.feltLightBottom,
    required this.feltDarkTop,
    required this.feltDarkMid,
    required this.feltDarkBottom,
    required this.textLight,
    required this.textLightSecondary,
    required this.textDark,
    required this.textDarkSecondary,
  });

  /// Human-readable name shown in settings.
  final String label;

  /// The theme's primary accent (buttons, badges, highlights).
  final Color accent;

  /// Text/icon color that reads on [accent].
  final Color onAccent;

  /// A lighter tint of [accent] for gradients and highlights.
  final Color accentSoft;

  // Felt palette for the light theme mode.
  final Color feltLightTop;
  final Color feltLightMid;
  final Color feltLightBottom;

  // Felt palette for the dark theme mode.
  final Color feltDarkTop;
  final Color feltDarkMid;
  final Color feltDarkBottom;

  // On-felt text colors for each mode.
  final Color textLight;
  final Color textLightSecondary;
  final Color textDark;
  final Color textDarkSecondary;
}

/// The user-selectable card designs.
///
/// Presentation only: the underlying [Card] model, ranks, suits, deck, and
/// gameplay are identical for every design.
enum CardDesign {
  classicPoker('Classic Poker'),
  turtleKing('Turtle King'),
  noir('Noir');

  const CardDesign(this.label);

  /// Human-readable name shown in settings.
  final String label;
}

/// The visual style of the card table (felt, accents, on-felt text).
///
/// Carried on [ThemeData.extensions] so any screen reads one coherent style
/// for the current color theme + brightness instead of hardcoding colors.
class GameTableStyle extends ThemeExtension<GameTableStyle> {
  const GameTableStyle({
    required this.feltTop,
    required this.feltMid,
    required this.feltBottom,
    required this.textPrimary,
    required this.textSecondary,
    required this.accent,
    required this.onAccent,
    required this.accentSoft,
    required this.accentText,
    required this.accentTextSoft,
    required this.chipBg,
    required this.chipBorder,
    required this.danger,
    required this.onDanger,
  });

  /// The radial "table light" center.
  final Color feltTop;

  /// The mid-radius felt color.
  final Color feltMid;

  /// The felt color at the table edges.
  final Color feltBottom;

  /// Primary on-felt text.
  final Color textPrimary;

  /// Secondary on-felt text (captions, hints).
  final Color textSecondary;

  /// The accent used for primary actions and highlights.
  final Color accent;

  /// Text/icon that reads on [accent].
  final Color onAccent;

  /// A lighter tint of [accent] for gradients.
  final Color accentSoft;

  /// The accent variant used for text ON the felt: the bright accent in dark
  /// mode, a darkened, readable shade in light mode.
  final Color accentText;

  /// A lighter accent variant for emphasis text on the felt (dark mode uses
  /// [accentSoft]; light mode darkens it for contrast).
  final Color accentTextSoft;

  /// Translucent chip/badge background on the felt.
  final Color chipBg;

  /// The chip/badge outline (accent-tinted).
  final Color chipBorder;

  /// The semantic danger/elimination color (YAMADA, eliminated).
  final Color danger;

  /// Text that reads on [danger].
  final Color onDanger;

  /// The style for a [colorTheme] + [brightness] pair.
  factory GameTableStyle.forTheme(
    AppColorTheme colorTheme,
    Brightness brightness,
  ) {
    final dark = brightness == Brightness.dark;
    return GameTableStyle(
      feltTop: dark ? colorTheme.feltDarkTop : colorTheme.feltLightTop,
      feltMid: dark ? colorTheme.feltDarkMid : colorTheme.feltLightMid,
      feltBottom: dark ? colorTheme.feltDarkBottom : colorTheme.feltLightBottom,
      textPrimary: dark ? colorTheme.textDark : colorTheme.textLight,
      textSecondary: dark
          ? colorTheme.textDarkSecondary
          : colorTheme.textLightSecondary,
      accent: colorTheme.accent,
      onAccent: colorTheme.onAccent,
      accentSoft: colorTheme.accentSoft,
      accentText: dark
          ? colorTheme.accent
          : Color.lerp(colorTheme.accent, Colors.black, 0.8)!,
      accentTextSoft: dark
          ? colorTheme.accentSoft
          : Color.lerp(colorTheme.accentSoft, Colors.black, 0.8)!,
      chipBg: dark ? const Color(0x14FFFFFF) : const Color(0x12000000),
      chipBorder: colorTheme.accent,
      danger: TurtleKingColors.suitRed,
      onDanger: Colors.white,
    );
  }

  /// Reads the active table style, falling back to the Turtle King Gold
  /// dark felt when the theme carries no extension (plain test themes).
  static GameTableStyle of(BuildContext context) =>
      Theme.of(context).extension<GameTableStyle>() ??
      GameTableStyle.forTheme(AppColorTheme.turtleKingGold, Brightness.dark);

  @override
  GameTableStyle copyWith({
    Color? feltTop,
    Color? feltMid,
    Color? feltBottom,
    Color? textPrimary,
    Color? textSecondary,
    Color? accent,
    Color? onAccent,
    Color? accentSoft,
    Color? accentText,
    Color? accentTextSoft,
    Color? chipBg,
    Color? chipBorder,
    Color? danger,
    Color? onDanger,
  }) {
    return GameTableStyle(
      feltTop: feltTop ?? this.feltTop,
      feltMid: feltMid ?? this.feltMid,
      feltBottom: feltBottom ?? this.feltBottom,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      accentSoft: accentSoft ?? this.accentSoft,
      accentText: accentText ?? this.accentText,
      accentTextSoft: accentTextSoft ?? this.accentTextSoft,
      chipBg: chipBg ?? this.chipBg,
      chipBorder: chipBorder ?? this.chipBorder,
      danger: danger ?? this.danger,
      onDanger: onDanger ?? this.onDanger,
    );
  }

  @override
  GameTableStyle lerp(GameTableStyle? other, double t) {
    if (other == null) return this;
    return GameTableStyle(
      feltTop: Color.lerp(feltTop, other.feltTop, t)!,
      feltMid: Color.lerp(feltMid, other.feltMid, t)!,
      feltBottom: Color.lerp(feltBottom, other.feltBottom, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      accentText: Color.lerp(accentText, other.accentText, t)!,
      accentTextSoft: Color.lerp(accentTextSoft, other.accentTextSoft, t)!,
      chipBg: Color.lerp(chipBg, other.chipBg, t)!,
      chipBorder: Color.lerp(chipBorder, other.chipBorder, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      onDanger: Color.lerp(onDanger, other.onDanger, t)!,
    );
  }
}

/// The visual style of playing cards (face + back) for a [CardDesign].
///
/// Carried on [ThemeData.extensions]. The card back's fields carry no rank or
/// suit — they are purely decorative surface colors, so a hidden card can
/// never expose its identity through its design.
class CardStyle extends ThemeExtension<CardStyle> {
  const CardStyle({
    required this.design,
    required this.faceTop,
    required this.faceBottom,
    required this.faceBorder,
    required this.inkDark,
    required this.inkRed,
    required this.watermark,
    required this.highlight,
    required this.backSurface,
    required this.backBorder,
    required this.backRing,
    required this.backDisc,
  });

  /// Which design these colors implement.
  final CardDesign design;

  /// Face gradient top/bottom.
  final Color faceTop;
  final Color faceBottom;

  /// Face border color.
  final Color faceBorder;

  /// Ink for clubs/spades (the "dark" suit) on this face.
  final Color inkDark;

  /// Ink for hearts/diamonds (always a red) on this face.
  final Color inkRed;

  /// The soft circle behind the center pip.
  final Color watermark;

  /// The accent used to highlight a card (e.g. the smallest hand).
  final Color highlight;

  /// The card back surface color.
  final Color backSurface;

  /// The card back outer border.
  final Color backBorder;

  /// The card back inner ring (accent-tinted).
  final Color backRing;

  /// The emblem disc color on the card back.
  final Color backDisc;

  /// The style for [design], tinted with [accent].
  factory CardStyle.forDesign(
    CardDesign design, {
    Color accent = TurtleKingColors.gold,
  }) {
    return switch (design) {
      CardDesign.classicPoker => CardStyle(
        design: design,
        faceTop: const Color(0xFFFFFFFF),
        faceBottom: const Color(0xFFF6F1E3),
        faceBorder: const Color(0xFFC9C2AE),
        inkDark: TurtleKingColors.suitBlack,
        inkRed: TurtleKingColors.suitRed,
        watermark: const Color(0xFFEFE9D8).withValues(alpha: 0.6),
        highlight: accent,
        backSurface: const Color(0xFFF6F1E3),
        backBorder: const Color(0xFFC9C2AE),
        backRing: accent,
        backDisc: TurtleKingColors.navy,
      ),
      CardDesign.turtleKing => CardStyle(
        design: design,
        faceTop: const Color(0xFF1D4E77),
        faceBottom: const Color(0xFF0B2A47),
        faceBorder: accent,
        inkDark: const Color(0xFFF2E8C9),
        inkRed: const Color(0xFFE57373),
        watermark: accent.withValues(alpha: 0.20),
        highlight: accent,
        backSurface: const Color(0xFFF6F1E3),
        backBorder: const Color(0xFFC9C2AE),
        backRing: accent,
        backDisc: TurtleKingColors.navy,
      ),
      CardDesign.noir => CardStyle(
        design: design,
        faceTop: const Color(0xFF33333D),
        faceBottom: const Color(0xFF1D1D24),
        faceBorder: const Color(0xFF8A8A99),
        inkDark: const Color(0xFFEDEDF2),
        inkRed: const Color(0xFFE57373),
        watermark: const Color(0xFFFFFFFF).withValues(alpha: 0.06),
        highlight: accent,
        backSurface: const Color(0xFF1D1D24),
        backBorder: const Color(0xFF8A8A99),
        backRing: accent,
        backDisc: const Color(0xFF101014),
      ),
    };
  }

  /// Reads the active card style, falling back to Classic Poker.
  static CardStyle of(BuildContext context) =>
      Theme.of(context).extension<CardStyle>() ??
      CardStyle.forDesign(CardDesign.classicPoker);

  @override
  CardStyle copyWith({
    CardDesign? design,
    Color? faceTop,
    Color? faceBottom,
    Color? faceBorder,
    Color? inkDark,
    Color? inkRed,
    Color? watermark,
    Color? highlight,
    Color? backSurface,
    Color? backBorder,
    Color? backRing,
    Color? backDisc,
  }) {
    return CardStyle(
      design: design ?? this.design,
      faceTop: faceTop ?? this.faceTop,
      faceBottom: faceBottom ?? this.faceBottom,
      faceBorder: faceBorder ?? this.faceBorder,
      inkDark: inkDark ?? this.inkDark,
      inkRed: inkRed ?? this.inkRed,
      watermark: watermark ?? this.watermark,
      highlight: highlight ?? this.highlight,
      backSurface: backSurface ?? this.backSurface,
      backBorder: backBorder ?? this.backBorder,
      backRing: backRing ?? this.backRing,
      backDisc: backDisc ?? this.backDisc,
    );
  }

  @override
  CardStyle lerp(CardStyle? other, double t) {
    if (other == null) return this;
    return CardStyle(
      design: t < 0.5 ? design : other.design,
      faceTop: Color.lerp(faceTop, other.faceTop, t)!,
      faceBottom: Color.lerp(faceBottom, other.faceBottom, t)!,
      faceBorder: Color.lerp(faceBorder, other.faceBorder, t)!,
      inkDark: Color.lerp(inkDark, other.inkDark, t)!,
      inkRed: Color.lerp(inkRed, other.inkRed, t)!,
      watermark: Color.lerp(watermark, other.watermark, t)!,
      highlight: Color.lerp(highlight, other.highlight, t)!,
      backSurface: Color.lerp(backSurface, other.backSurface, t)!,
      backBorder: Color.lerp(backBorder, other.backBorder, t)!,
      backRing: Color.lerp(backRing, other.backRing, t)!,
      backDisc: Color.lerp(backDisc, other.backDisc, t)!,
    );
  }
}

/// Builds the Turtle King theme for a [colorTheme] and [brightness].
///
/// The user-selectable [AppColorTheme] seeds the Material color scheme and
/// drives the card-table [GameTableStyle]; the selected [CardDesign] is
/// carried via [CardStyle]. Light and dark are intentional palettes, not an
/// inversion.
ThemeData buildTheme({
  AppColorTheme colorTheme = AppColorTheme.turtleKingGold,
  Brightness brightness = Brightness.light,
  CardDesign cardDesign = CardDesign.classicPoker,
}) {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: colorTheme.accent,
    brightness: brightness,
  );
  return ThemeData(
    colorScheme: colorScheme,
    scaffoldBackgroundColor: colorScheme.surface,
    extensions: [
      GameTableStyle.forTheme(colorTheme, brightness),
      CardStyle.forDesign(cardDesign, accent: colorTheme.accent),
    ],
  );
}
