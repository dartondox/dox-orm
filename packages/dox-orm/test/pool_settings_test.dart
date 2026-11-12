import 'package:dox_orm/dox_orm.dart';
import 'package:test/test.dart';

import 'connection.dart';

/// the pool settings of `extra` and query cancel. The database tests run
/// on Postgres and MySQL only: SQLite has no pool and no cancel.
void main() {
  ConnectionConfig base = databaseConfig.getConnectionConfig();
  bool native = base.driver != Driver.sqlite;

  /// a query that takes [seconds] on the server
  String sleepSql(int seconds) => base.driver == Driver.postgres
      ? 'SELECT pg_sleep($seconds) AS s'
      : 'SELECT SLEEP($seconds) AS s';

  ConnectionConfig withExtra(Map<String, dynamic> extra) => ConnectionConfig(
    driver: base.driver,
    host: base.host,
    port: base.port,
    user: base.user,
    password: base.password,
    database: base.database,
    debug: false,
    extra: <String, dynamic>{...base.extra, ...extra},
  );

  group('extraDuration', () {
    test('a Duration, an int of seconds, or null', () {
      ConnectionConfig config = ConnectionConfig(
        driver: Driver.sqlite,
        database: ':memory:',
        debug: false,
        extra: <String, dynamic>{
          'a': const Duration(milliseconds: 1500),
          'b': 30,
          'c': 'x',
        },
      );
      expect(config.extraDuration('a'), const Duration(milliseconds: 1500));
      expect(config.extraDuration('b'), const Duration(seconds: 30));
      expect(config.extraDuration('none'), isNull);
      expect(() => config.extraDuration('c'), throwsArgumentError);
    });

    test('a database url gives seconds', () {
      ConnectionConfig config = ConnectionConfig.fromUrl(
        'postgres://u:p@db/app?requestTimeout=30&idleTimeout=60',
      );
      expect(
        config.extraDuration('requestTimeout'),
        const Duration(seconds: 30),
      );
      expect(config.extraDuration('idleTimeout'), const Duration(minutes: 1));
    });
  });

  group('pool settings', () {
    test('requestTimeout stops a slow query', () async {
      DBDriver driver = withExtra(<String, dynamic>{
        'requestTimeout': const Duration(milliseconds: 300),
        // a pool of its own: isolates share a pool only with the same settings
        'maxConnectionCount': 2,
      }).createDriver();
      addTearDown(driver.close);
      Stopwatch watch = Stopwatch()..start();
      await expectLater(driver.query(sleepSql(3)), throwsA(anything));
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('maxConnectionAge, idleTimeout and serverKill are taken', () async {
      DBDriver driver = withExtra(<String, dynamic>{
        'maxConnectionAge': const Duration(minutes: 5),
        'idleTimeout': 60,
        'serverKill': false,
        'maxConnectionCount': 3,
      }).createDriver();
      addTearDown(driver.close);
      List<Map<String, dynamic>> rows = await driver.query('SELECT 1 AS n');
      expect('${rows.first['n']}', '1');
    });
  }, skip: native ? false : 'Postgres and MySQL only');

  group('cancelWith', () {
    setUpAll(initQueryBuilder);

    Matcher cancelled() => base.driver == Driver.postgres
        ? throwsA(isA<PgQueryCancelledException>())
        : throwsA(isA<MysqlQueryCancelledException>());

    test('cancel stops a running query', () async {
      QueryCancelToken token = QueryCancelToken();
      Future<List<Map<String, dynamic>>> slow = QueryBuilder.table('x')
          .rawQuery(sleepSql(10))
          .cancelWith(token)
          .get();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      Stopwatch watch = Stopwatch()..start();
      token.cancel();
      await expectLater(slow, cancelled());
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
      expect(token.isCancelled, isTrue);
    });

    test('a cancelled token fails a new query at once', () async {
      QueryCancelToken token = QueryCancelToken()..cancel();
      await expectLater(
        QueryBuilder.table('x').rawQuery(sleepSql(10)).cancelWith(token).get(),
        cancelled(),
      );
    });

    test('a query with a token that is not cancelled works', () async {
      List<Map<String, dynamic>> rows = await QueryBuilder.table('x')
          .rawQuery('SELECT 1 AS n')
          .cancelWith(QueryCancelToken())
          .get();
      expect('${rows.first['n']}', '1');
    });
  }, skip: native ? false : 'SQLite has no query cancel');
}
