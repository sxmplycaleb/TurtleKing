import 'dart:convert';
import 'dart:typed_data';

/// The maximum size of one framed BLE message. Bounds the memory a
/// misbehaving peer can force us to buffer (mirrors [kMaxFrameBytes] on the
/// TCP transport).
const int kBleMaxMessageBytes = 256 * 1024;

/// Header byte of a chunk that begins a new message (carries the total
/// message length).
const int _kChunkFirst = 0x01;

/// Header byte of a continuation chunk (carries the next slice of the
/// current message).
const int _kChunkContinuation = 0x02;

/// Splits one complete message into MTU-sized chunks suitable for a single
/// BLE notification or write.
///
/// Wire format (per chunk):
/// ```text
/// FIRST chunk:        [0x01] [len 4 bytes BE] [message bytes ...]
/// CONTINUATION chunk: [0x02] [message bytes ...]
/// ```
///
/// [chunkSize] is the maximum payload of one ATT operation (typically
/// `getMaximumWriteLength`/`getMaximumNotifyLength`, floor 20). The header
/// byte is included in [chunkSize], so a single-chunk message needs
/// `message.length + 5 <= chunkSize`.
///
/// Chunking is deterministic and lossless: feeding every returned chunk to a
/// [BleFrameAssembler] in order reproduces [message] byte-for-byte.
List<Uint8List> encodeBleMessage(Uint8List message, int chunkSize) {
  final size = chunkSize < 6 ? 6 : chunkSize;
  final data = message;
  if (data.length + 5 <= size) {
    // Single chunk: header + full message.
    final out = Uint8List(5 + data.length);
    out[0] = _kChunkFirst;
    out.buffer.asByteData().setUint32(1, data.length);
    out.setRange(5, out.length, data);
    return [out];
  }
  final chunks = <Uint8List>[];
  var offset = 0;
  // First chunk carries the length header and as much data as fits.
  final firstData = size - 5;
  final first = Uint8List(size);
  first[0] = _kChunkFirst;
  first.buffer.asByteData().setUint32(1, data.length);
  first.setRange(5, size, data, 0);
  chunks.add(first);
  offset += firstData;
  while (offset < data.length) {
    final take = (data.length - offset) < (size - 1)
        ? (data.length - offset)
        : (size - 1);
    final chunk = Uint8List(1 + take);
    chunk[0] = _kChunkContinuation;
    chunk.setRange(1, chunk.length, data, offset);
    chunks.add(chunk);
    offset += take;
  }
  return chunks;
}

/// Reassembles chunked BLE frames back into complete messages.
///
/// Feed every inbound chunk ([BleCentralConnection.data] /
/// [BleAdapter.hostData]) to [feed]; it returns the complete messages whose
/// chunks have arrived (normally zero or one per chunk). Malformed framing
/// (unknown header byte, a continuation without a start, a length that
/// exceeds [kBleMaxMessageBytes]) throws [FormatException] — the transport
/// treats that as a protocol violation and drops the connection.
class BleFrameAssembler {
  final BytesBuilder _bytes = BytesBuilder();
  int _expected = -1;

  bool get _inMessage => _expected >= 0;

  /// Feeds one chunk; returns the completed messages (in order).
  List<Uint8List> feed(Uint8List chunk) {
    if (chunk.isEmpty) return const [];
    final header = chunk[0];
    switch (header) {
      case _kChunkFirst:
        if (chunk.length < 5) {
          throw const FormatException('BLE first chunk too short');
        }
        final length = chunk.buffer
            .asByteData(chunk.offsetInBytes)
            .getUint32(1);
        if (length == 0 || length > kBleMaxMessageBytes) {
          throw FormatException('invalid BLE message length $length');
        }
        _expected = length;
        _bytes.clear();
        _bytes.add(chunk.sublist(5));
        return _emitIfComplete();
      case _kChunkContinuation:
        if (!_inMessage) {
          throw const FormatException('BLE continuation without a start');
        }
        _bytes.add(chunk.sublist(1));
        return _emitIfComplete();
      default:
        throw FormatException(
          'unknown BLE chunk header 0x${header.toRadixString(16)}',
        );
    }
  }

  List<Uint8List> _emitIfComplete() {
    final have = _bytes.length;
    if (have > _expected) {
      // More data than the declared length: corrupt framing.
      throw FormatException('BLE message exceeds declared length');
    }
    if (have < _expected) return const [];
    final message = _bytes.takeBytes();
    _expected = -1;
    return [message];
  }

  /// Whether a partial message is currently buffered.
  bool get hasPartial => _inMessage;

  /// Drops any partial message (e.g. on connection teardown).
  void reset() {
    _expected = -1;
    _bytes.clear();
  }
}

/// Convenience: encodes a UTF-8 string message into BLE chunks.
List<Uint8List> encodeBleString(String message, int chunkSize) =>
    encodeBleMessage(utf8.encode(message), chunkSize);
