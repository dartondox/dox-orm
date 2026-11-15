## Unreleased

- Faster writes. `add`, taking a lock, `increment`, `pull` and `touch` now run one statement on Postgres and SQLite (it was 2 to 6). On MySQL and MariaDB, `add`, taking a lock and `touch` run one statement, and `increment` runs 4 (it was 6). The results stay the same, also for expired rows.
- The SQL text is built once per store and database type, not on every call.
- An `increment` past the 64-bit int limit is now an error on every database, and the stored value does not change. On SQLite it used to wrap around without an error.
- New opt-in lazy prune: set `pruneInterval` (store option `prune_interval`, in seconds). A write then starts `prune()` at most once per that time, not awaited and outside app transactions. It is off by default. `DatabaseCacheDriver.defaultPruneInterval` is one hour.
- `CacheTables.up` now makes an index on `expires_at`, so `prune()` reads only the expired rows. An old table keeps working without it. To add it, write a migration with `schema.table('cache', (Table t) => t.index('expires_at'))`.

## 3.2.1

No changes.

## 3.2.0

- First version. `DatabaseCacheDriver` is a dox_cache store that keeps cache items, locks and sessions in a database table, on SQLite, Postgres, MySQL and MariaDB. Register it with `Dox().cache.extend('database', DatabaseCacheDriverFactory(encrypter))`. Store options: `table`, `connection`, `prefix`, `encrypt`. `prune()` deletes expired rows.
- A write that fails with a deadlock runs again after a short random wait, up to `DatabaseCacheDriver.deadlockTries` (5) runs in all. A lock wait timeout is not retried, and inside an app transaction on the same connection there is no retry. `DatabaseCacheDriver.isDeadlock(error)` tells if an error is a deadlock.
- The `database:` constructor parameter takes a `DBDriver` to use instead of the one of `connection`.
- `CacheTables.up(schema)` and `CacheTables.down(schema)` make and drop the table. `dox cache:table` writes a migration that uses them.
