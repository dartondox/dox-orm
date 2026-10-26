# dox_orm

Models, relations and a query builder for Postgres, MySQL, MariaDB and SQLite.

[![pub package](https://img.shields.io/pub/v/dox_orm.svg)](https://pub.dev/packages/dox_orm)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/dartondox/dox-orm/blob/main/LICENSE)

Part of [Dox](https://dartondox.dev), a web backend framework for Dart.
Source code: [github.com/dartondox/dox-orm](https://github.com/dartondox/dox-orm).

## Install

```bash
dart pub add dox_orm
```

Dox 3.x is in alpha (`3.0.0-alpha.x`). The API can still change before the stable release.

## Use it

Set up the connection once:

```dart
import 'package:dox_orm/dox_orm.dart';

DatabaseConfig databaseConfig = DatabaseConfig(
  connection: 'sqlite',
  connections: <String, ConnectionConfig>{
    'sqlite': ConnectionConfig(
      driver: Driver.sqlite,
      database: 'storage/app.db', // file path, or ':memory:'
    ),
  },
);

SqlQueryBuilder.initializeWithDatabaseConfig(databaseConfig);
```

Write a model. `dox_builder` makes the `BlogGenerator` class
(`dart pub add dev:dox_builder dev:build_runner`, then `dart run build_runner build`):

```dart
part 'blog.model.g.dart';

@DoxModel(table: 'blogs')
class Blog extends BlogGenerator {
  @Column()
  String? title;

  @Column()
  String? status;
}
```

Use it:

```dart
Blog blog = Blog();
blog.title = 'Hello';
blog.status = 'active';
await blog.save();

List<Blog> active = await Blog().where('status', 'active').orderBy('id', 'desc').get();
Blog? one = await Blog().find(1);

// no model: a list of maps
List<Map<String, dynamic>> rows = await QueryBuilder.table('blogs').where('id', '>', 10).get();

// filter by a relation, without loading it (User has a `@HasMany(Post) posts` field)
List<User> writers = await User().whereHas('posts', (QueryBuilder<dynamic> q) {
  q.where('published', true);
}).get();

// conditions in brackets
List<Blog> blogs = await Blog()
    .where('status', 'active')
    .whereGroup((QueryBuilder<Blog> q) {
      q.where('views', '>', 100).orWhere('pinned', true);
    })
    .get();

// write methods return the number of changed rows
int changed = await Blog().where('status', 'draft').update(<String, dynamic>{'status': 'active'});
int deleted = await Blog().where('status', 'spam').delete();

// lock a row in a transaction
await QueryBuilder.transaction(() async {
  Blog blog = await Blog().lockForUpdate().findOrFail(1);
  blog.status = 'archived';
  await blog.save();
});
```

In a Dox app, start the ORM in a `DoxProvider`, so each isolate gets its own pool.

## Features

- One API for Postgres, MySQL 8+, MariaDB and SQLite.
- Postgres and MySQL use the native Rust drivers (`dox_postgres_native`, `dox_mysql_native`). When the native library does not load, the app stops with an error that says why and how to fix it.
- Models with `@Column`, timestamps, soft deletes, events and `hidden` fields.
- Relations: `@HasOne`, `@HasMany`, `@BelongsTo`, `@ManyToMany`, with eager loading.
- Filter by relations: `whereHas`, `orWhereHas`, `whereDoesntHave`, `orWhereDoesntHave` and `has('posts', '>=', 3)`. Nested names like `posts.comments` work.
- Query builder: `where` (a `null` value is `IS NULL` or `IS NOT NULL`), `whereIn`, `whereBetween`, `whereColumn`, `whereLike`, `whereExists`, `whereGroup`, `whereNot`, `when`, `join`, `groupBy`, `having`, `distinct`, `latest`, `paginate`, raw SQL with bound values.
- Read helpers: `firstOrFail` and `findOrFail` (throw `ModelNotFoundException`), `hasRows`, `pluck`, `pluckMap`, `valueOf`, `chunk` and `chunkById`.
- Aggregates: `count`, `sum`, `avg`, `min`, `max`, and `withCount`, `withSum`, `withMax` for relations.
- Writes: `create` and `insert` return the new model or map. `update`, `delete`, `increment`, `decrement` and `upsert` return the number of changed rows. `firstOrCreate`, `firstOrNew` and `updateOrCreate`.
- Transactions with `QueryBuilder.transaction()`, nested with savepoints, and row locks with `lockForUpdate()` and `sharedLock()`.
- Schema builder for migrations (used by `dox_migration`).
- DTO rules `@Unique` and `@Exists` that check the database.

## Documentation

- [Database setup](https://dartondox.dev/latest/database/)
- [Query builder](https://dartondox.dev/latest/database/query-builder/), [Models](https://dartondox.dev/latest/database/model/), [Query by relations](https://dartondox.dev/latest/database/model/relation-queries/), [Transactions](https://dartondox.dev/latest/database/transactions/)
- [API reference](https://pub.dev/documentation/dox_orm/latest/)

## License

MIT. See [LICENSE](https://github.com/dartondox/dox-orm/blob/main/LICENSE).
