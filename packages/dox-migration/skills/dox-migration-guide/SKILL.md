---
name: dox-migration-guide
description: How to write and run database migrations and seeders in a Dox app with dox_migration. Use it when you create or change a table, add columns, indexes or foreign keys, run, roll back or check migrations, write a seeder, or run migrations in a test.
---

# Dox migration guide

`dox_migration` runs migrations and seeders. The schema builder (`Schema`, `Table`) comes from
`dox_orm`, and `package:dox_migration/dox_migration.dart` exports it.
Models and factories are in the `dox-orm-guide` skill.

Full docs:

- https://dartondox.dev/latest/database/migration/
- https://dartondox.dev/latest/database/schema/
- https://dartondox.dev/latest/database/seeders/

## Files

| Path | What it is |
| --- | --- |
| `db/migration/<date>_<name>.dart` | one migration |
| `db/migration/migrations.dart` | the list of all Dart migrations. The CLI writes it. Never edit it. |
| `db/seeders/<name>.seeder.dart` | one seeder |
| `db/seeders/database.seeder.dart` | `DatabaseSeeder`: `dox db:seed` runs it |
| `db/seeders/seeders.dart` | the list of all seeders. The CLI writes it. Never edit it. |
| `bin/migrate.dart`, `bin/seed.dart` | the scripts that the `dox` commands run |

## Make a migration

Stop `dox s` first. `bin/server.dart` runs new migrations at start, before you add the columns.

```bash
dox make:migration create_posts_table      # schema.create('posts', ...)
dox make:migration add_slug_to_posts_table # schema.table('posts', ...)
dox make:model Post -m                     # a model and its create_posts_table migration
```

The CLI writes `db/migration/<yyyy>_<mm>_<dd>_<hhmmss>_<name>.dart` and updates `migrations.dart`.
Never write a migration file by hand, and never edit `migrations.dart`.

```dart
// db/migration/<date>_create_posts_table.dart
// ignore_for_file: file_names
import 'package:dox_migration/dox_migration.dart';

class CreatePostsTable extends Migration {
  @override
  Future<void> up(Schema schema) async {
    await schema.create('posts', (Table table) {
      table.id();
      table.foreignId('user_id').nullable().constrained('users').nullOnDelete();
      table.string('title');
      table.text('body');
      table.enumeration('status', <String>['draft', 'published']).defaultTo('draft');
      table.timestamps();
    });
  }

  @override
  Future<void> down(Schema schema) async {
    await schema.dropIfExists('posts');
  }
}
```

Every migration has `up` and `down`. `down` undoes `up`.

Change a table in a new migration:

```dart
class AddAvatarToUsersTable extends Migration {
  @override
  Future<void> up(Schema schema) async {
    await schema.table('users', (Table table) {
      table.string('avatar').nullable();
    });
  }

  @override
  Future<void> down(Schema schema) async {
    await schema.table('users', (Table table) {
      table.dropColumn('avatar');
    });
  }
}
```

- Never change a migration that already ran. Make a new migration.
- Columns are `NOT NULL` by default. Add `.nullable()` for optional columns.
- A column in `schema.table` is added. Add `.change()` to change a column that exists,
  and give every modifier you want to keep: `table.string('title', 500).nullable().change();`.
- Raw SQL in a migration: `await schema.driver.execute('UPDATE ...');`.
  Do not use models or `QueryBuilder` in a migration. They use another connection.

## Schema builder

Tables: `create`, `table`, `drop`, `dropIfExists`, `rename(from, to)`, `hasTable`, `hasColumn`.

Column types:

| Method | Notes |
| --- | --- |
| `id()` | big auto increment primary key `id` |
| `string('c', [255])`, `char('c', [255])` | text with a length |
| `text('c')`, `mediumText`, `longText` | long text |
| `integer`, `bigInteger`, `smallInteger`, `tinyInteger`, `unsignedInteger` | numbers |
| `float`, `double`, `decimal('c', [8], [2])` | decimals |
| `boolean('c')` | bool |
| `date`, `dateTime`, `dateTimeTz`, `time`, `timestamp`, `timestampTz` | dates and times |
| `json('c')`, `jsonb('c')` | JSON. Use a `Map<String, dynamic>?` or `List<dynamic>?` model field. |
| `uuid(['uuid'])`, `ulid(['ulid'])` | ids as text |
| `enumeration('c', <String>['a', 'b'])` | one of the values |
| `foreignId('user_id')`, `foreignUuid`, `foreignUlid` | a key column for another table |
| `timestamps()` | nullable `created_at` and `updated_at` |
| `softDeletes()` | nullable `deleted_at`, for `@DoxModel(softDelete: true)` |
| `morphs('owner')` | `owner_id`, `owner_type` and an index |

Modifiers (chain them): `nullable()`, `defaultTo(value)`, `defaultRaw('sql')`, `useCurrent()`,
`unique()`, `index()`, `primary()`, `unsigned()`, `comment('text')`, `after('column')` (MySQL), `change()`.

Foreign keys:

```dart
table.foreignId('user_id').constrained('users').cascadeOnDelete();
table.foreignId('team_id').nullable().constrained('teams').nullOnDelete();
```

`constrained()` with no table guesses it from the column: `user_id` gives `users`.
Give the table name when it is different.

Indexes and drops:

```dart
table.index(<String>['state', 'created_at']);
table.unique('slug');
table.dropIndex(<String>['state', 'created_at']);
table.dropUnique('posts_slug_unique');
table.dropColumn('age');
table.renameColumn('bio', 'about');
table.dropConstrainedForeignId('user_id');
```

## Run migrations

```bash
dox migration:run             # run the new migrations (also: dox migrate)
dox migration:status          # which migrations ran, and their batch
dox migration:rollback        # undo the last batch
dox migration:rollback --step=2   # undo the last 2 migrations
dox migration:reset           # undo every migration
dox migration:refresh         # undo every migration, then run them all again
dox migration:fresh           # drop every table, then run all migrations
dox migration:run --seed      # run, then run DatabaseSeeder
```

- `migration:fresh` drops every table, also tables that no migration made. Never run it on production.
- The database comes from `.env`: `DB_CONNECTION`, `DB_HOST`, `DB_PORT`, `DB_USERNAME`, `DB_PASSWORD`, `DB_NAME`.
- The ran migrations are saved in the `dox_db_migration` table.
- `dart run bin/migrate.dart <run|rollback [--step=n]|reset|refresh|status>` works too.
- `bin/server.dart` runs the new migrations each time the server starts:

```dart
Dox().initialize(appConfig);
await Migrator(
  migrations: migrations,
  config: databaseConfig.getConnectionConfig(),
).migrate();
await Dox().startServer();
```

## Seeders

```bash
dox make:seeder Post   # db/seeders/post.seeder.dart, and updates seeders.dart
```

```dart
// db/seeders/post.seeder.dart
import 'package:dox_migration/dox_migration.dart';

import '../factories/post.factory.dart';

class PostSeeder extends Seeder {
  @override
  Future<void> run() async {
    await PostFactory().count(10).create();
  }
}
```

Add the new seeder to `DatabaseSeeder`, and import its file at the top:

```dart
// db/seeders/database.seeder.dart
import 'package:dox_migration/dox_migration.dart';

import 'post.seeder.dart';
import 'user.seeder.dart';

class DatabaseSeeder extends Seeder {
  @override
  Future<void> run() async {
    await call(<Seeder>[UserSeeder(), PostSeeder()]);
  }
}
```

```bash
dox db:seed                     # run DatabaseSeeder
dox db:seed --class=PostSeeder  # run one seeder
```

- `call()` runs the seeders one after another, in the list order.
- A seed runs in one transaction. When a seeder throws, nothing is saved.
- Use factories, models or `QueryBuilder` in `run()`.

## Migrations in tests

Run the migrations once in `setUpAll`, before `DoxTestClient.start`:

```dart
import 'package:dox_migration/dox_migration.dart';
import 'package:my_app/config/database.dart';

import '../db/migration/migrations.dart';

setUpAll(() async {
  await Migrator(
    migrations: migrations,
    config: databaseConfig.getConnectionConfig(),
  ).migrate();
});
```

`my_app` is the `name:` of the app's `pubspec.yaml`.
To empty the tables before each test, use `setUp(refreshDatabase);` from `package:dox_orm/testing.dart`.

## Before you finish

```bash
dox migration:run
dox migration:status
dart analyze
dart test
```
