# Turtle King

Turtle King is a pass-and-play card game for friends, built with Flutter for
Android and iOS.

## Gameplay — Authoritative Rules (current implementation)

The game is implemented directly from the authoritative Turtle King rules:

> This is a game that cannot be stopped, to see who can hold out until the
> end.

- **Two cards, one visible** — each player is dealt two cards but may only
  look at **one** of them. The second card stays hidden (even from its
  owner) until the group reveal. The pass-and-play flow hands the phone
  around; each player reveals their one visible card privately, then passes
  through a neutral handoff with zero cards on screen.
- **The pouring cup** — after everyone has viewed, a water cup is placed and
  water begins to be poured. In turn, each active player holds out or shouts
  **YAMADA**.
- **YAMADA = admit defeat** — calling YAMADA means the player admits defeat:
  they drink the water currently in the cup, are dealt two new cards (and
  look at one of them), and continue the game. The round is not revealed.
- **Everyone holds out → reveal** — if all players hold out without
  shouting, all hands are revealed together and the player with the
  **smallest** cards drinks a **full cup**, plus an **extra cup** because
  they held out with the smallest cards. Ties share the penalty.
- **Cup sizes** — the cup starts normal; because no player admitted defeat
  in round one, round two switches to a **large** cup, and round three to an
  **extra-large** cup (a round with YAMADA keeps the current size).
- **Six drinks = elimination** — each drink (YAMADA, full-cup penalty, extra
  cup) counts as one drinking event. A player who accumulates **six**
  drinking events is directly eliminated on the spot; eliminated players
  receive no hands, take no turns, and cannot act.
- **Turtle King** — the last player remaining on the field wins the crown
  and becomes the Turtle King. If every remaining player is eliminated by
  the same event, no Turtle King is declared.
- **Deterministic** — `GameState` accepts an injected `Random`; with the
  same players, seed, and actions the outcome is identical.

Card values are Ace = 1, number cards = their number, Jack = 11, Queen = 12,
King = 13, and "smallest" means the lowest total of a player's two cards.

### Assumptions (the rules are silent)

The authoritative rules leave a few details open; the game implements them
as clearly-labeled project rules (also listed on the How to Play screen):

- "Smallest" = lowest total hand value; tied players all drink.
- A YAMADA drink, the full-cup penalty, and the extra cup each count as one
  drinking event.
- The cup grows one step after every round with no YAMADA and stays the
  same after a round with YAMADA.
- When the deck runs low it is reset to a full 52-card deck (shuffled) so
  the game can continue.
- Each new YAMADA hand shows the player the first of their two new cards.
- A round ends once every active player has held out in a row; if YAMADA
  was called during the round, no reveal happens and the round simply
  completes with the YAMADA drinks recorded.

### Superseded provisional mechanics

Milestones 05–09 below document *provisional* mechanics that were designed
before the authoritative rules were adopted and have since been **removed**
from the implementation: a face-up center pile, draw-to-center turns,
strictly-between YAMADA captures, wrong-call penalties, cup-capacity/penalty
counters, fewest-captures Turtle King determination, and a 2-full-cup
elimination threshold. They remain in this README only as historical
milestone records and are marked as superseded.

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

> ⚠️ **Superseded** — the center pile described below no longer exists in
> the implementation. The authoritative rules have no center pile; rounds
> revolve around the pouring cup instead. Kept as a historical record.

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

> ⚠️ **Superseded** — the strictly-between capture mechanics described below
> were replaced by the authoritative rules: YAMADA now means *admitting
> defeat* (drink the cup, get new cards, continue). Kept as a historical
> record.

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

## Milestone 07 — Cup/Penalty Mechanics & Captured-Pile Scoring

> ⚠️ **Superseded** — the penalty-cup counters and captured-pile scoring
> described below were removed when the authoritative rules were adopted
> (the current cup is a pouring cup with the smallest-hand penalty, and
> scoring is by drinking events). Kept as a historical record.

This milestone layers penalties and scoring onto the YAMADA round:

- **Wrong YAMADA calls** — calling YAMADA when the center card's value is not
  strictly between your two cards is now a legal action rather than an
  exception: nothing is captured, the center card stays in place, one penalty
  point is added to your cup, and the turn advances. `callYamada` returns a
  `YamadaResult` describing whether the call captured or was penalized.
- **Cup model** — each player's cup holds up to `cupCapacity` penalty points
  (default 3, configurable at game creation). When a penalty would overflow
  the cup, the cup empties and the full-cup count (`cupDrinksOf`) increases;
  the lifetime penalty count (`penaltyCountOf`) never decreases. The cup is
  pure-Dart state on `GameState`.
- **Scoring** — `captureCountOf(player)` and `totalCapturedCards` expose the
  captured-pile counts. Once the round completes, `roundResult` returns a
  deterministic `RoundResult` with per-player scores and the tied highest and
  lowest scorers.
- **No winner rule** — the real game's Turtle King determination is not
  specified, so the result exposes scores and explicit ties
  (`highestScorers`/`lowestScorers`) without declaring a winner or applying a
  hidden tie-breaker.
- **UI** — the YAMADA button is always available; the screen hints whether
  the call will capture or cost a penalty, a wrong call shows a penalty
  screen with the caller's cup state before the neutral handoff, and the
  completion screen lists each player's captures and penalties.
- **Assumptions** — the default cup capacity and the "wrong call = 1 penalty
  point" rule are assumptions (the repository specifies no authoritative
  YAMADA rules); they are isolated behind the cup API so they can be adjusted
  without touching the round engine.
- **Out of scope** — multiple rounds, round escalation, elimination, winner/
  Turtle King declaration, drinking instructions, and multiplayer remain
  later milestones.

## Milestone 08 — Multi-Round Game & Turtle King Determination

> ⚠️ **Superseded** — `maxRounds`, the never-reshuffle rule, and the
> fewest-total-captures Turtle King rule described below were replaced by
> the authoritative rules: the game continues until one player remains, the
> deck is reset when it runs low, and the Turtle King is the last player
> standing. Kept as a historical record.

This milestone turns the single-round M07 game into a complete multi-round
pass-and-play game:

- **Lifecycle** — a game spans up to `maxRounds` rounds (default 3,
  configurable at game creation). Each round repeats the flow: players view
  their fresh two-card hands privately, play the YAMADA round, and the round
  result is recorded. `startNextRound()` prepares the next round; the game
  completes after `maxRounds` rounds or when the deck cannot guarantee
  another round, whichever comes first (`gameComplete`, `finalResult`).
- **Round reset** — a new round resets per-round state only: center pile,
  current-round captures, viewing/turn state, and hands (two fresh cards per
  player). The single deck is never reshuffled, so a physical card is never
  dealt twice anywhere in the game; a new round starts only while the deck
  can guarantee it completes (two cards per player plus the initial center
  card plus one potential draw per player).
- **Persistent state** — cup penalties are lifetime: `penaltyCountOf`,
  `cupFillOf`, and `cupDrinksOf` carry into every new round and are never
  reset. Total captures accumulate via `totalCapturesOf(player)` and
  `totalCapturesAcrossGame`; `roundResults` keeps every completed round's
  scoring result in order.
- **Scoring** — current-round captures stay in `captureCountOf` /
  `roundResult`; game totals live in `totalCapturesOf` / `finalResult`.
- **Turtle King (assumed rule)** — the repository specifies no official
  winner rule, so the Turtle King is assumed to be the player(s) with the
  **fewest total captures** across all rounds. Ties share the title
  (`finalResult.turtleKings`); no hidden tie-breaker is applied. The rule is
  isolated in `GameState`'s final-result calculation so it can be replaced
  without touching the round engine. This is an assumption, not an official
  rule.
- **UI** — a round label appears once a round starts, the round-completion
  screen offers "Start Next Round", and the final screen crowns the Turtle
  King with each player's total captures and penalties. The pass-and-play
  privacy contract is unchanged: every new round's hands stay hidden until
  the phone-holder explicitly reveals them, and handoffs show zero cards.
- **Assumptions** — `maxRounds` (3), the deck-never-reshuffles rule, the
  early-termination guard (deck must guarantee a full round), and the
  fewest-captures Turtle King rule are all assumptions: the repository
  specifies no authoritative multi-round or winner rules.
- **Out of scope** — drinking instructions, persistence, and multiplayer
  remain later milestones.

## Milestone 09 — Elimination & End-of-Game Escalation

> ⚠️ **Superseded** — elimination is now governed by the authoritative rule:
> **six drinking events** eliminate a player on the spot (the cup-count
> trigger and 2-full-cup default described below were removed). Kept as a
> historical record.

This milestone adds elimination on top of the multi-round game:

- **Elimination model** — every player starts active. `isEliminated(player)`,
  `activePlayers`, `eliminatedPlayers`, `activePlayerCount`, and
  `eliminationHistory` expose the state; eliminated players keep their
  player object and full history (captures, penalties, cup drinks, scores).
- **Trigger (assumed rule)** — the repository specifies no authoritative
  elimination rule, so the assumed trigger is the lifetime cup count:
  a player whose `cupDrinksOf(player)` reaches the configurable
  `eliminationThreshold` (default **2** full cups) is eliminated. The
  threshold is validated at construction (`>= 1`, `ArgumentError`
  otherwise). Like the Turtle King rule, this is an assumption, not an
  official rule.
- **Timing** — eliminations are evaluated only *after* a completed round
  action: the capture/penalty resolves, the turn advances, then any player
  who reached the threshold is eliminated. An elimination never interrupts
  an action halfway through, and validation stays atomic — a rejected
  action mutates nothing.
- **Eliminated players do not participate** — they receive no new hands
  (`hasHand` is false), never become the current viewer or round player,
  and cannot act (`callYamada` / `drawToCenter` throw
  `YamadaRoundException`). Turn order is built from `activePlayers`, so
  `roundCurrentPlayer` is never eliminated and rounds complete based on the
  active players.
- **Multi-round integration** — `startNextRound()` deals fresh two-card
  hands to active players only, from the same never-reshuffled deck; card
  uniqueness and `remainingCards` accounting are preserved.
- **Game termination** — the game ends when the configured `maxRounds` is
  reached, the deck cannot guarantee another round, or **fewer than two
  active players remain**, whichever comes first (checked in that order).
  When only one player is left the game ends immediately — even mid-round
  — so the remaining player never plays a meaningless turn.
- **Elimination history** — each elimination is recorded as an immutable
  `EliminationRecord` (player, 1-based round, `EliminationReason`), kept in
  `eliminationHistory` in elimination order.
- **Final result** — `GameResult` now also exposes `finalists` (players
  still active at the end), `eliminated`, and `eliminations`. The assumed
  fewest-total-captures Turtle King rule is unchanged and still counts
  every player's lifetime captures — including eliminated players', whose
  history must not be deleted — so an eliminated player can share the title
  on a tie. Ties remain explicit; no hidden tie-breaker.
- **UI** — the penalty screen announces an elimination ("X has been
  eliminated!"), round completion lists who was eliminated that round, and
  the final screen shows Game complete, Turtle King(s), finalists,
  eliminated players, and lifetime capture/penalty counts. No private card
  identities ever appear on handoff, penalty, or result screens.
- **Assumptions** — the cup-based trigger and default threshold of 2, the
  fewer-than-two-active-players end condition, and elimination eligibility
  under the Turtle King rule are all assumptions; the repository specifies
  no official elimination rules.
- **Out of scope** — drinking instructions, persistence, and multiplayer
  remain later milestones.

## Milestone 10 — How to Play & Rules Documentation

This milestone adds a dedicated **How to Play** screen that documents the
rules implemented in the game:

- **Screen** — `lib/how_to_play_screen.dart` renders the full rules as a
  scrollable, mobile-friendly page with a clear title and accessible back
  navigation. It is pure documentation: a stateless widget that takes no
  `GameState`, never mutates gameplay state, and contains no private card
  information.
- **Navigation** — a "How to Play" action on the home screen opens the rules
  from the app shell (and the game screen's app bar reuses the same screen
  in-game). Back returns where you came from; the game flow is unchanged.
- **Topics covered** — The Goal; Setting Up (2–10 players, single phone);
  Your Two Cards (two cards dealt, only one visible); Pass the Phone
  (neutral handoff, explicit Continue); The Pouring Cup; YAMADA (admit
  defeat — drink the cup, new cards, continue); Hold Out; The Reveal
  (simultaneous reveal, smallest hand drinks a full cup plus an extra cup,
  with Ace=1 … King=13 values and a worked example); Cup Sizes (normal →
  large → extra-large); Drinking Counts (six drinks = elimination);
  Multiple Rounds (fresh hands, cup size carries over, deck reset when
  low); Elimination (six drinking events, on the spot); Turtle King (last
  player remaining); and a highlighted **Current Project Rules** section.
- **Assumptions** — the screen explicitly labels the rules the repository
  does not specify authoritatively as *current project rules / project
  assumptions*: smallest = lowest total hand value with tied players
  sharing the penalty; each drink counts as one drinking event; the cup
  grows one step after rounds with no YAMADA; the deck resets when low; and
  each new YAMADA hand shows the first of two new cards. None are presented
  as official Turtle King rules.
- **Out of scope** — no gameplay mechanics were added or changed; drinking
  instructions, persistence, and multiplayer remain later milestones.

## Milestone 11 — In-Game Rules Reference & Round History

This milestone makes the rules available *during* a game and adds a
read-only round history to the final result screen, without touching any
gameplay mechanics:

- **In-game rules reference** — the game screen's app bar gains a "How to
  Play" action that pushes the *same* stateless `HowToPlayScreen` used from
  the home screen. Opening it creates no `GameState`, resets nothing, and
  returning lands on the exact same stage with identical state (the neutral
  handoff stays neutral and the next player's cards stay hidden).
- **Round history** — the final game screen gains a "Round History" button
  that opens `lib/round_history_screen.dart`, a pure presentation layer over
  data `GameState` already records. There is no second history store.
- **Data sources** — rounds come from `GameState.roundResults` in
  chronological order; per-round drinking events and YAMADA calls from
  `RoundResult` (`drinks`, `calledYamada`, `smallestHands`, `cupSize`);
  eliminations from `GameState.eliminationHistory` matched by round number.
  Recorded results are fixed snapshots, so later rounds can never
  retroactively rewrite earlier history.
- **History content** — each completed round shows its number and cup size,
  every player's drinks for that round (zero-drink players and YAMADA calls
  included), the smallest-hand penalty, and anyone eliminated during it. An
  empty history shows a defensive "No completed rounds yet." message.
- **Privacy** — history and rules show only player names and counts. No
  card widget, card identity, or hand information ever appears; the
  pass-and-play privacy contract is unchanged.
- **Out of scope** — no gameplay rules, scoring, elimination, cup, deck, or
  round-progression behavior changed; persistence and multiplayer remain
  later milestones.

## Milestone 12 — Branding: Launch Screen, Launcher Icon & Homepage Logo

This milestone turns the Turtle King generated artwork into a coherent
application identity — one visual identity, three presentations — without
touching any gameplay:

- **Full artwork** (`assets/branding/turtle_king_splash.png`, 1024×1536) —
  the emblem circle (crowned turtle, sunglasses, ermine cape, fanned cards)
  plus the TURTLE/KING banner. It powers the **app launch experience**: a
  Flutter-side `SplashScreen` (`lib/splash_screen.dart`) shows it centered
  on the navy brand color `#0B263C` for ~1.2 s, then fades into the home
  screen. The native launch screens are branded too: Android
  `launch_background.xml` draws the artwork on navy (with an Android 12+
  system-splash override in `values-v31/styles.xml`), and the iOS
  `LaunchScreen.storyboard` aspect-fits the same artwork on navy.
- **Simplified emblem** (`assets/branding/turtle_king_emblem.png`) — the
  emblem circle only (no banner), centered on a transparent square. It is
  the **home screen brand mark** (sized responsively and paired with the
  "Turtle King" title) and the base for the **launcher icon**: the emblem is
  composited at 88% on the navy field (`assets/branding/turtle_king_icon.png`),
  then exported to every Android mipmap density (legacy `ic_launcher.png`
  plus adaptive `ic_launcher_foreground.png`/`ic_launcher_background`) and
  every iOS AppIcon slot. The default Flutter launcher icon is fully
  replaced.
- **Derivation pipeline** — `tool/generate_branding.ps1` regenerates every
  derivative from the source artwork, including the measured crop bounds
  (the emblem ring spans x 11..1010, y 100..890; the TURTLE/KING shield
  starts at y ≈ 895, so the emblem crop stops at y 890) and the sampled
  navy `#0B263C`. The emblem content is scaled to 84% of its canvas so the
  ring and fanned cards keep safe-area breathing room; the adaptive
  foreground then draws the padded emblem at 70% of the 108 dp canvas, so
  the artwork lands at ≈59% — inside the 66 dp Android safe zone.
- **Accessibility & responsiveness** — the home emblem scales with screen
  width (`screenWidth * 0.4`, clamped 140–200 px) and exposes a semantic
  label (`"Turtle King logo"`); the splash artwork uses `BoxFit.contain` so
  it is never stretched or distorted on any screen size.
- **No gameplay impact** — the splash is purely presentational: no
  `GameState` is created or mutated, no game starts during launch, and the
  New Game / How to Play navigation is unchanged.
- **Out of scope** — gameplay rules, privacy, and `GameState` are untouched;
  persistence and multiplayer remain later milestones.

## Milestone 13 — Card Game UI & Visual Experience

This milestone turns the functional game screen into a polished card-table
experience. It is presentation-only: the authoritative rules, `GameState`,
privacy guarantees, and navigation are unchanged.

**Reusable card widgets** (`lib/card_widgets.dart`):

- `PlayingCard` — a realistic face-up poker card: cream surface, rounded
  corners, subtle shadow, standard rank/suit corner indices (top-left and
  rotated bottom-right), a large center suit pip, and red (`#C62828`) for
  hearts/diamonds vs near-black (`#212121`) for spades/clubs. Card sizes
  are responsive (`~26%` of screen width, clamped 72–104 px) with a
  standard 2.5 : 3.5 ratio. An optional `highlighted` state draws a gold
  border (used to single out the smallest hand at the reveal). It renders
  the existing pure-Dart `Card` model and exposes a single semantic label
  (e.g. "7 of Clubs") with decorative glyphs excluded from semantics.
- `CardBack` — the face-down Turtle King card back: the navy emblem on a
  gold-ringed cream card. It deliberately takes **no** `Card`, so a hidden
  card can never leak its identity through pixels, semantics, or keys; its
  accessibility label is just "Card back".
- `CardFace` — kept as a thin wrapper around `PlayingCard` so existing
  screens and tests using `CardFace.card` keep working unchanged.

**Card-table environment** (`lib/game_table.dart`):

- `GameTableBackground` — a deep-green felt table: a radial "table light"
  gradient (green center fading to `#08211A` edges) with a subtle,
  deterministic felt texture. The game screen sits on it behind a
  transparent, gold-titled app bar.
- `TurtleKingCup` — a drawn water cup whose size reflects the authoritative
  `CupSize` (normal → large → extra-large); pure presentation, never a
  second cup-size state.
- `TurtleKingCrown` — the gold crown shown on the final Turtle King screen.

**Game screen presentation** (`lib/game_start_screen.dart`):

- Every stage keeps its exact flow and copy, restyled for the table:
  round badge, "Player X of Y" pill, gold-ringed player avatar, and a
  "Your turn" indicator; the viewing screens pair the one visible card
  with a hidden `CardBack`; the neutral handoff shows a phone icon and
  zero cards; the pour turn shows the cup, the drinks chip, a prominent
  red "YAMADA! — Admit defeat · drink the cup" button, and a green
  "Hold out" button; the group reveal animates in once (a short,
  settling fade/scale) and gold-highlights the smallest hand(s); the
  final screen shows the crown, the gold Turtle King name, and
  de-emphasizes (struck-through) eliminated players.
- The reveal and hands use `Wrap`, so any number of players' cards flow
  to new rows instead of overflowing small screens; the whole screen
  scrolls and avoids hard-coded coordinates.
- No infinite/repeating animations are used, so gameplay never blocks and
  the existing test flow (which relies on `pumpAndSettle`) is unaffected.

**Theme** (`lib/theme.dart`) — added `TurtleKingColors`, the shared brand
palette (navy `#0B263C`, gold `#D4AF37`, felt greens, card cream, suit
red/black) used by the card widgets, table, and game screen.

**Out of scope** — gameplay rules, `GameState`, privacy behavior, and all
other screens are untouched; no dependencies were added.

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
  main.dart               # App entry point (splash -> home)
  theme.dart              # Shared visual theme
  splash_screen.dart      # Branded launch screen (full artwork -> home)
  home_screen.dart        # Home screen (emblem brand mark + New Game + How to Play)
  how_to_play_screen.dart # Rules documentation (How to Play screen)
  player.dart             # Player model (id, name, color)
  player_colors.dart      # Auto-assigned player color palette
  player_setup_screen.dart# Player setup (add/remove/limits/start)
  game_start_screen.dart  # Pass-and-play flow + YAMADA round screen (card table UI)
  card_widgets.dart       # Realistic PlayingCard, Turtle King CardBack, CardFace
  game_table.dart         # Felt table background, cup and crown visuals
  round_history_screen.dart # Read-only round-by-round history
  card.dart               # Suit, Rank, and Card model
  deck.dart               # Standard 52-card deck (shuffle/deal/reset)
  game_state.dart         # Hands, turns, rounds, cup, scoring, elimination, result
assets/
  branding/               # Turtle King artwork (splash, emblem, icon)
tool/
  generate_branding.ps1   # Regenerates all branding derivatives
test/
  home_screen_test.dart        # Home screen branding + navigation
  splash_screen_test.dart      # Launch screen artwork + transition
  branding_config_test.dart    # Native icon/splash configuration
  player_test.dart             # Player model + color palette
  player_setup_screen_test.dart# Player setup behavior
  card_test.dart               # Suit/rank values, Card display + equality
  deck_test.dart               # Deck creation, shuffle, dealing, reset
  game_state_test.dart         # Hands, rounds, cup, scoring, elimination, result
  game_start_screen_test.dart  # Pass-and-play + round + penalty + multi-round UI
  card_widgets_test.dart       # PlayingCard/CardBack/CardFace rendering + semantics
  game_visuals_test.dart       # Table, hidden cards, cup, YAMADA, reveal, winner UI
  how_to_play_screen_test.dart # How to Play content, scrolling, navigation
  round_history_screen_test.dart# Round history content, privacy, scrolling
```
