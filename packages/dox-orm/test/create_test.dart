import 'package:dox_orm/dox_orm.dart';
import 'package:test/test.dart';

import 'connection.dart';
import 'models/cast_item/cast_item.model.dart';
import 'models/event_post/event_post.model.dart';
import 'models/note/note.model.dart';
import 'models/setting/setting.model.dart';

void main() async {
  await initQueryBuilder();

  /// create() works like save() on a new model
  group('Model create() |', () {
    setUp(() async {
      EventPost.log = <String>[];
      EventPost.cancelOn = null;
      EventPost.failOn = null;
      await Schema().create('notes', (Table table) {
        table.id();
        table.string('slug').nullable();
        table.string('title').nullable();
        table.boolean('pinned').withDefault(false);
        table.timestamps();
      });
      await Schema().create('setting', (Table table) {
        table.id();
        table.string('name');
      });
      await Schema().create('cast_item', (Table table) {
        table.id();
        table.text('meta').nullable();
        table.text('tags').nullable();
        table.boolean('active').nullable();
        table.boolean('done').withDefault(false);
        table.string('status').nullable();
        table.integer('level').nullable();
        table.integer('price').nullable();
      });
      await Schema().create('event_posts', (Table table) {
        table.id();
        table.string('title').nullable();
        table.softDeletes();
        table.timestamps();
      });
    });

    tearDown(() async {
      await Schema().dropIfExists('notes');
      await Schema().dropIfExists('setting');
      await Schema().dropIfExists('cast_item');
      await Schema().dropIfExists('event_posts');
    });

    test('runs beforeSave and sets the timestamps', () async {
      Note note = await Note().create(<String, dynamic>{
        'title': 'Hello World',
      });
      expect(note.id, isNotNull);
      expect(note.slug, 'hello-world');
      expect(note.createdAt, isNotNull);
      expect(note.updatedAt, isNotNull);

      /// a null value is not sent, so the column default is used
      expect(note.pinned, false);

      Map<String, dynamic>? row = await QueryBuilder.table('notes')
          .find(note.id);
      expect(row?['slug'], 'hello-world');
      expect(row?['created_at'], isNotNull);
      expect(row?['updated_at'], isNotNull);
    });

    test('insert() and firstOrCreate() set the timestamps too', () async {
      Note a = await Note().insert(<String, dynamic>{'title': 'A b'});
      Note b = await Note().firstOrCreate(<String, dynamic>{'title': 'C d'});
      expect(a.slug, 'a-b');
      expect(a.createdAt, isNotNull);
      expect(b.slug, 'c-d');
      expect(b.createdAt, isNotNull);
    });

    test('keeps created_at when the data has it', () async {
      DateTime old = DateTime.utc(2020, 1, 2, 3, 4, 5);
      Note note = await Note().create(<String, dynamic>{
        'title': 'old',
        'created_at': old,
      });
      expect(note.createdAt?.toUtc(), old);
      expect(note.updatedAt?.isAfter(old), true);
    });

    test('works without timestamps', () async {
      Setting setting = await Setting().create(<String, dynamic>{'name': 'x'});
      expect(setting.id, isNotNull);
      expect(setting.name, 'x');
    });

    test('runs the casts', () async {
      CastItem item = await CastItem().create(<String, dynamic>{
        'meta': <String, dynamic>{'a': 1},
        'tags': <String>['red'],
        'active': true,
        'status': 'live',
        'level': 2,
        'price': 1250,
      });
      expect(item.meta, <String, dynamic>{'a': 1});
      expect(item.tags, <String>['red']);
      expect(item.active, true);
      expect(item.status, Status.live);
      expect(item.level, Level.high);
      expect(item.price?.cents, 1250);

      Map<String, dynamic>? row = await QueryBuilder.table('cast_item')
          .find(item.id);
      expect(row?['status'], 'live');
      expect(row?['level'], 2);
      expect(row?['price'], 1250);

      /// a field that is not nullable keeps its default
      CastItem fresh = await CastItem().firstOrNew(<String, dynamic>{
        'status': 'draft',
      });
      expect(fresh.exists, false);
      expect(fresh.done, false);
      expect(fresh.status, Status.draft);
    });

    test('fires the hooks and sets the timestamps', () async {
      EventPost post = await EventPost().create(<String, dynamic>{
        'title': '  hi  ',
      });
      expect(EventPost.log, <String>['saving', 'creating', 'created', 'saved']);
      expect(post.title, 'hi');
      expect(post.createdAt, isNotNull);
      expect(post.updatedAt, isNotNull);
    });

    test('a hook can cancel it', () async {
      EventPost.cancelOn = 'creating';
      EventPost post = await EventPost().create(<String, dynamic>{
        'title': 'no',
      });
      expect(post.id, null);
      expect(await EventPost().withTrash().count(), 0);
    });

    test('withoutEvents() still sets the timestamps', () async {
      EventPost post = await Model.withoutEvents(() {
        return EventPost().create(<String, dynamic>{'title': 'quiet'});
      });
      expect(EventPost.log, isEmpty);
      expect(post.createdAt, isNotNull);
    });

    test('QueryBuilder.table() create stays raw', () async {
      Map<String, dynamic> row = await QueryBuilder.table('notes')
          .create(<String, dynamic>{'title': 'Raw Title'});
      expect(row['slug'], null);
      expect(row['created_at'], null);
    });
  });
}
