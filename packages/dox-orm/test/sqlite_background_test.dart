import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dox_orm/dox_orm.dart';
import 'package:dox_orm/src/drivers/sqlite_driver.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

/// a recursive count that keeps sqlite busy for a moment
const String slowSql =
    'WITH RECURSIVE c(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM c '
    'WHERE x < 3000000) SELECT count(*) AS n FROM c';

DBDriver sqliteDriver({bool background = true, String database = ':memory:'}) {
  return ConnectionConfig(
    driver: Driver.sqlite,
    database: database,
    debug: false,
    extra: <String, dynamic>{'background': background},
  ).createDriver();
}

/// runs [body] on a driver in the helper isolate and on a normal one, and
/// gives both results, so a test can check they are the same
Future<(T, T)> both<T>(Future<T> Function(DBDriver driver) body) async {
  DBDriver plain = sqliteDriver(background: false);
  DBDriver background = sqliteDriver();
  try {
    return (await body(plain), await body(background));
  } finally {
    await plain.close();
    await background.close();
  }
}

/// uses a background driver and does not close it
Future<void> useAndForget(SendPort done) async {
  DBDriver driver = sqliteDriver();
  await driver.query('SELECT 1 AS n');
  done.send(true);
}

/// keeps every logged line
class _Capture implements QueryPrinter {
  List<String> lines = <String>[];

  @override
  void log(String query, List<String> params) {
    lines.add(query);
  }
}

void main() {
  test('the option is off by default', () async {
    DBDriver driver = ConnectionConfig(
      driver: Driver.sqlite,
      database: ':memory:',
      debug: false,
    ).createDriver();
    expect((driver as SqliteDriver).conn, isA<sqlite.Database>());
    await driver.close();
  });

  test('this isolate keeps running while a slow query runs', () async {
    DBDriver driver = sqliteDriver();
    expect((driver as SqliteDriver).conn, isA<SqliteIsolate>());
    int ticks = 0;
    Timer timer = Timer.periodic(const Duration(milliseconds: 1), (_) {
      ticks++;
    });
    List<Map<String, dynamic>> rows = await driver.query(slowSql);
    timer.cancel();
    expect(rows.first['n'], 3000000);
    expect(ticks, greaterThan(0));
    await driver.close();
  });

  test('values and types are the same as without the option', () async {
    DateTime time = DateTime.utc(2024, 5, 6, 7, 8, 9);
    var (List<Object?> plain, List<Object?> background) = await both((
      DBDriver d,
    ) async {
      await d.execute(
        'CREATE TABLE t (id INTEGER PRIMARY KEY AUTOINCREMENT, i INTEGER, '
        'f REAL, s TEXT, b BOOLEAN, d DATETIME, j JSON, raw BLOB, list TEXT)',
      );
      List<Map<String, dynamic>> inserted = await d.query(
        'INSERT INTO t (i, f, s, b, d, j, raw, list) '
        "VALUES (@i, @f, @s, @b, @d, @j, X'00ff10', @list) RETURNING id",
        primaryKey: 'id',
        substitutionValues: <String, dynamic>{
          'i': 42,
          'f': 1.5,
          's': "it's",
          'b': true,
          'd': time,
          'j': <String, dynamic>{'a': 1},
          'list': Uint8List.fromList(<int>[1, 2]),
        },
      );
      await d.execute(
        'INSERT INTO t (s) VALUES (@s)',
        substitutionValues: <String, dynamic>{'s': null},
      );
      List<Map<String, dynamic>> rows = await d.query(
        'SELECT * FROM t ORDER BY id',
      );
      int changed = await d.affectingStatement(
        'UPDATE t SET i = @i',
        substitutionValues: <String, dynamic>{'i': 7},
      );
      int deleted = await d.affectingStatement('DELETE FROM t WHERE id = 1');
      return <Object?>[inserted, rows, changed, deleted];
    });
    expect(background, plain);
    List<Map<String, dynamic>> rows =
        background[1] as List<Map<String, dynamic>>;
    expect(rows.first['b'], isTrue);
    expect(rows.first['d'], time);
    expect(rows.first['j'], <String, dynamic>{'a': 1});
    expect(rows.first['raw'], isA<Uint8List>());
    expect(rows.first['raw'], <int>[0, 255, 16]);
    expect(rows.last['s'], isNull);
    expect(background[2], 2);
    expect(background[3], 1);
  });

  test('a SQL error is the same SqliteException as without the option', () {
    return both((DBDriver d) async {
      await d.execute('CREATE TABLE u (email TEXT UNIQUE)');
      await d.execute("INSERT INTO u VALUES ('a@b.c')");
      try {
        await d.execute(
          'INSERT INTO u VALUES (@e)',
          substitutionValues: <String, dynamic>{'e': 'a@b.c'},
        );
      } on sqlite.SqliteException catch (e) {
        return e;
      }
      fail('no error');
    }).then(((sqlite.SqliteException, sqlite.SqliteException) errors) {
      var (sqlite.SqliteException plain, sqlite.SqliteException bg) = errors;
      expect(bg.extendedResultCode, plain.extendedResultCode);
      expect(bg.resultCode, 19);
      expect(bg.message, plain.message);
      expect(bg.causingStatement, plain.causingStatement);
      expect(bg.parametersToStatement, plain.parametersToStatement);
      expect(bg.toString(), plain.toString());
    });
  });

  test('transactions commit, roll back and do not mix', () async {
    DBDriver d = sqliteDriver();
    await d.execute('CREATE TABLE t (n INTEGER)');

    await d.transaction(() async {
      await d.execute('INSERT INTO t VALUES (1)');
    });
    await expectLater(
      d.transaction(() async {
        await d.execute('INSERT INTO t VALUES (2)');
        await d.execute('INSERT INTO nope VALUES (2)');
      }),
      throwsA(isA<sqlite.SqliteException>()),
    );
    await expectLater(
      d.transaction(() async {
        await d.execute('INSERT INTO t VALUES (3)');
        throw StateError('stop');
      }),
      throwsStateError,
    );

    /// three requests start a transaction at the same time. each one sees
    /// only its own rows, and the one that fails leaves nothing.
    Completer<void> firstInside = Completer<void>();
    Future<int> request(int n, bool fails) {
      return d.transaction(() async {
        await d.execute(
          'INSERT INTO t VALUES (@n)',
          substitutionValues: <String, dynamic>{'n': n},
        );
        if (!firstInside.isCompleted) firstInside.complete();
        await Future<void>.delayed(const Duration(milliseconds: 5));
        List<Map<String, dynamic>> rows = await d.query(
          'SELECT count(*) AS c FROM t WHERE n >= 10',
        );
        if (fails) throw StateError('fail $n');
        return rows.first['c'] as int;
      });
    }

    List<Future<int>> requests = <Future<int>>[
      request(10, false),
      request(11, true),
      request(12, false),
    ];

    /// a query outside waits for the open transaction to end
    await firstInside.future;
    Future<List<Map<String, dynamic>>> outside = d.query('SELECT n FROM t');
    expect(await requests[0], 1);
    await expectLater(requests[1], throwsStateError);
    expect(await requests[2], 2);
    List<Object?> seen = <Object?>[
      for (Map<String, dynamic> r in await outside) r['n'],
    ];
    expect(seen, containsAll(<int>[1, 10]));
    expect(seen, isNot(contains(11)));
    expect(
      <Object?>[
        for (Map<String, dynamic> r in await d.query(
          'SELECT n FROM t ORDER BY n',
        ))
          r['n'],
      ],
      <int>[1, 10, 12],
    );
    await d.close();
  });

  test('a file database opens with WAL and busy_timeout', () async {
    Directory dir = Directory.systemTemp.createTempSync('dox_sqlite_bg_');
    addTearDown(() => dir.deleteSync(recursive: true));
    DBDriver d = sqliteDriver(database: '${dir.path}/app.sqlite');
    expect((await d.query('PRAGMA journal_mode')).first.values.first, 'wal');
    expect((await d.query('PRAGMA busy_timeout')).first.values.first, 5000);
    expect((await d.query('PRAGMA foreign_keys')).first.values.first, 1);
    await d.close();
  });

  test('a database that does not open gives its error, not a hang', () async {
    DBDriver d = sqliteDriver(database: '/no/such/folder/app.sqlite');
    await expectLater(
      d.query('SELECT 1'),
      throwsA(isA<sqlite.SqliteException>()),
    );
    await d.close();
  });

  test('close lets sent queries finish, later ones get an error', () async {
    DBDriver d = sqliteDriver();
    SqliteIsolate helper = (d as SqliteDriver).conn as SqliteIsolate;
    await d.execute('CREATE TABLE t (n INTEGER)');
    Future<List<Map<String, dynamic>>> sent = d.query(slowSql);

    /// a query outside the transaction waits for it to end
    Completer<void> inside = Completer<void>();
    Future<void> tx = d.transaction(() async {
      await d.execute('INSERT INTO t VALUES (1)');
      inside.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await d.execute('INSERT INTO t VALUES (2)');
    });
    await inside.future;
    Future<List<Map<String, dynamic>>> waiting = d.query('SELECT * FROM t');

    Future<void> closed = d.close();
    await expectLater(tx, throwsStateError);
    await expectLater(waiting, throwsA(anything));
    expect((await sent).first['n'], 3000000);
    await closed;
    await d.close();
    await expectLater(helper.close(), completes);
  });

  test('a helper isolate that dies gives an error, not a hang', () async {
    DBDriver d = sqliteDriver();
    SqliteIsolate helper = (d as SqliteDriver).conn as SqliteIsolate;
    await d.query('SELECT 1');
    Future<List<Map<String, dynamic>>> waiting = d.query(slowSql);
    helper.isolate!.kill(priority: Isolate.immediate);
    await expectLater(waiting, throwsStateError);
    await expectLater(d.query('SELECT 1'), throwsStateError);
    await d.close();
  });

  test('a driver that is not closed does not keep its isolate alive', () async {
    ReceivePort exit = ReceivePort();
    ReceivePort done = ReceivePort();
    await Isolate.spawn(useAndForget, done.sendPort, onExit: exit.sendPort);
    expect(await done.first, isTrue);
    await exit.first.timeout(const Duration(seconds: 10));
  });

  test('the query listener and slow log see the full wait', () async {
    _Capture slowLog = _Capture();
    SqlQueryBuilder.initializeWithDatabaseConfig(
      DatabaseConfig(
        connection: 'bg',
        connections: <String, ConnectionConfig>{
          'bg': ConnectionConfig(
            driver: Driver.sqlite,
            database: ':memory:',
            debug: false,
            extra: <String, dynamic>{'background': true},
            slowQueryMs: 1,
            printer: slowLog,
          ),
        },
      ),
    );
    addTearDown(SqlQueryBuilder.close);
    List<QueryEvent> events = <QueryEvent>[];
    SqlQueryBuilder().listen(events.add);
    addTearDown(() => SqlQueryBuilder().removeListener(events.add));
    Stopwatch watch = Stopwatch()..start();
    await QueryBuilder.query(slowSql);
    watch.stop();
    expect(events, hasLength(1));
    expect(events.first.time.inMilliseconds, greaterThan(1));
    expect(events.first.time, lessThanOrEqualTo(watch.elapsed));
    expect(slowLog.lines, hasLength(1));
  });
}
