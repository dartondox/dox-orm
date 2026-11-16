import 'dart:async';
import 'dart:math';

import 'package:dox_mysql_native/dox_mysql_native.dart';
import 'package:dox_orm/dox_orm.dart';
import 'package:dox_orm/src/drivers/sqlite_driver.dart';
import 'package:dox_postgres_native/dox_postgres_native.dart';

enum Driver { postgres, mysql, sqlite }

/// a callback for [DBDriver.afterCommit]
typedef AfterCommitCallback = FutureOr<void> Function();

/// the [DBDriver.afterCommit] callbacks of one transaction (or
/// savepoint). a driver makes one for each outermost transaction, see
/// [DBDriver.afterCommitZone] and [DBDriver.runAfterCommit].
class AfterCommitCallbacks {
  final List<AfterCommitCallback> _list = <AfterCommitCallback>[];

  /// the outer level, once this savepoint was released
  AfterCommitCallbacks? _movedTo;

  /// set when the transaction committed and its callbacks run
  bool _committed = false;
}

/// Stops the queries of a query builder, see [QueryBuilder.cancelWith].
///
/// ```
/// QueryCancelToken token = QueryCancelToken();
/// Future<List<Blog>> slow = Blog().cancelWith(token).get();
/// token.cancel(); // slow fails with a QueryCancelledException
/// ```
///
/// - Postgres and MySQL: the driver stops the query on the server. The
///   query then fails with `PgQueryCancelledException` or
///   `MysqlQueryCancelledException`. See their README for the details.
/// - SQLite: not supported. A query runs to its end.
/// - One token can stop many queries. After [cancel], new queries with it
///   fail at once.
class QueryCancelToken {
  bool _cancelled = false;
  PgCancelToken? _postgres;
  MysqlCancelToken? _mysql;

  /// true after [cancel]
  bool get isCancelled => _cancelled;

  /// stop the queries of this token. calling it again does nothing.
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _postgres?.cancel();
    _mysql?.cancel();
  }

  /// the token for the Postgres driver, made on the first use
  PgCancelToken get postgresToken =>
      _postgres ??= _cancelled ? (PgCancelToken()..cancel()) : PgCancelToken();

  /// the token for the MySQL driver, made on the first use
  MysqlCancelToken get mysqlToken => _mysql ??= _cancelled
      ? (MysqlCancelToken()..cancel())
      : MysqlCancelToken();
}

/// interface for database driver
abstract class DBDriver {
  /// zone key for the [QueryCancelToken] of the running query
  static const Symbol _cancelKey = #doxQueryCancelToken;

  /// the [QueryCancelToken] of the query that runs now, or null. the
  /// Postgres and MySQL drivers read it, see [withCancelToken].
  static QueryCancelToken? get currentCancelToken =>
      Zone.current[_cancelKey] as QueryCancelToken?;

  /// run [body] with [token] as [currentCancelToken]. with no [token] it
  /// just runs [body].
  static R withCancelToken<R>(QueryCancelToken? token, R Function() body) {
    if (token == null) return body();
    return runZoned(body, zoneValues: <Symbol, Object>{_cancelKey: token});
  }

  Driver getName();

  /// true when insert can use `RETURNING` to get the new id
  bool get supportsReturning => false;

  /// [value] as it goes into a column on insert or update. postgres
  /// changes a [List] to json text, because it sends a list as an array.
  Object? columnValue(dynamic value) => value;

  /// run query and return map result
  Future<List<Map<String, dynamic>>> query(
    String query, {
    String? primaryKey,
    Map<String, dynamic>? substitutionValues,
  });

  /// run [query] and give its rows in chunks of up to [chunkSize] rows,
  /// for `cursor()`. The query starts when the stream is listened to.
  /// Cancel the subscription to stop it.
  ///
  /// The built-in drivers read the rows from the database as the listener
  /// takes them, so a big result does not fill the memory. This default,
  /// for a driver of your own, runs [query] and splits all its rows.
  Stream<List<Map<String, dynamic>>> stream(
    String query, {
    Map<String, dynamic>? substitutionValues,
    int chunkSize = 1000,
  }) async* {
    List<Map<String, dynamic>> rows = await this.query(
      query,
      substitutionValues: substitutionValues,
    );
    for (int i = 0; i < rows.length; i += chunkSize) {
      yield rows.sublist(i, min(i + chunkSize, rows.length));
    }
  }

  /// run query, this function do not return any value
  Future<void> execute(
    String query, {
    Map<String, dynamic>? substitutionValues,
  });

  /// run [query] (an UPDATE, DELETE or INSERT) and return the number of
  /// rows it changed.
  ///
  /// ```
  /// int count = await driver.affectingStatement(
  ///   'UPDATE blog SET status = @status WHERE id = @id',
  ///   substitutionValues: <String, dynamic>{'status': 'done', 'id': 1},
  /// );
  /// ```
  ///
  /// - Postgres and SQLite count every row the query matched.
  /// - MySQL and MariaDB count only the rows that really changed. An
  ///   UPDATE that sets a row to the values it already has counts 0 (the
  ///   pool does not set CLIENT_FOUND_ROWS). An upsert counts 1 for each
  ///   new row and 2 for each updated row.
  ///
  /// A custom driver must override it to use update(), delete(),
  /// increment() and upsert().
  Future<int> affectingStatement(
    String query, {
    Map<String, dynamic>? substitutionValues,
  }) async {
    throw UnsupportedError(
      '$runtimeType can not give the number of changed rows. '
      'Override affectingStatement().',
    );
  }

  /// run [callback] in one database transaction.
  /// commit when it ends, rollback when it throws.
  /// all queries inside [callback] (models too) use the transaction.
  /// inside another transaction it uses a savepoint, see [savepoint].
  Future<R> transaction<R>(Future<R> Function() callback);

  /// zone key for how deep the savepoints are
  static const Symbol _savepointKey = #doxSavepointDepth;

  /// run [callback] in a savepoint of the open transaction. the drivers
  /// call it for a nested [transaction]. when [callback] throws, only its
  /// work is undone and the error is thrown again. the outer transaction
  /// stays open, so the caller can catch the error and go on.
  ///
  /// ponytail: one savepoint at a time per transaction. two nested
  /// transactions that run at the same time (eg. in `Future.wait`) mix up
  /// their savepoints, the same as any queries on one connection.
  Future<R> savepoint<R>(Future<R> Function() callback) async {
    int depth = (Zone.current[_savepointKey] as int? ?? 0) + 1;
    String name = 'sp_$depth';
    await execute('SAVEPOINT $name');

    /// [afterCommit] callbacks of this savepoint. they move to the outer
    /// level when it is released, and are dropped when it rolls back.
    AfterCommitCallbacks? outer = _afterCommitLevel;
    AfterCommitCallbacks callbacks = AfterCommitCallbacks();
    R result;
    try {
      result = await runZoned(
        callback,
        zoneValues: <Symbol, dynamic>{
          _savepointKey: depth,
          if (outer != null) ...afterCommitZone(callbacks),
        },
      );
    } catch (_) {
      try {
        await execute('ROLLBACK TO SAVEPOINT $name');
        // ROLLBACK TO keeps the savepoint open. Release it, so caught
        // errors do not pile up open savepoints until the end.
        await execute('RELEASE SAVEPOINT $name');
      } catch (_) {
        // keep the first error: it tells what went wrong
      }
      rethrow;
    }
    await execute('RELEASE SAVEPOINT $name');
    if (outer != null) {
      outer._list.addAll(callbacks._list);
      callbacks._movedTo = outer;
    }
    return result;
  }

  /// zone key for the [afterCommit] callbacks of each open transaction
  static const Symbol _afterCommitKey = #doxAfterCommit;

  /// [afterCommit] callbacks of the transaction (or savepoint) of this
  /// driver that is open in this zone. null when none is open.
  AfterCommitCallbacks? get _afterCommitLevel =>
      (Zone.current[_afterCommitKey]
          as Map<DBDriver, AfterCommitCallbacks>?)?[this];

  /// true when this code runs inside a transaction of this driver
  /// (connection). [inTransaction] is true for a transaction of any
  /// driver. ponytail: a custom driver that does not use [afterCommitZone]
  /// always gives false.
  bool get hasOpenTransaction => _afterCommitLevel != null;

  /// [Schema] tells the driver that the foreign key checks of the open
  /// transaction are off ([off] true) or on again. a driver with a
  /// connection setting for it (MySQL) turns them on again when the
  /// transaction ends, also after a rollback, so a pooled connection never
  /// goes back with the checks off. it does nothing by default.
  void trackForeignKeyChecks({required bool off}) {}

  /// run [callback] after the outermost transaction of this driver
  /// commits. outside a transaction it runs at once.
  ///
  /// - callbacks run one by one, in the order they were added, after the
  ///   COMMIT is done. the transaction call waits for them (async too).
  /// - a rollback drops them. a nested transaction that rolls back drops
  ///   the callbacks it added, even when the outer one commits.
  /// - a callback that throws does not undo the commit. the other
  ///   callbacks still run, then the first error is thrown by the
  ///   transaction call.
  /// - it only waits for a transaction of this driver (connection).
  /// - a late call from code that outlived its transaction (a `Timer`, a
  ///   future that was not awaited) runs at once when that transaction
  ///   committed, and is dropped when it rolled back. it never joins a
  ///   later transaction. a late call that throws gives the error to the
  ///   future it returns: await it or catch it, else it is an uncaught
  ///   async error.
  ///
  /// ```
  /// await driver.afterCommit(() => sendMail(user));
  /// ```
  Future<void> afterCommit(AfterCommitCallback callback) async {
    AfterCommitCallbacks? level = _afterCommitLevel;
    // a released savepoint gave its callbacks to the outer level
    while (level?._movedTo != null) {
      level = level!._movedTo;
    }
    if (level == null || level._committed) {
      await callback();
      return;
    }
    // ponytail: after a rollback the list never runs, so this drops it
    level._list.add(callback);
  }

  /// zone values that give a new transaction level of this driver its
  /// own [callbacks]. the drivers add them to the zone of an
  /// outermost transaction, and call [runAfterCommit] after the commit.
  ///
  /// ponytail: a custom driver that does not use it runs [afterCommit]
  /// callbacks at once, like outside a transaction.
  Map<Symbol, dynamic> afterCommitZone(AfterCommitCallbacks callbacks) {
    return <Symbol, dynamic>{
      _afterCommitKey: <DBDriver, AfterCommitCallbacks>{
        ...?Zone.current[_afterCommitKey]
            as Map<DBDriver, AfterCommitCallbacks>?,
        this: callbacks,
      },
    };
  }

  /// run the [afterCommit] [callbacks] of a committed transaction in
  /// order. when some throw, all still run and the first error is thrown.
  Future<void> runAfterCommit(AfterCommitCallbacks callbacks) async {
    callbacks._committed = true;
    List<AfterCommitCallback> list = callbacks._list;
    if (list.isEmpty) return;
    Object? error;
    StackTrace? stack;
    // by index: a late savepoint can still add to the list while it runs
    for (int i = 0; i < list.length; i++) {
      try {
        await list[i]();
      } catch (e, s) {
        if (error == null) {
          error = e;
          stack = s;
        }
      }
    }
    if (error != null) {
      Error.throwWithStackTrace(error, stack!);
    }
  }

  /// close the connections of this driver. it is safe to call it twice.
  /// do not run queries on this driver after it.
  Future<void> close() async {}

  /// zone keys the drivers use for an open transaction
  static const List<Symbol> _transactionKeys = <Symbol>[
    #doxPostgresNativeTransaction,
    #doxMysqlNativeTransaction,
    #doxSqliteTransaction,
  ];

  /// true when this code runs inside a transaction of any driver
  static bool get inTransaction {
    for (Symbol key in _transactionKeys) {
      if (Zone.current[key] != null) return true;
    }
    return false;
  }

  /// quote a table or column name, `"name"` on postgres and sqlite and
  /// `` `name` `` on mysql. it handles `table.column`, `table.*`, `*` and
  /// `column as alias`. anything else (eg. `count(*)`) throws an
  /// [ArgumentError], so user input can not add sql. use the raw methods,
  /// like `selectRaw()` or `orderByRaw()`, for expressions.
  String wrap(String value) {
    String? known = _wrapped[value];
    if (known != null) {
      return known;
    }

    /// ponytail: cleared when full, names are a small set
    if (_wrapped.length >= 1000) {
      _wrapped.clear();
    }
    return _wrapped[value] = _wrap(value);
  }

  /// quoted names, made once
  final Map<String, String> _wrapped = <String, String>{};

  String _wrap(String value) {
    value = value.trim();
    if (value.contains('->')) {
      return _wrapJson(value);
    }
    if (!_namePattern.hasMatch(value)) {
      throw ArgumentError.value(value, 'name', 'is not a plain column name');
    }
    List<String> alias = value.split(_aliasPattern);
    if (alias.length == 2) {
      return '${wrap(alias[0])} as ${_wrapPart(alias[1].trim())}';
    }
    return value.split('.').map(_wrapPart).join('.');
  }

  /// `name`, `table.name`, `table.*`, `*` and `name as alias`
  static final RegExp _namePattern = RegExp(
    r'^(?:[\p{L}\p{N}_$]+\.)*(?:[\p{L}\p{N}_$]+|\*)(?:\s+as\s+[\p{L}\p{N}_$]+)?$',
    caseSensitive: false,
    unicode: true,
  );

  static final RegExp _aliasPattern = RegExp(r'\s+as\s+', caseSensitive: false);

  /// `column` or `table.column` in front of a json path
  static final RegExp _jsonColumnPattern = RegExp(
    r'^(?:[\p{L}\p{N}_$]+\.)*[\p{L}\p{N}_$]+$',
    unicode: true,
  );

  /// a json key: letters, digits and `_` only, like whereJsonContains(),
  /// so a key can never add sql
  static final RegExp _jsonKeyPattern = RegExp(r'^\w+$');

  /// an alias name
  static final RegExp _aliasNamePattern = RegExp(
    r'^[\p{L}\p{N}_$]+$',
    unicode: true,
  );

  /// `meta->a->b` (and `meta->a as name`) as sql that reads the json
  /// value at that path:
  /// - SQLite: `json_extract("meta", '$."a"."b"')`
  /// - MySQL and MariaDB: `json_unquote(json_extract(...))`
  /// - Postgres: `CAST("meta" AS jsonb)->'a'->>'b'` (the value as text).
  ///   The cast makes it work on `json`, `jsonb` and `text` columns.
  String _wrapJson(String value) {
    List<String> alias = value.split(_aliasPattern);
    String path = alias.first;
    List<String> parts = path.split('->');
    List<String> keys = parts.sublist(1);
    if (alias.length > 2 ||
        (alias.length == 2 && !_aliasNamePattern.hasMatch(alias[1])) ||
        !_jsonColumnPattern.hasMatch(parts.first) ||
        !keys.every(_jsonKeyPattern.hasMatch)) {
      throw ArgumentError.value(
        value,
        'name',
        'is not a plain json path. Keys are letters, digits and _',
      );
    }
    String column = parts.first.split('.').map(_wrapPart).join('.');
    String sql;
    switch (getName()) {
      case Driver.sqlite:
        sql = "json_extract($column, '\$${keys.map(_jsonPathKey).join()}')";
      case Driver.mysql:
        sql =
            "json_unquote(json_extract($column, "
            "'\$${keys.map(_jsonPathKey).join()}'))";
      case Driver.postgres:
        String arrows = keys
            .sublist(0, keys.length - 1)
            .map((String k) => "->'$k'")
            .join();
        sql = "CAST($column AS jsonb)$arrows->>'${keys.last}'";
    }
    if (alias.length == 2) {
      return '$sql as ${_wrapPart(alias[1])}';
    }
    return sql;
  }

  static String _jsonPathKey(String key) => '."$key"';

  String _wrapPart(String part) {
    if (part == '*') {
      return part;
    }
    String q = getName() == Driver.mysql ? '`' : '"';
    return '$q${part.replaceAll(q, '$q$q')}$q';
  }
}

/// get database driver to run queries on [database]: a [PgNativePool] for
/// postgres, a [MysqlNativePool] for mysql, or a sqlite `Database` (or a
/// `Future` of it) for sqlite.
/// [statementCacheSize] is the max prepared statements kept (sqlite).
DBDriver getDatabaseDriver(
  Driver driver,
  dynamic database, {
  int statementCacheSize = defaultStatementCacheSize,
}) {
  if (driver == Driver.postgres) {
    return PostgresNativeDriver(database as PgNativePool);
  } else if (driver == Driver.mysql) {
    return MysqlNativeDriver(database as MysqlNativePool);
  } else if (driver == Driver.sqlite) {
    return SqliteDriver(conn: database, statementCacheSize: statementCacheSize);
  }
  throw Exception('Invalid driver or not supported');
}

/// mysql and sqlite use `?` placeholders. replace each known `@key` in the
/// order it shows in [sql], and add its value (after [convert]) in the same
/// order. unknown `@word` (eg. `@@sql_mode`) is kept as it is. `@word`
/// inside a quoted string, a quoted name or a comment is not a parameter,
/// like in the Postgres driver. set [mysql] for the MySQL rules: `\` escapes
/// a quote in a string, and `#` starts a comment.
(String, List<Object?>) toPositionalParams(
  String sql,
  Map<String, dynamic>? values,
  Object? Function(dynamic value) convert, {
  bool mysql = false,
}) {
  if (values == null || values.isEmpty) {
    return (sql, <Object?>[]);
  }

  /// fast path: the sql was seen before and every `@key` has a value
  _QuestionSql q = _QuestionSql.of(sql, mysql);
  List<String> names = q.names;
  List<Object?> params = List<Object?>.filled(names.length, null);
  for (int i = 0; i < names.length; i++) {
    String key = names[i];
    dynamic value = values[key];
    if (value == null && !values.containsKey(key)) {
      return _toPositionalSlow(sql, values, convert, mysql);
    }
    params[i] = convert(value);
  }
  return (q.sql, params);
}

(String, List<Object?>) _toPositionalSlow(
  String sql,
  Map<String, dynamic> values,
  Object? Function(dynamic value) convert,
  bool mysql,
) {
  List<Object?> params = <Object?>[];
  StringBuffer out = StringBuffer();
  int copied = 0;
  for (SqlParam p in findSqlParams(sql, mysql: mysql)) {
    if (!values.containsKey(p.name)) continue;
    out
      ..write(sql.substring(copied, p.start))
      ..write('?');
    copied = p.end;
    params.add(convert(values[p.name]));
  }
  out.write(sql.substring(copied));
  return (out.toString(), params);
}

/// one `@name` in a sql text: `sql.substring(start, end)` is `@name`
class SqlParam {
  final int start;
  final int end;
  final String name;

  const SqlParam(this.start, this.end, this.name);
}

const int _quote = 0x27; // '
const int _doubleQuote = 0x22; // "
const int _backtick = 0x60; // `
const int _backslash = 0x5c;
const int _minus = 0x2d;
const int _slash = 0x2f;
const int _star = 0x2a;
const int _hash = 0x23;
const int _atSign = 0x40;

/// a letter, a digit or `_`, like `\w`
bool _isWord(int c) =>
    (c >= 0x30 && c <= 0x39) ||
    (c >= 0x41 && c <= 0x5a) ||
    (c >= 0x61 && c <= 0x7a) ||
    c == 0x5f;

/// every `@name` of [sql] that is not inside a quoted string ('' and ""),
/// a quoted name (``) or a comment (`--`, `/* */`, and `#` for [mysql]).
/// in [mysql] mode `\` escapes the next char in a string, and `--` is a
/// comment only when a space follows, like MySQL. `/*! ... */` and
/// `/*M! ... */` are not comments in [mysql] mode: MySQL runs the SQL in
/// them, so their `@name` is found.
/// ponytail: a MySQL server with `NO_BACKSLASH_ESCAPES` does not treat `\`
/// as an escape, so a string that ends in `\` (eg. `'C:\'`) is read wrong
/// and the `@name` after it is skipped. the default sql_mode is fine.
List<SqlParam> findSqlParams(String sql, {bool mysql = false}) {
  List<SqlParam> found = <SqlParam>[];
  int n = sql.length;
  int i = 0;
  while (i < n) {
    int c = sql.codeUnitAt(i);
    if (c == _quote || c == _doubleQuote || c == _backtick) {
      // '' inside a string is a close and an open: still inside
      bool escapes = mysql && c != _backtick;
      i++;
      while (i < n) {
        int d = sql.codeUnitAt(i++);
        if (escapes && d == _backslash) {
          i++;
        } else if (d == c) {
          break;
        }
      }
    } else if (c == _minus &&
        i + 1 < n &&
        sql.codeUnitAt(i + 1) == _minus &&
        (!mysql || i + 2 >= n || sql.codeUnitAt(i + 2) <= 0x20)) {
      i = _lineEnd(sql, i);
    } else if (c == _hash && mysql) {
      i = _lineEnd(sql, i);
    } else if (c == _slash && i + 1 < n && sql.codeUnitAt(i + 1) == _star) {
      if (mysql && _isRunComment(sql, i + 2)) {
        i += 2; // MySQL runs it: scan the inside like normal sql
        continue;
      }
      int end = sql.indexOf('*/', i + 2);
      i = end < 0 ? n : end + 2;
    } else if (c == _atSign) {
      int j = i + 1;
      while (j < n && _isWord(sql.codeUnitAt(j))) {
        j++;
      }
      if (j > i + 1) {
        found.add(SqlParam(i, j, sql.substring(i + 1, j)));
      }
      i = j;
    } else {
      i++;
    }
  }
  return found;
}

/// true when [sql] has `!` or `M!` at [i]: a `/*!` or `/*M!` block
bool _isRunComment(String sql, int i) =>
    sql.startsWith('!', i) || sql.startsWith('M!', i);

/// index of the line break after [i], or the end of [sql]
int _lineEnd(String sql, int i) {
  while (i < sql.length &&
      sql.codeUnitAt(i) != 0x0a &&
      sql.codeUnitAt(i) != 0x0d) {
    i++;
  }
  return i;
}

/// sql with every `@key` changed to `?`, made once per sql text
class _QuestionSql {
  final String sql;

  /// key of each `?`, in order
  final List<String> names;

  _QuestionSql(this.sql, this.names);

  /// ponytail: cleared when full, an LRU is not needed for sql texts
  static final Map<String, _QuestionSql> _cache = <String, _QuestionSql>{};
  static final Map<String, _QuestionSql> _mysqlCache = <String, _QuestionSql>{};

  static _QuestionSql of(String sql, bool mysql) {
    Map<String, _QuestionSql> cache = mysql ? _mysqlCache : _cache;
    _QuestionSql? q = cache[sql];
    if (q != null) {
      return q;
    }
    if (cache.length >= 2000) {
      cache.clear();
    }
    List<String> names = <String>[];
    StringBuffer out = StringBuffer();
    int copied = 0;
    for (SqlParam p in findSqlParams(sql, mysql: mysql)) {
      names.add(p.name);
      out
        ..write(sql.substring(copied, p.start))
        ..write('?');
      copied = p.end;
    }
    out.write(sql.substring(copied));
    return cache[sql] = _QuestionSql(out.toString(), names);
  }
}

/// parse a date from mysql or sqlite. a date without time zone is read as
/// UTC. return [value] as it is when it is not a date.
dynamic parseDbDate(dynamic value) {
  DateTime? d = value is DateTime ? value : DateTime.tryParse('$value');
  if (d == null || d.isUtc) {
    return d ?? value;
  }
  return DateTime.utc(
    d.year,
    d.month,
    d.day,
    d.hour,
    d.minute,
    d.second,
    d.millisecond,
    d.microsecond,
  );
}
