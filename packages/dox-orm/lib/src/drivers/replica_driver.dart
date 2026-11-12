import 'dart:async';
import 'dart:io';

import 'package:dox_orm/dox_orm.dart';

/// A driver that sends reads to read replicas and the rest to the write
/// (primary) database. The ORM makes it when a [ConnectionConfig] has
/// `read` hosts. See [ConnectionConfig.read].
///
/// - A plain `SELECT` goes to a reader. The readers take turns (round
///   robin), in the order of the config.
/// - Everything else goes to the [writer]: insert, update, delete, a raw
///   query that is not a `SELECT`, schema changes, a `SELECT` with a lock
///   (`lockForUpdate()`, `sharedLock()`) or with `INTO`, and every query
///   inside a transaction.
/// - `onWriteConnection()` on a query sends its reads to the writer too.
/// - With [sticky], a read after a write goes to the writer, inside the
///   same [stickyScope] (eg. one request). So a request reads what it just
///   wrote, even when the replicas are behind.
///
/// A `SELECT` that changes data (eg. it calls a function that writes)
/// must use `onWriteConnection()`.
class ReplicaDriver extends DBDriver {
  ReplicaDriver({
    required this.writer,
    required List<DBDriver> readers,
    this.sticky = false,
  }) : readers = List<DBDriver>.unmodifiable(readers) {
    if (readers.isEmpty) {
      throw ArgumentError.value(readers, 'readers', 'must not be empty');
    }
    if (sticky) stickyInUse = true;
  }

  /// true when a connection uses `sticky`. [stickyReads] makes no scope
  /// when it is false.
  static bool stickyInUse = false;

  /// the driver of the write (primary) database
  final DBDriver writer;

  /// the drivers of the read replicas
  final List<DBDriver> readers;

  /// true: after a write, reads in the same [stickyScope] go to [writer]
  final bool sticky;

  int _next = 0;

  /// zone key for the drivers that wrote in this [stickyScope]
  static const Symbol _stickyKey = #doxReplicaSticky;

  /// run [body] as one unit of work (eg. one request) for `sticky`: after
  /// a write inside it, its reads go to the write database. Outside a
  /// scope, `sticky` does nothing. It prints a warning once when a read
  /// from a replica follows a write that was outside any scope. A nested
  /// scope starts fresh.
  ///
  /// In a Dox app each request gets a scope by itself: see [stickyReads].
  /// Use this one outside Dox, eg. around each job of a worker.
  ///
  /// ```
  /// await ReplicaDriver.stickyScope(() => handleJob(job));
  /// ```
  static R stickyScope<R>(R Function() body) {
    return runZoned(
      body,
      zoneValues: <Symbol, Object>{_stickyKey: <DBDriver>{}},
    );
  }

  /// a `SELECT` at the start: maybe in brackets, eg. a union
  static final RegExp _select = RegExp(
    r'^[\s(]*select\b',
    caseSensitive: false,
  );

  /// a lock or `SELECT ... INTO`: it needs the write database. a match in
  /// a string or a name is fine: the query then goes to the writer.
  static final RegExp _writeSelect = RegExp(
    r'\bfor\s+(update|share|no\s+key\s+update|key\s+share)\b'
    r'|\block\s+in\s+share\s+mode\b|\binto\b',
    caseSensitive: false,
  );

  /// true when [sql] only reads, so a replica can run it
  static bool isReadQuery(String sql) =>
      _select.hasMatch(sql) && !_writeSelect.hasMatch(sql);

  /// the driver that runs [sql]
  DBDriver driverFor(String sql) {
    bool read = isReadQuery(sql);
    if (!read) {
      _wrote();
      return writer;
    }
    if (writer.hasOpenTransaction ||
        (sticky && _scope()?.contains(this) == true)) {
      return writer;
    }
    if (sticky) _warnIfUnscopedAfterWrite();
    DBDriver reader = readers[_next];
    _next = (_next + 1) % readers.length;
    return reader;
  }

  /// the drivers that wrote in this [stickyScope], or null outside one
  static Set<DBDriver>? _scope() => Zone.current[_stickyKey] as Set<DBDriver>?;

  /// true after a write outside any scope on this connection
  bool _wroteOutsideScope = false;

  static bool _noScopeWarned = false;

  /// forget that the warning was printed. This is for tests only.
  static void resetStickyWarning() => _noScopeWarned = false;

  /// a read goes to a replica outside any scope, after an unscoped write:
  /// here `sticky` could have changed the result. Migrations and other
  /// writer-only work never reach this.
  void _warnIfUnscopedAfterWrite() {
    if (_scope() != null || !_wroteOutsideScope || _noScopeWarned) return;
    _noScopeWarned = true;
    stderr.writeln(
      'Dox ORM warning: a connection has sticky: true, but this read '
      'goes to a replica outside ReplicaDriver.stickyScope(), after a '
      'write. So sticky does nothing here. In a Dox app each request gets '
      'a scope by itself. Outside a request (eg. a job or a script), wrap '
      'the work in ReplicaDriver.stickyScope().',
    );
  }

  /// remember a write for [sticky]
  void _wrote() {
    if (!sticky) return;
    Set<DBDriver>? scope = _scope();
    if (scope == null) {
      _wroteOutsideScope = true;
    } else {
      scope.add(this);
    }
  }

  @override
  Driver getName() => writer.getName();

  @override
  bool get supportsReturning => writer.supportsReturning;

  @override
  Object? columnValue(dynamic value) => writer.columnValue(value);

  @override
  Future<List<Map<String, dynamic>>> query(
    String query, {
    String? primaryKey,
    Map<String, dynamic>? substitutionValues,
  }) {
    return driverFor(query).query(
      query,
      primaryKey: primaryKey,
      substitutionValues: substitutionValues,
    );
  }

  @override
  Stream<List<Map<String, dynamic>>> stream(
    String query, {
    Map<String, dynamic>? substitutionValues,
    int chunkSize = 1000,
  }) {
    return driverFor(query).stream(
      query,
      substitutionValues: substitutionValues,
      chunkSize: chunkSize,
    );
  }

  @override
  Future<void> execute(
    String query, {
    Map<String, dynamic>? substitutionValues,
  }) {
    _wrote();
    return writer.execute(query, substitutionValues: substitutionValues);
  }

  @override
  Future<int> affectingStatement(
    String query, {
    Map<String, dynamic>? substitutionValues,
  }) {
    _wrote();
    return writer.affectingStatement(
      query,
      substitutionValues: substitutionValues,
    );
  }

  /// a transaction runs on the writer, with all its queries
  @override
  Future<R> transaction<R>(Future<R> Function() callback) {
    _wrote();
    return writer.transaction(callback);
  }

  @override
  bool get hasOpenTransaction => writer.hasOpenTransaction;

  @override
  Future<void> afterCommit(AfterCommitCallback callback) =>
      writer.afterCommit(callback);

  /// close the writer and every reader
  @override
  Future<void> close() async {
    for (DBDriver driver in <DBDriver>{writer, ...readers}) {
      await driver.close();
    }
  }
}

/// A Dox middleware (a `NextMiddlewareFunction` of dox_core, with no
/// dox_core types here): it runs the rest of the request [next] in a
/// [ReplicaDriver.stickyScope], so `sticky: true` works per request.
/// `SqlQueryBuilder.initializeWithDatabaseConfig()` adds it to
/// `GlobalMiddleware` when a connection uses `sticky`, so a Dox app does
/// not add it itself. With no sticky connection it just runs [next].
Future<Object?> stickyReads(Object? req, Future<Object?> Function() next) {
  if (!ReplicaDriver.stickyInUse) return next();
  return ReplicaDriver.stickyScope(next);
}
