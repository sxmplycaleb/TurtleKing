import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/multiplayer/net_utils.dart';

/// A fake network interface for the pure selector.
LanInterface _iface(String name, List<String> addresses) =>
    LanInterface(name, addresses);

void main() {
  group('isValidIpv4', () {
    test('accepts valid dotted-quad addresses', () {
      expect(isValidIpv4('192.168.1.20'), isTrue);
      expect(isValidIpv4('127.0.0.1'), isTrue);
      expect(isValidIpv4('0.0.0.0'), isTrue);
      expect(isValidIpv4('255.255.255.255'), isTrue);
      expect(isValidIpv4('10.0.0.1'), isTrue);
      expect(isValidIpv4(' 192.168.1.20 '), isTrue, reason: 'trims whitespace');
    });

    test('rejects malformed addresses', () {
      expect(isValidIpv4(''), isFalse);
      expect(isValidIpv4('   '), isFalse);
      expect(isValidIpv4('192.168.1'), isFalse);
      expect(isValidIpv4('192.168.1.1.1'), isFalse);
      expect(isValidIpv4('192.168.1.999'), isFalse, reason: 'octet > 255');
      expect(isValidIpv4('192.168.1.-1'), isFalse);
      expect(isValidIpv4('a.b.c.d'), isFalse);
      expect(isValidIpv4('192.168.01.1'), isFalse, reason: 'no leading zeros');
      expect(
        isValidIpv4('192.168.1.1 '),
        isTrue,
        reason: 'surrounding whitespace is trimmed',
      );
      expect(isValidIpv4('fe80::1'), isFalse, reason: 'IPv6 is not accepted');
      expect(isValidIpv4('192.168.1.1a'), isFalse);
    });
  });

  group('isValidPort', () {
    test('accepts valid ports', () {
      expect(isValidPort('41321'), isTrue);
      expect(isValidPort('1'), isTrue);
      expect(isValidPort('65535'), isTrue);
      expect(isValidPort(' 8080 '), isTrue, reason: 'trims whitespace');
    });

    test('rejects invalid ports', () {
      expect(isValidPort(''), isFalse);
      expect(isValidPort('0'), isFalse);
      expect(isValidPort('65536'), isFalse);
      expect(isValidPort('-1'), isFalse);
      expect(isValidPort('abc'), isFalse);
      expect(isValidPort('80.5'), isFalse);
    });
  });

  group('selectLanIpv4Addresses', () {
    test('prefers the Wi-Fi interface over cellular', () {
      final result = selectLanIpv4Addresses([
        _iface('rmnet0', ['10.142.7.3']),
        _iface('wlan0', ['192.168.1.5']),
      ]);
      expect(result, ['192.168.1.5']);
    });

    test('prefers the Wi-Fi interface over VPN tunnels', () {
      final result = selectLanIpv4Addresses([
        _iface('tun0', ['10.8.0.2']),
        _iface('wlan0', ['192.168.1.5']),
      ]);
      expect(result, ['192.168.1.5']);
    });

    test('prefers Ethernet as a LAN interface', () {
      expect(
        selectLanIpv4Addresses([
          _iface('eth0', ['192.168.0.10']),
        ]),
        ['192.168.0.10'],
      );
      // Android-style Ethernet interface names are also accepted.
      expect(
        selectLanIpv4Addresses([
          _iface('enp0s3', ['10.0.0.4']),
        ]),
        ['10.0.0.4'],
      );
    });

    test('accepts a hotspot/softAP interface when it is the only LAN', () {
      expect(
        selectLanIpv4Addresses([
          _iface('ap0', ['192.168.43.1']),
        ]),
        ['192.168.43.1'],
      );
      expect(
        selectLanIpv4Addresses([
          _iface('softap0', ['192.168.43.1']),
        ]),
        ['192.168.43.1'],
      );
    });

    test('prefers station Wi-Fi over the hotspot interface', () {
      final result = selectLanIpv4Addresses([
        _iface('ap0', ['192.168.43.1']),
        _iface('wlan0', ['192.168.1.5']),
      ]);
      expect(result, ['192.168.1.5']);
    });

    test('never selects cellular even when it is the only interface', () {
      expect(
        selectLanIpv4Addresses([
          _iface('rmnet_data0', ['10.142.7.3']),
        ]),
        isEmpty,
      );
      expect(
        selectLanIpv4Addresses([
          _iface('ccmni0', ['10.142.7.3']),
        ]),
        isEmpty,
      );
      expect(
        selectLanIpv4Addresses([
          _iface('wwan0', ['10.142.7.3']),
        ]),
        isEmpty,
      );
    });

    test('never selects VPN, Bluetooth PAN, USB tethering, or virtual', () {
      expect(
        selectLanIpv4Addresses([
          _iface('tun0', ['10.8.0.2']),
        ]),
        isEmpty,
      );
      expect(
        selectLanIpv4Addresses([
          _iface('ppp0', ['10.8.0.2']),
        ]),
        isEmpty,
      );
      expect(
        selectLanIpv4Addresses([
          _iface('wg0', ['10.8.0.2']),
        ]),
        isEmpty,
      );
      expect(
        selectLanIpv4Addresses([
          _iface('bnep0', ['192.168.44.1']),
        ]),
        isEmpty,
      );
      expect(
        selectLanIpv4Addresses([
          _iface('rndis0', ['192.168.42.129']),
        ]),
        isEmpty,
      );
      expect(
        selectLanIpv4Addresses([
          _iface('dummy0', ['192.168.99.1']),
        ]),
        isEmpty,
      );
      expect(
        selectLanIpv4Addresses([
          _iface('docker0', ['172.17.0.1']),
        ]),
        isEmpty,
      );
    });

    test('drops loopback, link-local, and unspecified addresses', () {
      final result = selectLanIpv4Addresses([
        _iface('wlan0', [
          '127.0.0.1',
          '169.254.10.20',
          '0.0.0.0',
          '192.168.1.5',
        ]),
      ]);
      expect(result, ['192.168.1.5']);
    });

    test('accepts an unclassified name only as a last resort', () {
      expect(
        selectLanIpv4Addresses([
          _iface('foo0', ['192.168.1.9']),
        ]),
        ['192.168.1.9'],
      );
      // But it still loses to a real Wi-Fi interface when both exist.
      final result = selectLanIpv4Addresses([
        _iface('foo0', ['192.168.1.9']),
        _iface('wlan0', ['192.168.1.5']),
      ]);
      expect(result, ['192.168.1.5']);
    });

    test('returns an empty list for no interfaces or no usable ones', () {
      expect(selectLanIpv4Addresses(const []), isEmpty);
      expect(
        selectLanIpv4Addresses([
          _iface('wlan0', ['127.0.0.1']),
        ]),
        isEmpty,
      );
    });

    test('result is deterministic regardless of kernel enumeration order', () {
      final wlan = _iface('wlan0', ['192.168.1.5']);
      final eth = _iface('eth0', ['192.168.1.10']);
      final rmnet = _iface('rmnet0', ['10.142.7.3']);
      final first = selectLanIpv4Addresses([wlan, eth, rmnet]);
      final second = selectLanIpv4Addresses([rmnet, wlan, eth]);
      expect(first, second);
      // Addresses are string-sorted for stability; both orders above must
      // collapse to the same result.
      expect(first, ['192.168.1.10', '192.168.1.5']);
    });
  });

  group('localLanIpv4Addresses', () {
    test('never throws and never returns unusable addresses', () async {
      final addresses = await localLanIpv4Addresses();
      for (final address in addresses) {
        expect(isValidIpv4(address), isTrue);
        expect(address, isNot('127.0.0.1'));
        expect(
          address.startsWith('169.254.'),
          isFalse,
          reason: 'no link-local',
        );
        expect(address, isNot('0.0.0.0'));
      }
    });
  });
}
