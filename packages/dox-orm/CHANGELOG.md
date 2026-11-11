## Unreleased

- New: `Schema.hasColumns(table, columns)` is true when the table has every one of the columns, like Laravel `Schema::hasColumns`. It is case sensitive, like `hasColumn`.
- New: `Schema.hasIndex(table, index)` is true when the table has the index, like Laravel `Schema::hasIndex`. `index` is an index name (a `String`), or a list of its columns in the order of the index. The primary key is named `primary` on MySQL, MariaDB and SQLite. The name is compared like the database does: case-insensitive on MySQL, MariaDB and SQLite, exact on Postgres.
- New: `Schema.disableForeignKeyConstraints()`, `enableForeignKeyConstraints()` and `withoutForeignKeyConstraints(callback)`, like Laravel. `withoutForeignKeyConstraints` turns the checks on again after the callback, also when it throws. Limits:
  - SQLite: `PRAGMA foreign_keys`. It is for the one connection of the isolate, so other code of the isolate is not checked either while it is off. Inside a transaction it does nothing (a migration already runs with the checks off on SQLite).
  - MySQL and MariaDB: `SET FOREIGN_KEY_CHECKS`. It is a setting of one pool connection, so `disable` and `enable` must run inside a transaction (a migration runs in one), else they throw a `StateError`. Turn the checks on again before the transaction ends. `withoutForeignKeyConstraints` runs in a transaction (a savepoint inside one), so it does this for you.
  - Postgres: `SET CONSTRAINTS ALL DEFERRED` and `IMMEDIATE`, like Laravel. Only keys made `DEFERRABLE` (with raw SQL) wait, and only until the checks are on again or the commit. Dox keys are not `DEFERRABLE`, so they are still checked. It must run inside a transaction too.
- New: `QueryBuilder.transaction(callback, attempts: n)` runs the whole transaction again when it fails with a deadlock or a lock / serialization failure, up to `n` runs in all, like Laravel `DB::transaction($callback, $attempts)`. Other errors are thrown at once. There is no wait between the runs. The default is 1, which works as before (0 and below run once too). Only the outermost transaction runs again: a nested one gives the error to it. The `afterCommit()` callbacks of a failed run are dropped. An error after the commit (eg. of an `afterCommit()` callback) never runs it again. `DatabaseTransaction.isConcurrencyError(error)` tells which errors count: Postgres SQLSTATE `40001` and `40P01`, MySQL and MariaDB error `1213`, `1205`, `1020` and SQLSTATE `40001`, SQLite `SQLITE_BUSY` and `SQLITE_LOCKED`.
- New: `QueryBuilder.beginTransaction()` begins a transaction that stays open until `commit()` or `rollBack()`. It gives a `DatabaseTransaction`. Only code inside `tx.run(callback)` uses it, so queries of other requests never join it. Nested `transaction()` calls (savepoints) and `afterCommit()` work inside `run()`. `rollBack()` does nothing on a closed transaction, so it is safe in a `finally`. Limits:
  - It holds one connection until it is closed. A transaction that is still open after `timeout` (default 1 minute) is rolled back, so a forgotten one gives its connection back.
  - On SQLite, other queries of the isolate wait until it is closed.
  - It can not begin inside a transaction of the same connection: it throws a `StateError`.
  - Use it only in the code that began it (the same request, job or test).
  - After the timeout, `run()` and `commit()` throw a `StateError` and the work is lost. On SQLite, a query or a `QueryBuilder.transaction()` outside `run()` waits until the manual transaction ends or times out.
  - Postgres: after a database error inside `run()`, call `rollBack()`. A `commit()` then saves nothing and gives no error, because the server answers COMMIT with ROLLBACK. `QueryBuilder.transaction()` with a caught database error inside does the same.
- New: `DBDriver.hasOpenTransaction` is true inside a transaction of that driver (connection). `DBDriver.inTransaction` is true for a transaction of any driver. `SchemaGrammar` has `compileIndexListing()`, `compileDisableForeignKeyConstraints()` and `compileEnableForeignKeyConstraints()` for the new `Schema` methods. A grammar of your own still builds: they throw an `UnsupportedError` until you add them. Limit: a wrapper `DBDriver` that hands `transaction()` to another driver and does not use the `afterCommitZone()` helper always gives `hasOpenTransaction == false`. So there the MySQL and Postgres foreign key methods throw a `StateError`, and `beginTransaction()` has no guard against nesting.

- New: `QueryBuilder.afterCommit(callback)` runs a callback after the transaction commits, like Laravel `DB::afterCommit`. Use it for work that must only happen when the data is saved, like a mail or a queue job. Outside a transaction it runs at once. Inside a transaction it waits for the outermost transaction of that connection to commit. A rollback drops it. A nested transaction that rolls back drops the callbacks it added, even when the outer one commits. Callbacks run in the order they were added, after the COMMIT, and the transaction call waits for them (async ones too). A callback that throws does not undo the commit: the other callbacks still run, then the transaction call throws the first error. `connection:` picks a named connection. `DBDriver.afterCommit(callback)` does the same on a driver. Code that does not use it works as before. Limits:
  - A late call from code that outlived its transaction (a `Timer`, a future that was not awaited) runs at once when that transaction committed, and is dropped when it rolled back. It never joins a later transaction.
  - A custom `DBDriver` that does not use the new `afterCommitZone()` and `runAfterCommit()` helpers runs the callbacks at once.
  - A transaction opened with the default connection's own name (eg. `connection: 'main'`) uses a different driver than no name. So `afterCommit()` with no name runs at once there. Pass the same `connection:` to both, or no name to both.
- New: `OrmFlags` turns on ORM behaviors that work like Laravel. Each flag is off by default, so nothing changes until you turn it on. Pass it as `flags:` to `DatabaseConfig` (or `SqlQueryBuilder.initialize`). `OrmFlags.all()` turns on every flag. The ORM keeps it in `SqlQueryBuilder().flags`, one per isolate. The flags:
  - `skipCleanUpdateEvents`: `save()` on a model with no changes fires `saving` and `saved`, but not `updating` and `updated`. A model with a `Map` or `List` field always counts as changed, because the field can be changed in place.
  - `belongsToKeyFromRelation`: the default foreign key of a `belongsTo` relation comes from the relation name and the owner primary key (`author` gives `author_id`), not from the class name. `belongsTo()` takes a new `relation:` name for this. The model generator does not pass it yet, so a generated model still uses the class name.
  - `pluralTableNames`: the default table name is plural: `User` uses `users`, `BlogPost` uses `blog_posts`. It uses the same English plural rules as Laravel `Str::plural` (ported from Doctrine Inflector), on the last word of the name. A table name set with `@DoxModel(table: ...)` does not change. The default foreign key stays singular (`user_id`).
  - `createWritesNull`: `create()` writes NULL for a key that is null in its data. A key that is not in the data still uses the column default.
  - `sumReturnsZero`: `sum()` gives 0 when no row matches, not null.
  - `selectRawAdds`: `selectRaw()` adds to the select list, so `select('a').selectRaw('count(*) c')` selects both.
  - `groupByAdds`: a second `groupBy()` or `groupByRaw()` adds to the first.
  - `lastPageAtLeastOne`: `paginate()` gives `lastPage` 1 when there are no rows, not 0.
  - `laravelPostgresTypes`: on Postgres, a new table made with `Schema.create` gets `TIMESTAMP` for `timestamps()` and `softDeletes()`, and `JSON` for `json()`, not `TIMESTAMPTZ` and `JSONB`. `Schema.table` and tables that are already there do not change. MySQL and SQLite do not change. `Schema` and `Table` take `flags` too.
- New: SQLite can run its queries in a helper isolate. Turn it on with `extra: {'background': true}` in the SQLite `ConnectionConfig`. It is off by default, and with it off nothing changes. SQLite is synchronous, so today one slow query stops every request on the same isolate. With the option on, a helper isolate opens the database and runs every query, and the request isolate only waits with `await`, so it keeps serving other requests. Queries, transactions, `:memory:` databases, the query listener and the slow query log work as before, and a SQL error is the same `SqliteException`. The cost: each query is one message to the helper isolate and one back. It helps when some queries are slow and one isolate serves many requests. It does not help an app that runs many tiny queries: they get a little slower. After `close()`, or when the helper isolate stops, a waiting query gets a `StateError`. A database that does not open (eg. a wrong folder) does not throw at startup: the error comes on the first query. `DATABASE_URL` can turn it on too, eg. `sqlite://db/dox.sqlite?background=true`: the SQLite url now keeps its options in `extra`, like the Postgres and MySQL urls. `background` takes `true`, `1`, `'true'` and `'1'`. An option with a wrong type, like `?busyTimeout=abc`, now fails when the database opens. Before, the SQLite url dropped all its options.
- New: `SqlQueryBuilder().listen(listener)` runs your function after each query, like Laravel `DB::listen`. The `QueryEvent` has the `sql`, the `bindings` (values named in `logRedact` show as `***`), the `time` the query took and the `connection` name. It works on every driver and in a transaction. It also gets the queries of `Schema`, `truncate()` and the migrator, when they run on a connection of the ORM. A migrator that opens its own database from `.env` has no connection name, so its queries are not sent. `Schema` and the migrator use the new `SqlQueryBuilder().queryOn(driver, sql)` and `executeOn(driver, sql)` for this. App code does not need them. With `debug` on, `truncate()` on SQLite now also prints its two `sqlite_sequence` queries. A failed query is not sent: its error goes to your code, as before. An error in a listener is logged, the query does not fail. `removeListener(listener)` stops it. With no listener the query does not measure its time.
- New: `slowQueryMs` in `ConnectionConfig` logs each query that takes longer than this many milliseconds. It is off (null) by default and works with `debug` off. The line goes to the query printer, with the time, the connection and the SQL. Values named in `logRedact` show as `***`. `0` logs every query. A failed query is not logged here. With `debug` on, a slow query of the query builder shows twice: the debug line before it runs, and the slow line with its time after it.
- New: `toJson()` of a model read by a `@ManyToMany` relation now has a `pivot` key with the pivot values (the two keys, the `withPivot` columns and the timestamps), like Laravel. So `withPivot` values reach an API answer. Dates are ISO text. Other models have no `pivot` key, as before. Put `'pivot'` in `hidden` to leave it out. A model with its own `pivot` column keeps its column value in that key.
- New: a column name can read a value inside a json column with `->`, like Laravel: `where('meta->lang', 'en')`, `meta->a->b` for a nested key, `select('meta->lang as lang')`, `orderBy('meta->lang')`, and every `where*` method, join and groupBy that takes a column. SQLite uses `json_extract()`, MySQL and MariaDB use `json_unquote(json_extract())`, Postgres uses `->` and `->>` (the column is cast to `jsonb`, so `json`, `jsonb` and `text` columns work). A key can have letters, digits and `_` only, else it throws an `ArgumentError`, so a key can never add SQL. In `where()`, a number or a bool value works on every database: Postgres compares it as `jsonb`, and MySQL compares a bool with the text `true` or `false`. Other methods compare the text of the value on Postgres. Names without `->` give the same SQL as before.
- New: `join()`, `leftJoin()` and `rightJoin()` take a callback in place of the columns, for a join with many conditions, like Laravel: `join('contact', (JoinClause j) { j.on('contact.user_id', 'user.id').orOn(...).where('contact.active', true); })`. `JoinClause` has `on()`, `orOn()`, `where()` and `orWhere()`. The `where()` values are bound. A callback with no condition throws an `ArgumentError`. The old forms work as before.
- New: `crossJoin(table)` adds a `CROSS JOIN`.
- New: `orderByDesc(column)`, and `reorder([column, direction])` to remove the order of a query (and set a new one).
- New: `skip(n)` is the same as `offset(n)`. `forPage(page, [perPage = 15])` sets the limit and offset of a page.
- New: `sole()` gives the only row of a query. It throws a `ModelNotFoundException` when no row matches, and the new `MultipleRecordsFoundException` when more than one row matches.
- New: `updateOrInsert(where, [values])` updates the rows that match `where`, or inserts one row from `where` and `values`, like Laravel. It returns a bool. An empty `where` throws an `ArgumentError`.
- New: `whereAny(columns, ...)`, `orWhereAny(...)`, `whereAll(columns, ...)` and `orWhereAll(...)` put one `where()` for each column in one bracket, joined by OR (any) or AND (all).
- New: `selectRaw(sql, params)` takes values for `@name` in the sql, like `whereRaw()`. The values are only sent when the query uses the select, so `count()` and `hasRows()` still work on Postgres. It works with `OrmFlags.selectRawAdds` on and off. Use unique names: a name that the query uses in another place (eg. in `whereRaw()`) throws an `ArgumentError` when the query runs.
- New: a column with `->` in `insert()`, `update()`, `upsert()`, `insertOrIgnore()`, `increment()` or `decrement()` still throws `ArgumentError: is not a plain column name`. A json path can be read, not written.
- Note: the new methods `skip`, `sole`, `reorder`, `forPage`, `orderByDesc`, `updateOrInsert`, `whereAny`, `orWhereAny`, `whereAll`, `orWhereAll` and `crossJoin` are members of every model, like `limit` or `first`. A model with a field of one of these names does not compile: rename the field (eg. `skip` to `skipCount`), the same as for the other query methods.
- Fix: SQLite: a plain query that starts in the same event-loop turn as a transaction could run inside that transaction. So when the transaction rolled back, the plain query was undone too. Now the plain query waits for the transaction to end, as it should. This was true with and without `background`.
- Fix: `restore()` is now on the query builder too, so `Blog().where('status', 'old').restore()` compiles without a cast to the model. It restores the soft deleted rows of the query, like Laravel. `blog.restore()` works as before. On a query with no soft deletes, like `QueryBuilder.table()`, it throws a `StateError`.
- Fix: `insertGetId()` on a model now drops the keys that `fillable` and `guarded` do not allow before it looks for the id. Before, when the database gave no id back (MySQL with no auto increment), it gave back the id from your data, even when `fillable` had dropped it and it was never inserted.

## 3.1.0

- Fix: `findOrFail()` and `firstOrFail()` with no row now answer 404 in a Dox app, like Laravel. Before, the `ModelNotFoundException` was a plain `Exception`, so Dox answered 500 and logged it as a server error. Now it extends `IHttpException` (from dox_annotation) with code 404. The body is `{"code": "not_found", "message": "Not Found"}`, the same as other 404 answers. The table, column and id are not sent to the client. The class name, the `table`, `id` and `column` fields, `toString()` and `on ModelNotFoundException catch` stay the same. The constructor is no longer `const`, because `IHttpException` has fields that can change.
- New: `first()` is the same as `getFirst()`, and `doesntExist()` is the same as `hasNoRows()`, like Laravel. There is no `exists()` or `value()`: a model already has the getter `exists`, and `value` is a common column name. Use `hasRows()` and `valueOf()`.
- New: `unless(condition, callback)` runs the callback when the condition is false. `whenValue(value, (q, value) {...})` runs the callback with the value when it is not null, like Laravel's `when($value, fn)`. `when()` works as before.
- New: `whereNot('status', 'draft')` and `orWhereNot(...)` also take a column and a value, like `where()`. The callback form works as before. Give the callback arg its type (`(QueryBuilder<Blog> q) {...}`), or it is `dynamic`.
- New: `toRawSql()` gives the SQL with each value quoted for the database, like `status = 'it''s'`. It is for logs and debugging. `toSql()` works as before.
- New: `insertGetId(data)` inserts one row and returns its new id. `insertMany(rows)` inserts many rows, reads nothing back and returns true. It works on a table with no `id` column, like a pivot table. On a model, both drop the keys that `fillable` and `guarded` do not allow. `insert()` and `delete()` work as before.
- New: schema helpers `foreignIdFor(User())`, `ulid()`, `foreignUlid()`, `year()`, `ipAddress()`, `softDeletesTz()`, `nullableMorphs()`, `uuidMorphs()`, `dropTimestamps()`, `dropSoftDeletes()`, `dropConstrainedForeignId()`, `dropPrimary()`, `renameIndex()`, `fullText()`, and `nullOnUpdate()` and `restrictOnUpdate()` on a foreign key. SQLite has no full text index and can not drop a primary key, so these throw an `UnsupportedError` there. `renameIndex()` on SQLite makes the index again with the new name.
- Fix: `save()` now keeps an `updated_at` that you set on the model, like Laravel. Before, it always set the time to now.
- Fix: `blog.update({...})` on a model from the table now sets the `updatedAt` field when the map has a time for a custom `updated_at` column. Before, only the database row got it.
- Fix: `logRedact` of a named connection is now used for its queries. Before, only the default connection's `logRedact` was read, so a value could show in the log. The default list still counts for every connection.
- Fix: `find()` on a `union()` query, and `find(5, null)`, now fail in the returned Future, like `findOrFail()`. Before, they threw before the Future. `await` catches both, as before.
- Fix: with only `guarded` set and no `tableColumns` (a hand-written model), a key with a char that is not ASCII is now dropped. MySQL folds the case of more chars than Dart, so a key like `'İS_ADMIN'` could set `is_admin`.
- Fix: many to many `sync()` and `toggle()` now count pivot rows, not ids, to check the delete. Two pivot rows of one id no longer make it read the rows again, and can no longer hide a row that was not deleted.
- Fix (security): `guarded` could be skipped with a changed key. A key like `' is_admin'`, `'is_admin\t'`, `'IS_ADMIN'` or `'users.is_admin'` set the guarded `is_admin` column, because the SQL builder trims the name and SQLite and MySQL match names without case. This was true for a query `update()`, `update()` on a loaded model, `upsert()`, `insertOrIgnore()` and `insertMultiple()`. Now `guarded` compares the trimmed, lower case name without a table prefix. With only `guarded` set, a key must also be one of the model columns (`tableColumns`), like Laravel. A `fillable` key must still match the name exactly.
- Fix: `fromSub()` on a model now uses the alias. Before, the soft delete check and the `chunk()` order used the model table, like `blog.deleted_at`, so `Blog().fromSub(sub, 'b').get()` failed with `no such column: blog.deleted_at`. Now they use `b.deleted_at` and `b.uid`. `update()`, `delete()` and `restore()` after `fromSub()` still run on the model table, as before.
- Fix: `find()`, `findOrFail()`, `firstOrNew()`, `firstOrCreate()` and `updateOrCreate()` on a `union()` query now throw a `StateError`. Before, their where went to the first part only and `LIMIT 1` to the whole union, so they could give a wrong row, and `firstOrCreate()` and `updateOrCreate()` could write the wrong row. Use `get()` on a union. `getFirst()` and `firstOrFail()` work as before.
- Fix: `pluck()`, `pluckMap()` and `valueOf()` on a `union()` query now throw a clear `StateError`. Before, only the first part got the select, so the database gave an SQL error.
- Fix: many to many `sync()` and `toggle()` now report in `detached` only the rows that the database really deleted. Before, on a column that compares text without case, with stored `'ABC'` and `'abc'`, `sync(['ABC'])` reported `detached: ['abc']`, but the database kept both rows.
- Fix: many to many `sync()` and `toggle()` now check all text ids that match a stored row only by case in one query for each 100 ids. Before, they ran one query for each id.
- Fix: `restore()` now sets `updated_at` too, like Laravel, when the model has timestamps. It uses a custom `updated_at` column, and sets nothing when the model has no timestamps. This is true for `blog.restore()` (it also sets the `updatedAt` field) and for a query like `Blog().where('id', 1).restore()`.
- Fix: `blog.update({...})` on a model from the table now sets the `updatedAt` field when the model has a custom `updated_at` column. Before, only the database row got the new time.
- Fix: `foreignId('x')` now keeps `constrained()` and `references()` after every column modifier, like Laravel. Before, `foreignId('user_id').unique().constrained()` (and the same after `defaultTo()`, `change()`, `primary()` and others) did not compile.
- Fix: `forceFill()` now throws an `ArgumentError` when it can not set a column: a value of the wrong type, or a model with no `setColumnValue()` (a hand-written model, or one made by an old dox_builder). Before, it skipped them with no error, so nothing was set. An ISO date text now sets a `DateTime` field. A key that is not a column is still skipped.
- Fix: a soft delete now sets `updated_at` too, like Laravel, when the model has timestamps. This is true for `blog.delete()` and for a query like `Blog().where('id', 1).delete()`. `blog.delete()` now also sets the `deletedAt` and `updatedAt` fields of the model, and `blog.restore()` sets `deletedAt` back to null. Before, the fields kept their old values.
- Fix: `find(5, null)` and `findOrFail(5, null)` now throw an `ArgumentError` that says the first arg must be a column name. Before, they threw a type error with no clear message. `find(5)` and `find('email', null)` work as before.
- Fix: `restore()` on a query now only changes soft deleted rows (`deleted_at IS NOT NULL`). Before, it returned true when any row matched, even a row that was not deleted, on Postgres and SQLite. MySQL counts only changed rows, so it gave false. Now all databases give the same answer.
- Fix: `cursorPaginate()` now adds the primary key as the last order column when you order by a column of another table with the same name, like `orderBy('author.id')` on a join. Before, it only compared the last part of the name, so it skipped the key and rows with the same value could be skipped. Also, a null in the first row of a page no longer makes a good cursor give page 1 (a client looped on page 1). The order columns must still have no nulls: the page now throws the clear `StateError` of a null cursor value.
- Fix: many to many writes now see ids with the same text (`'1'` and `1`) as one id. Before, on a text key, `toggle(['1', 1])` removed both `'1'` and `'01'`. The `attached`, `detached` and `updated` lists also list an id once now. Before, two stored rows of one id gave `detached: [1, 1]`.
- Fix: many to many `sync()` and `toggle()` on a text key no longer lose links when the column compares text without case (MySQL and MariaDB by default, SQLite `COLLATE NOCASE`). Before, with a stored `'ABC'`, `sync(['abc'])` added `'abc'` and then deleted `'ABC'`, and the database deleted both rows. Now an id that the database sees as a stored row keeps that row (`sync`) or removes it (`toggle`), and the delete never removes a row that the database sees as a kept id. The same is true for a UUID in the other case and for an end space on MariaDB.
- New: `forceCreate()`, `forceUpdate()` and `forceFill()` ignore `fillable` and `guarded`, like Laravel. `User().where('id', 1).forceUpdate({'is_admin': true})` sets a guarded column. `forceFill()` sets the fields of a model and does not save. Do not pass user input to them.
- New: `Model.unguarded(() async { ... })` turns `fillable` and `guarded` off for every write inside the callback, like Laravel's `Model::unguarded()`. It uses a zone, so other requests that run at the same time still use `fillable`. `Model.isUnguarded` tells if the check is off.
- Note: a query `update()` on a model still drops the keys that `fillable` does not allow. Laravel's query update does not. Dox keeps the check, so `User().where('id', 1).update(req.body)` stays safe. Use `forceUpdate()` for the Laravel behaviour.
- Fix: `blog.update({...})` on a model from the table now sets `updated_at` (and the `updatedAt` field), like Laravel, when the model has timestamps and the map has no value for it.
- Fix: `limit()` and `take()` with a negative number are now ignored, like Laravel. Before, `limit(-1)` sent `LIMIT -1`, which is an error on Postgres.
- Fix: `having('x', '!=', null)` now builds `x IS NOT NULL`, and `having('x', '=', null)` builds `x IS NULL`, like `where()`. Before, a null third arg was read as no arg, so it built `x = '!='`.
- Fix: `restore()` on a query, like `Blog().withTrash().where('status', 'old').restore()`, now restores every soft deleted row of the query, like Laravel. It fires no events and returns true when it changed a row. Before, it ran `WHERE id IS NULL`, changed nothing and returned true. With no `where()` it throws a `StateError`, like `delete()`, so it can not restore every row by mistake. `restore()` on a loaded model works as before.
- Fix: `find('email', null)` and `findOrFail('email', null)` now find the row where `email IS NULL`. Before, a null second arg meant "id only", so it searched `id = 'email'`. `find(5)` works as before.
- Docs: the `select()` comment said a second call adds columns. It replaces them, like Laravel. Only the comment changed.
- Fix: a model write with no primary key value and no `where()` no longer changes every row. Before, `Blog().delete()`, `Blog().update({...})`, `Blog().forceDelete()`, `Blog().increment('views')` or `decrement()`, or the same call on a model read without its key (like after `select('title')`), ran with no `WHERE`, so it deleted or changed every row of the table. Now these throw a `StateError` and run no query, like `touch()`. A `where()`, `onlyTrashed()` or a global scope that adds a condition picks the rows, like Laravel, so these work as before. To write every row on purpose, use `Blog().whereRaw('1 = 1').delete()` (or `.update()`). It keeps soft deletes and global scopes. Do not use `QueryBuilder.table()` for this on a model table: it skips soft deletes (it really deletes the rows), global scopes and `fillable`.
- Fix: `blog.update({...})` on a model from the table now changes only that row, like Laravel, and sets the fields to the new values. Before, it ran with no `WHERE` and changed every row of the table. It runs one query and fires no model events.
- New: `onlyTrashed()` gives only the soft deleted rows, like Laravel. `Blog().onlyTrashed().forceDelete()` deletes only the soft deleted rows. On a model without soft deletes (or a `QueryBuilder.table()` query) it throws a `StateError`, so it can never delete every row.
- New: `withAvg()`, `withMin()` and `withExists()`, next to `withCount()`, `withSum()` and `withMax()`. `withExists('posts')` adds `posts_exists`, a `bool`.
- New: `simplePaginate()` gives a page without the total count, so it runs one query. It returns a `SimplePagination` with `hasMorePages`. Its JSON has `per_page`, `current_page`, `from`, `to`, `has_more_pages` and `data`.
- New: `cursorPaginate()` gives a page after a cursor, like Laravel. It uses `WHERE (a > x) OR (a = x AND b > y)`, not `OFFSET`. It orders by all the `orderBy()` columns (asc and desc can be mixed), or by `column` and `direction` when there is no `orderBy()`, or by the primary key. The primary key is added last when it is not in the order, so rows with the same values are never skipped. It returns a `CursorPagination` with `nextCursor` and `prevCursor`. Its JSON has `per_page`, `next_cursor`, `prev_cursor` and `data`. The cursor is safe to take from a user: the columns and the order come from the code, and its values are only sent as query values. A cursor that is not valid gives the first page: bad base64 or JSON, made for other columns, or a value of the wrong kind for its column (a text for a number column, for example). A Postgres "data exception" from a cursor value also gives the first page, and in a transaction it does not break the transaction. `orderByRaw()` and `inRandomOrder()` throw a `StateError`.
- New: `touch()` sets `updated_at` (or a given column) to now. On a model from the table it changes only that row, and it fires `saving`, `updating`, `updated` and `saved`, like Laravel. `touchQuietly()` does the same with no events. On a query it changes every row of the query and fires no events. On a model with no primary key value (never saved) and no `where()`, it throws a `StateError`, so it can not change every row by mistake.
- New: `replicate()` makes a new, unsaved copy of a model, without the primary key, `created_at` and `updated_at`. `replicate(['slug'])` leaves out more columns. Like Laravel, it copies `deleted_at`.
- New: `union()` and `unionAll()`, like Laravel. `orderBy()`, `limit()` and `offset()` of the main query sort and cut the whole result. Each part can have its own `orderBy()` and `limit()`. `count()`, `paginate()`, `sum()`, `avg()`, `min()` and `max()` use the whole result, like Laravel. `sum()` and the other aggregates keep `orderBy()`, `limit()` and `offset()`. `count()` does not. `cursorPaginate()` and `chunkById()` throw a `StateError` on a union or a `fromSub()` query. Use `paginate()`, `simplePaginate()` or `chunk()` there. `update()`, `delete()`, `forceDelete()`, `increment()`, `decrement()`, `touch()` and `all()` throw a `StateError` on a union query, because they would use only the first query. Use `get()` to read it.
- New: sub queries. `whereIn()`, `whereNotIn()` and their `or` forms take a query or any `Iterable` (like a `Set`), like `whereIn('id', QueryBuilder.table('post').select('user_id'))`. `joinSub()` and `leftJoinSub()` join the rows of a query. `fromSub(query, alias)` selects from the rows of a query. The values of the sub query are bound, never put in the SQL text. A sub query is built when it is added, so a later change to it is not used. MySQL and MariaDB do not allow `LIMIT` in `IN (sub query)`.
- New: `whereDate()`, `whereTime()`, `whereYear()`, `whereMonth()` and `whereDay()`, each with an `or` form and an optional operator, like `whereDate('created_at', '>=', '2024-05-01')`. They take a `DateTime` too. A `DateTime` is read in UTC on SQLite and Postgres, like the drivers bind it, and as the wall clock on MySQL and MariaDB. A Postgres connection with another session `timeZone` reads a `timestamptz` in that zone, so a `DateTime` value does not match there. MySQL and MariaDB use `DATE(col)` and `TIME(col)`, like Laravel. On Postgres, a column with fractions of a second does not equal a time without them.
- New: `whereJsonContains()` and `whereJsonDoesntContain()`, each with an `or` form. `column->key` reads a key inside the json. It is `@>` on Postgres, `JSON_CONTAINS()` on MySQL and MariaDB, and `json_each()` on SQLite (strings, numbers, bools and lists of them only). Like Laravel, `whereJsonDoesntContain()` on a row without the key differs per database. On SQLite, `true`, `1` and `1.0` match each other.
- New: `insertOrIgnore(rows)` inserts rows and skips the ones that clash with a unique key. It returns how many rows were inserted. It is `ON CONFLICT DO NOTHING` on Postgres, `INSERT OR IGNORE` on SQLite and `INSERT IGNORE` on MySQL and MariaDB. The model form drops keys that `fillable` and `guarded` do not allow.
- New: the ORM is now the `PresenceVerifier` of `dox_validation`. So `v.string().exists('teams')` and `v.string().unique('users')` in fluent schemas read the database. It is set when the driver is set. An app that set its own verifier keeps it. This needs the next `dox_validation`.
- Fix: `@Unique` now trusts the database match. Before, it also compared the text in Dart. MySQL and MariaDB ignore case, so `TAKEN@dox.dev` passed `@Unique` when `taken@dox.dev` was in the table. One `@Exists` value does not change: it still needs its exact text, as before, so `'01'` or `'1abc'` do not pass for the id `1`. On a `List` field the whole list is one query: an `@Exists` item passes only when its exact text is found, and a `@Unique` item fails when a found row has its exact text, as in 3.0.1. When a found row matches no item by its text (MySQL case or trailing space), one query can not tell which item it was, so every item fails (the safe side). Before, those lists passed. A dotted column like `t.name` works too. Limit long lists with `@MaxItems`.
- Fix: a nested transaction that fails now releases its savepoint after `ROLLBACK TO SAVEPOINT`. Before, every caught error left one savepoint open until the outer transaction ended.
- Fix: on Postgres, `@Unique` and `@Exists` with a value that does not fit the column no longer throw a database error (a 500). This is every Postgres "data exception" (SQLSTATE class 22), like `abc` for a number id, a number that is too big, text with a NUL byte, or a bad date for a `date` column. The value is "not found". When the bad value is the ignore value (`ignoreParam` from the URL, like `/users/abc`), no row can have it, so the ignore part is dropped and the value is still checked. A list with such a value fails every item, because one bad value fails the whole query. Other database errors still throw. On Postgres inside a transaction the lookup runs in a savepoint, so a caught error does not break the transaction.
- New: many to many writes, like Laravel. `attach()`, `detach()`, `sync()`, `syncWithoutDetaching()`, `toggle()` and `updateExistingPivot()` change the pivot rows of a `@ManyToMany` relation, like `await artist.sync('songs', [1, 2])`. `sync()` and `toggle()` return a `PivotSyncResult` with the `attached`, `detached` and `updated` ids. The ids can be ids, models, a list, or a map of `id => extra pivot values`. `null` or `[]` means no ids, so `sync(null)` detaches all and `detach('songs', null)` detaches nothing. Only `detach('songs')` with no ids detaches all. Every write matches ids with one rule. Two texts only match by the exact text, so `'007'` and `'7'` are two ids. When one id is a number (`int` or `double`), Dart reads the other one as a number: it trims it, drops a `.0` end and tries `int.tryParse` (`' 1'`, `'+1'`, `'01'`, `'1.0'`), then `double.tryParse` (`'1.'`, `'1e0'`). They match when the two numbers are the same. This keeps the rows of a number key column, which come back as numbers: `sync(['01'])` keeps the row of `1`. It is only how Dart matches ids. The databases read some texts in other ways, so a text id that is sent to the database can find another row or throw, as in `where()`. For example, `'0x1'` is 1 in Dart and on Postgres, 0 on MariaDB, and an error on MySQL. Postgres throws for `'1.0'`, `'1.'` and `'1e0'` on an integer column. A given text that only reads as a number at or past ±2^53 (like `'1e20'` or `'9007199254740993.'`) is not exact, so it throws an `ArgumentError` when it is matched to a number. A stored value never throws: one that can not be read exactly does not match a number, so a long digit text in a text key column does not stop `sync()`. `sync()` checks every id before its first write. The ORM does not know the type of the key column, so `attach(['1', '01'])` gives two rows. Each id finds its own stored row when it can, and a row with the same text wins (on a text key, `1` finds `'1'`, not `'01'`). A stored row is matched once, so on a number key `toggle(['1', '01'])` detaches the row of `1` once. `detach()` and `updateExistingPivot()` send every given id, so on a text key `detach([1, '01'])` deletes both rows. `sync()` deletes a stored row only when none of the given ids matches it, so on a text key `sync([1, '01'])` keeps the rows `'1'` and `'01'`. A new row is added once for ids that are the same by this rule, so on a number key `attach([1, '01'])` gives one row, and on a text key it gives only the row `1` (the first id wins). A whole double within ±2^53 like `2.0` is sent to the database as `2`. Any other double (`1.5`, NaN, infinity, `1e20`) throws an `ArgumentError`. Text ids are sent as they are. A bool id is `1` or `0`, like the databases read it. A `BigInt` id is an `int` when it fits, else it throws an `ArgumentError`. Any other type that is not an `int`, a `String`, a `bool`, a `double` or a model throws an `ArgumentError` before any query. The result lists show an id as an `int` when it is a number or the plain text of an int (`'4'`), so `'007'` stays text. `attach()`, `detach()`, `toggle()`, `syncWithoutDetaching()` and `updateExistingPivot()` skip a null id or a model that is not saved. `sync()` throws an `ArgumentError` for one, before any query, so a missing id can not delete every link. `sync()` and `toggle()` insert before they delete, so a failed insert keeps the old links.
- Note: the new many to many methods (`attach`, `detach`, `sync`, `syncWithoutDetaching`, `toggle`, `updateExistingPivot` and the `pivot` getter) are on every model. A `@Scope()` with one of these names is now hidden when you call it right on a model, like `Song().sync()`. Dart picks the new method, so the call runs the wrong code or does not compile. After another query method, like `Song().where(...).sync()`, the scope still runs. To fix: rename the scope.
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
