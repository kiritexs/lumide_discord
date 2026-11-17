import 'package:lumide_discord/lumide_discord.dart';
import 'package:test/test.dart';

void main() {
  final start = DateTime(2026, 11, 17, 9);
  const settings = PresenceSettings();

  Activity activity({
    String? filePath = '/work/tilawa/lib/main.dart',
    bool editing = false,
    String? projectName = 'tilawa',
    bool flutterProject = false,
    bool idle = false,
    RunMode runMode = RunMode.none,
  }) =>
      Activity(
        sessionStart: start,
        filePath: filePath,
        editing: editing,
        projectName: projectName,
        flutterProject: flutterProject,
        idle: idle,
        runMode: runMode,
      );

  group('presenceFor', () {
    test('shows the file, project, language, time and buttons', () {
      expect(
        presenceFor(activity(editing: true), settings),
        PresenceContent(
          details: 'Editing main.dart',
          state: 'In tilawa',
          imageKey: 'dart',
          imageText: 'Dart',
          startedAt: start,
          buttons: const [
            PresenceSettings.websiteButton,
            PresenceSettings.discordButton,
          ],
        ),
      );
    });

    test('says Viewing until the file is changed', () {
      expect(presenceFor(activity(), settings)!.details, 'Viewing main.dart');
    });

    test('shows Flutter for Dart files in a Flutter project', () {
      final content = presenceFor(activity(flutterProject: true), settings)!;
      expect(content.imageKey, 'flutter');
      expect(content.imageText, 'Flutter');
    });

    test('hides the file name, keeping the language', () {
      const hidden = PresenceSettings(showFileName: false);
      expect(
        presenceFor(activity(editing: true), hidden)!.details,
        'Editing a Dart file',
      );
      expect(
        presenceFor(activity(filePath: '/work/notes.xyz'), hidden)!.details,
        'Viewing a file',
      );
    });

    test('hides the file name and the language', () {
      const hidden = PresenceSettings(showFileName: false, showLanguage: false);
      final content = presenceFor(activity(), hidden)!;
      expect(content.details, 'Viewing a file');
      expect(content.imageKey, isNull);
      expect(content.imageText, isNull);
    });

    test('hides the project and the time', () {
      const hidden = PresenceSettings(
        showProjectName: false,
        showElapsedTime: false,
      );
      final content = presenceFor(activity(), hidden)!;
      expect(content.state, isNull);
      expect(content.startedAt, isNull);
    });

    test('shows no project when there is none', () {
      expect(presenceFor(activity(projectName: null), settings)!.state, isNull);
      expect(presenceFor(activity(projectName: ''), settings)!.state, isNull);
    });

    test('handles no open file', () {
      final content = presenceFor(activity(filePath: null), settings)!;
      expect(content.details, 'No file open');
      expect(content.state, 'In tilawa');
      expect(content.imageKey, isNull);
    });

    test('pads one-letter language names to 2 characters', () {
      final content =
          presenceFor(activity(filePath: '/work/main.c'), settings)!;
      expect(content.imageKey, 'c');
      expect(content.imageText, 'C ');
    });

    test("keeps texts within Discord's 2 to 128 characters", () {
      final long = '${'a' * 200}.dart';
      final content = presenceFor(
        activity(filePath: '/work/$long', projectName: 'x' * 200),
        settings,
      )!;
      expect(content.details, hasLength(128));
      expect(content.details, endsWith('…'));
      expect(content.state, hasLength(128));
      expect(presenceFor(activity(projectName: 'a'), settings)!.state, 'In a');
    });
  });

  group('idle', () {
    test('shows Idle with the idle image', () {
      final content = presenceFor(activity(idle: true), settings)!;
      expect(content.details, 'Idle');
      expect(content.state, 'In tilawa');
      expect(content.imageKey, 'idle');
      expect(content.imageText, 'Idle');
      expect(content.startedAt, start);
    });

    test('shows nothing while idle when set to hide', () {
      const hide = PresenceSettings(clearWhenIdle: true);
      expect(presenceFor(activity(idle: true), hide), isNull);
      expect(presenceFor(activity(), hide), isNotNull);
    });

    test('is never shown while something runs', () {
      const hide = PresenceSettings(clearWhenIdle: true);
      final content = presenceFor(
        activity(idle: true, runMode: RunMode.running),
        hide,
      )!;
      expect(content.details, 'Running main.dart');
      expect(content.imageKey, 'dart');
    });
  });

  group('run and debug', () {
    test('shows Debugging with the debugging image', () {
      final content = presenceFor(
        activity(editing: true, runMode: RunMode.debugging),
        settings,
      )!;
      expect(content.details, 'Debugging main.dart');
      expect(content.imageKey, 'debugging');
      expect(content.imageText, 'Debugging');
    });

    test('shows Running and Testing with the language', () {
      expect(
        presenceFor(activity(runMode: RunMode.testing), settings)!.details,
        'Testing main.dart',
      );
      final running = presenceFor(
        activity(flutterProject: true, runMode: RunMode.running),
        settings,
      )!;
      expect(running.details, 'Running main.dart');
      expect(running.imageKey, 'flutter');
    });

    test('shows only the run mode without an open file', () {
      final content = presenceFor(
        activity(filePath: null, runMode: RunMode.debugging),
        settings,
      )!;
      expect(content.details, 'Debugging');
      expect(content.state, 'In tilawa');
    });

    test('respects hidden file names', () {
      const hidden = PresenceSettings(showFileName: false);
      expect(
        presenceFor(activity(runMode: RunMode.debugging), hidden)!.details,
        'Debugging a Dart file',
      );
    });
  });

  group('privacy mode', () {
    const private = PresenceSettings(privacyMode: true);

    test('hides the file and project names, keeping the language', () {
      final content = presenceFor(activity(editing: true), private)!;
      expect(content.details, 'Editing a Dart file');
      expect(content.state, isNull);
      expect(content.imageKey, 'dart');
      expect(content.startedAt, start);
    });

    test('still shows idle and debugging', () {
      expect(presenceFor(activity(idle: true), private)!.details, 'Idle');
      expect(
        presenceFor(activity(runMode: RunMode.debugging), private)!.details,
        'Debugging a Dart file',
      );
    });

    test('hides everything with the language turned off', () {
      final content = presenceFor(
        activity(),
        const PresenceSettings(privacyMode: true, showLanguage: false),
      )!;
      expect(content.details, 'Viewing a file');
      expect(content.state, isNull);
      expect(content.imageKey, isNull);
    });
  });

  group('discordPresenceOf', () {
    test('shows the image large with Lumide in the small circle', () {
      final presence = discordPresenceOf(
        presenceFor(activity(editing: true), settings)!,
      );
      expect(presence.details, 'Editing main.dart');
      expect(presence.state, 'In tilawa');
      expect(presence.largeAsset?.key, 'dart');
      expect(presence.largeAsset?.text, 'Dart');
      expect(presence.smallAsset?.key, 'lumide');
      expect(presence.smallAsset?.text, 'Lumide');
      expect(
        presence.timestamps?.start,
        start.millisecondsSinceEpoch ~/ 1000,
      );
    });

    test('shows only the Lumide logo without an image', () {
      final presence = discordPresenceOf(
        presenceFor(activity(filePath: null), settings)!,
      );
      expect(presence.largeAsset?.key, 'lumide');
      expect(presence.smallAsset, isNull);
    });

    test('adds the buttons', () {
      final presence = discordPresenceOf(presenceFor(activity(), settings)!);
      expect(
        [for (final b in presence.buttons!) (label: b.label, url: b.url)],
        settings.buttons,
      );
      const none = PresenceSettings(showButtons: false);
      expect(discordPresenceOf(presenceFor(activity(), none)!).buttons, isNull);
    });

    test('leaves out the time when hidden', () {
      const hidden = PresenceSettings(showElapsedTime: false);
      expect(
        discordPresenceOf(presenceFor(activity(), hidden)!).timestamps,
        isNull,
      );
    });
  });

  test('PresenceContent compares by value', () {
    final a = PresenceContent(details: 'Idle', startedAt: start);
    final b = PresenceContent(details: 'Idle', startedAt: start);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(const PresenceContent(details: 'Idle')));
    expect(
      a,
      isNot(PresenceContent(
        details: 'Idle',
        startedAt: start,
        buttons: const [PresenceSettings.websiteButton],
      )),
    );
  });
}
