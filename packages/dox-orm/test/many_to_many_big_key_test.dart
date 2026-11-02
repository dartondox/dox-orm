import 'package:dox_orm/dox_orm.dart';
import 'package:test/test.dart';

import 'connection.dart';
import 'models/artist/artist.model.dart';

/// A bigInteger related key past 2^53, where a double is not exact. Its
/// own file, so the pivot column type does not change on one connection.
void main() async {
  await initQueryBuilder();

  group('Many To Many big key |', () {
    late Artist artist;
    const int big = 9007199254740993;

    setUp(() async {
      await Schema().dropIfExists('artist');
      await Schema().dropIfExists('artist_song');
      await Schema().create('artist', (Table table) {
        table.id();
        table.string('name');
        table.timestamps();
      });
      await Schema().create('artist_song', (Table table) {
        table.id();
        table.bigInteger('song_id');
        table.integer('artist_id');
        table.string('role').nullable();
        table.timestamps();
      });
      artist = await Artist().create(<String, dynamic>{'name': 'A'});
      await artist.attach('songs', big, <String, dynamic>{'role': 'r4'});
    });

    Future<List<String>> rows() async {
      List<Map<String, dynamic>> list = await QueryBuilder.table('artist_song')
          .where('artist_id', artist.id)
          .get();
      return <String>[
        for (Map<String, dynamic> r in list) '${r['song_id']}:${r['role']}',
      ];
    }

    test("sync ['9007199254740993.0'] keeps the row", () async {
      PivotSyncResult r = await artist.sync('songs', <dynamic>[
        '9007199254740993.0',
      ]);
      expect(r.attached, isEmpty);
      expect(r.detached, isEmpty);
      expect(await rows(), <String>['$big:r4']);
    });

    test('a text that is not an exact number throws first', () async {
      for (String text in <String>[
        '9007199254740993.5',
        '9007199254740993.',
        '9007199254740993e0',
        '9.007199254740993e15',
        '1e20',
      ]) {
        await expectLater(
          artist.sync('songs', <dynamic>[text]),
          throwsA(isA<ArgumentError>()),
          reason: text,
        );
        await expectLater(
          artist.toggle('songs', <dynamic>[text]),
          throwsA(isA<ArgumentError>()),
          reason: text,
        );
      }
      expect(await rows(), <String>['$big:r4']);
    });
  });
}
