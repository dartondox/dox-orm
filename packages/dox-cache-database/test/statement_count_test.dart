import 'package:dox_cache_database/dox_cache_database.dart';
import 'package:dox_orm/dox_orm.dart';
import 'package:test/test.dart';

/// Counts the statements a call sends. A transaction counts 2 (BEGIN and
/// COMMIT). Every row read gives the value `1`, every write changes 1 row.
class CountingDriver extends DBDriver {
  CountingDriver(this.type, {this.returning = true});

  final Driver type;
  final bool returning;
  List<String> statements = <String>[];

  @override
  Driver getName() => type;

  @override
  bool get supportsReturning => returning;

  @override
  Future<List<Map<String, dynamic>>> query(
    String query, {
    String? primaryKey,
    Map<String, dynamic>? substitutionValues,
  }) async {
    statements.add(query);
    return <Map<String, dynamic>>[
      <String, dynamic>{'value': '1', 'expires_at': null},
    ];
  }

  @override
  Future<void> execute(
    String query, {
    Map<String, dynamic>? substitutionValues,
  }) async {
    statements.add(query);
  }

  @override
  Future<int> affectingStatement(
    String query, {
    Map<String, dynamic>? substitutionValues,
  }) async {
    statements.add(query);
    return 1;
  }

  @override
  Future<R> transaction<R>(Future<R> Function() callback) async {
    statements.add('BEGIN');
    R result = await callback();
    statements.add('COMMIT');
    return result;
  }
}

/// Statements per call: add, lock get, increment, pull, touch.
Future<List<int>> counts(CountingDriver db) async {
  DatabaseCacheDriver cache = DatabaseCacheDriver(database: db);
  List<int> result = <int>[];
  Future<void> count(Future<Object?> Function() call) async {
    db.statements.clear();
    await call();
    result.add(db.statements.length);
  }

  await count(() => cache.add('a', 'v', null));
  await count(() => cache.lock('job', null).get());
  await count(() => cache.increment('n', 1));
  await count(() => cache.pull('a'));
  await count(() => cache.touch('a', null));
  return result;
}

void main() {
  test('Postgres: one statement each', () async {
    expect(await counts(CountingDriver(Driver.postgres)), <int>[1, 1, 1, 1, 1]);
  });

  test('SQLite: one statement each', () async {
    expect(await counts(CountingDriver(Driver.sqlite)), <int>[1, 1, 1, 1, 1]);
  });

  test('SQLite without RETURNING: old increment and pull', () async {
    expect(await counts(CountingDriver(Driver.sqlite, returning: false)), <int>[
      1,
      1,
      5,
      5,
      1,
    ]);
  });

  test('MySQL: increment in a transaction, pull as before', () async {
    expect(await counts(CountingDriver(Driver.mysql)), <int>[1, 1, 4, 5, 1]);
  });

  test('the SQL text is built once per database type', () async {
    CountingDriver db = CountingDriver(Driver.postgres);
    DatabaseCacheDriver cache = DatabaseCacheDriver(database: db);
    await cache.put('a', 1, null);
    await cache.put('b', 2, null);
    expect(identical(db.statements[0], db.statements[1]), isTrue);
  });
}
