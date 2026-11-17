/// The Lumide plugin: tracks what the user is doing and shows it on Discord.
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:lumide_api/lumide_api.dart';
import 'package:path/path.dart' as p;

import 'activity.dart';
import 'discord_link.dart';
import 'menu.dart';
import 'projects.dart';
import 'settings.dart';

class DiscordPresencePlugin extends LumidePlugin {
  DiscordPresencePlugin({DiscordLink Function(DiscordPresencePlugin)? link})
      : _createLink = link;

  static const _statusItem = 'discord';
  static const menuCommand = 'discordPresence.menu';
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

  /// The Discord icon for the status bar; `null` shows text instead.
  String? _iconPath;

  PresenceSettings _settings = const PresenceSettings();
  final DateTime _sessionStart = DateTime.now();
  DateTime _lastActivity = DateTime.now();
  bool _idle = false;
  String? _filePath;
  bool _editing = false;
  String? _projectName;
  String? _projectPath;
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

    _iconPath = await _findIcon();
    await context.statusBar.createItem(
      id: _statusItem,
      text: _iconPath == null ? 'Discord' : '',
      tooltip: 'Discord Presence',
      command: menuCommand,
      iconPath: _iconPath,
      alignment: 'right',
    );
    await context.commands.registerCommand(
      id: menuCommand,
      title: 'Discord Presence: Show Menu',
      category: 'Discord Presence',
      callback: ([args]) => _guard(() => _showMenu(args)),
    );
    await context.commands.registerCommand(
      id: toggleCommand,
      title: 'Discord Presence: Turn On/Off',
      category: 'Discord Presence',
      callback: ([_]) => _flip(MenuAction.toggle),
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
      callback: ([_]) => _flip(MenuAction.privacyMode),
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
    _projectFilter = _settings.projectFilter;
    _updateExcluded();

    if (!_settings.enabled) {
      await _link.stop();
    } else if (_link.state == LinkState.off ||
        previous.applicationId != _settings.applicationId) {
      await _link.start(_settings.applicationId);
    }
    _showPresence();
    await _updateStatusBar();
  }

  /// Turns the on/off setting behind [action] around.
  Future<void> _flip(MenuAction action) async {
    final setting = settingOf(action, _settings);
    if (setting == null) return;
    await _context.workspace.updateConfiguration(setting.$1, !setting.$2);
    await _reloadSettings();
  }

  /// The menu from the status bar icon, opened where it was clicked.
  Future<void> _showMenu(Map<String, dynamic>? args) async {
    final position = _positionOf(args);
    final selected = await _context.window.showQuickPick(
      menuItems(
        settings: _settings,
        linkState: _link.state,
        projectName: _projectName,
        projectState: _projectState,
      ),
      placeholder: 'Discord Presence',
      position: position,
    );
    final action = MenuAction.values.asNameMap()[_payloadOf(selected)];
    switch (action) {
      case null:
        return;
      case MenuAction.reconnect:
        await _link.reconnectNow();
      case MenuAction.project:
        await _toggleProject();
      case MenuAction.excludedProjects:
        await _editProjects(
          PresenceSettings.excludedProjectsKey,
          () => _settings.excludedProjects,
          'Excluded Projects',
          position,
        );
      case MenuAction.includedProjects:
        await _editProjects(
          PresenceSettings.includedProjectsKey,
          () => _settings.includedProjects,
          'Included Projects',
          position,
        );
      default:
        await _flip(action);
    }
  }

  /// Lumide answers a quick pick with the picked payload; older hosts with
  /// the whole item.
  static Object? _payloadOf(QuickPickItem? selected) =>
      switch (selected?.payload) {
        final Map item => item['payload'],
        final other => other,
      };

  /// The menu for a project list ([key]): add folders with the folder
  /// picker or patterns by typing, or remove entries. It opens again after
  /// each change, until dismissed.
  Future<void> _editProjects(String key, List<String> Function() entries,
      String title, Map<String, int>? position) async {
    while (!_deactivated) {
      final current = entries();
      final selected = await _context.window.showQuickPick(
        projectListItems(current),
        placeholder: title,
        position: position,
      );
      final List<String> updated;
      switch (ListAction.of(_payloadOf(selected))) {
        case null:
          return;
        case AddFolder():
          final folder = await _context.window.showOpenFolderDialog(
            title: '$title: Add Folder',
            defaultPath: _projectPath == null ? null : p.dirname(_projectPath!),
          );
          if (folder == null || folder.isEmpty) continue;
          updated = addEntry(current, folder);
        case AddPattern():
          final pattern = await _context.window.showInputBox(
            title: '$title: Add Pattern',
            prompt: 'A folder path, a glob or a project name',
            placeHolder: r'D:/work/**   **/clients/*   company_app',
          );
          if (pattern == null) continue;
          updated = addEntry(current, pattern);
        case RemoveEntry(:final index):
          if (index < 0 || index >= current.length) continue;
          updated = [...current]..removeAt(index);
      }
      if (!identical(updated, current)) {
        await _context.workspace.updateConfiguration(key, joinList(updated));
        await _reloadSettings();
      }
    }
  }

  ProjectState get _projectState {
    if (!_isExcluded) return ProjectState.shown;
    final path = _projectPath;
    final byMenu = path != null &&
        _settings.excludedProjects
            .any((entry) => ProjectPattern(entry).isFolder(path));
    return byMenu ? ProjectState.hiddenByMenu : ProjectState.hiddenBySettings;
  }

  /// Adds the current project's folder to the exclude list, or removes it.
  Future<void> _toggleProject() async {
    final path = _projectPath;
    if (path == null) return;
    final entries = [..._settings.excludedProjects];
    final before = entries.length;
    entries.removeWhere((entry) => ProjectPattern(entry).isFolder(path));
    if (entries.length == before) entries.add(path);
    await _context.workspace.updateConfiguration(
        PresenceSettings.excludedProjectsKey, joinList(entries));
    await _reloadSettings();
  }

  /// The exclude and include lists, parsed once per settings change.
  ProjectFilter _projectFilter = ProjectFilter();

  /// Whether the current project is excluded. It only changes with the open
  /// file or the settings, so it is worked out then, not on every keystroke.
  bool _isExcluded = false;

  void _updateExcluded() {
    _isExcluded = _projectFilter.isExcluded(
      projectPath: _projectPath,
      projectName: _projectName,
      filePath: _filePath,
    );
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
    final wasExcluded = _isExcluded;
    if (uri != null) await _loadProject(uri);
    _updateExcluded();
    _onActivity();
    if (_isExcluded != wasExcluded) await _updateStatusBar();
  }

  /// The workspace folder holding [uri], and whether it is a Flutter
  /// project (its pubspec.yaml depends on the Flutter SDK).
  Future<void> _loadProject(String uri) async {
    final folder = await _context.workspace.getWorkspaceFolder(uri);
    if (folder == null) return;
    _projectName = folder.name;
    _projectPath = _pathOf(folder.uri);
    _flutterProject = _flutterByFolder[folder.uri] ??=
        await _isFlutterProject(_projectPath);
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
        excluded: _isExcluded,
      ),
      _settings,
    ));
  }

  Future<void> _updateStatusBar() async {
    if (_deactivated) return;
    final hidden = _settings.privacyMode
        ? ' Privacy mode: file and project names are hidden.'
        : _isExcluded
            ? _settings.hideExcludedProjects
                ? ' This project is hidden from Discord.'
                : ' File and project names of this project are hidden.'
            : '';
    final (label, tooltip, color) = switch (_link.state) {
      _ when !_settings.enabled => (
          'Discord: off',
          'Discord Presence is off.',
          '#8A8A8A',
        ),
      LinkState.connected => (
          _settings.privacyMode ? 'Discord: private' : 'Discord',
          'Showing your activity on Discord.$hidden',
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
              '${_link.retryDelay.inSeconds} s.',
          '#8A8A8A',
        ),
    };
    await _guard(() => _context.statusBar.updateItem(
          _statusItem,
          text: _iconPath == null ? label : '',
          tooltip: '$tooltip Click for options.',
          color: color,
        ));
  }

  /// The Discord icon shipped with the plugin, wherever it is installed.
  static Future<String?> _findIcon() async {
    const asset = 'assets/icon_discord.svg';
    final candidates = <String>[];
    try {
      final library = await Isolate.resolvePackageUri(
          Uri.parse('package:lumide_discord/lumide_discord.dart'));
      if (library != null && library.isScheme('file')) {
        candidates.add(p.join(p.dirname(p.dirname(library.toFilePath())), asset));
      }
    } catch (_) {
      // No package config; try next to the script instead.
    }
    candidates
      ..add(p.join(p.dirname(Platform.script.toFilePath()), '..', asset))
      ..add(p.join(Directory.current.path, asset));
    for (final candidate in candidates) {
      final path = p.normalize(candidate);
      if (await File(path).exists()) return path;
    }
    return null;
  }

  /// Where the status bar item was clicked, to open the menu there.
  static Map<String, int>? _positionOf(Map<String, dynamic>? args) {
    final position = args?['position'];
    if (position is! Map) return null;
    final (x, y) = (position['x'], position['y']);
    if (x is! num || y is! num) return null;
    return {'x': x.toInt(), 'y': y.toInt()};
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
