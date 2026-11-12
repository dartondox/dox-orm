import 'package:dox_orm/dox_orm.dart';

import 'count.dart';
import 'delete.dart';
import 'get.dart';
import 'group_by.dart';
import 'insert.dart';
import 'join.dart';
import 'limit.dart';
import 'order_by.dart';
import 'raw.dart';
import 'select.dart';
import 'truncate.dart';
import 'union.dart';
import 'update.dart';
import 'utils/helper.dart';
import 'utils/logger.dart';
import 'where.dart';
import 'with_count.dart';

class QueryBuilder<T>
    with
        Limit<T>,
        Where<T>,
        OrderBy<T>,
        GroupBy<T>,
        Insert<T>,
        Join<T>,
        Raw<T>,
        Get<T>,
        Update<T>,
        Select<T>,
        Truncate<T>,
        Delete<T>,
        Count<T>,
        WithCount<T>,
        Union<T> {
  /// made on the first use, a find() with a cached sql makes it once
  Map<String, dynamic>? _substitutionValues;

  dynamic self;

  @override
  QueryBuilder<T> get queryBuilder => this;

  @override
  String primaryKey = 'id';

  @override
  String? connection;

  @override
  DBDriver get dbDriver {
    DBDriver driver = connection != null
        ? SqlQueryBuilder().getDBDriver(connection)
        : SqlQueryBuilder().dbDriver;
    if (_onWrite && driver is ReplicaDriver) return driver.writer;
    return driver;
  }

  bool _onWrite = false;

  /// run the queries of this query builder on the write database, also
  /// its reads. It matters only for a connection with `read` hosts (see
  /// [ConnectionConfig.read]): use it to read a row you just wrote, or for
  /// a `SELECT` that changes data.
  ///
  /// ```
  /// User? user = await User().onWriteConnection().find(id);
  /// ```
  QueryBuilder<T> onWriteConnection() {
    _onWrite = true;
    return this;
  }

  /// true after [onWriteConnection]
  bool get usesWriteConnection => _onWrite;

  /// for a query made for [from], like the query of a relation: take its
  /// connection (when this has none), [onWriteConnection] and
  /// [cancelWith] token.
  void useConnectionOf(QueryBuilder<dynamic> from) {
    connection ??= from.connection;
    if (from._onWrite) _onWrite = true;
    cancelToken ??= from.cancelToken;
  }

  @override
  late final QueryBuilderHelper<T> helper = QueryBuilderHelper<T>(this);

  // coverage:ignore-start
  @override
  Logger get logger => Logger();
  // coverage:ignore-end

  @override
  bool shouldDebug = SqlQueryBuilder().debug;

  @override
  Map<String, dynamic> get substitutionValues =>
      _substitutionValues ??= <String, dynamic>{};

  @override
  String get selectQueryString => getSelectQuery() + aggregateSelects();

  List<String> getPreload() => <String>[];

  @override
  bool isSoftDeletes = false;

  @override
  bool withTrashed = false;

  /// true after onlyTrashed()
  @override
  bool trashedOnly = false;

  @override
  String tableName = '';

  /// the name of the table in a whereHas() or withCount() subquery on
  /// the same table as the parent query, like a parent category
  @override
  String? tableAlias;

  @override
  void addSubstitutionValues(String key, dynamic value) {
    String index = key.replaceFirst('@', '');
    substitutionValues[index] = value;
  }

  @override
  Map<String, dynamic> resetSubstitutionValues() {
    return _substitutionValues = <String, dynamic>{};
  }

  /// set table and continue query
  ///
  /// ```
  /// QueryBuilder.table('blog');
  /// ```
  /// the rows are maps, so get() gives `List<Map<String, dynamic>>`
  /// and getFirst() gives `Map<String, dynamic>?`.
  static QueryBuilder<Map<String, dynamic>> table(String tableName) {
    return QueryBuilder<Map<String, dynamic>>()..tableName = tableName;
  }

  /// set debug on or of
  ///
  /// ```
  /// QueryBuilder().debug(true)
  /// ```
  QueryBuilder<T> debug([bool? debug]) {
    shouldDebug = debug ?? true;
    return this;
  }

  /// use different connection to query
  ///
  /// ```
  /// QueryBuilder().withConnection('mysql')
  /// ```
  QueryBuilder<T> withConnection(String connectionName) {
    connection = connectionName;
    return this;
  }

  /// the token of [cancelWith], or null
  QueryCancelToken? cancelToken;

  /// stop the queries of this query builder when [token] is cancelled.
  /// Postgres and MySQL only, SQLite runs a query to its end. See
  /// [QueryCancelToken].
  ///
  /// ```
  /// QueryCancelToken token = QueryCancelToken();
  /// Future<List<Blog>> slow = Blog().where('status', 'draft').cancelWith(token).get();
  /// token.cancel();
  /// ```
  QueryBuilder<T> cancelWith(QueryCancelToken token) {
    cancelToken = token;
    return this;
  }

  /// set debug on or of
  ///
  /// ```
  /// QueryBuilder.table('blog').setPrimaryKey('uid')
  /// ```
  QueryBuilder<T> setPrimaryKey(String id) {
    primaryKey = id;
    _keySet = true;
    return this;
  }

  bool _keySet = false;

  /// true when the table surely has the [primaryKey] column: a model, or
  /// a query with [setPrimaryKey]. a QueryBuilder.table() query may not.
  bool get hasKnownPrimaryKey => _keySet || self is Model;

  /// With trash (this function can be used with SoftDeletes only)
  ///
  /// ```
  /// List blogs = await Blog().withTrash().all();
  /// ```
  QueryBuilder<T> withTrash([bool withTrashed = true]) {
    this.withTrashed = withTrashed;
    return queryBuilder;
  }

  /// only the soft deleted rows. On a model without soft deletes (or
  /// a QueryBuilder.table() query) it throws a [StateError], so
  /// `onlyTrashed().forceDelete()` can never delete every row.
  ///
  /// ```
  /// List<Blog> blogs = await Blog().onlyTrashed().get();
  /// ```
  QueryBuilder<T> onlyTrashed() {
    if (!isSoftDeletes) {
      throw StateError(
        'onlyTrashed() needs a model with soft deletes, like '
        '@DoxModel(softDelete: true).',
      );
    }
    trashedOnly = true;
    return queryBuilder;
  }

  /// set [column] of the rows of this query to now, and return how many
  /// rows changed
  ///
  /// ```
  /// await QueryBuilder.table('blog').where('status', 'draft').touch();
  /// ```
  Future<int> touch([String? column]) {
    /// super.update(): a model does not check the column against fillable
    return super.update(<String, dynamic>{column ?? 'updated_at': now()});
  }

  /// **** global scopes

  /// the global scopes of the model: name => scope method.
  /// the generator overrides it for models with `@Scope(global: true)`.
  /// an empty `Never` map fits every model type.
  Map<String, QueryBuilder<T> Function(QueryBuilder<T>)> get globalScopes =>
      const <String, Never>{};

  /// true when the model has global scopes
  bool get hasGlobalScopes => globalScopes.isNotEmpty;

  bool _globalScopesDone = false;
  bool _noGlobalScopes = false;
  Set<String>? _skippedScopes;

  /// leave out the global scope [name] in this query
  ///
  /// ```
  /// await User().withoutGlobalScope('active').get();
  /// ```
  QueryBuilder<T> withoutGlobalScope(String name) {
    (_skippedScopes ??= <String>{}).add(name);
    return this;
  }

  /// leave out every global scope in this query
  QueryBuilder<T> withoutGlobalScopes() {
    _noGlobalScopes = true;
    return this;
  }

  /// adds the global scopes to the where conditions, once, when the sql
  /// is made. the conditions so far go in brackets, and each scope too,
  /// so an OR in one part can not skip another part.
  void applyGlobalScopes() {
    if (_globalScopesDone) return;
    _globalScopesDone = true;
    Map<String, QueryBuilder<T> Function(QueryBuilder<T>)> scopes =
        globalScopes;
    if (_noGlobalScopes || scopes.isEmpty) return;
    groupWheres(0);
    for (MapEntry<String, QueryBuilder<T> Function(QueryBuilder<T>)> e
        in scopes.entries) {
      if (_skippedScopes?.contains(e.key) == true) continue;
      int from = whereCount;
      e.value(this);
      groupWheres(from);
    }
  }

  /// **** map

  /// the row this model was made from
  Map<String, dynamic> get originalMap => _originalMap ??= <String, dynamic>{};
  set originalMap(Map<String, dynamic> value) => _originalMap = value;
  Map<String, dynamic>? _originalMap;

  // coverage:ignore-start
  Map<String, dynamic> convertToMap(dynamic i) {
    return <String, dynamic>{};
  }

  Future<void> initPreload(List<Model<T>> list) async {}

  dynamic fromMap(Map<String, dynamic> m) {}
  // coverage:ignore-end

  /// **** map

  /// run [callback] in one database transaction.
  /// it commits when [callback] ends, and rolls back when it throws
  /// (the error is thrown again). queries and models inside use the
  /// transaction. a nested call makes a savepoint. if it fails, only the
  /// work since that savepoint is rolled back.
  ///
  /// ```
  /// await QueryBuilder.transaction(() async {
  ///   await Blog().create({'title': 'a', 'body': 'b'});
  ///   await QueryBuilder.table('blog_info').insert({'blog_id': 1});
  /// });
  /// ```
  ///
  /// [attempts] > 1 runs the whole transaction again when it fails with
  /// a deadlock or a lock / serialization failure (see
  /// [DatabaseTransaction.isConcurrencyError]), up to [attempts] runs in
  /// all. other errors are thrown at once. only the outermost transaction
  /// runs again: a nested one throws the error to it. the `afterCommit()`
  /// callbacks of a failed run are dropped. an error after the commit (eg.
  /// of an `afterCommit()` callback) never runs it again.
  /// there is no wait between the runs.
  static Future<R> transaction<R>(
    Future<R> Function() callback, {
    String? connection,
    int attempts = 1,
  }) {
    DBDriver driver = SqlQueryBuilder().getDBDriver(connection);
    if (attempts <= 1 || driver.hasOpenTransaction) {
      return driver.transaction(callback);
    }
    return _retryTransaction(driver, callback, attempts);
  }

  static Future<R> _retryTransaction<R>(
    DBDriver driver,
    Future<R> Function() callback,
    int attempts,
  ) async {
    for (int attempt = 1; ; attempt++) {
      bool committed = false;
      try {
        return await driver.transaction(() async {
          // the first callback after the commit
          await driver.afterCommit(() => committed = true);
          return callback();
        });
      } catch (error) {
        if (committed ||
            attempt >= attempts ||
            !DatabaseTransaction.isConcurrencyError(error)) {
          rethrow;
        }
      }
    }
  }

  /// begin a transaction that stays open until you call
  /// [DatabaseTransaction.commit] or [DatabaseTransaction.rollBack]. only
  /// code inside [DatabaseTransaction.run] uses it. it is rolled back
  /// after [timeout] when it is still open, so a forgotten transaction
  /// does not hold its connection. [QueryBuilder.transaction] is simpler:
  /// use this one only when the work can not fit in one callback.
  ///
  /// ```
  /// DatabaseTransaction tx = await QueryBuilder.beginTransaction();
  /// try {
  ///   await tx.run(() => Blog().create({'title': 'a', 'body': 'b'}));
  ///   await tx.commit();
  /// } finally {
  ///   await tx.rollBack(); // does nothing after commit
  /// }
  /// ```
  static Future<DatabaseTransaction> beginTransaction({
    String? connection,
    Duration timeout = const Duration(minutes: 1),
  }) {
    return DatabaseTransaction.begin(
      SqlQueryBuilder().getDBDriver(connection),
      timeout,
    );
  }

  /// run [callback] after the outermost transaction of [connection]
  /// commits, so the data is saved before it runs. outside a transaction
  /// it runs at once. a rollback drops it. see [DBDriver.afterCommit].
  ///
  /// ```
  /// await QueryBuilder.transaction(() async {
  ///   User user = await User().create({'email': email});
  ///   await QueryBuilder.afterCommit(() => sendWelcomeMail(user));
  /// });
  /// ```
  static Future<void> afterCommit(
    AfterCommitCallback callback, {
    String? connection,
  }) {
    return SqlQueryBuilder().getDBDriver(connection).afterCommit(callback);
  }

  /// run a raw query. [connection] is a connection name, the default
  /// connection is used when it is null.
  ///
  /// ```
  /// var rows = await QueryBuilder.query(
  ///   'select * from blog where id = @id',
  ///   substitutionValues: {'id': 1},
  ///   connection: 'mysql',
  /// );
  /// ```
  static Future<List<Map<String, dynamic>>> query(
    String query, {
    Map<String, dynamic>? substitutionValues = const <String, dynamic>{},
    String? connection,
  }) {
    SqlQueryBuilder sql = SqlQueryBuilder();
    Stopwatch? watch = sql.startQueryWatch(connection);
    return sql.timeQuery(
      sql
          .getDBDriver(connection)
          .query(query, substitutionValues: substitutionValues),
      watch,
      query,
      substitutionValues,
      connection,
    );
  }
}
