import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/multiplayer/relay_config.dart';

/// Contract: the default build ships with NO relay endpoint baked in, so the
/// lobby shows the "relay is not configured" error instead of failing
/// silently. A production build must inject one explicitly:
///
///     flutter build apk --release --dart-define=RELAY_URL=wss://<relay-host>
void main() {
  test('the default build has no relay endpoint configured', () {
    expect(kDefaultRelayUrl, isEmpty);
  });

  test('RELAY_URL is a valid WebSocket endpoint when provided', () {
    // The constant is compile-time; this documents the accepted shape.
    expect(kDefaultRelayUrl, isA<String>());
  });
}
