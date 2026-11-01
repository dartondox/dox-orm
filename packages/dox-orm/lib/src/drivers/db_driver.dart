import 'dart:async';

import 'package:dox_mysql_native/dox_mysql_native.dart';
import 'package:dox_orm/dox_orm.dart';
import 'package:dox_orm/src/drivers/sqlite_driver.dart';
import 'package:dox_postgres_native/dox_postgres_native.dart';

enum Driver { postgres, mysql, sqlite }

/// interface for database driver
abstract class DBDriver {
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
    R result;
    try {
      result = await runZoned(
        callback,
        zoneValues: <Symbol, dynamic>{_savepointKey: depth},
      );
    } catch (_) {
      try {
        await execute('ROLLBACK TO SAVEPOINT $name');
      } catch (_) {
        // keep the first error: it tells what went wrong
      }
      rethrow;
    }
    await execute('RELEASE SAVEPOINT $name');
    return result;
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
