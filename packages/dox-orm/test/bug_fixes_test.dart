import 'package:dox_orm/dox_orm.dart';
import 'package:test/test.dart';

import 'connection.dart';
import 'models/author/author.model.dart';
import 'models/blog/blog.model.dart';
import 'models/blog_info/blog_info.model.dart';

void main() async {
  await initQueryBuilder();

  bool isMysql() => SqlQueryBuilder().dbDriver.getName() == Driver.mysql;

  Future<bool> isMariaDb() async {
    if (!isMysql()) return false;
    List<Map<String, dynamic>> rows = await QueryBuilder.query(
      'SELECT VERSION() as v',
    );
    return rows.first['v'].toString().contains('MariaDB');
  }

  group('Bug fixes |', () {
    setUp(() async {
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
    });

    tearDown(() async {
      await Schema().dropIfExists('blog');
      await Schema().dropIfExists('blog_info');
    });

    test('save can set a field to null on update', () async {
      Blog blog = Blog();
      blog.title = 'title';
      blog.description = 'body';
      blog.slug = 'slug';
      await blog.save();

      blog.slug = null;
      await blog.save();
      Blog? saved = await Blog().find(blog.uid);
      expect(saved?.slug, null);

      saved?.slug = 'again';
      await saved?.save();
      Blog? loaded = await Blog().find(blog.uid);
      expect(loaded?.slug, 'again');

      loaded?.slug = null;
      await loaded?.save();
      Blog? cleared = await Blog().find(blog.uid);
      expect(cleared?.slug, null);
      expect(cleared?.status, 'active');
    });

    test('save on a model loaded with select keeps other columns', () async {
      Blog blog = Blog();
      blog.title = 'title';
      blog.description = 'body';
      blog.slug = 'slug';
      await blog.save();

      Blog? partial = await Blog().select('uid, title').find(blog.uid);
      partial?.title = 'new title';
      await partial?.save();

      Blog? found = await Blog().find(blog.uid);
      expect(found?.title, 'new title');
      expect(found?.slug, 'slug');
      expect(found?.description, 'body');
    });

    test('insert with uuid primary key', () async {
      await Schema().create('uuid_item', (Table table) {
        table.uuid('id');
        table.string('name');
      });
      String id = '6f1c8d2e-4b7a-4e3f-9c1d-2a5b6c7d8e9f';
      Map<String, dynamic> row = await QueryBuilder.table('uuid_item')
          .setPrimaryKey('id')
          .insert(<String, dynamic>{'id': id, 'name': 'x'});
      await Schema().dropIfExists('uuid_item');
      expect(row['id'], id);
      expect(row['name'], 'x');
    });

    test('relations with a custom local key', () async {
      await Schema().create('author', (Table table) {
        table.id();
        table.string('code');
      });
      await Schema().create('book', (Table table) {
        table.id();
        table.string('title');
        table.string('author_code');
      });
      await Schema().create('tag', (Table table) {
        table.id();
        table.string('title');
      });
      await Schema().create('author_tag', (Table table) {
        table.id();
        table.string('author_code');
        table.integer('tag_id');
      });

      /// ids and codes do not match, so using the id would find nothing
      await QueryBuilder.table('author').insertMultiple(<Map<String, dynamic>>[
        <String, dynamic>{'code': 'B'},
        <String, dynamic>{'code': 'A'},
      ]);
      await QueryBuilder.table('book').insertMultiple(<Map<String, dynamic>>[
        <String, dynamic>{'title': 'b1', 'author_code': 'A'},
        <String, dynamic>{'title': 'b2', 'author_code': 'A'},
      ]);
      await QueryBuilder.table('tag').insert(<String, dynamic>{'title': 't1'});
      await QueryBuilder.table('author_tag')
          .insert(<String, dynamic>{'author_code': 'A', 'tag_id': 1});

      List<Author> authors = await Author()
          .preload('books')
          .preload('firstBook')
          .preload('tags')
          .orderBy('id')
          .get();

      await Schema().dropIfExists('author');
      await Schema().dropIfExists('book');
      await Schema().dropIfExists('tag');
      await Schema().dropIfExists('author_tag');

      Author b = authors.first;
      Author a = authors.last;
      expect(a.code, 'A');
      expect(a.books.length, 2);
      expect(a.firstBook?.authorCode, 'A');
      expect(a.tags.length, 1);
      expect(b.books.length, 0);
      expect(b.firstBook, null);

      /// a two word relation is in toJson() with a snake case key
      expect(a.toJson()['first_book']['author_code'], 'A');
      expect(a.toJson().containsKey('books'), true);
      expect(b.tags.length, 0);
    });

    test('json arrays are decoded and plain text is not', () async {
      await QueryBuilder.table('blog_info')
          .insert(<String, dynamic>{'info': '[1, 2]', 'blog_id': 1});
      Map<String, dynamic>? info = await QueryBuilder.table('blog_info')
          .getFirst();
      expect(info?['info'], <int>[1, 2]);

      await QueryBuilder.table('blog')
          .setPrimaryKey('uid')
          .insert(<String, dynamic>{'title': 't', 'body': '{"a": 1}'});
      Map<String, dynamic>? blog = await QueryBuilder.table('blog').getFirst();

      /// mariadb can not tell text from json, see docs
      if (await isMariaDb()) {
        expect(blog?['body'], <String, dynamic>{'a': 1});
      } else {
        expect(blog?['body'], '{"a": 1}');
      }
    });

    test('a Dart list goes into a json column', () async {
      await QueryBuilder.table('blog_info').insert(<String, dynamic>{
        'info': <int>[1, 2],
        'blog_id': 1,
      });
      await QueryBuilder.table('blog_info')
          .where('blog_id', 1)
          .update(<String, dynamic>{
            'info': <dynamic>['a', 3],
          });
      Map<String, dynamic>? info = await QueryBuilder.table('blog_info')
          .getFirst();
      expect(info?['info'], <dynamic>['a', 3]);
    });

    test('withTrash(false) on a model without soft deletes', () async {
      await QueryBuilder.table('blog_info')
          .insert(<String, dynamic>{'info': '{}', 'blog_id': 1});
      int total = await BlogInfo().withTrash(false).count();
      expect(total, 1);
    });

    test('forceDelete removes soft deleted rows', () async {
      await Blog().insertMultiple(<Map<String, dynamic>>[
        <String, dynamic>{'title': 'title 1', 'body': 'body 1'},
        <String, dynamic>{'title': 'title 2', 'body': 'body 2'},
      ]);
      await Blog().where('uid', 1).delete();
      await Blog().where('uid', 1).forceDelete();
      int total = await Blog().withTrash().count();
      expect(total, 1);
    });

    test('model delete only deletes that row', () async {
      await Blog().insertMultiple(<Map<String, dynamic>>[
        <String, dynamic>{'title': 'title 1', 'body': 'body 1'},
        <String, dynamic>{'title': 'title 2', 'body': 'body 2'},
      ]);
      Blog? blog = await Blog().find(1);
      await blog?.delete();
      expect(await Blog().count(), 1);

      Blog? other = await Blog().find(2);
      await other?.forceDelete();
      expect(await Blog().withTrash().count(), 1);
    });

    test('count ignores limit, offset and order by', () async {
      await Blog().insertMultiple(<Map<String, dynamic>>[
        <String, dynamic>{'title': 'c', 'body': 'body'},
        <String, dynamic>{'title': 'a', 'body': 'body'},
        <String, dynamic>{'title': 'b', 'body': 'body'},
      ]);
      expect(await Blog().limit(1).offset(1).count(), 3);
      expect(await Blog().orderBy('title').limit(2).count(), 3);
    });

    test('insert multiple uses keys from all rows', () async {
      await Blog().insertMultiple(<Map<String, dynamic>>[
        <String, dynamic>{'title': 'title 1', 'body': 'body 1'},
        <String, dynamic>{
          'title': 'title 2',
          'body': 'body 2',
          'slug': 's',
          'status': 'draft',
        },
      ]);
      List<Map<String, dynamic>> rows = await QueryBuilder.table('blog')
          .orderBy('uid')
          .get();
      expect(rows.first['slug'], null);
      expect(rows.first['status'], 'active');
      expect(rows.last['slug'], 's');
      expect(rows.last['status'], 'draft');
    });

    test('reserved words as table and column names', () async {
      await Schema().create('order', (Table table) {
        table.id();
        table.string('key');
        table.string('group').nullable();
      });
      await QueryBuilder.table('order').insertMultiple(<Map<String, dynamic>>[
        <String, dynamic>{'key': 'b', 'group': 'g'},
        <String, dynamic>{'key': 'a', 'group': 'g'},
      ]);
      await QueryBuilder.table('order')
          .where('key', 'a')
          .update(<String, dynamic>{'group': 'h'});
      List<Map<String, dynamic>> rows = await QueryBuilder.table('order')
          .select(<String>['order.key', 'group as grp'])
          .where('order.key', '!=', 'z')
          .orderBy('key')
          .get();
      String group = SqlQueryBuilder().dbDriver.wrap('group');
      List<Map<String, dynamic>> groups = await QueryBuilder.table('order')
          .selectRaw('$group, count(*) as total')
          .groupBy('group')
          .get();
      int total = await QueryBuilder.table('order').groupBy('group').count();
      await Schema().dropIfExists('order');

      expect(rows.first['key'], 'a');
      expect(rows.first['grp'], 'h');
      expect(groups.length, 2);
      expect(total, 2);
    });

    test('a negative limit is ignored', () async {
      for (String s in <String>['a', 'b', 'c']) {
        await (Blog()
              ..title = s
              ..description = s)
            .save();
      }
      expect(Blog().limit(-1).toSql(), isNot(contains('LIMIT')));
      expect(await Blog().limit(-1).get(), hasLength(3));
      expect(await Blog().limit(2).limit(-1).get(), hasLength(2));
      expect(await Blog().take(-1).get(), hasLength(3));
    });

    test('having with null builds IS NULL and IS NOT NULL', () async {
      await (Blog()
            ..title = 'a'
            ..description = 'a'
            ..slug = 'x')
          .save();
      await (Blog()
            ..title = 'b'
            ..description = 'b')
          .save();
      QueryBuilder<dynamic> notNull() =>
          QueryBuilder.table('blog').select('slug').groupBy('slug');
      String sql = notNull().having('slug', '!=', null).toSql();
      expect(sql, contains('IS NOT NULL'));
      expect(sql, isNot(contains('!=')));
      List<dynamic> rows = await notNull().having('slug', '!=', null).get();
      expect(rows.map((dynamic r) => r['slug']), <String>['x']);
      rows = await notNull().having('slug', '=', null).get();
      expect(rows.map((dynamic r) => r['slug']), <String?>[null]);
      rows = await notNull().having('slug', null).get();
      expect(rows.map((dynamic r) => r['slug']), <String?>[null]);
    });

    test('restore on a query restores the matching rows', () async {
      for (String s in <String>['old', 'old', 'new']) {
        await (Blog()
              ..title = s
              ..description = s
              ..status = s)
            .save();
      }
      await Blog().where('status', 'old').delete();
      await Blog().where('status', 'new').delete();
      expect(await Blog().get(), isEmpty);

      Blog query = Blog().where('status', 'old') as Blog;
      expect(await query.restore(), true);
      List<Blog> blogs = await Blog().get();
      expect(blogs.map((Blog b) => b.status), <String>['old', 'old']);

      /// nothing left to restore
      query = Blog().where('status', 'none') as Blog;
      expect(await query.restore(), false);

      /// no where: it does not restore every row
      expect(() => Blog().restore(), throwsStateError);
      expect(await Blog().get(), hasLength(2));

      /// restore on a loaded model still works
      Blog? trashed = await Blog()
          .withTrash()
          .where('status', 'new')
          .getFirst();
      expect(await trashed!.restore(), true);
      expect(await Blog().get(), hasLength(3));
    });

    test('soft delete sets updated_at and deletedAt', () async {
      Blog blog = Blog()
        ..title = 'a'
        ..description = 'a';
      await blog.save();
      DateTime old = DateTime.utc(2020);
      await Blog().where('uid', blog.uid).update(<String, dynamic>{
        'updated_at': old,
      });
      blog = (await Blog().find(blog.uid))!;

      await blog.delete();
      expect(blog.deletedAt, isNotNull);
      expect(blog.updatedAt!.isAfter(old), isTrue);
      Blog? row = await Blog().withTrash().find(blog.uid);
      expect(row!.deletedAt, isNotNull);
      expect(row.updatedAt!.isAfter(old), isTrue);

      await blog.restore();
      expect(blog.deletedAt, isNull);

      /// a query soft delete sets updated_at too
      await Blog().where('uid', blog.uid).update(<String, dynamic>{
        'updated_at': old,
      });
      await Blog().where('uid', blog.uid).delete();
      row = await Blog().withTrash().find(blog.uid);
      expect(row!.updatedAt!.isAfter(old), isTrue);
    });

    test('restore on a query skips rows that are not deleted', () async {
      await (Blog()
            ..title = 'a'
            ..description = 'a'
            ..status = 'live')
          .save();

      /// the row matches, but it is not deleted: nothing to restore, on
      /// every database (MySQL counts only changed rows)
      Blog query = Blog().where('status', 'live') as Blog;
      expect(await query.restore(), false);
    });

    test('find with a column and null finds IS NULL', () async {
      Blog withSlug = Blog()
        ..title = 'a'
        ..description = 'a'
        ..slug = 'x';
      await withSlug.save();
      Blog noSlug = Blog()
        ..title = 'b'
        ..description = 'b';
      await noSlug.save();
      Blog? found = await Blog().find('slug', null);
      expect(found?.uid, noSlug.uid);
      expect((await Blog().find('slug', 'x'))?.uid, withSlug.uid);
      expect((await Blog().find(withSlug.uid))?.uid, withSlug.uid);
      expect((await Blog().findOrFail('slug', null)).uid, noSlug.uid);
    });

    test('find(5, null) gives a clear error', () async {
      expect(
        () => Blog().find(5, null),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => '${e.message}',
            'message',
            contains('column name'),
          ),
        ),
      );
      expect(() => Blog().findOrFail(5, null), throwsArgumentError);
    });

    Future<List<Blog>> threeBlogs() async {
      List<Blog> blogs = <Blog>[];
      for (String status in <String>['x', 'y', 'z']) {
        Blog blog = Blog()
          ..title = status
          ..description = status
          ..status = status;
        await blog.save();
        blogs.add(blog);
      }
      return blogs;
    }

    test('fromSub on a model uses the alias', () async {
      List<Blog> blogs = await threeBlogs();
      await blogs[1].delete();
      QueryBuilder<Map<String, dynamic>> sub() =>
          QueryBuilder.table('blog').select('uid, title, deleted_at');

      /// the soft delete check uses `b.deleted_at`, not `blog.deleted_at`
      List<Blog> rows = await Blog().fromSub(sub(), 'b').orderBy('uid').get();
      expect(rows.map((Blog b) => b.title), <String>['x', 'z']);
      expect(await Blog().fromSub(sub(), 'b').count(), 2);

      /// chunk() orders by `b.uid`
      List<String?> titles = <String?>[];
      await Blog().fromSub(sub(), 'b').chunk(1, (List<Blog> page) {
        titles.addAll(page.map((Blog b) => b.title));
        return true;
      });
      expect(titles, <String>['x', 'z']);
    });

    test('update and delete after fromSub on a model', () async {
      List<Blog> blogs = await threeBlogs();
      int id = blogs[0].uid!;
      Blog q() => Blog()
        ..fromSub(QueryBuilder.table('blog').select('uid'), 'b')
        ..where('uid', id);

      /// writes run on the real table, so the soft delete check uses
      /// `blog.deleted_at`, not `b.deleted_at`
      expect(await q().update(<String, dynamic>{'title': 'new'}), 1);
      expect((await Blog().find(id))?.title, 'new');
      expect(await q().delete(), 1);
      expect(await Blog().find(id), isNull);
      expect(await q().restore(), isTrue);
      expect((await Blog().find(id))?.title, 'new');
    });

    group('union guards |', () {
      QueryBuilder<Map<String, dynamic>> q() =>
          QueryBuilder.table('blog')
              .where('status', 'zzz')
              .union(QueryBuilder.table('blog').where('status', 'y'));
      Blog blogs() => Blog()
        ..where('status', 'zzz')
        ..union(Blog().where('status', 'y'));
      Map<String, dynamic> where = <String, dynamic>{'title': 'x'};
      Map<String, dynamic> values = <String, dynamic>{'body': 'b'};

      setUp(threeBlogs);

      /// a Future, not a sync throw: find() fails like findOrFail()
      test('find', () async {
        await expectLater(q().find(1), throwsStateError);
        await expectLater(q().find('title', 'x'), throwsStateError);
      });

      test('findOrFail', () async {
        await expectLater(q().findOrFail(1), throwsStateError);
      });

      test('pluck', () {
        expect(() => q().pluck('title'), throwsStateError);
      });

      test('pluckMap', () {
        expect(() => q().pluckMap('title', 'uid'), throwsStateError);
      });

      test('valueOf', () {
        expect(() => q().valueOf('title'), throwsStateError);
      });

      test('firstOrNew', () async {
        await expectLater(q().firstOrNew(where), throwsStateError);
      });

      test('firstOrCreate writes nothing', () async {
        await expectLater(q().firstOrCreate(where, values), throwsStateError);
        expect(await Blog().count(), 3);
      });

      test('updateOrCreate writes nothing', () async {
        await expectLater(q().updateOrCreate(where, values), throwsStateError);
        expect(await Blog().count(), 3);
      });

      /// a model has its own firstOrNew() and updateOrCreate()
      test('model firstOrNew', () async {
        await expectLater(blogs().firstOrNew(where), throwsStateError);
      });

      test('model firstOrCreate writes nothing', () async {
        await expectLater(
          blogs().firstOrCreate(where, values),
          throwsStateError,
        );
        expect(await Blog().count(), 3);
      });

      test('model updateOrCreate writes nothing', () async {
        await expectLater(
          blogs().updateOrCreate(where, values),
          throwsStateError,
        );
        expect(await Blog().count(), 3);
      });

      /// getFirst() and firstOrFail() put LIMIT 1 on the whole union, so
      /// they give the right row
      test('getFirst and firstOrFail work', () async {
        expect((await q().getFirst())?['status'], 'y');
        expect((await q().firstOrFail())['status'], 'y');
      });
    });
  });

  group('Schema fixes |', () {
    tearDown(() async {
      await Schema().dropIfExists('schema_fix');
    });

    test('unique on an existing column with change()', () async {
      await Schema().create('schema_fix', (Table table) {
        table.id();
        table.string('slug').nullable();
      });
      await Schema().table('schema_fix', (Table table) {
        table.string('slug').unique().nullable().change();
      });
      await QueryBuilder.table('schema_fix')
          .insert(<String, dynamic>{'slug': 'a'});
      expect(
        () =>
            QueryBuilder.table('schema_fix')
                .insert(<String, dynamic>{'slug': 'a'}),
        throwsA(anything),
      );
    });

    test('default value with a quote', () async {
      await Schema().create('schema_fix', (Table table) {
        table.id();
        table.string('name').withDefault("it's");
        table.string('other').nullable();
      });
      await Schema().table('schema_fix', (Table table) {
        table.string('other').nullable().withDefault("o'k").change();
      });
      await QueryBuilder.table('schema_fix').insert(<String, dynamic>{'id': 1});
      Map<String, dynamic>? row = await QueryBuilder.table('schema_fix')
          .getFirst();
      expect(row?['name'], "it's");
      expect(row?['other'], "o'k");
    });
  });

  test('snake case keeps a digit with the word before it', () {
    Blog blog = Blog();
    expect(blog.helper.toSnakeCase('Address2'), 'address2');
    expect(blog.helper.toSnakeCase('BlogInfo'), 'blog_info');
    expect(blog.helper.toSnakeCase('blog_info'), 'blog_info');
  });
}
