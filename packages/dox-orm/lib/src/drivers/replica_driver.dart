import 'dart:async';

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
  }

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
  /// scope, `sticky` does nothing. A nested scope starts fresh.
  ///
  /// ```
  /// // a middleware of your app (dox_core)
  /// class StickyReads implements IDoxNextMiddleware {
  ///   @override
  ///   Future<DoxResponse> handle(DoxRequest req, Next next) =>
  ///       ReplicaDriver.stickyScope(next);
  /// }
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
    if (writer.hasOpenTransaction || (sticky && _wroteInScope)) {
      return writer;
    }
    DBDriver reader = readers[_next];
    _next = (_next + 1) % readers.length;
    return reader;
  }

  bool get _wroteInScope =>
      (Zone.current[_stickyKey] as Set<DBDriver>?)?.contains(this) ?? false;

  /// remember a write for [sticky]
  void _wrote() {
    if (!sticky) return;
    (Zone.current[_stickyKey] as Set<DBDriver>?)?.add(this);
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
