import 'package:flutter/services.dart';

/// Acquires/releases the Android Wi-Fi multicast lock so the app reliably
/// receives multicast discovery beacons while the session is active.
///
/// Best-effort only: where the platform channel is unavailable (tests,
/// desktop, or a platform without the channel) every call is a silent no-op.
/// Discovery degrades gracefully to the manual host-IP join path.
class MulticastLock {
  MulticastLock._();

  static const MethodChannel _channel = MethodChannel(
    'turtle_king/multicast_lock',
  );

  static Future<void> acquire() async {
    try {
      await _channel.invokeMethod<void>('acquire');
    } catch (_) {
      // No channel: nothing to hold.
    }
  }

  static Future<void> release() async {
    try {
      await _channel.invokeMethod<void>('release');
    } catch (_) {
      // No channel: nothing to release.
    }
  }
}
