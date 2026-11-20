import 'dart:async';

import 'package:dox_orm/dox_orm.dart';
import 'package:dox_orm/src/utils/cast_reads.dart';
import 'package:test/test.dart';

import 'connection.dart';
import 'models/cast_item/cast_item.model.dart';
import 'models/enum_item/enum_item.model.dart';

/// the lines that [body] prints
Future<List<String>> printed(Future<void> Function() body) async {
  List<String> lines = <String>[];
  await runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      print: (Zone self, ZoneDelegate parent, Zone zone, String line) {
        lines.add(line);
      },
    ),
  );
  return lines;
}

void main() async {
  await initQueryBuilder();

  group('EnumCast unknown values |', () {
    setUp(() async {
      CastReads.resetWarnings();
      await Schema().dropIfExists('enum_item');
      await Schema().create('enum_item', (Table table) {
        table.id();
        table.string('title').nullable();
        table.string('status').nullable();
        table.string('level').nullable();
        table.string('fallback').nullable();
        table.string('kind').withDefault('draft');
      });
    });

    tearDown(() async {
      await Schema().dropIfExists('enum_item');
    });

    /// a row with raw [values], and its id
    Future<dynamic> insert(Map<String, dynamic> values) async {
      Map<String, dynamic> row = await QueryBuilder.table('enum_item')
          .create(values);
      return row['id'];
    }

    Future<Map<String, dynamic>?> raw(dynamic id) =>
        QueryBuilder.table('enum_item').find(id);

    test('normal values by name and by index', () async {
      dynamic id = await insert(<String, dynamic>{
        'status': 'live',
        'level': '2',
        'fallback': 'live',
        'kind': 'live',
      });
      List<String> lines = <String>[];
      EnumItem? item;
      lines = await printed(() async => item = await EnumItem().find(id));
      expect(item?.status, Status.live);
      expect(item?.level, Level.high);
      expect(item?.fallback, Status.live);
      expect(item?.kind, Status.live);
      expect(lines, isEmpty);
    });

    test('unknown name reads as null and warns once', () async {
      dynamic id = await insert(<String, dynamic>{'status': 'archived'});
      await insert(<String, dynamic>{'status': 'archived'});
      List<EnumItem> items = <EnumItem>[];
      List<String> lines = await printed(() async {
        items = await EnumItem().all();
        await EnumItem().find(id);
      });
      expect(items.length, 2);
      expect(items.first.status, isNull);
      expect(items.first.kind, Status.draft);
      expect(lines.length, 1);
      expect(lines.first, contains('enum_item'));
      expect(lines.first, contains('"status"'));
      expect(lines.first, contains('"archived"'));
      expect(lines.first, contains('reads as null'));
    });

    test('out of range index and not a number read as null', () async {
      dynamic a = await insert(<String, dynamic>{'level': '7'});
      dynamic b = await insert(<String, dynamic>{'level': '-1'});
      dynamic c = await insert(<String, dynamic>{'level': 'high'});
      List<String> lines = await printed(() async {
        expect((await EnumItem().find(a))?.level, isNull);
        expect((await EnumItem().find(b))?.level, isNull);
        expect((await EnumItem().find(c))?.level, isNull);
      });
      expect(lines.length, 3);
      expect(lines[0], contains('"level"'));
      expect(lines[0], contains('"7"'));
      expect(lines[2], contains('"high"'));
    });

    test('the unknown: fallback', () async {
      dynamic id = await insert(<String, dynamic>{'fallback': 'archived'});
      EnumItem? item;
      List<String> lines = await printed(
        () async => item = await EnumItem().find(id),
      );
      expect(item?.fallback, Status.draft);
      expect(lines.single, contains('reads as Status.draft'));
      expect(
        const EnumCast<Status>(Status.values, unknown: Status.live).get('x'),
        Status.live,
      );
    });

    test('a field that can not be null throws a clear error', () async {
      dynamic id = await insert(<String, dynamic>{'kind': 'archived'});
      await expectLater(
        EnumItem().find(id),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            allOf(
              contains('"kind"'),
              contains('"archived"'),
              contains('can not be null'),
            ),
          ),
        ),
      );
    });

    test('save keeps the unknown stored value', () async {
      dynamic id = await insert(<String, dynamic>{
        'title': 'old',
        'status': 'archived',
        'level': '9',
        'fallback': 'gone',
      });
      EnumItem? item;
      await printed(() async => item = await EnumItem().find(id));
      expect(item!.isDirty(), isFalse);
      item!.title = 'new';
      expect(item!.getDirty().keys, <String>['title']);
      await item!.save();

      Map<String, dynamic>? row = await raw(id);
      expect(row?['title'], 'new');
      expect(row?['status'], 'archived');
      expect(row?['level'], '9');
      expect(row?['fallback'], 'gone');

      /// a second save still keeps it
      item!.title = 'newer';
      await item!.save();
      expect((await raw(id))?['status'], 'archived');

      /// the app sets the field: it is saved
      item!.status = Status.live;
      await item!.save();
      expect((await raw(id))?['status'], 'live');

      /// and set back to null: that is saved too
      item!.status = null;
      await item!.save();
      expect((await raw(id))?['status'], isNull);
    });

    test('updateOrCreate keeps the unknown stored value', () async {
      dynamic id = await insert(<String, dynamic>{
        'title': 'a',
        'status': 'archived',
      });
      await printed(() async {
        await EnumItem().updateOrCreate(
          <String, dynamic>{'title': 'a'},
          <String, dynamic>{'level': '1'},
        );
      });
      Map<String, dynamic>? row = await raw(id);
      expect(row?['status'], 'archived');
      expect(row?['level'].toString(), '1');
    });

    test('refresh keeps the unknown stored value on save', () async {
      dynamic id = await insert(<String, dynamic>{'status': 'archived'});
      await printed(() async {
        EnumItem item = (await EnumItem().find(id))!;
        await item.refresh();
        item.title = 'x';
        await item.save();
      });
      expect((await raw(id))?['status'], 'archived');
    });
  });
}
