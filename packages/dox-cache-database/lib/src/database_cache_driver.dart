import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dox_cache/dox_cache.dart';
import 'package:dox_orm/dox_orm.dart';

/// Keeps cache items in a database table, so all servers that use the
/// same database share the cache, the locks and the sessions. It works on
/// SQLite, Postgres and MySQL (also MariaDB) through the dox_orm
/// connection.
///
/// The table (default `cache`, made by [CacheTables]) has these columns:
/// - `key`: string(255), the primary key. It is [prefix] + the key.
///   On MySQL it uses the `utf8mb4_bin` collation, so `A` and `a` are
///   two keys.
/// - `value`: text (longText on MySQL), the value as JSON text. On
///   MySQL it uses `utf8mb4_bin` too, so lock owners compare by case.
/// - `expires_at`: bigint, nullable. Unix time in milliseconds (UTC).
///   Null means it never expires.
///
/// An expired row reads as a miss. It stays in the table until the key is
/// written again, or [prune] deletes it. Run [prune] from time to time,
/// eg. in a schedule, or set [pruneInterval].
///
/// Locks are rows in the same table: the key is [prefix] + `lock:` +
/// name, the value is the owner token.
///
/// - `add` and lock `get` run one upsert. It inserts the row, or replaces
///   it only when it is expired. The database runs it as one atomic step,
///   so two servers never both win.
/// - `increment` runs one upsert that adds to the value and returns it
///   (`RETURNING`). On MySQL and MariaDB it is the upsert and a SELECT in
///   one transaction: the upsert locks the row until the end.
/// - `pull` runs one `DELETE ... RETURNING`. `touch` runs one UPDATE (on
///   MySQL and MariaDB a SELECT too, when the UPDATE changed nothing).
/// - On MySQL and MariaDB, `pull` reads the key, then locks the row in a
///   transaction (`FOR UPDATE`), reads it again and deletes it.
/// - SQLite older than 3.35 has no `RETURNING`: there `increment` and
///   `pull` lock the row in a transaction (SQLite runs one write
///   transaction at a time).
/// - A lock release deletes the row only when the owner matches, in one
///   statement.
///
/// A full key ([prefix] + key, also for locks) may have at most 255
/// characters, the size of the `key` column. A longer key throws an
/// [ArgumentError] on every database.
///
/// Times come from the [CacheClock] of this server, not the database.
/// Keep the clocks of the servers in sync. When two clocks differ, a key
/// or a lock can end early by that difference.
///
/// Cache calls inside an app transaction on the same connection join
/// that transaction: their writes roll back with it, a lock is not seen
/// by other servers until the commit, and the row locks of the writes
/// stay until the end. On Postgres a failed cache
/// query also breaks the app transaction. Give the cache store its own
/// [connection] name (with the same database settings) to keep it out
/// of app transactions. On SQLite, a second connection waits for the
/// write transaction of the first one.
///
/// Reads go to the write database, also with read replicas, so a read
/// sees the last write.
///
/// A write that fails with a deadlock runs again, up to [deadlockTries]
/// times in all, after a short random wait. A deadlock is MySQL and
/// MariaDB error 1213 (SQLSTATE 40001), and Postgres SQLSTATE 40P01 or
/// 40001. A lock wait timeout (MySQL 1205) is not retried: each wait can
/// take long. Inside an app transaction on the same connection there is
/// no retry: the deadlock rolled back the app transaction, so the error
/// goes to the caller at once.
///
/// With an [encrypter], every value is encrypted before it is written.
/// A plain `int` stays plain JSON text, the same as the Redis driver.
/// A value that can not be decrypted reads as a miss.
class DatabaseCacheDriver extends CacheDriver {
  /// A [prefix] that does not end with `:` gets one, so `flush` of the
  /// prefix `app` never deletes the keys of `app2`.
  DatabaseCacheDriver({
    this.connection,
    this.table = defaultTable,
    String prefix = CacheConstants.defaultPrefix,
    this._clock = const CacheClock(),
    this.encrypter,
    this.database,
    this.pruneInterval,
  }) : prefix = RedisDriver.withSeparator(prefix);

  /// The table when the store sets none.
  static const String defaultTable = 'cache';

  /// The driver name in the store config: `'driver': 'database'`.
  static const String driverName = 'database';

  /// Store config keys of this driver.
  static const String tableOption = 'table';
  static const String connectionOption = 'connection';

  /// Store config key of [pruneInterval], in seconds (an int).
  static const String pruneIntervalOption = 'prune_interval';

  /// A good [pruneInterval] for most apps.
  static const Duration defaultPruneInterval = Duration(hours: 1);

  /// The size of the `key` column, in characters.
  static const int maxKeyLength = 255;

  /// Keys per query in [many]. SQLite allows only so many values in one
  /// query.
  static const int manyChunk = 500;

  /// Tries of [increment] when the row is deleted between the insert
  /// and the transaction. Only SQLite older than 3.35 uses it.
  static const int incrementTries = 5;

  /// Runs of a write that fails with a deadlock, the first run included.
  static const int deadlockTries = 5;

  static final Random _random = Random();

  /// The dox_orm connection name. Null: the default connection.
  final String? connection;

  /// The database driver to use instead of the one of [connection].
  /// Null (the default): the driver of [connection].
  final DBDriver? database;

  /// The cache table.
  final String table;

  @override
  final String prefix;

  final CacheClock _clock;

  /// Encrypts the values. Null means plain JSON.
  final CacheEncrypter? encrypter;

  /// Run [prune] by itself at most once per this time, started by a
  /// write (`put`, `putMany`, `add`, `increment` or a lock `get`). It is
  /// not awaited, and it runs outside any app transaction. Reads never
  /// start it. Null (the default): never, call [prune] yourself.
  ///
  /// Each process (and each isolate) counts its own time. So with many
  /// servers, the table gets a prune about that many times per interval.
  /// Each prune is one DELETE that uses the `expires_at` index, so this
  /// is cheap. Make that index for an old table, see the README.
  final Duration? pruneInterval;

  /// When the last lazy prune started, in ms of the clock. Null: never.
  int? _lastPrune;

  static final RegExp _plainInt = RegExp(r'^-?\d+$');

  /// What a value of [increment] must look like in the database: a plain
  /// int. Postgres and MySQL check it with a regex.
  static const String _intPattern = '^-?[0-9]+\$';

  /// The SQL text of each database type, built once.
  final Map<Driver, _CacheSql> _sqlByDriver = <Driver, _CacheSql>{};

  _CacheSql _sql(DBDriver db) {
    Driver type = db.getName();
    return _sqlByDriver[type] ??= _CacheSql(type, table, prefix);
  }

  /// The driver of [connection]. With read replicas, the write database.
  DBDriver get _db {
    DBDriver db = database ?? SqlQueryBuilder().getDBDriver(connection);
    return db is ReplicaDriver ? db.writer : db;
  }

  /// [prefix] + [key]. Throws an [ArgumentError] when it is longer than
  /// the `key` column. MySQL without strict mode would cut it, so two
  /// long keys would share one row.
  String _key(String key) {
    String full = prefix + key;
    if (full.runes.length > maxKeyLength) {
      throw ArgumentError.value(
        key,
        'key',
        'Cache key with prefix is longer than $maxKeyLength characters',
      );
    }
    return full;
  }

  /// Run [work], and run it again when it fails with a deadlock, up to
  /// [deadlockTries] runs. Inside a transaction of [db] it runs once.
  Future<R> _retry<R>(DBDriver db, Future<R> Function() work) async {
    if (db.hasOpenTransaction) return work();
    for (int run = 1; ; run++) {
      try {
        return await work();
      } catch (error) {
        if (run >= deadlockTries || !isDeadlock(error)) rethrow;
        await Future<void>.delayed(
          Duration(milliseconds: 1 + _random.nextInt(10 * run)),
        );
      }
    }
  }

  /// True when [error] is a deadlock that the database rolled back:
  /// MySQL and MariaDB error 1213 (or SQLSTATE 40001), Postgres SQLSTATE
  /// 40P01 or 40001. A lock wait timeout (MySQL 1205) is false.
  static bool isDeadlock(Object error) {
    if (error is MysqlException) {
      return error.code == 1213 ||
          (error.sqlState == '40001' && error.code != 1205);
    }
    if (error is PgServerException) {
      return error.code == '40P01' || error.code == '40001';
    }
    return false;
  }

  @override
  Future<dynamic> get(String key) async {
    return _decode(await _liveValue(_key(key)));
  }

  /// The stored JSON text. No decode.
  @override
  Future<String?> getRaw(String key) async {
    String? text = _plainText(await _liveValue(_key(key)));
    return text == null ? null : CacheDriver.liveText(text);
  }

  @override
  Future<bool> has(String key) async {
    return await getRaw(key) != null;
  }

  /// One SELECT for each [manyChunk] keys.
  @override
  Future<Map<String, dynamic>> many(List<String> keys) async {
    Map<String, dynamic> result = <String, dynamic>{};
    if (keys.isEmpty) return result;
    DBDriver db = _db;
    _CacheSql sql = _sql(db);
    List<String> fullKeys = <String>[for (String key in keys) _key(key)];
    Map<String, Object?> found = <String, Object?>{};
    for (int start = 0; start < fullKeys.length; start += manyChunk) {
      int end = start + manyChunk < fullKeys.length
          ? start + manyChunk
          : fullKeys.length;
      Map<String, dynamic> values = <String, dynamic>{'now': _clock.nowMs()};
      List<String> names = <String>[];
      for (int i = start; i < end; i++) {
        values['k$i'] = fullKeys[i];
        names.add('@k$i');
      }
      List<Map<String, dynamic>> rows = await db.query(
        '${sql.many}(${names.join(', ')}) AND ${sql.live}',
        substitutionValues: values,
      );
      for (Map<String, dynamic> row in rows) {
        found[_text(row['key'] as Object)] = row['value'];
      }
    }
    for (int i = 0; i < keys.length; i++) {
      result[keys[i]] = _decode(found[fullKeys[i]]);
    }
    return result;
  }

  /// All upserts in one transaction.
  @override
  Future<void> putMany(Map<String, Object?> values, Duration? ttl) async {
    if (values.isEmpty) return;
    DBDriver db = _db;
    await _retry(db, () {
      return db.transaction(() async {
        for (MapEntry<String, Object?> entry in values.entries) {
          await put(entry.key, entry.value, ttl);
        }
      });
    });
  }

  /// One upsert: insert the row, or replace the value and expiry time.
  @override
  Future<void> put(String key, Object? value, Duration? ttl) async {
    DBDriver db = _db;
    Map<String, dynamic> values = <String, dynamic>{
      'key': _key(key),
      'value': _encode(value),
      'expires': _expiresAt(ttl),
    };
    await _retry(db, () {
      return db.execute(_sql(db).put, substitutionValues: values);
    });
    _pruneSometimes();
  }

  @override
  Future<bool> add(String key, Object? value, Duration? ttl) async {
    return _insertIfMissing(_key(key), _encode(value), _expiresAt(ttl));
  }

  /// One upsert that adds [by] and returns the new value. A missing or
  /// expired key starts at 0 with no expiry time. A live key keeps its
  /// expiry time.
  @override
  Future<int> increment(String key, int by) async {
    DBDriver db = _db;
    String fullKey = _key(key);
    Driver type = db.getName();
    int? next;
    if (type == Driver.mysql) {
      next = await _retry(db, () => _incrementMysql(db, fullKey, by));
    } else if (db.supportsReturning) {
      next = await _retry(db, () => _incrementReturning(db, fullKey, by));
    } else {
      next = await _incrementOld(db, fullKey, by);
    }
    _pruneSometimes();
    if (next == null) throw _notInt(fullKey);
    return next;
  }

  /// Postgres needs exactly the values its query uses.
  Map<String, dynamic> _incrementValues(DBDriver db, String fullKey, int by) {
    Map<String, dynamic> values = <String, dynamic>{
      'key': fullKey,
      'by': by,
      'start': '$by',
      'now': _clock.nowMs(),
    };
    if (db.getName() == Driver.sqlite) {
      // the old values that do not go past the 64-bit limit with [by]
      values['low'] = by < 0 ? _minInt - by : _minInt;
      values['high'] = by > 0 ? _maxInt - by : _maxInt;
    } else {
      values['int'] = _intPattern;
    }
    return values;
  }

  static const int _maxInt = 0x7FFFFFFFFFFFFFFF;
  static const int _minInt = -_maxInt - 1;

  /// Postgres and SQLite 3.35+. Null when the live value is not an int.
  Future<int?> _incrementReturning(DBDriver db, String fullKey, int by) async {
    List<Map<String, dynamic>> rows = await db.query(
      _sql(db).increment,
      substitutionValues: _incrementValues(db, fullKey, by),
    );
    return rows.isEmpty
        ? null
        : int.parse(_text(rows.first['value'] as Object));
  }

  /// MySQL and MariaDB have no `RETURNING` on an upsert. The upsert locks
  /// the row until the end of the transaction, so the SELECT reads the
  /// value of this call. Null when the live value is not an int.
  Future<int?> _incrementMysql(DBDriver db, String fullKey, int by) {
    _CacheSql sql = _sql(db);
    return db.transaction(() async {
      await db.execute(
        sql.increment,
        substitutionValues: _incrementValues(db, fullKey, by),
      );
      List<Map<String, dynamic>> rows = await db.query(
        sql.valueOfKey,
        substitutionValues: <String, dynamic>{'key': fullKey},
      );
      Object? text = rows.isEmpty ? null : rows.first['value'];
      String plain = text == null ? '' : _text(text);
      return _plainInt.hasMatch(plain) ? int.parse(plain) : null;
    });
  }

  /// SQLite older than 3.35: insert the row when missing, then read and
  /// write the row in a write transaction.
  Future<int?> _incrementOld(DBDriver db, String fullKey, int by) async {
    for (int i = 0; i < incrementTries; i++) {
      await _insertIfMissing(fullKey, '0', null);
      int? next = await _retry(db, () => _incrementLocked(db, fullKey, by));
      if (next != null) return next;
    }
    throw StateError(
      'Cache increment of "${fullKey.substring(prefix.length)}" failed: '
      'the row was deleted $incrementTries times in a row',
    );
  }

  /// The value is not an int, or the sum would go past the 64-bit
  /// limit (SQLite only: Postgres and MySQL throw their own error).
  StateError _notInt(String fullKey) {
    return StateError(
      'Cache value of "${fullKey.substring(prefix.length)}" '
      'is not an integer, or the increment goes past the 64-bit limit',
    );
  }

  /// The new value of [fullKey], or null when the row is gone.
  Future<int?> _incrementLocked(DBDriver db, String fullKey, int by) {
    return db.transaction(() async {
      Map<String, dynamic>? row = await _lockedRow(db, fullKey);
      // deleted or expired since the insert: try again
      if (row == null) return null;
      String? text = _plainText(row['value']);
      Object? current = text == null ? null : jsonDecode(text);
      if (current is! int ||
          (by > 0 && current > _maxInt - by) ||
          (by < 0 && current < _minInt - by)) {
        throw _notInt(fullKey);
      }
      int value = current + by;
      await db.execute(
        _sql(db).setValue,
        substitutionValues: <String, dynamic>{
          'key': fullKey,
          'value': '$value',
        },
      );
      return value;
    });
  }

  /// Deletes the live row and gives its value, so only one caller gets
  /// it. Postgres and SQLite 3.35+: one `DELETE ... RETURNING`.
  /// MySQL: reads and deletes the locked row in a transaction. A missing
  /// key is read first with no lock: on MySQL a lock on a missing row
  /// also locks the gap around it.
  @override
  Future<dynamic> pull(String key) async {
    DBDriver db = _db;
    String fullKey = _key(key);
    if (db.getName() != Driver.mysql && db.supportsReturning) {
      List<Map<String, dynamic>> rows = await _retry(db, () {
        return db.query(
          _sql(db).pull,
          substitutionValues: <String, dynamic>{
            'key': fullKey,
            'now': _clock.nowMs(),
          },
        );
      });
      return rows.isEmpty ? null : _decode(rows.first['value']);
    }
    if (await _liveValue(fullKey) == null) return null;
    return _retry(db, () {
      return db.transaction(() async {
        Map<String, dynamic>? row = await _lockedRow(db, fullKey);
        if (row == null) return null;
        await _delete(db, fullKey);
        return _decode(row['value']);
      });
    });
  }

  /// One UPDATE of the live row. MySQL counts only changed rows, so when
  /// it counts 0 (the key is missing, or the expiry time was the same) a
  /// SELECT tells if the key is there.
  @override
  Future<bool> touch(String key, Duration? ttl) async {
    DBDriver db = _db;
    String fullKey = _key(key);
    Map<String, dynamic> values = <String, dynamic>{
      'key': fullKey,
      'expires': _expiresAt(ttl),
      'now': _clock.nowMs(),
    };
    int changed = await _retry(db, () {
      return db.affectingStatement(_sql(db).touch, substitutionValues: values);
    });
    if (changed > 0) return true;
    if (db.getName() != Driver.mysql) return false;
    return await _liveValue(fullKey) != null;
  }

  /// True when a row was deleted. A row that expired but was not deleted
  /// yet counts too.
  @override
  Future<bool> forget(String key) async {
    return await _delete(_db, _key(key)) > 0;
  }

  /// Delete the rows of this store: the keys that start with [prefix].
  /// Its locks go too. Other stores in the same table keep their rows.
  @override
  Future<void> flush() async {
    if (prefix.isEmpty) {
      throw StateError(
        'DatabaseCacheDriver.flush needs a prefix. '
        'It will not delete the whole table.',
      );
    }
    DBDriver db = _db;
    _CacheSql sql = _sql(db);
    await _retry(db, () {
      return db.execute(sql.flush, substitutionValues: sql.prefixValues);
    });
  }

  /// Delete the expired rows of this store. Returns how many.
  /// With an empty [prefix] it deletes every expired row of the table,
  /// also the rows of other stores.
  Future<int> prune() {
    DBDriver db = _db;
    _CacheSql sql = _sql(db);
    Map<String, dynamic> values = <String, dynamic>{
      ...sql.prefixValues,
      'now': _clock.nowMs(),
    };
    return _retry(db, () {
      return db.affectingStatement(sql.prune, substitutionValues: values);
    });
  }

  /// Start [prune] when [pruneInterval] has passed since the last one.
  /// It runs in the root zone, so it never joins an app transaction, and
  /// nobody waits for it. A failed prune only leaves rows for the next one.
  void _pruneSometimes() {
    Duration? interval = pruneInterval;
    if (interval == null) return;
    int now = _clock.nowMs();
    int? last = _lastPrune;
    if (last != null && now - last < interval.inMilliseconds) return;
    _lastPrune = now;
    // a write never fails because of the prune, also not when it throws
    // before its future starts
    try {
      Zone.root.run(prune).catchError(_ignorePruneError);
    } on Object {
      // the next interval tries again
    }
  }

  static int _ignorePruneError(Object error) {
    return 0;
  }

  @override
  CacheLock lock(String name, Duration? ttl, [String? owner]) {
    return DatabaseCacheLock(this, name, ttl, owner);
  }

  /// Insert the lock row when the lock is free. True when taken.
  Future<bool> acquireLock(String name, String owner, Duration? ttl) async {
    return _insertIfMissing(_lockKey(name), owner, _expiresAt(ttl));
  }

  /// Delete the lock row only when [owner] holds it and it has not
  /// expired. An expired row stays: the next lock `get` replaces it.
  Future<bool> releaseLock(String name, String owner) async {
    DBDriver db = _db;
    Map<String, dynamic> values = <String, dynamic>{
      'key': _lockKey(name),
      'owner': owner,
      'now': _clock.nowMs(),
    };
    int deleted = await _retry(db, () {
      return db.affectingStatement(
        _sql(db).releaseLock,
        substitutionValues: values,
      );
    });
    return deleted > 0;
  }

  /// Delete the lock row, whoever holds it.
  Future<bool> forceReleaseLock(String name) async {
    return await _delete(_db, _lockKey(name)) > 0;
  }

  String _lockKey(String name) {
    return _key('${CacheConstants.lockKeyPart}$name');
  }

  /// Insert the row of [fullKey], or replace it only when it is expired.
  /// One atomic upsert, so of two callers at the same time only one wins.
  Future<bool> _insertIfMissing(
    String fullKey,
    String text,
    int? expiresAt,
  ) async {
    DBDriver db = _db;
    Map<String, dynamic> values = <String, dynamic>{
      'key': fullKey,
      'value': text,
      'expires': expiresAt,
      'now': _clock.nowMs(),
    };
    // MySQL counts 1 for a new row and 2 for a replaced one
    int written = await _retry(db, () {
      return db.affectingStatement(_sql(db).add, substitutionValues: values);
    });
    _pruneSometimes();
    return written > 0;
  }

  /// The live row of [fullKey], locked until the transaction ends.
  /// SQLite has no `FOR UPDATE`: its write transaction locks the file.
  Future<Map<String, dynamic>?> _lockedRow(DBDriver db, String fullKey) async {
    List<Map<String, dynamic>> rows = await db.query(
      _sql(db).lockedRow,
      substitutionValues: <String, dynamic>{
        'key': fullKey,
        'now': _clock.nowMs(),
      },
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// The stored value of a live [fullKey], or null.
  Future<Object?> _liveValue(String fullKey) async {
    DBDriver db = _db;
    List<Map<String, dynamic>> rows = await db.query(
      _sql(db).get,
      substitutionValues: <String, dynamic>{
        'key': fullKey,
        'now': _clock.nowMs(),
      },
    );
    return rows.isEmpty ? null : rows.first['value'];
  }

  Future<int> _delete(DBDriver db, String fullKey) {
    return _retry(db, () {
      return db.affectingStatement(
        _sql(db).delete,
        substitutionValues: <String, dynamic>{'key': fullKey},
      );
    });
  }

  int? _expiresAt(Duration? ttl) {
    return ttl == null ? null : _clock.nowMs() + ttl.inMilliseconds;
  }

  /// The text to store. A plain int stays plain, the same as Redis.
  String _encode(Object? value) {
    String plain = jsonEncode(value);
    CacheEncrypter? secret = encrypter;
    return secret == null || value is int ? plain : secret.encrypt(plain);
  }

  /// The JSON text of a stored value, decrypted when needed. Null for a
  /// miss, also when it can not be decrypted.
  String? _plainText(Object? stored) {
    if (stored == null) return null;
    String text = _text(stored);
    CacheEncrypter? secret = encrypter;
    if (secret == null || _plainInt.hasMatch(text)) return text;
    try {
      return secret.decrypt(text);
    } on Object {
      return null;
    }
  }

  dynamic _decode(Object? stored) {
    String? text = _plainText(stored);
    return text == null ? null : jsonDecode(text);
  }

  /// MariaDB gives JSON looking text of a long text column as a Map or
  /// a List. Turn it back into text.
  static String _text(Object value) {
    if (value is String) return value;
    if (value is Map || value is List) return jsonEncode(value);
    return '$value';
  }
}

/// The SQL text of one database type, for one table and prefix. Built
/// once per driver, so a call does not build its query again.
class _CacheSql {
  _CacheSql(Driver type, String table, String prefix) {
    bool mysql = type == Driver.mysql;
    bool sqlite = type == Driver.sqlite;
    String q = mysql ? '`' : '"';
    String t = _quote(q, table);
    String k = _quote(q, 'key');
    String v = _quote(q, 'value');
    String e = _quote(q, 'expires_at');
    // a row that has not expired at `@now`
    live = '($e IS NULL OR $e > @now)';
    String byKey = 'WHERE $k = @key';
    String insert =
        'INSERT INTO $t ($k, $v, $e) VALUES (@key, @value, @expires)';

    get = 'SELECT $v FROM $t $byKey AND $live';
    valueOfKey = 'SELECT $v FROM $t $byKey';
    many = 'SELECT $k, $v FROM $t WHERE $k IN ';
    lockedRow =
        'SELECT $v, $e FROM $t $byKey AND $live${sqlite ? '' : ' FOR UPDATE'}';
    setValue = 'UPDATE $t SET $v = @value $byKey';
    delete = 'DELETE FROM $t $byKey';
    releaseLock = 'DELETE FROM $t $byKey AND $v = @owner AND $live';
    touch = 'UPDATE $t SET $e = @expires $byKey AND $live';
    pull = 'DELETE FROM $t $byKey AND $live RETURNING $v';

    // the old row expired: `NULL <= @now` is not true, so no expiry
    // time means it never expires
    String expired = mysql ? '$e <= @now' : '$t.$e <= @now';
    if (mysql) {
      put = '$insert ON DUPLICATE KEY UPDATE $v = @value, $e = @expires';
      // MySQL sets the columns from left to right: `value` first, while
      // `expires_at` still has the old time.
      add =
          '$insert ON DUPLICATE KEY UPDATE '
          '$v = IF($expired, @value, $v), $e = IF($expired, @expires, $e)';
      // a value that is not an int stays as it is: the SELECT after it
      // tells. CAST AS SIGNED keeps big ints exact (no DOUBLE).
      increment =
          'INSERT INTO $t ($k, $v, $e) VALUES (@key, @start, NULL) '
          'ON DUPLICATE KEY UPDATE '
          '$v = IF($expired, @start, IF($v REGEXP @int, '
          'CAST(CAST($v AS SIGNED) + @by AS CHAR), $v)), '
          '$e = IF($expired, NULL, $e)';
    } else {
      put = '$insert ON CONFLICT ($k) DO UPDATE SET $v = @value, $e = @expires';
      add =
          '$insert ON CONFLICT ($k) DO UPDATE SET $v = @value, $e = @expires '
          'WHERE $expired';
      // SQLite has no regex: an int is text that stays the same as an
      // INTEGER and back. A value that is not an int updates no row, so
      // RETURNING gives none. SQLite turns a sum past the 64-bit limit
      // into a REAL, so it also updates no row when the sum would not fit
      // (@low and @high). Postgres and MySQL throw an error for it.
      String isInt = sqlite
          ? '$t.$v = CAST(CAST($t.$v AS INTEGER) AS TEXT) '
                'AND CAST($t.$v AS INTEGER) BETWEEN @low AND @high'
          : '$t.$v ~ @int';
      String type = sqlite ? 'INTEGER' : 'bigint';
      increment =
          'INSERT INTO $t ($k, $v, $e) VALUES (@key, @start, NULL) '
          'ON CONFLICT ($k) DO UPDATE SET '
          '$v = CASE WHEN $expired THEN @start '
          'ELSE CAST(CAST($t.$v AS $type) + @by AS TEXT) END, '
          '$e = CASE WHEN $expired THEN NULL ELSE $t.$e END '
          'WHERE $expired OR $isInt RETURNING $v';
    }

    // The keys that start with the prefix, case sensitive.
    // - SQLite: LIKE ignores the case of ASCII letters there, so it
    //   compares the start of the key with `substr`.
    // - Postgres and MySQL: LIKE, which is case sensitive there (the
    //   `key` column is `utf8mb4_bin` on MySQL). `!` escapes the LIKE
    //   wildcards, so the `_` in `dox_cache:` is a plain `_`.
    //
    // On Postgres with a collation other than `C`, LIKE can not use the
    // index of the `key` column, so flush reads the whole table. This is
    // slow only on very big tables.
    String prefixMatch;
    if (sqlite) {
      prefixMatch = 'substr($k, 1, ${prefix.runes.length}) = @prefix';
      prefixValues = <String, dynamic>{'prefix': prefix};
    } else {
      prefixMatch = "$k LIKE @pattern ESCAPE '!'";
      String escaped = prefix.replaceAllMapped(RegExp(r'[!%_]'), _escapeLike);
      prefixValues = <String, dynamic>{'pattern': '$escaped%'};
    }
    flush = 'DELETE FROM $t WHERE $prefixMatch';
    // `expires_at` first: it can use the index of that column
    prune = 'DELETE FROM $t WHERE $e <= @now AND $prefixMatch';
  }

  late final String live;
  late final String get;
  late final String valueOfKey;
  late final String many;
  late final String lockedRow;
  late final String setValue;
  late final String delete;
  late final String releaseLock;
  late final String touch;
  late final String pull;
  late final String put;
  late final String add;
  late final String increment;
  late final String flush;
  late final String prune;

  /// The values of the prefix match of [flush] and [prune].
  late final Map<String, dynamic> prefixValues;

  static String _escapeLike(Match match) {
    return '!${match[0]}';
  }

  /// [name] quoted as a column or table name. `key` is a reserved word
  /// in MySQL.
  static String _quote(String q, String name) {
    return '$q${name.replaceAll(q, '$q$q')}$q';
  }
}

/// Lock kept as a row of the cache table. Works across servers.
class DatabaseCacheLock extends CacheLock {
  DatabaseCacheLock(this._driver, super.name, super.ttl, [super.owner]);

  final DatabaseCacheDriver _driver;

  @override
  Future<bool> get() {
    return _driver.acquireLock(name, owner, ttl);
  }

  @override
  Future<bool> release() {
    return _driver.releaseLock(name, owner);
  }

  @override
  Future<bool> forceRelease() {
    return _driver.forceReleaseLock(name);
  }
}

/// Builds a [DatabaseCacheDriver]. Options: table (default `cache`),
/// connection (a dox_orm connection name, default the default
/// connection), prefix, encrypt (needs an encrypter), prune_interval
/// (seconds, see [DatabaseCacheDriver.pruneInterval]).
///
/// ```
/// Dox().cache.extend(
///   'database',
///   DatabaseCacheDriverFactory(Dox().cache.config.encrypter),
/// );
/// ```
class DatabaseCacheDriverFactory implements CacheDriverFactory {
  const DatabaseCacheDriverFactory([
    this._encrypter,
    this._clock = const CacheClock(),
  ]);

  final CacheEncrypter? _encrypter;
  final CacheClock _clock;

  @override
  CacheDriver create(Map<String, dynamic> options) {
    return DatabaseCacheDriver(
      connection: options[DatabaseCacheDriver.connectionOption] as String?,
      table:
          options[DatabaseCacheDriver.tableOption] as String? ??
          DatabaseCacheDriver.defaultTable,
      prefix:
          options[CacheConstants.prefixOption] as String? ??
          CacheConstants.defaultPrefix,
      clock: _clock,
      encrypter: options[CacheConstants.encryptOption] == true
          ? _encrypter
          : null,
      pruneInterval: _seconds(options[DatabaseCacheDriver.pruneIntervalOption]),
    );
  }

  /// `prune_interval` in seconds. Null or 0: no lazy prune.
  static Duration? _seconds(Object? seconds) {
    if (seconds == null) return null;
    if (seconds is! int) {
      throw ArgumentError.value(
        seconds,
        DatabaseCacheDriver.pruneIntervalOption,
        'Must be an int of seconds',
      );
    }
    return seconds > 0 ? Duration(seconds: seconds) : null;
  }
}
