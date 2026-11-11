import 'package:dox_orm/dox_orm.dart';
import 'package:dox_orm/src/utils/plural.dart';
import 'package:test/test.dart';

import 'connection.dart';
import 'models/book/book.model.dart';
import 'models/event_post/event_post.model.dart';
import 'models/owner/owner.model.dart';

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
      Map<String, String> words = <String, String>{
        'user': 'users',
        'blog_post': 'blog_posts',
        'category': 'categories',
        'day': 'days',
        'status': 'statuses',
        'box': 'boxes',
        'match': 'matches',
        'person': 'people',
        'news': 'news',
        'blog_child': 'blog_children',
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
      EventPost.log = <String>[];
      EventPost.cancelOn = null;
      EventPost.failOn = null;
    });

    tearDown(() async {
      for (String t in <String>['book', 'event_posts', 'owners', 'pets']) {
        await Schema().dropIfExists(t);
      }
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
