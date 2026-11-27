import 'dart:convert';
import 'dart:math';

import 'package:dox_core/dox_core.dart' show JSON;
import 'package:dox_orm/dox_orm.dart';
import 'package:test/test.dart';

import 'connection.dart';
import 'models/artist/artist.model.dart';
import 'models/artist_song/artist_song.model.dart';
import 'models/author/author.model.dart';
import 'models/blog/blog.model.dart';
import 'models/blog_info/blog_info.model.dart';
import 'models/book/book.model.dart';
import 'models/cast_item/cast_item.model.dart';
import 'models/song/song.model.dart';

/// a book with its own toJson()
class _LoudBook extends Book {
  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'title': title?.toUpperCase(),
  };
}

/// a book that shows only its title
class _TitleBook extends Book {
  @override
  List<String> get visibleFields => const <String>['title'];
}

/// The JSON encoder of dox_core calls `writeJson()` of a model when the
/// generator made one. It must give the same JSON as `toJson()`.
///
/// `toJson()` gives a map of plain values, so `jsonEncode` of it is the
/// JSON of the model with no `writeJson()`.
void sameJson(Object? value) {
  Object? plain = value is List
      ? value.map((dynamic e) => e.toJson()).toList()
      : (value as dynamic).toJson();
  expect(utf8.decode(JSON.bytes(value)), jsonEncode(plain));
}

void main() async {
  await initQueryBuilder();

  const List<String> tables = <String>[
    'artist',
    'song',
    'artist_song',
    'author',
    'book',
    'tag',
    'author_tag',
    'cast_item',
    'blog',
    'blog_info',
  ];

  group('writeJson |', () {
    setUp(() async {
      for (String table in tables) {
        await Schema().dropIfExists(table);
      }
      await Schema().create('artist', (Table table) {
        table.id();
        table.string('name');
        table.timestamps();
      });
      await Schema().create('song', (Table table) {
        table.id();
        table.string('title');
        table.timestamps();
      });
      await Schema().create('artist_song', (Table table) {
        table.id();
        table.integer('song_id');
        table.integer('artist_id');
        table.string('role').nullable();
        table.timestamps();
      });
      await Schema().create('author', (Table table) {
        table.id();
        table.string('code');
        table.timestamps();
      });
      await Schema().create('book', (Table table) {
        table.id();
        table.string('title').nullable();
        table.string('author_code').nullable();
        table.timestamps();
      });
      await Schema().create('tag', (Table table) {
        table.id();
        table.string('title');
        table.timestamps();
      });
      await Schema().create('author_tag', (Table table) {
        table.id();
        table.string('author_code');
        table.integer('tag_id');
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
      for (String table in tables) {
        await Schema().dropIfExists(table);
      }
    });

    Future<void> seedAuthors() async {
      await Author().insertMultiple(<Map<String, dynamic>>[
        <String, dynamic>{'code': 'A'},
        <String, dynamic>{'code': 'B'},
        <String, dynamic>{'code': 'C'},
      ]);
      await Book().insertMultiple(<Map<String, dynamic>>[
        <String, dynamic>{'title': 'a1', 'author_code': 'A'},
        <String, dynamic>{'title': 'a2 "quoted" \\ \n', 'author_code': 'A'},
        <String, dynamic>{'title': 'မြန်မာ 日本語 😀', 'author_code': 'B'},
      ]);
      await QueryBuilder.table('tag').insertMultiple(<Map<String, dynamic>>[
        <String, dynamic>{'title': 't1'},
        <String, dynamic>{'title': 't2'},
      ]);
      await QueryBuilder.table('author_tag')
          .insertMultiple(<Map<String, dynamic>>[
            <String, dynamic>{'author_code': 'A', 'tag_id': 1},
            <String, dynamic>{'author_code': 'A', 'tag_id': 2},
            <String, dynamic>{'author_code': 'B', 'tag_id': 2},
          ]);
    }

    test('a new model: every column is null', () {
      sameJson(Book());
      sameJson(Author());
      sameJson(CastItem());
      sameJson(BlogInfo());
      expect(utf8.decode(JSON.bytes(Book()..title = 'x')), contains('"x"'));
    });

    test('rows from the database', () async {
      await seedAuthors();
      List<Book> books = await Book().get();
      expect(books.length, 3);
      sameJson(books);
      sameJson(books.first);
      sameJson(await Author().get());
    });

    test('a model in a map and in a list', () async {
      await seedAuthors();
      List<Book> books = await Book().get();
      Map<String, dynamic> body = <String, dynamic>{
        'data': books,
        'first': books.first,
        'count': books.length,
      };
      Map<String, dynamic> plain = <String, dynamic>{
        'data': books.map((Book b) => b.toJson()).toList(),
        'first': books.first.toJson(),
        'count': books.length,
      };
      expect(utf8.decode(JSON.bytes(body)), jsonEncode(plain));
    });

    test('preloaded relations: a list, one row and no row', () async {
      await seedAuthors();
      List<Author> authors = await Author()
          .preload('books')
          .preload('firstBook')
          .get();
      expect(authors[0].books.length, 2);
      expect(authors[2].firstBook, null);
      sameJson(authors);
      expect(
        utf8.decode(JSON.bytes(authors[0])),
        contains('"books":[{"id":1,"title":"a1"'),
      );

      /// a relation that was not preloaded has no key
      List<Author> plain = await Author().get();
      sameJson(plain);
      expect(utf8.decode(JSON.bytes(plain[0])), isNot(contains('books')));
    });

    test('many to many: the related rows have a pivot key', () async {
      await Artist().insertMultiple(<Map<String, String>>[
        <String, String>{'name': 'one'},
        <String, String>{'name': 'two'},
      ]);
      await Song().insertMultiple(<Map<String, String>>[
        <String, String>{'title': 's1'},
        <String, String>{'title': 's2'},
      ]);
      await ArtistSong().insertMultiple(<Map<String, String>>[
        <String, String>{'song_id': '1', 'artist_id': '1', 'role': 'lead'},
        <String, String>{'song_id': '2', 'artist_id': '1'},
        <String, String>{'song_id': '2', 'artist_id': '2'},
      ]);
      List<Artist> artists = await Artist().preload('songs').get();
      sameJson(artists);
      expect(utf8.decode(JSON.bytes(artists)), contains('"pivot":{'));

      /// a hidden pivot key
      artists.first.songs.first.hidden = <String>['pivot'];
      sameJson(artists);
    });

    test('many to many with no pivot columns', () async {
      await seedAuthors();
      sameJson(await Author().preload('tags').get());
    });

    test('withCount', () async {
      await seedAuthors();
      List<Author> authors = await Author().withCount('books').get();
      sameJson(authors);
      expect(utf8.decode(JSON.bytes(authors[0])), contains('"books_count":2'));
    });

    test('hidden', () async {
      await seedAuthors();
      List<Book> books = await Book().get();
      books[0].hidden = <String>['title'];
      books[1].hidden = <String>['id', 'created_at', 'updated_at', 'none'];
      sameJson(books);
      expect(utf8.decode(JSON.bytes(books[0])), isNot(contains('title')));

      /// every key is hidden
      books[2].hidden = <String>[
        'id',
        'title',
        'author_code',
        'created_at',
        'updated_at',
      ];
      expect(utf8.decode(JSON.bytes(books[2])), '{}');

      /// a hidden relation
      Author author = (await Author().preload('books').find(1))!;
      author.hidden = <String>['books', 'code'];
      sameJson(author);
      expect(utf8.decode(JSON.bytes(author)), isNot(contains('books')));
    });

    test('makeHidden and makeVisible', () async {
      await seedAuthors();
      List<Book> books = await Book().get();
      books[0].makeHidden(<String>['title']);
      books[1].hidden = <String>['title', 'id'];
      books[1].makeVisible(<String>['title']);
      sameJson(books);
      expect(utf8.decode(JSON.bytes(books[0])), isNot(contains('title')));
      expect(utf8.decode(JSON.bytes(books[1])), contains('title'));
    });

    test('a class that extends a model keeps its own JSON', () {
      _LoudBook loud = _LoudBook()..title = 'quiet';
      expect(utf8.decode(JSON.bytes(loud)), '{"title":"QUIET"}');
      sameJson(<Book>[loud, Book()..title = 'quiet']);

      _TitleBook only = _TitleBook()
        ..id = 3
        ..title = 't';
      expect(utf8.decode(JSON.bytes(only)), '{"title":"t"}');
    });

    test('casts', () async {
      CastItem item = CastItem()
        ..meta = <String, dynamic>{
          'a': 1,
          'b': <int>[1, 2],
          'c': null,
        }
        ..tags = <String>['x', 'y']
        ..active = true
        ..done = true
        ..status = Status.live
        ..level = Level.high
        ..price = const Money(250);
      sameJson(item);
      await item.save();
      List<CastItem> rows = await CastItem().get();
      sameJson(rows);
      await (CastItem()).save();
      sameJson(await CastItem().get());
    });

    test('computed values and a model with no writeJson()', () async {
      Blog blog = Blog()
        ..title = 'hello'
        ..description = 'body';
      await blog.save();
      await (BlogInfo()
            ..info = <String, dynamic>{'name': 'x'}
            ..blogId = blog.uid)
          .save();
      List<BlogInfo> infos = await BlogInfo().get();
      sameJson(infos);
      expect(utf8.decode(JSON.bytes(infos)), contains('"has_info":true'));
      sameJson(await BlogInfo().preload('blog').get());
      sameJson(await Blog().get());
    });

    test('random rows', () {
      Random random = Random(7);
      const List<String> texts = <String>[
        '',
        'plain text',
        'a "quote" and a \\ backslash',
        'line\nbreak\ttab\u0000',
        'မြန်မာစာ',
        '日本語 한국어 العربية',
        '😀 emoji 👍🏽',
        'é ü ß ñ',
        'a text that is longer than thirty two characters in total',
      ];
      const List<String> keys = <String>[
        'id',
        'title',
        'author_code',
        'created_at',
        'updated_at',
      ];
      List<Book> books = <Book>[];
      for (int i = 0; i < 2000; i++) {
        Book book = Book();
        if (random.nextBool()) book.id = random.nextInt(1 << 31) - (1 << 30);
        if (random.nextBool()) book.title = texts[random.nextInt(texts.length)];
        if (random.nextBool()) {
          book.authorCode = texts[random.nextInt(texts.length)];
        }
        if (random.nextBool()) {
          book.createdAt = DateTime.utc(2000 + random.nextInt(30), 5, 17, 3);
        }
        if (random.nextInt(4) == 0) {
          book.hidden = <String>[
            for (String key in keys)
              if (random.nextBool()) key,
          ];
        }
        if (random.nextInt(8) == 0) {
          book.makeHidden(<String>[keys[random.nextInt(keys.length)]]);
        }
        books.add(book);
      }
      sameJson(books);
    });
  });
}
