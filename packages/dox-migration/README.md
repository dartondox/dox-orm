# dox_migration

Database migrations in Dart for Postgres, MySQL, MariaDB and SQLite.

[![pub package](https://img.shields.io/pub/v/dox_migration.svg)](https://pub.dev/packages/dox_migration)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/dartondox/dox-orm/blob/main/LICENSE)

Part of [Dox](https://dartondox.dev), a web backend framework for Dart.
Source code: [github.com/dartondox/dox-orm](https://github.com/dartondox/dox-orm).

## Install

```bash
dart pub add dox_migration
```

The `dox` CLI makes the files and runs the commands. A new app made with `dox create` already has it.

To see what is ready and what may still change, read [Status and roadmap](https://dartondox.dev/latest/concepts/status-and-roadmap/).

## Use it

`dox make:migration create_users_table` makes this file:

```dart
import 'package:dox_migration/dox_migration.dart';

class CreateUsersTable extends Migration {
  @override
  Future<void> up(Schema schema) async {
    await schema.create('users', (Table table) {
      table.id();
      table.string('email').unique();
      table.timestamps();
    });
  }

  @override
  Future<void> down(Schema schema) async {
    await schema.dropIfExists('users');
  }
}
```

It also writes the list of migrations (`db/migration/migrations.dart`) and `bin/migrate.dart`.
Then run:

```bash
dox migration:run        # or: dox migrate
dox migration:rollback
dox migration:status
```

The server binary can run them at start:

```dart
Dox().initialize(appConfig);
await Migrator(migrations: migrations).migrate();
await Dox().startServer();
```

## Features

- One Dart migration works on Postgres, MySQL, MariaDB and SQLite.
- Plain `.sql` migrations work too, in the same folder.
- Run, rollback (by batch or `--step`), reset, refresh and status.
- Each migration runs in one transaction. On MySQL, `CREATE`, `ALTER` and `DROP` can not be undone.
- The migration list is compiled in, so an AOT binary can migrate.
- Reads the database settings from `DATABASE_URL`, or `DB_CONNECTION`, `DB_HOST`, ... A real env var wins over `.env`.
- With no database settings, it uses SQLite with `db/dox.sqlite`, the same as the app template.
- A lock lets only one app instance run the migrations at a time. The others wait.

## Documentation

- [Migration](https://dartondox.dev/latest/database/migration/) and [Schema](https://dartondox.dev/latest/database/schema/)
- [API reference](https://pub.dev/documentation/dox_migration/latest/)

## License

MIT. See [LICENSE](https://github.com/dartondox/dox-orm/blob/main/LICENSE).
