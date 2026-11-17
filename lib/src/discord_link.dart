/// Keeps a connection to the Discord app and sends the presence to it.
library;

import 'dart:async';

import 'package:dart_discord_presence/dart_discord_presence.dart';

import 'activity.dart';

/// The connection's state, shown in the status bar.
enum LinkState {
  /// Not started (turned off, or no application ID).
  off,

  /// Connecting to Discord.
  connecting,

  /// Connected; the presence is shown.
  connected,

  /// Discord isn't running or the connection was lost; retrying.
  waiting,
}

/// The calls made to Discord. [RpcPresenceClient] talks to the Discord app;
/// tests use a fake.
abstract interface class PresenceClient {
  /// Connects; throws when Discord isn't running.
  Future<void> connect(String applicationId);

  Future<void> show(PresenceContent content);

  Future<void> clear();

  /// Fires once when the connection is lost.
  Stream<void> get lost;

  Future<void> close();
}

/// The Lumide logo, in the small circle next to the large image or, when
/// there is none, as the large image.
const lumideAsset = DiscordAsset.fromKey('lumide', text: 'Lumide');

/// Discord always shows a timer: without a start time it counts from when
/// the status last changed. A start this far ahead keeps it at 0:00, which
/// is as close to no timer as Discord allows.
const hiddenTimerLead = Duration(days: 365);

/// [content] as Discord presence: the language (or idle or debugging) as
/// the large image with the Lumide logo in the small circle, like the
/// editor extensions for VS Code. Without a start time, the timer stays at
/// 0:00 (see [hiddenTimerLead]); [now] is for tests.
DiscordPresence discordPresenceOf(PresenceContent content, {DateTime? now}) {
  final started =
      content.startedAt ?? (now ?? DateTime.now()).add(hiddenTimerLead);
  final image = content.imageKey;
  return DiscordPresence(
    details: content.details,
    state: content.state,
    timestamps: DiscordTimestamps.started(started),
    largeAsset: image == null
        ? lumideAsset
        : DiscordAsset.fromKey(image, text: content.imageText),
    smallAsset: image == null ? null : lumideAsset,
    buttons: content.buttons.isEmpty
        ? null
        : [
            for (final button in content.buttons.take(2))
              DiscordButton(label: button.label, url: button.url),
          ],
  );
}

/// [PresenceClient] for the Discord app, through its local connection
/// (named pipe on Windows, Unix socket on macOS and Linux).
class RpcPresenceClient implements PresenceClient {
  final DiscordRPC _rpc = DiscordRPC();

  @override
  Future<void> connect(String applicationId) => _rpc.initialize(applicationId);

  @override
  Future<void> show(PresenceContent content) =>
      _rpc.setPresence(discordPresenceOf(content));

  @override
  Future<void> clear() => _rpc.clearPresence();

  @override
  Stream<void> get lost => _rpc.onDisconnected;

  @override
  Future<void> close() => _rpc.dispose();
}

/// Connects to Discord, reconnects when Discord starts or restarts, and
/// sends the latest presence without exceeding Discord's rate limit.
class DiscordLink {
  DiscordLink({
    PresenceClient Function()? clientFactory,
    this.retryDelay = const Duration(seconds: 20),
    this.connectTimeout = const Duration(seconds: 10),
    this.minUpdateInterval = const Duration(seconds: 4),
    void Function(String message)? log,
    this.onStateChanged,
  })  : _clientFactory = clientFactory ?? RpcPresenceClient.new,
        _log = log ?? ((_) {});

  final PresenceClient Function() _clientFactory;
  final void Function(String message) _log;

  /// How long to wait before trying to connect again.
  final Duration retryDelay;

  /// How long a connection attempt may take. Discord sometimes accepts the
  /// connection but never answers (while starting, for example), and the
  /// library would wait forever.
  final Duration connectTimeout;

  /// Discord accepts about 5 updates per 20 s; changes in between are
  /// merged and the latest one is sent.
  final Duration minUpdateInterval;

  final void Function(LinkState state)? onStateChanged;

  String? _applicationId;
  PresenceClient? _client;

  /// Bumped by [stop]: a connection attempt from before then is dropped.
  int _generation = 0;
  bool _connecting = false;
  StreamSubscription<void>? _lostSubscription;
  Timer? _retryTimer;
  Timer? _sendTimer;

  PresenceContent? _wanted;
  bool _hasWanted = false;
  PresenceContent? _sent;
  bool _hasSent = false;
  DateTime? _lastSend;

  LinkState _state = LinkState.off;
  LinkState get state => _state;

  /// Starts (or restarts) the connection for [applicationId].
  Future<void> start(String applicationId) async {
    await stop();
    _applicationId = applicationId;
    await _connect();
  }

  /// Clears the presence and disconnects.
  Future<void> stop() async {
    _generation++;
    _applicationId = null;
    _connecting = false;
    _retryTimer?.cancel();
    _sendTimer?.cancel();
    final client = _client;
    _client = null;
    await _lostSubscription?.cancel();
    _lostSubscription = null;
    if (client != null) {
      try {
        await client.clear();
      } catch (_) {
        // Already gone.
      }
      await _closeQuietly(client);
    }
    _hasSent = false;
    _setState(LinkState.off);
  }

  /// Shows [content] on Discord, or clears the presence when `null`.
  void show(PresenceContent? content) {
    _wanted = content;
    _hasWanted = true;
    _scheduleSend();
  }

  /// Tries to connect now instead of waiting for the next retry.
  Future<void> reconnectNow() async {
    if (_client != null || _connecting || _applicationId == null) return;
    _retryTimer?.cancel();
    await _connect();
  }

  Future<void> _connect() async {
    final applicationId = _applicationId;
    if (applicationId == null || _client != null || _connecting) return;
    final generation = _generation;
    _connecting = true;
    _setState(LinkState.connecting);
    final client = _clientFactory();
    try {
      await client.connect(applicationId).timeout(connectTimeout);
    } catch (error) {
      await _closeQuietly(client);
      if (generation != _generation) return; // Stopped meanwhile.
      _connecting = false;
      _log('Discord not reachable ($error); retrying in '
          '${retryDelay.inSeconds} s.');
      _setState(LinkState.waiting);
      _retryTimer = Timer(retryDelay, _connect);
      return;
    }
    if (generation != _generation) {
      await _closeQuietly(client); // Stopped meanwhile.
      return;
    }
    _connecting = false;
    _client = client;
    _hasSent = false;
    _lostSubscription = client.lost.listen((_) => _onLost(client));
    _setState(LinkState.connected);
    _scheduleSend();
  }

  void _onLost(PresenceClient client) {
    if (_client != client) return;
    _client = null;
    _sendTimer?.cancel();
    unawaited(_lostSubscription?.cancel());
    _lostSubscription = null;
    unawaited(_closeQuietly(client));
    if (_applicationId == null) return;
    _log('Lost the connection to Discord; retrying in '
        '${retryDelay.inSeconds} s.');
    _setState(LinkState.waiting);
    _retryTimer?.cancel();
    _retryTimer = Timer(retryDelay, _connect);
  }

  void _scheduleSend() {
    if (_client == null || !_hasWanted) return;
    if (_sendTimer?.isActive ?? false) return; // Sends the latest then.
    final last = _lastSend;
    final wait = last == null
        ? Duration.zero
        : minUpdateInterval - DateTime.now().difference(last);
    if (wait <= Duration.zero) {
      unawaited(_send());
    } else {
      _sendTimer = Timer(wait, _send);
    }
  }

  Future<void> _send() async {
    final client = _client;
    if (client == null || !_hasWanted) return;
    final content = _wanted;
    if (_hasSent && content == _sent) return;
    _lastSend = DateTime.now();
    try {
      if (content == null) {
        await client.clear();
      } else {
        await client.show(content);
      }
      _sent = content;
      _hasSent = true;
    } catch (error) {
      _log('Could not update the Discord presence: $error');
      _onLost(client);
      return;
    }
    if (_wanted != content) _scheduleSend(); // Changed while sending.
  }

  void _setState(LinkState state) {
    if (_state == state) return;
    _state = state;
    onStateChanged?.call(state);
  }

  static Future<void> _closeQuietly(PresenceClient client) async {
    try {
      await client.close();
    } catch (_) {
      // Nothing left to release.
    }
  }
}
