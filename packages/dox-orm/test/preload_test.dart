import 'package:dox_orm/dox_orm.dart';
import 'package:test/test.dart';

import 'connection.dart';
import 'models/writer/writer.model.dart';

void main() async {
  await initQueryBuilder();

  /// the sql of each query that runs, so a test can count them
  List<String> queries = <String>[];
  void onQuery(QueryEvent e) => queries.add(e.sql);

  setUp(() {
    queries.clear();
    SqlQueryBuilder().listen(onQuery);
  });

  tearDown(() {
    SqlQueryBuilder().removeListener(onQuery);
    SqlQueryBuilder().flags = const OrmFlags();
  });

  group('preload |', () {
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

      /// ada: a1 (published, remarks x and y), a2
      /// bob: b1 (published, remark z)
      await Writer().insertMultiple(<Map<String, dynamic>>[
        <String, dynamic>{'name': 'ada'},
        <String, dynamic>{'name': 'bob'},
      ]);
      await Article().insertMultiple(<Map<String, dynamic>>[
        <String, dynamic>{'title': 'a1', 'published': true, 'writer_id': 1},
        <String, dynamic>{'title': 'a2', 'published': false, 'writer_id': 1},
        <String, dynamic>{'title': 'b1', 'published': true, 'writer_id': 2},
      ]);
      await Remark().insertMultiple(<Map<String, dynamic>>[
        <String, dynamic>{'body': 'x', 'article_id': 1},
        <String, dynamic>{'body': 'y', 'article_id': 1},
        <String, dynamic>{'body': 'z', 'article_id': 3},
      ]);
      await Topic().insertMultiple(<Map<String, dynamic>>[
        <String, dynamic>{'name': 'dart'},
        <String, dynamic>{'name': 'sql'},
      ]);
      await QueryBuilder.table('topic_writer')
          .insertMultiple(<Map<String, dynamic>>[
            <String, dynamic>{'writer_id': 1, 'topic_id': 1},
            <String, dynamic>{'writer_id': 2, 'topic_id': 2},
          ]);
    });

    test('a dot path loads each level with one query', () async {
      queries.clear();
      List<Writer> list = await Writer()
          .preload('articles.remarks')
          .orderBy('id')
          .get();
      expect(queries.length, 3);
      expect(list[0].articles.map((Article a) => a.title), <String>[
        'a1',
        'a2',
      ]);
      expect(list[0].articles[0].remarks.map((Remark r) => r.body), <String>[
        'x',
        'y',
      ]);
      expect(list[0].articles[1].remarks, isEmpty);
      expect(list[1].articles[0].remarks.single.body, 'z');

      Map<String, dynamic> json = list[0].toJson();
      List<dynamic> articles = json['articles'] as List<dynamic>;
      expect((articles[0] as Map<String, dynamic>)['remarks'], hasLength(2));
    });

    test('three levels, with a belongsTo and a manyToMany', () async {
      queries.clear();
      Article? a = await Article()
          .preload('writer.topics')
          .preload('writer.articles.remarks')
          .find(3);
      expect(queries.length, 5);
      expect(a!.writer!.name, 'bob');
      expect(a.writer!.topics.single.name, 'sql');
      expect(a.writer!.articles.single.remarks.single.body, 'z');
      Map<String, dynamic> writer =
          a.toJson()['writer'] as Map<String, dynamic>;
      expect(writer['topics'], hasLength(1));
      expect(writer['articles'], hasLength(1));
    });

    test('a plain name and a path of it load the relation once', () async {
      queries.clear();
      Writer? w = await Writer()
          .preload('articles')
          .preload('articles.remarks')
          .find(1);
      expect(queries.length, 3);
      expect(w!.articles[0].remarks, hasLength(2));
    });

    test('reload() of a row loads the paths again', () async {
      Writer? w = await Writer().preload('articles.remarks').find(1);
      w!.articles = <Article>[];
      await w.reload();
      expect(w.articles[0].remarks, hasLength(2));
    });
    test('a where on the relation query', () async {
      List<Writer> list = await Writer()
          .preload('articles', (QueryBuilder<dynamic> q) {
            q.where('published', true);
          })
          .orderBy('id')
          .get();
      expect(list[0].articles.map((Article a) => a.title), <String>['a1']);
      expect(list[1].articles.map((Article a) => a.title), <String>['b1']);
      expect(list[0].toJson()['articles'], hasLength(1));
    });

    test('a where on a dot path is for the last relation', () async {
      Writer? w = await Writer()
          .preload('articles.remarks', (QueryBuilder<dynamic> q) {
            q.where('body', 'y');
          })
          .find(1);
      expect(w!.articles, hasLength(2));
      expect(w.articles[0].remarks.single.body, 'y');
    });

    test('a where and a dot path on the same relation', () async {
      queries.clear();
      Writer? w = await Writer()
          .preload('articles', (QueryBuilder<dynamic> q) {
            q.where('published', true);
          })
          .preload('articles.remarks')
          .find(1);
      expect(queries.length, 3);
      expect(w!.articles.single.remarks, hasLength(2));
    });

    test('a where on a manyToMany and a belongsTo', () async {
      List<Writer> list = await Writer()
          .preload('topics', (QueryBuilder<dynamic> q) {
            q.where('name', 'sql');
          })
          .orderBy('id')
          .get();
      expect(list[0].topics, isEmpty);
      expect(list[1].topics.single.name, 'sql');

      Article? a = await Article()
          .preload('writer', (QueryBuilder<dynamic> q) {
            q.where('name', 'nobody');
          })
          .find(1);
      expect(a!.writer, isNull);
    });

    test('reload() of a row keeps the where', () async {
      Writer? w = await Writer()
          .preload('articles', (QueryBuilder<dynamic> q) {
            q.where('published', true);
          })
          .find(1);
      await w!.reload();
      expect(w.articles.single.title, 'a1');
    });
    test('preloadUnknownThrows off: an unknown name loads nothing', () async {
      Writer? w = await Writer().preload('typo').find(1);
      expect(w!.name, 'ada');
      w = await Writer().preload('articles.typo').find(1);
      expect(w!.articles, hasLength(2));
    });

    test('preloadUnknownThrows on: an unknown name throws', () async {
      SqlQueryBuilder().flags = const OrmFlags.all();
      Matcher unknown(String name) => throwsA(
        isA<ArgumentError>().having(
          (ArgumentError e) => e.invalidValue,
          'name',
          name,
        ),
      );
      await expectLater(Writer().preload('typo').find(1), unknown('typo'));
      await expectLater(
        Writer().preload('articles.typo').find(1),
        unknown('typo'),
      );
      await expectLater(
        Writer().preload('articles.remarks.typo').get(),
        unknown('typo'),
      );
      Writer? w = await Writer().preload('articles.remarks').find(1);
      expect(w!.articles[0].remarks, hasLength(2));
    });
    test(
      'toJsonLoadedRelations off: \$getRelation() is not in toJson',
      () async {
        Writer w = (await Writer().find(1))!;
        await w.$getRelation<dynamic>('articles');
        expect(w.articles, hasLength(2));
        expect(w.toJson().containsKey('articles'), isFalse);
      },
    );

    test('toJsonLoadedRelations on: \$getRelation() is in toJson', () async {
      SqlQueryBuilder().flags = const OrmFlags.all();
      Writer w = (await Writer().find(1))!;
      expect(w.toJson().containsKey('articles'), isFalse);
      await w.$getRelation<dynamic>('articles');
      await w.$getRelation<dynamic>('articles');
      await w.$getRelation<dynamic>('typo');
      expect(w.toJson()['articles'], hasLength(2));
      expect(w.toJson().containsKey('topics'), isFalse);

      /// reload() loads it again
      w.articles = <Article>[];
      await w.reload();
      expect(w.articles, hasLength(2));

      /// hidden still leaves it out
      w.hidden = <String>['articles'];
      expect(w.toJson().containsKey('articles'), isFalse);
    });
  });
}
