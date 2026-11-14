import 'package:dox_orm/dox_orm.dart';
import 'package:dox_orm/src/drivers/sqlite_driver.dart';

class ConnectionConfig {
  /// Database driver
  /// Driver.postgres, Driver.mysql (also mariadb) or Driver.sqlite
  Driver driver;

  /// Enable debugging mode
  bool debug;

  /// Query printer to use when debugging mode is no.
  /// support build-in `PrettyQueryPrinter()` and `ConsoleQueryPrinter()`
  /// and `FileQueryPrinter()`.
  /// You can also create your own custom query printer by implementing
  /// `QueryPrinter` interface
  QueryPrinter? printer;

  /// names of values to hide in the debug query log. off by default: the
  /// log shows every value. a value is shown as `***` when its key ends
  /// with one of these names (case does not matter). eg. `['password',
  /// 'token']` hides `password`, `users.password`, `old_password` and
  /// `remember_token`. only the log changes, the query still gets the
  /// real values.
  List<String> logRedact;

  /// log each query that takes longer than this many milliseconds. 0 logs
  /// every query. null (the default) turns it off. it works with [debug]
  /// off. the line goes to the query printer and hides the `logRedact`
  /// values. a failed query is not logged here. with [debug] on, a slow
  /// query of the query builder shows twice: the debug line before it
  /// runs, and the slow line with its time after it.
  int? slowQueryMs;

  /// database host
  String host;

  /// database username
  String user;

  /// database password
  String password;

  /// database name.
  /// for sqlite it is the file path, or `:memory:`
  String database;

  /// database connection port
  int port;

  /// use TLS.
  /// - mysql: the server certificate is checked. set
  ///   `extra['verifyCertificate']` to false to skip the check, eg. for a
  ///   self-signed certificate in development.
  /// - postgres: TLS mode `require` (encrypt, no certificate check, like
  ///   libpq). set `extra['sslMode']` to `verify-full` to also check the
  ///   certificate. see [postgresSslMode]. the app prints one warning to
  ///   stderr when it connects with `require`. set `extra['sslWarning']`
  ///   to false to turn the warning off.
  bool useSSL;

  /// extra configuration for the connection
  /// eg. `maxConnectionCount`, `requestTimeout`, `maxConnectionAge` and
  /// `idleTimeout` for postgres and mysql, `serverKill` for mysql,
  /// `sslMode` for postgres, `busyTimeout` and `background` for sqlite
  /// (see [sqliteBackground]).
  Map<String, dynamic> extra;

  /// use your own driver class instead of the built-in one.
  /// it gets this config and returns the driver. it wins over every other
  /// setting. [driver] is still used to pick the sql dialect.
  ///
  /// ```
  /// driverFactory: MysqlDriverOfMyOwn.fromConfig,
  /// ```
  DBDriver Function(ConnectionConfig config)? driverFactory;

  /// read replicas. When it is set (and not empty), a plain `SELECT` goes
  /// to one of these hosts, and everything else (writes, locks, schema
  /// changes, transactions) to the write host. See [ReplicaDriver].
  ///
  /// Each map changes some settings of this config for that host: `host`,
  /// `port`, `user`, `password`, `database`, and `extra` (added to
  /// [extra]). The other settings are shared. The hosts take turns (round
  /// robin). With a database url (`DATABASE_URL`, see
  /// [DatabaseConfig.url]), the url is the write host, and these read
  /// hosts and [sticky] stay. [write] is not used then.
  ///
  /// ```
  /// ConnectionConfig(
  ///   driver: Driver.postgres,
  ///   host: 'primary.db',
  ///   user: 'app',
  ///   database: 'app',
  ///   debug: false,
  ///   read: <Map<String, dynamic>>[
  ///     <String, dynamic>{'host': 'replica-1.db'},
  ///     <String, dynamic>{'host': 'replica-2.db'},
  ///   ],
  ///   sticky: true,
  /// )
  /// ```
  List<Map<String, dynamic>>? read;

  /// settings of the write host, in the same form as one [read] map. With
  /// no [write], the write host is this config as it is. Only used with
  /// [read].
  Map<String, dynamic>? write;

  /// with [read]: after a write, the reads of the same unit of work go to
  /// the write host, so they see the write. The unit is a
  /// [ReplicaDriver.stickyScope], eg. one request. Off by default.
  bool sticky;

  /// [user], [password] and [port] are not used by sqlite
  ConnectionConfig({
    required this.driver,
    this.host = 'localhost',
    this.useSSL = false,
    this.user = '',
    this.password = '',
    required this.database,
    this.port = 0,
    this.extra = const <String, dynamic>{},
    required this.debug,
    this.printer,
    this.driverFactory,
    this.logRedact = const <String>[],
    this.slowQueryMs,
    this.read,
    this.write,
    this.sticky = false,
  });

  /// Makes a config from a database url, like `DATABASE_URL`.
  ///
  /// - `postgres://user:pass@host:5432/db` (also `postgresql://`)
  /// - `mysql://user:pass@host:3306/db` (also `mariadb://`)
  /// - `sqlite:///abs/path.db`, `sqlite://db/dox.sqlite`, `sqlite::memory:`
  ///   or `file:db/dox.sqlite`
  ///
  /// The user, password and database name are url-decoded. A missing port
  /// is 5432 for Postgres and 3306 for MySQL.
  ///
  /// Query options:
  /// - `host=/path` (or `socket=/path`): a Unix socket. It wins over the
  ///   host part of the url. For Postgres it is the socket folder, eg.
  ///   `/cloudsql/project:region:instance`. For MySQL it is the socket
  ///   file, eg. `/var/run/mysqld/mysqld.sock`.
  /// - `sslmode` (or `ssl`): `disable`, `false` and `0` mean no TLS.
  ///   `allow` and `prefer` use TLS only when the server has it (Postgres)
  ///   and set no [useSSL]. Any other value (eg. `require`, `true`) turns
  ///   TLS on. For Postgres, `require` does not check the certificate (like
  ///   libpq), `verify-ca` and `verify-full` check it. For MySQL the
  ///   certificate is checked, add `verifyCertificate=false` to skip the
  ///   check (eg. a self-signed certificate in development).
  /// - `sslrootcert=/path/ca.pem` (Postgres): the CA certificates to trust
  ///   for `verify-full`. See [postgresSslRootCert].
  /// - any other option goes to [extra]. `10` becomes an int, and `true` or
  ///   `false` a bool. Eg. `?maxConnectionCount=20`. For SQLite every
  ///   option goes to [extra], eg. `sqlite://db/dox.sqlite?background=true`.
  ///
  /// [extra] is the base, the url options win over it.
  factory ConnectionConfig.fromUrl(
    String url, {
    bool debug = false,
    QueryPrinter? printer,
    Map<String, dynamic> extra = const <String, dynamic>{},
    List<String> logRedact = const <String>[],
    int? slowQueryMs,
  }) {
    url = url.trim();
    int colon = url.indexOf(':');
    String scheme = colon < 0 ? '' : url.substring(0, colon).toLowerCase();

    if (scheme == 'sqlite' || scheme == 'file') {
      String path = url.substring(colon + 1);
      if (path.startsWith('//')) path = path.substring(2);
      Map<String, dynamic> options = <String, dynamic>{...extra};
      int query = path.indexOf('?');
      if (query >= 0) {
        try {
          for (MapEntry<String, String> e in Uri.splitQueryString(
            path.substring(query + 1),
          ).entries) {
            options[e.key] = _urlValue(e.value);
          }
        } on ArgumentError {
          // options that can not be read are left out, as before
        }
        path = path.substring(0, query);
      }
      return ConnectionConfig(
        driver: Driver.sqlite,
        database: Uri.decodeComponent(path),
        debug: debug,
        printer: printer,
        logRedact: logRedact,
        slowQueryMs: slowQueryMs,
        extra: options,
      );
    }

    // The url can hold a secret anywhere (user info, path, query,
    // fragment), so no error shows any part of it after the scheme.
    Driver driver = switch (scheme) {
      'postgres' || 'postgresql' => Driver.postgres,
      'mysql' || 'mariadb' => Driver.mysql,
      _ => throw FormatException(
        'DATABASE_URL must start with postgres://, postgresql://, mysql://, '
        'mariadb://, sqlite: or file:${_schemeHint(scheme)}',
      ),
    };
    if (!url.startsWith('//', colon + 1)) {
      // without `//` there is no host, and the rest would be the
      // database name
      throw FormatException(
        'DATABASE_URL has no host. Use $scheme://user:password@host/database',
      );
    }
    try {
      return _fromServerUrl(
        url,
        driver,
        debug: debug,
        printer: printer,
        extra: extra,
        logRedact: logRedact,
        slowQueryMs: slowQueryMs,
      );
    } on FormatException catch (e) {
      // the error of Uri holds the whole url: only a fixed text here
      throw FormatException(
        e.message.toLowerCase().contains('port')
            ? 'DATABASE_URL has a bad port'
            : 'DATABASE_URL is not a valid url',
      );
    } on ArgumentError {
      // eg. a bad `%` in the user or password
      throw FormatException('DATABASE_URL is not a valid url');
    }
  }

  /// ` (it starts with x:)` when [scheme] is a plain scheme name, else
  /// nothing: text before the first `:` with other characters can be a
  /// part of the user info
  static String _schemeHint(String scheme) =>
      RegExp(r'^[a-z][a-z0-9+.-]{0,19}$').hasMatch(scheme)
      ? ' (it starts with $scheme:)'
      : '';

  static ConnectionConfig _fromServerUrl(
    String url,
    Driver driver, {
    required bool debug,
    required QueryPrinter? printer,
    required Map<String, dynamic> extra,
    required List<String> logRedact,
    required int? slowQueryMs,
  }) {
    Uri uri = Uri.parse(url);
    Map<String, dynamic> options = <String, dynamic>{...extra};
    String host = Uri.decodeComponent(uri.host);
    bool useSSL = false;
    uri.queryParameters.forEach((String key, String value) {
      switch (key) {
        case 'host' || 'socket':
          host = value;
        case 'sslmode' || 'ssl':
          String mode = switch (value.toLowerCase()) {
            'disable' || 'disabled' || 'false' || '0' => 'disable',
            'allow' || 'prefer' || 'preferred' => 'prefer',
            'verify-ca' => 'verify-ca',
            String m when m.startsWith('verify') => 'verify-full',
            _ => 'require',
          };
          useSSL = mode == 'require' || mode.startsWith('verify');
          // like libpq: `require` encrypts but does not check the
          // certificate (eg. Heroku). `verify-ca` and `verify-full`
          // check it.
          if (driver == Driver.postgres) options['sslMode'] = mode;
        case 'sslrootcert' when driver == Driver.postgres:
          options['sslRootCert'] = value;
        default:
          options[key] = _urlValue(value);
      }
    });
    List<String> userInfo = uri.userInfo.split(':');
    String path = uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;

    return ConnectionConfig(
      driver: driver,
      host: host.isEmpty ? 'localhost' : host,
      port: uri.hasPort
          ? uri.port
          : driver == Driver.postgres
          ? 5432
          : 3306,
      user: Uri.decodeComponent(userInfo.first),
      password: userInfo.length > 1
          ? Uri.decodeComponent(userInfo.sublist(1).join(':'))
          : '',
      database: Uri.decodeComponent(path),
      useSSL: useSSL,
      debug: debug,
      printer: printer,
      logRedact: logRedact,
      slowQueryMs: slowQueryMs,
      extra: options,
    );
  }

  /// a url option value: `10` becomes an int, `true` or `false` a bool
  static Object _urlValue(String value) =>
      int.tryParse(value) ?? bool.tryParse(value) ?? value;

  /// true when [host] is a Unix socket: a path that starts with `/`.
  /// For Postgres it is the folder of the socket, like libpq. For MySQL it
  /// is the socket file. Eg. Google Cloud SQL uses
  /// `/cloudsql/project:region:instance` for both.
  bool get isUnixSocket => host.startsWith('/');

  /// false when `extra['verifyCertificate']` is false: MySQL TLS does
  /// not check the server certificate. only use it for a self-signed
  /// certificate in development. default true.
  bool get verifyCertificate => extra['verifyCertificate'] as bool? ?? true;

  /// the Postgres TLS mode: `disable`, `prefer`, `require`, `verify-ca`
  /// (checks the certificate, not the host name) or `verify-full`. it is `extra['sslMode']` when set, else `require`
  /// with [useSSL], else `disable`.
  ///
  /// `require` encrypts the data but does not check the server
  /// certificate, so it does not stop a fake server in the middle. the app
  /// prints one warning to stderr when it connects with `require`. use
  /// `verify-full` in production.
  String get postgresSslMode =>
      extra['sslMode'] as String? ?? (useSSL ? 'require' : 'disable');

  /// the path of a PEM file with the CA certificates that Postgres TLS
  /// trusts for `verify-ca` and `verify-full`, eg. the CA of a cloud database. it is
  /// `extra['sslRootCert']` (`sslrootcert` in a url). when it is not set,
  /// the system certificates are used.
  String? get postgresSslRootCert => extra['sslRootCert'] as String?;

  /// max prepared statements kept per connection (default 100).
  /// set it with `extra['preparedStatementCacheSize']`.
  int get statementCacheSize =>
      extra['preparedStatementCacheSize'] as int? ?? defaultStatementCacheSize;

  /// sqlite only: run the queries in a helper isolate when
  /// `extra['background']` is true. off by default.
  ///
  /// sqlite is synchronous, so a query blocks the isolate that runs it.
  /// with this on, the helper isolate owns the database and this isolate
  /// only waits for the answer, so it can serve other requests in the
  /// meantime. each query costs one message to the helper and one back.
  /// it helps when some queries are slow. it does not help an app that
  /// runs many tiny queries: they get a little slower.
  ///
  /// `true`, `1`, `'true'` and `'1'` turn it on, so `?background=true`
  /// in the database url works too.
  bool get sqliteBackground => switch (extra['background']) {
    true || 1 => true,
    String s => s.toLowerCase() == 'true' || s == '1',
    _ => false,
  };

  /// `extra[key]` as a [Duration]. An int is seconds, so a database url
  /// (eg. `?requestTimeout=30`) works too. Null when it is not set.
  Duration? extraDuration(String key) => switch (extra[key]) {
    Duration d => d,
    int seconds => Duration(seconds: seconds),
    null => null,
    Object v => throw ArgumentError.value(
      v,
      key,
      'must be a Duration or an int of seconds',
    ),
  };

  int get _busyTimeout => extra['busyTimeout'] as int? ?? 5000;

  /// make the driver of this connection: [driverFactory] when it is set,
  /// else the native driver for postgres and mysql, else the sqlite
  /// driver. postgres and mysql throw an [UnsupportedError] when their
  /// native library does not load (see [NativeDrivers.ensureAvailable]).
  ///
  /// With [read] hosts it makes a [ReplicaDriver]: one driver for the
  /// write host and one for each read host.
  DBDriver createDriver() {
    List<Map<String, dynamic>>? reads = read;
    if (reads != null && reads.isNotEmpty) {
      Map<String, dynamic>? writeHost = write;
      return ReplicaDriver(
        writer: (writeHost == null ? this : _forHost(writeHost))._create(),
        readers: <DBDriver>[
          for (Map<String, dynamic> r in reads) _forHost(r)._create(),
        ],
        sticky: sticky,
      );
    }
    return _create();
  }

  /// the keys a [read] or [write] map can have
  static const Set<String> _hostKeys = <String>{
    'host',
    'port',
    'user',
    'password',
    'database',
    'extra',
  };

  /// a copy of this config with the settings of one [read] or [write]
  /// [host], and no read hosts
  ConnectionConfig _forHost(Map<String, dynamic> host) {
    for (String key in host.keys) {
      if (!_hostKeys.contains(key)) {
        throw ArgumentError.value(
          key,
          'read/write',
          'is not a host setting. Use ${_hostKeys.join(', ')}',
        );
      }
    }
    return ConnectionConfig(
      driver: driver,
      host: host['host'] as String? ?? this.host,
      port: host['port'] as int? ?? port,
      user: host['user'] as String? ?? user,
      password: host['password'] as String? ?? password,
      database: host['database'] as String? ?? database,
      useSSL: useSSL,
      extra: <String, dynamic>{
        ...extra,
        ...?host['extra'] as Map<String, dynamic>?,
      },
      debug: debug,
      printer: printer,
      driverFactory: driverFactory,
      logRedact: logRedact,
      slowQueryMs: slowQueryMs,
    );
  }

  /// the driver of one host
  DBDriver _create() {
    if (driverFactory != null) {
      return driverFactory!(this);
    }
    return switch (driver) {
      Driver.postgres => PostgresNativeDriver.fromConfig(this),
      Driver.mysql => MysqlNativeDriver.fromConfig(this),
      Driver.sqlite => SqliteDriver(
        conn: sqliteBackground
            ? SqliteIsolate(database, _busyTimeout, statementCacheSize)
            : openSqliteDatabase(database, _busyTimeout),
        statementCacheSize: statementCacheSize,
      ),
    };
  }
}
