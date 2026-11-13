import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dox_mysql_native/dox_mysql_native.dart';
import 'package:dox_orm/dox_orm.dart';

/// zone key to find the open transaction of a pool
const Symbol _txKey = #doxMysqlNativeTransaction;

/// zone key to find the foreign key state of the open transaction. it is in
/// the zone, not in the driver, so any driver or Schema object on the same
/// pool finds it.
const Symbol _fkKey = #doxMysqlNativeForeignKeys;

/// true when the transaction turned the foreign key checks off
class _ForeignKeyState {
  bool off = false;
}

/// The Dox ORM driver for MySQL and MariaDB, on [MysqlNativePool]
/// (dox_mysql_native). Errors are [MysqlException].
class MysqlNativeDriver extends DBDriver {
  MysqlNativeDriver(this.pool);

  /// Makes the pool from a Dox [ConnectionConfig]. Reads
  /// `maxConnectionCount` (default 10), `preparedStatementCacheSize`
  /// (default 100), `threads` (default 1), `serverKill` (default true) and
  /// the pool times from `extra`.
  ///
  /// The pool times are a `Duration`, or an int of seconds (eg. from a
  /// database url):
  /// - `requestTimeout` (default 300 s): the longest wait for one request.
  /// - `maxConnectionAge` (default 12 hours): close a connection older
  ///   than this when it has no query.
  /// - `idleTimeout` (default 12 hours): close a connection with no
  ///   traffic for this long.
  ///
  /// `serverKill` false: a cancelled or timed out query is not stopped
  /// on the server with `KILL QUERY`. Use it behind a proxy, where the
  /// KILL may reach another server.
  /// `useSSL` turns on TLS, and the server
  /// certificate is checked unless `extra['verifyCertificate']` is false.
  /// A host that starts with `/` is a Unix socket file.
  /// Throws an [UnsupportedError] when the native library does not load.
  factory MysqlNativeDriver.fromConfig(ConnectionConfig config) {
    NativeDrivers.ensureAvailable(Driver.mysql);
    Map<String, dynamic> extra = config.extra;
    return MysqlNativeDriver(
      MysqlNativePool.open(
        host: config.host,
        port: config.port == 0 ? 3306 : config.port,
        user: config.user,
        password: config.password,
        database: config.database,
        secure: config.useSSL,
        verifyCertificate: config.verifyCertificate,
        maxConnections: extra['maxConnectionCount'] as int? ?? 10,
        maxConnectionAge:
            config.extraDuration('maxConnectionAge') ??
            const Duration(hours: 12),
        idleTimeout: config.extraDuration('idleTimeout'),
        requestTimeout:
            config.extraDuration('requestTimeout') ??
            const Duration(seconds: 300),
        serverKill: extra['serverKill'] as bool? ?? true,
        statementCacheSize: config.statementCacheSize,
        threads: extra['threads'] as int? ?? 1,
      ),
    );
  }

  final MysqlNativePool pool;

  @override
  Driver getName() => Driver.mysql;

  int get _tx =>
      (Zone.current[_txKey] as Map<MysqlNativePool, int>?)?[pool] ?? 0;

  bool _closed = false;

  /// let go of the pool. isolates with the same settings share one pool,
  /// and it closes when the last one lets go. running queries finish.
  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    pool.close();
  }

  /// the shared pool can stay open for other isolates after [close], so
  /// this driver checks its own flag.
  void _checkOpen() {
    if (_closed) {
      throw StateError(
        'This MySQL connection is closed. Set up the ORM again to use it.',
      );
    }
  }

  Future<MysqlNativeResult> _run(
    String sql,
    Map<String, dynamic>? values,
    bool rows,
  ) {
    _checkOpen();
    var (String query, List<Object?> params) = toPositionalParams(
      sql,
      values,
      _toMysqlValue,
      mysql: true,
    );
    MysqlCancelToken? token = DBDriver.currentCancelToken?.mysqlToken;
    return rows
        ? pool.query(
            query,
            parameters: params,
            transaction: _tx,
            cancelToken: token,
          )
        : pool.execute(
            query,
            parameters: params,
            transaction: _tx,
            cancelToken: token,
          );
  }

  @override
  Future<List<Map<String, dynamic>>> query(
    String query, {
    String? primaryKey,
    Map<String, dynamic>? substitutionValues,
  }) async {
    MysqlNativeResult result = await _run(query, substitutionValues, true);

    /// insert query returns the new auto increment id
    if (result.columns.isEmpty) {
      if (result.insertId > 0 && primaryKey != null) {
        return <Map<String, dynamic>>[
          <String, dynamic>{primaryKey: result.insertId},
        ];
      }
      return <Map<String, dynamic>>[];
    }
    return result.rows;
  }

  /// the rows as they come from the server, see [MysqlNativePool.stream]
  @override
  Stream<List<Map<String, dynamic>>> stream(
    String query, {
    Map<String, dynamic>? substitutionValues,
    int chunkSize = 1000,
  }) {
    _checkOpen();
    var (String sql, List<Object?> params) = toPositionalParams(
      query,
      substitutionValues,
      _toMysqlValue,
      mysql: true,
    );
    return pool
        .stream(
          sql,
          parameters: params,
          transaction: _tx,
          chunkSize: chunkSize,
          cancelToken: DBDriver.currentCancelToken?.mysqlToken,
        )
        .map(_rows);
  }

  static List<Map<String, dynamic>> _rows(MysqlNativeResult result) =>
      result.rows;

  @override
  Future<void> execute(
    String query, {
    Map<String, dynamic>? substitutionValues,
  }) {
    return _run(query, substitutionValues, false);
  }

  /// the rows that really changed, see [DBDriver.affectingStatement]
  @override
  Future<int> affectingStatement(
    String query, {
    Map<String, dynamic>? substitutionValues,
  }) async {
    MysqlNativeResult result = await _run(query, substitutionValues, false);
    return result.affectedRows;
  }

  @override
  void trackForeignKeyChecks({required bool off}) {
    _ForeignKeyState? state = Zone.current[_fkKey] as _ForeignKeyState?;
    state?.off = off;
  }

  /// turn the foreign key checks on again before the connection goes back
  /// to the pool. a rollback does not undo `SET FOREIGN_KEY_CHECKS`.
  Future<void> _restoreForeignKeys(_ForeignKeyState state, int tx) async {
    if (!state.off) return;
    state.off = false;
    try {
      await pool.execute('SET FOREIGN_KEY_CHECKS = 1', transaction: tx);
    } catch (_) {
      // the connection is broken: the pool drops it
    }
  }

  /// one pooled connection runs the whole transaction.
  /// note: in mysql, schema changes (create/alter/drop table) commit the
  /// transaction right away, they can not be rolled back.
  @override
  Future<R> transaction<R>(Future<R> Function() callback) async {
    _checkOpen();
    Map<MysqlNativePool, int>? open =
        Zone.current[_txKey] as Map<MysqlNativePool, int>?;

    /// a nested transaction uses a savepoint on the same connection
    if (open?[pool] != null) {
      return savepoint(callback);
    }
    int tx = await pool.begin();
    _ForeignKeyState fk = _ForeignKeyState();
    AfterCommitCallbacks callbacks = AfterCommitCallbacks();
    R result;
    try {
      result = await runZoned(
        callback,
        zoneValues: <Symbol, dynamic>{
          _txKey: <MysqlNativePool, int>{...?open, pool: tx},
          _fkKey: fk,
          ...afterCommitZone(callbacks),
        },
      );
    } catch (_) {
      await _restoreForeignKeys(fk, tx);
      try {
        await pool.rollback(tx);
      } catch (_) {
        // keep the first error: it tells what went wrong
      }
      rethrow;
    }
    await _restoreForeignKeys(fk, tx);
    await pool.commit(tx);
    await runAfterCommit(callbacks);
    return result;
  }

  /// false when [text] can not be a date for DateTime.tryParse(), so a
  /// word like `XYZ` is not parsed. a date starts with a digit, `+` or
  /// `-`, and has 8 digits at least.
  static bool _mayBeDate(String text) {
    if (text.length < 9) return false;
    int first = text.codeUnitAt(0);
    return (first >= 0x30 && first <= 0x39) || first == 0x2B || first == 0x2D;
  }

  /// a Dox value as a MySQL parameter
  static Object? _toMysqlValue(dynamic value) {
    if (value == null ||
        value is int ||
        value is double ||
        value is Uint8List) {
      return value;
    } else if (value is bool) {
      return value ? 1 : 0;
    } else if (value is Map || value is List) {
      return jsonEncode(value);
    } else if (value is DateTime) {
      return value.toIso8601String().split('.').first;
    }
    String text = value.toString();

    /// iso date string with `Z` (eg. from model timestamps), mysql
    /// DATETIME do not accept the `Z`
    if (text.endsWith('Z') && _mayBeDate(text)) {
      DateTime? date = DateTime.tryParse(text);
      if (date != null) {
        return date.toIso8601String().split('.').first;
      }
    }
    return text;
  }
}
