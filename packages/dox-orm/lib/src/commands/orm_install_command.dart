import 'dart:io';

import 'package:dox_annotation/command.dart';
import 'package:dox_annotation/install.dart';

/// `dox orm:install [--driver=sqlite|postgres|mysql]`. `dox add orm` runs
/// it. It sets up the ORM in an app: dox_migration, the database config,
/// the provider, `bin/migrate.dart`, `db/migration/` and the `DB_*` keys.
/// It never overwrites a file, so it is safe to run twice.
class OrmInstallCommand extends Command {
  /// [root] is the app folder (the current folder by default). [runner]
  /// runs `dart`, tests pass a fake one.
  OrmInstallCommand({this.root, this.runner});

  final Directory? root;
  final ProcessRunner? runner;

  static const List<String> drivers = <String>['sqlite', 'postgres', 'mysql'];

  @override
  String get name => 'orm:install';

  @override
  String get description => 'Set up the ORM and migrations in this app';

  @override
  String get usage => 'orm:install [--driver=sqlite|postgres|mysql]';

  @override
  Future<void> run(List<String> args) async {
    String? driver = _driver(args);
    if (driver == null) {
      print(
        'Unknown option. Use --driver=sqlite, --driver=postgres or '
        '--driver=mysql (sqlite when not given).',
      );
      exitCode = 1;
      return;
    }
    Installer installer = Installer(root: root, runner: runner);
    String app = installer.appName;

    /// first, so an app without the AppEnv class gets the hint and
    /// nothing else is changed
    for (String getter in envGetters(driver)) {
      installer.addEnvGetter(getter);
    }
    if (!installer.ok) {
      installer.printSummary(<String>[
        'lib/config/env.dart has no `abstract class AppEnv`. Run '
            '`dox env:generate` to make it, then run this again.',
      ]);
      return;
    }

    await installer.addDependency('dox_orm');
    await installer.addDependency('dox_migration');
    await installer.addDependency('dox_builder', dev: true);
    await installer.addDependency('build_runner', dev: true);
    _skipOtherDrivers(installer, driver);

    installer.writeFile('lib/config/database.dart', databaseConfig(app));
    installer.writeFile('lib/providers/orm_provider.dart', ormProvider(app));
    installer.writeFile('bin/migrate.dart', migrateEntry);
    installer.writeFile('db/migration/migrations.dart', migrationList);

    Map<String, String> keys = envKeys(driver);
    for (String key in keys.keys) {
      installer.addEnv(key, keys[key]!);
    }

    await installer.buildRunner();
    String pubspec = File('${installer.root.path}/pubspec.yaml')
        .readAsStringSync();
    installer.printSummary(<String>[
      if (pubspec.contains('dox_${driver}_native:'))
        'pubspec.yaml skips the $driver driver: remove the '
            '`dox_${driver}_native:` and `skip: true` lines under hooks.',
      if (driver != 'sqlite')
        'Check DB_CONNECTION=$driver, DB_HOST, DB_NAME, DB_USERNAME and '
            'DB_PASSWORD in .env. A key that was already there is not changed.',
      'Make a model and its migration: `dox make:model Post -m`.',
      'Run the migrations: `dox migrate`.',
    ]);
  }

  /// the value of `--driver=x` or `--driver x`, sqlite when not given.
  /// Null for an unknown option, a missing value or an unknown driver.
  String? _driver(List<String> args) {
    String driver = 'sqlite';
    for (int i = 0; i < args.length; i++) {
      if (args[i].startsWith('--driver=')) {
        driver = args[i].substring('--driver='.length);
      } else if (args[i] == '--driver' && i + 1 < args.length) {
        driver = args[++i];
      } else {
        return null;
      }
    }
    return drivers.contains(driver) ? driver : null;
  }

  /// dox_orm has the Postgres and MySQL native drivers. An app that does
  /// not use one skips its build, with a `skip: true` user define in
  /// pubspec.yaml. Only added when pubspec.yaml has no `hooks:` key.
  void _skipOtherDrivers(Installer installer, String driver) {
    File pubspec = File('${installer.root.path}/pubspec.yaml');
    String text = pubspec.readAsStringSync();
    if (RegExp(r'^hooks:', multiLine: true).hasMatch(text)) {
      installer.note('skipped  pubspec.yaml hooks (already there)');
      return;
    }
    StringBuffer block = StringBuffer(
      '\n# Skip the build of the native database drivers this app does not\n'
      '# use. To use one, remove its two lines.\n'
      'hooks:\n'
      '  user_defines:\n',
    );
    for (String other in <String>['postgres', 'mysql']) {
      if (other == driver) continue;
      block.write('    dox_${other}_native:\n      skip: true\n');
    }
    if (!text.endsWith('\n')) text = '$text\n';
    pubspec.writeAsStringSync('$text$block');
    installer.note('added    hooks to pubspec.yaml');
  }

  /// the getters of `AppEnv` that `lib/config/database.dart` reads
  static List<String> envGetters(String driver) {
    return <String>[
      '/// development, staging or production. Not set: production.\n'
          "  String get appEnv => 'production';",
      '/// a database url, eg. `postgres://user:pass@host:5432/db`.\n'
          '  /// When set, it wins over the DB_* keys (see DatabaseConfig.url).\n'
          '  String? get databaseUrl;',
      '/// sqlite, postgres or mysql\n'
          "  String get dbConnection => '$driver';",
      '/// the database name. For SQLite: the file path.\n'
          "  String get dbName => 'db/dox.sqlite';",
      "String get dbHost => 'localhost';",
      '/// null: 5432 for Postgres, 3306 for MySQL\n'
          '  int? get dbPort;',
      "String get dbUsername => 'postgres';",
      "String get dbPassword => '';",
    ];
  }

  /// the `.env` keys of [driver]
  static Map<String, String> envKeys(String driver) {
    return switch (driver) {
      'postgres' => <String, String>{
        'DB_CONNECTION': 'postgres',
        'DB_HOST': 'localhost',
        'DB_PORT': '5432',
        'DB_NAME': 'dox',
        'DB_USERNAME': 'postgres',
        'DB_PASSWORD': 'postgres',
      },
      'mysql' => <String, String>{
        'DB_CONNECTION': 'mysql',
        'DB_HOST': 'localhost',
        'DB_PORT': '3306',
        'DB_NAME': 'dox',
        'DB_USERNAME': 'root',
        'DB_PASSWORD': '',
      },
      _ => <String, String>{
        'DB_CONNECTION': 'sqlite',
        'DB_NAME': 'db/dox.sqlite',
      },
    };
  }

  /// `lib/config/database.dart`, the same as the app template
  static String databaseConfig(String app) {
    return '''
import 'package:dox_orm/dox_orm.dart';
import 'package:$app/config/env.dart';

/// Print every SQL query only in development.
/// Printing each query costs time, so it is off in production.
/// Not `appConfig`: config/app.dart imports this file through the
/// generated container, so reading it here makes an import cycle.
bool _debug = env.appEnv == 'development';

DatabaseConfig databaseConfig = DatabaseConfig(
  /// Database url
  /// -------------------------------
  /// `DATABASE_URL` from `.env` or the environment, the same one that
  /// `dox migrate` reads. When it is set, it wins over the DB_* keys.
  url: env.databaseUrl,

  /// Connection
  /// -------------------------------
  /// The connection to use. It is one key of `connections` below.
  connection: env.dbConnection,

  connections: <String, ConnectionConfig>{
    /// Postgres
    'postgres': ConnectionConfig(
      driver: Driver.postgres,
      host: env.dbHost,
      port: env.dbPort ?? 5432,
      user: env.dbUsername,
      password: env.dbPassword,
      database: env.dbName,
      extra: <String, dynamic>{
        /// All isolates of the process share one pool,
        /// so this is the limit for the whole process.
        'maxConnectionCount': 10,
      },
      debug: _debug,
      printer: PrettyQueryPrinter(),
    ),

    /// MySQL and MariaDB
    'mysql': ConnectionConfig(
      driver: Driver.mysql,
      host: env.dbHost,
      port: env.dbPort ?? 3306,
      user: env.dbUsername,
      password: env.dbPassword,
      database: env.dbName,
      extra: <String, dynamic>{
        /// All isolates of the process share one pool,
        /// so this is the limit for the whole process.
        'maxConnectionCount': 10,
      },
      debug: _debug,
      printer: PrettyQueryPrinter(),
    ),

    /// SQLite. `DB_NAME` is a file path, or `:memory:`.
    'sqlite': ConnectionConfig(
      driver: Driver.sqlite,
      database: env.dbName,
      debug: _debug,
      printer: PrettyQueryPrinter(),
    ),
  },
);
''';
  }

  /// `lib/providers/orm_provider.dart`, the same as the app template
  static String ormProvider(String app) {
    return '''
import 'package:dox_core/dox_core.dart';
import 'package:dox_orm/dox_orm.dart';
import 'package:$app/config/database.dart';

/// Query builder provider
/// --------------------------
/// Sets up the query builder, so this project can use the ORM.
/// If this project does not need a database, delete this file
/// (Dox finds every DoxProvider class, see lib/generated/container.g.dart).
class ORMProvider extends DoxProvider {
  @override
  Future<void> setup() async {
    SqlQueryBuilder.initializeWithDatabaseConfig(databaseConfig);
  }

  /// Close the database connections when the server stops.
  @override
  Future<void> shutdown() async {
    await SqlQueryBuilder.close();
  }
}
''';
  }

  /// `bin/migrate.dart`, the same as `dox make:migration` makes
  static const String migrateEntry = '''
import 'dart:io';

import 'package:dox_migration/dox_migration.dart';

import '../db/migration/migrations.dart';

/// run the migrations of db/migration (Dart and .sql files):
/// `dart run bin/migrate.dart <run|rollback [--step=n|--batch=n]|reset|refresh|status>`.
/// `dox migration:*` commands run this file.
/// the database is from `.env` (DB_CONNECTION, DB_HOST, DB_PORT, ...).
Future<void> main(List<String> args) async {
  exitCode = await Migrator(migrations: migrations).run(args);
}
''';

  /// an empty `db/migration/migrations.dart`. `dox make:migration` and
  /// `dox migrate` write it again from the files of the folder.
  static const String migrationList = '''
// Made by `dox make:migration` and the `dox migration:*` commands.
// Do not edit, it is made again from the files in this folder.
import 'package:dox_migration/dox_migration.dart';

/// all Dart migrations of db/migration, sorted by name
final List<MigrationEntry> migrations = <MigrationEntry>[];
''';
}
