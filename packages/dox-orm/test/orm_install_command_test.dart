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

  test('an unknown driver stops with exit code 1', () async {
    await install(<String>['--driver=oracle']);
    expect(exitCode, 1);
    expect(runner.calls, isEmpty);
    exitCode = 0;
  });
}
