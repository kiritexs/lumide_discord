import 'package:lumide_api/lumide_api.dart';
import 'package:lumide_discord/lumide_discord.dart';
import 'package:test/test.dart';

void main() {
  List<QuickPickItem> items({
    PresenceSettings settings = const PresenceSettings(),
    LinkState state = LinkState.connected,
    String? project = 'tilawa',
    ProjectState projectState = ProjectState.shown,
  }) =>
      menuItems(
        settings: settings,
        linkState: state,
        projectName: project,
        projectState: projectState,
      );

  QuickPickItem item(List<QuickPickItem> all, MenuAction action) =>
      all.singleWhere((item) => item.payload == action.name);

  test('starts with the connection state, which cannot be picked', () {
    final first = items().first;
    expect(first.label, 'Showing your activity on Discord');
    expect(first.enabled, isFalse);
    expect(
      items(state: LinkState.waiting).first.label,
      'Waiting for Discord to start',
    );
    expect(
      items(settings: const PresenceSettings(enabled: false)).first.label,
      'Turned off',
    );
  });

  test('shows each setting as on or off', () {
    final all = items(
      settings: const PresenceSettings(privacyMode: true, showButtons: false),
    );
    expect(item(all, MenuAction.privacyMode).description, 'On');
    expect(item(all, MenuAction.privacyMode).icon, 'check');
    expect(item(all, MenuAction.showButtons).description, 'Off');
    expect(item(all, MenuAction.showButtons).icon, isNull);
    expect(item(all, MenuAction.toggle).label, 'Turn Off');
  });

  test('offers to hide or show the current project', () {
    expect(item(items(), MenuAction.project).label, 'Hide "tilawa"');
    expect(
      item(items(projectState: ProjectState.hiddenByMenu), MenuAction.project)
          .label,
      'Show "tilawa"',
    );
    final bySettings = items(projectState: ProjectState.hiddenBySettings)
        .singleWhere((item) => item.label == '"tilawa" is hidden');
    expect(bySettings.enabled, isFalse);
    expect(
      items(project: null).any((item) => item.payload == 'project'),
      isFalse,
    );
  });

  test('opens the project lists, with how many entries each has', () {
    final all = items(
      settings: const PresenceSettings(excludedProjects: ['a', 'b']),
    );
    expect(item(all, MenuAction.excludedProjects).description, '2');
    expect(item(all, MenuAction.includedProjects).description, 'None');
  });

  group('project list menu', () {
    test('offers to add a folder or a pattern', () {
      final all = projectListItems(const []);
      expect([for (final i in all) i.label], ['Add Folder…', 'Add Pattern…']);
      expect(ListAction.of(all[0].payload), isA<AddFolder>());
      expect(ListAction.of(all[1].payload), isA<AddPattern>());
    });

    test('lists the entries, each removed by clicking it', () {
      final all = projectListItems(const [r'D:\work\app', 'company_app']);
      final entries = all.where((i) => i.detail == 'Click to remove').toList();
      expect([for (final i in entries) i.label], [r'D:\work\app', 'company_app']);
      expect(
        (ListAction.of(entries.last.payload)! as RemoveEntry).index,
        1,
      );
      expect(all.where((i) => i.isSeparator), hasLength(1));
    });

    test('ignores unknown or broken payloads', () {
      expect(ListAction.of(null), isNull);
      expect(ListAction.of('remove:x'), isNull);
      expect(ListAction.of('something'), isNull);
      expect(ListAction.of(3), isNull);
    });
  });

  test('offers Reconnect only while not connected', () {
    bool hasReconnect(List<QuickPickItem> all) =>
        all.any((item) => item.payload == MenuAction.reconnect.name);
    expect(hasReconnect(items()), isFalse);
    expect(hasReconnect(items(state: LinkState.waiting)), isTrue);
    expect(
      hasReconnect(items(
        settings: const PresenceSettings(enabled: false),
        state: LinkState.off,
      )),
      isFalse,
    );
  });

  test('every on/off item names its setting', () {
    const settings = PresenceSettings(showLanguage: false);
    for (final action in MenuAction.values) {
      final setting = settingOf(action, settings);
      if (const [
        MenuAction.project,
        MenuAction.excludedProjects,
        MenuAction.includedProjects,
        MenuAction.reconnect,
      ].contains(action)) {
        expect(setting, isNull);
      } else {
        expect(PresenceSettings.keys, contains(setting!.$1));
      }
    }
    expect(
      settingOf(MenuAction.showLanguage, settings),
      (PresenceSettings.showLanguageKey, false),
    );
  });
}
