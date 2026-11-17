/// The language shown for a file: its Discord image key and its name.
library;

import 'package:path/path.dart' as p;

/// A language as shown on Discord. [key] names an image uploaded to the
/// Discord application (Rich Presence → Art Assets).
typedef Language = ({String key, String name});

/// Shown for files without a known language.
const Language unknownLanguage = (key: 'file', name: 'Text');

/// The language of [fileName]. Dart files in a Flutter project count as
/// Flutter.
Language languageForFile(String fileName, {bool flutterProject = false}) {
  final name = p.basename(fileName).toLowerCase();
  final byName = _byFileName[name];
  if (byName != null) return byName;
  final extension = p.extension(name).replaceFirst('.', '');
  if (extension == 'dart' && flutterProject) {
    return (key: 'flutter', name: 'Flutter');
  }
  return _byExtension[extension] ?? unknownLanguage;
}

const Map<String, Language> _byFileName = {
  'dockerfile': (key: 'docker', name: 'Docker'),
  'makefile': (key: 'makefile', name: 'Makefile'),
};

const Map<String, Language> _byExtension = {
  'dart': (key: 'dart', name: 'Dart'),
  'js': (key: 'javascript', name: 'JavaScript'),
  'mjs': (key: 'javascript', name: 'JavaScript'),
  'cjs': (key: 'javascript', name: 'JavaScript'),
  'ts': (key: 'typescript', name: 'TypeScript'),
  'mts': (key: 'typescript', name: 'TypeScript'),
  'jsx': (key: 'react', name: 'React'),
  'tsx': (key: 'react', name: 'React'),
  'vue': (key: 'vue', name: 'Vue'),
  'svelte': (key: 'svelte', name: 'Svelte'),
  'py': (key: 'python', name: 'Python'),
  'java': (key: 'java', name: 'Java'),
  'kt': (key: 'kotlin', name: 'Kotlin'),
  'kts': (key: 'kotlin', name: 'Kotlin'),
  'gradle': (key: 'gradle', name: 'Gradle'),
  'swift': (key: 'swift', name: 'Swift'),
  'go': (key: 'go', name: 'Go'),
  'rs': (key: 'rust', name: 'Rust'),
  'c': (key: 'c', name: 'C'),
  'h': (key: 'c', name: 'C'),
  'cpp': (key: 'cpp', name: 'C++'),
  'cc': (key: 'cpp', name: 'C++'),
  'cxx': (key: 'cpp', name: 'C++'),
  'hpp': (key: 'cpp', name: 'C++'),
  'cs': (key: 'csharp', name: 'C#'),
  'php': (key: 'php', name: 'PHP'),
  'rb': (key: 'ruby', name: 'Ruby'),
  'lua': (key: 'lua', name: 'Lua'),
  'html': (key: 'html', name: 'HTML'),
  'htm': (key: 'html', name: 'HTML'),
  'css': (key: 'css', name: 'CSS'),
  'scss': (key: 'sass', name: 'Sass'),
  'sass': (key: 'sass', name: 'Sass'),
  'json': (key: 'json', name: 'JSON'),
  'yaml': (key: 'yaml', name: 'YAML'),
  'yml': (key: 'yaml', name: 'YAML'),
  'toml': (key: 'toml', name: 'TOML'),
  'xml': (key: 'xml', name: 'XML'),
  'md': (key: 'markdown', name: 'Markdown'),
  'markdown': (key: 'markdown', name: 'Markdown'),
  'sql': (key: 'sql', name: 'SQL'),
  'sh': (key: 'shell', name: 'Shell'),
  'bash': (key: 'shell', name: 'Shell'),
  'zsh': (key: 'shell', name: 'Shell'),
  'ps1': (key: 'powershell', name: 'PowerShell'),
};
