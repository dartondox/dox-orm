import 'package:dox_orm/dox_orm.dart';
import 'package:test/test.dart';

import 'connection.dart';
import 'models/blog/blog.model.dart';
import 'models/scoped_post/scoped_post.model.dart';

void main() async {
  await initQueryBuilder();

  Driver driver = SqlQueryBuilder().dbDriver.getName();

  QueryBuilder<Map<String, dynamic>> item() => QueryBuilder.table('item');

  group('Read helpers |', () {
    setUp(() async {
      for (String t in <String>['item', 'blog', 'blog_info', 'scoped_post']) {
        await Schema().dropIfExists(t);
      }
      await Schema().create('item', (Table table) {
        table.id();
        table.string('name');
        table.string('category');
        table.decimal('price');
        table.integer('qty');
        table.dateTime('made_at').nullable();
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
      await Schema().create('scoped_post', (Table table) {
        table.id();
        table.string('title');
        table.boolean('published');
        table.boolean('archived').nullable();
        table.integer('views');
      });
    });

    tearDown(() async {
      for (String t in <String>['item', 'blog', 'blog_info', 'scoped_post']) {
        await Schema().dropIfExists(t);
      }
    });

    Future<void> seedItems() async {
      await item().insertMultiple(<Map<String, dynamic>>[
        <String, dynamic>{
          'name': 'apple',
          'category': 'fruit',
          'price': 1.5,
          'qty': 10,
          'made_at': DateTime.utc(2024),
        },
        <String, dynamic>{
          'name': 'pear',
          'category': 'fruit',
          'price': 2.25,
          'qty': 5,
          'made_at': DateTime.utc(2024, 2),
        },
        <String, dynamic>{
          'name': 'kale',
          'category': 'veg',
          'price': 3,
          'qty': 0,
          'made_at': DateTime.utc(2024, 3),
        },
        <String, dynamic>{
          'name': 'leek',
          'category': 'veg',
          'price': 3,
          'qty': 7,
        },
      ]);
    }

    /// three blogs, the second one is soft deleted
    Future<void> seedBlogs() async {
      for (String title in <String>['one', 'two', 'three']) {
        await Blog().create(<String, dynamic>{'title': title, 'body': 'b'});
      }
      await Blog().where('title', 'two').delete();
    }

    /// a, b and d are visible. c is archived, the global scope hides it.
    Future<void> seedPosts() async {
      await ScopedPost().insertMultiple(<Map<String, dynamic>>[
        <String, dynamic>{
          'title': 'a',
          'published': true,
          'archived': false,
          'views': 10,
        },
        <String, dynamic>{
          'title': 'b',
          'published': false,
          'archived': false,
          'views': 20,
        },
        <String, dynamic>{
          'title': 'c',
          'published': true,
          'archived': true,
          'views': 30,
        },
        <String, dynamic>{'title': 'd', 'published': true, 'views': 40},
      ]);
    }

    group('paginate |', () {
      test('perPage below 1 throws an ArgumentError', () async {
        await seedItems();
        await expectLater(
          item().paginate(currentPage: 1, perPage: 0),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError e) => e.name,
              'name',
              'perPage',
            ),
          ),
        );
        await expectLater(
          item().paginate(currentPage: 1, perPage: -3),
          throwsArgumentError,
        );
      });

      test('currentPage below 1 is page 1', () async {
        await seedItems();
        for (int page in <int>[0, -5]) {
          Pagination<Map<String, dynamic>> p = await item()
              .orderBy('id')
              .paginate(currentPage: page, perPage: 3);
          expect(p.currentPage, 1);
          expect(p.total, 4);
          expect(p.lastPage, 2);
          expect(
            <dynamic>[for (Map<String, dynamic> r in p.data) r['name']],
            <String>['apple', 'pear', 'kale'],
          );
        }
      });

      test('an empty table gives no pages', () async {
        Pagination<Map<String, dynamic>> p = await item().paginate(
          currentPage: 1,
          perPage: 10,
        );
        expect(p.total, 0);
        expect(p.lastPage, 0);
        expect(p.data, isEmpty);
      });
    });

    group('firstOrFail and findOrFail |', () {
      test('they give the row', () async {
        await seedItems();
        Map<String, dynamic> row = await item()
            .where('name', 'pear')
            .firstOrFail();
        expect(row['qty'], 5);
        expect((await item().findOrFail(3))['name'], 'kale');
        expect((await item().findOrFail('name', 'leek'))['id'], 4);
      });

      test('they throw on an empty table', () async {
        await expectLater(
          item().firstOrFail(),
          throwsA(
            isA<ModelNotFoundException>()
                .having((ModelNotFoundException e) => e.table, 'table', 'item')
                .having((ModelNotFoundException e) => e.id, 'id', null),
          ),
        );
        await expectLater(
          item().findOrFail(7),
          throwsA(
            isA<ModelNotFoundException>()
                .having((ModelNotFoundException e) => e.table, 'table', 'item')
                .having((ModelNotFoundException e) => e.id, 'id', 7)
                .having((ModelNotFoundException e) => e.column, 'column', 'id'),
          ),
        );
        await expectLater(
          item().findOrFail('name', 'x'),
          throwsA(
            isA<ModelNotFoundException>()
                .having(
                  (ModelNotFoundException e) => e.column,
                  'column',
                  'name',
                )
                .having((ModelNotFoundException e) => e.id, 'id', 'x'),
          ),
        );
        expect(
          const ModelNotFoundException('item', id: 7, column: 'id').toString(),
          contains('item'),
        );
      });

      test('a soft deleted model is not found', () async {
        await seedBlogs();
        Blog one = await Blog().where('title', 'one').firstOrFail();
        expect((await Blog().findOrFail(one.uid)).title, 'one');
        expect(await Blog().where('title', 'one').firstOrFail(), isA<Blog>());
        await expectLater(
          Blog().findOrFail(2),
          throwsA(
            isA<ModelNotFoundException>()
                .having((ModelNotFoundException e) => e.table, 'table', 'blog')
                .having(
                  (ModelNotFoundException e) => e.column,
                  'column',
                  'uid',
                ),
          ),
        );
        expect((await Blog().withTrash().findOrFail(2)).title, 'two');
      });

      test('a global scope hides the row', () async {
        await seedPosts();
        await expectLater(
          ScopedPost().where('title', 'c').firstOrFail(),
          throwsA(isA<ModelNotFoundException>()),
        );
        ScopedPost post = await ScopedPost()
            .withoutGlobalScopes()
            .where('title', 'c')
            .firstOrFail();
        expect(post.views, 30);
      });
    });

    group('hasRows and hasNoRows |', () {
      test('empty table', () async {
        expect(await item().hasRows(), false);
        expect(await item().hasNoRows(), true);
      });

      test('with where, order by and limit', () async {
        await seedItems();
        expect(await item().hasRows(), true);
        expect(await item().where('category', 'veg').hasRows(), true);
        expect(await item().where('category', 'nut').hasRows(), false);
        expect(await item().where('category', 'nut').hasNoRows(), true);
        expect(
          await item().where('qty', '>', 1).orderBy('id').limit(2).hasRows(),
          true,
        );
        expect(await item().groupBy('category').hasRows(), true);
      });

      test('soft deletes and global scopes', () async {
        await seedBlogs();
        await seedPosts();
        expect(await Blog().where('title', 'two').hasRows(), false);
        expect(await Blog().withTrash().where('title', 'two').hasRows(), true);
        expect(await ScopedPost().where('title', 'c').hasNoRows(), true);
        expect(
          await ScopedPost()
              .withoutGlobalScopes()
              .where('title', 'c')
              .hasRows(),
          true,
        );
        Blog blog = Blog();
        expect(blog.exists, false);
      });
    });

    group('pluck and valueOf |', () {
      test('empty table', () async {
        expect(await item().pluck('name'), isEmpty);
        expect(await item().pluckMap('name', 'id'), isEmpty);
        expect(await item().valueOf('name'), isNull);
      });

      test('one column, with where, order and distinct', () async {
        await seedItems();
        expect(await item().orderBy('id').pluck('name'), <String>[
          'apple',
          'pear',
          'kale',
          'leek',
        ]);
        expect(
          await item().where('category', 'veg').orderBy('name').pluck('name'),
          <String>['kale', 'leek'],
        );
        List<dynamic> categories = await item().distinct().pluck('category');
        expect(categories..sort(), <String>['fruit', 'veg']);
        expect(await item().orderBy('id').limit(2).pluck('qty'), <int>[10, 5]);
        expect(await item().pluckMap('name', 'id'), <dynamic, dynamic>{
          1: 'apple',
          2: 'pear',
          3: 'kale',
          4: 'leek',
        });
        expect(await item().where('id', 2).valueOf('name'), 'pear');
        expect(await item().orderBy('qty', 'desc').valueOf('name'), 'apple');
        expect(await item().where('id', 99).valueOf('name'), isNull);
        expect(await item().where('id', 4).valueOf('made_at'), isNull);
        expect(
          await item().where('id', 1).valueOf('made_at'),
          contains('2024-01-01'),
        );
      });

      test('soft deletes and global scopes', () async {
        await seedBlogs();
        await seedPosts();
        expect(await Blog().orderBy('uid').pluck('title'), <String>[
          'one',
          'three',
        ]);
        expect(await ScopedPost().orderBy('id').pluck('title'), <String>[
          'a',
          'b',
          'd',
        ]);
        expect(await ScopedPost().where('title', 'c').valueOf('views'), isNull);
      });

      test('a value is a param, a column name is checked', () {
        expect(
          () => item().pluck('name; drop table item'),
          throwsArgumentError,
        );
        expect(() => item().valueOf('count(*)'), throwsArgumentError);
        expect(
          () => item().rawQuery('select 1').pluck('name'),
          throwsStateError,
        );
      });
    });

    group('aggregates |', () {
      test('null on an empty table', () async {
        expect(await item().sum('qty'), isNull);
        expect(await item().avg('qty'), isNull);
        expect(await item().min('qty'), isNull);
        expect(await item().max('qty'), isNull);
        expect(await item().where('id', 1).max('made_at'), isNull);
      });

      test('sum, avg, min and max', () async {
        await seedItems();
        num? qty = await item().sum('qty');
        expect(qty, 22);

        /// an int or a double, by driver
        expect(qty, isA<num>());
        expect(await item().sum('price'), closeTo(9.75, 0.0001));
        expect(await item().sum('price'), isA<num>());
        expect(await item().avg('qty'), 5.5);
        expect(await item().avg('price'), closeTo(2.4375, 0.0001));
        expect(await item().min('qty'), 0);
        expect(await item().max('qty'), 10);
        expect(await item().max('name'), 'pear');
        expect(await item().min('made_at'), contains('2024-01-01'));
        expect(await item().max('made_at'), contains('2024-03-01'));
        expect(num.parse('${await item().max('price')}'), 3);
      });

      test('with where, join and order by', () async {
        await seedItems();
        expect(await item().where('category', 'fruit').sum('qty'), 15);
        expect(await item().where('category', 'nut').sum('qty'), isNull);
        expect(
          await item()
              .where('category', 'veg')
              .orderBy('id')
              .limit(1)
              .sum('qty'),
          7,
        );
        expect(await item().where('qty', '>', 0).min('qty'), 5);
        await QueryBuilder.table('blog_info')
            .insert(<String, dynamic>{'info': '{}', 'blog_id': 2});
        expect(
          await item()
              .join('blog_info', 'blog_info.blog_id', 'item.id')
              .sum('item.qty'),
          5,
        );
      });

      test('distinct sum and avg', () async {
        await seedItems();
        expect(await item().distinct().sum('price'), closeTo(6.75, 0.0001));
        expect(await item().distinct().avg('price'), closeTo(2.25, 0.0001));
        expect(await item().distinct().max('price'), isNotNull);
      });

      test('soft deletes and global scopes', () async {
        await seedBlogs();
        await seedPosts();
        expect(await Blog().max('uid'), 3);
        expect(await Blog().withTrash().sum('uid'), 6);
        expect(await Blog().sum('uid'), 4);
        expect(await ScopedPost().sum('views'), 70);
        expect(await ScopedPost().withoutGlobalScopes().sum('views'), 100);
        expect(await ScopedPost().max('views'), 40);
        expect(await ScopedPost().where('published', true).min('views'), 10);
        expect(await ScopedPost().avg('views'), closeTo(70 / 3, 0.0001));
      });

      test('groupBy and having throw a StateError', () async {
        expect(() => item().groupBy('category').sum('qty'), throwsStateError);
        expect(() => item().havingRaw('1 = 1').max('qty'), throwsStateError);
      });
    });

    group('distinct |', () {
      test('get and count distinct rows', () async {
        expect(await item().select('category').distinct().count(), 0);
        await seedItems();
        List<Map<String, dynamic>> rows = await item()
            .select('category')
            .distinct()
            .orderBy('category')
            .get();
        expect(rows, <Map<String, dynamic>>[
          <String, dynamic>{'category': 'fruit'},
          <String, dynamic>{'category': 'veg'},
        ]);
        expect(await item().select('category').distinct().count(), 2);
        expect(await item().select('category, price').distinct().count(), 3);
        expect(await item().select('price').distinct().count(), 3);
        expect(
          await item()
              .select('category')
              .distinct()
              .where('qty', '>', 0)
              .count(),
          2,
        );
        expect(await item().distinct().count(), 4);
        expect(await item().select('category').distinct(false).count(), 4);
        expect(
          item().select('category').distinct().toSql(),
          startsWith('SELECT DISTINCT'),
        );
      });

      test('paginate with distinct', () async {
        await seedItems();
        Pagination<Map<String, dynamic>> p = await item()
            .select('category')
            .distinct()
            .orderBy('category')
            .paginate(currentPage: 1, perPage: 1);
        expect(p.total, 2);
        expect(p.lastPage, 2);
        expect(p.data.single['category'], 'fruit');
      });

      test('soft deletes', () async {
        await seedBlogs();
        expect(await Blog().select('body').distinct().count(), 1);
        expect(await Blog().select('title').distinct().count(), 2);
        expect(await Blog().withTrash().select('title').distinct().count(), 3);
      });
    });

    group('having |', () {
      Future<List<String>> groups(QueryBuilder<Map<String, dynamic>> q) async {
        List<Map<String, dynamic>> rows = await q
            .selectRaw('category, count(*) as total')
            .groupBy('category')
            .orderBy('category')
            .get();
        return <String>[for (Map<String, dynamic> r in rows) r['category']];
      }

      test('having, orHaving and havingRaw', () async {
        expect(await groups(item().having('category', 'veg')), isEmpty);
        await seedItems();
        await item().insert(<String, dynamic>{
          'name': 'fig',
          'category': 'fruit',
          'price': 4,
          'qty': 1,
        });
        expect(await groups(item().having('category', 'veg')), <String>['veg']);
        expect(await groups(item().having('category', '!=', 'veg')), <String>[
          'fruit',
        ]);
        expect(
          await groups(
            item().having('category', 'veg').orHaving('category', 'fruit'),
          ),
          <String>['fruit', 'veg'],
        );
        expect(
          await groups(
            item().havingRaw('count(*) > @min', <String, dynamic>{'min': 2}),
          ),
          <String>['fruit'],
        );
        expect(
          await groups(
            item()
                .havingRaw('count(*) > @min', <String, dynamic>{'min': 2})
                .orHavingRaw('sum(qty) = @q', <String, dynamic>{'q': 7}),
          ),
          <String>['fruit', 'veg'],
        );
        expect(
          await groups(
            item().where('qty', '>', 0).havingRaw(
              'count(*) = @n',
              <String, dynamic>{'n': 1},
            ),
          ),
          <String>['veg'],
        );
        expect(
          await item().groupBy('category').havingRaw(
            'count(*) > @min',
            <String, dynamic>{'min': 2},
          ).count(),
          1,
        );
        expect(
          await item().groupBy('category').havingRaw(
            'count(*) > @min',
            <String, dynamic>{'min': 2},
          ).hasRows(),
          true,
        );
      });

      test('having sql goes after group by', () {
        String sql = item()
            .where('qty', '>', 0)
            .groupBy('category')
            .having('category', 'veg')
            .orderBy('category')
            .limit(5)
            .toSql();
        String q = driver == Driver.mysql ? '`' : '"';
        expect(
          sql,
          endsWith(
            'GROUP BY ${q}category$q HAVING ${q}category$q = veg '
            'ORDER BY ${q}category$q LIMIT 5',
          ),
        );
        expect(
          item().groupBy('category').having('category', null).toSql(),
          endsWith('HAVING ${q}category$q IS NULL'),
        );
        expect(
          () => item().having('category', 'drop', 'x'),
          throwsArgumentError,
        );
        expect(() => item().having('count(*)', 1), throwsArgumentError);
      });
    });

    group('chunk |', () {
      test('empty table', () async {
        int calls = 0;
        expect(
          await item().chunk(2, (List<Map<String, dynamic>> rows) {
            calls++;
            return null;
          }),
          true,
        );
        expect(
          await item().chunkById(2, (List<Map<String, dynamic>> rows) {
            calls++;
            return null;
          }),
          true,
        );
        expect(calls, 0);
      });

      test('chunk gives every row once, in pages', () async {
        await seedItems();
        List<List<dynamic>> pages = <List<dynamic>>[];
        bool done = await item().chunk(3, (List<Map<String, dynamic>> rows) {
          pages.add(<dynamic>[for (Map<String, dynamic> r in rows) r['id']]);
          return true;
        });
        expect(done, true);
        expect(pages, <List<int>>[
          <int>[1, 2, 3],
          <int>[4],
        ]);

        pages.clear();
        await item().orderBy('name').chunk(2, (
          List<Map<String, dynamic>> rows,
        ) async {
          pages.add(<dynamic>[for (Map<String, dynamic> r in rows) r['name']]);
          return null;
        });
        expect(pages, <List<String>>[
          <String>['apple', 'kale'],
          <String>['leek', 'pear'],
        ]);

        /// 4 rows and size 2: 2 full pages, then one empty read
        pages.clear();
        await item().where('id', '>', 0).chunk(2, (
          List<Map<String, dynamic>> rows,
        ) {
          pages.add(rows);
          return true;
        });
        expect(pages.length, 2);
      });

      test('false stops the loop', () async {
        await seedItems();
        int calls = 0;
        bool done = await item().chunk(1, (List<Map<String, dynamic>> rows) {
          calls++;
          return calls < 2;
        });
        expect(done, false);
        expect(calls, 2);
        calls = 0;
        done = await item().chunkById(1, (List<Map<String, dynamic>> rows) {
          calls++;
          return false;
        });
        expect(done, false);
        expect(calls, 1);
      });

      test('size below 1 throws', () async {
        Future<bool?> none(List<Map<String, dynamic>> rows) async => null;
        await expectLater(item().chunk(0, none), throwsArgumentError);
        await expectLater(item().chunkById(-1, none), throwsArgumentError);
      });

      test('chunkById is safe when the callback deletes rows', () async {
        await seedItems();
        List<dynamic> seen = <dynamic>[];
        await item().chunkById(2, (List<Map<String, dynamic>> rows) async {
          for (Map<String, dynamic> r in rows) {
            seen.add(r['id']);
            await item().where('id', r['id']).delete();
          }
          return true;
        });
        expect(seen, <int>[1, 2, 3, 4]);
        expect(await item().count(), 0);
      });

      test('chunkById keeps an OR in brackets', () async {
        await seedItems();
        List<dynamic> seen = <dynamic>[];
        await item()
            .where('category', 'fruit')
            .orWhere('category', 'veg')
            .chunkById(1, (List<Map<String, dynamic>> rows) {
              seen.add(rows.single['id']);

              /// a stop, so a bug can not loop for ever
              return seen.length < 10;
            });
        expect(seen, <int>[1, 2, 3, 4]);
      });

      test('chunkById throws with orderBy', () async {
        await expectLater(
          item()
              .orderBy('name')
              .chunkById(2, (List<Map<String, dynamic>> rows) => true),
          throwsStateError,
        );
      });

      test('chunk and chunkById on models, soft deletes and scopes', () async {
        await seedBlogs();
        await seedPosts();
        List<String?> titles = <String?>[];
        await Blog().chunk(1, (List<Blog> blogs) {
          titles.addAll(blogs.map((Blog b) => b.title));
          return true;
        });
        expect(titles, <String>['one', 'three']);
        titles.clear();
        await Blog().chunkById(1, (List<Blog> blogs) {
          titles.addAll(blogs.map((Blog b) => b.title));
          return true;
        });
        expect(titles, <String>['one', 'three']);
        titles.clear();
        await ScopedPost().chunkById(2, (List<ScopedPost> posts) {
          titles.addAll(posts.map((ScopedPost p) => p.title));
          return true;
        });
        expect(titles, <String>['a', 'b', 'd']);
        titles.clear();
        await ScopedPost().where('views', '>', 10).chunk(1, (
          List<ScopedPost> posts,
        ) {
          titles.addAll(posts.map((ScopedPost p) => p.title));
          return true;
        });
        expect(titles, <String>['b', 'd']);
      });
    });

    group('order helpers and when |', () {
      test('latest, oldest and inRandomOrder', () async {
        await seedItems();
        expect(
          await item().latest('made_at').whereNotNull('made_at').pluck('name'),
          <String>['kale', 'pear', 'apple'],
        );
        expect(
          await item().oldest('made_at').whereNotNull('made_at').pluck('name'),
          <String>['apple', 'pear', 'kale'],
        );
        List<dynamic> random = await item().inRandomOrder().pluck('id');
        expect(random..sort(), <int>[1, 2, 3, 4]);
        expect(
          item().inRandomOrder().toSql(),
          endsWith(driver == Driver.mysql ? 'RAND()' : 'RANDOM()'),
        );
        await seedBlogs();
        expect(Blog().latest().toSql(), contains('created_at'));
        expect((await Blog().oldest().getFirst())?.title, 'one');
      });

      test('when', () async {
        await seedItems();
        Future<List<dynamic>> names(String? category) {
          return item()
              .when(category != null, (QueryBuilder<Map<String, dynamic>> q) {
                q.where('category', category);
              })
              .orderBy('id')
              .pluck('name');
        }

        expect(await names('veg'), <String>['kale', 'leek']);
        expect((await names(null)).length, 4);
        List<dynamic> other = await item()
            .when(
              false,
              (QueryBuilder<Map<String, dynamic>> q) => q.where('id', 1),
              (QueryBuilder<Map<String, dynamic>> q) => q.where('id', 2),
            )
            .pluck('name');
        expect(other, <String>['pear']);
      });
    });
  });
}
