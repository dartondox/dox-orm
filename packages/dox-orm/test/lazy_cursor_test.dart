import 'package:dox_orm/dox_orm.dart';
import 'package:test/test.dart';

import 'connection.dart';
import 'models/blog/blog.model.dart';
import 'models/cast_item/cast_item.model.dart';

/// lazy(), lazyById() and cursor() on every driver of the CI job
void main() async {
  await initQueryBuilder();
  Driver driver = SqlQueryBuilder().dbDriver.getName();
  bool native = driver != Driver.sqlite;
  const int total = 50000;

  QueryBuilder<Map<String, dynamic>> big() => QueryBuilder.table('lazy_big');

  setUpAll(() async {
    await Schema().dropIfExists('lazy_big');
    await Schema().create('lazy_big', (Table table) {
      table.id();
      table.integer('n');
      table.string('half');
    });
    for (int start = 0; start < total; start += 1000) {
      await big().insertMultiple(<Map<String, dynamic>>[
        for (int i = start; i < start + 1000; i++)
          <String, dynamic>{'n': i, 'half': i < total / 2 ? 'low' : 'high'},
      ]);
    }
  });

  tearDownAll(() async {
    await Schema().dropIfExists('lazy_big');
  });

  group('big result |', () {
    test('the driver gives the rows in chunks', () async {
      int chunks = 0;
      int rows = 0;
      await for (List<Map<String, dynamic>> chunk
          in SqlQueryBuilder().dbDriver.stream('SELECT * FROM lazy_big')) {
        expect(chunk.length, lessThanOrEqualTo(1000));
        chunks++;
        rows += chunk.length;
      }
      expect(rows, total);
      expect(chunks, total ~/ 1000);
    });

    test('cursor() reads every row', () async {
      int rows = 0;
      int sum = 0;
      await for (Map<String, dynamic> row in big().cursor(chunkSize: 700)) {
        rows++;
        sum += row['n'] as int;
      }
      expect(rows, total);
      expect(sum, total * (total - 1) ~/ 2);
    });

    test('query listeners see a cursor() once', () async {
      List<QueryEvent> events = <QueryEvent>[];
      SqlQueryBuilder().listen(events.add);
      addTearDown(() => SqlQueryBuilder().removeListener(events.add));

      int rows = await big().where('n', '<', 50).cursor(chunkSize: 10).length;
      expect(rows, 50);
      expect(events.length, 1);
      expect(events.single.sql, contains('lazy_big'));
      expect(events.single.bindings.values, contains(50));

      // an empty result is seen too
      expect(await big().where('n', -1).cursor().length, 0);
      expect(events.length, 2);
    });

    test('lazy() reads every row in chunks by id', () async {
      int queries = 0;
      void count(QueryEvent e) => queries++;
      SqlQueryBuilder().listen(count);
      addTearDown(() => SqlQueryBuilder().removeListener(count));

      int rows = 0;
      int last = -1;
      await for (Map<String, dynamic> row in big().lazy(chunkSize: 5000)) {
        expect(row['id'] as int, greaterThan(last));
        last = row['id'] as int;
        rows++;
      }
      expect(rows, total);
      // 10 full chunks, then one empty
      expect(queries, 11);
    });
  });

  group('early stop |', () {
    test('cursor().take(3) stops the query', () async {
      List<Map<String, dynamic>> rows = await big()
          .orderBy('id')
          .cursor(chunkSize: 100)
          .take(3)
          .toList();
      expect(rows.map((Map<String, dynamic> r) => r['n']), <int>[0, 1, 2]);

      /// the connection is free again: a query and a transaction work
      expect(await big().where('n', 5).count(), 1);
      await QueryBuilder.transaction(() async {
        expect(await big().where('n', 6).count(), 1);
      });
    });

    test('break in await for stops the cursor', () async {
      int seen = 0;
      await for (Map<String, dynamic> _ in big().cursor(chunkSize: 10)) {
        if (++seen == 25) break;
      }
      expect(seen, 25);
      expect(await big().count(), total);
    });

    test('lazy().take(3) runs one query', () async {
      int queries = 0;
      void count(QueryEvent e) => queries++;
      SqlQueryBuilder().listen(count);
      addTearDown(() => SqlQueryBuilder().removeListener(count));

      List<Map<String, dynamic>> rows = await big()
          .lazy(chunkSize: 10)
          .take(3)
          .toList();
      expect(rows.map((Map<String, dynamic> r) => r['n']), <int>[0, 1, 2]);
      expect(queries, 1);
    });
  });

  group('where and order |', () {
    test('cursor() keeps where and order', () async {
      List<Map<String, dynamic>> rows = await big()
          .where('half', 'high')
          .where('n', '<', total ~/ 2 + 10)
          .orderBy('n', 'desc')
          .cursor(chunkSize: 3)
          .toList();
      expect(rows.map((Map<String, dynamic> r) => r['n']), <int>[
        for (int i = total ~/ 2 + 9; i >= total ~/ 2; i--) i,
      ]);
    });

    test('lazy() with orderBy keeps the order', () async {
      List<Map<String, dynamic>> rows = await big()
          .where('n', '<', 10)
          .orderBy('n', 'desc')
          .lazy(chunkSize: 3)
          .toList();
      expect(rows.map((Map<String, dynamic> r) => r['n']), <int>[
        for (int i = 9; i >= 0; i--) i,
      ]);
    });

    test('lazy() keeps an OR where', () async {
      List<Map<String, dynamic>> rows = await big()
          .where('n', 1)
          .orWhere('n', 40000)
          .lazy(chunkSize: 1)
          .toList();
      expect(rows.map((Map<String, dynamic> r) => r['n']), <int>[1, 40000]);
    });

    test('lazyById() by another column', () async {
      List<Map<String, dynamic>> rows = await big()
          .where('n', '>=', 100)
          .where('n', '<', 105)
          .lazyById(chunkSize: 2, column: 'n')
          .toList();
      expect(rows.map((Map<String, dynamic> r) => r['n']), <int>[
        100,
        101,
        102,
        103,
        104,
      ]);
    });

    test('lazyById() throws with an orderBy', () async {
      await expectLater(
        big().orderBy('n').lazyById().toList(),
        throwsStateError,
      );
    });
  });

  group('review fixes |', () {
    test(
      'lazy() and chunk() with an order on a column that is not unique',
      () async {
        // every row with n < 25 has half = 'low'. setPrimaryKey(): a
        // QueryBuilder.table() query adds the key only when it is known.
        List<Map<String, dynamic>> rows = await big()
            .setPrimaryKey('id')
            .where('n', '<', 25)
            .orderBy('half')
            .lazy(chunkSize: 7)
            .toList();
        expect(rows.length, 25);
        expect(
          rows.map((Map<String, dynamic> r) => r['id']).toSet().length,
          25,
        );

        Set<dynamic> ids = <dynamic>{};
        int count = 0;
        await big()
            .setPrimaryKey('id')
            .where('n', '<', 25)
            .orderBy('half')
            .chunk(7, (List<Map<String, dynamic>> page) {
              count += page.length;
              ids.addAll(page.map((Map<String, dynamic> r) => r['id']));
              return true;
            });
        expect(count, 25);
        expect(ids.length, 25);
      },
    );

    test('chunk() and lazy() with orderBy on a table with no id', () async {
      await Schema().dropIfExists('lazy_noid');
      await Schema().create('lazy_noid', (Table table) {
        table.integer('n');
      });
      addTearDown(() => Schema().dropIfExists('lazy_noid'));
      QueryBuilder<Map<String, dynamic>> noId() =>
          QueryBuilder.table('lazy_noid');
      // raw sql: insertMultiple() reads back an id column
      await SqlQueryBuilder().dbDriver.execute(
        'INSERT INTO lazy_noid (n) VALUES (0), (1), (2), (3), (4)',
      );
      List<dynamic> seen = <dynamic>[];
      await noId().orderBy('n', 'desc').chunk(2, (
        List<Map<String, dynamic>> rows,
      ) {
        seen.addAll(rows.map((Map<String, dynamic> r) => r['n']));
        return true;
      });
      expect(seen, <int>[4, 3, 2, 1, 0]);
      List<Map<String, dynamic>> rows = await noId()
          .orderBy('n')
          .lazy(chunkSize: 2)
          .toList();
      expect(rows.map((Map<String, dynamic> r) => r['n']), <int>[
        0,
        1,
        2,
        3,
        4,
      ]);
    });

    test('lazy(), lazyById() and cursor() keep limit() and offset()', () async {
      List<int> ns(List<Map<String, dynamic>> rows) =>
          rows.map((Map<String, dynamic> r) => r['n'] as int).toList();

      expect(
        ns(
          await big().where('n', '<', 100).limit(5).lazy(chunkSize: 2).toList(),
        ),
        <int>[0, 1, 2, 3, 4],
      );
      expect(
        ns(
          await big()
              .where('n', '<', 100)
              .orderBy('n', 'desc')
              .limit(5)
              .offset(3)
              .lazy(chunkSize: 2)
              .toList(),
        ),
        <int>[96, 95, 94, 93, 92],
      );
      expect(
        ns(
          await big().where('n', '<', 10).offset(7).lazy(chunkSize: 2).toList(),
        ),
        <int>[7, 8, 9],
      );
      expect(
        ns(
          await big()
              .where('n', '<', 100)
              .limit(5)
              .offset(2)
              .lazyById(chunkSize: 2)
              .toList(),
        ),
        <int>[2, 3, 4, 5, 6],
      );
      expect(
        ns(await big().orderBy('n').limit(5).cursor(chunkSize: 2).toList()),
        <int>[0, 1, 2, 3, 4],
      );
    });

    test('lazy() and cursor() with a join', () async {
      await Schema().dropIfExists('lazy_tag');
      await Schema().create('lazy_tag', (Table table) {
        table.id();
        table.integer('big_id');
        table.string('tag');
      });
      addTearDown(() => Schema().dropIfExists('lazy_tag'));
      await QueryBuilder.table('lazy_tag')
          .insertMultiple(<Map<String, dynamic>>[
            for (int i = 1; i <= 5; i++)
              <String, dynamic>{'big_id': i * 2, 'tag': 't$i'},
          ]);
      QueryBuilder<Map<String, dynamic>> joined() => big()
          .select(<String>['lazy_big.id', 'lazy_big.n', 'lazy_tag.tag'])
          .join('lazy_tag', 'lazy_tag.big_id', '=', 'lazy_big.id');
      List<Map<String, dynamic>> rows = await joined()
          .lazy(chunkSize: 2)
          .toList();
      expect(rows.map((Map<String, dynamic> r) => r['tag']), <String>[
        't1',
        't2',
        't3',
        't4',
        't5',
      ]);
      rows = await joined()
          .orderBy('lazy_big.id')
          .cursor(chunkSize: 2)
          .toList();
      expect(rows.length, 5);
    });

    test('delete rows while lazy() reads them', () async {
      await Schema().dropIfExists('lazy_del');
      await Schema().create('lazy_del', (Table table) {
        table.id();
        table.integer('n');
      });
      addTearDown(() => Schema().dropIfExists('lazy_del'));
      QueryBuilder<Map<String, dynamic>> del() =>
          QueryBuilder.table('lazy_del');
      await del().insertMultiple(<Map<String, dynamic>>[
        for (int i = 0; i < 30; i++) <String, dynamic>{'n': i},
      ]);
      int seen = 0;
      await for (Map<String, dynamic> row in del().lazy(chunkSize: 7)) {
        await del().where('id', row['id']).delete();
        seen++;
      }
      expect(seen, 30);
      expect(await del().count(), 0);
    });
  });

  group('empty result |', () {
    test('cursor(), lazy() and lazyById() give nothing', () async {
      expect(await big().where('n', -1).cursor().toList(), isEmpty);
      expect(await big().where('n', -1).lazy().toList(), isEmpty);
      expect(await big().where('n', -1).lazyById().toList(), isEmpty);
    });

    test('a chunk size below 1 throws', () async {
      await expectLater(
        big().cursor(chunkSize: 0).toList(),
        throwsArgumentError,
      );
      await expectLater(big().lazy(chunkSize: 0).toList(), throwsArgumentError);
    });
  });

  group('transaction |', () {
    test('cursor() and lazy() see the rows of the transaction', () async {
      await QueryBuilder.transaction(() async {
        await big().insert(<String, dynamic>{'n': -5, 'half': 'tx'});
        List<Map<String, dynamic>> rows = await big()
            .where('half', 'tx')
            .cursor()
            .toList();
        expect(rows.single['n'], -5);
        rows = await big().where('half', 'tx').lazy().toList();
        expect(rows.single['n'], -5);
        await big().where('half', 'tx').delete();
      });
      expect(await big().where('half', 'tx').count(), 0);
    });

    test('a cursor that stops early in a transaction', () async {
      await QueryBuilder.transaction(() async {
        List<Map<String, dynamic>> rows = await big()
            .cursor(chunkSize: 5)
            .take(2)
            .toList();
        expect(rows.length, 2);
        expect(await big().where('n', 7).count(), 1);
      });
    });
  });

  group('models |', () {
    setUp(() async {
      for (String t in <String>['cast_item', 'blog', 'blog_info']) {
        await Schema().dropIfExists(t);
      }
      await Schema().create('cast_item', (Table table) {
        table.id();
        table.text('meta').nullable();
        table.text('tags').nullable();
        table.boolean('active').nullable();
        table.boolean('done').withDefault(false);
        table.string('status').nullable();
        table.integer('level').nullable();
        table.integer('price').nullable();
      });
      await Schema().create('blog', (Table table) {
        table.id('uid');
        table.string('title');
        table.string('status').withDefault('active');
        table.text('body');
        table.string('slug').nullable();
        table.softDeletes();
        table.timestamps();
      });
      await Schema().create('blog_info', (Table table) {
        table.id();
        table.json('info');
        table.integer('blog_id');
        table.timestamps();
      });
    });

    tearDown(() async {
      for (String t in <String>['cast_item', 'blog', 'blog_info']) {
        await Schema().dropIfExists(t);
      }
    });

    test('cursor() and lazy() give models with casts', () async {
      for (int i = 0; i < 5; i++) {
        await (CastItem()
              ..meta = <String, dynamic>{'i': i}
              ..tags = <String>['t$i']
              ..active = i.isEven
              ..status = Status.live
              ..level = Level.high
              ..price = Money(i * 100))
            .save();
      }
      for (Stream<CastItem> s in <Stream<CastItem>>[
        CastItem().cursor(chunkSize: 2),
        CastItem().lazy(chunkSize: 2),
      ]) {
        List<CastItem> items = await s.toList();
        expect(items.length, 5);
        expect(items[3].meta, <String, dynamic>{'i': 3});
        expect(items[3].tags, <String>['t3']);
        expect(items[3].active, isFalse);
        expect(items[3].status, Status.live);
        expect(items[3].level, Level.high);
        expect(items[3].price?.cents, 300);
      }
    });

    test('relations load for each chunk', () async {
      for (int i = 0; i < 5; i++) {
        Blog blog = await Blog().create(<String, dynamic>{
          'title': 'b$i',
          'body': 'x',
        });
        await QueryBuilder.table('blog_info').insert(<String, dynamic>{
          'info': <String, dynamic>{'i': i},
          'blog_id': blog.uid,
        });
      }
      for (Stream<Blog> s in <Stream<Blog>>[
        Blog().cursor(chunkSize: 2),
        Blog().lazy(chunkSize: 2),
      ]) {
        List<Blog> blogs = await s.toList();
        expect(blogs.map((Blog b) => b.title), <String>[
          'b0',
          'b1',
          'b2',
          'b3',
          'b4',
        ]);
        expect(blogs.every((Blog b) => b.blogInfos.length == 1), isTrue);
      }
    });

    test('cursor() with relations in a transaction', () async {
      await Blog().create(<String, dynamic>{'title': 'a', 'body': 'x'});
      await QueryBuilder.transaction(() async {
        if (native) {
          await expectLater(Blog().cursor().toList(), throwsStateError);
        } else {
          expect((await Blog().cursor().toList()).single.title, 'a');
        }
        // lazy() works on every driver
        expect((await Blog().lazy().toList()).single.title, 'a');
      });
    });
  });
}
