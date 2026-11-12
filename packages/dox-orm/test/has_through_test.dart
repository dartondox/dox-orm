import 'package:dox_orm/dox_orm.dart';
import 'package:test/test.dart';

import 'connection.dart';
import 'models/citizen/citizen.model.dart';
import 'models/country/country.model.dart';
import 'models/letter/letter.model.dart';

void main() async {
  await initQueryBuilder();

  group('Has through |', () {
    late Country myanmar;
    late Country japan;
    late Country empty;

    setUp(() async {
      for (String t in <String>['country', 'citizen', 'letter']) {
        await Schema().dropIfExists(t);
      }
      await Schema().create('country', (Table table) {
        table.id();
        table.string('name');
        table.string('code');
        table.timestamps();
      });
      await Schema().create('citizen', (Table table) {
        table.id();
        table.string('name');
        table.integer('country_id').nullable();
        table.string('home_code').nullable();
        table.string('ref').nullable();
        table.integer('manager_id').nullable();
        table.softDeletes();
        table.timestamps();
      });
      await Schema().create('letter', (Table table) {
        table.id();
        table.string('title');
        table.integer('citizen_id').nullable();
        table.string('writer_ref').nullable();
        table.softDeletes();
        table.timestamps();
      });

      myanmar = await Country().create(<String, dynamic>{
        'name': 'Myanmar',
        'code': 'MM',
      });
      japan = await Country().create(<String, dynamic>{
        'name': 'Japan',
        'code': 'JP',
      });
      empty = await Country().create(<String, dynamic>{
        'name': 'Empty',
        'code': 'XX',
      });

      Citizen aung = await Citizen().create(<String, dynamic>{
        'name': 'Aung',
        'country_id': myanmar.id,
        'home_code': 'MM',
        'ref': 'r-aung',
      });
      Citizen mya = await Citizen().create(<String, dynamic>{
        'name': 'Mya',
        'country_id': myanmar.id,
        'home_code': 'MM',
        'ref': 'r-mya',
        'manager_id': aung.id,
      });
      Citizen ken = await Citizen().create(<String, dynamic>{
        'name': 'Ken',
        'country_id': japan.id,
        'home_code': 'JP',
        'ref': 'r-ken',
        'manager_id': aung.id,
      });

      Future<void> letter(String title, Citizen c) async {
        await Letter().create(<String, dynamic>{
          'title': title,
          'citizen_id': c.id,
          'writer_ref': c.ref,
        });
      }

      await letter('a1', aung);
      await letter('m1', mya);
      await letter('m2', mya);
      await letter('k1', ken);
    });

    tearDown(() async {
      for (String t in <String>['country', 'citizen', 'letter']) {
        await Schema().dropIfExists(t);
      }
    });

    List<String> titles(List<Letter> list) {
      return <String>[for (Letter l in list) l.title!]..sort();
    }

    test('lazy hasManyThrough', () async {
      await myanmar.$getRelation('letters');
      expect(titles(myanmar.letters), <String>['a1', 'm1', 'm2']);

      Letter q = myanmar.related<Letter>('letters')!;
      List<Letter> list = await q.where('letter.title', 'm1').get();
      expect(titles(list), <String>['m1']);
    });

    test('lazy hasOneThrough picks the row with onQuery', () async {
      await myanmar.$getRelation('latestLetter');
      expect(myanmar.latestLetter?.title, 'm2');

      await empty.$getRelation('latestLetter');
      expect(empty.latestLetter, isNull);
    });

    test('eager load many parents in one query each', () async {
      List<String> sqls = <String>[];
      void onQuery(QueryEvent e) => sqls.add(e.sql);
      SqlQueryBuilder().listen(onQuery);
      List<Country> list;
      try {
        list = await Country()
            .preload('letters')
            .preload('latestLetter')
            .orderBy('id')
            .get();
      } finally {
        SqlQueryBuilder().removeListener(onQuery);
      }

      /// one query for the countries, one for each relation
      expect(sqls.length, 3);
      expect(titles(list[0].letters), <String>['a1', 'm1', 'm2']);
      expect(titles(list[1].letters), <String>['k1']);
      expect(list[2].letters, isEmpty);
      expect(list[0].latestLetter?.title, 'm2');
      expect(list[1].latestLetter?.title, 'k1');
      expect(list[2].latestLetter, isNull);

      Map<String, dynamic> json = list[0].toMap();
      expect((json['letters'] as List<dynamic>).length, 3);
      expect(json['latest_letter']['title'], 'm2');
    });

    test('custom keys', () async {
      List<Country> list = await Country()
          .preload('lettersByCode')
          .orderBy('id')
          .get();
      expect(titles(list[0].lettersByCode), <String>['a1', 'm1', 'm2']);
      expect(titles(list[1].lettersByCode), <String>['k1']);
      expect(list[2].lettersByCode, isEmpty);
    });

    test('soft deleted through and far rows are left out', () async {
      await Letter().where('title', 'a1').delete();
      await Citizen().where('name', 'Ken').delete();

      List<Country> list = await Country()
          .preload('letters')
          .withCount('letters')
          .orderBy('id')
          .get();
      expect(titles(list[0].letters), <String>['m1', 'm2']);
      expect(list[1].letters, isEmpty);
      expect(list[0].countOf('letters'), 2);
      expect(list[1].countOf('letters'), 0);

      List<Country> has = await Country().whereHas('letters').get();
      expect(<String?>[for (Country c in has) c.name], <String>['Myanmar']);
    });

    test('withCount', () async {
      List<Country> list = await Country()
          .withCount('letters')
          .withCount('letters as m_count', (QueryBuilder<dynamic> q) {
            q.where('letter.title', 'like', 'm%');
          })
          .orderBy('id')
          .get();
      expect(
        <int?>[for (Country c in list) c.countOf('letters')],
        <int>[3, 1, 0],
      );
      expect(
        <dynamic>[for (Country c in list) c.aggregate('m_count')],
        <int>[2, 0, 0],
      );
    });

    test('whereHas, whereDoesntHave and has', () async {
      List<String?> names(List<Country> list) => <String?>[
        for (Country c in list) c.name,
      ];

      expect(
        names(await Country().whereHas('letters').orderBy('id').get()),
        <String>['Myanmar', 'Japan'],
      );
      expect(
        names(
          await Country().whereHas('latestLetter', (QueryBuilder<dynamic> q) {
            q.where('letter.title', 'k1');
          }).get(),
        ),
        <String>['Japan'],
      );
      expect(names(await Country().whereDoesntHave('letters').get()), <String>[
        'Empty',
      ]);
      expect(names(await Country().has('letters', '>=', 2).get()), <String>[
        'Myanmar',
      ]);
    });

    test('the through table can be the parent table', () async {
      List<Citizen> list = await Citizen()
          .preload('teamLetters')
          .withCount('teamLetters')
          .whereHas('teamLetters')
          .get();
      expect(list.length, 1);
      expect(list[0].name, 'Aung');
      expect(titles(list[0].teamLetters), <String>['k1', 'm1', 'm2']);
      expect(list[0].countOf('teamLetters'), 3);
    });
  });
}
