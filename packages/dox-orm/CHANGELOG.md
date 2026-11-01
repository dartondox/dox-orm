## Unreleased

- New: the ORM is now the `PresenceVerifier` of `dox_validation`. So `v.string().exists('teams')` and `v.string().unique('users')` in fluent schemas read the database. It is set when the driver is set. An app that set its own verifier keeps it. This needs the next `dox_validation`.
- Fix: `@Unique` and `@Exists` now trust the database match. Before, they also compared the text in Dart. MySQL and MariaDB ignore case, so `TAKEN@dox.dev` passed `@Unique` when `taken@dox.dev` was in the table. On MySQL this also means `'1abc'` and `' 1'` find the id `1`, like Laravel. On a `List` field the whole list is one query, like Laravel: `@Exists` passes when the database finds as many different values as the list has, and `@Unique` passes when it finds none. When it can not tell which item matched, every item fails (the safe side). Limit long lists with `@MaxItems`.
- Fix: a nested transaction that fails now releases its savepoint after `ROLLBACK TO SAVEPOINT`. Before, every caught error left one savepoint open until the outer transaction ended.
- Fix: on Postgres, `@Unique` and `@Exists` with a value that does not fit the column no longer throw a database error (a 500). This is every Postgres "data exception" (SQLSTATE class 22), like `abc` for a number id, a number that is too big, text with a NUL byte, or a bad date for a `date` column. The value is "not found". When the bad value is the ignore value (`ignoreParam` from the URL, like `/users/abc`), no row can have it, so the ignore part is dropped and the value is still checked. A list with such a value fails every item, because one bad value fails the whole query. Other database errors still throw. Inside a transaction the lookup runs in a savepoint, so a caught error does not break the transaction.
- New: many to many writes, like Laravel. `attach()`, `detach()`, `sync()`, `syncWithoutDetaching()`, `toggle()` and `updateExistingPivot()` change the pivot rows of a `@ManyToMany` relation, like `await artist.sync('songs', [1, 2])`. `sync()` and `toggle()` return a `PivotSyncResult` with the `attached`, `detached` and `updated` ids (a number id is an `int`). The ids can be ids, models, a list, or a map of `id => extra pivot values`. `null` or `[]` means no ids, so `sync(null)` detaches all and `detach('songs', null)` detaches nothing. Only `detach('songs')` with no ids detaches all. Ids match the stored ids by value, like the database: `'01'` and `1.0` are song `1`. `attach()`, `detach()`, `toggle()`, `syncWithoutDetaching()` and `updateExistingPivot()` skip a null id or a model that is not saved. `sync()` throws an `ArgumentError` for one, before any query, so a missing id can not delete every link. An id is used once (`[1, '1']` gives one row). `sync()` and `toggle()` insert before they delete, so a failed insert keeps the old links.
- New: `@ManyToMany(withPivot: ['role'])` reads extra pivot columns, and `withTimestamps: true` reads and sets the pivot `created_at` and `updated_at`. Read them with `song.pivot['role']`. `pivot` has the two pivot keys for rows read by the relation (`preload`, `$getRelation`, `eager` or `related().get()`). A relation without `withPivot` and `withTimestamps` runs the same SQL as before. `updateExistingPivot()` takes one id or a list. `sync()` compares pivot values by type, so a bool read back as `1` does not count as updated. It needs dox_builder with `withPivot` support to make the code.
- New: polymorphic relations, like Laravel. `@MorphMany(Comment, 'commentable')` and `@MorphOne(...)` read the rows whose `commentable_id` and `commentable_type` point to this model. `@MorphTo()` on a `Model<dynamic>?` field reads the model a row points to, with one query per type. `Model.morphMap({'post': Post.new})` sets the type names (call it in a provider `setup()`, the map is per isolate). `Model.morphTypeOf()` and `Model.morphModel()` read it. `@MorphTo` needs every model it can point to in this map. Without a map, the type is the class name, like `Post`. `whereHas()` and `withCount()` work with `@MorphMany` and `@MorphOne`, not with `@MorphTo`. An empty type is like no type. It needs dox_builder with morph support to make the code.
- Breaking: models are guarded from mass assignment by default, like Laravel. `guarded` is now `['*']`. A model with no `fillable` throws `MassAssignmentException` when `create()`, `insert()`, `insertMultiple()`, `upsert()`, `update()`, `firstOrCreate()`, `firstOrNew()` or `updateOrCreate()` gets a map with keys. Before, it took every key, so `User().create(req.body)` could set `id` or `is_admin`. To fix: add `fillable` with the columns that may be set from a map, or set `guarded` to `const <String>[]` to take every key as before. `save()` and fields set in code are not changed.
- Fix: `update()` and `delete()` with `join()`, `orderBy()` or `limit()` now work on Postgres and SQLite. The rows are picked by primary key in a sub query. MySQL with no join and no offset keeps its own `ORDER BY ... LIMIT`. `groupBy()` and `having()` with `update()` or `delete()` now throw an `ArgumentError`, because the SQL was never valid.
- Warning: Postgres with `useSSL: true` (or `sslmode=require`) uses TLS mode `require`. It encrypts the data but does not check the server certificate. The app now prints one warning to stderr when it connects this way. The mode does not change. To check the certificate, set `extra['sslMode'] = 'verify-full'`. To hide the warning, set `extra['sslWarning'] = false` (or `sslWarning=false` in the database url). It prints once per isolate.
- New: `ConnectionConfig.logRedact` (and `SqlQueryBuilder().logRedact`) hides values in the debug query log. It is a list of names, like `['password', 'token']`. A value whose key ends with one of the names is shown as `***`. It is off by default, so the log does not change unless you set it.
- Fix: on MySQL and SQLite, `@name` inside a quoted string, a quoted name or a comment is no longer changed to a `?` parameter. Before, `whereRaw("name = '@who' OR name = @who", {'who': 'bob'})` sent two values for one `?` and failed. Postgres already worked this way.
- Fix: the debug query log now lists the values in the order of the `?` in the query. Before, it used the order the values were added, so `where(...).update(...)` showed the WHERE value first. Only the log changes.
- New: `FileQueryPrinter(file: f, buffered: true)` keeps the log lines in memory and writes them in the background, in order, so a query does not wait for the disk. Call the new `flush()` to wait until every line is in the file, eg. before `exit()`. The default does not change: each line is written before `log()` returns.
- Fix: `Logger.warn` now prints yellow, as its docs say. Before, it printed blue.
- Fix: a digit in a model or relation name no longer gets its own `_`. `Address2` now gives `address2`, the same as dox_builder. Before, the ORM gave `address_2`. This changes the default names for a model or relation with a digit in its name: the table name (`address2`), the foreign key (`address2_id`), the many-to-many pivot table (`address2_tag`) and the `withCount` key (`address2_count`). If you use these default names today, rename the table or column. Or keep the old names by setting them by hand: `tableName`, `foreignKey`, `pivotTable`, `pivotForeignKey` and `pivotRelatedForeignKey`. For `withCount`, use an alias: `withCount('address2 as address_2_count')`.

## 3.0.1

- Faster: `paginate()` runs the count query and the page query at the same time, on two connections. One page now waits for one database round trip, not two. In a transaction, and on SQLite, they still run one after the other.
- Faster: eager loading of a `belongsTo` relation reads the foreign key of each model once, not twice.
- Faster: the MySQL driver no longer tries to read every text that ends with `Z` as a date. A text that can not be a date is sent as it is, without the parse.

## 3.0.0

- The first stable release.

## 3.0.0-rc.1

- Fix: `create()` of a model now works like `save()` on a new model. Before, a model without hooks wrote the raw map. So `beforeSave` and the casts did not run, and `created_at` and `updated_at` were not set. Now `create()` fills a new model from the map and saves it. It fires the model events (saving, creating, created, saved), and a hook can cancel it. It sets `created_at` and `updated_at`, unless the model has `timestamps: false`. A value for them in the map is kept. Only `@Column` fields are saved. `insert()`, `firstOrCreate()` and `updateOrCreate()` of a model use it too. `QueryBuilder.table().create()` and `insert()` still write the map as it is.
- Fix: `firstOrNew()` and `create()` no longer fail on a model with a field that is not nullable, like `bool done = false`, when the map has no value for it. The field keeps its default.

## 3.0.0-alpha.14

- Fix: when many isolates open a new SQLite file at the same time (the first server start), some failed with `SqliteException(5): database is locked` on `PRAGMA journal_mode = WAL`. SQLite does not use `busy_timeout` for this step. Now it retries until `busyTimeout` (5 seconds by default) has passed.

## 3.0.0-alpha.13

- Fix: `whereHas()`, `whereDoesntHave()`, `has()` and `withCount()` now work on a relation to the same table, like the parent or the children of a category. Before, the subquery compared each row with itself, so the result was wrong. Now the subquery gives its table its own name.

## 3.0.0-alpha.12

- Breaking: `update()`, `delete()` and `forceDelete()` of a query return `Future<int>`: the number of changed rows. Postgres and SQLite count every row the where matched. MySQL and MariaDB count only the rows that really changed, so a row that already has the new values counts 0.
- Breaking: `delete()` and `forceDelete()` of a model return `Future<int>`, not `Future<bool>`. It is 1 when the row was deleted, and 0 when the row was not there or a hook throws `CancelModelEvent`.
- Breaking: `create()` and `insert()` return `Future<T>`: a model for a model query, a map for `QueryBuilder.table()`. Before, they returned `dynamic`, and `{}` when the new row could not be read. On MySQL, a table with no auto increment and no id in the data now gives back the data (as a map, or as a model made from it). The new row is read on a new query, so the where, the global scopes and the soft delete check of the query are not used.
- Breaking: custom `DBDriver` classes must override the new `affectingStatement()` to use `update()`, `delete()`, `increment()` and `upsert()`. The default throws an `UnsupportedError`.
- Breaking: `where('a', '=', null)` is now `"a" IS NULL`, and `where('a', '!=', null)` (or `<>`) is `"a" IS NOT NULL`. Before, they gave `"a" = '='` and `"a" = '!='`, so the query ran with wrong rows. Any other operator with `null` throws an `ArgumentError`. `where('a')` with no value throws an `ArgumentError` (it was `IS NULL`). The same for `orWhere()`.
- Breaking: a model with a field or getter that has the name of a new query method (`min`, `max`, `sum`, `avg`, `latest`, `oldest`, `distinct`, `having`, `when`, `chunk`, `pluck`, `has`, ...) does not compile.
- Fix: `update({})` sent `UPDATE "t" SET` and failed. Now it runs no query and returns 0.
- Fix: `paginate(perPage: 0)` failed with `Infinity or NaN toInt`. Now a `perPage` below 1 throws an `ArgumentError`, and a `currentPage` below 1 is read as page 1.
- Fix: params that the `onQuery` of a relation adds get the key prefix of the subquery, so they do not clash with the parent query in `withCount()`.
- New `whereHas()`, `orWhereHas()`, `whereDoesntHave()`, `orWhereDoesntHave()` and `has(relation, [operator, count, where])`. They add an `EXISTS`, `NOT EXISTS` or `COUNT` subquery for a `hasOne`, `hasMany`, `belongsTo` or `manyToMany` relation. A name like `posts.comments` checks a relation of a relation. Soft deleted related rows do not count. A relation to the same table does not work yet.
- New `whereGroup()`, `orWhereGroup()`, `whereNot()` and `orWhereNot()`: conditions in brackets, with a callback. Groups can nest.
- New `whereBetween()`, `whereNotBetween()`, `whereColumn()`, `whereExists()`, `whereNotExists()`, `whereLike()` and `whereNotLike()`, each with an `or` form. `whereLike()` does not care about case by default (`ILIKE` on Postgres). `caseSensitive: true` uses `LIKE` on Postgres, `LIKE BINARY` on MySQL and `GLOB` on SQLite.
- New `lockForUpdate()` and `sharedLock()`: `FOR UPDATE` and `FOR SHARE` on Postgres, `FOR UPDATE` and `LOCK IN SHARE MODE` on MySQL and MariaDB, nothing on SQLite (a SQLite transaction already takes the write lock). A lock lasts only inside `QueryBuilder.transaction()`. A locked `find()` does not use the find SQL cache.
- New `firstOrFail()` and `findOrFail()`. They throw the new `ModelNotFoundException` (with `table`, `id` and `column`).
- New `hasRows()` and `hasNoRows()`, `pluck()`, `pluckMap()` and `valueOf()`.
- New `sum()`, `avg()`, `min()` and `max()`. They give `null` when no row matches, and throw a `StateError` with `groupBy()`.
- New `distinct()`. `count()` then counts the distinct rows, and `sum()` and `avg()` use the distinct values.
- New `having()`, `orHaving()`, `havingRaw()` and `orHavingRaw()`.
- New `chunk()` and `chunkById()`. The callback returns `false` to stop.
- New `latest()`, `oldest()`, `inRandomOrder()` and `when()`.
- New `increment()` and `decrement()`, on a query and on a model. They run one `SET col = col + @n` query and return the changed rows. On a model they change only its row, and the model field gets the new value. They fire no events and do not set `updated_at`.
- New `Model.setColumnValue(column, value)`: sets a field by its column name. `dox_builder` writes it for every model, so run `build_runner` again after you update. Models made by an older `dox_builder` still work, but `increment()` does not change their field.
- New `upsert(rows, uniqueBy, [updateColumns])`: `ON CONFLICT ... DO UPDATE` on Postgres and SQLite, `ON DUPLICATE KEY UPDATE` on MySQL and MariaDB. It returns the changed rows. The model form drops keys that `fillable` and `guarded` do not allow, and sets `created_at` and `updated_at`.
- New `firstOrCreate()`, `firstOrNew()` and `updateOrCreate()`. The model forms go through `save()`, so the model events fire.
- `insertMultiple()` docs say what it returns on each driver.

## 3.0.0-alpha.11

- Version bump only, to match the other packages.

## 3.0.0-alpha.10

- Version bump only, to match the other packages.

## 3.0.0-alpha.9

- Breaking: the `ModelObserver` methods now have the same names as the model hooks: `onSaving`, `onSaved`, `onCreating`, `onCreated`, `onUpdating`, `onUpdated`, `onDeleting`, `onDeleted`, `onRestoring`, `onRestored`, `onForceDeleting` and `onForceDeleted`. Rename the methods in your observers, for example `created(User user)` to `onCreated(User user)`.
- New model factories: `import 'package:dox_orm/factory.dart';`. Extend `Factory<User>` and write `definition()`. Then use `count(n)`, `state()`, `sequence()`, `has()`, `make()`, `makeOne()`, `create()` and `createOne()`. See the Factories docs page.
- New query scopes. `@Scope()` on a static model method adds it as a query method, like `User().isActive().get()`. `@Scope(global: true)` adds it to every query of the model. Remove it with `withoutGlobalScope('name')` or `withoutGlobalScopes()`.
- New attribute casts with `@Column(cast: ...)`: `JsonCast`, `ListCast<E>`, `BoolCast`, `EnumCast<E>` (by name or by index), or your own `Cast<T>` class. `bool` fields get `BoolCast` and enum fields get `EnumCast` without `cast`.
- New `withCount('posts')`, `withSum('posts', 'views')` and `withMax('posts', 'views')`. They add the value with a subquery, for `hasOne`, `hasMany` and `manyToMany` relations. Read it with `countOf('posts')` or `aggregate('posts_sum_views')`. `toJson()` has it too.
- `all()` now uses the where conditions of the query, like `get()`. Before, it used only the soft delete check.
- New: `package:dox_orm/testing.dart` with `refreshDatabase()`. Use `setUp(refreshDatabase)` in tests: it empties every table and starts the ids at 1 again, on Postgres, MySQL, MariaDB and SQLite. The migrations table keeps its rows. `keep:` keeps more tables.

## 3.0.0-alpha.8

- A `transaction()` inside another transaction now uses a savepoint (`SAVEPOINT sp_N`). When the inner function throws, only its work is undone, and the error is thrown again. If the caller catches the error, the outer transaction goes on and can commit. Before, the inner one joined the outer one, so an inner error always undid the outer work too. Works on Postgres, MySQL, MariaDB and SQLite. New `DBDriver.savepoint()`.
- Postgres: new `extra['sslRootCert']`, the path of a PEM file with the CA certificates to trust for `verify-full`. `sslrootcert` in `DATABASE_URL` sets it. New `ConnectionConfig.postgresSslRootCert`. Needs the next `dox_postgres_native` release.

## 3.0.0-alpha.7

- Breaking: Postgres and MySQL use only the native drivers. The Dart drivers (`postgres` and `mysql_dart` packages) are gone. So are `PostgresDriver`, `MysqlDriver`, `DOX_DB_DRIVER=dart` and `extra['native']`.
- Breaking: when the native library does not load, `createDriver()` and `SqlQueryBuilder.initializeWithDatabaseConfig()` throw an `UnsupportedError`. It says why the library did not load and how to fix it. Before, the ORM used the Dart driver and printed a warning.
- Postgres has TLS now. `useSSL: true` is mode `require` (no certificate check, like libpq). `extra['sslMode']` is a `String`: `disable`, `prefer`, `require` or `verify-full`. `sslmode` in `DATABASE_URL` sets it. `prefer` and `allow` in the url now mean "TLS when the server has it".
- Breaking: errors are `PgServerException` and `PgException` for Postgres, and `MysqlException` for MySQL. `dox_orm` exports them. The `ServerException` classes of the `postgres` package and `MySQLServerException` are gone.
- Breaking: `ConnectionConfig` loses `getDatabaseConnection()`, `postgresEndpoint`, `mysqlHost`, `mysqlPort`, `mysqlAllowPublicKeyRetrieval` and `mysqlAcceptBadCertificate`. `postgresSslMode` is now a `String`. The `collation`, `timeoutMs`, `timeZone` (MySQL), `serverPublicKey`, `allowPublicKeyRetrieval` and the `postgres` package pool keys of `extra` are no longer read.
- Breaking: `getDatabaseDriver()` and `SqlQueryBuilder.initialize()` take a `PgNativePool` for Postgres and a `MysqlNativePool` for MySQL.
- On Postgres, a `List` in `insert()` or `update()` is sent as json text, so it fits a json column. New `DBDriver.columnValue()`.
- `dox_postgres_native` and `dox_mysql_native` now live in their own repos (dartondox/dox-postgres-native, dartondox/dox-mysql-native). Dox uses them from pub.dev (`^3.0.0-alpha.7`). Their build hooks download ready-built libraries, so you do not need Rust.
- Faster `belongsTo` load. It reads each owner once with `WHERE owner.id IN (...)`, with no join to the children. Before, a user with 10,000 blogs came back 10,000 times. Children of the same owner now get the same model object.
- `save()` on a new model runs one `INSERT` and reads the id from it. There is no `SELECT` after it. `insert()` and `create()` use `RETURNING *` on Postgres and SQLite, so they also skip the `SELECT`. MySQL still reads the row with `find()`.
- `save()` on an existing model sends only the columns that changed since the last load or save. A `Map` or `List` field is always sent. When nothing changed, `save()` runs no query and `updated_at` stays as it is. Before, it always ran an `UPDATE` with every column that had a value.
- Fix: after `restore()`, a `save()` on the same model sent the old `deleted_at` again and deleted the row again. Now `deleted_at` is not sent, because it did not change.
- `LIMIT` and `OFFSET` are bound parameters (`@dox_limit`, `@dox_offset`). Every page gives the same SQL, so the drivers reuse one prepared statement.
- On Postgres, `whereIn` and `whereNotIn` with only `int` or only `String` values send one array parameter (`= ANY(@p)`, `<> ALL(@p)`). A list of any size gives the same SQL. Other lists keep one parameter per value.
- Relations of one model (`preload` and `eager`) load at the same time outside a transaction, so the native drivers send them in one batch. Inside a transaction they still load one by one. New `DBDriver.inTransaction`.
- Rows of a model made by the new generator skip the date to string step. `fromMap()` takes the `DateTime` of the driver as it is. `toMap(original: true)` still gives dates as ISO strings.
- New `Model.columnsToMap()`: the columns only, without relations. `save()` uses it, so it no longer turns preloaded relations into JSON.
- Less work per row: the where, join and order lists of a model are made only when used. `getPreload()` and the generated getters do not make a new list or map on each call.
- The SQL text is no longer scanned for double spaces on each query. `orderBy()` without a direction no longer adds a space.
- `QueryBuilderHelper.runQuery()` no longer has the `clean` parameter.
- Fix: in a native Postgres or MySQL `transaction()`, when the rollback after an error also fails, the first error is thrown. Before, the rollback error replaced it.
- The native Postgres driver shares one pool for all isolates with the same settings, like the native MySQL driver. `maxConnectionCount` is for the whole process on both native drivers.
- The Dart Postgres driver keeps its prepared statements after a session command like `SET`, `SHOW`, `BEGIN` or `COMMIT`. Before, any query that was not select/insert/update/delete dropped all of them.
- Breaking: column and table names in `select`, `where`, `orderBy`, `groupBy`, `join`, `insert` and `update` must be plain names (`name`, `table.name`, `table.*`, `*`, `name as alias`). Anything else, like `count(*)`, throws an `ArgumentError`. Before, a name with `(` went into the SQL as it is, so user input could add SQL. Use `selectRaw`, `whereRaw` or the new `orderByRaw` and `groupByRaw` for expressions.
- Breaking: the operator of `where()` and `join()` must be one of `=`, `!=`, `<>`, `<`, `>`, `<=`, `>=`, `like`, `not like`, `ilike` (any case). Any other value throws an `ArgumentError`.
- New `fillable` and `guarded` lists on `Model`. When set, `create()`, `insert()` and `update()` on the model drop the keys that are not allowed, so `User().create(req.body)` can not set `is_admin`. `insertMultiple()` on the model drops them from each row too. Both are empty by default, so nothing changes until you set them.
- Breaking: TLS checks the server certificate. Postgres `useSSL` (and `sslmode=verify-ca` or `verify-full` in a url) now uses `SslMode.verifyFull`. `sslmode=require` in a url stays `SslMode.require` like libpq: it encrypts but does not check the certificate (eg. Heroku). The Dart MySQL driver no longer accepts a bad certificate. Set `extra['verifyCertificate']` to false (or `?verifyCertificate=false` in a url) to skip the check for a self-signed certificate in development.
- Breaking: the Dart MySQL driver no longer asks the server for its RSA key by default. It still asks with TLS on, or on `localhost`, `127.0.0.1`, `::1` and a Unix socket. Give the key in `serverPublicKey`, or set `allowPublicKeyRetrieval: true`.

## 3.0.0-alpha.6

- MySQL and MariaDB Unix sockets. A host that starts with `/` is the socket file, like `/var/run/mysqld/mysqld.sock` or `/cloudsql/project:region:instance` on Cloud Run. Works on the native and the Dart driver. In a url, use `?socket=/path` or `?host=/path`.
- New `SqlQueryBuilder.close()`. It closes every open database connection of the isolate: the default and all named connections, on every driver (native Postgres and MySQL, the Dart drivers and SQLite). It is safe to call twice. Call it on shutdown, eg. from a `DoxShutdown` service.
- New `DBDriver.close()`, for one driver. Custom drivers can override it. The default does nothing.
- `SqlQueryBuilder().dbDriver` throws a `StateError` with a clear message when the ORM is not set up (or after `close()`).
- After `close()`, the native MySQL driver throws a `StateError` on a new query or transaction. Before, the query still ran when another isolate kept the shared pool open.

## 3.0.0-alpha.5

- `DATABASE_URL` support. `ConnectionConfig.fromUrl()` reads `postgres://`, `postgresql://`, `mysql://`, `mariadb://`, `sqlite:` and `file:` urls: url-decoded user and password, host, port, database, `sslmode` and other options (they go to `extra`).
- `DatabaseConfig` has a new `url`. It is `DATABASE_URL` from the environment when not given. When it is set, it wins: it replaces the default connection. Pass `url: ''` to turn it off.
- Postgres Unix sockets. A host that starts with `/` is a socket folder, like `/cloudsql/project:region:instance` on Cloud Run. Works on the native and the Dart driver. Use `?host=/cloudsql/...` in a url.
- Breaking: the finders are typed. On a model, `get()` and `all()` give `Future<List<T>>`, `find()` and `getFirst()` give `Future<T?>`, and `paginate()` gives `Future<Pagination<T>>` (`page.data` is a `List<T>`). `QueryBuilder.table()` gives maps: `get()` is `Future<List<Map<String, dynamic>>>` and `getFirst()` is `Future<Map<String, dynamic>?>`. `QueryBuilder.table()` has no type argument and no second argument any more.
- Breaking: `groupBy()` and `rawQuery()` rows are maps, so use them on `QueryBuilder.table()`. On a model, `get()` throws a `StateError` for them. `count()` with `groupBy()` still works on a model.
- Breaking: the default foreign keys use the model name, like Laravel. A `User` model with `table: 'users'` gives `user_id`, not `users_id`. The default pivot table of `@ManyToMany` also uses the model names (`artist_song`). Keys you set yourself work as before. New `Model.foreignKeyName` gives the default key of a model.
- Breaking: `save()` inserts when the model is new and updates when the row is in the table (`model.exists`). Before, it updated when the primary key was set. So a new model with a key you set yourself, like a UUID, is now inserted.
- `QueryBuilder.query()` has a new `connection` parameter, to run a raw query on a named connection.
- Fix: `withConnection()` did not reach `save()`, `delete()`, `forceDelete()` and `restore()`. They used the default connection. Now they use the connection of the model. Models that a query returns keep the connection of the query, and relation queries use the connection of the parent model. `Model.withConnection()` returns the model, so `Blog()..withConnection('other')` works.

## 3.0.0-alpha.4

- Version bump only, to match the other packages.

## 3.0.0-alpha.3

- Postgres and MySQL/MariaDB now use the native drivers by default (`dox_postgres_native` and `dox_mysql_native`). You do not change any config. If the native library does not load, the ORM uses the Dart driver and prints one warning line. Set `DOX_DB_DRIVER=dart`, or `extra: {'native': false}` on one connection, to use the Dart driver. `driverFactory` still wins over all of this.
- Breaking: `PostgresNativeDriver` and `MysqlNativeDriver` moved into `dox_orm`. Import them from `package:dox_orm/dox_orm.dart`.
- `PostgresNativeDriver.query` does one less async step per query.
- Faster queries on all databases. Each connection keeps its prepared statements (LRU, 100 by default, `extra['preparedStatementCacheSize']`). The same query now has the same sql text, so the statements are reused. `find()` no longer sends `LIMIT 1 OFFSET 0`: LIMIT and OFFSET are only sent when set, and never `OFFSET 0`. Less work per row when models are built. A find by id on SQLite went from 23 µs to 6 µs.
- Less Dart work per query. A plain `find()` builds its SQL once per driver, table and column, and reuses it. A model makes its maps and lists only when they are used. Rows become models without one more `await` when there is nothing to preload. ORM work per `World().find(id)` went from 2.6 µs to 1.0 µs (no database, AOT).
- New `ConnectionConfig.driverFactory`: plug in your own driver class with one line. The default and the named connections use it.

## 3.0.0-alpha.2

- Needs Dart 3.13 or newer.
- All dependencies updated to their latest versions.
- `sqlite3` 3. SQLite is now bundled by a build hook, so no system `libsqlite3` is needed.
- Breaking: `dart compile exe` does not work with build hooks. Use `dart build cli` (or `dox build`).
- SQLite: set `busy_timeout` before `journal_mode = WAL`. Before, many isolates that opened the same file at start could fail with "database is locked".
- New DTO rules `@Unique('users', column: 'email', ignoreParam: 'id')` and `@Exists('teams')`. They run after all other checks. A `List` field is checked with one `WHERE IN` query. Soft-deleted rows count too.


## 3.0.0-alpha.1

- Renamed from `dox_query_builder` to `dox_orm`. Change `package:dox_query_builder/dox_query_builder.dart` to `package:dox_orm/dox_orm.dart`. The old package still works for now: it only re-exports this one.
- Added SQLite (`Driver.sqlite`, package `sqlite3`). `database` is a file path or `:memory:`. Uses WAL, `busy_timeout` and foreign keys. One connection per isolate. See the docs for limits.
- MySQL driver is now `mysql_dart` (was `mysql1`). The MySQL 8 default login (`caching_sha2_password`) works. It uses a real connection pool (`maxConnectionCount`, default 10), prepared statements with bound values, and one pooled connection per transaction.
- Breaking: `extra['characterSet']` (a `mysql1` type) is no longer read. Use `extra['collation']` (default `utf8mb4_general_ci`). `getDatabaseConnection()` for MySQL now returns a `MySQLConnectionPool`.
- Breaking: MySQL `TIME` columns are now a `String` (was a `Duration`). `BLOB` columns are `Uint8List` (was text).
- `ConnectionConfig`: `user`, `password` and `port` are optional (not used by SQLite).
- Needs Dart 3.6 or newer.
- Added `whereNull`, `whereNotNull`, `orWhereNull`, `orWhereNotNull`, `whereNotIn`, `orWhereIn`, `orWhereNotIn` and `selectRaw`.
- Added `QueryBuilder.transaction()`. Postgres now uses a real connection pool (`maxConnectionCount`) and no longer runs each query in its own transaction.
- Added `boolean()` schema column (Postgres `BOOLEAN`, MySQL `TINYINT(1)`, read as `bool`).
- Table and column names are now quoted (`"name"` on Postgres, `` `name` `` on MySQL). On Postgres, quoted names are case sensitive. Use `selectRaw`/`whereRaw` for raw SQL.
- `count()` ignores `limit`, `offset` and `orderBy`. With `groupBy` it now returns the number of groups (before: the size of the first group).
- `save()` can set a field to null on update.
- `insert()` works with any primary key type (uuid strings too).
- `model.delete()` and `model.forceDelete()` only delete that record. Before, they had no where condition.
- `forceDelete()` also deletes soft deleted rows. `withTrash(false)` on a model without soft deletes no longer adds a `deleted_at` filter.
- hasOne, hasMany and manyToMany work with a custom `localKey`.
- `insertMultiple()` uses keys from all rows. Missing keys use the column default.
- MySQL: only JSON columns are decoded (arrays too). MariaDB keeps decoding JSON-like text, because it stores JSON as text.
- Schema: `unique()` on a column that is already unique is skipped. Default values are escaped.

## 2.1.0

- Added support for MYSQL driver

## 2.0.0

- Support postgres driver v3

## 1.1.16

- Bug fixed on save
- Change `newQuery` to `query()` and deprecate `newQuery`

## 1.1.15

- Bug fixed on toMap

## 1.1.14

- Bug fixed on eager/preload data missing in `toMap` response.
- Bug fixed on `deleted_at` column conflict.
- Support for `withTrash` chain on any query builder function.

## 1.1.13

- Update readme
- bug fixed on count() with order by

## 1.1.12

- Add support for paginate() function
- Add support for query printer, file printer, consoler printer and pretty printer.

## 1.1.11

- Add missing types on function and arguments
- Bug fixed on count, custom query

## 1.1.10

- Remove hidden fields on toJson

## 1.1.9

- Bug fixed on jsonEncode(Model)

## 1.1.8

- Update readme

## 1.1.7

- Add option in `toMap()` to remove hidden fields

## 1.1.6

- Create own annotation and builder
- Added belongsTo support
- Added hasOne support
- Added hasMany support
- Added manyToMany support
- Added eager loading support

## 1.0.11

- Bug fixed id null on save

## 1.0.10

- Bug fixed on debug option in model
- Bug fixed on debug query param missing
- Support Postgres Pool
- Support hidden fields in model

## 1.0.1

- Update documentation

## 1.0.0

- Initial release
