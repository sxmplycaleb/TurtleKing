import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/multiplayer/ble/ble_framing.dart';

void main() {
  group('encodeBleMessage', () {
    test('a message that fits in one chunk is emitted as a single chunk', () {
      final message = Uint8List.fromList(utf8.encode('{"a":1}'));
      final chunks = encodeBleMessage(message, 180);
      expect(chunks.length, 1);
      expect(chunks.first.length, 5 + message.length);
      // Header: first-byte 0x01 + 4-byte big-endian length.
      expect(chunks.first[0], 0x01);
      expect(
        chunks.first.buffer.asByteData(chunks.first.offsetInBytes).getUint32(1),
        message.length,
      );
    });

    test('a message spanning the MTU is chunked and reassembled exactly', () {
      final message = Uint8List.fromList(
        utf8.encode(
          '{"type":"STATE_UPDATE","seq":42,"sessionId":"tk-abc123",'
          '"body":{"stateSeq":7,"round":2}}',
        ),
      );
      for (final size in [20, 23, 180, 185, 247, 512, 517]) {
        final chunks = encodeBleMessage(message, size);
        if (size < message.length + 5) {
          expect(chunks.length, greaterThan(1), reason: 'chunk size $size');
        }
        for (final chunk in chunks) {
          expect(chunk.length, lessThanOrEqualTo(size));
        }
        final assembler = BleFrameAssembler();
        final out = <Uint8List>[];
        for (final chunk in chunks) {
          out.addAll(assembler.feed(chunk));
        }
        expect(out.length, 1, reason: 'chunk size $size');
        expect(out.first, message);
      }
    });

    test(
      'a large message (few KB, the largest broadcast) survives chunking',
      () {
        // The reveal broadcast is the largest message: all hands, names, etc.
        final body = List<String>.generate(64, (i) => '"player$i":"card$i"');
        final message = Uint8List.fromList(
          utf8.encode('{"type":"STATE_UPDATE","body":{${body.join(',')}}}'),
        );
        expect(message.length, greaterThan(1000));
        final assembler = BleFrameAssembler();
        final out = <Uint8List>[];
        for (final chunk in encodeBleMessage(message, 185)) {
          out.addAll(assembler.feed(chunk));
        }
        expect(out.single, message);
      },
    );

    test('chunk size is floored so tiny MTUs still produce valid chunks', () {
      final message = Uint8List.fromList(utf8.encode('hello'));
      final chunks = encodeBleMessage(message, 3); // below header overhead
      final assembler = BleFrameAssembler();
      final out = <Uint8List>[];
      for (final chunk in chunks) {
        out.addAll(assembler.feed(chunk));
      }
      expect(out.single, message);
    });
  });

  group('BleFrameAssembler', () {
    test('rejects a continuation chunk without a start', () {
      final assembler = BleFrameAssembler();
      expect(
        () => assembler.feed(Uint8List.fromList([0x02, 1, 2, 3])),
        throwsFormatException,
      );
    });

    test('rejects an unknown header byte', () {
      final assembler = BleFrameAssembler();
      expect(
        () => assembler.feed(Uint8List.fromList([0x7f, 0, 0, 0, 1, 1])),
        throwsFormatException,
      );
    });

    test('rejects a first chunk that is too short', () {
      final assembler = BleFrameAssembler();
      expect(
        () => assembler.feed(Uint8List.fromList([0x01, 0, 0])),
        throwsFormatException,
      );
    });

    test('rejects a zero-length or oversized declared message', () {
      final zero = Uint8List.fromList([0x01, 0, 0, 0, 0]);
      expect(() => BleFrameAssembler().feed(zero), throwsFormatException);

      final oversized = Uint8List(5);
      oversized[0] = 0x01;
      oversized.buffer
          .asByteData(oversized.offsetInBytes)
          .setUint32(1, kBleMaxMessageBytes + 1);
      expect(() => BleFrameAssembler().feed(oversized), throwsFormatException);
    });

    test('rejects a message that overruns its declared length', () {
      final assembler = BleFrameAssembler();
      final first = Uint8List(8);
      first[0] = 0x01;
      first.buffer.asByteData(first.offsetInBytes).setUint32(1, 2);
      first.setRange(5, 8, [65, 66, 67]);
      // Declared length 2 but fed 3 bytes.
      expect(() => assembler.feed(first), throwsFormatException);
    });

    test('a partial message is reported and reset() drops it', () {
      final message = utf8.encode('abcdefghij');
      final chunks = encodeBleMessage(Uint8List.fromList(message), 6);
      final assembler = BleFrameAssembler();
      var out = assembler.feed(chunks.first);
      expect(out, isEmpty);
      expect(assembler.hasPartial, isTrue);
      assembler.reset();
      expect(assembler.hasPartial, isFalse);
      // A fresh start after reset assembles cleanly.
      out = <Uint8List>[];
      for (final chunk in encodeBleMessage(Uint8List.fromList(message), 6)) {
        out.addAll(assembler.feed(chunk));
      }
      expect(out.single, message);
    });

    test('feeds from a real transport-style byte stream in order', () {
      // Simulate the notify stream: chunks arrive one per event, possibly
      // with unrelated traffic between messages.
      final messages = [
        Uint8List.fromList(utf8.encode('{"m":1}')),
        Uint8List.fromList(utf8.encode('{"m":2,"x":"${'y' * 300}"}')),
        Uint8List.fromList(utf8.encode('{"m":3}')),
      ];
      final assembler = BleFrameAssembler();
      final received = <Uint8List>[];
      for (final message in messages) {
        for (final chunk in encodeBleMessage(message, 100)) {
          received.addAll(assembler.feed(chunk));
        }
      }
      expect(received.length, messages.length);
      for (var i = 0; i < messages.length; i++) {
        expect(received[i], messages[i]);
      }
    });
  });

  group('encodeBleString', () {
    test('round-trips a string message', () {
      const text = '{"type":"HEARTBEAT","seq":1,"sessionId":"tk-1","body":{}}';
      final assembler = BleFrameAssembler();
      final out = <String>[];
      for (final chunk in encodeBleString(text, 180)) {
        out.addAll(assembler.feed(chunk).map(utf8.decode));
      }
      expect(out.single, text);
    });
  });
}
