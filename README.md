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
- **Start Game** — hands the configured players to the game flow (see
  Milestone 04).

Cards, rounds, and actual gameplay arrive in later milestones.

## Milestone 03 — Standard Deck & Card System

This milestone adds the reusable card foundation for later gameplay:

- **Standard 52-card deck** — four suits (Hearts, Diamonds, Clubs, Spades) and
  thirteen ranks (Ace, 2–10, Jack, Queen, King), with exactly one card for
  every suit/rank combination.
- **Rank values** — Ace is lowest (1), King is highest (13); numeric cards use
  their face value, Jack = 11, Queen = 12.
- **Card model** — immutable `Card` with suit, rank, a numeric value derived
  from the rank, and a display name like "Ace of Hearts". Cards compare by
  value equality.
- **Deck operations** — `shuffle()`, `dealOne()`, `deal(count)`,
  `remainingCards`, and `reset()`. Dealing from an empty (or too-small) deck
  throws `EmptyDeckException`.
- **Out of scope** — no gameplay, player hands, dealing to players, YAMADA,
  cup mechanics, round escalation, elimination, or multiplayer. Those arrive
  in later milestones.

## Milestone 04 — Two-Card Hands & Pass-and-Play

This milestone turns the placeholder game screen into the pass-and-play flow:

- **GameState** — created when the game starts; shuffles a fresh 52-card deck
  and deals exactly two unique cards to every player, keyed by player id.
  Hands stay separate from the `Player` identity model.
- **Turn tracking** — players view their cards one at a time, in setup order;
  the state tracks whose turn it is and whether all players have viewed.
- **Game screen** — the current player sees their name and a "Reveal My
  Cards" button; their cards stay hidden until revealed. After viewing,
  "Pass to Next Player" moves to a neutral handoff screen so the phone can be
  handed over — the next player's cards only appear after they explicitly
  reveal them.
- **Completion** — after the final player views their cards, a simple screen
  confirms the initial dealing phase is complete, with a way back to setup.
- **Privacy** — a player never sees another player's cards; the previous
  player's cards are gone before the next player's turn begins.

YAMADA, rounds, penalties, elimination, and winner logic arrive in later
milestones.

## Milestone 05 — Center Pile

This milestone adds the model seam for shared gameplay, without gameplay
rules yet:

- **Center pile** — a face-up pile owned by `GameState`; a new game starts
  with an empty pile, and cards are added in deal order via
  `dealToCenter()`.
- **Single deck** — the pile is fed exclusively from the same shuffled deck
  the hands were dealt from. No second deck is created, and hands are never
  re-dealt.
- **Card accounting** — each `dealToCenter()` draws the top card of the
  remaining deck, so `remainingCards` decreases by one and a center card can
  never also be in a player's hand or elsewhere in the pile.
- **Out of scope** — YAMADA rules, rounds, penalties, elimination, and
  winner logic remain later milestones; the center pile is only their
  foundation.

## Milestone 06 — YAMADA Round Mechanics

This milestone implements the YAMADA round on top of the center pile:

- **Round start** — once every player has viewed their two cards, the round
  begins (`startYamadaRound`): the top card of the remaining deck becomes the
  first center card, and the first player takes the turn.
- **Turn actions** — players act in setup order. On a turn, a player either
  **draws** the top card of the deck onto the center pile
  (`drawToCenter`), or, when the current center card's value is **strictly
  between** their two hand cards, calls **YAMADA** (`callYamada`) to capture
  that card into their own captured pile. Every action advances the turn
  exactly once.
- **Center card** — the top of the center pile is public; players compare it
  with their own two cards using `Card.value` (Ace = 1 … King = 13). A
  capture removes only the top card, so the remaining pile keeps its deal
  order. Player hands never change.
- **Round completion** — the round is complete after every player has acted
  once. A single round never exhausts the deck (up to 10 players leaves at
  least 31 cards).
- **Invalid actions** — acting before the round starts, after it completes,
  out of turn, twice in a row, or calling YAMADA when the center card is not
  between the player's cards throws `YamadaRoundException` and leaves the
  state unchanged.
- **Determinism** — rounds are fully deterministic for a given `Random`
  seed, so gameplay can be replayed for testing or debugging.
- **Out of scope** — drinking/cup mechanics, penalties (a false YAMADA call
  in the drinking game costs a drink), elimination, winner/Turtle King
  determination, round escalation, and multiplayer remain later milestones.

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
  game_start_screen.dart  # Pass-and-play flow + YAMADA round screen
  card.dart               # Suit, Rank, and Card model
  deck.dart               # Standard 52-card deck (shuffle/deal/reset)
  game_state.dart         # Hands, turn state, center pile, YAMADA round
test/
  home_screen_test.dart        # Home screen branding + navigation
  player_test.dart             # Player model + color palette
  player_setup_screen_test.dart# Player setup behavior
  card_test.dart               # Suit/rank values, Card display + equality
  deck_test.dart               # Deck creation, shuffle, dealing, reset
  game_state_test.dart         # Hands, turn flow, center pile, YAMADA round
  game_start_screen_test.dart  # Pass-and-play + YAMADA round flow + privacy
```
