import 'dart:convert';

import 'package:flutter/material.dart' show Color;
import 'package:shared_preferences/shared_preferences.dart';

import 'card.dart';
import 'game_state.dart';
import 'player.dart';

/// Thrown when a saved game cannot be loaded: corrupt JSON, an unsupported
/// schema version, or a structurally invalid document. The save layer never
/// returns a partially restored game — loading either succeeds fully or
/// throws this.
class GameSaveException implements Exception {
  const GameSaveException(this.message);

  /// Why the save could not be loaded.
  final String message;

  @override
  String toString() => 'GameSaveException: $message';
}

/// The schema version of the saved-game document written by this app.
///
/// Bump this whenever the document layout changes; older versions are
/// rejected safely instead of being misinterpreted.
const int kGameSaveSchemaVersion = 1;

/// The SharedPreferences key holding the single saved-game document.
const String kGameSaveKey = 'game.save.v1';

/// Serializes a [GameState] to a single versioned JSON document and back.
///
/// The document is local-only and contains exactly the gameplay state needed
/// to resume: players, hands, remaining deck order, turn/pouring position,
/// cup size, drinks, eliminations, round results, and the replay event log.
/// Hidden card identities are stored here because they are gameplay state,
/// but the codec exposes them nowhere else — the UI and history layers only
/// ever read GameState's aggregate getters, so the privacy contract is
/// unchanged.
class GameSaveCodec {
  const GameSaveCodec();

  /// Encodes [game] into a compact JSON string.
  String encode(GameState game) => jsonEncode(toMap(game));

  /// Decodes [raw]. Throws [GameSaveException] on corrupt, unsupported, or
  /// structurally invalid input. Never partially restores a game.
  GameState decode(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (error) {
      throw GameSaveException('corrupt JSON: ${error.message}');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const GameSaveException('the save root must be a JSON object');
    }
    return fromMap(decoded);
  }

  /// Converts [game] into the JSON-encodable document map.
  Map<String, dynamic> toMap(GameState game) {
    final playersById = {for (final player in game.players) player.id: player};
    return <String, dynamic>{
      'schemaVersion': kGameSaveSchemaVersion,
      'players': [for (final player in game.players) _playerToMap(player)],
      'eliminationThreshold': game.eliminationThreshold,
      'lifetimeDrinks': {
        for (final player in game.players) player.id: game.drinksOf(player),
      },
      'roundDrinks': {
        for (final player in game.players)
          player.id: game.roundDrinksOf(player),
      },
      'calledYamada': {
        for (final player in game.players)
          player.id: game.calledYamadaThisRound(player),
      },
      'roundResults': [
        for (final result in game.roundResults)
          _roundResultToMap(result, playersById),
      ],
      'events': [
        for (final event in game.events) _eventToMap(event, playersById),
      ],
      'eliminatedIds': [for (final player in game.eliminatedPlayers) player.id],
      'eliminations': [
        for (final record in game.eliminationHistory) _eliminationToMap(record),
      ],
      'hands': {
        for (final player in game.players)
          if (game.hasHand(player))
            player.id: [
              for (final card in game.handOf(player)) _cardToMap(card),
            ],
      },
      'viewIndex': game.viewIndex,
      'revealed': game.currentPlayerRevealed,
      'pouring': game.pouringStarted,
      'pourIndex': game.pourIndex,
      'consecutiveHolds': game.consecutiveHolds,
      'cupSize': game.cupSize.name,
      'roundNumber': game.roundNumber,
      'roundFinalized': game.roundComplete,
      'smallestHands': [for (final player in game.smallestHands) player.id],
      'revealedPlayers': [for (final player in game.revealedPlayers) player.id],
      'gameComplete': game.gameComplete,
      'finalResult': game.finalResult == null
          ? null
          : _resultToMap(game.finalResult!, playersById),
      'remainingDeck': [
        for (final card in game.remainingDeck) _cardToMap(card),
      ],
    };
  }

  /// Rebuilds a [GameState] from [map]. Throws [GameSaveException] on any
  /// missing field, wrong type, or unknown value — never returns a partially
  /// restored game.
  GameState fromMap(Map<String, dynamic> map) {
    try {
      final version = _requireInt(map, 'schemaVersion');
      if (version != kGameSaveSchemaVersion) {
        throw GameSaveException(
          'unsupported save schema version $version '
          '(expected $kGameSaveSchemaVersion)',
        );
      }
      final players = [
        for (final item in _requireList(map, 'players'))
          _playerFromMap(_requireMap(item, 'players[]')),
      ];
      final playersById = {for (final player in players) player.id: player};

      final roundResults = [
        for (final item in _requireList(map, 'roundResults'))
          _roundResultFromMap(_requireMap(item, 'roundResults[]'), playersById),
      ];
      final events = [
        for (final item in _requireList(map, 'events'))
          _eventFromMap(_requireMap(item, 'events[]'), playersById),
      ];
      final eliminations = [
        for (final item in _requireList(map, 'eliminations'))
          _eliminationFromMap(_requireMap(item, 'eliminations[]'), playersById),
      ];

      final hands = <String, List<Card>>{};
      for (final entry in _requireMap(map['hands'], 'hands').entries) {
        final rawCards = entry.value;
        if (rawCards is! List) {
          throw GameSaveException('hands[${entry.key}] must be a list');
        }
        hands[entry.key] = [
          for (final item in rawCards)
            _cardFromMap(_requireMap(item, 'hands[${entry.key}][]')),
        ];
      }

      final finalResultRaw = map['finalResult'];
      final GameResult? finalResult;
      if (finalResultRaw == null) {
        finalResult = null;
      } else {
        finalResult = _resultFromMap(
          _requireMap(finalResultRaw, 'finalResult'),
          playersById,
        );
      }

      return GameState.restore(
        players: players,
        eliminationThreshold: _requireInt(map, 'eliminationThreshold'),
        lifetimeDrinks: _stringIntMap(map, 'lifetimeDrinks'),
        roundDrinks: _stringIntMap(map, 'roundDrinks'),
        calledYamada: _stringBoolMap(map, 'calledYamada'),
        roundResults: roundResults,
        events: events,
        eliminatedIds: {
          for (final id in _requireList(map, 'eliminatedIds')) id as String,
        },
        eliminations: eliminations,
        hands: hands,
        viewIndex: _requireInt(map, 'viewIndex'),
        revealed: _requireBool(map, 'revealed'),
        pouring: _requireBool(map, 'pouring'),
        pourIndex: _requireInt(map, 'pourIndex'),
        consecutiveHolds: _requireInt(map, 'consecutiveHolds'),
        cupSize: _enumByName(
          CupSize.values,
          _requireString(map, 'cupSize'),
          'cupSize',
        ),
        roundNumber: _requireInt(map, 'roundNumber'),
        roundFinalized: _requireBool(map, 'roundFinalized'),
        smallestHands: [
          for (final id in _requireList(map, 'smallestHands'))
            _playerRef(id as String, playersById),
        ],
        revealedPlayers: [
          for (final id in _requireList(map, 'revealedPlayers'))
            _playerRef(id as String, playersById),
        ],
        gameComplete: _requireBool(map, 'gameComplete'),
        finalResult: finalResult,
        remainingDeck: [
          for (final item in _requireList(map, 'remainingDeck'))
            _cardFromMap(_requireMap(item, 'remainingDeck[]')),
        ],
      );
    } on GameSaveException {
      rethrow;
    } on Object catch (error) {
      throw GameSaveException('invalid saved game: $error');
    }
  }

  // ---------------------------------------------------------------------
  // Encoders
  // ---------------------------------------------------------------------

  Map<String, dynamic> _playerToMap(Player player) => {
    'id': player.id,
    'name': player.name,
    'color': player.color.toARGB32(),
  };

  Map<String, dynamic> _cardToMap(Card card) => {
    'suit': card.suit.name,
    'rank': card.rank.name,
  };

  Map<String, dynamic> _roundResultToMap(
    RoundResult result,
    Map<String, Player> playersById,
  ) => {
    'drinks': {
      for (final entry in result.drinks.entries) entry.key.id: entry.value,
    },
    'calledYamada': {
      for (final entry in result.calledYamada.entries)
        entry.key.id: entry.value,
    },
    'smallestHands': [for (final player in result.smallestHands) player.id],
    'cupSize': result.cupSize.name,
  };

  Map<String, dynamic> _eventToMap(
    GameEvent event,
    Map<String, Player> playersById,
  ) => {
    'type': event.type.name,
    'round': event.round,
    'player': event.player?.id,
    'players': [for (final player in event.players) player.id],
    'cupSize': event.cupSize?.name,
    'result': event.result == null
        ? null
        : _roundResultToMap(event.result!, playersById),
  };

  Map<String, dynamic> _eliminationToMap(EliminationRecord record) => {
    'player': record.player.id,
    'round': record.round,
    'drinks': record.drinks,
    'reason': record.reason.name,
  };

  Map<String, dynamic> _resultToMap(
    GameResult result,
    Map<String, Player> playersById,
  ) => {
    'drinks': {
      for (final entry in result.drinks.entries) entry.key.id: entry.value,
    },
    'turtleKings': [for (final player in result.turtleKings) player.id],
    'finalists': [for (final player in result.finalists) player.id],
    'eliminated': [for (final player in result.eliminated) player.id],
    'eliminations': [
      for (final record in result.eliminations) _eliminationToMap(record),
    ],
    'roundsPlayed': result.roundsPlayed,
  };

  // ---------------------------------------------------------------------
  // Decoders
  // ---------------------------------------------------------------------

  Player _playerFromMap(Map<String, dynamic> map) => Player(
    id: _requireString(map, 'id'),
    name: _requireString(map, 'name'),
    color: Color(_requireInt(map, 'color')),
  );

  Card _cardFromMap(Map<String, dynamic> map) => Card(
    suit: _enumByName(Suit.values, _requireString(map, 'suit'), 'suit'),
    rank: _enumByName(Rank.values, _requireString(map, 'rank'), 'rank'),
  );

  RoundResult _roundResultFromMap(
    Map<String, dynamic> map,
    Map<String, Player> playersById,
  ) => RoundResult(
    drinks: _playerIntMap(map, 'drinks', playersById),
    calledYamada: _playerBoolMap(map, 'calledYamada', playersById),
    smallestHands: [
      for (final id in _requireList(map, 'smallestHands'))
        _playerRef(id as String, playersById),
    ],
    cupSize: _enumByName(
      CupSize.values,
      _requireString(map, 'cupSize'),
      'cupSize',
    ),
  );

  GameEvent _eventFromMap(
    Map<String, dynamic> map,
    Map<String, Player> playersById,
  ) {
    final playerId = map['player'];
    final cupSizeRaw = map['cupSize'];
    final resultRaw = map['result'];
    return GameEvent(
      type: _enumByName(
        GameEventType.values,
        _requireString(map, 'type'),
        'event type',
      ),
      round: _requireInt(map, 'round'),
      player: playerId == null
          ? null
          : _playerRef(playerId as String, playersById),
      players: [
        for (final id in _requireList(map, 'players'))
          _playerRef(id as String, playersById),
      ],
      cupSize: cupSizeRaw == null
          ? null
          : _enumByName(CupSize.values, cupSizeRaw as String, 'event cupSize'),
      result: resultRaw == null
          ? null
          : _roundResultFromMap(
              _requireMap(resultRaw, 'event result'),
              playersById,
            ),
    );
  }

  EliminationRecord _eliminationFromMap(
    Map<String, dynamic> map,
    Map<String, Player> playersById,
  ) => EliminationRecord(
    player: _playerRef(_requireString(map, 'player'), playersById),
    round: _requireInt(map, 'round'),
    drinks: _requireInt(map, 'drinks'),
    reason: _enumByName(
      EliminationReason.values,
      _requireString(map, 'reason'),
      'elimination reason',
    ),
  );

  GameResult _resultFromMap(
    Map<String, dynamic> map,
    Map<String, Player> playersById,
  ) => GameResult(
    drinks: _playerIntMap(map, 'drinks', playersById),
    turtleKings: [
      for (final id in _requireList(map, 'turtleKings'))
        _playerRef(id as String, playersById),
    ],
    finalists: [
      for (final id in _requireList(map, 'finalists'))
        _playerRef(id as String, playersById),
    ],
    eliminated: [
      for (final id in _requireList(map, 'eliminated'))
        _playerRef(id as String, playersById),
    ],
    eliminations: [
      for (final item in _requireList(map, 'eliminations'))
        _eliminationFromMap(
          _requireMap(item, 'finalResult eliminations[]'),
          playersById,
        ),
    ],
    roundsPlayed: _requireInt(map, 'roundsPlayed'),
  );

  // ---------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------

  Map<String, int> _stringIntMap(Map<String, dynamic> map, String key) => {
    for (final entry in _requireMap(map[key], key).entries)
      entry.key: entry.value as int,
  };

  Map<String, bool> _stringBoolMap(Map<String, dynamic> map, String key) => {
    for (final entry in _requireMap(map[key], key).entries)
      entry.key: entry.value as bool,
  };

  Map<Player, int> _playerIntMap(
    Map<String, dynamic> map,
    String key,
    Map<String, Player> playersById,
  ) => {
    for (final entry in _requireMap(map[key], key).entries)
      _playerRef(entry.key, playersById): entry.value as int,
  };

  Map<Player, bool> _playerBoolMap(
    Map<String, dynamic> map,
    String key,
    Map<String, Player> playersById,
  ) => {
    for (final entry in _requireMap(map[key], key).entries)
      _playerRef(entry.key, playersById): entry.value as bool,
  };

  Player _playerRef(String id, Map<String, Player> playersById) {
    final player = playersById[id];
    if (player == null) {
      throw GameSaveException('saved game references unknown player "$id"');
    }
    return player;
  }

  T _enumByName<T extends Enum>(List<T> values, String name, String what) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    throw GameSaveException('unknown $what "$name"');
  }

  dynamic _require(Map<String, dynamic> map, String key) {
    if (!map.containsKey(key) || map[key] == null) {
      throw GameSaveException('missing required field "$key"');
    }
    return map[key];
  }

  int _requireInt(Map<String, dynamic> map, String key) =>
      _require(map, key) as int;

  String _requireString(Map<String, dynamic> map, String key) =>
      _require(map, key) as String;

  bool _requireBool(Map<String, dynamic> map, String key) =>
      _require(map, key) as bool;

  List<dynamic> _requireList(Map<String, dynamic> map, String key) =>
      _require(map, key) as List<dynamic>;

  Map<String, dynamic> _requireMap(Object? value, String what) {
    if (value is! Map<String, dynamic>) {
      throw GameSaveException('$what must be an object');
    }
    return value;
  }
}

/// Stores and loads the single saved game through [SharedPreferences].
///
/// Local-only: the document is a plain string under one versioned key. There
/// is no networking, analytics, telemetry, or cloud sync anywhere in this
/// layer.
class GameSaveStore {
  GameSaveStore(this._prefs, {this.codec = const GameSaveCodec()});

  final SharedPreferences _prefs;

  /// The codec used for encode/decode.
  final GameSaveCodec codec;

  /// The preference key backing the saved game.
  static const String saveKey = kGameSaveKey;

  /// Whether a saved game document exists.
  bool get hasSave => _prefs.containsKey(saveKey);

  /// Loads and decodes the saved game.
  ///
  /// Returns null when no save exists. Throws [GameSaveException] when the
  /// save is corrupt or from an unsupported version; the caller can offer to
  /// discard it via [clear].
  GameState? load() {
    final raw = _prefs.getString(saveKey);
    if (raw == null) return null;
    return codec.decode(raw);
  }

  /// Encodes [game] and persists it as the current save.
  Future<bool> save(GameState game) =>
      _prefs.setString(saveKey, codec.encode(game));

  /// Removes the saved game (e.g. after completion or a fresh New Game).
  Future<bool> clear() => _prefs.remove(saveKey);
}
