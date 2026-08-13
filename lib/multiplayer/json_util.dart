import 'dart:convert';

import 'errors.dart';

/// Encodes [value] as canonical, deterministic JSON.
///
/// Map keys are sorted recursively, so two structurally equal payloads always
/// produce byte-identical output regardless of the order the maps were built
/// in. This is what makes the protocol deterministic on the wire (and lets
/// tests compare encoded messages by string equality).
String canonicalJson(Object? value) =>
    const JsonEncoder().convert(_canonicalize(value));

Object? _canonicalize(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return {for (final key in keys) key: _canonicalize(value[key])};
  }
  if (value is List) return [for (final item in value) _canonicalize(item)];
  return value;
}

// ---------------------------------------------------------------------------
// Strict field readers. Every reader throws [MultiplayerProtocolException]
// with a precise reason instead of crashing or returning partial data.
// ---------------------------------------------------------------------------

Object? require(Object? value, String what) {
  if (value == null) {
    throw MultiplayerProtocolException('$what is missing');
  }
  return value;
}

Object? requireKey(Map<String, dynamic> map, String key) {
  if (!map.containsKey(key)) {
    throw MultiplayerProtocolException('missing field "$key"');
  }
  return require(map[key], 'field "$key"');
}

Map<String, dynamic> requireMap(Object? value, String what) {
  if (value is! Map<String, dynamic>) {
    throw MultiplayerProtocolException('$what must be an object');
  }
  return value;
}

List<dynamic> requireList(Object? value, String what) {
  if (value is! List) {
    throw MultiplayerProtocolException('$what must be a list');
  }
  return value;
}

String requireString(Object? value, String what) {
  final result = require(value, what);
  if (result is! String) {
    throw MultiplayerProtocolException('$what must be a string');
  }
  return result;
}

int requireInt(Object? value, String what) {
  final result = require(value, what);
  if (result is! int) {
    throw MultiplayerProtocolException('$what must be an integer');
  }
  return result;
}

bool requireBool(Object? value, String what) {
  final result = require(value, what);
  if (result is! bool) {
    throw MultiplayerProtocolException('$what must be a boolean');
  }
  return result;
}

/// Reads a string-keyed map with values of one type.
Map<String, int> requireIntMap(Object? value, String what) {
  final map = requireMap(value, what);
  return {
    for (final entry in map.entries)
      entry.key: requireInt(entry.value, '$what[${entry.key}]'),
  };
}

Map<String, bool> requireBoolMap(Object? value, String what) {
  final map = requireMap(value, what);
  return {
    for (final entry in map.entries)
      entry.key: requireBool(entry.value, '$what[${entry.key}]'),
  };
}

/// Reads an enum by its serialized `name`.
T requireEnum<T extends Enum>(List<T> values, Object? value, String what) {
  final name = requireString(value, what);
  for (final candidate in values) {
    if (candidate.name == name) return candidate;
  }
  throw MultiplayerProtocolException('unknown $what "$name"');
}
