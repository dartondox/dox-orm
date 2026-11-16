import 'package:dox_orm/dox_orm.dart';
import 'package:test/test.dart';

import 'connection.dart';
import 'models/blog/blog.model.dart';

void main() async {
  await initQueryBuilder();

  QueryBuilder<Map<String, dynamic>> people() => QueryBuilder.table('hp_user');

  List<String> sqls = <String>[];
  void onQuery(QueryEvent e) => sqls.add(e.sql);

  setUp(() async {
    await Schema().dropIfExists('hp_user');
    await Schema().dropIfExists('blog');
    await Schema().dropIfExists('blog_info');
    await Schema().create('blog_info', (Table table) {
      table.id();
      table.json('info');
      table.integer('blog_id');
      table.timestamps();
    });
    await Schema().create('hp_user', (Table table) {
      table.id();
      table.string('name');
      table.string('email').nullable();
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
    await people().insertMultiple(<Map<String, dynamic>>[
      <String, dynamic>{'name': 'a', 'email': 'a@x'},
      <String, dynamic>{'name': 'b', 'email': null},
      <String, dynamic>{'name': 'c', 'email': 'c@x'},
      <String, dynamic>{'name': 'd', 'email': 'd@x'},
      <String, dynamic>{'name': 'e', 'email': null},
    ]);
    sqls.clear();
    SqlQueryBuilder().listen(onQuery);
  });

  tearDown(() async {
    SqlQueryBuilder().removeListener(onQuery);
    await Schema().dropIfExists('hp_user');
    await Schema().dropIfExists('blog');
    await Schema().dropIfExists('blog_info');
  });

  group('save() dirty check with dates |', () {
    test('the same moment is not a change, another one is', () async {
      Blog blog = await Blog().create(<String, dynamic>{
        'title': 't',
        'body': 'b',
      });
      DateTime time = DateTime.utc(2026, 1, 2, 3, 4, 5);
      blog.deletedAt = time;
      await blog.saveQuietly();

      /// a new DateTime of the same moment and zone: no query
      blog.deletedAt = DateTime.fromMicrosecondsSinceEpoch(
        time.microsecondsSinceEpoch,
        isUtc: true,
      );
      sqls.clear();
      await blog.save();
      expect(sqls, isEmpty);

      blog.deletedAt = time.add(Duration(seconds: 1));
      await blog.save();
      expect(sqls.where((String s) => s.startsWith('UPDATE')).length, 1);
      expect(blog.getChanges().containsKey('deleted_at'), isTrue);
    });
  });

  group('where().first() |', () {
    test('right row for each value, also after the builder changed', () async {
      Map<String, dynamic>? row = await people().where('name', 'b').first();
      expect(row?['name'], 'b');
      row = await people().where('name', 'c').first();
      expect(row?['name'], 'c');

      /// a builder used again, then changed after first()
      QueryBuilder<Map<String, dynamic>> q = people().where('name', 'a');
      expect((await q.first())?['name'], 'a');
      expect((await q.first())?['name'], 'a');
      q.where('email', 'zzz');
      expect(await q.first(), isNull);

      /// more parts than one where
      expect(
        (await people()
            .where('email', null)
            .orderBy('name', 'desc')
            .first())?['name'],
        'e',
      );
      expect(
        (await people()
            .where('name', 'a')
            .orWhere('name', 'd')
            .orderBy('name', 'desc')
            .first())?['name'],
        'd',
      );
      expect(
        (await people()
            .where('name', '!=', 'a')
            .orderBy('name')
            .first())?['name'],
        'b',
      );
    });

    test('find() on a json path with a number, two times', () async {
      await Schema().dropIfExists('hp_json');
      await Schema().create('hp_json', (Table table) {
        table.id();
        table.json('meta');
      });
      QueryBuilder<Map<String, dynamic>> items() =>
          QueryBuilder.table('hp_json');
      await items().insert(<String, dynamic>{
        'meta': <String, dynamic>{'n': 10},
      });
      expect((await items().find('meta->n', 10))?['id'], 1);
      expect((await items().find('meta->n', 10))?['id'], 1);
      expect((await items().where('meta->n', 10).first())?['id'], 1);
      await Schema().dropIfExists('hp_json');
    });

    test('a wrapped where does not use the kept sql', () async {
      expect((await people().where('name', 'a').first())?['name'], 'a');
      Map<String, dynamic>? row = await people()
          .whereNot(
            (QueryBuilder<Map<String, dynamic>> q) => q.where('name', 'a'),
          )
          .orderBy('name')
          .first();
      expect(row?['name'], 'b');
      row = await people()
          .whereNot(
            (QueryBuilder<Map<String, dynamic>> q) => q.where('name', 'a'),
          )
          .first();
      expect(row?['name'], isNot('a'));
    });

    test('model: soft deletes, find() and first() share the sql', () async {
      Blog one = await Blog().create(<String, dynamic>{
        'title': 'x',
        'body': 'b',
      });
      Blog two = await Blog().create(<String, dynamic>{
        'title': 'y',
        'body': 'b',
      });
      expect((await Blog().where('title', 'y').first())?.uid, two.uid);
      expect((await Blog().find('title', 'x'))?.uid, one.uid);
      await one.delete();
      expect(await Blog().where('title', 'x').first(), isNull);
      expect(await Blog().find('title', 'x'), isNull);
      expect(
        (await Blog().withTrash().where('title', 'x').first())?.uid,
        one.uid,
      );
      expect((await Blog().where('uid', two.uid).first())?.uid, two.uid);
    });
  });
}
