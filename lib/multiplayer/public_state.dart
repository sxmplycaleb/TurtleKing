import '../game_state.dart';
import '../player.dart';
import 'json_util.dart';

/// A single public roster entry: identity + display color, nothing else.
class PublicPlayer {
  const PublicPlayer({
    required this.id,
    required this.name,
    required this.color,
  });

  factory PublicPlayer.fromGame(Player player) => PublicPlayer(
    id: player.id,
    name: player.name,
    color: player.color.toARGB32(),
  );

  final String id;
  final String name;

  /// The player's assigned color (ARGB int) — public presentation data.
  final int color;

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'color': color};

  factory PublicPlayer.fromJson(Object? value) {
    final map = requireMap(value, 'player');
    return PublicPlayer(
      id: requireString(map['id'], 'player.id'),
      name: requireString(map['name'], 'player.name'),
      color: requireInt(map['color'], 'player.color'),
    );
  }
}

/// One public elimination record (who, when, at what drink count, why).
class PublicElimination {
  const PublicElimination({
    required this.playerId,
    required this.round,
    required this.drinks,
    required this.reason,
  });

  factory PublicElimination.fromGame(EliminationRecord record) =>
      PublicElimination(
        playerId: record.player.id,
        round: record.round,
        drinks: record.drinks,
        reason: record.reason.name,
      );

  final String playerId;
  final int round;
  final int drinks;
  final String reason;

  Map<String, Object?> toJson() => {
    'playerId': playerId,
    'round': round,
    'drinks': drinks,
    'reason': reason,
  };

  factory PublicElimination.fromJson(Object? value) {
    final map = requireMap(value, 'elimination');
    return PublicElimination(
      playerId: requireString(map['playerId'], 'elimination.playerId'),
      round: requireInt(map['round'], 'elimination.round'),
      drinks: requireInt(map['drinks'], 'elimination.drinks'),
      reason: requireString(map['reason'], 'elimination.reason'),
    );
  }
}

/// The public result of one completed round (aggregates only — never cards).
class PublicRoundResult {
  const PublicRoundResult({
    required this.drinks,
    required this.calledYamada,
    required this.smallestHands,
    required this.cupSize,
  });

  factory PublicRoundResult.fromGame(RoundResult result) => PublicRoundResult(
    drinks: {for (final e in result.drinks.entries) e.key.id: e.value},
    calledYamada: {
      for (final e in result.calledYamada.entries) e.key.id: e.value,
    },
    smallestHands: [for (final p in result.smallestHands) p.id],
    cupSize: result.cupSize.name,
  );

  final Map<String, int> drinks;
  final Map<String, bool> calledYamada;
  final List<String> smallestHands;
  final String cupSize;

  Map<String, Object?> toJson() => {
    'drinks': drinks,
    'calledYamada': calledYamada,
    'smallestHands': smallestHands,
    'cupSize': cupSize,
  };

  factory PublicRoundResult.fromJson(Object? value) {
    final map = requireMap(value, 'round result');
    return PublicRoundResult(
      drinks: requireIntMap(map['drinks'], 'round result.drinks'),
      calledYamada: requireBoolMap(
        map['calledYamada'],
        'round result.calledYamada',
      ),
      smallestHands: [
        for (final id in requireList(
          map['smallestHands'],
          'round result.smallestHands',
        ))
          requireString(id, 'round result.smallestHands[]'),
      ],
      cupSize: requireString(map['cupSize'], 'round result.cupSize'),
    );
  }
}

/// One public replay event. `GameEvent` is documented card-identity-free, so
/// the whole log may cross the network; this mirrors it without exposing
/// any internal state.
class PublicGameEvent {
  const PublicGameEvent({
    required this.type,
    required this.round,
    this.playerId,
    this.playerIds = const [],
    this.cupSize,
    this.result,
  });

  factory PublicGameEvent.fromGame(GameEvent event) => PublicGameEvent(
    type: event.type.name,
    round: event.round,
    playerId: event.player?.id,
    playerIds: [for (final p in event.players) p.id],
    cupSize: event.cupSize?.name,
    result: event.result == null
        ? null
        : PublicRoundResult.fromGame(event.result!),
  );

  final String type;
  final int round;
  final String? playerId;
  final List<String> playerIds;
  final String? cupSize;
  final PublicRoundResult? result;

  Map<String, Object?> toJson() => {
    'type': type,
    'round': round,
    'playerId': playerId,
    'playerIds': playerIds,
    'cupSize': cupSize,
    'result': result?.toJson(),
  };

  factory PublicGameEvent.fromJson(Object? value) {
    final map = requireMap(value, 'game event');
    final playerId = map['playerId'];
    final cupSize = map['cupSize'];
    final result = map['result'];
    return PublicGameEvent(
      type: requireString(map['type'], 'game event.type'),
      round: requireInt(map['round'], 'game event.round'),
      playerId: playerId == null
          ? null
          : requireString(playerId, 'game event.playerId'),
      playerIds: [
        for (final id in requireList(map['playerIds'], 'game event.playerIds'))
          requireString(id, 'game event.playerIds[]'),
      ],
      cupSize: cupSize == null
          ? null
          : requireString(cupSize, 'game event.cupSize'),
      result: result == null ? null : PublicRoundResult.fromJson(result),
    );
  }
}

/// The public final result of a completed game (aggregates only — never cards).
class PublicGameResult {
  const PublicGameResult({
    required this.drinks,
    required this.turtleKings,
    required this.finalists,
    required this.eliminated,
    required this.eliminations,
    required this.roundsPlayed,
  });

  factory PublicGameResult.fromGame(GameResult result) => PublicGameResult(
    drinks: {for (final e in result.drinks.entries) e.key.id: e.value},
    turtleKings: [for (final p in result.turtleKings) p.id],
    finalists: [for (final p in result.finalists) p.id],
    eliminated: [for (final p in result.eliminated) p.id],
    eliminations: [
      for (final r in result.eliminations) PublicElimination.fromGame(r),
    ],
    roundsPlayed: result.roundsPlayed,
  );

  final Map<String, int> drinks;
  final List<String> turtleKings;
  final List<String> finalists;
  final List<String> eliminated;
  final List<PublicElimination> eliminations;
  final int roundsPlayed;

  Map<String, Object?> toJson() => {
    'drinks': drinks,
    'turtleKings': turtleKings,
    'finalists': finalists,
    'eliminated': eliminated,
    'eliminations': [for (final e in eliminations) e.toJson()],
    'roundsPlayed': roundsPlayed,
  };

  factory PublicGameResult.fromJson(Object? value) {
    final map = requireMap(value, 'game result');
    return PublicGameResult(
      drinks: requireIntMap(map['drinks'], 'game result.drinks'),
      turtleKings: [
        for (final id in requireList(
          map['turtleKings'],
          'game result.turtleKings',
        ))
          requireString(id, 'game result.turtleKings[]'),
      ],
      finalists: [
        for (final id in requireList(map['finalists'], 'game result.finalists'))
          requireString(id, 'game result.finalists[]'),
      ],
      eliminated: [
        for (final id in requireList(
          map['eliminated'],
          'game result.eliminated',
        ))
          requireString(id, 'game result.eliminated[]'),
      ],
      eliminations: [
        for (final e in requireList(
          map['eliminations'],
          'game result.eliminations',
        ))
          PublicElimination.fromJson(e),
      ],
      roundsPlayed: requireInt(map['roundsPlayed'], 'game result.roundsPlayed'),
    );
  }
}

/// The sanitized public projection of a [GameState] — the ONLY state view the
/// protocol may broadcast.
///
/// It is constructed **explicitly** from allowed public getters and contains
/// nothing else: no hands, no visible cards, no hidden cards, no remaining
/// deck, no save document, and no [GameState] internals. The replay events
/// it carries are the documented card-identity-free `GameEvent`s, so no card
/// identity can ride along with history.
///
/// Privacy is structural: this view has no `Card`-typed field at all. The
/// only place card identities may enter the protocol is the narrow
/// [PrivateStateView] in private_state.dart, which carries exactly one
/// rule-authorized card to exactly one recipient.
class PublicStateView {
  PublicStateView({
    required this.players,
    required this.eliminationThreshold,
    required this.roundNumber,
    required this.cupSize,
    required this.pouringStarted,
    required this.allPlayersViewed,
    required this.currentPlayerRevealed,
    required this.currentPlayerIndex,
    required this.roundComplete,
    required this.canStartNextRound,
    required this.gameComplete,
    required this.completedRounds,
    required this.lifetimeDrinks,
    required this.roundDrinks,
    required this.calledYamada,
    required this.smallestHands,
    required this.revealedPlayers,
    required this.eliminatedPlayerIds,
    required this.eliminations,
    required this.roundResults,
    required this.events,
    required this.finalResult,
  });

  /// Builds the projection from a [GameState] using **only public getters**.
  factory PublicStateView.fromGame(GameState game) {
    return PublicStateView(
      players: [for (final p in game.players) PublicPlayer.fromGame(p)],
      eliminationThreshold: game.eliminationThreshold,
      roundNumber: game.roundNumber,
      cupSize: game.cupSize.name,
      pouringStarted: game.pouringStarted,
      allPlayersViewed: game.allPlayersViewed,
      currentPlayerRevealed: game.currentPlayerRevealed,
      currentPlayerIndex: game.currentPlayerIndex,
      roundComplete: game.roundComplete,
      canStartNextRound: game.canStartNextRound,
      gameComplete: game.gameComplete,
      completedRounds: game.completedRounds,
      lifetimeDrinks: {for (final p in game.players) p.id: game.drinksOf(p)},
      roundDrinks: {for (final p in game.players) p.id: game.roundDrinksOf(p)},
      calledYamada: {
        for (final p in game.players) p.id: game.calledYamadaThisRound(p),
      },
      smallestHands: [for (final p in game.smallestHands) p.id],
      revealedPlayers: [for (final p in game.revealedPlayers) p.id],
      eliminatedPlayerIds: [for (final p in game.eliminatedPlayers) p.id],
      eliminations: [
        for (final r in game.eliminationHistory) PublicElimination.fromGame(r),
      ],
      roundResults: [
        for (final r in game.roundResults) PublicRoundResult.fromGame(r),
      ],
      events: [for (final e in game.events) PublicGameEvent.fromGame(e)],
      finalResult: game.finalResult == null
          ? null
          : PublicGameResult.fromGame(game.finalResult!),
    );
  }

  final List<PublicPlayer> players;
  final int eliminationThreshold;
  final int roundNumber;
  final String cupSize;
  final bool pouringStarted;
  final bool allPlayersViewed;
  final bool currentPlayerRevealed;
  final int currentPlayerIndex;
  final bool roundComplete;
  final bool canStartNextRound;
  final bool gameComplete;
  final int completedRounds;
  final Map<String, int> lifetimeDrinks;
  final Map<String, int> roundDrinks;
  final Map<String, bool> calledYamada;
  final List<String> smallestHands;
  final List<String> revealedPlayers;
  final List<String> eliminatedPlayerIds;
  final List<PublicElimination> eliminations;
  final List<PublicRoundResult> roundResults;
  final List<PublicGameEvent> events;
  final PublicGameResult? finalResult;

  Map<String, Object?> toJson() => {
    'players': [for (final p in players) p.toJson()],
    'eliminationThreshold': eliminationThreshold,
    'roundNumber': roundNumber,
    'cupSize': cupSize,
    'pouringStarted': pouringStarted,
    'allPlayersViewed': allPlayersViewed,
    'currentPlayerRevealed': currentPlayerRevealed,
    'currentPlayerIndex': currentPlayerIndex,
    'roundComplete': roundComplete,
    'canStartNextRound': canStartNextRound,
    'gameComplete': gameComplete,
    'completedRounds': completedRounds,
    'lifetimeDrinks': lifetimeDrinks,
    'roundDrinks': roundDrinks,
    'calledYamada': calledYamada,
    'smallestHands': smallestHands,
    'revealedPlayers': revealedPlayers,
    'eliminatedPlayerIds': eliminatedPlayerIds,
    'eliminations': [for (final e in eliminations) e.toJson()],
    'roundResults': [for (final r in roundResults) r.toJson()],
    'events': [for (final e in events) e.toJson()],
    'finalResult': finalResult?.toJson(),
  };

  /// Strictly rebuilds the view from a previously encoded payload.
  factory PublicStateView.fromJson(Object? value) {
    final map = requireMap(value, 'public state');
    final finalResult = map['finalResult'];
    return PublicStateView(
      players: [
        for (final p in requireList(map['players'], 'public state.players'))
          PublicPlayer.fromJson(p),
      ],
      eliminationThreshold: requireInt(
        map['eliminationThreshold'],
        'public state.eliminationThreshold',
      ),
      roundNumber: requireInt(map['roundNumber'], 'public state.roundNumber'),
      cupSize: requireString(map['cupSize'], 'public state.cupSize'),
      pouringStarted: requireBool(
        map['pouringStarted'],
        'public state.pouringStarted',
      ),
      allPlayersViewed: requireBool(
        map['allPlayersViewed'],
        'public state.allPlayersViewed',
      ),
      currentPlayerRevealed: requireBool(
        map['currentPlayerRevealed'],
        'public state.currentPlayerRevealed',
      ),
      currentPlayerIndex: requireInt(
        map['currentPlayerIndex'],
        'public state.currentPlayerIndex',
      ),
      roundComplete: requireBool(
        map['roundComplete'],
        'public state.roundComplete',
      ),
      canStartNextRound: requireBool(
        map['canStartNextRound'],
        'public state.canStartNextRound',
      ),
      gameComplete: requireBool(
        map['gameComplete'],
        'public state.gameComplete',
      ),
      completedRounds: requireInt(
        map['completedRounds'],
        'public state.completedRounds',
      ),
      lifetimeDrinks: requireIntMap(
        map['lifetimeDrinks'],
        'public state.lifetimeDrinks',
      ),
      roundDrinks: requireIntMap(
        map['roundDrinks'],
        'public state.roundDrinks',
      ),
      calledYamada: requireBoolMap(
        map['calledYamada'],
        'public state.calledYamada',
      ),
      smallestHands: [
        for (final id in requireList(
          map['smallestHands'],
          'public state.smallestHands',
        ))
          requireString(id, 'public state.smallestHands[]'),
      ],
      revealedPlayers: [
        for (final id in requireList(
          map['revealedPlayers'],
          'public state.revealedPlayers',
        ))
          requireString(id, 'public state.revealedPlayers[]'),
      ],
      eliminatedPlayerIds: [
        for (final id in requireList(
          map['eliminatedPlayerIds'],
          'public state.eliminatedPlayerIds',
        ))
          requireString(id, 'public state.eliminatedPlayerIds[]'),
      ],
      eliminations: [
        for (final e in requireList(
          map['eliminations'],
          'public state.eliminations',
        ))
          PublicElimination.fromJson(e),
      ],
      roundResults: [
        for (final r in requireList(
          map['roundResults'],
          'public state.roundResults',
        ))
          PublicRoundResult.fromJson(r),
      ],
      events: [
        for (final e in requireList(map['events'], 'public state.events'))
          PublicGameEvent.fromJson(e),
      ],
      finalResult: finalResult == null
          ? null
          : PublicGameResult.fromJson(finalResult),
    );
  }
}
