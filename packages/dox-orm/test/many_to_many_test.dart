import 'dart:io';

import 'package:dox_orm/dox_orm.dart';
import 'package:dox_orm/src/relationships/pivot_ids.dart';
import 'package:test/test.dart';

import 'connection.dart';
import 'models/artist/artist.model.dart';
import 'models/artist_song/artist_song.model.dart';
import 'models/song/song.model.dart';

void main() async {
  await initQueryBuilder();

  group('Many To Many |', () {
    setUp(() async {
      await Schema().dropIfExists('artist');
      await Schema().dropIfExists('song');
      await Schema().dropIfExists('artist_song');
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
        table.string('role').nullable();
        table.timestamps();
      });
    });

    test('Many to Many', () async {
      await Artist().insertMultiple(<Map<String, String>>[
        <String, String>{'name': "Arijit Singh"},
        <String, String>{'name': "Naw Naw"},
        <String, String>{'name': "Lay Phy"},
      ]);

      await Song().insertMultiple(<Map<String, String>>[
        <String, String>{'title': "Tum hi ho"},
        <String, String>{'title': "Di Lo Nya Tine"},
        <String, String>{'title': "Aein Mat"},
      ]);

      await ArtistSong().insertMultiple(<Map<String, String>>[
        <String, String>{'song_id': '1', 'artist_id': '1'},
        <String, String>{'song_id': '2', 'artist_id': '1'},
        <String, String>{'song_id': '2', 'artist_id': '2'},
        <String, String>{'song_id': '3', 'artist_id': '2'},
        <String, String>{'song_id': '2', 'artist_id': '3'},
        <String, String>{'song_id': '1', 'artist_id': '3'},
      ]);

      Artist? artist = await Artist().preload('songs').find(1);

      expect(artist?.songs.length, 2);
      expect(artist?.songs.map((Song e) => e.id).toList(), <int>[1, 2]);

      Song? song = await Song().preload('artists').find(2);

      expect(song?.artists.length, 3);
      expect(song?.artists.map((Artist e) => e.id).toList(), <int>[1, 2, 3]);
    });

    group('writes |', () {
      late Artist artist;

      setUp(() async {
        artist = await Artist().create(<String, dynamic>{'name': 'A'});
        await Song().insertMultiple(<Map<String, String>>[
          <String, String>{'title': 'one'},
          <String, String>{'title': 'two'},
          <String, String>{'title': 'three'},
        ]);
      });

      Future<List<int>> songIds() async {
        Artist? a = await Artist().preload('songs').find(artist.id);
        return a!.songs.map((Song s) => s.id!).toList()..sort();
      }

      test('attach one id, a list, a model and a map', () async {
        await artist.attach('songs', 1);
        expect(await songIds(), <int>[1]);

        Song three = (await Song().find(3))!;
        await artist.attach(
          'songs',
          <dynamic>[2, three],
          <String, dynamic>{'role': 'singer'},
        );
        expect(await songIds(), <int>[1, 2, 3]);

        await artist.detach('songs');
        await artist.attach('songs', <int, Map<String, dynamic>>{
          1: <String, dynamic>{'role': 'writer'},
          2: <String, dynamic>{},
        });
        Artist? a = await Artist().preload('songs').find(artist.id);
        Map<int, dynamic> roles = <int, dynamic>{
          for (Song s in a!.songs) s.id!: s.pivot['role'],
        };
        expect(roles, <int, dynamic>{1: 'writer', 2: null});
      });

      test('pivot has the keys, extra columns and timestamps', () async {
        await artist.attach('songs', 2, <String, dynamic>{'role': 'singer'});
        Artist? a = await Artist().preload('songs').find(artist.id);
        Map<String, dynamic> pivot = a!.songs.first.pivot;
        expect(pivot['artist_id'].toString(), '${artist.id}');
        expect(pivot['song_id'].toString(), '2');
        expect(pivot['role'], 'singer');
        expect(pivot['created_at'], isNotNull);
        expect(pivot['updated_at'], isNotNull);

        /// a relation without withPivot reads only the keys
        Song? song = await Song().preload('artists').find(2);
        expect(song!.artists.first.pivot.keys.toSet(), <String>{
          'artist_id',
          'song_id',
        });

        /// a model not read by a many to many relation has no pivot
        expect((await Song().find(2))!.pivot, isEmpty);
      });

      test('a plain relation selects the same columns as before', () async {
        await artist.attach('songs', 1);
        Song? song = await Song().preload('artists').find(1);

        /// pivot still has both keys, made without more SQL
        Map<String, dynamic> pivot = song!.artists.first.pivot;
        expect('${pivot['artist_id']}', '${artist.id}');
        expect('${pivot['song_id']}', '1');

        expect(song.artists.first.toMap(original: true).keys.toSet(), <String>{
          'id',
          'name',
          'created_at',
          'updated_at',
          '_owner_id',
        });

        /// the same select as before the pivot columns came
        Song one = (await Song().find(1))!;
        String sql = one.related<Artist>('artists')!.toSql();
        String w(String n) => Artist().helper.wrap(n);
        expect(
          sql,
          contains(
            'SELECT ${w('artist.*')},'
            '${w('artist_song.song_id as _owner_id')} FROM',
          ),
        );
      });

      test('related().get() rows have the two pivot keys too', () async {
        await artist.attach('songs', 2, <String, dynamic>{'role': 'singer'});
        List<Song> songs = await artist.related<Song>('songs')!.get();
        expect(songs.first.pivot['role'], 'singer');
        expect('${songs.first.pivot['artist_id']}', '${artist.id}');
        expect('${songs.first.pivot['song_id']}', '2');

        Song? first = await artist.related<Song>('songs')!.getFirst();
        expect('${first!.pivot['song_id']}', '2');
      });

      test('a new query made from a loaded row has no pivot', () async {
        await artist.attach('songs', <int>[1, 2]);
        Song s = (await Artist().preload('songs').find(artist.id))!.songs.first;
        expect(s.pivot, isNotEmpty);
        List<Song> rows = await s.where('id', 3).get();
        expect(rows.first.pivot, isEmpty);
      });

      /// an untyped map literal like `{1: {'role': 'singer'}, 2: {}}` has
      /// `Map<dynamic, dynamic>` values. The lint wants types, so the test
      /// writes that type.
      test('untyped map literals work', () async {
        await artist.attach('songs', <dynamic, dynamic>{
          1: <dynamic, dynamic>{'role': 'singer'},
          2: <dynamic, dynamic>{},
        });
        Artist? a = await Artist().preload('songs').find(artist.id);
        expect(
          a!.songs.firstWhere((Song s) => s.id == 1).pivot['role'],
          'singer',
        );

        PivotSyncResult r = await artist.sync('songs', <dynamic, dynamic>{
          1: <dynamic, dynamic>{'role': 'bass'},
          3: <dynamic, dynamic>{},
        });
        expect(r.updated, <int>[1]);
        expect(r.attached, <int>[3]);

        r = await artist.syncWithoutDetaching('songs', <dynamic, dynamic>{
          2: <dynamic, dynamic>{'role': 'drums'},
        });
        expect(r.attached, <int>[2]);

        r = await artist.toggle('songs', <dynamic, dynamic>{
          2: <dynamic, dynamic>{},
          1: <dynamic, dynamic>{'role': 'x'},
        });
        expect(r.detached, <int>[2, 1]);
      });

      test('null ids are no ids, like Laravel', () async {
        await artist.attach('songs', null);
        await artist.attach('songs', <dynamic>[null, 1]);
        await artist.attach('songs', <dynamic, dynamic>{null: null, 2: null});
        await artist.attach('songs', Song()); // a model without an id
        expect(await songIds(), <int>[1, 2]);
        expect(await artist.detach('songs', <dynamic>[null]), 0);
        expect(await songIds(), <int>[1, 2]);

        PivotSyncResult r = await artist.toggle('songs', null);
        expect(r.attached, isEmpty);
        expect(r.detached, isEmpty);

        /// sync(null) is sync([]): it detaches all and throws nothing
        r = await artist.sync('songs', null);
        expect(r.detached.length, 2);
        expect(r.attached, isEmpty);
        expect(await songIds(), <int>[]);
      });

      test('sync with a null id or an unsaved model throws first', () async {
        await artist.attach('songs', <int>[2, 3]);
        expect(
          () => artist.sync('songs', <dynamic>[null]),
          throwsA(isA<ArgumentError>()),
        );
        expect(
          () => artist.sync('songs', <dynamic>[1, Song()..title = 'new']),
          throwsA(isA<ArgumentError>()),
        );
        expect(await songIds(), <int>[2, 3]);

        /// without detaching nothing is lost, so it is skipped
        await artist.syncWithoutDetaching('songs', <dynamic>[null, 1]);
        expect(await songIds(), <int>[1, 2, 3]);
      });

      test('a failed insert keeps the old links', () async {
        await artist.attach('songs', <int>[2, 3]);
        await expectLater(
          artist.sync('songs', <int, Map<String, dynamic>>{
            4: <String, dynamic>{'nope': 1},
          }),
          throwsA(anything),
        );
        expect(await songIds(), <int>[2, 3]);

        await expectLater(
          artist.toggle('songs', <int, Map<String, dynamic>>{
            2: <String, dynamic>{},
            4: <String, dynamic>{'nope': 1},
          }),
          throwsA(anything),
        );
        expect(await songIds(), <int>[2, 3]);
      });

      test('result ids have one type', () async {
        await artist.attach('songs', <int>[1, 2]);
        PivotSyncResult r = await artist.sync('songs', <dynamic>['2', '3']);
        expect(r.attached, <int>[3]);
        expect(r.detached, <int>[1]);
      });

      test('ids match by value, like the database', () async {
        await artist.attach('songs', <int>[1, 2]);
        PivotSyncResult r = await artist.sync('songs', <dynamic>['01', 2]);
        expect(r.attached, isEmpty);
        expect(r.detached, isEmpty);
        expect(await songIds(), <int>[1, 2]);

        r = await artist.sync('songs', <dynamic>[1.0, 2]);
        expect(r.attached, isEmpty);
        expect(r.detached, isEmpty);
        expect(await songIds(), <int>[1, 2]);

        /// '01' is song 1, so toggle removes it, no second row
        r = await artist.toggle('songs', <dynamic>['01']);
        expect(r.detached, <int>[1]);
        expect(r.attached, isEmpty);
        expect(await songIds(), <int>[2]);
        r = await artist.toggle('songs', <dynamic>['01', 1]);
        expect(r.attached.length, 1);
        List<Map<String, dynamic>> rows = await QueryBuilder.table(
          'artist_song',
        ).where('artist_id', artist.id).get();
        expect(rows.length, 2);
      });

      test('every write matches ids the same way', () async {
        Future<int> rowCount() async => (await QueryBuilder.table(
          'artist_song',
        ).where('artist_id', artist.id).get()).length;

        /// attach keeps one of `1`, `'01'` and `1.0`
        await artist.attach('songs', <dynamic>[1, '01', 1.0, 2.0]);
        expect(await rowCount(), 2);
        expect(await songIds(), <int>[1, 2]);

        /// a whole double works on every database, Postgres too
        expect(
          await artist.updateExistingPivot(
            'songs',
            <dynamic>[2.0],
            <String, dynamic>{'role': 'bass'},
          ),
          1,
        );
        expect(await artist.detach('songs', <dynamic>[2.0]), 1);
        expect(await songIds(), <int>[1]);
        expect(await artist.detach('songs', <dynamic>['01']), 1);
        expect(await songIds(), <int>[]);

        /// a whole double is an int in the result. A text id stays text
        /// unless it is the plain text of an int, so `'01'` stays `'01'`
        /// (it could be a text key)
        PivotSyncResult r = await artist.sync('songs', <dynamic>['01', 2.0]);
        expect(r.attached, <dynamic>['01', 2]);
        expect(await songIds(), <int>[1, 2]);

        /// a stored number key matches a text of the same number
        r = await artist.toggle('songs', <dynamic>['03', '02']);
        expect(r.attached, <dynamic>['03']);
        expect(r.detached, <int>[2]);
        expect(await songIds(), <int>[1, 3]);
      });

      test('a number text is song 1 on a number key', () async {
        for (String text in <String>[
          '+1',
          '1.0',
          '1.',
          '1e0',
          '1E0',
          '0x1',
          ' 01 ',
        ]) {
          await artist.detach('songs');
          await artist.attach('songs', 1, <String, dynamic>{'role': 'bass'});

          /// sync keeps the row and its role
          PivotSyncResult r = await artist.sync('songs', <dynamic>[text]);
          expect(r.attached, isEmpty, reason: text);
          expect(r.detached, isEmpty, reason: text);
          List<Map<String, dynamic>> rows = await QueryBuilder.table(
            'artist_song',
          ).where('artist_id', artist.id).get();
          expect(rows.single['role'], 'bass', reason: text);

          /// attach with the same id keeps one id
          await artist.detach('songs');
          await artist.attach('songs', <dynamic>[1, text]);
          expect(await songIds(), <int>[1], reason: text);

          /// toggle removes the link
          r = await artist.toggle('songs', <dynamic>[text]);
          expect(r.detached, <int>[1], reason: text);
          expect(await songIds(), <int>[], reason: text);

          /// a second sync and syncWithoutDetaching keep one row
          await artist.attach('songs', 1);
          await artist.sync('songs', <dynamic>[text]);
          r = await artist.syncWithoutDetaching('songs', <dynamic>[text]);
          expect(r.attached, isEmpty, reason: text);
          expect(await songIds(), <int>[1], reason: text);
        }

        /// detach sends the text as it is, and the database reads it.
        /// Each database reads other texts, so this checks '+1' only.
        expect(await artist.detach('songs', <dynamic>['+1']), 1);
        expect(await songIds(), <int>[]);
      });

      test('toggle detaches a row once', () async {
        await artist.attach('songs', 1);
        PivotSyncResult r = await artist.toggle('songs', <dynamic>['1', '01']);
        expect(r.detached, <int>[1]);
        expect(r.attached, isEmpty);
        expect(await songIds(), <int>[]);
      });

      test(
        'a stored 1.5 keeps its link on SQLite',
        () async {
          /// SQLite keeps the text '1.5' as 1.5 in an integer column
          await QueryBuilder.table(
            'artist_song',
          ).insert(<String, dynamic>{'artist_id': artist.id, 'song_id': '1.5'});
          PivotSyncResult r = await artist.sync('songs', <dynamic>['1.5']);
          expect(r.attached, isEmpty);
          expect(r.detached, isEmpty);
        },
        skip: Platform.environment['DRIVER'] == 'sqlite'
            ? false
            : 'only SQLite keeps 1.5 in an integer column',
      );

      test('a number id with spaces is the same id', () async {
        await artist.attach('songs', <dynamic>[1, 3]);
        await artist.updateExistingPivot('songs', 3, <String, dynamic>{
          'role': 'bass',
        });

        /// sync keeps the row of 3 and its role
        PivotSyncResult r = await artist.sync('songs', <dynamic>[1, ' 3 ']);
        expect(r.attached, isEmpty);
        expect(r.detached, isEmpty);
        List<Map<String, dynamic>> rows = await QueryBuilder.table(
          'artist_song',
        ).where('artist_id', artist.id).where('song_id', 3).get();
        expect(rows.single['role'], 'bass');

        /// toggle removes the link, it does not add a second row
        r = await artist.toggle('songs', <dynamic>[' 1']);
        expect(r.detached, <int>[1]);
        expect(r.attached, isEmpty);
        expect(await songIds(), <int>[3]);
      });

      test('detach(null) deletes nothing, detach() deletes all', () async {
        await artist.attach('songs', <int>[1, 2]);
        expect(await artist.detach('songs', null), 0);
        expect(await songIds(), <int>[1, 2]);
        expect(await artist.detach('songs'), 2);
        expect(await songIds(), <int>[]);
      });

      test('an id is kept once', () async {
        await artist.attach('songs', <dynamic>[1, 1, '1', 2]);
        List<Map<String, dynamic>> rows = await QueryBuilder.table(
          'artist_song',
        ).where('artist_id', artist.id).get();
        expect(rows.length, 2);

        PivotSyncResult r = await artist.sync('songs', <dynamic>[3, '3', 3]);
        expect(r.attached, <int>[3]);
        expect(await songIds(), <int>[3]);
      });

      test('sync compares pivot values by type', () async {
        await artist.attach('songs', 1, <String, dynamic>{'role': '1'});
        PivotSyncResult r = await artist.sync(
          'songs',
          <int, Map<String, dynamic>>{
            1: <String, dynamic>{'role': 1},
          },
        );
        expect(r.updated, isEmpty);
        r = await artist.sync('songs', <int, Map<String, dynamic>>{
          1: <String, dynamic>{'role': true},
        });
        expect(r.updated, isEmpty);
        r = await artist.sync('songs', <int, Map<String, dynamic>>{
          1: <String, dynamic>{'role': 'x'},
        });
        expect(r.updated, <int>[1]);
      });

      test('detach some ids or all', () async {
        await artist.attach('songs', <int>[1, 2, 3]);
        expect(await artist.detach('songs', <int>[1, 3]), 2);
        expect(await songIds(), <int>[2]);
        expect(await artist.detach('songs'), 1);
        expect(await songIds(), <int>[]);
        expect(await artist.detach('songs', <int>[]), 0);
      });

      test('sync returns attached, detached and updated ids', () async {
        await artist.attach('songs', <int>[1, 2]);
        PivotSyncResult r = await artist.sync('songs', <int>[2, 3]);
        expect(r.attached, <int>[3]);
        expect(r.detached, <int>[1]);
        expect(r.updated, isEmpty);
        expect(await songIds(), <int>[2, 3]);

        r = await artist.sync('songs', <int, Map<String, dynamic>>{
          2: <String, dynamic>{'role': 'singer'},
          3: <String, dynamic>{},
        });
        expect(r.attached, isEmpty);
        expect(r.detached, isEmpty);
        expect(r.updated, <int>[2]);

        /// the same values again do not count as updated
        r = await artist.sync('songs', <int, Map<String, dynamic>>{
          2: <String, dynamic>{'role': 'singer'},
          3: <String, dynamic>{},
        });
        expect(r.updated, isEmpty);

        r = await artist.syncWithoutDetaching('songs', <int>[1]);
        expect(r.attached, <int>[1]);
        expect(r.detached, isEmpty);
        expect(await songIds(), <int>[1, 2, 3]);

        r = await artist.sync('songs', <int>[]);
        expect(r.detached.length, 3);
        expect(await songIds(), <int>[]);
      });

      test('toggle', () async {
        await artist.attach('songs', <int>[1, 2]);
        PivotSyncResult r = await artist.toggle('songs', <int>[2, 3]);
        expect(r.attached, <int>[3]);
        expect(r.detached, <int>[2]);
        expect(await songIds(), <int>[1, 3]);
      });

      test('updateExistingPivot with a list', () async {
        await artist.attach('songs', <int>[1, 2, 3]);
        expect(
          await artist.updateExistingPivot(
            'songs',
            <int>[1, 2],
            <String, dynamic>{'role': 'bass'},
          ),
          2,
        );
        Artist? a = await Artist().preload('songs').find(artist.id);
        expect(a!.songs.where((Song s) => s.pivot['role'] == 'bass').length, 2);
      });

      test('updateExistingPivot', () async {
        await artist.attach('songs', 1);
        expect(
          await artist.updateExistingPivot('songs', 1, <String, dynamic>{
            'role': 'drums',
          }),
          1,
        );
        Artist? a = await Artist().preload('songs').find(artist.id);
        expect(a!.songs.first.pivot['role'], 'drums');
      });

      test('the default keys work too', () async {
        Song song = (await Song().find(1))!;
        await song.attach('artists', artist);
        expect(await songIds(), <int>[1]);
      });

      test('errors', () async {
        expect(() => artist.attach('nope', 1), throwsA(isA<ArgumentError>()));
        expect(() => Artist().attach('songs', 1), throwsA(isA<StateError>()));
      });
    });

    test('a double that is not a whole number id throws', () async {
      Artist artist = await Artist().create(<String, dynamic>{'name': 'A'});
      await artist.attach('songs', 1);
      for (dynamic id in <dynamic>[1.5, double.nan, double.infinity, 1e20]) {
        await expectLater(
          artist.attach('songs', <dynamic>[id]),
          throwsA(isA<ArgumentError>()),
        );
        await expectLater(
          artist.sync('songs', <dynamic>[id]),
          throwsA(isA<ArgumentError>()),
        );
        await expectLater(
          artist.detach('songs', <dynamic>[id]),
          throwsA(isA<ArgumentError>()),
        );
      }

      /// nothing changed
      List<Map<String, dynamic>> rows = await QueryBuilder.table('artist_song')
          .get();
      expect(rows.map((Map<String, dynamic> r) => r['song_id']), <int>[1]);
    });

    group('pivot ids |', () {
      test('intId', () {
        expect(intId(1), 1);
        expect(intId(1.0), 1);
        expect(intId('01'), 1);
        expect(intId(' 1 '), 1);
        expect(intId('+1'), 1);
        expect(intId('1.0'), 1);
        expect(intId('-2.00'), -2);
        expect(intId('1.'), 1);
        expect(intId('.0'), 0);
        expect(intId('1e0'), 1);
        expect(intId('1E0'), 1);
        expect(intId('0x1'), 1);
        expect(intId('1.01'), isNull);
        expect(intId('9007199254740993.0'), 9007199254740993);
        expect(intId('9007199254740993'), 9007199254740993);
        expect(() => intId('9007199254740993.5'), throwsArgumentError);
        expect(() => intId('1e20'), throwsArgumentError);
        expect(() => intId('99999999999999999999'), throwsArgumentError);
        expect(intId('++1'), isNull);
        expect(intId('Infinity'), isNull);
        expect(intId('NaN'), isNull);
        expect(intId(9007199254740992.0), 9007199254740992);
        expect(intId(18014398509481984.0), isNull);
        expect(intId('-2'), -2);
        expect(intId('1.5'), isNull);
        expect(intId(1.5), isNull);
        expect(intId('abc'), isNull);
        expect(intId(''), isNull);

        /// out of the int range: not clamped to the max int
        expect(intId(1e20), isNull);
        expect(intId(-1e20), isNull);
        expect(intId(double.infinity), isNull);
        expect(intId(double.nan), isNull);
        expect(sameId(1e20, 9223372036854775807), isFalse);
        expect(sameId(9007199254740992.0, 9007199254740993), isFalse);
      });

      test('sameId', () {
        expect(sameId(1, '01'), isTrue);
        expect(sameId(' 1', 1.0), isTrue);
        expect(sameId(1, ' 01 '), isTrue);

        /// two texts only match by the exact text: it can be a text key
        expect(sameId('007', '7'), isFalse);
        expect(sameId('1', '01'), isFalse);
        expect(sameId('1.5', 1.5), isTrue);
        expect(sameId('1.5', 1), isFalse);
        expect(sameId(1, '1e0'), isTrue);
        expect(sameId(1, '0x1'), isTrue);
        expect(sameId('1', '1e0'), isFalse);
        expect(sameId(1, 'NaN'), isFalse);
        expect(sameId(double.nan, 'NaN'), isFalse);
        expect(sameId('abc', 'abc'), isTrue);
        expect(sameId('abc', 'ABC'), isFalse);
      });
    });
  });
}
