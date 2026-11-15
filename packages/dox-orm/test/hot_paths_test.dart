import 'package:dox_orm/dox_orm.dart';
import 'package:dox_orm/src/drivers/sqlite_driver.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

import 'connection.dart';
import 'models/blog/blog.model.dart';

void main() async {
  await initQueryBuilder();

  QueryBuilder<Map<String, dynamic>> people() => QueryBuilder.table('hp_user');

  /// sorted names of the rows
  Future<List<String>> names(QueryBuilder<Map<String, dynamic>> query) async {
    List<Map<String, dynamic>> rows = await query.get();
    return <String>[for (Map<String, dynamic> r in rows) r['name'] as String]
      ..sort();
  }

  List<String> sqls = <String>[];
  void onQuery(QueryEvent e) => sqls.add(e.sql);

  setUp(() async {
    await Schema().dropIfExists('hp_user');
    await Schema().dropIfExists('blog');
    await Schema().dropIfExists('blog_info');
    await Schema().create('blog_info', (Table table) {
      table.id();
      table.json('info');
      table.integer('blog_id');
      table.timestamps();
    });
    await Schema().create('hp_user', (Table table) {
      table.id();
      table.string('name');
      table.string('email').nullable();
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
    await people().insertMultiple(<Map<String, dynamic>>[
      <String, dynamic>{'name': 'a', 'email': 'a@x'},
      <String, dynamic>{'name': 'b', 'email': null},
      <String, dynamic>{'name': 'c', 'email': 'c@x'},
      <String, dynamic>{'name': 'd', 'email': 'd@x'},
      <String, dynamic>{'name': 'e', 'email': null},
    ]);
    sqls.clear();
    SqlQueryBuilder().listen(onQuery);
  });

  tearDown(() async {
    SqlQueryBuilder().removeListener(onQuery);
    await Schema().dropIfExists('hp_user');
    await Schema().dropIfExists('blog');
    await Schema().dropIfExists('blog_info');
  });

  group('whereIn padding |', () {
    test('same rows for each list size', () async {
      List<String> all = <String>['a', 'b', 'c', 'd', 'e'];
      for (int n = 1; n <= 5; n++) {
        List<String> want = all.sublist(0, n);
        expect(await names(people().whereIn('name', want)), want);
        expect(await names(people().whereNotIn('name', want)), all.sublist(n));
      }
    });

    test('duplicates, nulls and mixed types', () async {
      expect(
        await names(people().whereIn('name', <String>['a', 'a', 'c'])),
        <String>['a', 'c'],
      );

      /// a null never matches IN, and NOT IN with a null matches nothing
      expect(
        await names(people().whereIn('email', <String?>['a@x', null, 'c@x'])),
        <String>['a', 'c'],
      );
      expect(
        await names(people().whereNotIn('email', <String?>['a@x', null])),
        <String>[],
      );
      expect(await names(people().whereIn('id', <Object>[1, '2', 3])), <String>[
        'a',
        'b',
        'c',
      ]);
      expect(
        await names(people().orWhereIn('name', <String>['d', 'e', 'a'])),
        <String>['a', 'd', 'e'],
      );
    });

    test('empty list', () async {
      expect(await names(people().whereIn('name', <String>[])), <String>[]);
      expect((await names(people().whereNotIn('name', <String>[]))).length, 5);
    });

    test('toSql, toRawSql and query events show the list as it is', () async {
      QueryBuilder<Map<String, dynamic>> q = people().whereIn('id', <Object>[
        1,
        '2',
        3,
      ]);
      expect(q.toSql(), contains('IN (1,2,3)'));
      expect(q.toRawSql(), contains("IN (1,'2',3)"));
      expect(q.substitutionValues.length, 3);
      await q.get();
      expect(sqls.single, isNot(contains('1,2,3,')));
      expect(RegExp('@').allMatches(sqls.single).length, 3);
    });

    test('rows inside OR groups and subqueries', () async {
      expect(
        await names(
          people().where('name', 'e').orWhereGroup((
            QueryBuilder<Map<String, dynamic>> q,
          ) {
            q.whereIn('name', <String>['a', 'b', 'c']);
          }),
        ),
        <String>['a', 'b', 'c', 'e'],
      );
      expect(
        await names(
          people().whereIn(
            'id',
            people().select('id').whereIn('name', <String>['b', 'c', 'd']),
          ),
        ),
        <String>['b', 'c', 'd'],
      );
    });

    test('the driver gets a padded list, a long one stays as it is', () {
      Object? same(dynamic v) => v;
      var (String sql, List<Object?> params) = toPositionalParams(
        'SELECT 1 WHERE a IN (@a,@b,@c) AND b NOT IN (@d,@e,@f,@g,@h)',
        <String, dynamic>{
          'a': 1,
          'b': 2,
          'c': 3,
          'd': 4,
          'e': 5,
          'f': 6,
          'g': 7,
          'h': 8,
        },
        same,
      );
      expect(
        sql,
        'SELECT 1 WHERE a IN (?,?,?,?) AND b NOT IN (?,?,?,?,?,?,?,?)',
      );
      expect(params, <Object?>[1, 2, 3, 3, 4, 5, 6, 7, 8, 8, 8, 8]);

      /// 2 values, a power of two, a spaced list and a quoted text
      var (String plain, _) = toPositionalParams(
        "SELECT 'IN (@a,@b,@c)' WHERE a IN (@a,@b) AND b IN (@a, @b, @c)",
        <String, dynamic>{'a': 1, 'b': 2, 'c': 3},
        same,
      );
      expect(
        plain,
        "SELECT 'IN (@a,@b,@c)' WHERE a IN (?,?) AND b IN (?, ?, ?)",
      );

      Map<String, dynamic> many = <String, dynamic>{
        for (int i = 0; i < 1025; i++) 'k$i': i,
      };
      var (String long, List<Object?> longParams) = toPositionalParams(
        'x IN (${many.keys.map((String k) => '@$k').join(',')})',
        many,
        same,
      );
      expect(longParams.length, 1025);
      expect(RegExp(r'\?').allMatches(long).length, 1025);
    });

    test('sqlite: list sizes 3 and 4 share one prepared statement', () async {
      sqlite.Database db = sqlite.sqlite3.openInMemory();
      SqliteDriver driver = SqliteDriver(conn: db);
      await driver.execute('CREATE TABLE t (id int)');
      for (List<int> ids in <List<int>>[
        <int>[1, 2, 3],
        <int>[1, 2, 3, 4],
        <int>[4, 5, 6],
      ]) {
        String list = <String>[for (int i = 0; i < ids.length; i++) '@p$i']
            .join(',');
        await driver.query(
          'SELECT * FROM t WHERE id IN ($list)',
          substitutionValues: <String, dynamic>{
            for (int i = 0; i < ids.length; i++) 'p$i': ids[i],
          },
        );
      }
      StatementCache<sqlite.PreparedStatement> c = driver.statementCacheOf(db)!;
      expect(c.misses, 1);
      expect(c.hits, 2);
      driver.clearStatementCache();
      db.close();
    });

    test('a long list gives one param for each value', () async {
      List<Object> ids = <Object>[for (int i = 0; i < 1025; i++) i, 'x'];
      QueryBuilder<Map<String, dynamic>> q = people().whereIn('id', ids);
      expect(q.substitutionValues.length, 1026);
    });
  });

  group('save() dirty check with dates |', () {
    test('the same moment is not a change, another one is', () async {
      Blog blog = await Blog().create(<String, dynamic>{
        'title': 't',
        'body': 'b',
      });
      DateTime time = DateTime.utc(2026, 1, 2, 3, 4, 5);
      blog.deletedAt = time;
      await blog.saveQuietly();

      /// a new DateTime of the same moment and zone: no query
      blog.deletedAt = DateTime.fromMicrosecondsSinceEpoch(
        time.microsecondsSinceEpoch,
        isUtc: true,
      );
      sqls.clear();
      await blog.save();
      expect(sqls, isEmpty);

      blog.deletedAt = time.add(Duration(seconds: 1));
      await blog.save();
      expect(sqls.where((String s) => s.startsWith('UPDATE')).length, 1);
      expect(blog.getChanges().containsKey('deleted_at'), isTrue);
    });
  });

  group('where().first() |', () {
    test('right row for each value, also after the builder changed', () async {
      Map<String, dynamic>? row = await people().where('name', 'b').first();
      expect(row?['name'], 'b');
      row = await people().where('name', 'c').first();
      expect(row?['name'], 'c');

      /// a builder used again, then changed after first()
      QueryBuilder<Map<String, dynamic>> q = people().where('name', 'a');
      expect((await q.first())?['name'], 'a');
      expect((await q.first())?['name'], 'a');
      q.where('email', 'zzz');
      expect(await q.first(), isNull);

      /// more parts than one where
      expect(
        (await people()
            .where('email', null)
            .orderBy('name', 'desc')
            .first())?['name'],
        'e',
      );
      expect(
        (await people()
            .where('name', 'a')
            .orWhere('name', 'd')
            .orderBy('name', 'desc')
            .first())?['name'],
        'd',
      );
      expect(
        (await people()
            .where('name', '!=', 'a')
            .orderBy('name')
            .first())?['name'],
        'b',
      );
    });

    test('find() on a json path with a number, two times', () async {
      await Schema().dropIfExists('hp_json');
      await Schema().create('hp_json', (Table table) {
        table.id();
        table.json('meta');
      });
      QueryBuilder<Map<String, dynamic>> items() =>
          QueryBuilder.table('hp_json');
      await items().insert(<String, dynamic>{
        'meta': <String, dynamic>{'n': 10},
      });
      expect((await items().find('meta->n', 10))?['id'], 1);
      expect((await items().find('meta->n', 10))?['id'], 1);
      expect((await items().where('meta->n', 10).first())?['id'], 1);
      await Schema().dropIfExists('hp_json');
    });

    test('a wrapped where does not use the kept sql', () async {
      expect((await people().where('name', 'a').first())?['name'], 'a');
      Map<String, dynamic>? row = await people()
          .whereNot(
            (QueryBuilder<Map<String, dynamic>> q) => q.where('name', 'a'),
          )
          .orderBy('name')
          .first();
      expect(row?['name'], 'b');
      row = await people()
          .whereNot(
            (QueryBuilder<Map<String, dynamic>> q) => q.where('name', 'a'),
          )
          .first();
      expect(row?['name'], isNot('a'));
    });

    test('model: soft deletes, find() and first() share the sql', () async {
      Blog one = await Blog().create(<String, dynamic>{
        'title': 'x',
        'body': 'b',
      });
      Blog two = await Blog().create(<String, dynamic>{
        'title': 'y',
        'body': 'b',
      });
      expect((await Blog().where('title', 'y').first())?.uid, two.uid);
      expect((await Blog().find('title', 'x'))?.uid, one.uid);
      await one.delete();
      expect(await Blog().where('title', 'x').first(), isNull);
      expect(await Blog().find('title', 'x'), isNull);
      expect(
        (await Blog().withTrash().where('title', 'x').first())?.uid,
        one.uid,
      );
      expect((await Blog().where('uid', two.uid).first())?.uid, two.uid);
    });
  });
}
