/// The internet relay endpoint the app uses for multiplayer.
///
/// Injected at build/run time with:
///
///     flutter run --dart-define=RELAY_URL=wss://relay.example.com
///
/// The relay itself is in this repository (`tool/relay_server_main.dart`,
/// backed by [RelayServer]) and is deployed on any host that supports
/// WebSockets (see docs/multiplayer/m18-architecture.md §8). When empty,
/// hosting/joining over the internet is unavailable and the lobby shows a
/// clear configuration error instead of failing silently.
const String kDefaultRelayUrl = String.fromEnvironment('RELAY_URL');
