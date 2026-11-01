import 'package:dox_orm/dox_orm.dart';
import 'package:test/test.dart';

import 'connection.dart';

QueryBuilder<Map<String, dynamic>> _items() => QueryBuilder.table('wolj_items');

Future<List<String>> _names() async {
  List<Map<String, dynamic>> rows = await _items().orderBy('id').get();
  return <String>[for (Map<String, dynamic> r in rows) r['name'] as String];
}

/// update() and delete() with ORDER BY, LIMIT or JOIN must work on every
/// driver. Postgres and SQLite do not take them in UPDATE or DELETE.
void main() async {
  await initQueryBuilder();

  group('Write with order, limit and join |', () {
    setUp(() async {
      await Schema().create('wolj_items', (Table table) {
        table.id();
        table.string('name');
        table.integer('tag_id').nullable();
      });
      await Schema().create('wolj_tags', (Table table) {
        table.id();
        table.string('label');
      });
      await QueryBuilder.table('wolj_tags')
          .insertMultiple(<Map<String, dynamic>>[
            <String, dynamic>{'label': 'keep'},
            <String, dynamic>{'label': 'drop'},
          ]);
      await _items().insertMultiple(<Map<String, dynamic>>[
        <String, dynamic>{'name': 'a', 'tag_id': 1},
        <String, dynamic>{'name': 'b', 'tag_id': 2},
        <String, dynamic>{'name': 'c', 'tag_id': 2},
        <String, dynamic>{'name': 'd', 'tag_id': 1},
      ]);
    });

    tearDown(() async {
      await Schema().dropIfExists('wolj_items');
      await Schema().dropIfExists('wolj_tags');
    });

    test('update with orderBy and limit changes only those rows', () async {
      int count = await _items().orderBy('id', 'desc').limit(2).update(
        <String, dynamic>{'name': 'x'},
      );
      expect(count, 2);
      expect(await _names(), <String>['a', 'b', 'x', 'x']);
    });

    test('delete with orderBy and limit removes only those rows', () async {
      int count = await _items().orderBy('id').limit(1).delete();
      expect(count, 1);
      expect(await _names(), <String>['b', 'c', 'd']);
    });

    test('delete with limit and offset', () async {
      int count = await _items().orderBy('id').limit(2).offset(1).delete();
      expect(count, 2);
      expect(await _names(), <String>['a', 'd']);
    });

    test('update with a join', () async {
      int count = await _items()
          .join('wolj_tags', 'wolj_tags.id', '=', 'wolj_items.tag_id')
          .where('wolj_tags.label', 'drop')
          .update(<String, dynamic>{'name': 'y'});
      expect(count, 2);
      expect(await _names(), <String>['a', 'y', 'y', 'd']);
    });

    test('delete with a join', () async {
      int count = await _items()
          .join('wolj_tags', 'wolj_tags.id', '=', 'wolj_items.tag_id')
          .where('wolj_tags.label', 'keep')
          .delete();
      expect(count, 2);
      expect(await _names(), <String>['b', 'c']);
    });

    test('a plain where has no sub query', () async {
      int count = await _items().where('name', 'a').delete();
      expect(count, 1);
      expect(await _names(), <String>['b', 'c', 'd']);
    });
  });
}
