import 'package:dox_orm/dox_orm.dart';
import 'package:test/test.dart';

/// keeps every logged query
class _Capture implements QueryPrinter {
  List<String> queries = <String>[];
  List<List<String>> params = <List<String>>[];

  @override
  void log(String query, List<String> params) {
    queries.add(query);
    this.params.add(params);
  }
}

void main() {
  late _Capture capture;
  late QueryPrinter oldPrinter;
  List<QueryEvent> events = <QueryEvent>[];

  void onQuery(QueryEvent e) => events.add(e);
  void fails(QueryEvent e) => throw StateError('listener broke');

  setUp(() async {
    SqlQueryBuilder.initializeWithDatabaseConfig(
      DatabaseConfig(
        connection: 'main',
        url: '',
        connections: <String, ConnectionConfig>{
          'main': ConnectionConfig(
            driver: Driver.sqlite,
            database: ':memory:',
            debug: false,
            logRedact: <String>['password'],
          ),
        },
      ),
    );
    await QueryBuilder.query(
      'CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, password TEXT)',
    );
    oldPrinter = SqlQueryBuilder().printer;
    capture = _Capture();
    SqlQueryBuilder().printer = capture;
    events.clear();
  });

  tearDown(() async {
    SqlQueryBuilder sql = SqlQueryBuilder();
    sql.removeListener(onQuery);
    sql.removeListener(fails);
    sql.printer = oldPrinter;
    sql.slowQueryMs = null;
    sql.logRedact = <String>[];
    await SqlQueryBuilder.close();
  });

  group('query listener', () {
    test('gets sql, bindings, time and connection', () async {
      SqlQueryBuilder().listen(onQuery);
      await QueryBuilder.table('users')
          .insert(<String, dynamic>{'name': 'ann', 'password': 'secret'});
      await QueryBuilder.table('users').where('name', 'ann').get();
      expect(events.length, 2);
      QueryEvent e = events.last;
      expect(e.sql, contains('SELECT'));
      expect(e.bindings.values, contains('ann'));
      expect(e.time, isA<Duration>());
      expect(e.connection, 'main');
      // the insert hides the password, the query still stores it
      expect(events.first.bindings.values, contains('***'));
      expect(events.first.bindings.values, isNot(contains('secret')));
      Map<String, dynamic>? row = await QueryBuilder.table('users')
          .where('name', 'ann')
          .getFirst();
      expect(row!['password'], 'secret');
    });

    test('works for updates, raw queries and in a transaction', () async {
      SqlQueryBuilder().listen(onQuery);
      await QueryBuilder.transaction(() async {
        await QueryBuilder.table('users')
            .insert(<String, dynamic>{'name': 'a'});
        await QueryBuilder.table('users')
            .where('name', 'a')
            .update(<String, dynamic>{'name': 'b'});
      });
      await QueryBuilder.query(
        'SELECT * FROM users WHERE name = @n',
        substitutionValues: <String, dynamic>{'n': 'b'},
      );
      expect(events.length, 3);
      expect(events[1].sql, startsWith('UPDATE'));
      expect(events[2].bindings, <String, dynamic>{'n': 'b'});
    });

    test('a listener that throws does not break the query', () async {
      SqlQueryBuilder().listen(fails);
      SqlQueryBuilder().listen(onQuery);
      List<Map<String, dynamic>> rows = await QueryBuilder.table('users').get();
      expect(rows, isEmpty);
      // the next listener still runs
      expect(events.length, 1);
    });

    test('removeListener stops it', () async {
      SqlQueryBuilder sql = SqlQueryBuilder();
      sql.listen(onQuery);
      await QueryBuilder.table('users').get();
      expect(sql.removeListener(onQuery), isTrue);
      await QueryBuilder.table('users').get();
      expect(events.length, 1);
      expect(sql.removeListener(onQuery), isFalse);
    });

    test('no listener and no slow log: no stopwatch', () {
      expect(SqlQueryBuilder().startQueryWatch(null), isNull);
      SqlQueryBuilder().listen(onQuery);
      expect(SqlQueryBuilder().startQueryWatch(null), isNotNull);
    });
  });

  group('slow query log', () {
    test('logs a query above the limit, with debug off', () async {
      SqlQueryBuilder().slowQueryMs = 0;
      // a query that takes more than 0 ms
      await QueryBuilder.query(
        'WITH RECURSIVE c(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM c '
        'WHERE x < 300000) SELECT count(*) FROM c WHERE @password_p1 = @password_p1',
        substitutionValues: <String, dynamic>{'password_p1': 'secret'},
      );
      expect(capture.queries.length, 1);
      expect(capture.queries.first, startsWith('Slow query ('));
      expect(capture.queries.first, contains('ms, main): WITH RECURSIVE'));
      expect(capture.params.first, <String>['***', '***']);
    });

    test('does not log a query below the limit', () async {
      SqlQueryBuilder().slowQueryMs = 60000;
      await QueryBuilder.table('users').get();
      expect(capture.queries, isEmpty);
    });

    test('is off by default', () async {
      expect(SqlQueryBuilder().slowQueryMs, isNull);
      await QueryBuilder.table('users').get();
      expect(capture.queries, isEmpty);
    });

    test(
      'ConnectionConfig.slowQueryMs is read on initialize and by url',
      () async {
        await SqlQueryBuilder.close();
        SqlQueryBuilder.initializeWithDatabaseConfig(
          DatabaseConfig(
            connection: 'slow',
            url: '',
            connections: <String, ConnectionConfig>{
              'slow': ConnectionConfig(
                driver: Driver.sqlite,
                database: ':memory:',
                debug: false,
                slowQueryMs: 250,
              ),
            },
          ),
        );
        expect(SqlQueryBuilder().slowQueryMs, 250);
        expect(SqlQueryBuilder().slowQueryMsOf('slow'), 250);
        expect(
          ConnectionConfig.fromUrl(
            'sqlite::memory:',
            slowQueryMs: 9,
          ).slowQueryMs,
          9,
        );
      },
    );
  });
}
