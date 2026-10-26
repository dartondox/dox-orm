import 'dart:async';

import 'package:dox_orm/dox_orm.dart';
import 'package:test/test.dart';

import 'connection.dart';
import 'models/scoped_post/scoped_post.model.dart';
import 'models/setting/setting.model.dart';

/// a driver that runs nothing: it keeps the sql and gives no rows
class SqlOnlyDriver extends DBDriver {
  final Driver name;
  final List<String> sqls = <String>[];

  SqlOnlyDriver(this.name);

  @override
  Driver getName() => name;

  @override
  Future<List<Map<String, dynamic>>> query(
    String query, {
    String? primaryKey,
    Map<String, dynamic>? substitutionValues,
  }) async {
    sqls.add(query);
    return <Map<String, dynamic>>[];
  }

  @override
  Future<void> execute(
    String query, {
    Map<String, dynamic>? substitutionValues,
  }) async {
    sqls.add(query);
  }

  @override
  Future<R> transaction<R>(Future<R> Function() callback) => callback();
}

/// a table query on [driver]
class FakeQuery extends QueryBuilder<Map<String, dynamic>> {
  final DBDriver driver;

  FakeQuery(this.driver, String table) {
    tableName = table;
  }

  @override
  DBDriver get dbDriver => driver;
}

/// the lock sql of each driver
const Map<Driver, (String, String)> lockSql = <Driver, (String, String)>{
  Driver.postgres: (' FOR UPDATE', ' FOR SHARE'),
  Driver.mysql: (' FOR UPDATE', ' LOCK IN SHARE MODE'),
  Driver.sqlite: ('', ''),
};

void main() async {
  await initQueryBuilder();

  Driver current = SqlQueryBuilder().dbDriver.getName();

  group('Lock sql |', () {
    for (Driver d in Driver.values) {
      String forUpdate = lockSql[d]!.$1;
      String forShare = lockSql[d]!.$2;
      String q = d == Driver.mysql ? '`' : '"';

      test('${d.name}: the lock goes after limit and offset', () {
        SqlOnlyDriver driver = SqlOnlyDriver(d);
        String sql = FakeQuery(driver, 'blog')
            .where('id', 1)
            .orderBy('id')
            .limit(5)
            .offset(10)
            .lockForUpdate()
            .toSql();
        expect(
          sql,
          'SELECT * FROM ${q}blog$q WHERE ${q}id$q = 1 ORDER BY ${q}id$q '
          'LIMIT 5 OFFSET 10$forUpdate',
        );
        expect(
          FakeQuery(driver, 'blog').sharedLock().toSql(),
          'SELECT * FROM ${q}blog$q$forShare',
        );
      });

      test('${d.name}: count, sum and hasRows do not lock', () async {
        SqlOnlyDriver driver = SqlOnlyDriver(d);
        await FakeQuery(driver, 'blog').lockForUpdate().count();
        await FakeQuery(driver, 'blog').lockForUpdate().sum('views');
        await FakeQuery(driver, 'blog').lockForUpdate().hasRows();
        for (String sql in driver.sqls) {
          expect(sql, isNot(contains('FOR UPDATE')));
        }
      });

      test('${d.name}: update and delete do not lock', () async {
        SqlOnlyDriver driver = SqlOnlyDriver(d);
        await FakeQuery(
          driver,
          'blog',
        ).where('id', 1).lockForUpdate().update(<String, dynamic>{'a': 1});
        await FakeQuery(driver, 'blog').where('id', 1).lockForUpdate().delete();
        expect(driver.sqls.length, 2);
        for (String sql in driver.sqls) {
          expect(sql, isNot(contains('FOR ')));
          expect(sql, isNot(contains('SHARE')));
        }
      });

      test('${d.name}: find, getFirst, all and pluck lock', () async {
        SqlOnlyDriver driver = SqlOnlyDriver(d);
        await FakeQuery(driver, 'blog').lockForUpdate().find(1);
        await FakeQuery(driver, 'blog').lockForUpdate().getFirst();
        await FakeQuery(driver, 'blog').sharedLock().all();
        await FakeQuery(driver, 'blog').sharedLock().pluck('id');
        expect(driver.sqls[0], endsWith('LIMIT @dox_limit$forUpdate'));
        expect(driver.sqls[1], endsWith('LIMIT @dox_limit$forUpdate'));
        expect(driver.sqls[2], endsWith('blog$q$forShare'));
        expect(driver.sqls[3], endsWith('blog$q$forShare'));
        await expectLater(
          FakeQuery(driver, 'blog').lockForUpdate().findOrFail(1),
          throwsA(isA<ModelNotFoundException>()),
        );
        expect(driver.sqls.last, endsWith(forUpdate));
      });

      test('${d.name}: a locked find does not use the find cache', () async {
        SqlOnlyDriver driver = SqlOnlyDriver(d);

        /// plain, locked, plain: the plain ones have no lock, the locked
        /// one has it, also when the plain sql is in the cache
        await FakeQuery(driver, 'cache_t').find(1);
        await FakeQuery(driver, 'cache_t').lockForUpdate().find(2);
        await FakeQuery(driver, 'cache_t').find(3);
        await FakeQuery(driver, 'cache_t2').lockForUpdate().find(1);
        await FakeQuery(driver, 'cache_t2').find(2);
        expect(driver.sqls[0], driver.sqls[2]);
        expect(
          driver.sqls[0],
          driver.sqls[4].replaceAll('cache_t2', 'cache_t'),
        );
        if (d != Driver.sqlite) {
          expect(driver.sqls[0], isNot(contains('FOR')));
          expect(driver.sqls[1], endsWith(forUpdate));
          expect(driver.sqls[3], endsWith(forUpdate));
        } else {
          expect(driver.sqls[1], driver.sqls[0]);
        }
      });
    }
  });

  group('Lock |', () {
    setUp(() async {
      await Schema().dropIfExists('lock_counter');
      await Schema().create('lock_counter', (Table table) {
        table.id();
        table.integer('value');
      });
      await QueryBuilder.table('lock_counter')
          .insert(<String, dynamic>{'value': 0});
      await Schema().dropIfExists('setting');
      await Schema().create('setting', (Table table) {
        table.id();
        table.string('name');
      });
      await Setting().create(<String, dynamic>{'name': 'x'});
      await Schema().dropIfExists('scoped_post');
      await Schema().create('scoped_post', (Table table) {
        table.id();
        table.string('title');
        table.boolean('published');
        table.boolean('archived').nullable();
        table.integer('views');
      });
      await ScopedPost().create(<String, dynamic>{
        'title': 'a',
        'published': true,
        'archived': false,
        'views': 0,
      });
    });

    tearDown(() async {
      await Schema().dropIfExists('lock_counter');
      await Schema().dropIfExists('setting');
      await Schema().dropIfExists('scoped_post');
    });

    /// wait until [log] has [entry], so the first transaction holds its
    /// lock before the second one starts
    Future<void> waitFor(List<String> log, String entry) async {
      for (int i = 0; i < 500 && !log.contains(entry); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(log, contains(entry));
    }

    Future<int> counter() async {
      dynamic value = await QueryBuilder.table('lock_counter')
          .where('id', 1)
          .valueOf('value');
      return int.parse(value.toString());
    }

    /// read the counter with a lock, wait [hold], then write it + 1
    Future<void> bump(
      String name,
      List<String> log, {
      Duration hold = Duration.zero,
    }) {
      return QueryBuilder.transaction(() async {
        Map<String, dynamic>? row = await QueryBuilder.table('lock_counter')
            .where('id', 1)
            .lockForUpdate()
            .getFirst();
        log.add('$name read ${row!['value']}');
        await Future<void>.delayed(hold);
        await QueryBuilder.table('lock_counter').where('id', 1).update(
          <String, dynamic>{'value': int.parse(row['value'].toString()) + 1},
        );
        log.add('$name write');
      });
    }

    test('the second lockForUpdate waits for the first commit', () async {
      List<String> log = <String>[];
      Future<void> first = bump(
        'a',
        log,
        hold: const Duration(milliseconds: 300),
      );
      await waitFor(log, 'a read 0');
      Future<void> second = bump('b', log);
      await Future.wait(<Future<void>>[first, second]);

      /// b waited, so it read the value that a wrote
      expect(log, <String>['a read 0', 'a write', 'b read 1', 'b write']);
      expect(await counter(), 2);
    });

    test('ten parallel read-modify-writes give the right count', () async {
      List<String> log = <String>[];
      await Future.wait(<Future<void>>[
        for (int i = 0; i < 10; i++) bump('t$i', log),
      ]);
      expect(await counter(), 10);
      for (int i = 0; i < 10; i++) {
        expect(log.where((String e) => e.endsWith('read $i')).length, 1);
      }
    });

    test('a lock ends when the transaction rolls back', () async {
      List<String> log = <String>[];
      Future<void> failing = QueryBuilder.transaction(() async {
        await QueryBuilder.table('lock_counter')
            .where('id', 1)
            .lockForUpdate()
            .getFirst();
        log.add('a locked');
        await Future<void>.delayed(const Duration(milliseconds: 200));
        log.add('a throws');
        throw StateError('stop');
      });
      await waitFor(log, 'a locked');
      Future<void> second = bump('b', log);
      await expectLater(failing, throwsStateError);
      await second;
      expect(log, <String>['a locked', 'a throws', 'b read 0', 'b write']);
      expect(await counter(), 1);
    });

    test('find() with a lock on a model, with the find cache', () async {
      /// fill the plain find cache first
      expect((await Setting().find(1))?.name, 'x');
      List<String> log = <String>[];
      Future<void> append(String name, Duration hold) {
        return QueryBuilder.transaction(() async {
          Setting setting = await Setting().lockForUpdate().findOrFail(1);
          log.add('$name read ${setting.name}');
          await Future<void>.delayed(hold);
          setting.name = '${setting.name}$name';
          await setting.save();
        });
      }

      Future<void> first = append('a', const Duration(milliseconds: 300));
      await waitFor(log, 'a read x');
      await Future.wait(<Future<void>>[first, append('b', Duration.zero)]);
      expect(log, <String>['a read x', 'b read xa']);
      expect((await Setting().find(1))?.name, 'xab');
    });

    test('find() with a lock and a global scope', () async {
      Future<void> view(Duration hold) {
        return QueryBuilder.transaction(() async {
          ScopedPost? post = await ScopedPost().lockForUpdate().find(1);
          await Future<void>.delayed(hold);
          await ScopedPost().where('id', 1).update(<String, dynamic>{
            'views': post!.views! + 1,
          });
        });
      }

      await Future.wait(<Future<void>>[
        view(const Duration(milliseconds: 100)),
        view(Duration.zero),
        view(Duration.zero),
      ]);
      expect((await ScopedPost().find(1))?.views, 3);
    });

    test('sharedLock: an update waits, a shared read does not', () async {
      List<String> log = <String>[];
      Future<void> reader = QueryBuilder.transaction(() async {
        await QueryBuilder.table('lock_counter')
            .where('id', 1)
            .sharedLock()
            .getFirst();
        log.add('a locked');
        await Future<void>.delayed(const Duration(milliseconds: 300));
        log.add('a done');
      });
      await waitFor(log, 'a locked');

      /// a second shared lock does not wait (sqlite runs one transaction
      /// at a time, so it waits there). it ends before the writer starts:
      /// mysql puts a new shared lock in the queue after a waiting writer.
      await QueryBuilder.transaction(() async {
        await QueryBuilder.table('lock_counter')
            .where('id', 1)
            .sharedLock()
            .getFirst();
        log.add('b shared read');
      });
      Future<void> writer = QueryBuilder.transaction(() async {
        await QueryBuilder.table('lock_counter')
            .where('id', 1)
            .update(<String, dynamic>{'value': 5});
        log.add('c write');
      });
      await Future.wait(<Future<void>>[reader, writer]);
      expect(log.indexOf('c write'), greaterThan(log.indexOf('a done')));
      if (current != Driver.sqlite) {
        expect(log.indexOf('b shared read'), lessThan(log.indexOf('a done')));
      }
      expect(await counter(), 5);
    });

    test('a lock outside a transaction ends at once', () async {
      await QueryBuilder.table('lock_counter')
          .where('id', 1)
          .lockForUpdate()
          .getFirst();

      /// no transaction holds the row, so this does not wait
      await QueryBuilder.transaction(() async {
        await QueryBuilder.table('lock_counter')
            .where('id', 1)
            .lockForUpdate()
            .getFirst();
      }).timeout(const Duration(seconds: 5));
    });
  });
}
