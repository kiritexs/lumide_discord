/// The menu that opens from the Discord icon in the status bar.
library;

import 'package:lumide_api/lumide_api.dart';

import 'discord_link.dart';
import 'settings.dart';

/// What a menu item does when picked; its [QuickPickItem.payload].
enum MenuAction {
  toggle,
  privacyMode,
  project,
  excludedProjects,
  includedProjects,
  showFileName,
  showProjectName,
  showLanguage,
  showElapsedTime,
  showButtons,
  reconnect,
}

/// Why the current project's names are hidden, if they are.
enum ProjectState {
  /// Shown on Discord.
  shown,

  /// Hidden from the menu: its folder is on the exclude list.
  hiddenByMenu,

  /// Hidden by a pattern or name in the settings, or by the include list;
  /// changed in the settings only.
  hiddenBySettings,
}

/// The menu's items for the plugin's current state.
List<QuickPickItem> menuItems({
  required PresenceSettings settings,
  required LinkState linkState,
  String? projectName,
  ProjectState projectState = ProjectState.shown,
}) {
  QuickPickItem toggle(MenuAction action, String label, bool on,
          {String? tooltip}) =>
      QuickPickItem(
        label: label,
        description: on ? 'On' : 'Off',
        icon: on ? 'check' : null,
        payload: action.name,
        tooltip: tooltip,
      );
  const separator = QuickPickItem(label: '', isSeparator: true);

  final status = switch (linkState) {
    _ when !settings.enabled => 'Turned off',
    LinkState.connected => 'Showing your activity on Discord',
    LinkState.connecting => 'Connecting to Discord…',
    LinkState.waiting || LinkState.off => "Waiting for Discord to start",
  };

  return [
    QuickPickItem(label: status, enabled: false),
    separator,
    QuickPickItem(
      label: settings.enabled ? 'Turn Off' : 'Turn On',
      icon: 'power',
      payload: MenuAction.toggle.name,
    ),
    toggle(MenuAction.privacyMode, 'Privacy Mode', settings.privacyMode,
        tooltip: 'Hide file and project names in every project.'),
    if (projectName != null)
      switch (projectState) {
        ProjectState.shown => QuickPickItem(
            label: 'Hide "$projectName"',
            detail: 'Keep this project\'s file and project names off Discord',
            icon: 'eye-off',
            payload: MenuAction.project.name,
          ),
        ProjectState.hiddenByMenu => QuickPickItem(
            label: 'Show "$projectName"',
            detail: 'This project is hidden; show its names again',
            icon: 'eye',
            payload: MenuAction.project.name,
          ),
        ProjectState.hiddenBySettings => QuickPickItem(
            label: '"$projectName" is hidden',
            detail: 'By the excluded or included projects in Settings',
            icon: 'eye-off',
            enabled: false,
          ),
      },
    QuickPickItem(
      label: 'Excluded Projects…',
      description: _count(settings.excludedProjects),
      detail: 'Projects whose names stay off Discord',
      icon: 'folder-x',
      payload: MenuAction.excludedProjects.name,
    ),
    QuickPickItem(
      label: 'Included Projects…',
      description: _count(settings.includedProjects),
      detail: 'When set, only these projects show their names',
      icon: 'folder-check',
      payload: MenuAction.includedProjects.name,
    ),
    separator,
    toggle(MenuAction.showFileName, 'Show File Name', settings.showFileName),
    toggle(MenuAction.showProjectName, 'Show Project Name',
        settings.showProjectName),
    toggle(MenuAction.showLanguage, 'Show Language', settings.showLanguage),
    toggle(MenuAction.showElapsedTime, 'Show Elapsed Time',
        settings.showElapsedTime),
    toggle(MenuAction.showButtons, 'Show Buttons', settings.showButtons),
    if (settings.enabled && linkState != LinkState.connected) ...[
      separator,
      QuickPickItem(
        label: 'Reconnect',
        detail: 'Try to connect to Discord now',
        icon: 'refresh-cw',
        payload: MenuAction.reconnect.name,
      ),
    ],
  ];
}

String _count(List<String> entries) =>
    entries.isEmpty ? 'None' : '${entries.length}';

/// What an item of a project list menu does: add a folder or a pattern, or
/// remove the entry at [index].
sealed class ListAction {
  const ListAction();

  /// The action for a picked item's payload, or `null` for none.
  static ListAction? of(Object? payload) => switch (payload) {
        'addFolder' => const AddFolder(),
        'addPattern' => const AddPattern(),
        final String p when p.startsWith('remove:') =>
          switch (int.tryParse(p.substring('remove:'.length))) {
            final int index => RemoveEntry(index),
            null => null,
          },
        _ => null,
      };
}

class AddFolder extends ListAction {
  const AddFolder();
}

class AddPattern extends ListAction {
  const AddPattern();
}

class RemoveEntry extends ListAction {
  const RemoveEntry(this.index);
  final int index;
}

/// The menu for the excluded or included projects: add a folder with the
/// folder picker, add a pattern, or click an entry to remove it.
List<QuickPickItem> projectListItems(List<String> entries) => [
      const QuickPickItem(
        label: 'Add Folder…',
        detail: 'Choose a project folder',
        icon: 'folder-plus',
        payload: 'addFolder',
      ),
      const QuickPickItem(
        label: 'Add Pattern…',
        detail: r'A glob or project name, e.g. D:/work/** or company_app',
        icon: 'plus',
        payload: 'addPattern',
      ),
      if (entries.isNotEmpty) const QuickPickItem(label: '', isSeparator: true),
      for (final (index, entry) in entries.indexed)
        QuickPickItem(
          label: entry,
          detail: 'Click to remove',
          icon: 'x',
          payload: 'remove:$index',
        ),
    ];

/// The setting each on/off item changes, with its current value.
(String key, bool value)? settingOf(MenuAction action, PresenceSettings s) =>
    switch (action) {
      MenuAction.toggle => (PresenceSettings.enabledKey, s.enabled),
      MenuAction.privacyMode => (PresenceSettings.privacyModeKey, s.privacyMode),
      MenuAction.showFileName => (PresenceSettings.showFileNameKey, s.showFileName),
      MenuAction.showProjectName => (
          PresenceSettings.showProjectNameKey,
          s.showProjectName
        ),
      MenuAction.showLanguage => (PresenceSettings.showLanguageKey, s.showLanguage),
      MenuAction.showElapsedTime => (
          PresenceSettings.showElapsedTimeKey,
          s.showElapsedTime
        ),
      MenuAction.showButtons => (PresenceSettings.showButtonsKey, s.showButtons),
      MenuAction.project ||
      MenuAction.excludedProjects ||
      MenuAction.includedProjects ||
      MenuAction.reconnect =>
        null,
    };
