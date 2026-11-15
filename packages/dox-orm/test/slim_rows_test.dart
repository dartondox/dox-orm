import 'package:dox_orm/dox_orm.dart';
import 'package:test/test.dart';

import 'connection.dart';
import 'models/artist/artist.model.dart';
import 'models/blog/blog.model.dart';
import 'models/blog_info/blog_info.model.dart';

void main() async {
  await initQueryBuilder();

  group('Slim rows |', () {
    setUp(() async {
      for (String t in <String>['artist', 'blog', 'blog_info']) {
        await Schema().dropIfExists(t);
      }
      await Schema().create('artist', (Table table) {
        table.id();
        table.string('name');
        table.timestamps();
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
      await Schema().dropIfExists('artist');
      await Schema().dropIfExists('blog');
      await Schema().dropIfExists('blog_info');
    });

    test('a loaded row has no query state', () async {
      await Artist().create(<String, dynamic>{'name': 'a'});
      await Artist().create(<String, dynamic>{'name': 'b'});

      List<Artist> rows = await Artist().orderBy('id').get();
      Artist? found = await Artist().find(rows.first.id);
      for (Artist row in <Artist>[...rows, found!]) {
        expect(row.$stateOrNull, isNull);
        expect(row.toJson()['name'], isNotNull);
        expect(row.exists, isTrue);
        expect(row.wasRecentlyCreated, isFalse);
        expect(row.getChanges(), isEmpty);
        expect(row.tableName, 'artist');
        expect(row.shouldDebug, SqlQueryBuilder().debug);
        expect(row.$stateOrNull, isNull);
      }
    });

    test('rows with eager relations have no query state', () async {
      Blog blog = await Blog().create(<String, dynamic>{
        'title': 't',
        'body': 'b',
      });
      await BlogInfo().create(<String, dynamic>{
        'info': <String, dynamic>{'a': 1},
        'blog_id': blog.uid,
      });

      List<Blog> rows = await Blog().get();
      expect(rows.single.blogInfos, hasLength(1));
      expect(rows.single.$stateOrNull, isNull);
      expect(rows.single.blogInfos.single.$stateOrNull, isNull);
    });

    test('query methods on a loaded row still work', () async {
      await Artist().create(<String, dynamic>{'name': 'a'});
      await Artist().create(<String, dynamic>{'name': 'b'});
      Artist row = (await Artist().where('name', 'a').getFirst())!;

      /// a query from a row makes its own state
      Artist? other = await row.where('name', 'b').getFirst();
      expect(other!.name, 'b');
      expect(row.$stateOrNull, isNotNull);

      Artist fresh = (await Artist().where('name', 'a').getFirst())!;
      fresh.name = 'c';
      await fresh.save();
      expect(fresh.getChanges().keys, contains('name'));
      expect((await Artist().find(fresh.id))!.name, 'c');

      await fresh.reload();
      expect(fresh.name, 'c');

      expect(await fresh.delete(), 1);
      expect(await Artist().count(), 1);
    });

    test('a relation and preload() from a loaded row work', () async {
      Blog blog = await Blog().create(<String, dynamic>{
        'title': 't',
        'body': 'b',
      });
      await BlogInfo().create(<String, dynamic>{
        'info': <String, dynamic>{'a': 1},
        'blog_id': blog.uid,
      });

      Blog row = (await Blog().find(blog.uid))!;
      row.blogInfos = <BlogInfo>[];
      await row.$getRelation<dynamic>('blogInfos');
      expect(row.blogInfos, hasLength(1));

      Blog withPreload = row.preload('blogInfos') as Blog;
      expect(withPreload.getPreload(), contains('blogInfos'));
    });

    test('a query keeps its state across calls', () {
      QueryBuilder<Map<String, dynamic>> q = QueryBuilder.table('artist');
      q.where('name', 'a');
      q.orderBy('id', 'desc');
      q.limit(2);
      String sql = q.toSql();
      expect(sql, contains('WHERE'));
      expect(sql, contains('ORDER BY'));
      expect(sql, contains('LIMIT'));
      expect(q.tableName, 'artist');
    });

    test('an old style model with field overrides works', () async {
      _OldArtist made = _OldArtist()..name = 'old';
      await made.save();
      expect(made.tempIdValue, isNotNull);

      _OldArtist row = (await _OldArtist().where('name', 'old').getFirst())!;
      expect(row.name, 'old');
      expect(row.tableName, 'artist');
      expect(row.primaryKey, 'id');
      row.name = 'new';
      await row.save();
      expect((await _OldArtist().find(row.tempIdValue))!.name, 'new');
    });
  });
}

/// a hand-written model in the style of an old dox_builder: it sets
/// tableName and primaryKey as fields, not getters
class _OldArtist extends Model<_OldArtist> {
  String? name;

  @override
  String tableName = 'artist';

  @override
  String primaryKey = 'id';

  @override
  List<String> get guarded => const <String>[];

  @override
  List<String> get tableColumns => const <String>[
    'id',
    'name',
    'created_at',
    'updated_at',
  ];

  @override
  _OldArtist fromMap(Map<String, dynamic> m) => _OldArtist()
    ..tempIdValue = m['id']
    ..name = m['name'] as String?;

  @override
  Map<String, dynamic> columnsToMap() => <String, dynamic>{
    'id': tempIdValue,
    'name': name,
  };

  @override
  Map<String, dynamic> convertToMap(dynamic i) =>
      (i as _OldArtist).columnsToMap();
}
