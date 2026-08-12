import 'dart:math';

/// The digits a join code may contain.
///
/// `0`, `1` and `I`/`l` are excluded so handwritten/read-out codes cannot be
/// confused (0↔O, 1↔I/l) — the classic "ambiguous characters" trick used by
/// airline and conference codes. The remaining 8 digits give 8^6 = 262,144
/// distinct codes, far more than the handful of sessions on any one LAN.
const String kJoinCodeDigits = '23456789';

/// The canonical length of a join code.
const int kJoinCodeLength = 6;

/// Generates a 6-digit ambiguity-free join code.
///
/// The code is a *locator*, not a credential: it exists so friends can find
/// the host's session without typing an IP address. It carries no session
/// secret, and the host never trusts it for authentication — the normal
/// HostSession/ClientSession validation still applies to every join.
String generateJoinCode({Random? random}) {
  final rng = random ?? Random.secure();
  final buffer = StringBuffer();
  for (var i = 0; i < kJoinCodeLength; i++) {
    buffer.write(kJoinCodeDigits[rng.nextInt(kJoinCodeDigits.length)]);
  }
  return buffer.toString();
}

/// Whether [value] is a syntactically valid join code (exactly 6 digits
/// from the ambiguity-free set). Whitespace is trimmed.
bool isValidJoinCode(String value) {
  final trimmed = value.trim();
  if (trimmed.length != kJoinCodeLength) return false;
  for (final char in trimmed.split('')) {
    if (!kJoinCodeDigits.contains(char)) return false;
  }
  return true;
}

/// Formats a code for display with a spacing break after the third digit
/// (e.g. `483 729`), which is easier to read and read aloud than six digits
/// in a row. Returns [value] unchanged when it is not a valid code.
String formatJoinCode(String value) {
  final trimmed = value.trim();
  if (!isValidJoinCode(trimmed)) return trimmed;
  return '${trimmed.substring(0, 3)} ${trimmed.substring(3)}';
}
