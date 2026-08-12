/// Thrown by the multiplayer protocol codec whenever a message or payload is
/// malformed, unknown, or structurally invalid.
///
/// Decoding is strictly fail-safe: a [MultiplayerProtocolException] is thrown
/// instead of returning a partial or misinterpreted message, and callers can
/// always catch it without crashing the session or gameplay.
class MultiplayerProtocolException implements Exception {
  const MultiplayerProtocolException(this.reason);

  /// Why the payload was rejected.
  final String reason;

  @override
  String toString() => 'MultiplayerProtocolException: $reason';
}
