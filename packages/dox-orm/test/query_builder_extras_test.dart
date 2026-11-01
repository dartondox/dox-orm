import 'package:dox_orm/dox_orm.dart';
import 'package:test/test.dart';

import 'connection.dart';

void main() async {
  await initQueryBuilder();

  QueryBuilder<Map<String, dynamic>> users() => QueryBuilder.table('qx_user');
  QueryBuilder<Map<String, dynamic>> posts() => QueryBuilder.table('qx_post');

  /// sorted names of the rows
  Future<List<String>> names(QueryBuilder<Map<String, dynamic>> query) async {
    List<Map<String, dynamic>> rows = await query.get();
    return <String>[for (Map<String, dynamic> r in rows) r['name'] as String]
      ..sort();
  }

  group('Query builder extras |', () {
    setUp(() async {
      await Schema().dropIfExists('qx_post');
      await Schema().dropIfExists('qx_user');
      await Schema().create('qx_user', (Table table) {
        table.id();
        table.string('name').unique();
        table.integer('age');
        table.dateTime('joined_at');
        table.json('tags').nullable();
        table.json('options').nullable();
      });
      await Schema().create('qx_post', (Table table) {
        table.id();
        table.integer('user_id');
        table.string('title');
      });
      await users().insertMultiple(<Map<String, dynamic>>[
        <String, dynamic>{
          'name': 'Alice',
          'age': 20,
          'joined_at': DateTime.utc(2024, 5, 1, 9, 30),
          'tags': <String>['dart', 'php'],
          'options': <String, dynamic>{
            'languages': <String>['en', 'de'],
          },
        },
        <String, dynamic>{
          'name': 'Bob',
          'age': 30,
          'joined_at': DateTime.utc(2024, 5, 15, 18),
          'tags': <String>['go'],
          'options': <String, dynamic>{
            'languages': <String>['en'],
          },
        },
        <String, dynamic>{
          'name': 'Carol',
          'age': 40,
          'joined_at': DateTime.utc(2023, 12, 31, 23, 59, 59),
          'tags': <dynamic>['dart', 7, true],
          'options': <String, dynamic>{
            'languages': <String>['fr'],
          },
        },
      ]);
      await posts().insertMultiple(<Map<String, dynamic>>[
        <String, dynamic>{'user_id': 1, 'title': 'a'},
        <String, dynamic>{'user_id': 1, 'title': 'b'},
        <String, dynamic>{'user_id': 3, 'title': 'c'},
      ]);
    });

    tearDown(() async {
      await Schema().dropIfExists('qx_post');
      await Schema().dropIfExists('qx_user');
    });

    test('union drops same rows, unionAll keeps them', () async {
      QueryBuilder<Map<String, dynamic>> young() =>
          users().select('name').where('age', '<', 35);
      QueryBuilder<Map<String, dynamic>> old() =>
          users().select('name').where('age', '>', 25);
      expect(await names(young().union(old())), <String>[
        'Alice',
        'Bob',
        'Carol',
      ]);
      expect(await names(young().unionAll(old())), <String>[
        'Alice',
        'Bob',
        'Bob',
        'Carol',
      ]);
    });

    test('union: orderBy and limit are for the whole result', () async {
      List<Map<String, dynamic>> rows = await users()
          .select('name')
          .where('name', 'Carol')
          .unionAll(users().select('name').where('age', '<', 35))
          .orderBy('name')
          .limit(2)
          .get();
      expect(rows.map(_name).toList(), <String>['Alice', 'Bob']);
    });

    test('union part keeps its own orderBy and limit', () async {
      List<Map<String, dynamic>> rows = await users()
          .select('name')
          .where('name', 'Carol')
          .unionAll(users().select('name').orderBy('age', 'desc').limit(1))
          .get();
      expect(rows.map(_name).toList(), <String>['Carol', 'Carol']);
    });

    test('union: count and paginate count the whole result', () async {
      QueryBuilder<Map<String, dynamic>> q() => users()
          .select('name')
          .where('age', 20)
          .unionAll(users().select('name').where('age', '>=', 30));
      expect(await q().count(), 3);
      expect(await q().hasRows(), isTrue);
      Pagination<Map<String, dynamic>> page = await q()
          .orderBy('name')
          .paginate(currentPage: 2, perPage: 2);
      expect(page.total, 3);
      expect(page.data.map(_name).toList(), <String>['Carol']);
    });

    test('union: aggregates use the whole result, like Laravel', () async {
      QueryBuilder<Map<String, dynamic>> q() => users()
          .select(<String>['name', 'age'])
          .where('age', 20)
          .unionAll(
            users().select(<String>['name', 'age']).where('age', '>=', 30),
          )
          .unionAll(users().select(<String>['name', 'age']).where('age', 40));
      expect(await q().sum('age'), 130);
      expect(await q().avg('age'), 32.5);
      expect(await q().min('age'), 20);
      expect(await q().max('age'), 40);
      expect(await q().count(), 4);

      /// union drops the second Carol: Bob 30 + Carol 40
      QueryBuilder<Map<String, dynamic>> distinct = users()
          .select(<String>['name', 'age'])
          .where('age', '>=', 30)
          .union(users().select(<String>['name', 'age']).where('age', 40));
      expect(await distinct.sum('age'), 70);
      expect(
        await users()
            .select('age')
            .where('age', 99)
            .union(users().select('age').where('age', 98))
            .max('age'),
        isNull,
      );
    });

    test('union on three queries, values bound in each part', () async {
      List<String> got = await names(
        users()
            .select('name')
            .where('name', 'Alice')
            .union(users().select('name').where('name', 'Bob'))
            .union(users().select('name').where('name', 'Carol')),
      );
      expect(got, <String>['Alice', 'Bob', 'Carol']);
    });

    test('whereIn and whereNotIn with a sub query', () async {
      QueryBuilder<Map<String, dynamic>> authors() =>
          posts().select('user_id').where('title', '!=', 'b');
      expect(await names(users().whereIn('id', authors())), <String>[
        'Alice',
        'Carol',
      ]);
      expect(await names(users().whereNotIn('id', authors())), <String>['Bob']);
      expect(
        await names(
          users()
              .where('name', 'Bob')
              .orWhereIn('id', posts().select('user_id')),
        ),
        <String>['Alice', 'Bob', 'Carol'],
      );
      expect(() => users().whereIn('id', 'x'), throwsArgumentError);
    });

    test('joinSub and leftJoinSub', () async {
      QueryBuilder<Map<String, dynamic>> counts() => posts()
          .selectRaw('user_id, COUNT(*) as post_count')
          .where('title', '!=', 'z')
          .groupBy('user_id');
      List<Map<String, dynamic>> rows = await users()
          .select(<String>['qx_user.name', 'pc.post_count'])
          .where('age', '>', 10)
          .joinSub(counts(), 'pc', 'pc.user_id', 'qx_user.id')
          .orderBy('qx_user.name')
          .get();
      expect(rows.map(_name).toList(), <String>['Alice', 'Carol']);
      expect(rows.map(_count).toList(), <int>[2, 1]);

      List<Map<String, dynamic>> all = await users()
          .select(<String>['qx_user.name', 'pc.post_count'])
          .leftJoinSub(counts(), 'pc', 'pc.user_id', '=', 'qx_user.id')
          .orderBy('qx_user.name')
          .get();
      expect(all.map(_name).toList(), <String>['Alice', 'Bob', 'Carol']);
      expect(all[1]['post_count'], isNull);
    });

    test('fromSub', () async {
      QueryBuilder<Map<String, dynamic>> counts = posts()
          .selectRaw('user_id, COUNT(*) as post_count')
          .where('title', '!=', 'z')
          .groupBy('user_id');
      QueryBuilder<Map<String, dynamic>> q() =>
          QueryBuilder.table('pc')
              .fromSub(counts, 'pc')
              .where('pc.post_count', '>', 1);
      List<Map<String, dynamic>> rows = await q().get();
      expect(rows.length, 1);
      expect(int.parse('${rows.first['user_id']}'), 1);
      expect(await q().count(), 1);
    });

    test('a sub query in a sub query keeps its values', () async {
      QueryBuilder<Map<String, dynamic>> inner = posts()
          .select('user_id')
          .where('title', 'a');
      QueryBuilder<Map<String, dynamic>> middle = users()
          .select('id')
          .whereIn('id', inner)
          .where('age', 20);
      expect(await names(users().whereIn('id', middle)), <String>['Alice']);
    });

    test('whereDate', () async {
      expect(
        await names(users().whereDate('joined_at', '2024-05-01')),
        <String>['Alice'],
      );
      expect(
        await names(
          users().whereDate('joined_at', '>=', DateTime.utc(2024, 5, 2)),
        ),
        <String>['Bob'],
      );
      expect(
        await names(
          users()
              .whereDate('joined_at', '2023-12-31')
              .orWhereDate('joined_at', '2024-05-15'),
        ),
        <String>['Bob', 'Carol'],
      );
      expect(() => users().whereDate('joined_at', null), throwsArgumentError);
      expect(
        () => users().whereDate('joined_at', 'or 1=1', '2024-01-01'),
        throwsArgumentError,
      );
    });

    test('whereTime', () async {
      expect(await names(users().whereTime('joined_at', '09:30:00')), <String>[
        'Alice',
      ]);
      expect(
        await names(users().whereTime('joined_at', '>', '12:00')),
        <String>['Bob', 'Carol'],
      );
    });

    test('whereYear, whereMonth and whereDay', () async {
      expect(await names(users().whereYear('joined_at', 2024)), <String>[
        'Alice',
        'Bob',
      ]);
      expect(await names(users().whereYear('joined_at', '<', '2024')), <String>[
        'Carol',
      ]);
      expect(await names(users().whereMonth('joined_at', 12)), <String>[
        'Carol',
      ]);
      expect(await names(users().whereMonth('joined_at', '05')), <String>[
        'Alice',
        'Bob',
      ]);
      expect(await names(users().whereDay('joined_at', 15)), <String>['Bob']);
      expect(
        await names(
          users()
              .whereDay('joined_at', DateTime.utc(2000))
              .orWhereYear('joined_at', 2023),
        ),
        <String>['Alice', 'Carol'],
      );
    });

    test('whereJsonContains', () async {
      expect(await names(users().whereJsonContains('tags', 'dart')), <String>[
        'Alice',
        'Carol',
      ]);
      expect(
        await names(users().whereJsonContains('tags', <String>['dart', 'php'])),
        <String>['Alice'],
      );
      expect(await names(users().whereJsonContains('tags', 7)), <String>[
        'Carol',
      ]);
      expect(await names(users().whereJsonContains('tags', true)), <String>[
        'Carol',
      ]);
      expect(
        await names(users().whereJsonContains('options->languages', 'en')),
        <String>['Alice', 'Bob'],
      );
      expect(
        await names(
          users()
              .whereJsonContains('options->languages', 'fr')
              .orWhereJsonContains('tags', 'go'),
        ),
        <String>['Bob', 'Carol'],
      );
      expect(
        await names(users().whereJsonDoesntContain('tags', 'dart')),
        <String>['Bob'],
      );
      expect(
        () => users().whereJsonContains("tags->a' OR 1=1", 'x'),
        throwsArgumentError,
      );
    });

    test('insertOrIgnore skips duplicate rows', () async {
      int added = await users().insertOrIgnore(<Map<String, dynamic>>[
        <String, dynamic>{
          'name': 'Alice',
          'age': 99,
          'joined_at': DateTime.utc(2025),
        },
        <String, dynamic>{
          'name': 'Dave',
          'age': 50,
          'joined_at': DateTime.utc(2025),
        },
      ]);
      expect(added, 1);
      expect(await users().count(), 4);
      expect(await users().where('name', 'Alice').valueOf('age'), 20);
      expect(await users().insertOrIgnore(<Map<String, dynamic>>[]), 0);
      expect(
        () => users().insertOrIgnore(<Map<String, dynamic>>[
          <String, dynamic>{'name': 'x'},
          <String, dynamic>{'age': 1},
        ]),
        throwsArgumentError,
      );
    });
  });
}

String _name(Map<String, dynamic> row) => row['name'] as String;

int _count(Map<String, dynamic> row) => int.parse('${row['post_count']}');
