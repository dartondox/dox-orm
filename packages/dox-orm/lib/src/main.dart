import 'package:dox_orm/dox_orm.dart';
import 'package:dox_orm/src/utils/logger.dart';
import 'package:dox_validation/dox_validation.dart' show PresenceVerifier;

/// one query that ran, see [SqlQueryBuilder.listen]
class QueryEvent {
  /// the sql text, with `@name` placeholders
  final String sql;

  /// the values of the query. values named in `logRedact` are `***`.
  final Map<String, dynamic> bindings;

  /// how long the query took
  final Duration time;

  /// the name of the connection that ran the query
  final String connection;

  const QueryEvent(this.sql, this.bindings, this.time, this.connection);
}

/// a function that gets each query, see [SqlQueryBuilder.listen]
typedef QueryListener = void Function(QueryEvent event);

/// one driver per connection name, so each name keeps its own pool and
/// its own statement caches
Map<String, DBDriver> _globalDrivers = <String, DBDriver>{};

class SqlQueryBuilder {
  static final SqlQueryBuilder _singleton = SqlQueryBuilder._internal();

  factory SqlQueryBuilder() {
    return _singleton;
  }

  SqlQueryBuilder._internal();

  DBDriver? _dbDriver;

  /// the driver of the default connection
  DBDriver get dbDriver {
    DBDriver? driver = _dbDriver;
    if (driver == null) {
      throw StateError(
        'The ORM is not set up. Call SqlQueryBuilder.initialize first.',
      );
    }
    return driver;
  }

  set dbDriver(DBDriver driver) {
    _dbDriver = driver;
    // `exists()` and `unique()` of dox_validation read the database
    // through this, unless the app set its own verifier
    PresenceVerifier.instance ??= const RowFinder();
  }

  bool debug = true;

  QueryPrinter printer = PrettyQueryPrinter();

  /// names of values to hide in the debug query log, see
  /// [ConnectionConfig.logRedact]. empty by default: nothing is hidden.
  List<String> logRedact = <String>[];

  /// log a query of the default connection that takes longer than this
  /// many milliseconds. 0 logs every query. null (the default) turns it
  /// off. see
  /// [ConnectionConfig.slowQueryMs].
  int? slowQueryMs;

  DatabaseConfig? databaseConfig;

  /// the opt-in ORM behaviors of this isolate, see [OrmFlags]. `initialize`
  /// and `initializeWithDatabaseConfig` set it.
  OrmFlags flags = const OrmFlags();

  final List<QueryListener> _listeners = <QueryListener>[];

  /// run [listener] after each query of every connection.
  /// it gets the sql, the values (`logRedact` names are
  /// hidden), the time and the connection name. it runs after the query
  /// ends well. a failed query is not sent to the listeners and not to
  /// the slow query log: its error goes to the caller. the queries of the
  /// schema builder and the migrator are sent too, see [queryOn]. an
  /// error in [listener] is logged, the query does not fail.
  /// ```
  /// SqlQueryBuilder().listen(onQuery);
  /// void onQuery(QueryEvent e) => print('${e.time} ${e.sql}');
  /// ```
  void listen(QueryListener listener) => _listeners.add(listener);

  /// stop calling [listener]. it returns false when it was not listening.
  bool removeListener(QueryListener listener) => _listeners.remove(listener);

  /// the slow query limit of [connection] in milliseconds, or null
  int? slowQueryMsOf(String? connection) => connection == null
      ? slowQueryMs
      : databaseConfig?.connections[connection]?.slowQueryMs;

  /// a started [Stopwatch] when a query on [connection] needs its time (a
  /// listener or a slow query limit is set), else null. pass it to
  /// [timeQuery].
  Stopwatch? startQueryWatch(String? connection) =>
      _listeners.isEmpty && slowQueryMsOf(connection) == null
      ? null
      : (Stopwatch()..start());

  /// wait for [result] of [query], then log it when it is slow and tell
  /// the listeners. with no [watch] it gives [result] as it is.
  Future<R> timeQuery<R>(
    Future<R> result,
    Stopwatch? watch,
    String query,
    Map<String, dynamic>? values,
    String? connection,
  ) {
    if (watch == null) return result;
    return _afterQuery(result, watch, query, values, connection);
  }

  /// run [query] on [driver] and give the rows. like [timeQuery], the slow
  /// query log and the listeners see it. it is for the queries of the
  /// schema builder and the migrator, that have a driver, not a query
  /// builder. a driver that the ORM did not make (eg. one that the
  /// migrator opened from `.env`) has no connection name, so its queries
  /// run as they are.
  /// app code does not need it: use the query builder.
  Future<List<Map<String, dynamic>>> queryOn(
    DBDriver driver,
    String query, {
    Map<String, dynamic>? substitutionValues,
  }) {
    var (bool known, String? connection) = _connectionOf(driver);
    Stopwatch? watch = known ? startQueryWatch(connection) : null;
    // the schema builder and the migrator read the write database
    DBDriver run = driver is ReplicaDriver ? driver.writer : driver;
    return timeQuery(
      run.query(query, substitutionValues: substitutionValues),
      watch,
      query,
      substitutionValues,
      connection,
    );
  }

  /// like [queryOn], with [DBDriver.execute]: it runs [query] on [driver]
  /// and gives nothing back. it is for the schema builder and the
  /// migrator, not for app code.
  Future<void> executeOn(
    DBDriver driver,
    String query, {
    Map<String, dynamic>? substitutionValues,
  }) {
    var (bool known, String? connection) = _connectionOf(driver);
    Stopwatch? watch = known ? startQueryWatch(connection) : null;
    return timeQuery(
      driver.execute(query, substitutionValues: substitutionValues),
      watch,
      query,
      substitutionValues,
      connection,
    );
  }

  /// the connection name of [driver]: null for the default driver. false
  /// when the ORM did not make it.
  (bool, String?) _connectionOf(DBDriver driver) {
    if (identical(driver, _dbDriver)) return (true, null);
    for (MapEntry<String, DBDriver> e in _globalDrivers.entries) {
      if (identical(e.value, driver)) return (true, e.key);
    }
    return (false, null);
  }

  Future<R> _afterQuery<R>(
    Future<R> result,
    Stopwatch watch,
    String query,
    Map<String, dynamic>? values,
    String? connection,
  ) async {
    R rows = await result;
    Duration time = watch.elapsed;
    String name = connection ?? databaseConfig?.connection ?? 'default';
    int? slowMs = slowQueryMsOf(connection);

    /// 0 logs every query, also one that took less than 1 ms
    if (slowMs != null && (slowMs == 0 || time.inMilliseconds > slowMs)) {
      Logger().log(
        query,
        values,
        connection,
        'Slow query (${time.inMilliseconds} ms, $name): ',
        time.inMilliseconds,
      );
    }
    if (_listeners.isNotEmpty) {
      QueryEvent event = QueryEvent(
        query,
        Logger.redact(values, connection),
        time,
        name,
      );
      // a copy: a listener may remove itself
      for (QueryListener listener in List<QueryListener>.of(_listeners)) {
        try {
          listener(event);
        } catch (e, s) {
          Logger.danger('A query listener failed: $e\n$s');
        }
      }
    }
    return rows;
  }

  /// the names to hide in the log of a query on [connection]: [logRedact]
  /// and the `logRedact` of that named connection
  List<String> logRedactOf(String? connection) {
    List<String> named = connection == null
        ? const <String>[]
        : databaseConfig?.connections[connection]?.logRedact ??
              const <String>[];
    return named.isEmpty ? logRedact : <String>[...logRedact, ...named];
  }

  /// initialize with DatabaseConfig class.
  /// postgres and mysql throw an [UnsupportedError] when their native
  /// library does not load.
  static void initializeWithDatabaseConfig(DatabaseConfig config) {
    SqlQueryBuilder sql = SqlQueryBuilder();
    sql.databaseConfig = config;
    sql.flags = config.flags;
    ConnectionConfig connConfig = config.getConnectionConfig();

    sql.dbDriver = connConfig.createDriver();
    sql.debug = connConfig.debug;

    /// sticky reads need a scope per request: a Dox app gets it from this
    /// middleware, with no change in the app
    bool sticky = <ConnectionConfig>[
      connConfig,
      ...config.connections.values,
    ].any((ConnectionConfig c) => c.sticky && (c.read?.isNotEmpty ?? false));
    if (sticky) {
      ReplicaDriver.stickyInUse = true;
      GlobalMiddleware.add(stickyReads);
    }
    sql.logRedact = connConfig.logRedact;
    sql.slowQueryMs = connConfig.slowQueryMs;
    if (connConfig.printer != null) {
      sql.printer = connConfig.printer!;
    }
  }

  /// Get database driver with connection name
  DBDriver getDBDriver([String? connection]) {
    if (connection == null || databaseConfig == null) {
      return dbDriver;
    }
    DBDriver? driver = _globalDrivers[connection];
    if (driver != null) {
      return driver;
    }
    ConnectionConfig connConfig = databaseConfig!.getConnectionConfig(
      connection,
    );
    return _globalDrivers[connection] = connConfig.createDriver();
  }

  /// Close every open database connection of this isolate: the default
  /// connection and all named connections. Running queries finish first.
  /// It is safe to call it twice. Call `initialize` again to use the
  /// database after it.
  /// ```
  /// await SqlQueryBuilder.close();
  /// ```
  static Future<void> close() async {
    SqlQueryBuilder sql = SqlQueryBuilder();
    Set<DBDriver> drivers = <DBDriver>{
      ?sql._dbDriver,
      ..._globalDrivers.values,
    };
    sql._dbDriver = null;
    _globalDrivers.clear();
    for (DBDriver driver in drivers) {
      await driver.close();
    }
  }

  /// initialize query builder with your own [database]: a `PgNativePool`
  /// for postgres, a `MysqlNativePool` for mysql or a sqlite `Database`.
  /// ```
  ///  SqlQueryBuilder.initialize(
  ///   database: db,
  ///   driver: Driver.sqlite,
  ///   debug: true,
  /// );
  /// ```
  /// [flags] turns on opt-in ORM behaviors, see [OrmFlags].
  static void initialize({
    required dynamic database,
    bool debug = false,
    QueryPrinter? printer,
    Driver driver = Driver.postgres,
    OrmFlags flags = const OrmFlags(),
  }) {
    SqlQueryBuilder sql = SqlQueryBuilder();
    sql.flags = flags;

    sql.dbDriver = getDatabaseDriver(driver, database);
    sql.debug = debug;

    // coverage:ignore-start
    if (printer != null) {
      sql.printer = printer;
    }
    // coverage:ignore-end
  }
}
