import 'package:dox_orm/dox_orm.dart';
import 'package:dox_orm/src/relationships/keys.dart';
import 'package:dox_orm/src/utils/plural.dart';
import 'package:test/test.dart';

import 'connection.dart';
import 'models/blog/blog.model.dart';
import 'models/blog_info/blog_info.model.dart';
import 'models/book/book.model.dart';
import 'models/event_post/event_post.model.dart';
import 'models/note/note.model.dart';
import 'models/owner/owner.model.dart';

/// a Book that can not set `author_code` by mass assignment
class GuardedBook extends Book {
  @override
  String get tableName => 'books';

  @override
  List<String> get guarded => const <String>['author_code'];
}

/// a saving hook that changes the title
class TitleObserver extends ModelObserver<EventPost> {
  @override
  void onSaving(EventPost model) => model.title = 'from hook';
}

/// turns on the events of Note
class NoteObserver extends ModelObserver<Note> {}

/// writes each event of BlogInfo
class InfoObserver extends ModelObserver<BlogInfo> {
  List<String> log = <String>[];

  @override
  void onUpdating(BlogInfo model) => log.add('updating');
}

/// the sql of a belongsTo relation made as a subquery, so the foreign
/// key is in the sql
String belongsToSql<T, M>(
  Model<T> child,
  Model<M> Function() owner, {
  String? relation,
}) {
  relationSubquery = true;
  subqueryKeyPrefix = 'p_';
  try {
    Model<M> q = belongsTo<T, M>(
      <Model<T>>[child],
      owner,
      relation: relation,
    ) as Model<M>;
    return q.toSql();
  } finally {
    relationSubquery = false;
    subqueryKeyPrefix = '';
  }
}

/// each test runs with the flags off (the default) and with [OrmFlags.all]
void main() async {
  await initQueryBuilder();

  tearDown(() {
    SqlQueryBuilder().flags = const OrmFlags();
  });

  void flagsOn() => SqlQueryBuilder().flags = const OrmFlags.all();

  group('OrmFlags |', () {
    test('all off by default, all on with OrmFlags.all()', () {
      const OrmFlags off = OrmFlags();
      const OrmFlags on = OrmFlags.all();
      List<bool> values(OrmFlags f) => <bool>[
        f.skipCleanUpdateEvents,
        f.belongsToKeyFromRelation,
        f.pluralTableNames,
        f.createWritesNull,
        f.sumReturnsZero,
        f.selectRawAdds,
        f.groupByAdds,
        f.lastPageAtLeastOne,
        f.laravelPostgresTypes,
        f.updateSetsUpdatedAt,
        f.incrementFiresEvents,
        f.preloadUnknownThrows,
        f.toJsonLoadedRelations,
      ];
      expect(values(off), everyElement(isFalse));
      expect(values(on), everyElement(isTrue));
      expect(SqlQueryBuilder().flags.pluralTableNames, isFalse);
    });

    test('DatabaseConfig flags reach the query builder', () {
      DatabaseConfig old = SqlQueryBuilder().databaseConfig!;
      DBDriver driver = SqlQueryBuilder().dbDriver;
      DatabaseConfig config = DatabaseConfig(
        connection: old.connection,
        connections: old.connections,
        flags: const OrmFlags(sumReturnsZero: true),
      );
      expect(old.flags.sumReturnsZero, isFalse);
      SqlQueryBuilder.initializeWithDatabaseConfig(config);
      addTearDown(() async {
        await SqlQueryBuilder().dbDriver.close();
        SqlQueryBuilder().databaseConfig = old;
        SqlQueryBuilder().dbDriver = driver;
      });
      expect(SqlQueryBuilder().flags.sumReturnsZero, isTrue);
      expect(SqlQueryBuilder().flags.groupByAdds, isFalse);
    });
  });

  group('pluralTableNames |', () {
    test('off: the class name in snake case', () {
      expect(Book().tableName, 'book');
    });

    test('on: plural', () {
      flagsOn();
      expect(Book().tableName, 'books');

      /// a table name set on the model does not change
      expect(Owner().tableName, 'owners');

      /// the default foreign key stays singular
      expect(Book().foreignKeyName, 'book_id');
    });

    test('plural rules', () {
      /// the Doctrine Inflector value of each word
      Map<String, String> words = <String, String>{
        'user': 'users',
        'blog_post': 'blog_posts',
        'user_profile': 'user_profiles',
        'category': 'categories',
        'day': 'days',
        'box': 'boxes',
        'match': 'matches',
        'person': 'people',
        'child': 'children',
        'blog_child': 'blog_children',
        'data': 'data',
        'sheep': 'sheep',
        'media': 'media',
        'quiz': 'quizzes',
        'hero': 'heroes',
        'potato': 'potatoes',
        'tomato': 'tomatoes',
        'echo': 'echoes',
        'photo': 'photos',
        'piano': 'pianos',
        'video': 'videos',
        'wolf': 'wolves',
        'shelf': 'shelves',
        'calf': 'calves',
        'loaf': 'loaves',
        'thief': 'thieves',
        'leaf': 'leaves',
        'knife': 'knives',
        'life': 'lives',
        'index': 'indices',
        'matrix': 'matrices',
        'axis': 'axes',
        'status': 'statuses',
        'bus': 'buses',
        'address': 'addresses',
        'virus': 'viri',
        'alias': 'aliases',
        'cactus': 'cacti',
        'news': 'news',
        'series': 'series',
        'analysis': 'analyses',
        'lens': 'lenses',
        'crisis': 'crises',
        'basis': 'bases',
        'diagnosis': 'diagnoses',
        'iris': 'irises',
        'focus': 'foci',
        'radius': 'radii',
        'self': 'selves',
        'elf': 'elves',
        'scarf': 'scarves',
        'medium': 'media',
        'datum': 'data',
        'stadium': 'stadia',
        'curriculum': 'curricula',
        'buffalo': 'buffalo',
        'volcano': 'volcanoes',
        'tornado': 'tornadoes',
        'veto': 'vetos',
        'gas': 'gases',
        'canvas': 'canvases',
        'bonus': 'bonuses',
        'campus': 'campuses',
        'man': 'men',
        'woman': 'women',
        'mouse': 'mice',
        'goose': 'geese',
        'foot': 'feet',
        'tooth': 'teeth',
        'roof': 'roofs',
        'chief': 'chiefs',
        'city': 'cities',
        'key': 'keys',
        'class': 'classes',
        'process': 'processes',
        'business': 'businesses',
        'fish': 'fish',
        'species': 'species',
        'user_data': 'user_data',
        // plural already: Doctrine keeps a word that ends in s, and
        // adds s to `children` and `men`
        'users': 'users',
        'settings': 'settings',
        'goods': 'goods',
        'people': 'people',
        'categories': 'categories',
        'statuses': 'statuses',
        'addresses': 'addresses',
        'boxes': 'boxes',
        'children': 'childrens',
        'men': 'mens',
      };
      for (MapEntry<String, String> e in words.entries) {
        expect(pluralName(e.key), e.value, reason: e.key);
      }
    });
  });

  group('selectRaw and groupBy |', () {
    String sql(QueryBuilder<dynamic> q) => q.toSql().toLowerCase();

    test('off: selectRaw replaces, a second groupBy replaces', () {
      String q = sql(
        QueryBuilder.table('t')
            .select('a')
            .selectRaw('count(*) as c')
            .groupBy('a')
            .groupBy('b'),
      );
      expect(q, contains('select count(*) as c from'));
      expect(q, matches(RegExp(r'group by .b.$')));
    });

    test('on: selectRaw adds, a second groupBy adds', () {
      flagsOn();
      String q = sql(
        QueryBuilder.table('t')
            .select('a')
            .selectRaw('count(*) as c')
            .groupBy('a')
            .groupByRaw('b'),
      );
      expect(q, matches(RegExp(r'select .a.,count\(\*\) as c from')));
      expect(q, matches(RegExp(r'group by .a.,b')));
    });

    test('on: select() after selectRaw() replaces both', () {
      flagsOn();
      String q = sql(
        QueryBuilder.table('t').selectRaw('count(*) as c').select('a'),
      );
      expect(q, matches(RegExp(r'select .a. from')));
    });

    test('on: selectRaw() twice adds both', () {
      flagsOn();
      String q = sql(
        QueryBuilder.table('t')
            .selectRaw('count(*) as c')
            .selectRaw('max(a) m'),
      );
      expect(q, contains('select count(*) as c,max(a) m from'));
    });

    test('only groupByAdds on', () {
      SqlQueryBuilder().flags = const OrmFlags(groupByAdds: true);
      String q = sql(
        QueryBuilder.table('t')
            .select('a')
            .selectRaw('count(*) as c')
            .groupBy('a')
            .groupBy('b'),
      );
      expect(q, matches(RegExp(r'group by .a.,.b.')));

      /// selectRawAdds is off: selectRaw replaces
      expect(q, contains('select count(*) as c from'));
    });

    test('on: selectRaw with no select() is the only column', () {
      flagsOn();
      String q = sql(QueryBuilder.table('t').selectRaw('count(*) as c'));
      expect(q, contains('select count(*) as c from'));
    });
  });

  group('with a table |', () {
    setUp(() async {
      await Schema().create('book', (Table table) {
        table.id();
        table.string('title').nullable().withDefault('untitled');
        table.string('author_code').nullable();
        table.timestamps();
      });
      await Schema().create('event_posts', (Table table) {
        table.id();
        table.string('title').nullable().withDefault('untitled');
        table.integer('views').withDefault(0);
        table.softDeletes();
        table.timestamps();
      });
      await Schema().create('owners', (Table table) {
        table.id();
        table.string('name');
      });
      await Schema().create('pets', (Table table) {
        table.id();
        table.string('name');
        table.integer('owner_id').nullable();
      });
      await Schema().create('blog_info', (Table table) {
        table.id();
        table.json('info');
        table.integer('blog_id');
        table.timestamps();
      });
      EventPost.log = <String>[];
      EventPost.cancelOn = null;
      EventPost.failOn = null;
    });

    tearDown(() async {
      for (String t in <String>[
        'book',
        'books',
        'event_posts',
        'owners',
        'pets',
        'blog_info',
      ]) {
        await Schema().dropIfExists(t);
      }
      Model.forgetObservers();
    });

    test('sum() off: null when no row matches', () async {
      expect(await QueryBuilder.table('book').sum('id'), isNull);
    });

    test('sum() on: 0 when no row matches', () async {
      flagsOn();
      expect(await QueryBuilder.table('book').sum('id'), 0);
      await QueryBuilder.table('book').insert(<String, dynamic>{'id': 4});
      expect(await QueryBuilder.table('book').sum('id'), 4);
    });

    test('sum() on: avg, min and max still give null', () async {
      flagsOn();
      expect(await QueryBuilder.table('book').avg('id'), isNull);
      expect(await QueryBuilder.table('book').min('id'), isNull);
      expect(await QueryBuilder.table('book').max('id'), isNull);
    });

    test('one flag on: the others stay off', () async {
      SqlQueryBuilder().flags = const OrmFlags(pluralTableNames: true);
      expect(Book().tableName, 'books');
      expect(await QueryBuilder.table('book').sum('id'), isNull);
      await Schema().create('books', (Table table) {
        table.id();
        table.string('title').nullable().withDefault('untitled');
        table.string('author_code').nullable();
        table.timestamps();
      });

      /// createWritesNull is off: the default is used
      Book book = await Book().create(<String, dynamic>{'title': null});
      expect(book.title, 'untitled');
    });

    test('only createWritesNull on', () async {
      SqlQueryBuilder().flags = const OrmFlags(createWritesNull: true);
      Book book = await Book().create(<String, dynamic>{'title': null});
      expect(book.title, isNull);
      expect(Book().tableName, 'book');
      expect(await QueryBuilder.table('event_posts').sum('id'), isNull);
    });

    test('paginate() off: lastPage 0 with no rows', () async {
      Pagination<dynamic> p = await QueryBuilder.table('book')
          .paginate(currentPage: 1, perPage: 10);
      expect(p.lastPage, 0);
    });

    test('paginate() on: lastPage 1 with no rows', () async {
      flagsOn();
      Pagination<dynamic> p = await QueryBuilder.table('book')
          .paginate(currentPage: 1, perPage: 10);
      expect(p.lastPage, 1);
      expect(p.total, 0);
      await QueryBuilder.table('book').insert(<String, dynamic>{'id': 1});
      p = await QueryBuilder.table('book')
          .paginate(currentPage: 1, perPage: 10);
      expect(p.lastPage, 1);
    });

    test('create() off: a null key uses the column default', () async {
      Book book = await Book().create(<String, dynamic>{
        'title': null,
        'author_code': 'a',
      });
      expect(book.title, 'untitled');
      EventPost post = await EventPost().create(<String, dynamic>{
        'title': null,
      });
      expect(post.title, 'untitled');
    });

    test('create() on: a null key is written as NULL', () async {
      flagsOn();

      /// the table name of Book is plural with the flags on
      await Schema().create('books', (Table table) {
        table.id();
        table.string('title').nullable().withDefault('untitled');
        table.string('author_code').nullable();
        table.timestamps();
      });
      addTearDown(() => Schema().dropIfExists('books'));

      Book book = await Book().create(<String, dynamic>{
        'title': null,
        'author_code': 'a',
      });
      expect(book.title, isNull);
      expect(book.id, isNotNull);

      /// a key that is not in the data still uses the default
      Book other = await Book().create(<String, dynamic>{'author_code': 'b'});
      expect(other.title, 'untitled');

      /// a model with events goes through save()
      EventPost post = await EventPost().create(<String, dynamic>{
        'title': null,
      });
      expect(post.title, isNull);
      expect(EventPost.log, contains('created'));
    });

    test('create() on: guarded null key, and a null created_at', () async {
      flagsOn();
      await Schema().create('books', (Table table) {
        table.id();
        table.string('title').nullable().withDefault('untitled');
        table.string('author_code').nullable().withDefault('x');
        table.timestamps();
      });

      /// author_code is guarded: it is dropped, so its default is used
      Book book = await GuardedBook().create(<String, dynamic>{
        'title': null,
        'author_code': null,
      });
      expect(book.title, isNull);
      expect(book.authorCode, 'x');

      /// a null created_at is set to now, not written as NULL
      Book other = await Book().create(<String, dynamic>{
        'title': 'a',
        'created_at': null,
      });
      Map<String, dynamic>? row = await QueryBuilder.table('books')
          .find(other.id);
      expect(row?['created_at'], isNotNull);
    });

    test('save() off: no changes still fires updating and updated', () async {
      EventPost post = await EventPost().create(<String, dynamic>{
        'title': 'a',
      });
      EventPost.log = <String>[];
      expect(await post.save(), isTrue);
      expect(EventPost.log, <String>['saving', 'updating', 'updated', 'saved']);
    });

    test('save() on: no changes fires only saving and saved', () async {
      flagsOn();
      EventPost post = await EventPost().create(<String, dynamic>{
        'title': 'a',
      });
      EventPost.log = <String>[];
      expect(await post.save(), isTrue);
      expect(EventPost.log, <String>['saving', 'saved']);

      /// with a change it fires all four
      EventPost.log = <String>[];
      post.title = 'b';
      expect(await post.save(), isTrue);
      expect(EventPost.log, <String>['saving', 'updating', 'updated', 'saved']);
      expect((await EventPost().find(post.id))!.title, 'b');
    });

    test('save() on: a saving hook that changes a field updates', () async {
      flagsOn();
      EventPost post = await EventPost().create(<String, dynamic>{
        'title': 'a',
      });
      Model.observe<EventPost>(TitleObserver());
      EventPost.log = <String>[];
      expect(await post.save(), isTrue);
      expect(EventPost.log, <String>['saving', 'updating', 'updated', 'saved']);
      expect((await EventPost().find(post.id))!.title, 'from hook');
    });

    test('save() on: a clean model with timestamps runs no query', () async {
      flagsOn();
      await EventPost().create(<String, dynamic>{'title': 'a'});
      EventPost post = (await EventPost().find(1))!;
      DateTime? updatedAt = post.updatedAt;
      int queries = 0;
      void count(QueryEvent e) => queries++;
      SqlQueryBuilder().listen(count);
      addTearDown(() => SqlQueryBuilder().removeListener(count));
      expect(await post.save(), isTrue);
      expect(queries, 0);
      expect(post.updatedAt, updatedAt);
    });

    /// a post whose updated_at is old, and the updated_at in the table
    Future<EventPost> oldPost() async {
      await EventPost().create(<String, dynamic>{'title': 'a'});
      await QueryBuilder.table('event_posts')
          .where('id', 1)
          .update(<String, dynamic>{'updated_at': DateTime.utc(2000, 6)});
      EventPost.log = <String>[];
      return (await EventPost().find(1))!;
    }

    Future<DateTime> storedUpdatedAt() async {
      Map<String, dynamic>? row = await QueryBuilder.table('event_posts')
          .where('id', 1)
          .getFirst();
      return DateTime.parse('${row!['updated_at']}');
    }

    test('updateSetsUpdatedAt off: the query form keeps updated_at', () async {
      await oldPost();
      await EventPost().where('id', 1).update(<String, dynamic>{'title': 'b'});
      expect((await storedUpdatedAt()).year, 2000);
    });

    test('updateSetsUpdatedAt on: the query form sets updated_at', () async {
      flagsOn();
      await oldPost();
      await EventPost().where('id', 1).update(<String, dynamic>{'title': 'b'});
      expect((await storedUpdatedAt()).year, greaterThan(2000));

      /// a value in the data is kept
      await EventPost().where('id', 1).update(<String, dynamic>{
        'title': 'c',
        'updated_at': DateTime.utc(2001, 6),
      });
      expect((await storedUpdatedAt()).year, 2001);
    });

    test('incrementFiresEvents off: no events, updated_at kept', () async {
      EventPost post = await oldPost();
      expect(await post.increment('views', 2), 1);
      expect(EventPost.log, isEmpty);
      expect((await storedUpdatedAt()).year, 2000);
    });

    test('incrementFiresEvents on: events and updated_at', () async {
      flagsOn();
      EventPost post = await oldPost();
      expect(await post.increment('views', 2), 1);
      expect(EventPost.log, <String>['saving', 'updating', 'updated', 'saved']);
      expect((await storedUpdatedAt()).year, greaterThan(2000));
      expect(post.updatedAt!.year, greaterThan(2000));

      /// decrement too, and a hook can stop it
      EventPost.log = <String>[];
      EventPost.cancelOn = 'updating';
      expect(await post.decrement('views'), 0);
      Map<String, dynamic>? row = await QueryBuilder.table('event_posts')
          .where('id', 1)
          .getFirst();
      expect(row!['views'], 2);
      EventPost.cancelOn = null;
      expect(await post.decrement('views'), 1);
    });

    test('save(): how many times beforeSave runs', () async {
      await Schema().create('notes', (Table table) {
        table.id();
        table.string('slug').nullable();
        table.string('title').nullable();
        table.boolean('pinned').nullable();
        table.timestamps();
      });
      addTearDown(() => Schema().dropIfExists('notes'));
      Model.observe<Note>(NoteObserver());
      Note note = await Note().create(<String, dynamic>{'title': 'a'});

      /// [clean save, changed save]
      Future<List<int>> calls() async {
        List<int> out = <int>[];
        Note.slugCalls = 0;
        await note.save();
        out.add(Note.slugCalls);
        note.title = '${note.title}x';
        Note.slugCalls = 0;
        await note.save();
        out.add(Note.slugCalls);
        return out;
      }

      expect(await calls(), <int>[1, 1]);
      SqlQueryBuilder().flags = const OrmFlags(skipCleanUpdateEvents: true);

      /// a changed save reads the columns again after `updating`
      expect(await calls(), <int>[1, 2]);
    });

    test('save() on: a Map or List field always counts as changed', () async {
      /// the loaded Map is the same object as the saved value, so a
      /// change in place can not be seen. The ORM sends it every time.
      SqlQueryBuilder().flags = const OrmFlags(skipCleanUpdateEvents: true);
      InfoObserver observer = InfoObserver();
      Model.observe<BlogInfo>(observer);
      await BlogInfo().create(<String, dynamic>{
        'info': <String, dynamic>{'a': 1},
        'blog_id': 1,
      });
      BlogInfo info = (await BlogInfo().find(1))!;
      expect(await info.save(), isTrue);
      expect(observer.log, <String>['updating']);

      /// a change in place is saved
      info.info!['b'] = 2;
      await info.save();
      expect((await BlogInfo().find(1))!.info, <String, dynamic>{
        'a': 1,
        'b': 2,
      });
    });

    test('belongsTo off: the key comes from the class name', () async {
      Owner owner = await Owner().create(<String, dynamic>{'name': 'ann'});
      Pet pet = await Pet().create(<String, dynamic>{
        'name': 'rex',
        'owner_id': owner.id,
      });

      /// `keeper` is not used: the key is owner_id
      Map<String, Owner> found = await getBelongsTo<Pet, Owner>(
        belongsTo<Pet, Owner>(<Pet>[pet], Owner.new, relation: 'keeper'),
        <Pet>[pet],
      );
      expect(found.values.single.name, 'ann');
    });

    test('belongsTo on: the key comes from the relation name', () async {
      flagsOn();
      Owner owner = await Owner().create(<String, dynamic>{'name': 'ann'});
      Pet pet = await Pet().create(<String, dynamic>{
        'name': 'rex',
        'owner_id': owner.id,
      });

      /// `owner` gives owner_id
      Map<String, Owner> found = await getBelongsTo<Pet, Owner>(
        belongsTo<Pet, Owner>(<Pet>[pet], Owner.new, relation: 'owner'),
        <Pet>[pet],
      );
      expect(found.values.single.name, 'ann');

      /// `keeper` gives keeper_id: the pet has no such value
      found = await getBelongsTo<Pet, Owner>(
        belongsTo<Pet, Owner>(<Pet>[pet], Owner.new, relation: 'keeper'),
        <Pet>[pet],
      );
      expect(found, isEmpty);

      /// a foreign key set on the relation wins
      found = await getBelongsTo<Pet, Owner>(
        belongsTo<Pet, Owner>(
          <Pet>[pet],
          Owner.new,
          relation: 'keeper',
          foreignKey: 'owner_id',
        ),
        <Pet>[pet],
      );
      expect(found.values.single.name, 'ann');
    });

    test('belongsTo on: no relation name uses the class name', () async {
      flagsOn();
      expect(belongsToSql<Pet, Owner>(Pet(), Owner.new), contains('owner_id'));
    });

    test('belongsTo on: a two word relation and a custom key', () async {
      flagsOn();
      expect(
        belongsToSql<Pet, Owner>(Pet(), Owner.new, relation: 'authorProfile'),
        contains('author_profile_id'),
      );

      /// Blog has the primary key `uid`
      expect(
        belongsToSql<BlogInfo, Blog>(BlogInfo(), Blog.new, relation: 'post'),
        contains('post_uid'),
      );

      /// off: the relation name is not used
      SqlQueryBuilder().flags = const OrmFlags();
      expect(
        belongsToSql<BlogInfo, Blog>(BlogInfo(), Blog.new, relation: 'post'),
        contains('blog_id'),
      );
    });
  });

  group('laravelPostgresTypes |', () {
    const SchemaGrammar pg = PostgresGrammar();

    String createSql(Table t) {
      t.json('meta');
      t.softDeletes();
      t.timestamps();
      return pg.compile(t).first;
    }

    test('off: TIMESTAMPTZ and JSONB', () {
      String sql = createSql(Table('t', creating: true));
      expect(sql, contains('"meta" JSONB'));
      expect(sql, contains('"created_at" TIMESTAMPTZ'));
      expect(sql, contains('"deleted_at" TIMESTAMPTZ'));
    });

    test('on: TIMESTAMP and JSON in a new table', () {
      flagsOn();
      String sql = createSql(Table('t', creating: true));
      expect(sql, contains('"meta" JSON NOT NULL'));
      expect(sql, contains('"created_at" TIMESTAMP,'));
      expect(sql, contains('"updated_at" TIMESTAMP)'));
      expect(sql, contains('"deleted_at" TIMESTAMP,'));
      expect(sql, isNot(contains('TIMESTAMPTZ')));
    });

    test('on: a table that is already there does not change', () {
      flagsOn();
      Table t = Table('t');
      t.json('meta');
      t.timestamps();
      String sql = pg.compile(t).join(';');
      expect(sql, contains('JSONB'));
      expect(sql, contains('TIMESTAMPTZ'));
    });

    test('flags given to Schema and Table win', () {
      Table t = Table(
        't',
        creating: true,
        flags: const OrmFlags(laravelPostgresTypes: true),
      );
      expect(createSql(t), contains('"meta" JSON NOT NULL'));
    });
  });
}
