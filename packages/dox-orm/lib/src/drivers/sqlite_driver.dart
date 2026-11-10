import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dox_orm/dox_orm.dart';
import 'package:sqlite3/sqlite3.dart';

/// zone key to find the databases that have an open transaction
const Symbol _txKey = #doxSqliteTransaction;

/// declared column kinds that need a conversion on read
const int _kBool = 1;
const int _kJson = 2;
const int _kDate = 3;

/// driver for sqlite (package `sqlite3`, ffi).
///
/// ponytail: sqlite3 is synchronous, so a query blocks this isolate while it
/// runs. there is one connection per isolate, and while a transaction is
/// open, other queries of this isolate wait until it ends. good for dev,
/// tests and small apps. use postgres or mysql when you need more.
///
/// with `extra['background']` the database lives in a helper isolate
/// ([SqliteIsolate]), so a slow query does not block this isolate.
class SqliteDriver extends DBDriver {
  /// a sqlite `Database`, a `Future` of it, or a [SqliteIsolate]
  dynamic conn;

  /// max prepared statements kept for the database
  final int statementCacheSize;

  /// constructor
  SqliteDriver({
    required this.conn,
    this.statementCacheSize = defaultStatementCacheSize,
  });

  /// prepared statements of each database, by sql text
  static final Expando<StatementCache<PreparedStatement>> _caches =
      Expando<StatementCache<PreparedStatement>>();

  static final Expando<Future<void>> _transactionDone = Expando<Future<void>>();

  static final Expando<_Schema> _schemas = Expando<_Schema>();

  /// RETURNING is in sqlite 3.35 and newer
  static final bool _hasReturning = sqlite3.version.versionNumber >= 3035000;

  @override
  Driver getName() {
    return Driver.sqlite;
  }

  @override
  bool get supportsReturning => _hasReturning;

  /// the `Database` (or the [SqliteIsolate] that owns it) when this zone
  /// can use it now, else null: it is still opening, or a transaction of
  /// another zone is open on it.
  ///
  /// the callers check it and use the database with no `await` in
  /// between. so a transaction that starts in the same event-loop turn
  /// can not take the database in that gap, and a plain query can not
  /// slip into it.
  Object? _ready() {
    Object? c = conn;
    if (c is Future) return null;
    // close() ran while this query waited
    if (c == null) throw StateError('the sqlite database is closed');
    Object db = c;
    if (!_inTransaction(db) && _transactionDone[db] != null) return null;
    return db;
  }

  /// wait until [_ready] may give the database
  Future<void> _waitReady() async {
    Object? c = conn;
    if (c is Future) {
      conn = await c;
      return;
    }
    if (c != null) await _transactionDone[c];
  }

  /// close the kept statements and the database
  @override
  Future<void> close() async {
    Object? c = conn;
    try {
      if (c is Future) c = conn = await c;
    } catch (_) {
      conn = null;
      return;
    }
    if (c is SqliteIsolate) {
      conn = null;
      await c.close();
      return;
    }
    if (c is! Database) return;
    clearStatementCache();
    conn = null;
    c.close();
  }

  bool _inTransaction(Object db) {
    Set<Object>? open = Zone.current[_txKey];
    return open?.contains(db) ?? false;
  }

  /// run query and return map result
  @override
  Future<List<Map<String, dynamic>>> query(
    String query, {
    String? primaryKey,
    Map<String, dynamic>? substitutionValues,
  }) async {
    Object? db;
    while ((db = _ready()) == null) {
      await _waitReady();
    }
    if (db is SqliteIsolate) {
      return await db._call(
        _SqliteOp.query,
        query,
        substitutionValues,
        primaryKey,
      ) as List<Map<String, dynamic>>;
    }
    return _query(db as Database, query, substitutionValues, primaryKey);
  }

  List<Map<String, dynamic>> _query(
    Database db,
    String query,
    Map<String, dynamic>? substitutionValues,
    String? primaryKey,
  ) {
    var (String sql, List<Object?> params) = toPositionalParams(
      query,
      substitutionValues,
      _toSqliteValue,
    );
    PreparedStatement statement = _statement(db, sql);
    ResultSet result;
    try {
      result = statement.select(params);
    } finally {
      statement.reset();
    }

    if (result.columnNames.isEmpty) {
      /// old sqlite without RETURNING: give the new row id of an insert
      if (primaryKey != null &&
          db.updatedRows > 0 &&
          sql.trimLeft().toUpperCase().startsWith('INSERT')) {
        return <Map<String, dynamic>>[
          <String, dynamic>{primaryKey: db.lastInsertRowId},
        ];
      }
      return <Map<String, dynamic>>[];
    }
    return _toMapList(db, sql, result);
  }

  /// sqlite counts the rows the query matched, not the rows changed by
  /// triggers or foreign key actions
  @override
  Future<int> affectingStatement(
    String query, {
    Map<String, dynamic>? substitutionValues,
  }) async {
    Object? db;
    while ((db = _ready()) == null) {
      await _waitReady();
    }
    if (db is SqliteIsolate) {
      return await db._call(_SqliteOp.affecting, query, substitutionValues)
          as int;
    }
    return _affecting(db as Database, query, substitutionValues);
  }

  int _affecting(
    Database db,
    String query,
    Map<String, dynamic>? substitutionValues,
  ) {
    var (String sql, List<Object?> params) = toPositionalParams(
      query,
      substitutionValues,
      _toSqliteValue,
    );
    PreparedStatement statement = _statement(db, sql);
    try {
      statement.execute(params);
    } finally {
      statement.reset();
    }

    /// sqlite3 is sync, so no other query ran since the execute
    return db.updatedRows;
  }

  /// only run query
  @override
  Future<void> execute(
    String query, {
    Map<String, dynamic>? substitutionValues,
  }) async {
    Object? db;
    while ((db = _ready()) == null) {
      await _waitReady();
    }
    if (db is SqliteIsolate) {
      await db._call(_SqliteOp.execute, query, substitutionValues);
      return;
    }
    _execute(db as Database, query, substitutionValues);
  }

  void _execute(
    Database db,
    String query,
    Map<String, dynamic>? substitutionValues,
  ) {
    var (String sql, List<Object?> params) = toPositionalParams(
      query,
      substitutionValues,
      _toSqliteValue,
    );

    /// no params: sqlite can run many statements in one text
    if (params.isEmpty) {
      db.execute(sql);
      return;
    }
    PreparedStatement statement = _statement(db, sql);
    try {
      statement.execute(params);
    } finally {
      statement.reset();
    }
  }

  /// the statement cache of [db], or null when it has none yet
  StatementCache<PreparedStatement>? statementCacheOf(Database db) {
    return _caches[db];
  }

  /// close all kept statements, eg. before you close the database
  void clearStatementCache() {
    if (conn is! Database) {
      return;
    }
    for (PreparedStatement statement
        in _caches[conn]?.clear() ?? <PreparedStatement>[]) {
      statement.close();
    }
  }

  /// the kept statement of [sql], prepared once
  PreparedStatement _statement(Database db, String sql) {
    StatementCache<PreparedStatement> cache = _caches[db] ??=
        StatementCache<PreparedStatement>(statementCacheSize);
    PreparedStatement? statement = cache.get(sql);
    if (statement != null) {
      return statement;
    }
    statement = db.prepare(sql, persistent: true, checkNoTail: true);
    cache.put(sql, statement)?.close();
    return statement;
  }

  @override
  Future<R> transaction<R>(Future<R> Function() callback) async {
    Object? ready;
    while ((ready = _ready()) == null) {
      await _waitReady();
    }
    Object db = ready as Object;

    /// a nested transaction uses a savepoint
    if (_inTransaction(db)) {
      return savepoint(callback);
    }

    /// [_ready] checked that no other transaction is open
    Completer<void> done = Completer<void>();
    _transactionDone[db] = done.future;

    Set<Object> open = <Object>{...?Zone.current[_txKey], db};
    try {
      /// IMMEDIATE takes the write lock now, so two isolates do not both
      /// read and then fail to upgrade to a write
      await _now(db, _SqliteOp.execute, 'BEGIN IMMEDIATE');
      R result = await runZoned(
        callback,
        zoneValues: <Symbol, dynamic>{_txKey: open},
      );
      await _now(db, _SqliteOp.execute, 'COMMIT');
      return result;
    } catch (error) {
      await _now(db, _SqliteOp.rollback, '');
      rethrow;
    } finally {
      _transactionDone[db] = null;
      done.complete();
    }
  }

  /// run [op] with no params on [db] right away. it does not wait for the
  /// open transaction, so the transaction itself uses it.
  Future<void> _now(Object db, _SqliteOp op, String sql) async {
    if (db is SqliteIsolate) {
      await db._call(op, sql, null);
      return;
    }
    _run(db as Database, op, sql, null, null);
  }

  /// run [op] on [db]. the helper isolate runs each request with it.
  Object? _run(
    Database db,
    _SqliteOp op,
    String sql,
    Map<String, dynamic>? values,
    String? primaryKey,
  ) {
    switch (op) {
      case _SqliteOp.query:
        return _query(db, sql, values, primaryKey);
      case _SqliteOp.affecting:
        return _affecting(db, sql, values);
      case _SqliteOp.execute:
        _execute(db, sql, values);
      case _SqliteOp.rollback:
        if (!db.autocommit) {
          db.execute('ROLLBACK');
        }
    }
    return null;
  }

  /// sqlite gives int, double, String, Uint8List or null. it has no bool,
  /// json or date type, so convert by the declared column type:
  /// BOOLEAN to bool, JSON to map/list, DATE/DATETIME/TIMESTAMP to DateTime.
  List<Map<String, dynamic>> _toMapList(
    Database db,
    String sql,
    ResultSet result,
  ) {
    List<String> names = result.columnNames;
    Map<String, int> kinds = _schemaOf(db).kindsFor(sql);
    List<int> columnKinds = <int>[for (String n in names) kinds[n] ?? 0];
    bool convert = columnKinds.any((int k) => k != 0);
    int length = names.length;

    List<Map<String, dynamic>> list = <Map<String, dynamic>>[];
    for (List<Object?> row in result.rows) {
      Map<String, dynamic> data = <String, dynamic>{};
      for (int i = 0; i < length; i++) {
        Object? value = row[i];
        data[names[i]] = convert && value != null
            ? _convert(columnKinds[i], value)
            : value;
      }
      list.add(data);
    }
    return list;
  }

  dynamic _convert(int kind, Object value) {
    if (kind == _kBool && value is int) {
      return value != 0;
    }
    if (kind == _kJson && value is String) {
      try {
        return jsonDecode(value);
      } catch (error) {
        /// not json, keep the text
        return value;
      }
    }
    if (kind == _kDate && value is String) {
      return parseDbDate(value);
    }
    return value;
  }

  _Schema _schemaOf(Database db) {
    _Schema schema = _schemas[db] ??= _Schema();
    schema.refresh(db);
    return schema;
  }

  static Object? _toSqliteValue(dynamic value) {
    if (value == null || value is int || value is double || value is String) {
      return value;
    } else if (value is bool) {
      return value ? 1 : 0;
    } else if (value is Map || value is List) {
      return jsonEncode(value);
    } else if (value is DateTime) {
      /// ISO text in UTC, so text order is time order
      return value.toUtc().toIso8601String();
    }
    return value.toString();
  }
}

/// declared column kinds of each table, read again when the schema changes
class _Schema {
  int _version = -1;

  /// table name => column name => kind
  Map<String, Map<String, int>> _tables = <String, Map<String, int>>{};

  /// result of [kindsFor] for each sql text
  final Map<String, Map<String, int>> _bySql = <String, Map<String, int>>{};

  PreparedStatement? _versionStatement;

  void refresh(Database db) {
    PreparedStatement statement = _versionStatement ??= db.prepare(
      'PRAGMA schema_version',
      persistent: true,
    );
    int version;
    try {
      version = statement.select().first.columnAt(0) as int;
    } finally {
      statement.reset();
    }
    if (version == _version) {
      return;
    }
    _bySql.clear();
    Map<String, Map<String, int>> tables = <String, Map<String, int>>{};
    ResultSet rows = db.select(
      "SELECT m.name AS t, p.name AS c, p.type AS ty FROM sqlite_schema m "
      "JOIN pragma_table_info(m.name) p WHERE m.type = 'table'",
    );
    for (Row row in rows) {
      int kind = _kindOf((row['ty'] as String).toUpperCase());
      if (kind != 0) {
        (tables[row['t'] as String] ??= <String, int>{})[row['c'] as String] =
            kind;
      }
    }
    _tables = tables;
    _version = version;
  }

  int _kindOf(String type) {
    if (type.contains('BOOL')) return _kBool;
    if (type == 'JSON' || type == 'JSONB') return _kJson;
    if (type.contains('DATE') || type.contains('TIMESTAMP')) return _kDate;
    return 0;
  }

  /// ponytail: sqlite (as bundled) can not tell which table a result column
  /// comes from. so use the typed columns of every table whose name is in
  /// [sql]. an alias or a same-named column of another table may be
  /// converted too, cast in sql if that matters.
  Map<String, int> kindsFor(String sql) {
    Map<String, int>? known = _bySql[sql];
    if (known != null) {
      return known;
    }
    if (_bySql.length >= 2000) {
      _bySql.clear();
    }
    Map<String, int> kinds = _bySql[sql] = <String, int>{};
    for (MapEntry<String, Map<String, int>> table in _tables.entries) {
      if (sql.contains(table.key)) {
        for (MapEntry<String, int> col in table.value.entries) {
          kinds.putIfAbsent(col.key, () => col.value);
        }
      }
    }
    return kinds;
  }
}

/// SQLITE_BUSY: the database file is locked by another connection.
const int _sqliteBusy = 5;

/// open sqlite database file (made if missing), or `:memory:`.
/// - WAL: readers do not wait for the writer, faster writes.
/// - busy_timeout: wait for a lock (eg. another isolate writing)
///   instead of failing right away.
/// - foreign_keys: sqlite turns them off by default.
Database openSqliteDatabase(String database, int busyTimeout) {
  Database db = database == ':memory:'
      ? sqlite3.openInMemory()
      : sqlite3.open(database);
  db.execute('PRAGMA busy_timeout = $busyTimeout');
  if (database != ':memory:') {
    _switchToWal(db, busyTimeout);
    db.execute('PRAGMA synchronous = NORMAL');
  }
  db.execute('PRAGMA foreign_keys = ON');
  return db;
}

/// switching a new file to WAL fails right away with SQLITE_BUSY when
/// another isolate does the same at that moment: sqlite does not use
/// busy_timeout here. So retry until [busyTimeout] ms have passed.
void _switchToWal(Database db, int busyTimeout) {
  Stopwatch watch = Stopwatch()..start();
  while (true) {
    try {
      db.execute('PRAGMA journal_mode = WAL');
      return;
    } on SqliteException catch (e) {
      if (e.resultCode != _sqliteBusy ||
          watch.elapsedMilliseconds >= busyTimeout) {
        rethrow;
      }
      sleep(const Duration(milliseconds: 10));
    }
  }
}

/// the work a request asks the helper isolate to do
enum _SqliteOp { query, affecting, execute, rollback }

/// a sqlite database that lives in a helper isolate. the helper opens it,
/// runs every request on it in the order they come, and closes it. this
/// isolate only waits for the answer, so a slow query does not stop it.
///
/// each request is one message to the helper and one back. a SQL error
/// comes back as the same `SqliteException`. when the helper stops, every
/// waiting request gets a [StateError].
class SqliteIsolate {
  /// the answers from the helper, and its exit
  final RawReceivePort _port = RawReceivePort();

  /// the port of the helper, set when the database is open
  final Completer<SendPort> _requests = Completer<SendPort>();

  /// done when the helper isolate has ended
  final Completer<void> _exited = Completer<void>();

  /// the requests that wait for an answer, by id
  final Map<int, Completer<Object?>> _waiting = <int, Completer<Object?>>{};

  int _nextId = 0;

  /// why no more requests can run: closed, or the helper stopped
  String? _stopped;

  /// the helper isolate, null until it has started
  Isolate? isolate;

  /// start a helper isolate that opens [database], like
  /// [openSqliteDatabase] does.
  SqliteIsolate(String database, int busyTimeout, int statementCacheSize) {
    _port.handler = _onMessage;
    _requests.future.ignore();
    unawaited(_start(database, busyTimeout, statementCacheSize));
  }

  Future<void> _start(
    String database,
    int busyTimeout,
    int statementCacheSize,
  ) async {
    try {
      isolate = await Isolate.spawn(
        _SqliteHelper.main,
        (
          _port.sendPort,
          database,
          busyTimeout,
          statementCacheSize,
          Isolate.current,
        ),
        onExit: _port.sendPort,
        debugName: 'dox sqlite',
      );
    } catch (error, stack) {
      _stop('the sqlite helper isolate did not start');
      if (!_requests.isCompleted) _requests.completeError(error, stack);
      _port.close();
      _exited.complete();
    }
  }

  /// send one request to the helper and wait for its answer
  Future<Object?> _call(
    _SqliteOp op,
    String sql,
    Map<String, dynamic>? values, [
    String? primaryKey,
  ]) async {
    SendPort requests = await _requests.future;
    if (_stopped != null) {
      throw StateError(_stopped!);
    }

    /// plain values only: they can always go to the other isolate
    Map<String, dynamic>? sendable = values == null
        ? null
        : <String, dynamic>{
            for (MapEntry<String, dynamic> e in values.entries)
              e.key: SqliteDriver._toSqliteValue(e.value),
          };
    int id = _nextId++;
    Completer<Object?> answer = Completer<Object?>();
    _waiting[id] = answer;
    _port.keepIsolateAlive = true;
    requests.send((id, op, sql, sendable, primaryKey));
    return answer.future;
  }

  void _onMessage(Object? message) {
    switch (message) {
      case SendPort requests:
        _requests.complete(requests);
        _port.keepIsolateAlive = _waiting.isNotEmpty;
      case (int id, Object? result):
        _answer(id)?.complete(result);
      case (int id, Object error, String stack):
        Completer<Object?>? answer = _answer(id);
        if (answer != null) {
          answer.completeError(error, StackTrace.fromString(stack));
        } else if (!_requests.isCompleted) {
          /// the database did not open
          _stop('the sqlite database did not open: $error');
          _requests.completeError(error, StackTrace.fromString(stack));
        }
      case null:

        /// the helper isolate ended
        _stop('the sqlite helper isolate stopped');
        if (!_requests.isCompleted) {
          _requests.completeError(StateError(_stopped!));
        }
        _port.close();
        _exited.complete();
    }
  }

  Completer<Object?>? _answer(int id) {
    Completer<Object?>? answer = _waiting.remove(id);
    if (_waiting.isEmpty) {
      /// idle: do not keep this isolate (or `dart run`) alive
      _port.keepIsolateAlive = false;
    }
    return answer;
  }

  /// no more requests. every waiting request gets an error with [reason].
  void _stop(String reason) {
    _stopped ??= reason;
    for (Completer<Object?> answer in _waiting.values) {
      answer.completeError(StateError(_stopped!));
    }
    _waiting.clear();
  }

  /// close the database and end the helper isolate. requests sent before
  /// it finish first. requests after it throw a [StateError].
  Future<void> close() async {
    if (_stopped == null) {
      _stopped = 'the sqlite database is closed';
      try {
        SendPort requests = await _requests.future;
        _port.keepIsolateAlive = true;
        requests.send(null);
      } catch (_) {
        /// it did not start: nothing to close
      }
    }
    await _exited.future;
  }
}

/// runs in the helper isolate: owns the database and answers requests
class _SqliteHelper {
  final Database db;
  final SqliteDriver driver;
  final SendPort answers;
  final RawReceivePort requests = RawReceivePort();

  _SqliteHelper(this.db, this.driver, this.answers);

  static void main((SendPort, String, int, int, Isolate) setup) {
    var (
      SendPort answers,
      String database,
      int busyTimeout,
      int cacheSize,
      Isolate parent,
    ) = setup;
    Database db;
    try {
      db = openSqliteDatabase(database, busyTimeout);
    } catch (error, stack) {
      _sendError(answers, -1, error, stack);
      return;
    }
    _SqliteHelper helper = _SqliteHelper(
      db,
      SqliteDriver(conn: db, statementCacheSize: cacheSize),
      answers,
    );
    helper.requests.handler = helper.onRequest;

    /// close the database when the isolate that made it ends
    parent.addOnExitListener(helper.requests.sendPort);
    answers.send(helper.requests.sendPort);
  }

  void onRequest(Object? message) {
    if (message case (
      int id,
      _SqliteOp op,
      String sql,
      Map<String, dynamic>? values,
      String? primaryKey,
    )) {
      try {
        answers.send((id, driver._run(db, op, sql, values, primaryKey)));
      } catch (error, stack) {
        _sendError(answers, id, error, stack);
      }
      return;
    }

    /// null: close, or the isolate that made it has ended
    driver.clearStatementCache();
    db.close();
    requests.close();
  }

  /// send [error] as it is (eg. a `SqliteException` with all its fields),
  /// or as a [StateError] with its text when it can not be sent
  static void _sendError(
    SendPort answers,
    int id,
    Object error,
    StackTrace stack,
  ) {
    try {
      answers.send((id, error, '$stack'));
    } catch (_) {
      answers.send((id, StateError('$error'), '$stack'));
    }
  }
}
