import 'dart:io';

/// Whether [value] is a well-formed IPv4 address (dotted quad, 0–255).
bool isValidIpv4(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return false;
  final parts = trimmed.split('.');
  if (parts.length != 4) return false;
  for (final part in parts) {
    if (part.isEmpty || part.length > 3) return false;
    if (!RegExp(r'^[0-9]+$').hasMatch(part)) return false;
    // Reject leading zeros: '01' is ambiguous (octal in some parsers) and
    // is not how routers present addresses.
    if (part.length > 1 && part.startsWith('0')) return false;
    final octet = int.tryParse(part);
    if (octet == null || octet < 0 || octet > 255) return false;
  }
  return true;
}

/// Whether [value] is a valid TCP port (1–65535).
bool isValidPort(String value) {
  final port = int.tryParse(value.trim());
  return port != null && port >= 1 && port <= 65535;
}

/// Whether an interface named [name] must never be selected as the host's
/// LAN address.
///
/// These interfaces are not reachable by peer devices on the same
/// Wi-Fi/LAN, so advertising them in the QR payload would produce a join
/// that can never succeed:
///
/// * **Cellular / mobile data** — Android `rmnet*`, `ccmni*`, `wwan*`,
///   `pdp*` (plus vendor variants). Peers are not on the carrier network.
/// * **VPN / tunnel** — `tun*`, `tap*`, `ppp*`, `wg*`, `ipsec*`, `sit*`,
///   `vpn*`, `gre*`. A VPN address is not the device's LAN address.
/// * **Bluetooth PAN** — `bt*`, `bnep*`, `pan*`.
/// * **USB tethering** — `rndis*`, `usb*`, `ncm*`, `ecm*`: a point-to-point
///   link to a single host, not a LAN other devices can join.
/// * **Virtual/container** — `dummy*`, `virbr*`, `docker*`, `veth*`,
///   `br-*`, and loopback (`lo*`).
bool isExcludedInterface(String name) {
  final n = name.toLowerCase();
  // Cellular / mobile data.
  if (n.startsWith('rmnet') ||
      n.startsWith('ccmni') ||
      n.startsWith('wwan') ||
      n.startsWith('pdp') ||
      n.startsWith('uwb') ||
      n.startsWith('mhi') ||
      n.contains('cellular') ||
      n.contains('radio')) {
    return true;
  }
  // VPN / tunnel.
  if (n.startsWith('tun') ||
      n.startsWith('tap') ||
      n.startsWith('ppp') ||
      n.startsWith('wg') ||
      n.startsWith('ipsec') ||
      n.startsWith('ip6tnl') ||
      n.startsWith('sit') ||
      n.startsWith('vpn') ||
      n.startsWith('gre')) {
    return true;
  }
  // Bluetooth PAN.
  if (n.startsWith('bt') || n.startsWith('bnep') || n.startsWith('pan')) {
    return true;
  }
  // USB tethering.
  if (n.startsWith('rndis') ||
      n.startsWith('usb') ||
      n.startsWith('ncm') ||
      n.startsWith('ecm')) {
    return true;
  }
  // Virtual / dummy / container / loopback.
  if (n.startsWith('dummy') ||
      n.startsWith('virbr') ||
      n.startsWith('docker') ||
      n.startsWith('veth') ||
      n.startsWith('br-') ||
      n.startsWith('lo')) {
    return true;
  }
  return false;
}

/// Ranks an interface [name] by how likely it is the LAN that peer
/// devices should connect through. Higher is better; excluded interfaces
/// (see [isExcludedInterface]) never reach this function.
int lanInterfaceScore(String name) {
  final n = name.toLowerCase();
  // Wi-Fi station and wired Ethernet are the primary LAN interfaces
  // (Android `wlan*`/`swlan*`, Linux `wlp*`/`enp*`, Windows `Wi-Fi`/
  // `Ethernet`, macOS `en0`).
  if (n.startsWith('wlan') ||
      n.startsWith('swlan') ||
      n.startsWith('wifi') ||
      n.startsWith('wl') ||
      n.startsWith('eth') ||
      n.startsWith('en')) {
    return 4;
  }
  // Wi-Fi hotspot / softAP: the device itself is the access point, so
  // joined peers connect through this interface.
  if (n.startsWith('softap') || n.startsWith('ap')) {
    return 3;
  }
  // Anything unclassified (e.g. Windows "Local Area Connection") is a
  // last resort — still preferred over advertising nothing.
  return 1;
}

/// A minimal, testable snapshot of one network interface, as needed for
/// LAN address selection.
///
/// The pure selector operates on this projection rather than dart:io's
/// [NetworkInterface] (which is abstract and cannot be constructed in
/// tests); [localLanIpv4Addresses] builds it from the real enumeration.
class LanInterface {
  const LanInterface(this.name, this.addresses);

  final String name;
  final List<String> addresses;
}

/// Deterministically selects the IPv4 addresses most likely to be the
/// device's current LAN address, given every interface the OS reports.
///
/// Interfaces are grouped by [lanInterfaceScore]; the best-scoring group
/// with any usable addresses wins. Within a group, addresses are sorted so
/// the result is stable regardless of kernel enumeration order (the previous
/// implementation used the raw first address, which on Android can be a
/// cellular, VPN, or virtual interface).
///
/// Loopback, link-local (169.254/16), and unspecified (0.0.0.0) addresses
/// are dropped, as are interfaces rejected by [isExcludedInterface].
///
/// Returns an empty list when nothing suitable exists — the caller then
/// falls back to manual host-IP entry, which remains always available.
List<String> selectLanIpv4Addresses(List<LanInterface> interfaces) {
  final byScore = <int, Set<String>>{};
  for (final interface in interfaces) {
    if (isExcludedInterface(interface.name)) continue;
    final score = lanInterfaceScore(interface.name);
    final bucket = byScore.putIfAbsent(score, () => <String>{});
    for (final address in interface.addresses) {
      if (address == '127.0.0.1') continue;
      if (address.startsWith('169.254.')) continue;
      if (address == '0.0.0.0') continue;
      bucket.add(address);
    }
  }
  for (final score in const [4, 3, 1]) {
    final bucket = byScore[score];
    if (bucket != null && bucket.isNotEmpty) {
      return bucket.toList()..sort();
    }
  }
  return const [];
}

/// The device's LAN IPv4 addresses (Wi-Fi/Ethernet first, deterministic).
///
/// Best-effort: returns an empty list when the network cannot be enumerated
/// (e.g. no interfaces) or when no suitable interface exists, never throws.
Future<List<String>> localLanIpv4Addresses() async {
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    return selectLanIpv4Addresses([
      for (final interface in interfaces)
        LanInterface(interface.name, [
          for (final address in interface.addresses) address.address,
        ]),
    ]);
  } catch (_) {
    return const [];
  }
}
