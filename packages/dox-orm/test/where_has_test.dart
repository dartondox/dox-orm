import 'package:dox_orm/dox_orm.dart';
import 'package:test/test.dart';

import 'connection.dart';
import 'models/writer/writer.model.dart';

/// ids of [list], to compare results in one line
List<int?> ids(List<Model<dynamic>> list) => <int?>[
  for (Model<dynamic> m in list) m.tempIdValue as int?,
];

Future<List<int?>> writers(QueryBuilder<Writer> q) async {
  return ids(await q.orderBy('id').get());
}

Future<List<int?>> articles(QueryBuilder<Article> q) async {
  return ids(await q.orderBy('id').get());
}

void main() async {
  await initQueryBuilder();

  group('whereHas |', () {
    setUpAll(() async {
      for (String t in <String>[
        'writers',
        'articles',
        'remarks',
        'topics',
        'topic_writer',
      ]) {
        await Schema().dropIfExists(t);
      }
      await Schema().create('writers', (Table table) {
        table.id();
        table.string('name');
        table.softDeletes();
      });
      await Schema().create('articles', (Table table) {
        table.id();
        table.string('title');
        table.boolean('published');
        table.integer('writer_id');
        table.softDeletes();
      });
      await Schema().create('remarks', (Table table) {
        table.id();
        table.string('body');
        table.integer('article_id');
      });
      await Schema().create('topics', (Table table) {
        table.id();
        table.string('name');
        table.softDeletes();
      });
      await Schema().create('topic_writer', (Table table) {
        table.id();
        table.integer('writer_id');
        table.integer('topic_id');
      });

      /// ada: 2 articles (1 published), topic dart
      /// bob: 1 article (not published), only a deleted topic
      /// cy: only a deleted article, topic sql
      /// dee: deleted writer with an article
      await Writer().insertMultiple(<Map<String, dynamic>>[
        <String, dynamic>{'name': 'ada'},
        <String, dynamic>{'name': 'bob'},
        <String, dynamic>{'name': 'cy'},
        <String, dynamic>{'name': 'dee'},
      ]);
      await Article().insertMultiple(<Map<String, dynamic>>[
        <String, dynamic>{'title': 'a1', 'published': true, 'writer_id': 1},
        <String, dynamic>{'title': 'a2', 'published': false, 'writer_id': 1},
        <String, dynamic>{'title': 'b1', 'published': false, 'writer_id': 2},
        <String, dynamic>{'title': 'c1', 'published': true, 'writer_id': 3},
        <String, dynamic>{'title': 'd1', 'published': true, 'writer_id': 4},
      ]);
      await Remark().insertMultiple(<Map<String, dynamic>>[
        <String, dynamic>{'body': 'x', 'article_id': 1},
        <String, dynamic>{'body': 'y', 'article_id': 1},
        <String, dynamic>{'body': 'x', 'article_id': 3},
        <String, dynamic>{'body': 'x', 'article_id': 4},
      ]);
      await Topic().insertMultiple(<Map<String, dynamic>>[
        <String, dynamic>{'name': 'dart'},
        <String, dynamic>{'name': 'sql'},
        <String, dynamic>{'name': 'old'},
      ]);
      await QueryBuilder.table('topic_writer')
          .insertMultiple(<Map<String, dynamic>>[
            <String, dynamic>{'writer_id': 1, 'topic_id': 1},
            <String, dynamic>{'writer_id': 2, 'topic_id': 3},
            <String, dynamic>{'writer_id': 3, 'topic_id': 2},
          ]);
      await Writer().where('id', 4).delete();
      await Article().where('id', 4).delete();
      await Topic().where('id', 3).delete();
    });

    test('hasMany', () async {
      expect(await writers(Writer().whereHas('articles')), <int>[1, 2]);
      expect(
        await writers(
          Writer().whereHas('articles', (QueryBuilder<dynamic> q) {
            q.where('published', true);
          }),
        ),
        <int>[1],
      );
      expect(await writers(Writer().whereDoesntHave('articles')), <int>[3]);
      expect(
        await writers(
          Writer().whereDoesntHave('articles', (QueryBuilder<dynamic> q) {
            q.where('published', true);
          }),
        ),
        <int>[2, 3],
      );
    });

    test('hasOne', () async {
      expect(await writers(Writer().whereHas('firstArticle')), <int>[1, 2]);
      expect(
        await writers(
          Writer().whereHas('firstArticle', (QueryBuilder<dynamic> q) {
            q.where('title', 'b1');
          }),
        ),
        <int>[2],
      );
      expect(await writers(Writer().whereDoesntHave('firstArticle')), <int>[3]);
    });

    test('belongsTo', () async {
      /// article 4 is deleted, article 5 belongs to a deleted writer
      expect(await articles(Article().whereHas('writer')), <int>[1, 2, 3]);
      expect(
        await articles(
          Article().whereHas('writer', (QueryBuilder<dynamic> q) {
            q.where('name', 'bob');
          }),
        ),
        <int>[3],
      );
      expect(await articles(Article().whereDoesntHave('writer')), <int>[5]);
      expect(
        await articles(
          Article().whereDoesntHave('writer', (QueryBuilder<dynamic> q) {
            q.where('name', 'ada');
          }),
        ),
        <int>[3, 5],
      );
    });

    test('manyToMany', () async {
      /// the topic of bob is deleted
      expect(await writers(Writer().whereHas('topics')), <int>[1, 3]);
      expect(
        await writers(
          Writer().whereHas('topics', (QueryBuilder<dynamic> q) {
            q.where('name', 'sql');
          }),
        ),
        <int>[3],
      );
      expect(await writers(Writer().whereDoesntHave('topics')), <int>[2]);
      expect(
        await writers(
          Writer().whereDoesntHave('topics', (QueryBuilder<dynamic> q) {
            q.where('name', 'dart');
          }),
        ),
        <int>[2, 3],
      );
    });

    test('or variants', () async {
      expect(
        await writers(
          Writer().where('name', 'cy').orWhereHas('articles', (
            QueryBuilder<dynamic> q,
          ) {
            q.where('published', true);
          }),
        ),
        <int>[1, 3],
      );
      expect(
        await writers(
          Writer().where('name', 'ada').orWhereDoesntHave('articles'),
        ),
        <int>[1, 3],
      );
      expect(
        await writers(
          Writer().where('name', 'bob').orWhereDoesntHave('topics', (
            QueryBuilder<dynamic> q,
          ) {
            q.where('name', 'dart');
          }),
        ),
        <int>[2, 3],
      );
    });

    test('where on the parent', () async {
      expect(
        await writers(Writer().where('name', 'bob').whereHas('articles')),
        <int>[2],
      );
      expect(
        await writers(Writer().where('name', 'cy').whereHas('articles')),
        <int>[],
      );
      expect(
        await writers(Writer().whereHas('articles').where('name', '!=', 'ada')),
        <int>[2],
      );
    });

    test('an OR can not show a soft deleted parent', () async {
      expect(
        await writers(Writer().where('name', 'dee').orWhereHas('articles')),
        <int>[1, 2],
      );
    });

    test('soft deleted children do not count', () async {
      /// cy has one article, and it is deleted
      expect(
        await writers(
          Writer().whereHas('articles', (QueryBuilder<dynamic> q) {
            q.where('title', 'c1');
          }),
        ),
        <int>[],
      );

      /// withTrashed in the callback counts them
      expect(
        await writers(
          Writer().whereHas('articles', (QueryBuilder<dynamic> q) {
            q.withTrashed = true;
            q.where('title', 'c1');
          }),
        ),
        <int>[3],
      );
    });

    test('two whereHas with the same column do not clash', () async {
      expect(
        await writers(
          Writer()
              .whereHas('articles', (QueryBuilder<dynamic> q) {
                q.where('title', 'a1');
              })
              .orWhereHas('articles', (QueryBuilder<dynamic> q) {
                q.where('title', 'b1');
              }),
        ),
        <int>[1, 2],
      );
      expect(
        await writers(
          Writer()
              .whereHas('articles', (QueryBuilder<dynamic> q) {
                q.where('title', 'a1');
              })
              .whereHas('articles', (QueryBuilder<dynamic> q) {
                q.where('title', 'b1');
              }),
        ),
        <int>[],
      );
    });

    test('together with withCount', () async {
      List<Writer> list = await Writer()
          .withCount('articles as published_count', (QueryBuilder<dynamic> q) {
            q.where('published', true);
          })
          .whereHas('articles', (QueryBuilder<dynamic> q) {
            q.where('published', false);
          })
          .orderBy('id')
          .get();
      expect(ids(list), <int>[1, 2]);
      expect(list[0].aggregate('published_count'), 1);
      expect(list[1].aggregate('published_count'), 0);

      list = await Writer()
          .whereHas('topics')
          .withCount('articles')
          .orderBy('id')
          .get();
      expect(ids(list), <int>[1, 3]);
      expect(list[0].countOf('articles'), 2);
      expect(list[1].countOf('articles'), 0);
    });

    test('onQuery params of the relation get the key prefix', () async {
      Writer q = Writer();
      q.whereHas('publishedArticles');
      expect(q.substitutionValues.keys, <String>['dox_has0_published_p0']);
      expect(await writers(Writer().whereHas('publishedArticles')), <int>[1]);
      expect(
        await writers(
          Writer()
              .whereHas('articles', (QueryBuilder<dynamic> q) {
                q.where('published', false);
              })
              .whereDoesntHave('publishedArticles'),
        ),
        <int>[2],
      );
    });

    test('has with a count', () async {
      expect(await writers(Writer().has('articles')), <int>[1, 2]);
      expect(await writers(Writer().has('articles', '>=', 2)), <int>[1]);
      expect(await writers(Writer().has('articles', '=', 1)), <int>[2]);
      expect(await writers(Writer().has('articles', '=', 0)), <int>[3]);
      expect(await writers(Writer().has('articles', '<', 1)), <int>[3]);
      expect(
        await writers(
          Writer().has('articles', '>', 0, (QueryBuilder<dynamic> q) {
            q.where('published', false);
          }),
        ),
        <int>[1, 2],
      );
      expect(await writers(Writer().has('topics', '=', 1)), <int>[1, 3]);
      expect(await articles(Article().has('writer', '=', 1)), <int>[1, 2, 3]);
    });

    test('nested relation names', () async {
      /// the remark of cy is on a deleted article
      expect(await writers(Writer().whereHas('articles.remarks')), <int>[1, 2]);
      expect(
        await writers(
          Writer().whereHas('articles.remarks', (QueryBuilder<dynamic> q) {
            q.where('body', 'y');
          }),
        ),
        <int>[1],
      );
      expect(await writers(Writer().whereDoesntHave('articles.remarks')), <int>[
        3,
      ]);
      expect(await writers(Writer().has('articles.remarks', '>=', 2)), <int>[
        1,
      ]);
      expect(await articles(Article().whereHas('writer.topics')), <int>[1, 2]);
    });

    test('count and paginate', () async {
      expect(await Writer().whereHas('articles').count(), 2);
      Pagination<Writer> page = await Writer()
          .whereDoesntHave('topics')
          .paginate(currentPage: 1, perPage: 10);
      expect(page.total, 1);
    });

    test('the same query gives the same sql', () {
      String sql() {
        Writer q = Writer();
        q
            .where('name', 'ada')
            .whereHas('articles', (QueryBuilder<dynamic> q) {
              q.where('published', true);
            })
            .orWhereDoesntHave('articles.remarks')
            .has('topics', '>', 1);
        return q.getWhereQuery();
      }

      String first = sql();
      expect(sql(), first);
      expect(first, contains('EXISTS (SELECT 1 FROM'));
      expect(first, contains('NOT EXISTS (SELECT 1 FROM'));
      expect(first, contains('(SELECT COUNT(*) FROM'));

      /// values are params, not sql text
      expect(first, isNot(contains('ada')));
    });

    test('bad input', () {
      expect(() => Writer().whereHas('nope'), throwsArgumentError);
      expect(() => Writer().has('articles', 'like', 1), throwsArgumentError);
      expect(
        () => Writer().has('articles', '>= 1 OR 1 =', 1),
        throwsArgumentError,
      );
      expect(
        () => QueryBuilder.table('writers').whereHas('articles'),
        throwsStateError,
      );
    });
  });

  group('whereHas on the same table |', () {
    Future<List<int?>> sections(QueryBuilder<Section> q) async {
      return ids(await q.orderBy('id').get());
    }

    setUpAll(() async {
      await Schema().dropIfExists('sections');
      await Schema().create('sections', (Table table) {
        table.id();
        table.string('name');
        table.integer('parent_id').nullable();
        table.softDeletes();
      });

      /// a > b > c, d has only a deleted child e
      await Section().insertMultiple(<Map<String, dynamic>>[
        <String, dynamic>{'name': 'a', 'parent_id': null},
        <String, dynamic>{'name': 'b', 'parent_id': 1},
        <String, dynamic>{'name': 'c', 'parent_id': 2},
        <String, dynamic>{'name': 'd', 'parent_id': null},
        <String, dynamic>{'name': 'e', 'parent_id': 4},
      ]);
      await Section().where('id', 5).delete();
    });

    test('hasMany', () async {
      expect(await sections(Section().whereHas('children')), <int>[1, 2]);
      expect(await sections(Section().whereDoesntHave('children')), <int>[
        3,
        4,
      ]);
      expect(
        await sections(
          Section().whereHas('children', (QueryBuilder<dynamic> q) {
            q.where('name', 'c');
          }),
        ),
        <int>[2],
      );
      expect(await sections(Section().has('children', '=', 0)), <int>[3, 4]);
    });

    test('belongsTo', () async {
      expect(await sections(Section().whereHas('parent')), <int>[2, 3]);
      expect(await sections(Section().whereDoesntHave('parent')), <int>[1, 4]);
      expect(
        await sections(
          Section().whereHas('parent', (QueryBuilder<dynamic> q) {
            q.where('name', 'a');
          }),
        ),
        <int>[2],
      );
    });

    test('nested relation names', () async {
      expect(await sections(Section().whereHas('children.children')), <int>[1]);
      expect(await sections(Section().whereHas('parent.parent')), <int>[3]);
    });

    test('withCount', () async {
      List<Section> list = await Section()
          .withCount('children')
          .orderBy('id')
          .get();
      expect(
        <dynamic>[for (Section s in list) s.countOf('children')],
        <int>[1, 1, 0, 0],
      );
    });
  });
}
