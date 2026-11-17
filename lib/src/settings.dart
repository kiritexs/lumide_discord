/// The plugin's settings (Settings → Plugins → Discord Presence).
library;

import 'projects.dart';

/// A button under the Discord status that opens [url]. Others can click
/// it; Discord doesn't let you click your own.
typedef PresenceButton = ({String label, String url});

/// Settings read from Lumide; keys are listed in `plugin.yaml`.
class PresenceSettings {
  const PresenceSettings({
    this.enabled = true,
    this.applicationId = defaultApplicationId,
    this.showFileName = true,
    this.showProjectName = true,
    this.showLanguage = true,
    this.showElapsedTime = true,
    this.idleMinutes = 5,
    this.clearWhenIdle = false,
    this.privacyMode = false,
    this.showButtons = true,
    this.customButton,
    this.excludedProjects = const [],
    this.includedProjects = const [],
    this.hideExcludedProjects = false,
  });

  /// The plugin's own Discord application ("Playing Lumide"), with the
  /// Lumide and language images. Used unless the user sets their own.
  static const defaultApplicationId = '1572227180954521641';

  static const websiteButton =
      (label: 'Get Lumide', url: 'https://lumide.dev');
  static const discordButton =
      (label: 'Join Lumide Discord', url: 'https://discord.gg/VP6p5JQdgt');

  /// Discord's limits for buttons.
  static const _maxLabelLength = 32;
  static const _maxUrlLength = 512;

  /// Reads the settings from [values] (setting key → value). Missing or
  /// wrongly typed values fall back to the defaults, and an empty
  /// application ID to [defaultApplicationId].
  factory PresenceSettings.fromValues(Map<String, Object?> values) {
    const defaults = PresenceSettings();
    bool flag(String key, bool fallback) => switch (values[key]) {
          final bool value => value,
          _ => fallback,
        };
    String text(String key) => switch (values[key]) {
          final String value => value.trim(),
          _ => '',
        };
    final idle = switch (values[idleMinutesKey]) {
      final num value => value.toInt(),
      _ => defaults.idleMinutes,
    };
    final applicationId = text(applicationIdKey);
    return PresenceSettings(
      enabled: flag(enabledKey, defaults.enabled),
      applicationId: applicationId.isEmpty
          ? defaults.applicationId
          : applicationId,
      showFileName: flag(showFileNameKey, defaults.showFileName),
      showProjectName: flag(showProjectNameKey, defaults.showProjectName),
      showLanguage: flag(showLanguageKey, defaults.showLanguage),
      showElapsedTime: flag(showElapsedTimeKey, defaults.showElapsedTime),
      idleMinutes: idle < 0 ? 0 : idle,
      clearWhenIdle: flag(clearWhenIdleKey, defaults.clearWhenIdle),
      privacyMode: flag(privacyModeKey, defaults.privacyMode),
      showButtons: flag(showButtonsKey, defaults.showButtons),
      customButton:
          _button(text(customButtonLabelKey), text(customButtonUrlKey)),
      excludedProjects: splitList(text(excludedProjectsKey)),
      includedProjects: splitList(text(includedProjectsKey)),
      hideExcludedProjects:
          flag(hideExcludedProjectsKey, defaults.hideExcludedProjects),
    );
  }

  /// A button for [label] and [url], or `null` when either is missing or
  /// the link isn't a web address. Long labels are shortened.
  static PresenceButton? _button(String label, String url) {
    final uri = Uri.tryParse(url);
    if (label.isEmpty ||
        url.length > _maxUrlLength ||
        uri == null ||
        !(uri.isScheme('https') || uri.isScheme('http')) ||
        uri.host.isEmpty) {
      return null;
    }
    return (
      label: label.length > _maxLabelLength
          ? '${label.substring(0, _maxLabelLength - 1)}…'
          : label,
      url: url,
    );
  }

  static const enabledKey = 'discordPresence.enabled';
  static const applicationIdKey = 'discordPresence.applicationId';
  static const showFileNameKey = 'discordPresence.showFileName';
  static const showProjectNameKey = 'discordPresence.showProjectName';
  static const showLanguageKey = 'discordPresence.showLanguage';
  static const showElapsedTimeKey = 'discordPresence.showElapsedTime';
  static const idleMinutesKey = 'discordPresence.idleMinutes';
  static const clearWhenIdleKey = 'discordPresence.clearWhenIdle';
  static const privacyModeKey = 'discordPresence.privacyMode';
  static const showButtonsKey = 'discordPresence.showButtons';
  static const customButtonLabelKey = 'discordPresence.customButtonLabel';
  static const customButtonUrlKey = 'discordPresence.customButtonUrl';
  static const excludedProjectsKey = 'discordPresence.excludedProjects';
  static const includedProjectsKey = 'discordPresence.includedProjects';
  static const hideExcludedProjectsKey = 'discordPresence.hideExcludedProjects';

  /// Every key, for reading all settings at once.
  static const keys = [
    enabledKey,
    applicationIdKey,
    showFileNameKey,
    showProjectNameKey,
    showLanguageKey,
    showElapsedTimeKey,
    idleMinutesKey,
    clearWhenIdleKey,
    privacyModeKey,
    showButtonsKey,
    customButtonLabelKey,
    customButtonUrlKey,
    excludedProjectsKey,
    includedProjectsKey,
    hideExcludedProjectsKey,
  ];

  /// Whether to show anything on Discord.
  final bool enabled;

  /// The Discord application the presence belongs to; its name is shown
  /// after "Playing".
  final String applicationId;

  /// Show the open file's name; otherwise only its language.
  final bool showFileName;

  /// Show the workspace folder's name.
  final bool showProjectName;

  /// Show the language icon and name.
  final bool showLanguage;

  /// Show how long Lumide has been open.
  final bool showElapsedTime;

  /// Minutes without activity before showing "Idle"; 0 never goes idle.
  final int idleMinutes;

  /// Remove the presence while idle instead of showing "Idle".
  final bool clearWhenIdle;

  /// Hide file and project names whatever [showFileName] and
  /// [showProjectName] say, e.g. for screen sharing or client work.
  final bool privacyMode;

  /// Show [buttons] under the status.
  final bool showButtons;

  /// The user's own button, in place of [discordButton].
  final PresenceButton? customButton;

  /// Projects whose names stay off Discord: folder paths, globs or project
  /// names (see [ProjectPattern]).
  final List<String> excludedProjects;

  /// When set, only these projects show their names; all others count as
  /// excluded.
  final List<String> includedProjects;

  /// Remove the status entirely in excluded projects, instead of showing it
  /// without file and project names.
  final bool hideExcludedProjects;

  ProjectFilter get projectFilter =>
      ProjectFilter(excluded: excludedProjects, included: includedProjects);

  /// The buttons to show: the website, then the user's own button or
  /// Lumide's Discord server.
  List<PresenceButton> get buttons => showButtons
      ? [websiteButton, customButton ?? discordButton]
      : const [];
}
