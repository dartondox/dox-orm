import 'dart:io';

import 'package:dox_orm/dox_orm.dart';
import 'package:test/test.dart';

import 'connection.dart';
import 'models/artist/artist.model.dart';

/// A text related key, like a zip code or a SKU: `'007'` and `'7'` are
/// two ids. This is its own file. In many_to_many_test.dart, after the
/// tests with a number column, Postgres and MySQL 8.4 stored `'007'` as
/// `7` in the new text column, probably by a kept prepared statement.
void main() async {
  await initQueryBuilder();

  group('Many To Many text key |', () {
    late Artist artist;

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
        table.string('song_id');
        table.integer('artist_id');
        table.string('role').nullable();
        table.timestamps();
      });
      artist = await Artist().create(<String, dynamic>{'name': 'A'});
    });

    Future<List<String>> keys() async {
      List<Map<String, dynamic>> rows = await QueryBuilder.table('artist_song')
          .where('artist_id', artist.id)
          .get();
      return <String>[for (Map<String, dynamic> r in rows) '${r['song_id']}']
        ..sort();
    }

    test('007 and 7 are two ids', () async {
      await artist.attach('songs', <dynamic>['007', '7']);
      expect(await keys(), <String>['007', '7']);
    });

    test('sync replaces 007 with 7', () async {
      await artist.attach('songs', <dynamic>['007']);
      PivotSyncResult r = await artist.sync('songs', <dynamic>['7']);
      expect(r.attached, <int>[7]);
      expect(r.detached, <String>['007']);
      expect(await keys(), <String>['7']);
    });

    test('sync returns 007 as text', () async {
      PivotSyncResult r = await artist.sync('songs', <dynamic>['007']);
      expect(r.attached, <String>['007']);
      expect(await keys(), <String>['007']);
    });

    test('toggle 7 keeps the 007 row', () async {
      await artist.attach('songs', <dynamic>['007']);
      PivotSyncResult r = await artist.toggle('songs', <dynamic>['7']);
      expect(r.attached, <int>[7]);
      expect(r.detached, isEmpty);
      expect(await keys(), <String>['007', '7']);

      r = await artist.toggle('songs', <dynamic>['007']);
      expect(r.detached, <String>['007']);
      expect(await keys(), <String>['7']);
    });

    test("sync [1, '01'] keeps the rows '1' and '01'", () async {
      await artist.attach('songs', <dynamic, Map<String, dynamic>>{
        '1': <String, dynamic>{'role': 'r0'},
        '01': <String, dynamic>{'role': 'r1'},
      });
      Future<List<String>> roles() async {
        List<Map<String, dynamic>> rows = await QueryBuilder.table(
          'artist_song',
        ).where('artist_id', artist.id).get();
        return <String>[
          for (Map<String, dynamic> r in rows) '${r['song_id']}:${r['role']}',
        ]..sort();
      }

      for (dynamic ids in <dynamic>[
        <dynamic>[1, '01'],
        <dynamic>['01', 1],
        <dynamic, Map<String, dynamic>>{
          1: <String, dynamic>{},
          '01': <String, dynamic>{},
        },
      ]) {
        PivotSyncResult r = await artist.sync('songs', ids);
        expect(r.detached, isEmpty, reason: '$ids');
        expect(r.attached, isEmpty, reason: '$ids');
        expect(await roles(), <String>['01:r1', '1:r0'], reason: '$ids');
      }
    });

    test(
      "detach, toggle and updateExistingPivot with [1, '01'] find both rows",
      () async {
        await artist.attach('songs', <dynamic>['1', '01']);
        expect(
          await artist.updateExistingPivot(
            'songs',
            <dynamic>[1, '01'],
            <String, dynamic>{'role': 'u'},
          ),
          2,
        );
        PivotSyncResult r = await artist.toggle('songs', <dynamic>['01', 1]);
        expect(r.detached, unorderedEquals(<dynamic>['01', 1]));
        expect(await keys(), <String>[]);

        await artist.attach('songs', <dynamic>['1', '01']);
        expect(await artist.detach('songs', <dynamic>[1, '01']), 2);
        expect(await keys(), <String>[]);
      },
    );

    test("toggle ['1', 1] is one id", () async {
      await artist.attach('songs', <dynamic>['1', '01']);
      PivotSyncResult r = await artist.toggle('songs', <dynamic>['1', 1]);
      expect(r.detached, <int>[1]);
      expect(r.attached, isEmpty);
      expect(await keys(), <String>['01']);
    });

    test('a long digit text in the table does not stop sync', () async {
      await artist.attach('songs', <dynamic>['12345678901234567890', '1e20']);
      PivotSyncResult r = await artist.sync('songs', <dynamic>[1]);
      expect(r.attached, <int>[1]);
      expect(
        r.detached,
        unorderedEquals(<String>['12345678901234567890', '1e20']),
      );
      expect(await keys(), <String>['1']);
    });

    test('other text keys match by the exact text', () async {
      await artist.attach('songs', <dynamic>['a1b2', 'A1B2', 'abc']);
      PivotSyncResult r = await artist.sync('songs', <dynamic>['abc', 'x']);
      expect(r.attached, <String>['x']);
      expect(r.detached..sort(), <String>['A1B2', 'a1b2']);
      expect(await keys(), <String>['abc', 'x']);
    });
  });

  /// MySQL and MariaDB compare text without case by default, and SQLite
  /// does with COLLATE NOCASE. 'abc' and 'ABC' are then one id.
  group('Many To Many text key, no case |', () {
    late Artist artist;

    setUp(() async {
      await Schema().dropIfExists('artist');
      await Schema().dropIfExists('artist_song');
      await Schema().create('artist', (Table table) {
        table.id();
        table.string('name');
        table.timestamps();
      });
      if (driver() == 'sqlite') {
        await SqlQueryBuilder().dbDriver.query(
          'CREATE TABLE artist_song (id INTEGER PRIMARY KEY, '
          'song_id TEXT COLLATE NOCASE, artist_id INTEGER, role TEXT, '
          'created_at TEXT, updated_at TEXT)',
        );
      } else {
        await Schema().create('artist_song', (Table table) {
          table.id();
          table.string('song_id');
          table.integer('artist_id');
          table.string('role').nullable();
          table.timestamps();
        });
      }
      artist = await Artist().create(<String, dynamic>{'name': 'A'});
    });

    Future<List<String>> keys() async {
      List<Map<String, dynamic>> rows = await QueryBuilder.table('artist_song')
          .where('artist_id', artist.id)
          .get();
      return <String>[for (Map<String, dynamic> r in rows) '${r['song_id']}']
        ..sort();
    }

    test('sync with the other case keeps the row', () async {
      await artist.attach('songs', <dynamic>['ABC', 'x']);
      PivotSyncResult r = await artist.sync('songs', <dynamic>['abc']);
      expect(r.attached, isEmpty);
      expect(r.detached, <String>['x']);
      expect(await keys(), <String>['ABC']);

      r = await artist.syncWithoutDetaching('songs', <dynamic>['abc']);
      expect(r.attached, isEmpty);
      expect(await keys(), <String>['ABC']);
    });

    test('sync does not delete a row that is the same as a kept row', () async {
      await artist.attach('songs', <dynamic>['ABC']);
      await artist.attach('songs', <dynamic>['abc']);
      PivotSyncResult r = await artist.sync('songs', <dynamic>['ABC']);

      /// the database keeps 'abc' with 'ABC', so it is not detached
      expect(r.detached, isEmpty);
      expect(await keys(), isNotEmpty);
    });

    test('a case-only match of many ids reads the rows once', () async {
      await artist.attach('songs', <dynamic>['ABC', 'DEF', 'x']);
      QueryPrinter old = SqlQueryBuilder().printer;
      _Selects selects = _Selects();
      SqlQueryBuilder().printer = selects;
      PivotSyncResult r;
      try {
        artist.debug(true);
        r = await artist.sync('songs', <dynamic>['abc', 'def']);
      } finally {
        artist.debug(false);
        SqlQueryBuilder().printer = old;
      }
      expect(r.attached, isEmpty);
      expect(r.detached, <String>['x']);
      expect(await keys(), <String>['ABC', 'DEF']);

      /// the pivot rows, then one query for all text ids
      expect(selects.count, 2);
    });

    test(
      'an accent-only match keeps the row',
      () async {
        await artist.attach('songs', <dynamic>['é', 'ABC']);
        PivotSyncResult r = await artist.sync('songs', <dynamic>['e', 'abc']);
        expect(r.attached, isEmpty);
        expect(r.detached, isEmpty);
        expect(await keys(), <String>['ABC', 'é']);
      },
      skip: driver() == 'mysql'
          ? false
          : 'only MySQL and MariaDB ignore accents',
    );

    test('toggle with the other case removes the row', () async {
      await artist.attach('songs', <dynamic>['ABC']);
      PivotSyncResult r = await artist.toggle('songs', <dynamic>['abc']);
      expect(r.attached, isEmpty);
      expect(r.detached, <String>['ABC']);
      expect(await keys(), isEmpty);
    });
  }, skip: driver() == 'postgres' ? 'Postgres compares text by case' : false);
}

String driver() => Platform.environment['DRIVER'] ?? 'mysql';

/// counts the logged SELECT queries on the pivot table
class _Selects implements QueryPrinter {
  int count = 0;

  @override
  void log(String query, List<String> params) {
    if (query.startsWith('SELECT') && query.contains('artist_song')) count++;
  }
}
