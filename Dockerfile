# syntax=docker/dockerfile:1

# Turtle King multiplayer relay — production container.
#
# Builds tool/relay_server_main.dart into a standalone AOT executable and
# runs it in a minimal runtime image. The relay stays a dumb WebSocket
# router: TLS terminates in front of it (Render provides HTTPS/WSS), and the
# process reads its port from the platform-standard PORT variable (Render
# injects this; RELAY_PORT or --port still win).

# ---- Build stage ----
# The relay is pure dart:io with zero external packages, so it is compiled
# with the Dart SDK alone (small, fast to pull). The Flutter app's pubspec
# (which declares `sdk: flutter`) is intentionally NOT used here; a minimal
# pubspec under the same package name resolves the relay's imports. If the
# relay ever imports a pub package, add it to this pubspec too.
FROM dart:stable AS build

WORKDIR /relay

# Relay sources (lib/multiplayer is the package's lib/ root).
COPY lib/multiplayer/ lib/multiplayer/
COPY tool/relay_server_main.dart tool/

# Minimal pubspec under the app's package name so `package:turtle_king/...`
# imports resolve; no Flutter SDK or app dependencies are needed.
RUN printf '%s\n' \
    'name: turtle_king' \
    'publish_to: none' \
    'environment:' \
    '  sdk: ">=3.0.0 <4.0.0"' > pubspec.yaml \
  && dart pub get \
  && mkdir -p /out \
  && dart compile exe tool/relay_server_main.dart -o /out/relay_server

# ---- Runtime stage ----
# Dart AOT executables link against glibc, so use a minimal glibc base.
FROM debian:stable-slim

# Run as an unprivileged user; the relay needs no filesystem access.
RUN useradd --create-home --uid 10001 relay
COPY --from=build /out/relay_server /usr/local/bin/relay_server

USER relay

# Render supplies a platform-chosen PORT; RELAY_PORT/--port override it.
# Bind 0.0.0.0 so the platform's health check can reach the relay.
ENV RELAY_BIND_ADDRESS=0.0.0.0
EXPOSE 8787

CMD ["/usr/local/bin/relay_server"]
