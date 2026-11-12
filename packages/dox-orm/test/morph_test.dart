import 'package:dox_orm/dox_orm.dart';
import 'package:test/test.dart';

import 'connection.dart';
import 'models/comment/comment.model.dart';
import 'models/photo/photo.model.dart';
import 'models/video/video.model.dart';

void main() async {
  await initQueryBuilder();

  group('Morph |', () {
    tearDownAll(() async {
      for (String t in <String>['photo', 'video', 'comment']) {
        await Schema().dropIfExists(t);
      }
    });

    setUp(() async {
      Model.morphMap(<String, Model<dynamic> Function()>{}, merge: false);
      for (String t in <String>['photo', 'video', 'comment']) {
        await Schema().dropIfExists(t);
      }
      for (String t in <String>['photo', 'video']) {
        await Schema().create(t, (Table table) {
          table.id();
          table.string('title');
          table.timestamps();
        });
      }
      await Schema().create('comment', (Table table) {
        table.id();
        table.string('body');
        table.morphs('commentable');
        table.timestamps();
      });
      await Photo().insertMultiple(<Map<String, dynamic>>[
        <String, dynamic>{'title': 'photo 1'},
        <String, dynamic>{'title': 'photo 2'},
      ]);
      await Video().insertMultiple(<Map<String, dynamic>>[
        <String, dynamic>{'title': 'video 1'},
      ]);
    });

    Future<void> addComments(String photo, String video) async {
      await Comment().insertMultiple(<Map<String, dynamic>>[
        <String, dynamic>{
          'body': 'a',
          'commentable_id': 1,
          'commentable_type': photo,
        },
        <String, dynamic>{
          'body': 'b',
          'commentable_id': 1,
          'commentable_type': photo,
        },
        <String, dynamic>{
          'body': 'c',
          'commentable_id': 1,
          'commentable_type': video,
        },
        <String, dynamic>{
          'body': 'd',
          'commentable_id': 2,
          'commentable_type': photo,
        },
      ]);
    }

    test('morphMany and morphOne use the class name by default', () async {
      expect(Model.morphTypeOf(Photo()), 'Photo');
      await addComments('Photo', 'Video');

      List<Photo> photos = await Photo()
          .preload('comments')
          .preload('latestComment')
          .orderBy('id')
          .get();
      expect(
        photos[0].comments.map((Comment c) => c.body).toList()..sort(),
        <String>['a', 'b'],
      );
      expect(photos[1].comments.map((Comment c) => c.body), <String>['d']);
      expect(photos[0].latestComment?.body, 'b');

      Video? video = await Video().preload('comments').find(1);
      expect(video!.comments.map((Comment c) => c.body), <String>['c']);
      expect(video.toMap()['comments'], hasLength(1));
    });

    test('morph map names, morphTo and related()', () async {
      Model.morphMap(<String, Model<dynamic> Function()>{
        'photo': Photo.new,
        'video': Video.new,
      });
      expect(Model.morphTypeOf(Video()), 'video');
      await addComments('photo', 'video');

      Photo? photo = await Photo().preload('comments').find(1);
      expect(photo!.comments, hasLength(2));

      List<Comment> comments = await Comment()
          .preload('commentable')
          .orderBy('id')
          .get();
      expect(comments[0].commentable, isA<Photo>());
      expect((comments[0].commentable as Photo).title, 'photo 1');
      expect(comments[2].commentable, isA<Video>());
      expect((comments[2].commentable as Video).title, 'video 1');
      expect((comments[3].commentable as Photo).title, 'photo 2');
      expect(comments[2].toMap()['commentable']['title'], 'video 1');

      /// the query of one comment
      Photo? parent = await comments[3]
          .related<Photo>('commentable')
          ?.getFirst();
      expect(parent?.title, 'photo 2');

      /// a where of preload() is used for the query of each type,
      /// and a dot path loads the comments of each parent
      List<Comment> some = await Comment()
          .preload('commentable', (QueryBuilder<dynamic> q) {
            q.where('title', 'like', '% 1');
          })
          .preload('commentable.comments')
          .orderBy('id')
          .get();
      expect((some[0].commentable as Photo).comments, hasLength(2));
      expect(some[2].commentable, isA<Video>());
      expect((some[2].commentable as Video).comments, hasLength(1));
      expect(some[3].commentable, isNull);

      /// only Photo has latestComment: the Video query skips it, also
      /// with preloadUnknownThrows on. A name no type has still throws.
      SqlQueryBuilder().flags = const OrmFlags(preloadUnknownThrows: true);
      try {
        List<Comment> mixed = await Comment()
            .preload('commentable.latestComment')
            .orderBy('id')
            .get();
        expect((mixed[0].commentable as Photo).latestComment?.body, 'b');
        expect((mixed[2].commentable as Video).title, 'video 1');
        await expectLater(
          Comment().preload('commentable.typo').get(),
          throwsA(isA<ArgumentError>()),
        );
      } finally {
        SqlQueryBuilder().flags = const OrmFlags();
      }

      /// a lazy load
      Comment c = (await Comment().find(3))!;
      await c.$getRelation<dynamic>('commentable');
      expect(c.commentable, isA<Video>());
    });

    test('whereHas works with morphMany', () async {
      await addComments('Photo', 'Video');
      List<Photo> photos = await Photo().whereHas('comments', (
        QueryBuilder<dynamic> q,
      ) {
        q.where('body', 'd');
      }).get();
      expect(photos.map((Photo p) => p.id), <int>[2]);
      List<Video> videos = await Video().withCount('comments').get();
      expect(videos.first.countOf('comments'), 1);
    });

    test('morphTo with an empty type and an unknown type', () async {
      await Comment().insertMultiple(<Map<String, dynamic>>[
        <String, dynamic>{
          'body': 'x',
          'commentable_id': 1,
          'commentable_type': 'nope',
        },
      ]);
      await expectLater(
        () => Comment().preload('commentable').get(),
        throwsA(isA<StateError>()),
      );
      expect(
        () => Comment().whereHas('commentable').get(),
        throwsA(isA<UnsupportedError>()),
      );

      /// an empty type is no type
      await Comment().where('body', 'x').update(<String, dynamic>{
        'commentable_type': '',
      });
      List<Comment> blank = await Comment().preload('commentable').get();
      expect(blank.first.commentable, isNull);

      Comment empty = Comment();
      await empty.$getRelation<dynamic>('commentable');
      expect(empty.commentable, isNull);
    });
  });
}
