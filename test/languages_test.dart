import 'package:lumide_discord/lumide_discord.dart';
import 'package:test/test.dart';

void main() {
  group('languageForFile', () {
    test('finds the language by extension', () {
      expect(languageForFile('main.dart'), (key: 'dart', name: 'Dart'));
      expect(languageForFile('app.tsx').key, 'react');
      expect(languageForFile('build.gradle.kts').key, 'kotlin');
      expect(languageForFile('script.ps1').key, 'powershell');
    });

    test('ignores case and folders', () {
      expect(languageForFile('/home/me/app/README.MD').key, 'markdown');
      expect(languageForFile(r'C:\src\Main.Java').key, 'java');
    });

    test('finds files known by name', () {
      expect(languageForFile('Dockerfile').key, 'docker');
      expect(languageForFile('/repo/Makefile').key, 'makefile');
    });

    test('shows Dart files in a Flutter project as Flutter', () {
      expect(
        languageForFile('lib/main.dart', flutterProject: true),
        (key: 'flutter', name: 'Flutter'),
      );
      expect(
        languageForFile('pubspec.yaml', flutterProject: true).key,
        'yaml',
      );
    });

    test('falls back to plain text', () {
      expect(languageForFile('notes.xyz'), unknownLanguage);
      expect(languageForFile('LICENSE'), unknownLanguage);
    });
  });
}
