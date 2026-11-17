/// The Lumide plugin: tracks what the user is doing and shows it on Discord.
library;

import 'dart:async';
import 'dart:io';

import 'package:lumide_api/lumide_api.dart';
import 'package:path/path.dart' as p;

import 'activity.dart';
import 'discord_link.dart';
import 'settings.dart';

class DiscordPresencePlugin extends LumidePlugin {
  DiscordPresencePlugin({DiscordLink Function(DiscordPresencePlugin)? link})
      : _createLink = link;

  static const _statusItem = 'discord';
  static const toggleCommand = 'discordPresence.toggle';
  static const reconnectCommand = 'discordPresence.reconnect';
  static const privacyCommand = 'discordPresence.togglePrivacy';

  final DiscordLink Function(DiscordPresencePlugin)? _createLink;
  late final LumideContext _context;
  // Set first thing in onActivate; onDeactivate can come before that.
  DiscordLink? _linkOrNull;
  DiscordLink get _link => _linkOrNull!;
  final _subscriptions = <LumideDisposable>[];
  Timer? _idleTimer;

  PresenceSettings _settings = const PresenceSettings();
  final DateTime _sessionStart = DateTime.now();
  DateTime _lastActivity = DateTime.now();
  bool _idle = false;
  String? _filePath;
  bool _editing = false;
  String? _projectName;
  bool _flutterProject = false;
  final _flutterByFolder = <String, bool>{};

  /// Lumide is stopping the plugin; the status bar item is going away.
  bool _deactivated = false;

  /// Runs and debug sessions started from Run and Debug, by launch.
  final _launches = <String, LumideLaunchKind>{};

  @override
  Future<void> onActivate(LumideContext context) async {
    _context = context;
    _linkOrNull = _createLink?.call(this) ??
        DiscordLink(log: log, onStateChanged: (_) => _updateStatusBar());

    await context.statusBar.createItem(
      id: _statusItem,
      text: 'Discord',
      command: toggleCommand,
      alignment: 'right',
    );
    await context.commands.registerCommand(
      id: toggleCommand,
      title: 'Discord Presence: Turn On/Off',
      category: 'Discord Presence',
      callback: ([_]) => _toggle(),
    );
    await context.commands.registerCommand(
      id: reconnectCommand,
      title: 'Discord Presence: Reconnect',
      category: 'Discord Presence',
      callback: ([_]) => _link.reconnectNow(),
    );
    await context.commands.registerCommand(
      id: privacyCommand,
      title: 'Discord Presence: Turn Privacy Mode On/Off',
      category: 'Discord Presence',
      callback: ([_]) => _togglePrivacy(),
    );

    _subscriptions
      ..add(context.editor.onDidChangeActiveDocument(
          (uri) => _guard(() => _onActiveDocument(uri))))
      ..add(context.workspace.onDidChangeTextDocument((event) {
        if (_pathOf(event.uri) == _filePath) _editing = true;
        _onActivity();
      }))
      ..add(context.editor.onDidChangeSelections((_) => _onActivity()))
      ..add(context.launch.onDidStart((event) {
        _launches[_launchId(event)] = event.kind;
        _onActivity();
      }))
      ..add(context.launch.onDidEnd((event) {
        _launches.remove(_launchId(event));
        _onActivity();
      }))
      ..add(context.workspace
          .onDidChangeConfiguration((_) => _reloadSettings()));

    _idleTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _checkIdle());

    await _guard(() async =>
        _onActiveDocument(await context.editor.getActiveDocumentUri()));
    await _reloadSettings();
  }

  @override
  Future<void> onDeactivate() async {
    _deactivated = true;
    _idleTimer?.cancel();
    for (final subscription in _subscriptions) {
      subscription.dispose();
    }
    _subscriptions.clear();
    await _linkOrNull?.stop();
  }

  /// The latest settings reload; reloads run one after another, so a
  /// command and the change it causes don't both start a connection.
  Future<void> _reloading = Future.value();

  Future<void> _reloadSettings() =>
      _reloading = _reloading.then((_) => _guard(_applySettings));

  Future<void> _applySettings() async {
    final values = <String, Object?>{
      for (final key in PresenceSettings.keys)
        key: await _context.workspace.getConfiguration(key),
    };
    final previous = _settings;
    _settings = PresenceSettings.fromValues(values);

    if (!_settings.enabled) {
      await _link.stop();
    } else if (_link.state == LinkState.off ||
        previous.applicationId != _settings.applicationId) {
      await _link.start(_settings.applicationId);
    }
    _showPresence();
    await _updateStatusBar();
  }

  Future<void> _toggle() async {
    await _context.workspace
        .updateConfiguration(PresenceSettings.enabledKey, !_settings.enabled);
    await _reloadSettings();
  }

  Future<void> _togglePrivacy() async {
    await _context.workspace.updateConfiguration(
        PresenceSettings.privacyModeKey, !_settings.privacyMode);
    await _reloadSettings();
  }

  static String _launchId(LumideLaunchEvent event) =>
      '${event.providerId}/${event.configurationId}/${event.deviceId}';

  /// Debugging wins over testing, testing over running.
  RunMode get _runMode {
    final kinds = _launches.values;
    if (kinds.any((kind) =>
        kind == LumideLaunchKind.debug || kind == LumideLaunchKind.attach)) {
      return RunMode.debugging;
    }
    if (kinds.contains(LumideLaunchKind.test)) return RunMode.testing;
    return kinds.isEmpty ? RunMode.none : RunMode.running;
  }

  Future<void> _onActiveDocument(String? uri) async {
    final path = _pathOf(uri);
    if (path != _filePath) _editing = false;
    _filePath = path;
    if (uri != null) await _loadProject(uri);
    _onActivity();
  }

  /// The workspace folder holding [uri], and whether it is a Flutter
  /// project (its pubspec.yaml depends on the Flutter SDK).
  Future<void> _loadProject(String uri) async {
    final folder = await _context.workspace.getWorkspaceFolder(uri);
    if (folder == null) return;
    _projectName = folder.name;
    _flutterProject = _flutterByFolder[folder.uri] ??=
        await _isFlutterProject(_pathOf(folder.uri));
  }

  Future<bool> _isFlutterProject(String? folder) async {
    if (folder == null) return false;
    try {
      final pubspec =
          await _context.fs.readString(p.join(folder, 'pubspec.yaml'));
      return RegExp(r'sdk:\s*flutter\b').hasMatch(pubspec);
    } catch (_) {
      return false; // No pubspec.yaml, or not readable.
    }
  }

  void _onActivity() {
    _lastActivity = DateTime.now();
    _idle = false;
    _showPresence();
  }

  void _checkIdle() {
    final minutes = _settings.idleMinutes;
    if (minutes == 0 || _idle) return;
    if (DateTime.now().difference(_lastActivity).inMinutes >= minutes) {
      _idle = true;
      _showPresence();
    }
  }

  void _showPresence() {
    if (!_settings.enabled) return;
    _link.show(presenceFor(
      Activity(
        sessionStart: _sessionStart,
        filePath: _filePath,
        editing: _editing,
        projectName: _projectName,
        flutterProject: _flutterProject,
        idle: _idle,
        runMode: _runMode,
      ),
      _settings,
    ));
  }

  Future<void> _updateStatusBar() async {
    if (_deactivated) return;
    final (text, tooltip, color) = switch (_link.state) {
      _ when !_settings.enabled => (
          'Discord: off',
          'Discord Presence is off. Click to turn it on.',
          '#8A8A8A',
        ),
      LinkState.connected when _settings.privacyMode => (
          'Discord: private',
          'Showing your activity on Discord without file and project '
              'names (privacy mode). Click to turn it off.',
          '#5865F2',
        ),
      LinkState.connected => (
          'Discord',
          'Showing your activity on Discord. Click to turn it off.',
          '#5865F2',
        ),
      LinkState.connecting => (
          'Discord…',
          'Connecting to Discord.',
          '#8A8A8A',
        ),
      LinkState.waiting || LinkState.off => (
          'Discord: waiting',
          'Discord isn\'t running. Retrying every '
              '${_link.retryDelay.inSeconds} s. Click to turn it off.',
          '#8A8A8A',
        ),
    };
    await _guard(() => _context.statusBar
        .updateItem(_statusItem, text: text, tooltip: tooltip, color: color));
  }

  /// A file path for a `file:` URI or a plain path; `null` for none.
  static String? _pathOf(String? uri) {
    if (uri == null || uri.isEmpty) return null;
    if (uri.startsWith('file:')) {
      return Uri.parse(uri).toFilePath(windows: Platform.isWindows);
    }
    return uri;
  }

  /// Runs [action], logging instead of crashing the plugin on errors.
  Future<void> _guard(FutureOr<void> Function() action) async {
    try {
      await action();
    } catch (error, stackTrace) {
      log('Discord Presence: $error\n$stackTrace');
    }
  }
}
