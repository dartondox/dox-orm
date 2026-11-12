import 'package:dox_orm/dox_orm.dart';
import 'package:test/test.dart';

import 'connection.dart';
import 'models/blog/blog.model.dart';
import 'models/blog_info/blog_info.model.dart';
import 'models/comment/comment.model.dart';
import 'models/photo/photo.model.dart';

class InfoObserver extends ModelObserver<BlogInfo> {
  List<String> log = <String>[];

  @override
  void onCreating(BlogInfo model) => log.add('creating:${model.blogId}');
}

void main() async {
  await initQueryBuilder();

  group('Relation writes |', () {
    setUp(() async {
      Model.forgetObservers();
      for (String t in <String>['blog', 'blog_info', 'photo', 'comment']) {
        await Schema().dropIfExists(t);
      }
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
        table.json('info').nullable();
        table.integer('blog_id').nullable();
        table.timestamps();
      });
      await Schema().create('photo', (Table table) {
        table.id();
        table.string('title');
        table.timestamps();
      });
      await Schema().create('comment', (Table table) {
        table.id();
        table.string('body');
        table.morphs('commentable');
        table.timestamps();
      });
    });

    tearDownAll(() async {
      Model.forgetObservers();
      for (String t in <String>['blog', 'blog_info', 'photo', 'comment']) {
        await Schema().dropIfExists(t);
      }
    });

    Future<Blog> newBlog() async {
      Blog blog = Blog()
        ..title = 'blog'
        ..description = 'body';
      await blog.save();
      return blog;
    }

    test('createRelated on hasMany sets the foreign key', () async {
      Blog blog = await newBlog();
      BlogInfo info = await blog.createRelated<BlogInfo>(
        'blogInfos',
        <String, dynamic>{
          'info': <String, dynamic>{'a': 1},
          'not_a_column': 1,
          'blog_id': 999,
        },
      );
      expect(info.blogId, blog.uid);
      expect(info.id, isNotNull);
      expect(info.createdAt, isNotNull);
      expect(info.wasRecentlyCreated, true);

      BlogInfo? row = await BlogInfo().find(info.id);
      expect(row?.blogId, blog.uid);
      expect(row?.info, <String, dynamic>{'a': 1});
    });

    test('createRelated fires the model events', () async {
      InfoObserver observer = InfoObserver();
      Model.observe<BlogInfo>(observer);
      Blog blog = await newBlog();
      await blog.createRelated<BlogInfo>('blogInfo', <String, dynamic>{});
      expect(observer.log, <String>['creating:${blog.uid}']);
    });

    test('saveRelated and saveManyRelated', () async {
      Blog blog = await newBlog();
      BlogInfo one = BlogInfo();
      expect(await blog.saveRelated('blogInfo', one), true);
      expect(one.blogId, blog.uid);
      expect(one.id, isNotNull);

      BlogInfo a = BlogInfo();
      BlogInfo b = BlogInfo()..blogId = 999;
      expect(await blog.saveManyRelated('blogInfos', <BlogInfo>[a, b]), true);
      expect(await BlogInfo().where('blog_id', blog.uid).count(), 3);

      await blog.reload();
      expect(blog.blogInfos.length, 3);
    });

    test('createRelated on morphMany sets the type column', () async {
      Photo photo = await Photo().create(<String, dynamic>{'title': 'p'});
      Comment c = await photo.createRelated<Comment>(
        'comments',
        <String, dynamic>{
          'body': 'hi',
          'commentable_id': 999,
          'commentable_type': 'other',
        },
      );
      expect(c.commentableId, photo.id);
      expect(c.commentableType, Model.morphTypeOf(photo));

      await photo.saveRelated('latestComment', Comment()..body = 'x');
      await photo.$getRelation<dynamic>('comments');
      expect(photo.comments.length, 2);
    });

    test('associate and dissociate on belongsTo', () async {
      Blog blog = await newBlog();
      BlogInfo info = BlogInfo();
      expect(info.associate('blog', blog), info);
      expect(info.blogId, blog.uid);
      await info.save();
      BlogInfo? row = await BlogInfo().find(info.id);
      expect(row?.blogId, blog.uid);

      info.dissociate('blog');
      expect(info.blogId, isNull);
      await info.save();
      row = await BlogInfo().find(info.id);
      expect(row?.blogId, isNull);
    });

    test('wrong relation kind or name throws', () async {
      Blog blog = await newBlog();
      expect(
        () => blog.associate('blogInfos', blog),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => blog.createRelated<BlogInfo>('nope', <String, dynamic>{}),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => BlogInfo().saveRelated('blog', Blog()),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a parent with no key throws', () async {
      expect(
        () => Blog().saveRelated('blogInfos', BlogInfo()),
        throwsA(isA<StateError>()),
      );
      expect(
        () => BlogInfo().associate('blog', Blog()),
        throwsA(isA<StateError>()),
      );
    });
  });
}
