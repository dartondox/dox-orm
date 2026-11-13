import 'dart:io';

import 'package:dox_annotation/install.dart';
import 'package:dox_orm/commands.dart';
import 'package:test/test.dart';

/// records the `dart` commands, runs nothing
class FakeRunner extends ProcessRunner {
  final List<String> calls = <String>[];

  @override
  Future<int> run(String executable, List<String> args, String folder) async {
    calls.add(args.join(' '));
    return 0;
  }
}

const String envDart = '''
abstract class AppEnv {
  String get appName => 'dox';
}
''';

void main() {
  late Directory root;
  late FakeRunner runner;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dox_orm_install_');
    File('${root.path}/pubspec.yaml').writeAsStringSync(
      'name: my_app\n\ndependencies:\n  dox_core: ^3.1.0\n  dox_orm: ^3.1.0\n',
    );
    File('${root.path}/.env').writeAsStringSync('APP_KEY=x\n');
    File('${root.path}/lib/config/env.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync(envDart);
    runner = FakeRunner();
    exitCode = 0;
  });

  tearDown(() {
    root.deleteSync(recursive: true);
  });

  String read(String path) => File('${root.path}/$path').readAsStringSync();

  Future<void> install(List<String> args) {
    return OrmInstallCommand(root: root, runner: runner).run(args);
  }

  test('sets up sqlite by default', () async {
    await install(<String>[]);
    expect(exitCode, 0);
    expect(runner.calls, <String>[
      'pub add dox_migration',
      'pub add --dev dox_builder',
      'pub add --dev build_runner',
      'run build_runner build',
    ]);
    expect(
      read('lib/config/database.dart'),
      contains("import 'package:my_app/config/env.dart';"),
    );
    expect(read('lib/providers/orm_provider.dart'), contains('ORMProvider'));
    expect(read('bin/migrate.dart'), contains('Migrator'));
    expect(read('db/migration/migrations.dart'), contains('MigrationEntry'));
    expect(read('.env'), contains('DB_CONNECTION=sqlite\n'));
    expect(read('lib/config/env.dart'), contains("dbConnection => 'sqlite'"));
    expect(read('pubspec.yaml'), contains('dox_postgres_native:\n'));
    expect(read('pubspec.yaml'), contains('dox_mysql_native:\n'));
  });

  test('postgres keeps its driver and adds its keys', () async {
    await install(<String>['--driver=postgres']);
    expect(read('.env'), contains('DB_PORT=5432\n'));
    expect(read('pubspec.yaml'), isNot(contains('dox_postgres_native:')));
    expect(read('pubspec.yaml'), contains('dox_mysql_native:\n'));
  });

  test('a second run changes nothing', () async {
    await install(<String>['--driver', 'mysql']);
    File('${root.path}/lib/config/database.dart').writeAsStringSync('mine');
    Map<String, String> before = <String, String>{};
    for (FileSystemEntity f in root.listSync(recursive: true)) {
      if (f is File) before[f.path] = f.readAsStringSync();
    }
    await install(<String>['--driver=postgres']);
    expect(read('pubspec.yaml'), contains('dox_postgres_native:\n'));
    for (String path in before.keys) {
      expect(File(path).readAsStringSync(), before[path], reason: path);
    }
  });

  /// every file of the app and its text
  Map<String, String> snapshot() {
    Map<String, String> files = <String, String>{};
    for (FileSystemEntity f in root.listSync(recursive: true)) {
      if (f is File) files[f.path] = f.readAsStringSync();
    }
    return files;
  }

  test('a bad option stops with exit code 1 and writes nothing', () async {
    for (List<String> args in <List<String>>[
      <String>['--driver=oracle'],
      <String>['--drive=postgres'],
      <String>['--driver'],
      <String>['--driver='],
      <String>['postgres'],
    ]) {
      Map<String, String> before = snapshot();
      await install(args);
      expect(exitCode, 1, reason: '$args');
      expect(runner.calls, isEmpty, reason: '$args');
      expect(snapshot(), before, reason: '$args');
      exitCode = 0;
    }
  });

  test('an existing hooks block is not touched', () async {
    String pubspec =
        'name: my_app\n\ndependencies:\n  dox_orm: ^3.1.0\n\n'
        '# my hooks\nhooks:\n  user_defines:\n    sqlite3:\n'
        '      source: system # keep\n';
    File('${root.path}/pubspec.yaml').writeAsStringSync(pubspec);
    await install(<String>[]);
    expect(read('pubspec.yaml'), pubspec);
  });

  test('a pubspec with no final new line gets the hooks block', () async {
    File('${root.path}/pubspec.yaml')
        .writeAsStringSync('name: my_app\ndependencies:\n  dox_orm: ^3.1.0');
    await install(<String>[]);
    expect(
      read('pubspec.yaml'),
      startsWith('name: my_app\ndependencies:\n  dox_orm: ^3.1.0\n\n# Skip'),
    );
  });

  test(
    'without AppEnv it gives a hint, exit code 1, and changes nothing',
    () async {
      for (String? env in <String?>[null, 'class Other {\n}\n']) {
        File file = File('${root.path}/lib/config/env.dart');
        if (env == null) {
          file.deleteSync();
        } else {
          file.writeAsStringSync(env);
        }
        Map<String, String> before = snapshot();
        await install(<String>[]);
        expect(exitCode, 1);
        expect(runner.calls, isEmpty);
        expect(snapshot(), before);
        exitCode = 0;
      }
    },
  );
}
