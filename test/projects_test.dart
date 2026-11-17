import 'package:lumide_discord/lumide_discord.dart';
import 'package:test/test.dart';

void main() {
  const project = r'D:\work\company_app';
  const file = r'D:\work\company_app\lib\main.dart';

  bool matches(
    String entry, {
    String? projectPath = project,
    String? projectName = 'company_app',
    String? filePath = file,
  }) =>
      ProjectPattern(entry).matches(
        projectPath: projectPath,
        projectName: projectName,
        filePath: filePath,
      );

  group('ProjectPattern', () {
    test('matches a folder and everything in it', () {
      expect(matches(r'D:\work\company_app'), isTrue);
      expect(matches(r'D:\work'), isTrue);
      expect(matches('d:/WORK/company_app/'), isTrue, reason: r'case, / and \');
      expect(matches(r'D:\work\company', projectName: 'x'), isFalse,
          reason: 'not part of a folder name');
      expect(matches(r'D:\other'), isFalse);
    });

    test('matches the open file when the project is unknown', () {
      expect(matches(r'D:\work', projectPath: null, projectName: null), isTrue);
    });

    test('matches globs against the project and the file', () {
      expect(matches('D:/work/*'), isTrue);
      expect(matches('**/company_*'), isTrue);
      expect(matches(r'D:\work\**'), isTrue);
      expect(matches('**/*.secret.dart'), isFalse);
      expect(
        matches('**/*.secret.dart',
            filePath: r'D:\work\company_app\a.secret.dart'),
        isTrue,
      );
      expect(matches('D:/other/**'), isFalse);
    });

    test('matches project names without a path', () {
      expect(matches('company_app', projectPath: null, filePath: null), isTrue);
      expect(matches('Company_App', projectPath: null, filePath: null), isTrue);
      expect(matches('company', projectPath: null, filePath: null), isFalse);
    });

    test('never matches empty or broken entries', () {
      expect(matches(''), isFalse);
      expect(matches('D:/work/[a'), isFalse);
    });

    test('knows the folder it names, for removing it again', () {
      expect(
        ProjectPattern(r'D:\work\company_app').isFolder('d:/work/company_app'),
        isTrue,
      );
      expect(ProjectPattern('D:/work/**').isFolder(project), isFalse);
      expect(ProjectPattern('company_app').isFolder(project), isFalse);
    });
  });

  group('ProjectFilter', () {
    bool excluded(ProjectFilter filter, {String path = project}) =>
        filter.isExcluded(
          projectPath: path,
          projectName: path.split(r'\').last,
        );

    test('excludes what the exclude list matches', () {
      final filter = ProjectFilter(excluded: ['company_app']);
      expect(excluded(filter), isTrue);
      expect(excluded(filter, path: r'D:\oss\tilawa'), isFalse);
    });

    test('with an include list, excludes everything it does not match', () {
      final filter = ProjectFilter(included: ['D:/oss/**']);
      expect(excluded(filter, path: r'D:\oss\tilawa'), isFalse);
      expect(excluded(filter), isTrue);
    });

    test('the exclude list wins over the include list', () {
      final filter =
          ProjectFilter(included: ['D:/oss/**'], excluded: [r'D:\oss\secret']);
      expect(excluded(filter, path: r'D:\oss\secret'), isTrue);
      expect(excluded(filter, path: r'D:\oss\tilawa'), isFalse);
    });

    test('excludes nothing without lists or without anything open', () {
      expect(excluded(ProjectFilter()), isFalse);
      expect(ProjectFilter(included: ['x']).isExcluded(), isFalse);
    });
  });

  group('addEntry', () {
    test('adds new entries at the end, trimmed', () {
      expect(addEntry(['a'], ' D:/work/app '), ['a', 'D:/work/app']);
    });

    test('skips duplicates and empty entries', () {
      final entries = [r'D:\work\app'];
      expect(addEntry(entries, 'd:/WORK/app/'), same(entries));
      expect(addEntry(entries, '  '), same(entries));
    });
  });

  test('splitList and joinList round-trip', () {
    expect(splitList(' a ; b\n\nc;'), ['a', 'b', 'c']);
    expect(splitList(joinList(['a', r'D:\b'])), ['a', r'D:\b']);
  });
}
