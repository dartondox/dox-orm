import 'package:dox_orm/dox_orm.dart';
import 'package:test/test.dart';

import 'connection.dart';
import 'models/setting/setting.model.dart';

void main() async {
  await initQueryBuilder();

  group('Timestamps off |', () {
    setUp(() async {
      /// no created_at and updated_at columns
      await Schema().create('setting', (Table table) {
        table.id();
        table.string('name');
      });
    });

    tearDown(() async {
      await Schema().dropIfExists('setting');
    });

    test('save and update a model without timestamps', () async {
      Setting setting = Setting();
      setting.name = 'theme';
      await setting.save();

      setting.name = 'language';
      await setting.save();

      Setting? found = await Setting().find(setting.id);
      expect(found?.name, 'language');
      expect(found?.toJson().containsKey('created_at'), false);
      expect(found?.toJson().containsKey('updated_at'), false);

      Setting created = await Setting().create(<String, dynamic>{'name': 'x'});
      expect(created.name, 'x');
    });

    test('update on a loaded model without timestamps', () async {
      Setting setting = await Setting().create(<String, dynamic>{'name': 'a'});
      Setting? loaded = await Setting().find(setting.id);

      /// no updated_at column, so the query must not set one
      expect(await loaded!.update(<String, dynamic>{'name': 'b'}), 1);
      expect(loaded.name, 'b');
      expect(loaded.updatedAt, isNull);
      expect((await Setting().find(setting.id))!.name, 'b');
    });
  });

  group('Custom updated_at column |', () {
    DateTime old = DateTime.utc(2020);

    setUp(() async {
      await Schema().create('stamped', (Table table) {
        table.id();
        table.string('title');
        table.softDeletes();
        table.timestampTz('created_at').nullable();
        table.timestampTz('modified_at').nullable();
      });
    });

    tearDown(() async {
      await Schema().dropIfExists('stamped');
    });

    /// a row with modified_at in 2020, read back
    Future<Stamped> oldRow() async {
      Stamped s = await Stamped().create(<String, dynamic>{'title': 'a'});
      await QueryBuilder.table('stamped')
          .where('id', s.id)
          .update(<String, dynamic>{'modified_at': old});
      return (await Stamped().withTrash().find(s.id))!;
    }

    Future<DateTime?> modifiedAt(int? id) async {
      Map<String, dynamic>? row = await QueryBuilder.table('stamped')
          .where('id', id)
          .getFirst();
      return _date(row!['modified_at']);
    }

    test('update on a loaded model sets the custom column', () async {
      Stamped s = await oldRow();
      expect(s.updatedAt!.year, 2020);
      expect(await s.update(<String, dynamic>{'title': 'b'}), 1);
      expect(s.title, 'b');
      expect(s.updatedAt!.isAfter(old), isTrue);
      expect((await modifiedAt(s.id))!.isAfter(old), isTrue);
    });

    test('update with the custom column in the map sets updatedAt', () async {
      Stamped s = await oldRow();
      DateTime given = DateTime.utc(2021, 5, 6);
      expect(
        await s.update(<String, dynamic>{'title': 'b', 'modified_at': given}),
        1,
      );
      expect(s.updatedAt!.isAtSameMomentAs(given), isTrue);
      expect((await modifiedAt(s.id))!.year, 2021);
    });

    test('save keeps an updated_at that the user set', () async {
      /// a loaded row: save() sets the time to now
      Stamped s = await oldRow();
      s.title = 'b';
      await s.save();
      expect(s.updatedAt!.isAfter(old), isTrue);
      expect((await modifiedAt(s.id))!.isAfter(old), isTrue);

      /// the user set it: save() keeps it
      DateTime given = DateTime.utc(2021, 5, 6);
      s
        ..title = 'c'
        ..updatedAt = given;
      await s.save();
      expect(s.updatedAt, given);
      expect((await modifiedAt(s.id))!.year, 2021);

      /// the next change sets it to now again
      s.title = 'd';
      await s.save();
      expect(s.updatedAt!.isAfter(given), isTrue);
    });

    test('save after update, touch, delete or restore sets now', () async {
      /// Stamped.setColumnValue() does not take modified_at, so the
      /// ORM must remember the time it set
      Stamped s = await oldRow();
      Future<void> saveSetsNow(Future<void> Function() write) async {
        await write();
        DateTime before = s.updatedAt!;
        await Future<void>.delayed(Duration(milliseconds: 5));
        s.title = '${s.title}x';
        await s.save();
        expect(s.updatedAt!.isAfter(before), isTrue);
      }

      await saveSetsNow(() => s.update(<String, dynamic>{'title': 'b'}));
      await saveSetsNow(() => s.touch());
      await saveSetsNow(() => s.delete());
      await saveSetsNow(() => s.restore());
    });

    test('restore sets the custom column', () async {
      Stamped s = await oldRow();
      await s.delete();
      await QueryBuilder.table('stamped')
          .where('id', s.id)
          .update(<String, dynamic>{'modified_at': old});
      s = (await Stamped().withTrash().find(s.id))!;
      expect(s.updatedAt!.year, 2020);

      expect(await s.restore(), isTrue);
      expect(s.deletedAt, isNull);
      expect(s.updatedAt!.isAfter(old), isTrue);
      expect((await modifiedAt(s.id))!.isAfter(old), isTrue);

      /// a query restore sets it too
      await s.delete();
      await QueryBuilder.table('stamped')
          .where('id', s.id)
          .update(<String, dynamic>{'modified_at': old});
      expect(await (Stamped().where('id', s.id) as Stamped).restore(), isTrue);
      expect((await modifiedAt(s.id))!.isAfter(old), isTrue);
    });
  });

  group('Restore without timestamps |', () {
    setUp(() async {
      /// no updated_at column
      await Schema().create('plain_trash', (Table table) {
        table.id();
        table.string('title');
        table.softDeletes();
      });
    });

    tearDown(() async {
      await Schema().dropIfExists('plain_trash');
    });

    test('restore does not set updated_at', () async {
      PlainTrash p = await PlainTrash().create(<String, dynamic>{'title': 'a'});
      await p.delete();
      p = (await PlainTrash().withTrash().find(p.id))!;
      expect(await p.restore(), isTrue);
      expect(p.updatedAt, isNull);
      await p.delete();
      expect(
        await (PlainTrash().where('id', p.id) as PlainTrash).restore(),
        isTrue,
      );
      expect(await PlainTrash().find(p.id), isNotNull);
    });
  });
}

DateTime? _date(dynamic v) => v is DateTime ? v : DateTime.tryParse('$v');

/// a soft delete model with `modified_at` for updated_at
class Stamped extends Model<Stamped> with SoftDeletes<Stamped> {
  /// test model: takes every key of a map
  @override
  List<String> get guarded => const <String>[];
  int? get id => tempIdValue as int?;
  set id(int? value) => tempIdValue = value;

  String? title;
  DateTime? deletedAt;

  @override
  String get tableName => 'stamped';

  @override
  Map<String, dynamic> get timestampsColumn => const <String, dynamic>{
    'created_at': 'created_at',
    'updated_at': 'modified_at',
  };

  @override
  List<String> get tableColumns => const <String>[
    'id',
    'title',
    'deleted_at',
    'created_at',
    'modified_at',
  ];

  @override
  Stamped fromMap(Map<String, dynamic> m) => Stamped()
    ..id = m['id'] as int?
    ..title = m['title'] as String?
    ..deletedAt = _date(m['deleted_at'])
    ..createdAt = _date(m['created_at'])
    ..updatedAt = _date(m['modified_at']);

  @override
  Map<String, dynamic> columnsToMap() => <String, dynamic>{
    'id': id,
    'title': title,
    'deleted_at': deletedAt,
    'created_at': createdAt,
    'modified_at': updatedAt,
  };

  @override
  Map<String, dynamic> convertToMap(dynamic i) => (i as Stamped).columnsToMap();

  @override
  bool setColumnValue(String column, dynamic value) {
    switch (column) {
      case 'id':
        if (value is! int?) return false;
        id = value;
        return true;
      case 'title':
        if (value is! String?) return false;
        title = value;
        return true;
      case 'deleted_at':
        if (value is! DateTime?) return false;
        deletedAt = value;
        return true;
    }
    return false;
  }
}

/// a soft delete model with no timestamps
class PlainTrash extends Model<PlainTrash> with SoftDeletes<PlainTrash> {
  /// test model: takes every key of a map
  @override
  List<String> get guarded => const <String>[];
  int? get id => tempIdValue as int?;
  set id(int? value) => tempIdValue = value;

  String? title;

  @override
  String get tableName => 'plain_trash';

  @override
  Map<String, dynamic> get timestampsColumn => const <String, dynamic>{
    'created_at': null,
    'updated_at': null,
  };

  @override
  List<String> get tableColumns => const <String>['id', 'title', 'deleted_at'];

  @override
  PlainTrash fromMap(Map<String, dynamic> m) => PlainTrash()
    ..id = m['id'] as int?
    ..title = m['title'] as String?;

  @override
  Map<String, dynamic> columnsToMap() => <String, dynamic>{
    'id': id,
    'title': title,
  };

  @override
  Map<String, dynamic> convertToMap(dynamic i) =>
      (i as PlainTrash).columnsToMap();

  @override
  bool setColumnValue(String column, dynamic value) {
    switch (column) {
      case 'id':
        if (value is! int?) return false;
        id = value;
        return true;
      case 'title':
        if (value is! String?) return false;
        title = value;
        return true;
    }
    return false;
  }
}
