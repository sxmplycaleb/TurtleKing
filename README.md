# Turtle King

Turtle King is a pass-and-play card game for friends, built with Flutter for
Android and iOS.


## Milestone 01 — Project Foundation

This milestone establishes the project skeleton: a minimal Flutter app that
runs on Android and iOS with a branded home screen. Gameplay (cards, rounds,
YAMADA mechanics, multiplayer, etc.) is intentionally **not** implemented yet.

## Milestone 02 — Player Setup

This milestone lets players configure a game before it begins:

- **Player model** — each player has a unique id, a name, and a color.
- **Player setup screen** — reached from the home screen's New Game button.
  Add players by name, remove them, and see the live player count.
- **Validation** — empty and duplicate names are rejected with inline
  feedback; names are trimmed on entry.
- **Limits** — 2 to 10 players. Start Game stays disabled until at least 2
  players are added, and adding stops at 10.
- **Auto colors** — each player is automatically assigned a distinct color
  from a fixed 10-color palette; removing a player frees their color.
- **Start Game** — hands the configured players to a placeholder game screen
  ("Game ready", player count, and names) with a temporary way back to setup.

Cards, rounds, and actual gameplay arrive in later milestones.

## Prerequisites

- Flutter SDK (stable channel) — see https://docs.flutter.dev/get-started/install
- For Android: Android SDK (via Android Studio)
- For iOS: Xcode (macOS only)

## Setup

```sh
flutter pub get
```

## Run

```sh
# Run on a connected device or emulator
flutter run

# Pick a specific device
flutter devices
flutter run -d <device-id>
```

## Tests

```sh
flutter test
```

## Static analysis

```sh
flutter analyze
```

## Build

```sh
# Android
flutter build apk --debug
flutter build apk --release

# iOS (requires macOS with Xcode)
flutter build ios
```

## Project structure

```
lib/
  main.dart               # App entry point
  theme.dart              # Shared visual theme
  home_screen.dart        # Home screen (branding + New Game button)
  turtle_art.dart         # Turtle mascot illustration (CustomPaint)
  player.dart             # Player model (id, name, color)
  player_colors.dart      # Auto-assigned player color palette
  player_setup_screen.dart# Player setup (add/remove/limits/start)
  game_start_screen.dart  # Placeholder game-start screen
test/
  home_screen_test.dart        # Home screen branding + navigation
  player_test.dart             # Player model + color palette
  player_setup_screen_test.dart# Player setup behavior
```
