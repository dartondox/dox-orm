import 'package:dox_orm/dox_orm.dart';
import 'package:test/test.dart';

import 'connection.dart';
import 'models/blog/blog.model.dart';
import 'models/blog_info/blog_info.model.dart';
import 'models/cast_item/cast_item.model.dart';
import 'models/event_post/event_post.model.dart';

void main() async {
  await initQueryBuilder();

  setUp(() async {
    EventPost.log = <String>[];
    EventPost.cancelOn = null;
    EventPost.failOn = null;
    await Schema().create('blog', (Table table) {
      table.id('uid');
      table.string('title');
      table.string('status').withDefault('active');
      table.text('body');
      table.string('slug').nullable();
      table.softDeletes();
      table.timestamps();
    });
    await Schema().create('blog_info', (Table table) {
      table.id();
      table.json('info');
      table.integer('blog_id');
      table.timestamps();
    });
    await Schema().create('event_posts', (Table table) {
      table.id();
      table.string('title').nullable();
      table.softDeletes();
      table.timestamps();
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
    await Schema().create('stamped_rows', (Table table) {
      table.id();
      table.string('title').nullable();
      table.dateTime('made_on').nullable();
      table.dateTime('changed_on').nullable();
    });
  });

  tearDown(() async {
    for (String table in <String>[
      'blog',
      'blog_info',
      'event_posts',
      'cast_item',
      'stamped_rows',
    ]) {
      await Schema().dropIfExists(table);
    }
  });

  Future<Blog> newBlog() async {
    Blog blog = Blog()
      ..title = 'a'
      ..description = 'body';
    await blog.save();
    return (await Blog().find(blog.uid))!;
  }

  group('dirty tracking |', () {
    test('a new model is dirty for the columns with a value', () {
      Blog blog = Blog()
        ..title = 'a'
        ..description = 'body';
      expect(blog.isDirty(), isTrue);
      expect(blog.isDirty('title'), isTrue);

      /// the column name, not the Dart field name
      expect(blog.isDirty('body'), isTrue);
      expect(blog.isDirty('slug'), isFalse);
      expect(blog.getDirty(), <String, dynamic>{'title': 'a', 'body': 'body'});
      expect(blog.getOriginal(), <String, dynamic>{});
      expect(blog.getOriginal('title'), isNull);
      expect(blog.getChanges(), <String, dynamic>{});
      expect(blog.wasRecentlyCreated, isFalse);
    });

    test('a loaded model is clean', () async {
      Blog blog = await newBlog();
      expect(blog.isDirty(), isFalse);
      expect(blog.isClean(), isTrue);
      expect(blog.getDirty(), <String, dynamic>{});
      expect(blog.getOriginal('title'), 'a');
      expect(blog.getOriginal('body'), 'body');
      expect(blog.wasRecentlyCreated, isFalse);
      expect(blog.getChanges(), <String, dynamic>{});
    });

    test('set a field', () async {
      Blog blog = await newBlog();
      blog.description = 'new body';
      expect(blog.isDirty(), isTrue);
      expect(blog.isDirty('body'), isTrue);
      expect(blog.isDirty('title'), isFalse);
      expect(blog.isDirty(<String>['title', 'body']), isTrue);
      expect(blog.isDirty(<String>['title', 'slug']), isFalse);
      expect(blog.isClean('title'), isTrue);
      expect(blog.isClean(<String>['title', 'body']), isFalse);
      expect(blog.getDirty(), <String, dynamic>{'body': 'new body'});
      expect(blog.getOriginal('body'), 'body');

      /// set it back: clean again
      blog.description = 'body';
      expect(blog.isDirty(), isFalse);
    });

    test('a wrong columns type throws', () async {
      Blog blog = await newBlog();
      expect(() => blog.isDirty(1), throwsArgumentError);
    });

    test('after an insert', () async {
      Blog blog = Blog()
        ..title = 'a'
        ..description = 'body';
      await blog.save();
      expect(blog.wasRecentlyCreated, isTrue);
      expect(blog.isDirty(), isFalse);
      expect(blog.getChanges(), <String, dynamic>{});
      expect(blog.getOriginal('title'), 'a');
    });

    test('create() sets wasRecentlyCreated, with and without events', () async {
      Blog blog = await Blog().create(<String, dynamic>{
        'title': 'a',
        'body': 'b',
      });
      expect(blog.wasRecentlyCreated, isTrue);
      expect(blog.isDirty(), isFalse);

      EventPost post = await EventPost().create(<String, dynamic>{
        'title': 'p',
      });
      expect(post.wasRecentlyCreated, isTrue);
      expect(post.isDirty(), isFalse);

      EventPost found = (await EventPost().find(post.id))!;
      expect(found.wasRecentlyCreated, isFalse);
    });

    test('firstOrCreate() tells a new row from a found one', () async {
      Blog made = await Blog().firstOrCreate(
        <String, dynamic>{'title': 'x'},
        <String, dynamic>{'body': 'b'},
      );
      expect(made.wasRecentlyCreated, isTrue);
      Blog found = await Blog().firstOrCreate(
        <String, dynamic>{'title': 'x'},
        <String, dynamic>{'body': 'b'},
      );
      expect(found.wasRecentlyCreated, isFalse);
    });

    test('after an update', () async {
      Blog blog = await newBlog();
      blog.description = 'new body';
      await blog.save();
      expect(blog.isDirty(), isFalse);
      expect(blog.wasRecentlyCreated, isFalse);
      expect(blog.wasChanged(), isTrue);
      expect(blog.wasChanged('body'), isTrue);
      expect(blog.wasChanged('updated_at'), isTrue);
      expect(blog.wasChanged('title'), isFalse);
      expect(blog.wasChanged(<String>['title', 'body']), isTrue);
      expect(
        blog.getChanges().keys,
        unorderedEquals(<String>['body', 'updated_at']),
      );
      expect(blog.getChanges()['body'], 'new body');
      expect(blog.getOriginal('body'), 'new body');

      /// a save with no changes clears getChanges()
      await blog.save();
      expect(blog.getChanges(), <String, dynamic>{});
      expect(blog.wasChanged(), isFalse);
    });

    test('a date field compares by time', () async {
      Blog blog = await newBlog();
      DateTime when = DateTime.utc(2024, 1, 2, 3, 4, 5);
      blog.deletedAt = when;
      expect(blog.isDirty('deleted_at'), isTrue);
      await blog.save();
      expect(blog.isDirty(), isFalse);

      Blog read = (await Blog().withTrash().find(blog.uid))!;
      expect(read.isDirty(), isFalse);

      read.deletedAt = when;
      expect(read.isDirty('deleted_at'), isFalse);
      read.deletedAt = when.add(const Duration(seconds: 1));
      expect(read.isDirty('deleted_at'), isTrue);
    });

    test('a json column is clean after a load', () async {
      BlogInfo info = BlogInfo()
        ..info = <String, dynamic>{'a': 1}
        ..blogId = 1;
      await info.save();
      BlogInfo read = (await BlogInfo().find(info.id))!;
      expect(read.isDirty(), isFalse);
      read.info = <String, dynamic>{'a': 2};
      expect(read.isDirty('info'), isTrue);
    });

    test('a model with casts is clean after a load', () async {
      CastItem item = CastItem()
        ..meta = <String, dynamic>{'a': 1}
        ..tags = <String>['red']
        ..active = true
        ..done = true
        ..status = Status.live
        ..level = Level.high
        ..price = const Money(250);
      await item.save();
      expect(item.isDirty(), isFalse);
      CastItem read = (await CastItem().find(item.id))!;
      expect(read.getDirty(), <String, dynamic>{});
      read.status = Status.draft;
      expect(read.getDirty(), <String, dynamic>{'status': 'draft'});
    });

    test('after increment()', () async {
      BlogInfo info = BlogInfo()
        ..info = <String, dynamic>{'a': 1}
        ..blogId = 1;
      await info.save();
      BlogInfo read = (await BlogInfo().find(info.id))!;
      await read.increment('blog_id', 2);
      expect(read.blogId, 3);
      expect(read.isDirty(), isFalse);
      expect(read.wasChanged('blog_id'), isTrue);
      expect(read.getChanges(), <String, dynamic>{'blog_id': 3});
      expect(read.getOriginal('blog_id'), 3);
    });

    test('after update() on the model', () async {
      Blog blog = await newBlog();
      await blog.update(<String, dynamic>{'title': 'b'});
      expect(blog.isDirty(), isFalse);
      expect(blog.wasChanged('title'), isTrue);
      expect(blog.wasChanged('updated_at'), isTrue);
      expect(blog.wasChanged('body'), isFalse);
    });

    test('a cancelled save keeps the model dirty', () async {
      EventPost post = await EventPost().create(<String, dynamic>{
        'title': 'p',
      });
      post.title = 'q';
      EventPost.cancelOn = 'updating';
      expect(await post.save(), isFalse);
      expect(post.isDirty('title'), isTrue);
      expect(post.getOriginal('title'), 'p');
      expect(post.wasChanged(), isFalse);

      EventPost.cancelOn = null;
      expect(await post.save(), isTrue);
      expect(post.isDirty(), isFalse);
      expect(post.wasChanged('title'), isTrue);
    });

    test('a cancelled create is not wasRecentlyCreated', () async {
      EventPost.cancelOn = 'creating';
      EventPost post = await EventPost().create(<String, dynamic>{
        'title': 'p',
      });
      expect(post.wasRecentlyCreated, isFalse);
      expect(post.isDirty('title'), isTrue);
    });

    test('a failed update keeps the model dirty', () async {
      Blog blog = await newBlog();
      blog.description = 'new body';
      await Schema().dropIfExists('blog');
      await expectLater(blog.save(), throwsA(anything));
      expect(blog.isDirty('body'), isTrue);
      expect(blog.wasChanged(), isFalse);
    });

    test('custom timestamp columns', () async {
      StampedRow row = StampedRow()..title = 'a';
      await row.save();
      expect(row.wasRecentlyCreated, isTrue);
      expect(row.isDirty(), isFalse);

      StampedRow read = (await StampedRow().find(row.id))!;
      expect(read.isDirty(), isFalse);
      expect(read.getOriginal('changed_on'), isNotNull);

      read.title = 'b';
      await read.save();
      expect(read.isDirty(), isFalse);
      expect(
        read.getChanges().keys,
        unorderedEquals(<String>['title', 'changed_on']),
      );
    });
  });
}

DateTime? _date(dynamic v) => v is DateTime ? v : DateTime.tryParse('$v');

/// a hand-written model with `made_on` and `changed_on` as timestamps
class StampedRow extends Model<StampedRow> {
  @override
  List<String> get guarded => const <String>[];
  int? get id => tempIdValue as int?;
  set id(int? value) => tempIdValue = value;

  String? title;

  @override
  String get tableName => 'stamped_rows';

  @override
  Map<String, dynamic> get timestampsColumn => const <String, dynamic>{
    'created_at': 'made_on',
    'updated_at': 'changed_on',
  };

  @override
  List<String> get tableColumns => const <String>[
    'id',
    'title',
    'made_on',
    'changed_on',
  ];

  @override
  StampedRow fromMap(Map<String, dynamic> m) => StampedRow()
    ..id = m['id'] as int?
    ..title = m['title'] as String?
    ..createdAt = _date(m['made_on'])
    ..updatedAt = _date(m['changed_on']);

  @override
  Map<String, dynamic> columnsToMap() => <String, dynamic>{
    'id': id,
    'title': title,
    'made_on': createdAt,
    'changed_on': updatedAt,
  };

  @override
  Map<String, dynamic> convertToMap(dynamic i) =>
      (i as StampedRow).columnsToMap();

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
