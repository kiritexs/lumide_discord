/// What to show on Discord for what the user is doing.
library;

import 'package:path/path.dart' as p;

import 'languages.dart';
import 'settings.dart';

/// What Lumide is running from Run and Debug, if anything.
enum RunMode {
  none(null),
  running('Running'),
  testing('Testing'),
  debugging('Debugging');

  const RunMode(this.verb);

  /// Replaces "Editing" or "Viewing" while running.
  final String? verb;
}

/// What the user is doing in Lumide right now.
class Activity {
  const Activity({
    required this.sessionStart,
    this.filePath,
    this.editing = false,
    this.projectName,
    this.flutterProject = false,
    this.idle = false,
    this.runMode = RunMode.none,
  });

  /// When Lumide was opened; the elapsed time counts from here.
  final DateTime sessionStart;

  /// The file open in the editor, or `null`.
  final String? filePath;

  /// Whether the user has typed in [filePath] since opening it.
  final bool editing;

  /// The workspace folder holding [filePath] (or the workspace root).
  final String? projectName;

  /// Whether that folder is a Flutter project.
  final bool flutterProject;

  /// No activity for the configured idle time.
  final bool idle;

  /// What is running; the user isn't shown as idle while something runs.
  final RunMode runMode;
}

/// The texts and images of the Discord presence.
class PresenceContent {
  const PresenceContent({
    required this.details,
    this.state,
    this.imageKey,
    this.imageText,
    this.startedAt,
    this.buttons = const [],
  });

  /// First line, e.g. "Editing main.dart".
  final String details;

  /// Second line, e.g. "In tilawa".
  final String? state;

  /// Large image (language, idle or debugging) and its hover text; `null`
  /// shows the Lumide logo instead.
  final String? imageKey;
  final String? imageText;

  /// Start of the elapsed time shown, or `null` to hide it.
  final DateTime? startedAt;

  /// Links shown as buttons under the status (at most 2).
  final List<PresenceButton> buttons;

  @override
  bool operator ==(Object other) =>
      other is PresenceContent &&
      other.details == details &&
      other.state == state &&
      other.imageKey == imageKey &&
      other.imageText == imageText &&
      other.startedAt == startedAt &&
      other.buttons.length == buttons.length &&
      Iterable.generate(buttons.length)
          .every((i) => other.buttons[i] == buttons[i]);

  @override
  int get hashCode => Object.hash(
      details, state, imageKey, imageText, startedAt, Object.hashAll(buttons));

  @override
  String toString() => '$details | $state | $imageKey';
}

/// Discord's limits for the text fields.
const _minLength = 2;
const _maxLength = 128;

/// The presence for [activity] under [settings], or `null` to show none.
PresenceContent? presenceFor(Activity activity, PresenceSettings settings) {
  final running = activity.runMode != RunMode.none;
  final idle = activity.idle && !running;
  if (idle && settings.clearWhenIdle) return null;

  final private = settings.privacyMode;
  final showFileName = settings.showFileName && !private;
  final showProjectName = settings.showProjectName && !private;

  final file = activity.filePath;
  final language = file == null
      ? null
      : languageForFile(file, flutterProject: activity.flutterProject);
  final showLanguage = settings.showLanguage && language != null;

  final String details;
  if (idle) {
    details = 'Idle';
  } else if (file == null) {
    details = activity.runMode.verb ?? 'No file open';
  } else {
    final verb = activity.runMode.verb ??
        (activity.editing ? 'Editing' : 'Viewing');
    final what = showFileName
        ? p.basename(file)
        : showLanguage && language != unknownLanguage
            ? 'a ${language.name} file'
            : 'a file';
    details = '$verb $what';
  }

  final (String? imageKey, String? imageText) = switch (activity.runMode) {
    _ when idle => ('idle', 'Idle'),
    RunMode.debugging => ('debugging', 'Debugging'),
    _ when showLanguage => (language.key, language.name),
    _ => (null, null),
  };

  final project = activity.projectName;
  return PresenceContent(
    details: _fit(details),
    state: showProjectName && project != null && project.isNotEmpty
        ? _fit('In $project')
        : null,
    imageKey: imageKey,
    imageText: imageText == null ? null : _fit(imageText),
    startedAt: settings.showElapsedTime ? activity.sessionStart : null,
    buttons: settings.buttons,
  );
}

/// [text] within Discord's 2 to 128 characters.
String _fit(String text) {
  if (text.length > _maxLength) return '${text.substring(0, _maxLength - 1)}…';
  return text.padRight(_minLength);
}
