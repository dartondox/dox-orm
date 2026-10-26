import 'package:dox_orm/dox_orm.dart';
import 'package:test/test.dart';

import 'connection.dart';

DateTime? _date(dynamic value) {
  if (value == null || value is DateTime) return value as DateTime?;
  return DateTime.parse('$value');
}

/// a model written by hand (no generated code), with hooks that log
class Counter extends Model<Counter> {
  static List<String> log = <String>[];

  /// the hook named here throws CancelModelEvent
  static String? cancelOn;

  int? get id => tempIdValue as int?;
  set id(int? value) => tempIdValue = value;

  String? name;
  int? views;

  @override
  String get tableName => 'write_counters';

  @override
  List<String> get tableColumns => const <String>[
    'id',
    'name',
    'views',
    'created_at',
    'updated_at',
  ];

  @override
  List<String> get guarded => const <String>['secret'];

  @override
  bool get hasModelHooks => true;

  @override
  Counter fromMap(Map<String, dynamic> m) => Counter()
    ..id = m['id'] as int?
    ..name = m['name'] as String?
    ..views = m['views'] as int?
    ..createdAt = _date(m['created_at'])
    ..updatedAt = _date(m['updated_at']);

  @override
  Map<String, dynamic> columnsToMap() => <String, dynamic>{
    'id': id,
    'name': name,
    'views': views,
    'created_at': createdAt?.toIso8601String(),
    'updated_at': updatedAt?.toIso8601String(),
  };

  @override
  Map<String, dynamic> convertToMap(dynamic i) => (i as Counter).columnsToMap();

  /// what dox_builder makes for each @Column
  @override
  bool setColumnValue(String column, dynamic value) {
    switch (column) {
      case 'id':
        if (value is! int?) return false;
        id = value;
        return true;
      case 'name':
        if (value is! String?) return false;
        name = value;
        return true;
      case 'views':
        if (value is! int?) return false;
        views = value;
        return true;
    }
    return false;
  }

  void _log(String event) {
    log.add(event);
    if (cancelOn == event) throw CancelModelEvent(event);
  }

  @override
  void onSaving() => _log('saving');
  @override
  void onSaved() => _log('saved');
  @override
  void onCreating() => _log('creating');
  @override
  void onCreated() => _log('created');
  @override
  void onUpdating() => _log('updating');
  @override
  void onUpdated() => _log('updated');
  @override
  void onDeleting() => _log('deleting');
  @override
  void onDeleted() => _log('deleted');
  @override
  void onForceDeleting() => _log('forceDeleting');
}

/// a model on the same table as [Counter] with no setColumnValue(), like
/// a model made by an old dox_builder
class PlainCounter extends Model<PlainCounter> {
  int? get id => tempIdValue as int?;
  set id(int? value) => tempIdValue = value;

  String? name;
  int? views;

  @override
  String get tableName => 'write_counters';

  @override
  List<String> get tableColumns => const <String>['id', 'name', 'views'];

  @override
  PlainCounter fromMap(Map<String, dynamic> m) => PlainCounter()
    ..id = m['id'] as int?
    ..name = m['name'] as String?
    ..views = m['views'] as int?;

  @override
  Map<String, dynamic> columnsToMap() => <String, dynamic>{
    'id': id,
    'name': name,
    'views': views,
  };

  @override
  Map<String, dynamic> convertToMap(dynamic i) =>
      (i as PlainCounter).columnsToMap();
}

/// a soft delete model
class Note extends Model<Note> with SoftDeletes<Note> {
  int? get id => tempIdValue as int?;
  set id(int? value) => tempIdValue = value;

  String? title;

  @override
  String get tableName => 'write_notes';

  @override
  List<String> get tableColumns => const <String>['id', 'title'];

  @override
  Note fromMap(Map<String, dynamic> m) => Note()
    ..id = m['id'] as int?
    ..title = m['title'] as String?;

  @override
  Map<String, dynamic> columnsToMap() => <String, dynamic>{
    'id': id,
    'title': title,
  };

  @override
  Map<String, dynamic> convertToMap(dynamic i) => (i as Note).columnsToMap();
}

/// a model on a table with no id column, so MySQL can not read the new
/// row back
class Pair extends Model<Pair> {
  int? aId;
  int? bId;

  @override
  String get tableName => 'write_pairs';

  @override
  Map<String, dynamic> get timestampsColumn => const <String, dynamic>{
    'created_at': null,
    'updated_at': null,
  };

  @override
  List<String> get tableColumns => const <String>['a_id', 'b_id'];

  @override
  Pair fromMap(Map<String, dynamic> m) => Pair()
    ..aId = m['a_id'] as int?
    ..bId = m['b_id'] as int?;

  @override
  Map<String, dynamic> columnsToMap() => <String, dynamic>{
    'a_id': aId,
    'b_id': bId,
  };

  @override
  Map<String, dynamic> convertToMap(dynamic i) => (i as Pair).columnsToMap();
}

bool get _isMysql => SqlQueryBuilder().dbDriver.getName() == Driver.mysql;

QueryBuilder<Map<String, dynamic>> _counters() =>
    QueryBuilder.table('write_counters');

Future<int> _views(String name) async {
  Map<String, dynamic>? row = await _counters().where('name', name).getFirst();
  return row!['views'] as int;
}

void main() async {
  await initQueryBuilder();

  group('Write results |', () {
    setUp(() async {
      Counter.log = <String>[];
      Counter.cancelOn = null;
      await Schema().create('write_counters', (Table table) {
        table.id();
        table.string('name').nullable();
        table.integer('views').withDefault(0);
        table.timestamps();
      });
      await Schema().create('write_notes', (Table table) {
        table.id();
        table.string('title');
        table.softDeletes();
        table.timestamps();
      });
      await Schema().create('write_pairs', (Table table) {
        table.integer('a_id');
        table.integer('b_id');
      });
      await Schema().create('write_flights', (Table table) {
        table.id();
        table.string('origin');
        table.string('dest');
        table.integer('price');
        table.unique(<String>['origin', 'dest']);
      });
      await _counters().insertMultiple(<Map<String, dynamic>>[
        <String, dynamic>{'name': 'a'},
        <String, dynamic>{'name': 'b'},
        <String, dynamic>{'name': 'c'},
      ]);
    });

    tearDown(() async {
      await Schema().dropIfExists('write_counters');
      await Schema().dropIfExists('write_notes');
      await Schema().dropIfExists('write_pairs');
      await Schema().dropIfExists('write_flights');
    });

    test('update returns the rows changed', () async {
      int count = await _counters().where('views', 0).update(<String, dynamic>{
        'name': 'x',
      });
      expect(count, 3);
      expect(
        await _counters().where('name', 'nobody').update(<String, dynamic>{
          'name': 'y',
        }),
        0,
      );
      expect(
        await Counter().where('name', 'x').update(<String, dynamic>{
          'views': 2,
        }),
        3,
      );
    });

    test('an empty update runs no query and returns 0', () async {
      expect(await _counters().update(<String, dynamic>{}), 0);
      expect(
        await _counters().where('name', 'a').update(<String, dynamic>{}),
        0,
      );

      /// every key is guarded, so nothing is left
      expect(
        await Counter().where('name', 'a').update(<String, dynamic>{
          'secret': 1,
        }),
        0,
      );
    });

    test('delete and forceDelete return the rows deleted', () async {
      expect(await _counters().where('name', 'a').delete(), 1);
      expect(await _counters().where('name', 'a').delete(), 0);
      expect(await _counters().forceDelete(), 2);
      expect(await _counters().count(), 0);
    });

    test('soft delete returns the rows deleted', () async {
      for (String title in <String>['a', 'b', 'c']) {
        await Note().create(<String, dynamic>{'title': title});
      }
      expect(await Note().where('title', 'a').delete(), 1);

      /// a soft deleted row is not deleted again
      expect(await Note().where('title', 'a').delete(), 0);

      Note? b = await Note().where('title', 'b').getFirst();
      expect(await b!.delete(), 1);
      expect(await Note().count(), 1);

      /// forceDelete also deletes the soft deleted rows
      Note? trashed = await Note().withTrash().where('title', 'a').getFirst();
      expect(await trashed!.forceDelete(), 1);
      expect(await Note().forceDelete(), 2);
      expect(await Note().withTrash().count(), 0);
    });

    test('model delete returns 0 when a hook cancels', () async {
      Counter? counter = await Counter().where('name', 'a').getFirst();
      Counter.cancelOn = 'deleting';
      expect(await counter!.delete(), 0);
      Counter.cancelOn = 'forceDeleting';
      expect(await counter.forceDelete(), 0);
      expect(await Counter().count(), 3);

      Counter.cancelOn = null;
      expect(await counter.delete(), 1);
      expect(await Counter().count(), 2);
    });

    test('create gives a typed model or map', () async {
      Counter counter = await Counter().create(<String, dynamic>{
        'name': 'new',
      });
      expect(counter.id, isNotNull);
      expect(counter.name, 'new');
      expect(counter.views, 0);
      expect(counter.exists, true);

      Map<String, dynamic> row = await _counters().create(<String, dynamic>{
        'name': 'row',
      });
      expect(row['id'], isNotNull);
      expect(row['name'], 'row');
      expect(row['views'], 0);

      Map<String, dynamic> inserted = await _counters().insert(
        <String, dynamic>{'name': 'inserted'},
      );
      expect(inserted['name'], 'inserted');
    });

    test('insert of a row that can not be read back', () async {
      /// no id column: MySQL can not read the row, it gives the data back
      Map<String, dynamic> row = await QueryBuilder.table('write_pairs')
          .insert(<String, dynamic>{'a_id': 1, 'b_id': 2});
      expect(row['a_id'], 1);
      expect(row['b_id'], 2);

      Pair pair = await Pair().create(<String, dynamic>{'a_id': 3, 'b_id': 4});
      expect(pair, isA<Pair>());
      expect(pair.aId, 3);
      expect(pair.bId, 4);
      expect(await QueryBuilder.table('write_pairs').count(), 2);
    });

    test('increment and decrement on a query', () async {
      expect(await _counters().where('name', 'a').increment('views'), 1);
      expect(await _views('a'), 1);
      expect(
        await _counters().where('name', 'a').increment(
          'views',
          5,
          <String, dynamic>{'name': 'a2'},
        ),
        1,
      );
      expect(await _views('a2'), 6);
      expect(await _counters().where('name', 'a2').decrement('views', 2), 1);
      expect(await _views('a2'), 4);

      /// every row
      expect(await Counter().increment('views', 10), 3);
      expect(await _views('b'), 10);
      expect(await Counter().where('name', 'b').decrement('views'), 1);
      expect(await _views('b'), 9);
    });

    test('increment and decrement on a model', () async {
      Counter? a = await Counter().where('name', 'a').getFirst();
      expect(await a!.increment('views', 3), 1);
      expect(await _views('a'), 3);
      expect(a.views, 3);

      /// only this row changed
      expect(await _views('b'), 0);

      expect(await a.decrement('views', 1, <String, dynamic>{'secret': 1}), 1);
      expect(await _views('a'), 2);
      expect(a.views, 2);

      /// save() does not send the old value of the field back
      a.name = 'a2';
      await a.save();
      expect(await _views('a2'), 2);
      expect(Counter.log, isNot(contains('creating')));
    });

    test('increment on a model sets the fields of extra', () async {
      Counter? a = await Counter().where('name', 'a').getFirst();
      expect(
        await a!.increment('views', 2, <String, dynamic>{'name': 'hot'}),
        1,
      );
      expect(a.views, 2);
      expect(a.name, 'hot');

      /// another process changes the row. save() with no change sends
      /// nothing, so it does not write views 2 back.
      await _counters().where('name', 'hot').update(<String, dynamic>{
        'views': 50,
      });
      await a.save();
      expect(await _views('hot'), 50);
    });

    test('increment on a model whose field was not read', () async {
      Counter? a = await Counter().select('id').where('name', 'a').getFirst();
      expect(await a!.increment('views', 4), 1);
      expect(await _views('a'), 4);

      /// the old value is not known, so the field stays null
      expect(a.views, isNull);
    });

    test('increment of a row that is gone changes no field', () async {
      Counter? a = await Counter().where('name', 'a').getFirst();
      await _counters().where('name', 'a').delete();
      expect(await a!.increment('views'), 0);
      expect(a.views, 0);
    });

    test('a model with no setColumnValue keeps its field', () async {
      PlainCounter? a = await PlainCounter().where('name', 'a').getFirst();
      expect(await a!.increment('views', 3), 1);
      expect(await _views('a'), 3);
      expect(a.views, 0);
      expect(a.setColumnValue('views', 3), false);

      /// save() does not send the old value back
      a.name = 'a2';
      await a.save();
      expect(await _views('a2'), 3);
    });

    test('upsert inserts and updates', () async {
      QueryBuilder<Map<String, dynamic>> flights() =>
          QueryBuilder.table('write_flights');
      int count = await flights().upsert(
        <Map<String, dynamic>>[
          <String, dynamic>{'origin': 'OAK', 'dest': 'SAN', 'price': 99},
          <String, dynamic>{'origin': 'ORD', 'dest': 'JFK', 'price': 150},
        ],
        <String>['origin', 'dest'],
      );
      expect(count, 2);

      count = await flights().upsert(
        <Map<String, dynamic>>[
          <String, dynamic>{'origin': 'OAK', 'dest': 'SAN', 'price': 120},
          <String, dynamic>{'origin': 'SFO', 'dest': 'LAX', 'price': 80},
        ],
        <String>['origin', 'dest'],
        <String>['price'],
      );

      /// MySQL counts an updated row as 2
      expect(count, _isMysql ? 3 : 2);
      expect(await flights().count(), 3);
      Map<String, dynamic>? oak = await flights()
          .where('origin', 'OAK')
          .getFirst();
      expect(oak!['price'], 120);

      /// no update columns: the old row stays
      count = await flights().upsert(
        <Map<String, dynamic>>[
          <String, dynamic>{'origin': 'OAK', 'dest': 'SAN', 'price': 1},
        ],
        <String>['origin', 'dest'],
        <String>[],
      );
      expect(count, 0);
      oak = await flights().where('origin', 'OAK').getFirst();
      expect(oak!['price'], 120);

      expect(
        () => flights().upsert(
          <Map<String, dynamic>>[
            <String, dynamic>{'origin': 'A', 'dest': 'B', 'price': 1},
            <String, dynamic>{'origin': 'C', 'dest': 'D'},
          ],
          <String>['origin', 'dest'],
        ),
        throwsArgumentError,
      );
      expect(
        await flights().upsert(<Map<String, dynamic>>[], <String>['id']),
        0,
      );
    });

    test('model upsert sets the timestamps', () async {
      Counter? a = await Counter().where('name', 'a').getFirst();
      int count = await Counter().upsert(
        <Map<String, dynamic>>[
          <String, dynamic>{'id': a!.id, 'name': 'a2', 'views': 7},
          <String, dynamic>{'id': 100, 'name': 'new', 'views': 1},
        ],
        <String>['id'],
      );
      expect(count, _isMysql ? 3 : 2);
      Counter? a2 = await Counter().find(a.id);
      expect(a2!.name, 'a2');
      expect(a2.views, 7);
      expect(a2.updatedAt, isNotNull);

      /// created_at is set on insert, not changed on update
      expect(a2.createdAt, isNull);
      Counter? created = await Counter().find(100);
      expect(created!.createdAt, isNotNull);
    });

    test('firstOrCreate finds or creates', () async {
      Map<String, dynamic> row = await _counters().firstOrCreate(
        <String, dynamic>{'name': 'd'},
        <String, dynamic>{'views': 4},
      );
      expect(row['views'], 4);
      Map<String, dynamic> again = await _counters().firstOrCreate(
        <String, dynamic>{'name': 'd'},
        <String, dynamic>{'views': 9},
      );
      expect(again['id'], row['id']);
      expect(again['views'], 4);
      expect(await _counters().count(), 4);

      Counter found = await Counter().firstOrCreate(<String, dynamic>{
        'name': 'a',
      });
      expect(found.name, 'a');
      expect(Counter.log, isEmpty);

      Counter created = await Counter().firstOrCreate(
        <String, dynamic>{'name': 'e'},
        <String, dynamic>{'views': 2},
      );
      expect(created.id, isNotNull);
      expect(created.views, 2);
      expect(Counter.log, <String>['saving', 'creating', 'created', 'saved']);
      expect(await Counter().count(), 5);
    });

    test('firstOrNew does not save', () async {
      Counter found = await Counter().firstOrNew(<String, dynamic>{
        'name': 'a',
      });
      expect(found.exists, true);

      Counter fresh = await Counter().firstOrNew(
        <String, dynamic>{'name': 'z'},
        <String, dynamic>{'views': 3, 'secret': 1},
      );
      expect(fresh.exists, false);
      expect(fresh.id, isNull);
      expect(fresh.views, 3);
      expect(await Counter().count(), 3);
      await fresh.save();
      expect(await _views('z'), 3);
    });

    test('updateOrCreate on a table', () async {
      Map<String, dynamic> created = await _counters().updateOrCreate(
        <String, dynamic>{'name': 'd'},
        <String, dynamic>{'views': 1},
      );
      expect(created['views'], 1);
      Map<String, dynamic> updated = await _counters().updateOrCreate(
        <String, dynamic>{'name': 'd'},
        <String, dynamic>{'views': 5},
      );
      expect(updated['id'], created['id']);
      expect(updated['views'], 5);
      expect(await _counters().count(), 4);

      /// a table with no id column is updated by the where pairs
      QueryBuilder<Map<String, dynamic>> pairs() =>
          QueryBuilder.table('write_pairs');
      await pairs().updateOrCreate(
        <String, dynamic>{'a_id': 1},
        <String, dynamic>{'b_id': 2},
      );
      Map<String, dynamic> pair = await pairs().updateOrCreate(
        <String, dynamic>{'a_id': 1},
        <String, dynamic>{'b_id': 3},
      );
      expect(pair['b_id'], 3);
      expect(await pairs().count(), 1);
      expect((await pairs().getFirst())!['b_id'], 3);
    });

    test('updateOrCreate on a model fires the events', () async {
      Counter created = await Counter().updateOrCreate(
        <String, dynamic>{'name': 'd'},
        <String, dynamic>{'views': 1},
      );
      expect(created.views, 1);
      expect(Counter.log, <String>['saving', 'creating', 'created', 'saved']);

      Counter.log.clear();
      Counter updated = await Counter().updateOrCreate(
        <String, dynamic>{'name': 'd'},
        <String, dynamic>{'views': 8},
      );
      expect(updated.id, created.id);
      expect(updated.views, 8);
      expect(updated.updatedAt, isNotNull);
      expect(Counter.log, <String>['saving', 'updating', 'updated', 'saved']);
      expect(await _views('d'), 8);

      /// a cancelled update gives the row as it is in the table
      Counter.cancelOn = 'updating';
      Counter same = await Counter().updateOrCreate(
        <String, dynamic>{'name': 'd'},
        <String, dynamic>{'views': 99},
      );
      expect(same.views, 8);
      expect(await _views('d'), 8);
      expect(await Counter().count(), 4);
    });

    test('row counts work in a transaction', () async {
      int count = -1;
      await expectLater(
        QueryBuilder.transaction(() async {
          count = await _counters().update(<String, dynamic>{'views': 5});
          throw StateError('undo');
        }),
        throwsStateError,
      );
      expect(count, 3);
      expect(await _views('a'), 0);

      await QueryBuilder.transaction(() async {
        count = await _counters().where('name', 'a').delete();
      });
      expect(count, 1);
      expect(await _counters().count(), 2);
    });
  });
}
