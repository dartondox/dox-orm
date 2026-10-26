import 'package:dox_orm/dox_orm.dart';
import 'package:test/test.dart';

import 'connection.dart';
import 'models/blog/blog.model.dart';
import 'models/scoped_post/scoped_post.model.dart';

void main() async {
  await initQueryBuilder();

  Driver driver = SqlQueryBuilder().dbDriver.getName();

  /// [sql] with `"` changed to the quote of the driver
  String q(String sql) =>
      driver == Driver.mysql ? sql.replaceAll('"', '`') : sql;

  QueryBuilder<Map<String, dynamic>> people() => QueryBuilder.table('wc_user');

  /// sorted names of the rows
  Future<List<String>> names(QueryBuilder<Map<String, dynamic>> query) async {
    List<Map<String, dynamic>> rows = await query.get();
    return <String>[for (Map<String, dynamic> r in rows) r['name'] as String]
      ..sort();
  }

  group('Where clauses |', () {
    setUp(() async {
      await Schema().dropIfExists('wc_post');
      await Schema().dropIfExists('wc_user');
      await Schema().create('wc_user', (Table table) {
        table.id();
        table.string('name');
        table.string('email').nullable();
        table.integer('age');
        table.integer('score');
      });
      await Schema().create('wc_post', (Table table) {
        table.id();
        table.integer('user_id');
        table.string('title');
      });
      await people().insertMultiple(<Map<String, dynamic>>[
        <String, dynamic>{
          'name': 'Alice',
          'email': 'alice@a.com',
          'age': 20,
          'score': 20,
        },
        <String, dynamic>{'name': 'bob', 'email': null, 'age': 30, 'score': 10},
        <String, dynamic>{
          'name': 'Carol',
          'email': 'carol@c.com',
          'age': 40,
          'score': 50,
        },
        <String, dynamic>{
          'name': 'dave',
          'email': null,
          'age': 50,
          'score': 50,
        },
      ]);
      await QueryBuilder.table('wc_post').insertMultiple(<Map<String, dynamic>>[
        <String, dynamic>{'user_id': 1, 'title': 'a'},
        <String, dynamic>{'user_id': 1, 'title': 'b'},
        <String, dynamic>{'user_id': 3, 'title': 'c'},
      ]);
    });

    tearDown(() async {
      await Schema().dropIfExists('wc_post');
      await Schema().dropIfExists('wc_user');
    });

    group('where with null |', () {
      test('3 args with = and null is IS NULL', () async {
        expect(
          people().where('email', '=', null).getWhereQuery(),
          q(' WHERE "email" IS NULL'),
        );
        expect(await names(people().where('email', '=', null)), <String>[
          'bob',
          'dave',
        ]);
      });

      test('3 args with != or <> and null is IS NOT NULL', () async {
        expect(
          people().where('email', '!=', null).getWhereQuery(),
          q(' WHERE "email" IS NOT NULL'),
        );
        expect(
          people().where('email', '<>', null).getWhereQuery(),
          q(' WHERE "email" IS NOT NULL'),
        );
        expect(await names(people().where('email', '!=', null)), <String>[
          'Alice',
          'Carol',
        ]);
        expect(await names(people().where('email', '<>', null)), <String>[
          'Alice',
          'Carol',
        ]);
      });

      test('2 args with null is still IS NULL', () async {
        expect(
          people().where('email', null).getWhereQuery(),
          q(' WHERE "email" IS NULL'),
        );
        expect(await names(people().where('email', null)), <String>[
          'bob',
          'dave',
        ]);
      });

      test('the operator string is a value with 2 args', () async {
        QueryBuilder<Map<String, dynamic>> query = people().where('name', '!=');
        expect(query.getWhereQuery(), q(' WHERE "name" = @name_p0'));
        expect(query.substitutionValues, <String, dynamic>{'name_p0': '!='});
        expect(await names(people().where('name', '!=')), <String>[]);
      });

      test('other operators with null throw', () {
        expect(() => people().where('age', '>', null), throwsArgumentError);
        expect(() => people().where('age', 'like', null), throwsArgumentError);
        expect(() => people().orWhere('age', '<', null), throwsArgumentError);
      });

      test('where needs a value', () {
        expect(() => people().where('age'), throwsArgumentError);
      });

      test('orWhere with null', () async {
        QueryBuilder<Map<String, dynamic>> query = people()
            .where('name', 'Alice')
            .orWhere('email', '=', null);
        expect(
          query.getWhereQuery(),
          q(' WHERE "name" = @name_p0 OR "email" IS NULL'),
        );
        expect(await names(query), <String>['Alice', 'bob', 'dave']);
        expect(
          await names(
            people().where('name', 'bob').orWhere('email', '!=', null),
          ),
          <String>['Alice', 'Carol', 'bob'],
        );
        expect(
          await names(people().where('name', 'bob').orWhere('email', null)),
          <String>['bob', 'dave'],
        );
      });

      test('3 args with a value still works', () async {
        expect(await names(people().where('age', '>=', 40)), <String>[
          'Carol',
          'dave',
        ]);
      });
    });

    group('whereGroup |', () {
      test('group gives brackets', () async {
        QueryBuilder<Map<String, dynamic>> query = people()
            .where('age', '>', 20)
            .whereGroup((QueryBuilder<Map<String, dynamic>> g) {
              g.where('name', 'bob').orWhere('name', 'Carol');
            });
        expect(
          query.getWhereQuery(),
          q(
            ' WHERE "age" > @age_p0 AND ("name" = @name_p1 OR "name" = @name_p2)',
          ),
        );
        expect(query.substitutionValues, <String, dynamic>{
          'age_p0': 20,
          'name_p1': 'bob',
          'name_p2': 'Carol',
        });
        expect(await names(query), <String>['Carol', 'bob']);
      });

      test('group first', () async {
        QueryBuilder<Map<String, dynamic>> query = people()
            .whereGroup((QueryBuilder<Map<String, dynamic>> g) {
              g.where('name', 'bob').orWhere('name', 'Alice');
            })
            .where('age', '>', 20);
        expect(
          query.getWhereQuery(),
          q(
            ' WHERE ("name" = @name_p0 OR "name" = @name_p1) AND "age" > @age_p2',
          ),
        );
        expect(await names(query), <String>['bob']);
      });

      test('orWhereGroup', () async {
        QueryBuilder<Map<String, dynamic>> query = people()
            .where('name', 'Alice')
            .orWhereGroup((QueryBuilder<Map<String, dynamic>> g) {
              g.where('age', '>', 30).where('score', 50);
            });
        expect(
          query.getWhereQuery(),
          q(
            ' WHERE "name" = @name_p0 OR ("age" > @age_p1 AND "score" = @score_p2)',
          ),
        );
        expect(await names(query), <String>['Alice', 'Carol', 'dave']);
      });

      test('nested groups', () async {
        QueryBuilder<Map<String, dynamic>> query = people()
            .where('score', 50)
            .whereGroup((QueryBuilder<Map<String, dynamic>> g) {
              g.where('name', 'dave').orWhereGroup((
                QueryBuilder<Map<String, dynamic>> g2,
              ) {
                g2.where('age', '<', 50).whereGroup((
                  QueryBuilder<Map<String, dynamic>> g3,
                ) {
                  g3.where('name', 'Carol').orWhere('name', 'Alice');
                });
              });
            });
        expect(
          query.getWhereQuery(),
          q(
            ' WHERE "score" = @score_p0 AND ("name" = @name_p1 OR '
            '("age" < @age_p2 AND ("name" = @name_p3 OR "name" = @name_p4)))',
          ),
        );
        expect(await names(query), <String>['Carol', 'dave']);
      });

      test('empty group adds nothing', () async {
        void empty(QueryBuilder<Map<String, dynamic>> g) {}
        expect(people().whereGroup(empty).getWhereQuery(), '');
        expect(
          people().where('age', 20).orWhereGroup(empty).getWhereQuery(),
          q(' WHERE "age" = @age_p0'),
        );
        expect(
          people().whereGroup(empty).where('age', 20).whereGroup((
            QueryBuilder<Map<String, dynamic>> g,
          ) {
            g.whereGroup(empty);
          }).getWhereQuery(),
          q(' WHERE "age" = @age_p0'),
        );
        expect(await names(people().whereGroup(empty)), hasLength(4));
      });

      test('the same query gives the same sql', () {
        String build() => people().where('age', '>', 1).whereGroup((
          QueryBuilder<Map<String, dynamic>> g,
        ) {
          g.where('name', 'a').orWhereExists('wc_post', (
            QueryBuilder<Map<String, dynamic>> s,
          ) {
            s.where('title', 'x');
          });
        }).getWhereQuery();
        expect(build(), build());
      });

      test('a callback can return the query', () async {
        expect(
          await names(
            people().whereGroup(
              (QueryBuilder<Map<String, dynamic>> g) =>
                  g.where('age', 20).orWhere('age', 30),
            ),
          ),
          <String>['Alice', 'bob'],
        );
      });
    });

    group('whereNot |', () {
      test('whereNot', () async {
        QueryBuilder<Map<String, dynamic>> query = people().whereNot((
          QueryBuilder<Map<String, dynamic>> g,
        ) {
          g.where('name', 'Alice').orWhere('age', '>', 40);
        });
        expect(
          query.getWhereQuery(),
          q(' WHERE NOT ("name" = @name_p0 OR "age" > @age_p1)'),
        );
        expect(await names(query), <String>['Carol', 'bob']);
      });

      test('orWhereNot', () async {
        QueryBuilder<Map<String, dynamic>> query = people()
            .where('name', 'Alice')
            .orWhereNot((QueryBuilder<Map<String, dynamic>> g) {
              g.where('age', '<', 50);
            });
        expect(
          query.getWhereQuery(),
          q(' WHERE "name" = @name_p0 OR NOT ("age" < @age_p1)'),
        );
        expect(await names(query), <String>['Alice', 'dave']);
      });

      test('empty whereNot adds nothing', () {
        expect(
          people()
              .whereNot((QueryBuilder<Map<String, dynamic>> g) {})
              .getWhereQuery(),
          '',
        );
      });
    });

    group('whereBetween |', () {
      test('whereBetween', () async {
        QueryBuilder<Map<String, dynamic>> query = people().whereBetween(
          'age',
          <int>[30, 40],
        );
        expect(
          query.getWhereQuery(),
          q(' WHERE "age" BETWEEN @age_p0 AND @age_p1'),
        );
        expect(query.substitutionValues, <String, dynamic>{
          'age_p0': 30,
          'age_p1': 40,
        });
        expect(await names(query), <String>['Carol', 'bob']);
      });

      test('whereNotBetween', () async {
        QueryBuilder<Map<String, dynamic>> query = people().whereNotBetween(
          'age',
          <int>[30, 40],
        );
        expect(
          query.getWhereQuery(),
          q(' WHERE "age" NOT BETWEEN @age_p0 AND @age_p1'),
        );
        expect(await names(query), <String>['Alice', 'dave']);
      });

      test('orWhereBetween and orWhereNotBetween', () async {
        QueryBuilder<Map<String, dynamic>> query = people()
            .where('name', 'dave')
            .orWhereBetween('age', <int>[15, 25]);
        expect(
          query.getWhereQuery(),
          q(' WHERE "name" = @name_p0 OR "age" BETWEEN @age_p1 AND @age_p2'),
        );
        expect(await names(query), <String>['Alice', 'dave']);
        expect(
          await names(
            people().where('name', 'bob').orWhereNotBetween('age', <int>[
              20,
              40,
            ]),
          ),
          <String>['bob', 'dave'],
        );
      });

      test('needs two values', () {
        expect(
          () => people().whereBetween('age', <int>[1]),
          throwsArgumentError,
        );
        expect(
          () => people().whereNotBetween('age', <int>[1, 2, 3]),
          throwsArgumentError,
        );
        expect(
          () => people().orWhereBetween('age', <int?>[1, null]),
          throwsArgumentError,
        );
      });
    });

    group('whereColumn |', () {
      test('2 args is =', () async {
        QueryBuilder<Map<String, dynamic>> query = people().whereColumn(
          'age',
          'score',
        );
        expect(query.getWhereQuery(), q(' WHERE "age" = "score"'));
        expect(query.substitutionValues, isEmpty);
        expect(await names(query), <String>['Alice', 'dave']);
      });

      test('3 args with an operator', () async {
        QueryBuilder<Map<String, dynamic>> query = people().whereColumn(
          'wc_user.score',
          '>',
          'wc_user.age',
        );
        expect(
          query.getWhereQuery(),
          q(' WHERE "wc_user"."score" > "wc_user"."age"'),
        );
        expect(await names(query), <String>['Carol']);
      });

      test('orWhereColumn', () async {
        QueryBuilder<Map<String, dynamic>> query = people()
            .where('name', 'bob')
            .orWhereColumn('score', '>', 'age');
        expect(
          query.getWhereQuery(),
          q(' WHERE "name" = @name_p0 OR "score" > "age"'),
        );
        expect(await names(query), <String>['Carol', 'bob']);
        expect(
          await names(
            people().where('name', 'bob').orWhereColumn('age', 'score'),
          ),
          <String>['Alice', 'bob', 'dave'],
        );
      });

      test('bad operator and bad names throw', () {
        expect(
          () => people().whereColumn('age', 'or 1=1 --', 'score'),
          throwsArgumentError,
        );
        expect(
          () => people().whereColumn('age', 'score; drop table x'),
          throwsArgumentError,
        );
      });
    });

    group('whereExists |', () {
      void hasPost(QueryBuilder<Map<String, dynamic>> s) {
        s.whereColumn('wc_post.user_id', 'wc_user.id');
      }

      test('whereExists', () async {
        QueryBuilder<Map<String, dynamic>> query = people().whereExists(
          'wc_post',
          hasPost,
        );
        expect(
          query.getWhereQuery(),
          q(
            ' WHERE EXISTS (SELECT 1 FROM "wc_post" '
            'WHERE "wc_post"."user_id" = "wc_user"."id")',
          ),
        );
        expect(await names(query), <String>['Alice', 'Carol']);
      });

      test('whereNotExists', () async {
        QueryBuilder<Map<String, dynamic>> query = people().whereNotExists(
          'wc_post',
          hasPost,
        );
        expect(
          query.getWhereQuery(),
          q(
            ' WHERE NOT EXISTS (SELECT 1 FROM "wc_post" '
            'WHERE "wc_post"."user_id" = "wc_user"."id")',
          ),
        );
        expect(await names(query), <String>['bob', 'dave']);
      });

      test('orWhereExists and orWhereNotExists', () async {
        expect(
          await names(
            people().where('name', 'bob').orWhereExists('wc_post', hasPost),
          ),
          <String>['Alice', 'Carol', 'bob'],
        );
        expect(
          await names(
            people()
                .where('name', 'Alice')
                .orWhereNotExists('wc_post', hasPost),
          ),
          <String>['Alice', 'bob', 'dave'],
        );
      });

      test('subquery params do not clash with the outer query', () async {
        QueryBuilder<Map<String, dynamic>> query = people()
            .where('name', '!=', 'Alice')
            .whereExists('wc_post', (QueryBuilder<Map<String, dynamic>> s) {
              s
                  .whereColumn('wc_post.user_id', 'wc_user.id')
                  .where('title', 'c');
            })
            .orWhereExists('wc_post', (QueryBuilder<Map<String, dynamic>> s) {
              s
                  .whereColumn('wc_post.user_id', 'wc_user.id')
                  .where('title', 'a')
                  .whereExists('wc_post as p2', (
                    QueryBuilder<Map<String, dynamic>> s2,
                  ) {
                    s2.where('title', 'b');
                  });
            });
        expect(
          query.getWhereQuery(),
          q(
            ' WHERE "name" != @name_p0 AND EXISTS (SELECT 1 FROM "wc_post" '
            'WHERE "wc_post"."user_id" = "wc_user"."id" '
            'AND "title" = @dox_ex0_title_p0) OR EXISTS (SELECT 1 FROM '
            '"wc_post" WHERE "wc_post"."user_id" = "wc_user"."id" '
            'AND "title" = @dox_ex1_title_p0 AND EXISTS (SELECT 1 FROM '
            '"wc_post" as "p2" WHERE "title" = @dox_ex1_dox_ex0_title_p0))',
          ),
        );
        expect(query.substitutionValues, <String, dynamic>{
          'name_p0': 'Alice',
          'dox_ex0_title_p0': 'c',
          'dox_ex1_title_p0': 'a',
          'dox_ex1_dox_ex0_title_p0': 'b',
        });

        /// Carol is not Alice and has post c. Alice fails the first
        /// part, but has post a and a post b exists, so the OR keeps her.
        expect(await names(query), <String>['Alice', 'Carol']);
      });

      test('in a group', () async {
        QueryBuilder<Map<String, dynamic>> query = people()
            .where('age', '>', 25)
            .whereGroup((QueryBuilder<Map<String, dynamic>> g) {
              g.whereExists('wc_post', hasPost).orWhere('name', 'dave');
            });
        expect(await names(query), <String>['Carol', 'dave']);
      });
    });

    group('whereLike |', () {
      String like(bool not, bool caseSensitive) {
        String op = switch (driver) {
          Driver.postgres => caseSensitive ? 'LIKE' : 'ILIKE',
          Driver.mysql => caseSensitive ? 'LIKE BINARY' : 'LIKE',
          Driver.sqlite => caseSensitive ? 'GLOB' : 'LIKE',
        };
        return not ? 'NOT $op' : op;
      }

      test('whereLike does not care about case', () async {
        QueryBuilder<Map<String, dynamic>> query = people().whereLike(
          'name',
          'c%',
        );
        expect(
          query.getWhereQuery(),
          q(' WHERE "name" ${like(false, false)} @name_p0'),
        );
        expect(query.substitutionValues, <String, dynamic>{'name_p0': 'c%'});
        expect(await names(query), <String>['Carol']);
        expect(await names(people().whereLike('name', '%A%')), <String>[
          'Alice',
          'Carol',
          'dave',
        ]);
      });

      test('whereLike case sensitive', () async {
        QueryBuilder<Map<String, dynamic>> query = people().whereLike(
          'name',
          'c%',
          caseSensitive: true,
        );
        expect(
          query.getWhereQuery(),
          q(' WHERE "name" ${like(false, true)} @name_p0'),
        );
        expect(await names(query), <String>[]);
        expect(
          await names(people().whereLike('name', 'C%', caseSensitive: true)),
          <String>['Carol'],
        );
        expect(
          await names(people().whereLike('name', '_a%', caseSensitive: true)),
          <String>['Carol', 'dave'],
        );
      });

      test('whereNotLike', () async {
        QueryBuilder<Map<String, dynamic>> query = people().whereNotLike(
          'name',
          '%a%',
        );
        expect(
          query.getWhereQuery(),
          q(' WHERE "name" ${like(true, false)} @name_p0'),
        );
        expect(await names(query), <String>['bob']);
        expect(
          await names(
            people().whereNotLike('name', '%a%', caseSensitive: true),
          ),
          <String>['Alice', 'bob'],
        );
      });

      test('orWhereLike and orWhereNotLike', () async {
        QueryBuilder<Map<String, dynamic>> query = people()
            .where('age', 30)
            .orWhereLike('name', 'ALI%');
        expect(
          query.getWhereQuery(),
          q(' WHERE "age" = @age_p0 OR "name" ${like(false, false)} @name_p1'),
        );
        expect(await names(query), <String>['Alice', 'bob']);
        expect(
          await names(people().where('age', 30).orWhereNotLike('name', '%a%')),
          <String>['bob'],
        );
        expect(
          await names(
            people()
                .where('age', 20)
                .orWhereNotLike('name', '%a%', caseSensitive: true),
          ),
          <String>['Alice', 'bob'],
        );
        expect(
          await names(
            people()
                .where('age', 20)
                .orWhereLike('name', 'd%', caseSensitive: true),
          ),
          <String>['Alice', 'dave'],
        );
      });

      test('glob characters are plain text in a case sensitive like', () async {
        await people().insert(<String, dynamic>{
          'name': 'a*b?[c]',
          'age': 1,
          'score': 1,
        });
        expect(
          await names(
            people().whereLike('name', 'a*b?[c]', caseSensitive: true),
          ),
          <String>['a*b?[c]'],
        );
        expect(
          await names(people().whereLike('name', 'a*%', caseSensitive: true)),
          <String>['a*b?[c]'],
        );
      });
    });
  });

  group('Where clauses with scopes |', () {
    setUp(() async {
      await Schema().dropIfExists('scoped_post');
      await Schema().create('scoped_post', (Table table) {
        table.id();
        table.string('title');
        table.boolean('published');
        table.boolean('archived').nullable();
        table.integer('views');
      });
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
    });

    tearDown(() async {
      await Schema().dropIfExists('scoped_post');
    });

    List<String?> titles(List<ScopedPost> list) {
      return <String?>[for (ScopedPost p in list) p.title]..sort();
    }

    test('a group and the global scope are both in brackets', () async {
      QueryBuilder<ScopedPost> query = ScopedPost()
          .where('views', '>', 0)
          .orWhereGroup((QueryBuilder<ScopedPost> g) {
            g.where('title', 'c').orWhere('title', 'b');
          });
      expect(
        query.getWhereQuery(),
        q(
          ' WHERE ("views" > @views_p0 OR ("title" = @title_p1 OR '
          '"title" = @title_p2)) AND ("archived" = @archived_p3 OR '
          '"archived" IS NULL)',
        ),
      );

      /// c is archived, the global scope leaves it out
      expect(
        titles(
          await ScopedPost().where('views', '>', 0).orWhereGroup((
            QueryBuilder<ScopedPost> g,
          ) {
            g.where('title', 'c').orWhere('title', 'b');
          }).get(),
        ),
        <String>['a', 'b', 'd'],
      );
      expect(
        titles(
          await ScopedPost().whereGroup((QueryBuilder<ScopedPost> g) {
            g.where('title', 'c').orWhere('title', 'b');
          }).get(),
        ),
        <String>['b'],
      );
    });

    test('whereNot and between with the global scope', () async {
      expect(
        titles(
          await ScopedPost().whereNot((QueryBuilder<ScopedPost> g) {
            g.whereBetween('views', <int>[15, 35]);
          }).get(),
        ),
        <String>['a', 'd'],
      );
      expect(
        titles(
          await ScopedPost().where('title', 'a').orWhereBetween('views', <int>[
            25,
            45,
          ]).get(),
        ),
        <String>['a', 'd'],
      );
    });

    test('where != null with the global scope', () async {
      expect(
        titles(await ScopedPost().where('archived', '!=', null).get()),
        <String>['a', 'b'],
      );
      expect(
        titles(
          await ScopedPost()
              .withoutGlobalScopes()
              .where('archived', '=', null)
              .get(),
        ),
        <String>['d'],
      );
    });
  });

  group('Where clauses with soft deletes |', () {
    setUp(() async {
      await Schema().dropIfExists('blog');
      await Schema().dropIfExists('blog_info');
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
      await Blog().insertMultiple(<Map<String, dynamic>>[
        <String, dynamic>{'title': 'one', 'body': 'x', 'status': 'active'},
        <String, dynamic>{'title': 'two', 'body': 'y', 'status': 'draft'},
        <String, dynamic>{'title': 'three', 'body': 'x', 'status': 'draft'},
      ]);
      await Blog().where('title', 'three').delete();
    });

    tearDown(() async {
      await Schema().dropIfExists('blog');
      await Schema().dropIfExists('blog_info');
    });

    List<String?> titles(List<Blog> list) {
      return <String?>[for (Blog b in list) b.title]..sort();
    }

    test('an or group can not skip the soft delete check', () async {
      QueryBuilder<Blog> query = Blog().where('status', 'active').orWhereGroup((
        QueryBuilder<Blog> g,
      ) {
        g.where('body', 'x').orWhere('status', 'draft');
      });
      expect(
        query.getWhereQuery(),
        q(
          ' WHERE ("status" = @status_p0 OR ("body" = @body_p1 OR '
          '"status" = @status_p2)) AND "blog"."deleted_at" IS NULL',
        ),
      );
      expect(
        titles(
          await Blog().where('status', 'active').orWhereGroup((
            QueryBuilder<Blog> g,
          ) {
            g.where('body', 'x').orWhere('status', 'draft');
          }).get(),
        ),
        <String>['one', 'two'],
      );
      expect(
        titles(
          await Blog().withTrash().where('status', 'active').orWhereGroup((
            QueryBuilder<Blog> g,
          ) {
            g.where('body', 'x').orWhere('status', 'draft');
          }).get(),
        ),
        <String>['one', 'three', 'two'],
      );
    });

    test('like, column and exists with soft deletes', () async {
      expect(
        titles(await Blog().where('uid', 1).orWhereLike('title', 'T%').get()),
        <String>['one', 'two'],
      );
      expect(titles(await Blog().whereColumn('title', 'title').get()), <String>[
        'one',
        'two',
      ]);
      expect(
        titles(
          await Blog().where('uid', 2).orWhereNotExists('blog_info', (
            QueryBuilder<Map<String, dynamic>> s,
          ) {
            s.whereColumn('blog_info.blog_id', 'blog.uid');
          }).get(),
        ),
        <String>['one', 'two'],
      );
    });

    test('where deleted_at != null with trash', () async {
      expect(
        titles(await Blog().withTrash().where('deleted_at', '!=', null).get()),
        <String>['three'],
      );
    });
  });
}
