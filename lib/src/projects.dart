/// Which projects keep their names off Discord: the exclude and include
/// lists from the settings.
library;

import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

/// One entry of an exclude or include list:
///
/// - a folder path, such as `D:\work\company_app`: that folder and
///   everything in it;
/// - a glob, such as `D:/work/**` or `**/clients/*`: matched against the
///   project folder and the open file;
/// - a project name, such as `company_app`: the workspace folder's name.
///
/// Matching ignores case and treats `\` and `/` alike.
class ProjectPattern {
  ProjectPattern(String text)
      : text = text.trim(),
        _value = _normalize(text.trim()) {
    if (_value.contains(RegExp(r'[*?\[{]'))) {
      try {
        _glob = Glob(_value, context: p.posix, caseSensitive: false);
      } on FormatException {
        _glob = null; // Not a valid glob: never matches.
      }
      _kind = _Kind.glob;
    } else {
      _kind = _value.contains('/') ? _Kind.folder : _Kind.name;
    }
  }

  /// The entry as written in the settings.
  final String text;
  final String _value;
  late final _Kind _kind;
  Glob? _glob;

  /// Whether the project at [projectPath] named [projectName], with
  /// [filePath] open, matches this entry.
  bool matches({String? projectPath, String? projectName, String? filePath}) {
    if (_value.isEmpty) return false;
    final paths = [
      for (final path in [projectPath, filePath])
        if (path != null && path.isNotEmpty) _normalize(path),
    ];
    switch (_kind) {
      case _Kind.name:
        return projectName != null && projectName.toLowerCase() == _value;
      case _Kind.folder:
        return paths.any((path) => path == _value || path.startsWith('$_value/'));
      case _Kind.glob:
        final glob = _glob;
        return glob != null && paths.any(glob.matches);
    }
  }

  /// Whether this entry names exactly the folder at [path], for removing it
  /// again from the menu.
  bool isFolder(String path) =>
      _kind == _Kind.folder && _value == _normalize(path);

  static String _normalize(String path) {
    var value = path.replaceAll('\\', '/').toLowerCase();
    while (value.length > 1 && value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }
}

enum _Kind { folder, glob, name }

/// Splits a list setting: entries separated by `;` or new lines.
List<String> splitList(String text) => [
      for (final entry in text.split(RegExp(r'[;\r\n]+')))
        if (entry.trim().isNotEmpty) entry.trim(),
    ];

/// Joins entries back into a list setting.
String joinList(List<String> entries) => entries.join('; ');

/// [entries] with [entry] added at the end, unless it is empty or already
/// there (ignoring case, `\` versus `/` and a trailing slash).
List<String> addEntry(List<String> entries, String entry) {
  final value = entry.trim();
  if (value.isEmpty) return entries;
  final key = ProjectPattern._normalize(value);
  if (entries.any((e) => ProjectPattern._normalize(e) == key)) return entries;
  return [...entries, value];
}

/// Decides whether a project is excluded: it matches the exclude list, or
/// an include list is set and it doesn't match it.
class ProjectFilter {
  ProjectFilter({List<String> excluded = const [], List<String> included = const []})
      : _excluded = [for (final entry in excluded) ProjectPattern(entry)],
        _included = [for (final entry in included) ProjectPattern(entry)];

  final List<ProjectPattern> _excluded;
  final List<ProjectPattern> _included;

  bool isExcluded({String? projectPath, String? projectName, String? filePath}) {
    if (projectPath == null && projectName == null && filePath == null) {
      return false; // Nothing open: nothing to hide.
    }
    bool matches(ProjectPattern pattern) => pattern.matches(
        projectPath: projectPath, projectName: projectName, filePath: filePath);
    if (_excluded.any(matches)) return true;
    return _included.isNotEmpty && !_included.any(matches);
  }
}
