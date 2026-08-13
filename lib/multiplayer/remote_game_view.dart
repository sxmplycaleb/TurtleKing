import 'private_state.dart';
import 'public_state.dart';

/// The minimum client-side representation needed to render a remote game.
///
/// Built **only** from the two protocol-authorized views:
///
/// * the broadcast [PublicStateView] (public players, turn, phase, drinks,
///   results, history — no card identities), and
/// * the client's own [PrivateStateView] (exactly its own authorized
///   visible card, delivered by PRIVATE_UPDATE).
///
/// It deliberately contains nothing else: no hidden second card, no other
/// player's cards, no deck, no `GameState` reference, no save data. The
/// remote UI renders from this object and nothing else.
///
/// This is a pure data snapshot — no gameplay rules live here. Deciding
/// whether an action is legal is the host's job.
class RemoteGameView {
  RemoteGameView({
    required this.publicState,
    required this.selfPlayerId,
    this.myCard,
  });

  factory RemoteGameView.empty({
    required List<PublicPlayer> players,
    required String selfPlayerId,
  }) => RemoteGameView(
    publicState: PublicStateView(
      players: players,
      eliminationThreshold: 6,
      roundNumber: 1,
      cupSize: 'normal',
      pouringStarted: false,
      allPlayersViewed: false,
      currentPlayerRevealed: false,
      currentPlayerIndex: 0,
      roundComplete: false,
      canStartNextRound: false,
      gameComplete: false,
      completedRounds: 0,
      lifetimeDrinks: {for (final p in players) p.id: 0},
      roundDrinks: {for (final p in players) p.id: 0},
      calledYamada: {for (final p in players) p.id: false},
      smallestHands: const [],
      revealedPlayers: const [],
      eliminatedPlayerIds: const [],
      eliminations: const [],
      roundResults: const [],
      events: const [],
      finalResult: null,
    ),
    selfPlayerId: selfPlayerId,
  );

  final PublicStateView publicState;
  final String selfPlayerId;

  /// This client's own authorized visible card (null before the first
  /// PRIVATE_UPDATE of a round).
  final PrivateCard? myCard;

  // -------------------------------------------------------------------
  // Public projection passthroughs
  // -------------------------------------------------------------------

  List<PublicPlayer> get players => publicState.players;
  int get roundNumber => publicState.roundNumber;
  String get cupSize => publicState.cupSize;
  bool get pouringStarted => publicState.pouringStarted;
  bool get allPlayersViewed => publicState.allPlayersViewed;
  bool get currentPlayerRevealed => publicState.currentPlayerRevealed;
  int get currentPlayerIndex => publicState.currentPlayerIndex;
  bool get roundComplete => publicState.roundComplete;
  bool get canStartNextRound => publicState.canStartNextRound;
  bool get gameComplete => publicState.gameComplete;
  int get completedRounds => publicState.completedRounds;
  Map<String, int> get lifetimeDrinks => publicState.lifetimeDrinks;
  Map<String, int> get roundDrinks => publicState.roundDrinks;
  Map<String, bool> get calledYamada => publicState.calledYamada;
  List<String> get smallestHands => publicState.smallestHands;
  List<String> get revealedPlayers => publicState.revealedPlayers;
  List<String> get eliminatedPlayerIds => publicState.eliminatedPlayerIds;
  List<PublicElimination> get eliminations => publicState.eliminations;
  List<PublicRoundResult> get roundResults => publicState.roundResults;
  List<PublicGameEvent> get events => publicState.events;
  PublicGameResult? get finalResult => publicState.finalResult;

  // -------------------------------------------------------------------
  // Derived convenience
  // -------------------------------------------------------------------

  /// The current actor (viewer during viewing, pourer during pouring).
  PublicPlayer? get currentPlayer =>
      currentPlayerIndex >= 0 && currentPlayerIndex < players.length
      ? players[currentPlayerIndex]
      : null;

  bool get isMyTurn => currentPlayer?.id == selfPlayerId;

  /// The client's own public roster entry (null before the host confirms).
  PublicPlayer? get me =>
      players.where((p) => p.id == selfPlayerId).firstOrNull;

  int? get myLifetimeDrinks => lifetimeDrinks[selfPlayerId];

  bool get iAmEliminated => eliminatedPlayerIds.contains(selfPlayerId);

  /// The final result names this client, if the game completed.
  bool get iWon => finalResult?.turtleKings.contains(selfPlayerId) ?? false;
}
