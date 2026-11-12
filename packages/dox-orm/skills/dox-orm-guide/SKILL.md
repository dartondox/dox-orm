---
name: dox-orm-guide
description: How to use the Dox ORM (dox_orm) in a Dox app. Use it when you add or change a model, its columns, fillable or hidden fields, queries, relations (HasMany, BelongsTo, HasOne, ManyToMany, HasManyThrough, HasOneThrough), pagination, soft deletes, transactions, model factories, database tests, or when you switch the database from SQLite to Postgres or MySQL.
---

# Dox ORM guide

`dox_orm` has the models, the query builder and the database drivers (SQLite, Postgres, MySQL/MariaDB).
Migrations and seeders are in `dox_migration` (see the `dox-migration-guide` skill).

Full docs: https://dartondox.dev/llms-full.txt. Read them before you guess an API.
Do not invent methods. Copy the style of the models that are already in the app.

The examples use the package name `my_app`. Use the `name:` of the app's `pubspec.yaml`.

## Make a model

Stop `dox s` first. It runs new migrations at start, before you add the columns.

```bash
dox make:model Post        # lib/app/models/post/post.model.dart
dox make:model Post -m     # the model and a create_posts_table migration
dox make:factory Post      # db/factories/post.factory.dart
```

`make:model` sets `table: 'posts'` (plural). The `-m` migration uses the same table.

```dart
// lib/app/models/post/post.model.dart
import 'package:dox_orm/dox_orm.dart';

part 'post.model.g.dart';

@DoxModel(table: 'posts')
class Post extends PostGenerator {
  /// Columns that `create(map)` and `update(map)` may set.
  @override
  List<String> get fillable => <String>['title', 'body', 'user_id'];

  /// Left out of toJson().
  @override
  List<String> get hidden => <String>[];

  @Column()
  String? title;

  @Column()
  String? body;

  @Column()
  int? userId; // column user_id
}
```

Then run the generator. It writes `post.model.g.dart` with `PostGenerator`:

```bash
dart run build_runner build
```

Rules:

- Every column field is nullable (`String?`, `int?`). A new model has no values yet.
- `id`, `createdAt` and `updatedAt` come from the generated class. Do not declare them.
- The column name is the field name in snake_case. `@Column(name: 'body')` sets another name.
- Field types: `String?`, `int?`, `double?`, `bool?`, `DateTime?`,
  `Map<String, dynamic>?` or `List<dynamic>?` (JSON), an enum (saved as its name).
- Never edit `*.model.g.dart`.

### Model options

All options go in `@DoxModel(...)`:

| Option | Default | What it does |
| --- | --- | --- |
| `table` | class name in snake_case | the table name |
| `primaryKey` | `'id'` | the primary key column |
| `primaryKeyType` | `int` | the Dart type of the key, like `String` for a UUID |
| `timestamps` | `true` | `false` when the table has no `created_at` and `updated_at` |
| `softDelete` | `false` | `delete()` sets `deleted_at` and keeps the row |

### fillable and hidden

- A model with no `fillable` throws a `MassAssignmentException` when `create(map)` or `update(map)` gets keys.
- With `fillable`, other keys are dropped. So `Post().create(req.body)` is safe.
- `save()` is not checked. Fields you set in code are always saved.
- Put secret columns (like `password`) in `hidden`.
- Only for trusted data (never `req.body`): `forceCreate(map)`, `forceUpdate(map)`, `forceFill(map)`.

## Save, update, delete

```dart
// insert
Post post = Post()
  ..title = 'Hello'
  ..body = 'My first post.';
await post.save();
print(post.id);

// insert from a map (only fillable keys)
Post created = await Post().create(<String, dynamic>{'title': 'Hi', 'body': 'Text'});

// update a loaded model: only changed fields are sent
Post? found = await Post().find(1);
found?.title = 'New title';
await found?.save();
await found?.update(<String, dynamic>{'title': 'Other'}); // only fillable keys

// update many rows
await Post().where('user_id', 1).update(<String, dynamic>{'title': 'x'});

// delete
await found?.delete();
int deleted = await Post().where('id', 5).delete(); // number of rows. 0 means not found

// find or create
Post one = await Post().firstOrCreate(
  <String, dynamic>{'title': 'Hello'},
  <String, dynamic>{'body': 'Text'},
);
```

## Query

Start each query with a new object: `Post()`. A query object keeps its `where` parts.

```dart
List<Post> all = await Post().all();
List<Post> posts = await Post()
    .where('user_id', 1)
    .where('created_at', '>=', DateTime(2026))
    .orderBy('id', 'desc')
    .limit(10)
    .get();
Post? post = await Post().find(1);                // by primary key, or null
Post? byTitle = await Post().find('title', 'Hi'); // by another column
Post? first = await Post().where('title', 'Hi').getFirst();
Post sure = await Post().findOrFail(1);           // throws ModelNotFoundException -> 404
int total = await Post().where('user_id', 1).count();
bool taken = await Post().where('title', 'Hi').hasRows();
List<dynamic> titles = await Post().pluck('title');
List<Post> some = await Post().whereIn('id', <int>[1, 2, 3]).get();
List<Post> drafts = await Post().whereNull('published_at').get();
```

- `all()` ignores `orderBy` and `limit`. Use `get()` for those.
- There is no `exists()` on a query. Use `hasRows()` or `hasNoRows()`. `model.exists` is a getter on one model.
- Values are always bound, never put into the SQL.
- Without a model, `QueryBuilder.table('posts').where('id', 1).get()` gives a `List<Map<String, dynamic>>`.

### Pagination

```dart
Pagination<Post> page = await Post()
    .orderBy('id', 'desc')
    .paginate(currentPage: 2, perPage: 10);
List<Post> rows = page.data;
// page.toJson(): total, per_page, last_page, current_page, data
```

Return `page` from a controller as JSON, or put a serializer in place of `data`:
`<String, dynamic>{...page.toJson(), 'data': PostSerializer(page.data).toJson()}`.
`simplePaginate` skips the count. `cursorPaginate(perPage: 10, cursor: ...)` is fast on big tables.

### Big tables

```dart
await Post().chunkById(100, (List<Post> posts) {
  for (Post post in posts) {
    print(post.title);
  }
  return true; // false stops
});

// one row at a time, read 1000 rows per query (by id, or LIMIT/OFFSET with an orderBy)
await for (Post post in Post().where('status', 'draft').lazy()) {
  await post.delete();
}

// one row at a time from ONE query, the driver streams the rows
await for (Post post in Post().orderBy('id').cursor(chunkSize: 500)) {
  print(post.title);
}
```

`break` or `.take(n)` stops the query. `lazyById(column: 'n')` pages by another unique column.
In a transaction on Postgres or MySQL, `cursor()` can not `preload()` relations and other queries
of that transaction wait until it ends: use `lazy()` there.

## Relations

Add a relation field, then run `dart run build_runner build`.
Import the related model file at the top.

```dart
// lib/app/models/user/user.model.dart
import 'package:dox_orm/dox_orm.dart';

import '../post/post.model.dart';

part 'user.model.g.dart';

@DoxModel(table: 'users')
class User extends UserGenerator {
  @override
  List<String> get fillable => <String>['name'];

  @Column()
  String? name;

  @HasMany(Post) // posts.user_id points to users.id
  List<Post> posts = <Post>[];
}
```

```dart
// in Post
@BelongsTo(User) // this table has user_id
User? user;
```

| Annotation | Field type | Foreign key |
| --- | --- | --- |
| `@HasMany(Post)` | `List<Post> posts = <Post>[];` | `post.user_id` |
| `@HasOne(Profile)` | `Profile? profile;` | `profile.user_id` |
| `@BelongsTo(User)` | `User? user;` | `this.user_id` |
| `@ManyToMany(Tag)` | `List<Tag> tags = <Tag>[];` | a pivot table like `post_tag` |
| `@HasManyThrough(Post, through: User)` | `List<Post> posts = <Post>[];` | `user.country_id`, then `post.user_id` |
| `@HasOneThrough(Post, through: User)` | `Post? post;` | the same, one row |

- The default foreign key uses the class name in snake_case: `User` gives `user_id`.
  Set `foreignKey:` and `localKey:` when your columns are different.
- Relations are not loaded by default. Load them with the field name:

```dart
User? user = await User().preload('posts').find(1);      // one query for the posts
List<Post> posts = await Post().preload('user').get();
await user?.$getRelation('posts');                       // load on a model you have
List<Post> recent = await user
        ?.related<Post>('posts')
        ?.where('title', 'Hi')
        .orderBy('id', 'desc')
        .get() ??
    <Post>[];
List<User> writers = await User().whereHas('posts').get();
List<User> idle = await User().whereDoesntHave('posts').get();
```

- `eager: true` on the annotation loads the relation on every query.
- A through relation reads the far rows through a model in the middle.
  A country has many posts through its users:

```dart
// in Country. users.country_id points to the country,
// posts.user_id points to the user.
@HasManyThrough(Post, through: User)
List<Post> posts = <Post>[];

// other column names
@HasManyThrough(
  Post,
  through: User,
  foreignKey: 'home_country_id', // on users, points to the country
  localKey: 'id',                // on countries
  throughForeignKey: 'author_id', // on posts, points to the user
  throughLocalKey: 'id',         // on users
)
List<Post> authored = <Post>[];
```

  `preload`, `withCount`, `whereHas` and `has` work on it. Soft deleted
  users and posts are left out. In `onQuery` or a `whereHas` callback,
  write the table in front of a column (`'post.title'`): the query joins
  the two tables.
- A relation loaded with `preload` is in `toJson()`, under the field name in snake_case.

## Soft deletes

`@DoxModel(table: 'posts', softDelete: true)` needs a nullable `deleted_at` column
(`table.softDeletes();` in the migration).

```dart
await post.delete();                           // sets deleted_at
List<Post> withOld = await Post().withTrash().get();
List<Post> onlyOld = await Post().onlyTrashed().get();
await post.restore();
await post.forceDelete();                      // really deletes
```

## Transactions

```dart
int? id = await QueryBuilder.transaction(() async {
  Post post = Post()..title = 'Hello';
  await post.save();
  await QueryBuilder.table('post_logs').insert(<String, dynamic>{'post_id': post.id});
  return post.id;
});
```

It commits when the function ends, and rolls back when it throws.
All queries inside the function use the transaction. You do not pass it around.

## Factories

```bash
dox make:factory Post   # db/factories/post.factory.dart
```

```dart
// db/factories/post.factory.dart
import 'package:dox_orm/factory.dart';
import 'package:my_app/app/models/post/post.model.dart';

class PostFactory extends Factory<Post> {
  @override
  Post definition() {
    Post post = Post();
    post.title = 'Hello';
    post.body = 'My first post.';
    return post;
  }
}
```

```dart
List<Post> posts = await PostFactory().count(10).create(); // saved
Post one = await PostFactory().createOne();
Post notSaved = PostFactory().makeOne();
await PostFactory().count(3).state((Post p) => p..userId = user.id).create();
await PostFactory()
    .count(3)
    .sequence((Post p, int i) => p..title = 'Post $i')
    .create();
List<User> users = await UserFactory()
    .count(2)
    .has(PostFactory().count(3), (Post p, User u) => p..userId = u.id)
    .create(); // 2 users, each with 3 posts
```

Dox has no fake data generator. The `faker` package works with factories.

## Tests with the database

Run the migrations once, then empty the tables before each test with `refreshDatabase`:

```dart
import 'package:dox_core/testing.dart';
import 'package:dox_migration/dox_migration.dart';
import 'package:dox_orm/testing.dart';
import 'package:my_app/config/app.dart';
import 'package:my_app/config/database.dart';
import 'package:test/test.dart';

import '../db/migration/migrations.dart';

void main() {
  late DoxTestClient client;

  setUpAll(() async {
    await Migrator(
      migrations: migrations,
      config: databaseConfig.getConnectionConfig(),
    ).migrate();
    client = await DoxTestClient.start(appConfig); // runs the ORM provider
  });

  setUp(refreshDatabase); // every test starts with empty tables

  tearDownAll(() async {
    await client.close();
  });

  test('saves a post', () async {
    Post post = await PostFactory().createOne();
    expect(post.id, isNotNull);
  });
}
```

Import the model and factory files the test uses.
A test without `DoxTestClient` must set up the ORM itself: call `Dox().initialize(appConfig)`,
run the migrations, then `await ORMProvider().setup();` (from `lib/providers/orm_provider.dart`).
The tests use the database of `.env`. Put test values in `.env.testing`, like `DB_NAME=test.sqlite`.

## Config

The connections are in `lib/config/database.dart`. `DB_CONNECTION` in `.env` picks one:
`sqlite`, `postgres` or `mysql` (also MariaDB). The other keys are `DB_HOST`, `DB_PORT`,
`DB_USERNAME`, `DB_PASSWORD` and `DB_NAME` (for SQLite: the file path).
`lib/providers/orm_provider.dart` starts the ORM in every isolate with
`SqlQueryBuilder.initializeWithDatabaseConfig(databaseConfig)`.

### Pool settings (Postgres and MySQL)

Put them in `extra` of the `ConnectionConfig`. A `Duration`, or an int of seconds.

```dart
extra: <String, dynamic>{
  'maxConnectionCount': 10,
  'requestTimeout': const Duration(seconds: 30), // default 300 s
  'maxConnectionAge': const Duration(minutes: 30), // Postgres: no limit, MySQL: 12 h
  'idleTimeout': const Duration(minutes: 5), // Postgres: kept, MySQL: 12 h
  'serverKill': false, // MySQL only: no KILL QUERY (eg. behind ProxySQL)
},
```

### Stop a slow query

```dart
QueryCancelToken token = QueryCancelToken();
Future<List<Post>> posts = Post().where('status', 'draft').cancelWith(token).get();
token.cancel(); // throws PgQueryCancelledException or MysqlQueryCancelledException
```

SQLite does not support it: the query runs to its end.

## Switch from SQLite to Postgres or MySQL

A new app uses SQLite. The end of `pubspec.yaml` skips the download of the two other drivers:

```yaml
hooks:
  user_defines:
    dox_postgres_native:
      skip: true
    dox_mysql_native:
      skip: true
```

For Postgres:

1. In `pubspec.yaml`, remove both `dox_postgres_native` lines: the name line and the `skip: true` line under it.
   Keep the MySQL skip.
2. Set `DB_CONNECTION=postgres` and the other `DB_*` keys in `.env`.
3. Run `dart pub get`, then start the app again.

For MySQL, do the same with `dox_mysql_native`.

A driver that is still skipped stops the app with an error: the native library is not in the build.
The fix is step 1.

When the app never opens SQLite, you may also add `sqlite3: source: system`.
Then the build does not download SQLite:

```yaml
hooks:
  user_defines:
    dox_mysql_native:
      skip: true
    sqlite3:
      source: system
```

Do not add it when the app opens SQLite. A system without `libsqlite3` (like the `FROM scratch`
Docker image) then fails at runtime.
In a pub workspace, the `user_defines` block goes in the root `pubspec.yaml`.

Docs: https://dartondox.dev/latest/database/#skip-unused-drivers

## Before you finish

```bash
dart run build_runner build
dart format .
dart analyze
dart test
```
