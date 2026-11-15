import 'dart:async';

import 'package:dox_orm/dox_orm.dart';
import 'package:dox_orm/src/types/orm_strict.dart' show StrictWatch;
import 'package:test/test.dart';

import 'connection.dart';
import 'models/artist/artist.model.dart';
import 'models/writer/writer.model.dart';

/// the strict mode warnings that [body] prints
Future<List<String>> warnings(Future<void> Function() body) async {
  List<String> out = <String>[];
  await runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      print: (Zone self, ZoneDelegate parent, Zone zone, String line) {
        if (line.contains('Strict mode')) out.add(line);
      },
    ),
  );
  return out;
}

void main() async {
  await initQueryBuilder();

  setUp(StrictWatch.reset);
  tearDown(() => SqlQueryBuilder().strict = const OrmStrict.off());

  setUpAll(() async {
    for (String t in <String>[
      'writers',
      'articles',
      'strict_rows',
      'artist',
      'artist_song',
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
    await Schema().create('strict_rows', (Table table) {
      table.id();
      table.integer('n');
    });
    await Schema().create('artist', (Table table) {
      table.id();
      table.string('name');
      table.timestamps();
    });
    await Schema().create('artist_song', (Table table) {
      table.id();
      table.string('song_id');
      table.integer('artist_id');
      table.string('role').nullable();
      table.timestamps();
    });
    await Writer().insertMultiple(<Map<String, dynamic>>[
      for (int i = 0; i < 20; i++) <String, dynamic>{'name': 'w$i'},
    ]);
    await QueryBuilder.table('strict_rows')
        .insertMultiple(<Map<String, dynamic>>[
          for (int i = 0; i < 30; i++) <String, dynamic>{'n': i},
        ]);
  });

  group('strict N+1 |', () {
    test('warns once for a loop of row by row loads', () async {
      SqlQueryBuilder().strict = const OrmStrict();
      List<Writer> list = await Writer().get();
      List<String> out = await warnings(() async {
        for (Writer w in list) {
          await w.$getRelation('articles');
        }
      });
      expect(out, hasLength(1));
      expect(out.single, contains('"articles" of Writer'));
      expect(out.single, contains('5 times'));
      expect(out.single, contains("preload('articles')"));
    });

    test('related() counts too', () async {
      SqlQueryBuilder().strict = const OrmStrict(nPlusOneCount: 3);
      List<Writer> list = await Writer().limit(5).get();
      List<String> out = await warnings(() async {
        for (Writer w in list) {
          w.related<Article>('articles');
        }
      });
      expect(out, hasLength(1));
    });

    test('write helpers are not counted', () async {
      SqlQueryBuilder().strict = const OrmStrict(nPlusOneCount: 3);
      List<Writer> list = await Writer().limit(10).get();
      Artist artist = await Artist().create(<String, dynamic>{'name': 'A'});
      List<String> out = await warnings(() async {
        for (Writer w in list) {
          await w.createRelated<Article>('articles', <String, dynamic>{
            'title': 't',
            'published': true,
          });
        }
        for (int i = 0; i < 10; i++) {
          await artist.attach('songs', <dynamic>['s$i']);
        }
      });
      expect(out, isEmpty);
    });

    test('no warning when off, under the count, or with preload', () async {
      List<Writer> list = await Writer().get();
      List<String> off = await warnings(() async {
        for (Writer w in list) {
          await w.$getRelation('articles');
        }
      });
      expect(off, isEmpty);

      SqlQueryBuilder().strict = const OrmStrict();
      List<String> few = await warnings(() async {
        for (Writer w in list.take(4)) {
          await w.$getRelation('articles');
        }
      });
      expect(few, isEmpty);

      StrictWatch.reset();
      List<String> preloaded = await warnings(() async {
        await Writer().preload('articles').get();
      });
      expect(preloaded, isEmpty);
    });
  });

  group('strict big result |', () {
    test('get() and all() warn once over the limit', () async {
      SqlQueryBuilder().strict = const OrmStrict(maxRows: 10);
      List<String> out = await warnings(() async {
        await QueryBuilder.table('strict_rows').get();
        await Writer().all();
      });
      expect(out, hasLength(2));
      expect(out[0], contains('table "strict_rows" read 30 rows'));
      expect(out[0], contains('paginate(), chunk(), lazy() or cursor()'));
      expect(out[1], contains('table "writers" read 20 rows'));
    });

    test('all() warns even with limit()', () async {
      SqlQueryBuilder().strict = const OrmStrict(maxRows: 10);
      List<String> out = await warnings(() async {
        await Writer().limit(5).all();
      });
      expect(out, hasLength(1));
    });

    test('preload of many child rows does not warn', () async {
      SqlQueryBuilder().strict = const OrmStrict(maxRows: 10);
      List<Writer> list = await Writer().limit(5).get();
      for (Writer w in list) {
        await QueryBuilder.table('articles')
            .insertMultiple(<Map<String, dynamic>>[
              for (int i = 0; i < 4; i++)
                <String, dynamic>{
                  'title': 't',
                  'published': true,
                  'writer_id': w.id,
                },
            ]);
      }
      StrictWatch.reset();
      List<String> out = await warnings(() async {
        await Writer().preload('articles').whereIn('id', <dynamic>[
          for (Writer w in list) w.id,
        ]).get();
      });
      expect(out, isEmpty);
    });

    test('no warning when off or under the limit', () async {
      List<String> off = await warnings(() async {
        await QueryBuilder.table('strict_rows').get();
      });
      expect(off, isEmpty);

      SqlQueryBuilder().strict = const OrmStrict(maxRows: 30);
      List<String> under = await warnings(() async {
        await QueryBuilder.table('strict_rows').get();
      });
      expect(under, isEmpty);
    });

    test('no warning on chunk, lazy, cursor and paginate', () async {
      SqlQueryBuilder().strict = const OrmStrict(maxRows: 10);
      List<String> out = await warnings(() async {
        await Writer().orderBy('id').chunk(20, (List<Writer> rows) => true);
        await for (Writer _ in Writer().lazy(chunkSize: 20)) {}
        await for (Writer _ in Writer().cursor(chunkSize: 20)) {}
        await Writer().paginate(currentPage: 1, perPage: 20);
      });
      expect(out, isEmpty);
    });
  });
}
