import 'dart:async';

import 'package:dox_orm/dox_orm.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;

/// a transaction that stays open after the call that began it, made by
/// [QueryBuilder.beginTransaction]. close it with [commit] or [rollBack].
///
/// - only code inside [run] uses the transaction. other queries (eg. of
///   other requests) never join it.
/// - nested `QueryBuilder.transaction()` calls and `afterCommit()` work
///   inside [run], like in `QueryBuilder.transaction()`.
/// - it holds one connection until it is closed. sqlite has one
///   connection per isolate: other queries of this isolate wait for it.
/// - a transaction that is not closed in time is rolled back after the
///   `timeout` of [QueryBuilder.beginTransaction], so its connection is
///   free again.
/// - use it only in the code that began it (the same request, job or
///   test). an error of [run] in another error zone does not reach you.
///
/// ```
/// DatabaseTransaction tx = await QueryBuilder.beginTransaction();
/// try {
///   await tx.run(() => User().create({'email': email}));
///   await tx.commit();
/// } finally {
///   await tx.rollBack(); // does nothing after commit
/// }
/// ```
class DatabaseTransaction {
  DatabaseTransaction._();

  /// the zone of the open transaction, [run] runs code in it
  late final Zone _zone;

  /// true to commit, false to roll back
  final Completer<bool> _end = Completer<bool>();

  /// the transaction call: done when it committed or rolled back
  late final Future<void> _done;

  /// why it is closed, null while it is open
  String? _closed;

  /// true until [commit], [rollBack] or the timeout
  bool get isOpen => _closed == null;

  /// begin a transaction on [driver], see [QueryBuilder.beginTransaction]
  static Future<DatabaseTransaction> begin(DBDriver driver, Duration timeout) {
    if (driver.hasOpenTransaction) {
      return Future<DatabaseTransaction>.error(
        StateError(
          'beginTransaction() can not run inside a transaction. use '
          'QueryBuilder.transaction() for nested work.',
        ),
      );
    }
    DatabaseTransaction tx = DatabaseTransaction._();
    Completer<DatabaseTransaction> started = Completer<DatabaseTransaction>();
    tx._done = driver.transaction(() async {
      tx._zone = Zone.current;
      started.complete(tx);
      Timer timer = Timer(timeout, () {
        tx._close(
          'the transaction was rolled back after the timeout of $timeout',
          false,
        );
      });
      bool commit = await tx._end.future;
      timer.cancel();
      if (!commit) throw const _RollBack();
    });
    // a timeout rollback is not awaited by anyone: handle it here
    tx._done.then(
      (_) {},
      onError: (Object error, StackTrace stack) {
        if (!started.isCompleted) started.completeError(error, stack);
      },
    );
    return started.future;
  }

  /// run [callback] in this transaction. its queries (models too) use it.
  /// await it before [commit].
  Future<R> run<R>(Future<R> Function() callback) {
    _checkOpen();
    return _zone.run(callback);
  }

  /// commit, then run the `afterCommit()` callbacks. throws the error of
  /// the COMMIT or of a callback. throws a [StateError] when the
  /// transaction is closed already.
  Future<void> commit() async {
    _checkOpen();
    _close('the transaction is committed', true);
    await _done;
  }

  /// roll back and drop the `afterCommit()` callbacks. it does nothing when
  /// the transaction is closed already, so it is safe in a `finally`.
  Future<void> rollBack() async {
    if (!isOpen) return;
    _close('the transaction is rolled back', false);
    try {
      await _done;
    } on _RollBack {
      // the rollback this call asked for
    }
  }

  void _close(String reason, bool commit) {
    if (_end.isCompleted) return;
    _closed = reason;
    _end.complete(commit);
  }

  void _checkOpen() {
    if (_closed != null) throw StateError(_closed!);
  }

  /// true when [error] is a deadlock or a lock / serialization failure, so
  /// the whole transaction can run again. see
  /// [QueryBuilder.transaction] `attempts`.
  ///
  /// - postgres: SQLSTATE `40001` (serialization failure) and `40P01`
  ///   (deadlock).
  /// - mysql and mariadb: error `1213` (deadlock), `1205` (lock wait
  ///   timeout), `1020` (record changed, mariadb) and SQLSTATE `40001`.
  /// - sqlite: `SQLITE_BUSY` and `SQLITE_LOCKED` ("database is locked").
  static bool isConcurrencyError(Object error) {
    if (error is PgServerException) {
      return error.code == '40001' || error.code == '40P01';
    }
    if (error is MysqlException) {
      return error.sqlState == '40001' ||
          error.code == 1213 ||
          error.code == 1205 ||
          error.code == 1020;
    }
    if (error is SqliteException) {
      return error.resultCode == 5 || error.resultCode == 6;
    }
    return false;
  }
}

/// thrown inside the transaction call to roll it back
class _RollBack {
  const _RollBack();
}
