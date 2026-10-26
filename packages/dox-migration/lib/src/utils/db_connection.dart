import 'dart:async';

import 'package:dox_orm/dox_orm.dart';
import 'package:sqlite3/sqlite3.dart';

/// Runs migration queries on a dox_orm [DBDriver]: the native Postgres or
/// MySQL driver, or the sqlite driver. Use `@name` for values in queries.
class DbConnection {
  final DBDriver driver;

  DbConnection(this.driver);

  bool get isMysql => driver.getName() == Driver.mysql;

  bool get isSqlite => driver.getName() == Driver.sqlite;

  /// The database config from [env].
  ///
  /// `DATABASE_URL` wins when it is set (see `ConnectionConfig.fromUrl`).
  /// Else `DB_CONNECTION` (postgres, mysql or sqlite), `DB_HOST`,
  /// `DB_PORT`, `DB_USERNAME`, `DB_PASSWORD` and `DB_DATABASE` (or
  /// `DB_NAME`). For sqlite, the database is the file path. A host that
  /// starts with `/` is a Unix socket: the socket folder for Postgres, the
  /// socket file for MySQL.
  ///
  /// The defaults are the same as in the app template: sqlite with the
  /// file `db/dox.sqlite`. So with an empty `.env`, the migrations and the
  /// app use the same database. Postgres and MySQL use the database `dox`
  /// when no name is set.
  static ConnectionConfig config(Map<String, String> env) {
    String? url = env['DATABASE_URL']?.trim();
    if (url != null && url.isNotEmpty) {
      return ConnectionConfig.fromUrl(url);
    }
    String? connection = env['DB_CONNECTION'];
    Driver driver = switch (connection) {
      null || 'sqlite' => Driver.sqlite,
      'mysql' => Driver.mysql,
      'postgres' => Driver.postgres,
      _ => throw ArgumentError.value(
        connection,
        'DB_CONNECTION',
        'use sqlite, postgres or mysql',
      ),
    };
    bool isMysql = driver == Driver.mysql;
    String database =
        env['DB_DATABASE'] ??
        env['DB_NAME'] ??
        (driver == Driver.sqlite ? 'db/dox.sqlite' : 'dox');
    return ConnectionConfig(
      driver: driver,
      host: env['DB_HOST'] ?? 'localhost',
      port: int.parse(env['DB_PORT'] ?? (isMysql ? '3306' : '5432')),
      user: env['DB_USERNAME'] ?? (isMysql ? 'root' : 'postgres'),
      password: env['DB_PASSWORD'] ?? (isMysql ? '' : 'postgres'),
      database: database,
      debug: false,
    );
  }

  /// open a driver with the config from [env], see [config].
  /// Postgres and MySQL throw an [UnsupportedError] when their native
  /// library does not load.
  static Future<DbConnection> open(Map<String, String> env) async {
    return DbConnection(config(env).createDriver());
  }

  /// run query and return rows as list of column maps
  Future<List<Map<String, dynamic>>> execute(
    String query, [
    Map<String, dynamic>? values,
  ]) {
    return driver.query(query, substitutionValues: values);
  }

  /// run [callback] in one transaction on one connection. commit when it
  /// ends, rollback when it throws. queries of [driver] inside [callback]
  /// use the transaction.
  Future<T> transaction<T>(Future<T> Function() callback) {
    return driver.transaction(callback);
  }

  /// how long to wait before the next try to get the migration lock
  static const Duration lockRetry = Duration(milliseconds: 100);

  /// run [task] while this runner holds the migration lock. So when many
  /// app instances start at once, only one runs the migrations at a time.
  /// The others wait, then run [task] when the lock is free.
  ///
  /// - Postgres: `pg_try_advisory_xact_lock`. The lock is held by a
  ///   transaction that stays open on its own pool connection.
  /// - MySQL and MariaDB: `GET_LOCK` and `RELEASE_LOCK`, on one pool
  ///   connection the same way. The lock name has the database name.
  /// - SQLite: an exclusive transaction on the file `<database>.lock`,
  ///   next to the database file. An in memory database needs no lock.
  ///
  /// The lock is released when [task] ends or throws. When the process
  /// dies, the database (or the OS for SQLite) releases it.
  ///
  /// ponytail: Postgres and MySQL need a pool with 2 or more connections:
  /// one holds the lock, one runs [task]. The default pool has 10.
  Future<T> withLock<T>(Future<T> Function() task) async {
    if (isSqlite) return _withSqliteLock(task);
    Completer<void> locked = Completer<void>();
    Completer<void> done = Completer<void>();
    Future<void> holder = transaction(() async {
      while (!await _tryLock()) {
        await Future<void>.delayed(lockRetry);
      }
      try {
        locked.complete();
        await done.future;
      } finally {
        /// postgres releases an xact lock on commit, mysql does not
        if (isMysql) {
          await execute('SELECT RELEASE_LOCK($_mysqlLockName) AS released');
        }
      }
    });

    /// an error of [holder] before the lock (eg. no connection) is thrown
    await Future.any(<Future<void>>[locked.future, holder]);
    try {
      return await task();
    } finally {
      done.complete();
      await holder;
    }
  }

  /// the MySQL lock is for the whole server, so the name has the database
  static const String _mysqlLockName = "CONCAT('dox_migration:', DATABASE())";

  /// try to get the Postgres or MySQL lock once, without waiting
  Future<bool> _tryLock() async {
    String query = isMysql
        ? 'SELECT GET_LOCK($_mysqlLockName, 0) AS ok'
        : "SELECT pg_try_advisory_xact_lock(hashtext('dox_migration')) AS ok";
    dynamic ok = (await execute(query)).first['ok'];
    return ok == true || ok.toString() == '1';
  }

  /// the SQLite lock, see [withLock]. It waits with a timer, not with a
  /// busy timeout, so other runners of this isolate can go on.
  Future<T> _withSqliteLock<T>(Future<T> Function() task) async {
    List<Map<String, dynamic>> files = await execute('PRAGMA database_list');
    String file = files.first['file']?.toString() ?? '';
    if (file.isEmpty) return await task();
    Database lock = sqlite3.open('$file.lock');
    try {
      while (true) {
        try {
          lock.execute('BEGIN EXCLUSIVE');
          break;
        } on SqliteException catch (error) {
          if (error.resultCode != SqlError.SQLITE_BUSY) rethrow;
          await Future<void>.delayed(lockRetry);
        }
      }
      return await task();
    } finally {
      /// closing the file ends the transaction, so the lock is free
      lock.close();
    }
  }

  Future<void> close() => driver.close();
}
