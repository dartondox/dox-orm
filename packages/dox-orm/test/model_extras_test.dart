import 'dart:convert';

import 'package:dox_orm/dox_orm.dart';
import 'package:test/test.dart';

import 'connection.dart';
import 'models/artist/artist.model.dart';
import 'models/artist_song/artist_song.model.dart';
import 'models/blog/blog.model.dart';
import 'models/blog_info/blog_info.model.dart';
import 'models/song/song.model.dart';

class _Recorder extends ModelObserver<Blog> {
  final List<ModelEvent> events = <ModelEvent>[];

  @override
  void handle(ModelEvent event, Blog model) => events.add(event);
}

String _cursor(Map<String, dynamic> data) {
  return base64Url.encode(utf8.encode(jsonEncode(data)));
}

const List<String> _tables = <String>[
  'blog',
  'blog_info',
  'artist',
  'song',
  'artist_song',
];

void main() async {
  await initQueryBuilder();

  setUp(() async {
    for (String t in _tables) {
      await Schema().dropIfExists(t);
    }
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
    await Schema().create('artist', (Table table) {
      table.id();
      table.string('name');
      table.timestamps();
    });
    await Schema().create('song', (Table table) {
      table.id();
      table.string('title');
      table.timestamps();
    });
    await Schema().create('artist_song', (Table table) {
      table.id();
      table.integer('song_id');
      table.integer('artist_id');
      table.timestamps();
    });
    await Blog().insertMultiple(<Map<String, dynamic>>[
      for (int i = 1; i <= 7; i++)
        <String, dynamic>{'title': 't$i', 'body': 'b', 'slug': 's$i'},
    ]);
  });

  tearDown(() async {
    for (String t in _tables) {
      await Schema().dropIfExists(t);
    }
  });

  List<String?> titles(List<Blog> list) => <String?>[
    for (Blog b in list) b.title,
  ];

  group('onlyTrashed |', () {
    test('gives only soft deleted rows, also with orWhere', () async {
      await Blog().where('uid', '<=', 2).delete();
      expect(await Blog().count(), 5);
      expect(await Blog().onlyTrashed().count(), 2);
      expect(titles(await Blog().onlyTrashed().orderBy('uid').get()), <String>[
        't1',
        't2',
      ]);
      expect(
        titles(
          await Blog()
              .onlyTrashed()
              .where('title', 't1')
              .orWhere('title', 't5')
              .get(),
        ),
        <String>['t1'],
      );
      expect((await Blog().onlyTrashed().find(1))?.title, 't1');
      expect(await Blog().onlyTrashed().find(3), isNull);
      expect(await Blog().find(1), isNull);
    });

    test('throws without soft deletes, so no row is deleted', () async {
      await Artist().create(<String, dynamic>{'name': 'x'});
      expect(() => Artist().onlyTrashed(), throwsStateError);
      expect(() => QueryBuilder.table('blog').onlyTrashed(), throwsStateError);
      expect(await Artist().count(), 1);
    });

    test('forceDelete only removes trashed rows', () async {
      await Blog().where('uid', 1).delete();
      expect(await Blog().onlyTrashed().forceDelete(), 1);
      expect(await Blog().withTrash().count(), 6);
    });
  });

  group('withAvg, withMin, withExists |', () {
    setUp(() async {
      await Artist().insertMultiple(<Map<String, String>>[
        <String, String>{'name': 'x'},
        <String, String>{'name': 'y'},
        <String, String>{'name': 'z'},
      ]);
      await Song().insertMultiple(<Map<String, String>>[
        <String, String>{'title': 's1'},
        <String, String>{'title': 's2'},
        <String, String>{'title': 's3'},
      ]);
      await ArtistSong().insertMultiple(<Map<String, int>>[
        <String, int>{'song_id': 1, 'artist_id': 1},
        <String, int>{'song_id': 2, 'artist_id': 1},
        <String, int>{'song_id': 3, 'artist_id': 2},
      ]);
    });

    test('manyToMany avg, min and exists', () async {
      List<Artist> artists = await Artist()
          .withAvg('songs', 'id')
          .withMin('songs', 'id')
          .withExists('songs')
          .withExists('songs as has_s3', (QueryBuilder<dynamic> q) {
            q.where('title', 's3');
          })
          .orderBy('id')
          .get();
      expect(artists[0].aggregate('songs_avg_id'), 1.5);
      expect(artists[0].aggregate('songs_min_id'), 1);
      expect(artists[0].aggregate('songs_exists'), isTrue);
      expect(artists[0].aggregate('has_s3'), isFalse);
      expect(artists[1].aggregate('has_s3'), isTrue);
      expect(artists[2].aggregate('songs_exists'), isFalse);
      expect(artists[2].aggregate('songs_avg_id'), isNull);
      expect(artists[2].aggregate('songs_min_id'), isNull);
      expect(artists[0].toJson()['songs_exists'], isTrue);
    });

    test('hasMany exists', () async {
      await BlogInfo().create(<String, dynamic>{
        'blog_id': 2,
        'info': <String, dynamic>{'n': 'a'},
      });
      List<Blog> blogs = await Blog()
          .withExists('blogInfos')
          .orderBy('uid')
          .limit(3)
          .get();
      expect(
        <dynamic>[for (Blog b in blogs) b.aggregate('blog_infos_exists')],
        <bool>[false, true, false],
      );
    });
  });

  group('simplePaginate |', () {
    test('pages without a count', () async {
      SimplePagination<Blog> one = await Blog()
          .orderBy('uid')
          .simplePaginate(currentPage: 1, perPage: 3);
      expect(titles(one.data), <String>['t1', 't2', 't3']);
      expect(one.hasMorePages, isTrue);
      expect(one.from, 1);
      expect(one.to, 3);

      SimplePagination<Blog> last = await Blog()
          .orderBy('uid')
          .simplePaginate(currentPage: 3, perPage: 3);
      expect(titles(last.data), <String>['t7']);
      expect(last.hasMorePages, isFalse);
      Map<String, dynamic> json =
          jsonDecode(jsonEncode(last)) as Map<String, dynamic>;
      expect(json['current_page'], 3);
      expect(json['from'], 7);
      expect(json['to'], 7);
      expect(json['has_more_pages'], false);
      expect((json['data'] as List<dynamic>).length, 1);

      SimplePagination<Blog> empty = await Blog().simplePaginate(
        currentPage: 9,
        perPage: 3,
      );
      expect(empty.data, isEmpty);
      expect(empty.from, isNull);
      expect(
        () => Blog().simplePaginate(currentPage: 1, perPage: 0),
        throwsArgumentError,
      );
    });
  });

  group('cursorPaginate |', () {
    test('walks forward and back by the primary key', () async {
      CursorPagination<Blog> p1 = await Blog().cursorPaginate(perPage: 3);
      expect(titles(p1.data), <String>['t1', 't2', 't3']);
      expect(p1.prevCursor, isNull);
      expect(p1.nextCursor, isNotNull);

      CursorPagination<Blog> p2 = await Blog().cursorPaginate(
        perPage: 3,
        cursor: p1.nextCursor,
      );
      expect(titles(p2.data), <String>['t4', 't5', 't6']);
      expect(p2.prevCursor, isNotNull);

      CursorPagination<Blog> p3 = await Blog().cursorPaginate(
        perPage: 3,
        cursor: p2.nextCursor,
      );
      expect(titles(p3.data), <String>['t7']);
      expect(p3.nextCursor, isNull);

      CursorPagination<Blog> back = await Blog().cursorPaginate(
        perPage: 3,
        cursor: p3.prevCursor,
      );
      expect(titles(back.data), <String>['t4', 't5', 't6']);
      expect(back.nextCursor, isNotNull);
      expect(back.prevCursor, isNotNull);

      CursorPagination<Blog> first = await Blog().cursorPaginate(
        perPage: 3,
        cursor: back.prevCursor,
      );
      expect(titles(first.data), <String>['t1', 't2', 't3']);
      expect(first.prevCursor, isNull);
      expect(first.nextCursor, isNotNull);

      Map<String, dynamic> json =
          jsonDecode(jsonEncode(p2)) as Map<String, dynamic>;
      expect(json.keys, <String>[
        'per_page',
        'next_cursor',
        'prev_cursor',
        'data',
      ]);
    });

    test('desc, other column, where with OR', () async {
      CursorPagination<Blog> p1 = await Blog()
          .where('title', 't1')
          .orWhere('title', 't6')
          .orWhere('title', 't7')
          .cursorPaginate(perPage: 2, column: 'slug', direction: 'desc');
      expect(titles(p1.data), <String>['t7', 't6']);
      CursorPagination<Blog> p2 = await Blog()
          .where('title', 't1')
          .orWhere('title', 't6')
          .orWhere('title', 't7')
          .cursorPaginate(
            perPage: 2,
            column: 'slug',
            direction: 'desc',
            cursor: p1.nextCursor,
          );
      expect(titles(p2.data), <String>['t1']);
      expect(p2.nextCursor, isNull);
    });

    test('works with a date column', () async {
      for (int i = 1; i <= 7; i++) {
        await Blog().where('uid', i).update(<String, dynamic>{
          'created_at': DateTime.utc(2020, 1, 10 - i, 8, 30),
        });
      }
      CursorPagination<Blog> p1 = await Blog().cursorPaginate(
        perPage: 2,
        column: 'created_at',
      );
      expect(titles(p1.data), <String>['t7', 't6']);
      CursorPagination<Blog> p2 = await Blog().cursorPaginate(
        perPage: 2,
        column: 'created_at',
        cursor: p1.nextCursor,
      );
      expect(titles(p2.data), <String>['t5', 't4']);
      CursorPagination<Blog> back = await Blog().cursorPaginate(
        perPage: 2,
        column: 'created_at',
        cursor: p2.prevCursor,
      );
      expect(titles(back.data), <String>['t7', 't6']);
    });

    test('a bad cursor gives the first page', () async {
      for (String? c in <String?>[
        'not base64 !!',
        _cursor(<String, dynamic>{'c': 'uid'}),
        base64Url.encode(utf8.encode('[1,2]')),
        _cursor(<String, dynamic>{
          'c': <String>['title'],
          'v': <int>[1],
          't': 'n',
          'n': true,
        }),
        _cursor(<String, dynamic>{
          'c': <String>['uid'],
          'v': <dynamic>[
            <int>[1],
          ],
          't': 'n',
          'n': true,
        }),
        // a text, a date, and a SQL text for an int column: on Postgres
        // a "data exception", on the others a value of the wrong kind
        for (String t in <String>['s', 'd'])
          for (String v in <String>['abc', '2020-01-01', '1; DROP TABLE blog'])
            _cursor(<String, dynamic>{
              'c': <String>['uid'],
              'v': <String>[v],
              't': t,
              'n': true,
            }),
        'a' * 2000,
      ]) {
        CursorPagination<Blog> p = await Blog().cursorPaginate(
          perPage: 2,
          cursor: c,
        );
        expect(titles(p.data), <String>['t1', 't2'], reason: '$c');
        expect(p.prevCursor, isNull);
      }
      expect(await Blog().count(), 7);
    });

    test('a bad cursor in a transaction keeps the transaction', () async {
      String bad = _cursor(<String, dynamic>{
        'c': <String>['uid'],
        'v': <String>['abc'],
        't': 's',
        'n': true,
      });
      await QueryBuilder.transaction(() async {
        CursorPagination<Blog> p = await Blog().cursorPaginate(
          perPage: 2,
          cursor: bad,
        );
        expect(titles(p.data), <String>['t1', 't2']);
        expect(await Blog().count(), 7);
      });
    });

    /// reads every page forward, then every page back from the end
    Future<void> walk(
      QueryBuilder<Blog> Function() query,
      List<String> expected,
    ) async {
      List<String?> seen = <String?>[];
      List<String?> cursors = <String?>[null];
      CursorPagination<Blog> page;
      do {
        page = await query().cursorPaginate(perPage: 2, cursor: cursors.last);
        seen.addAll(titles(page.data));
        cursors.add(page.nextCursor);
      } while (page.nextCursor != null);
      expect(seen, expected);

      List<String?> back = titles(page.data);
      while (page.prevCursor != null) {
        page = await query().cursorPaginate(
          perPage: 2,
          cursor: page.prevCursor,
        );
        back.insertAll(0, titles(page.data));
      }
      expect(back, expected);
    }

    test('ties on a column that is not unique are not skipped', () async {
      for (int i = 1; i <= 7; i++) {
        await Blog().where('uid', i).update(<String, dynamic>{
          'status': i.isEven ? 'b' : 'a',
        });
      }
      await walk(() => Blog().orderBy('status', 'desc'), <String>[
        't2',
        't4',
        't6',
        't1',
        't3',
        't5',
        't7',
      ]);
      await walk(
        () => Blog().orderBy('status').orderBy('uid', 'desc'),
        <String>['t7', 't5', 't3', 't1', 't6', 't4', 't2'],
      );
      await walk(
        () => Blog().where('uid', '>', 1).orderBy('status').orderBy('slug'),
        <String>['t3', 't5', 't7', 't2', 't4', 't6'],
      );
    });

    test('checks its input', () async {
      expect(
        () => Blog().orderBy('uid').cursorPaginate(perPage: 2, column: 'uid'),
        throwsStateError,
      );
      expect(
        () => Blog().orderByRaw('uid').cursorPaginate(perPage: 2),
        throwsStateError,
      );
      expect(
        () => Blog().cursorPaginate(perPage: 2, direction: 'up'),
        throwsArgumentError,
      );
      expect(() => Blog().cursorPaginate(perPage: 0), throwsArgumentError);
    });
  });

  group('touch |', () {
    test('a model sets updated_at of its row only', () async {
      DateTime old = DateTime.utc(2020);
      await Blog().where('uid', '>', 0).update(<String, dynamic>{
        'updated_at': old,
      });
      Blog blog = (await Blog().find(1))!;
      expect(await blog.touch(), 1);
      expect(blog.updatedAt!.isAfter(old), isTrue);
      Blog fresh = (await Blog().find(1))!;
      expect(fresh.updatedAt!.year, isNot(2020));
      expect((await Blog().find(2))!.updatedAt!.year, 2020);

      /// save() after touch() sends nothing
      expect(await Blog().where('updated_at', '>', old).count(), 1);
    });

    test('a model fires the save events, touchQuietly() does not', () async {
      _Recorder recorder = _Recorder();
      Model.observe<Blog>(recorder);
      addTearDown(Model.forgetObservers<Blog>);
      Blog blog = (await Blog().find(1))!;
      expect(await blog.touch(), 1);
      expect(recorder.events, <ModelEvent>[
        ModelEvent.saving,
        ModelEvent.updating,
        ModelEvent.updated,
        ModelEvent.saved,
      ]);
      recorder.events.clear();

      /// mysql counts a row as changed only when its value changes
      await Blog().where('uid', '>', 0).update(<String, dynamic>{
        'updated_at': DateTime.utc(2020),
      });
      expect(await blog.touchQuietly(), 1);
      expect(await Blog().where('uid', 2).touch(), 1);
      expect(recorder.events, isEmpty);
    });

    test('a query touches its rows, and another column', () async {
      DateTime old = DateTime.utc(2020);
      await Blog().where('uid', '>', 0).update(<String, dynamic>{
        'updated_at': old,
        'created_at': old,
      });
      expect(await Blog().where('uid', '<=', 3).touch(), 3);
      expect(await Blog().where('updated_at', '>', old).count(), 3);
      Blog blog = (await Blog().find(5))!;
      expect(await blog.touch('created_at'), 1);
      expect(blog.createdAt!.isAfter(old), isTrue);
      expect(await Blog().where('created_at', '>', old).count(), 1);
    });
  });

  group('replicate |', () {
    test('copies the columns, not the key or timestamps', () async {
      Blog blog = (await Blog().find(2))!;
      Blog copy = blog.replicate();
      expect(copy.exists, isFalse);
      expect(copy.uid, isNull);
      expect(copy.createdAt, isNull);
      expect(copy.title, 't2');
      expect(copy.slug, 's2');
      copy.title = 'copy';
      await copy.save();
      expect(copy.uid, 8);
      expect((await Blog().find(8))!.slug, 's2');
      expect((await Blog().find(2))!.title, 't2');

      Blog other = blog.replicate(<String>['slug']);
      expect(other.slug, isNull);
      expect(other.title, 't2');
      expect(() => blog.replicate(<String>['nope']), throwsArgumentError);
    });
  });
}
