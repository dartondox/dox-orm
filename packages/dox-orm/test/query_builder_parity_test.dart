import 'package:dox_orm/dox_orm.dart';
import 'package:test/test.dart';

import 'connection.dart';
import 'lock_test.dart' show FakeQuery, SqlOnlyDriver;

/// the sql of `get()` on [query], with the `@key` params as they are
Future<String> sqlOf(FakeQuery query) async {
  await query.get();
  return (query.driver as SqlOnlyDriver).sqls.last;
}

/// a select of `t` on [driver]
FakeQuery t(SqlOnlyDriver driver) => FakeQuery(driver, 't');

void main() async {
  await initQueryBuilder();

  group('Json path sql |', () {
    /// the read of `meta->a->b` and `meta->lang` on each driver
    const Map<Driver, (String, String)> paths = <Driver, (String, String)>{
      Driver.sqlite: (
        "json_extract(\"meta\", '\$.\"a\".\"b\"')",
        "json_extract(\"meta\", '\$.\"lang\"')",
      ),
      Driver.mysql: (
        "json_unquote(json_extract(`meta`, '\$.\"a\".\"b\"'))",
        "json_unquote(json_extract(`meta`, '\$.\"lang\"'))",
      ),
      Driver.postgres: (
        "CAST(\"meta\" AS jsonb)->'a'->>'b'",
        "CAST(\"meta\" AS jsonb)->>'lang'",
      ),
    };

    for (Driver d in Driver.values) {
      String ab = paths[d]!.$1;
      String lang = paths[d]!.$2;
      String q = d == Driver.mysql ? '`' : '"';

      test('${d.name}: select, where and orderBy', () async {
        SqlOnlyDriver driver = SqlOnlyDriver(d);
        String sql = await sqlOf(
          t(driver)
                  .select(<String>['id', 'meta->lang as lang'])
                  .where('meta->a->b', 'x')
                  .whereIn('meta->lang', <String>['en'])
                  .whereNull('meta->lang')
                  .orderBy('meta->lang', 'desc')
              as FakeQuery,
        );
        String inList = d == Driver.postgres
            ? '$lang = ANY(@metalang_p1)'
            : '$lang IN (@metalang_p1)';
        expect(
          sql,
          'SELECT ${q}id$q,$lang as ${q}lang$q FROM ${q}t$q '
          'WHERE $ab = @metaab_p0 AND $inList AND $lang IS NULL '
          'ORDER BY $lang desc',
        );
      });

      test('${d.name}: table.column and a join on a json path', () async {
        SqlOnlyDriver driver = SqlOnlyDriver(d);
        String sql = await sqlOf(
          t(driver).join('u', 'u.meta->lang', 't.lang') as FakeQuery,
        );
        expect(sql, contains('${q}u$q.${q}meta$q'));
        expect(sql, isNot(contains('->lang')));
      });

      test('${d.name}: a number or a bool in where()', () async {
        SqlOnlyDriver driver = SqlOnlyDriver(d);
        FakeQuery query = t(driver);
        String sql = await sqlOf(
          query.where('meta->lang', '>', 10).where('meta->lang', true)
              as FakeQuery,
        );
        Map<String, dynamic> values = query.substitutionValues;
        switch (d) {
          case Driver.postgres:
            String json = "CAST(\"meta\" AS jsonb)->'lang'";
            expect(
              sql,
              endsWith(
                'WHERE $json > CAST(@metalang_p0 AS jsonb) '
                'AND $json = CAST(@metalang_p1 AS jsonb)',
              ),
            );
            expect(values['metalang_p0'], '10');
            expect(values['metalang_p1'], 'true');
          case Driver.mysql:
            expect(sql, endsWith('@metalang_p0 AND $lang = @metalang_p1'));
            expect(values['metalang_p0'], 10);
            expect(values['metalang_p1'], 'true');
          case Driver.sqlite:
            expect(sql, endsWith('@metalang_p0 AND $lang = @metalang_p1'));
            expect(values['metalang_p0'], 10);
            expect(values['metalang_p1'], true);
        }
      });

      test('${d.name}: a bad json path throws', () {
        DBDriver driver = SqlOnlyDriver(d);
        for (String bad in <String>[
          "meta->a' OR 1=1",
          'meta->',
          'meta->a b',
          'count(*)->a',
          'meta->a as x y',
          'meta->a-b',
        ]) {
          expect(() => driver.wrap(bad), throwsArgumentError, reason: bad);
        }
      });
    }

    group('a json path can not be written |', () {
      SqlOnlyDriver driver = SqlOnlyDriver(Driver.sqlite);
      Matcher plainName = throwsA(
        isA<ArgumentError>().having(
          (ArgumentError e) => e.message,
          'message',
          'is not a plain column name',
        ),
      );
      Map<String, dynamic> data = <String, dynamic>{'meta->x': 1};

      test('insert', () {
        expect(() => t(driver).insert(data), plainName);
        expect(
          () => t(driver).insertOrIgnore(<Map<String, dynamic>>[data]),
          plainName,
        );
      });

      test('update', () {
        expect(() => t(driver).where('id', 1).update(data), plainName);
      });

      test('upsert', () {
        expect(
          () => t(driver).upsert(<Map<String, dynamic>>[data], <String>['id']),
          plainName,
        );
        expect(
          () => t(driver).upsert(
            <Map<String, dynamic>>[
              <String, dynamic>{'id': 1},
            ],
            <String>['id'],
            <String>['meta->x'],
          ),
          plainName,
        );
      });

      test('increment and decrement', () {
        expect(() => t(driver).where('id', 1).increment('meta->x'), plainName);
        expect(() => t(driver).where('id', 1).decrement('meta->x'), plainName);
      });
    });

    test('a plain name gives the same sql as before', () {
      DBDriver sqlite = SqlOnlyDriver(Driver.sqlite);
      DBDriver mysql = SqlOnlyDriver(Driver.mysql);
      expect(sqlite.wrap('blog.title as t'), '"blog"."title" as "t"');
      expect(mysql.wrap('blog.*'), '`blog`.*');
    });
  });

  group('Join with a callback sql |', () {
    for (Driver d in Driver.values) {
      String q = d == Driver.mysql ? '`' : '"';
      String w(String name) => '$q$name$q';

      test('${d.name}: on, orOn, where and orWhere', () async {
        SqlOnlyDriver driver = SqlOnlyDriver(d);
        String sql = await sqlOf(
          t(driver).where('id', 1).leftJoin('c', (JoinClause j) {
            j
                .on('c.t_id', 't.id')
                .orOn('c.owner_id', '>=', 't.id')
                .where('c.active', true)
                .orWhere('c.deleted_at', null)
                .where('c.views', '>', 5);
          }) as FakeQuery,
        );
        expect(
          sql,
          'SELECT * FROM ${w('t')} LEFT JOIN ${w('c')} on '
          '${w('c')}.${w('t_id')} = ${w('t')}.${w('id')} '
          'OR ${w('c')}.${w('owner_id')} >= ${w('t')}.${w('id')} '
          'AND ${w('c')}.${w('active')} = @cactive_p1 '
          'OR ${w('c')}.${w('deleted_at')} IS NULL '
          'AND ${w('c')}.${w('views')} > @cviews_p2 '
          'WHERE ${w('id')} = @id_p0',
        );
      });

      test('${d.name}: crossJoin', () async {
        SqlOnlyDriver driver = SqlOnlyDriver(d);
        expect(
          await sqlOf(t(driver).crossJoin('c') as FakeQuery),
          'SELECT * FROM ${w('t')} CROSS JOIN ${w('c')}',
        );
      });
    }

    test('the old join forms give the same sql', () async {
      SqlOnlyDriver driver = SqlOnlyDriver(Driver.sqlite);
      expect(
        await sqlOf(
          t(driver)
                  .join('c', 'c.t_id', 't.id')
                  .rightJoin('d', 'd.x', '>', 'c.x')
              as FakeQuery,
        ),
        'SELECT * FROM "t" JOIN "c" on "c"."t_id" = "t"."id" '
        'RIGHT JOIN "d" on "d"."x" > "c"."x"',
      );
    });

    test('a callback with no condition, or a missing column, throws', () {
      SqlOnlyDriver driver = SqlOnlyDriver(Driver.sqlite);
      expect(() => t(driver).join('c', (JoinClause j) {}), throwsArgumentError);
      expect(() => t(driver).join('c', 'c.id'), throwsArgumentError);
      expect(() => t(driver).join('c', 1, 'c.id'), throwsArgumentError);
      expect(
        () => t(driver).join('c', (JoinClause j) => j.on('c.id', ';', 't.id')),
        throwsArgumentError,
      );
    });
  });

  group('Query methods sql |', () {
    SqlOnlyDriver driver = SqlOnlyDriver(Driver.sqlite);

    test('orderByDesc and reorder', () async {
      expect(
        await sqlOf(t(driver).orderByDesc('id') as FakeQuery),
        'SELECT * FROM "t" ORDER BY "id" desc',
      );
      expect(
        await sqlOf(
          t(driver).orderBy('id').orderByRaw('1').reorder() as FakeQuery,
        ),
        'SELECT * FROM "t"',
      );
      expect(
        await sqlOf(t(driver).latest().reorder('name', 'asc') as FakeQuery),
        'SELECT * FROM "t" ORDER BY "name" asc',
      );
    });

    test('skip and forPage', () async {
      FakeQuery q = t(driver).skip(5).take(2) as FakeQuery;
      expect(await sqlOf(q), endsWith('LIMIT @dox_limit OFFSET @dox_offset'));
      expect(q.substitutionValues['dox_offset'], 5);

      q = t(driver).forPage(3, 10) as FakeQuery;
      await sqlOf(q);
      expect(q.substitutionValues['dox_limit'], 10);
      expect(q.substitutionValues['dox_offset'], 20);

      q = t(driver).forPage(0) as FakeQuery;
      expect(await sqlOf(q), endsWith('LIMIT @dox_limit'));
      expect(q.substitutionValues['dox_limit'], 15);
    });

    test('whereAny and whereAll', () async {
      expect(
        await sqlOf(
          t(driver)
                  .where('id', 1)
                  .whereAny(<String>['a', 'b'], 'like', '%x%')
                  .orWhereAll(<String>['c', 'd'], 2)
              as FakeQuery,
        ),
        'SELECT * FROM "t" WHERE "id" = @id_p0 '
        'AND ("a" like @a_p1 OR "b" like @b_p2) '
        'OR ("c" = @c_p3 AND "d" = @d_p4)',
      );
      expect(
        await sqlOf(
          t(driver).whereAll(<String>['a', 'b'], null).orWhereAny(<String>[], 1)
              as FakeQuery,
        ),
        'SELECT * FROM "t" WHERE ("a" IS NULL AND "b" IS NULL)',
      );
    });
  });

  group('Query builder parity |', () {
    QueryBuilder<Map<String, dynamic>> items() => QueryBuilder.table('pq_item');
    QueryBuilder<Map<String, dynamic>> users() => QueryBuilder.table('pq_user');

    /// sorted names of the rows
    Future<List<String>> names(QueryBuilder<Map<String, dynamic>> q) async {
      List<Map<String, dynamic>> rows = await q.get();
      return <String>[for (Map<String, dynamic> r in rows) r['name'] as String]
        ..sort();
    }

    setUp(() async {
      SqlQueryBuilder().flags = const OrmFlags();
      await Schema().dropIfExists('pq_contact');
      await Schema().dropIfExists('pq_item');
      await Schema().dropIfExists('pq_user');
      await Schema().create('pq_item', (Table table) {
        table.id();
        table.string('name');
        table.integer('views');
        table.json('meta').nullable();
      });
      await Schema().create('pq_user', (Table table) {
        table.id();
        table.string('name');
      });
      await Schema().create('pq_contact', (Table table) {
        table.id();
        table.integer('user_id');
        table.integer('owner_id');
        table.boolean('active');
      });
      await items().insertMultiple(<Map<String, dynamic>>[
        <String, dynamic>{
          'name': 'A',
          'views': 100,
          'meta': <String, dynamic>{
            'lang': 'en',
            'views': 100,
            'active': true,
            'a': <String, dynamic>{'b': 'x'},
          },
        },
        <String, dynamic>{
          'name': 'B',
          'views': 9,
          'meta': <String, dynamic>{
            'lang': 'de',
            'views': 9,
            'active': false,
            'a': <String, dynamic>{'b': 'y'},
          },
        },
        <String, dynamic>{'name': 'C', 'views': 50, 'meta': null},
      ]);
      await users().insertMultiple(<Map<String, dynamic>>[
        <String, dynamic>{'name': 'Ann'},
        <String, dynamic>{'name': 'Bob'},
        <String, dynamic>{'name': 'Cid'},
      ]);
      await QueryBuilder.table('pq_contact')
          .insertMultiple(<Map<String, dynamic>>[
            <String, dynamic>{'user_id': 1, 'owner_id': 9, 'active': true},
            <String, dynamic>{'user_id': 9, 'owner_id': 2, 'active': true},
            <String, dynamic>{'user_id': 9, 'owner_id': 3, 'active': false},
          ]);
    });

    tearDown(() => SqlQueryBuilder().flags = const OrmFlags());

    test('where on a json path', () async {
      expect(await names(items().where('meta->lang', 'en')), <String>['A']);
      expect(await names(items().where('meta->a->b', 'y')), <String>['B']);
      expect(await names(items().where('meta->views', '>', 10)), <String>['A']);
      expect(await names(items().where('meta->views', 9)), <String>['B']);
      expect(await names(items().where('meta->active', true)), <String>['A']);
      expect(await names(items().where('meta->active', false)), <String>['B']);
      expect(
        await names(items().whereIn('meta->lang', <String>['en', 'de'])),
        <String>['A', 'B'],
      );
      expect(await names(items().whereNull('meta->lang')), <String>['C']);
      expect(await names(items().whereNotNull('meta->lang')), <String>[
        'A',
        'B',
      ]);
      expect(await names(items().whereLike('meta->lang', 'e%')), <String>['A']);
    });

    test('select and orderBy on a json path', () async {
      List<Map<String, dynamic>> rows = await items()
          .select(<String>['name', 'meta->a->b as b'])
          .whereNotNull('meta')
          .orderBy('meta->lang', 'desc')
          .get();
      expect(rows.map((Map<String, dynamic> r) => r['b']).toList(), <String>[
        'x',
        'y',
      ]);
    });

    test('join with a callback keeps the values in order', () async {
      List<Map<String, dynamic>> rows = await users()
          .select('pq_user.name')
          .where('pq_user.name', '!=', 'Zed')
          .join('pq_contact', (JoinClause j) {
            j
                .on('pq_contact.user_id', 'pq_user.id')
                .orOn('pq_contact.owner_id', 'pq_user.id')
                .where('pq_contact.active', true);
          })
          .where('pq_user.id', '<', 10)
          .orderBy('pq_user.name')
          .get();
      expect(rows.map((Map<String, dynamic> r) => r['name']).toList(), <String>[
        'Ann',
        'Bob',
      ]);
      expect(
        await users().leftJoin('pq_contact', (JoinClause j) {
          j
              .on('pq_contact.user_id', 'pq_user.id')
              .where('pq_contact.active', true);
        }).count(),
        3,
      );
    });

    test('crossJoin', () async {
      expect(await users().crossJoin('pq_contact').count(), 9);
    });

    test('orderByDesc, reorder, skip and forPage', () async {
      expect((await items().orderByDesc('views').first())!['name'], 'A');
      expect(
        (await items().orderByDesc('views').reorder('name').first())!['name'],
        'A',
      );
      expect(
        (await items().orderBy('name').skip(1).take(1).first())!['name'],
        'B',
      );
      List<Map<String, dynamic>> page = await items()
          .orderBy('name')
          .forPage(2, 2)
          .get();
      expect(page.map((Map<String, dynamic> r) => r['name']).toList(), <String>[
        'C',
      ]);
    });

    test('sole', () async {
      expect((await items().where('name', 'B').sole())['views'], 9);
      expect(
        () => items().where('name', 'Z').sole(),
        throwsA(isA<ModelNotFoundException>()),
      );
      expect(
        () => items().where('views', '>', 10).sole(),
        throwsA(
          isA<MultipleRecordsFoundException>().having(
            (MultipleRecordsFoundException e) => e.table,
            'table',
            'pq_item',
          ),
        ),
      );
    });

    test('updateOrInsert', () async {
      expect(
        await items().updateOrInsert(
          <String, dynamic>{'name': 'D'},
          <String, dynamic>{'views': 1},
        ),
        isTrue,
      );
      expect((await items().where('name', 'D').sole())['views'], 1);
      expect(
        await items().updateOrInsert(
          <String, dynamic>{'name': 'D'},
          <String, dynamic>{'views': 2},
        ),
        isTrue,
      );
      expect((await items().where('name', 'D').sole())['views'], 2);
      expect(await items().count(), 4);
      expect(
        await items().updateOrInsert(<String, dynamic>{'name': 'D'}),
        isTrue,
      );
      expect(await items().count(), 4);
      expect(
        () => items().updateOrInsert(<String, dynamic>{}),
        throwsArgumentError,
      );
    });

    test('whereAny and whereAll', () async {
      expect(
        await names(items().whereAny(<String>['name', 'meta->lang'], 'de')),
        <String>['B'],
      );
      expect(
        await names(
          items().whereAll(<String>['views', 'meta->views'], '>', 10),
        ),
        <String>['A'],
      );
      expect(
        await names(
          items().where('name', 'C').orWhereAny(<String>[
            'name',
            'meta->lang',
          ], 'en'),
        ),
        <String>['A', 'C'],
      );
    });

    for (bool adds in <bool>[false, true]) {
      test('selectRaw with values, selectRawAdds: $adds', () async {
        SqlQueryBuilder().flags = OrmFlags(selectRawAdds: adds);
        QueryBuilder<Map<String, dynamic>> q() => items()
            .select('name')
            .selectRaw('views * @rate as score', <String, dynamic>{'rate': 2})
            .where('views', '>', 10)
            .orderBy('views');
        List<Map<String, dynamic>> rows = await q().get();
        expect(rows.map((Map<String, dynamic> r) => r['score']).toList(), <int>[
          100,
          200,
        ]);
        expect(rows.first.containsKey('name'), adds);

        /// count() and hasRows() do not use the select, so they do not
        /// send its values (Postgres would refuse them)
        expect(await q().count(), 2);
        expect(await q().hasRows(), isTrue);
        QueryBuilder<Map<String, dynamic>> both = q();
        await both.get();
        expect(await both.count(), 2);
        Pagination<Map<String, dynamic>> page = await q().paginate(
          currentPage: 1,
          perPage: 1,
        );
        expect(page.total, 2);
      });
    }

    test('a selectRaw value name that the query uses already throws', () {
      for (int other in <int>[9, 2]) {
        expect(
          () => items()
              .selectRaw('views * @r as s', <String, dynamic>{'r': 2})
              .whereRaw('views > @r', <String, dynamic>{'r': other})
              .get(),
          throwsArgumentError,
        );
      }
    });

    test('two selectRaw calls with one value name', () async {
      SqlQueryBuilder().flags = const OrmFlags(selectRawAdds: true);
      for (int other in <int>[3, 2]) {
        expect(
          () => items()
              .select('name')
              .selectRaw('views * @r as a', <String, dynamic>{'r': 2})
              .selectRaw('views * @r as b', <String, dynamic>{'r': other}),
          throwsArgumentError,
        );
      }

      /// with the flag off the second call replaces the first
      SqlQueryBuilder().flags = const OrmFlags();
      List<Map<String, dynamic>> rows = await items()
          .selectRaw('views * @r as a', <String, dynamic>{'r': 2})
          .selectRaw('views * @r as b', <String, dynamic>{'r': 3})
          .where('name', 'A')
          .get();
      expect(rows.single, <String, dynamic>{'b': 300});
    });

    test('a selectRaw value name that starts with dox_ throws', () {
      for (String name in <String>['dox_limit', 'dox_offset', 'dox_x']) {
        expect(
          () => items().selectRaw('@$name as a', <String, dynamic>{name: 1}),
          throwsArgumentError,
          reason: name,
        );
      }
    });

    test('selectRaw without values replaces the old values', () async {
      List<Map<String, dynamic>> rows = await items()
          .selectRaw('views * @rate as score', <String, dynamic>{'rate': 2})
          .selectRaw('name')
          .where('name', 'A')
          .get();
      expect(rows.single['name'], 'A');
    });
  });
}
