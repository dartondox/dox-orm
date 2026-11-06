import 'package:dox_orm/dox_orm.dart';

import 'shared_mixin.dart';
import 'union.dart';
import 'update.dart';

mixin Insert<T> implements SharedMixin<T> {
  /// create/insert a record and return it as it is in the table
  ///
  /// ```
  /// Blog blog = await Blog().create({
  ///   "title" : "Blog title",
  ///   "body" : "Lorem",
  /// });
  /// Map<String, dynamic> row = await QueryBuilder.table('blog').create({
  ///   "title" : "Blog title",
  /// });
  /// ```
  ///
  /// See [insert] for what it gives when the new row can not be read.
  Future<T> create(Map<String, dynamic> data) async {
    return await insert(data);
  }

  /// insert/create a record and return it as it is in the table: a model
  /// for a model query, a map for `QueryBuilder.table()`.
  ///
  /// ```
  /// Blog blog = await Blog().insert({
  ///   "title" : "Blog title",
  ///   "body" : "Lorem",
  /// });
  /// ```
  ///
  /// Postgres and SQLite read the new row with `RETURNING *`. MySQL reads
  /// it again by the auto increment id, or by the id in [data].
  ///
  /// ponytail: when MySQL can not find the new row (no auto increment and
  /// no id in [data], eg. a pivot table), it gives [data] back: as a map,
  /// or as a model made from [data]. Column defaults of the table are not
  /// in it then.
  Future<T> insert(Map<String, dynamic> data) async {
    /// RETURNING * gives the new row, so no select after the insert
    if (dbDriver.supportsReturning) {
      List<Map<String, dynamic>> rows = await _insert(<Map<String, dynamic>>[
        data,
      ], '*');
      resetSubstitutionValues();
      if (rows.isNotEmpty) {
        // ignore: always_specify_types
        List result = await helper.formatResult(rows);
        return result.first as T;
      }
      return _fromData(data);
    }

    /// _insert and not insertMultiple: a model overrides insertMultiple
    /// to drop keys, and [data] is ready to insert here
    List<Map<String, dynamic>> result = await _insert(<Map<String, dynamic>>[
      data,
    ], helper.wrap(primaryKey));

    /// id can be any type (int, uuid string...).
    /// mysql only returns auto increment ids, so use the given id if any.
    dynamic id = result.isNotEmpty ? result.first[primaryKey] : null;
    id ??= data[primaryKey];
    resetSubstitutionValues();
    T? row = id == null ? null : await _readBack(id);
    return row ?? _fromData(<String, dynamic>{...data, primaryKey: ?id});
  }

  /// read the new row [id] on a new query, so the where, the global
  /// scopes and the soft delete check of this query are not used
  Future<T?> _readBack(dynamic id) async {
    QueryBuilder<T> q = QueryBuilder<T>()
      ..tableName = tableName
      ..self = queryBuilder.self
      ..primaryKey = primaryKey
      ..connection = connection;
    T? row = await q.debug(shouldDebug).find(id);

    /// the new query has no relations to load, this query has them
    if (row is Model && queryBuilder.getPreload().isNotEmpty) {
      await queryBuilder.initPreload(<Model<T>>[row as Model<T>]);
    }
    return row;
  }

  /// [data] as a row of this query: a map, or a model made from it.
  /// a [saved] model knows it is in the table, so save() updates it.
  T _fromData(Map<String, dynamic> data, {bool saved = true}) {
    Map<String, dynamic> row = <String, dynamic>{
      for (MapEntry<String, dynamic> e in data.entries)
        e.key: e.value is DateTime
            ? (e.value as DateTime).toIso8601String()
            : e.value,
    };
    dynamic self = queryBuilder.self;
    if (self is Model) {
      Model<dynamic> model = self.fromMap(row);
      if (saved) model.originalMap = row;
      model.connection = connection;
      return model as T;
    }
    return row as T;
  }

  /// insert/create multiple records. it does not read the new rows.
  ///
  /// ```
  /// List<Map<String, dynamic>> ids = await Blog().insertMultiple([
  ///   {"title" : "Blog title"},
  ///   {"title" : "Another blog title"},
  /// ]);
  /// ```
  /// columns are all keys from all rows.
  /// a row without a key uses the column default value.
  ///
  /// It returns the new ids, by driver:
  /// - Postgres and SQLite: one map per new row, like `[{id: 1}, {id: 2}]`.
  /// - MySQL and MariaDB: one map with the first auto increment id of the
  ///   batch, like `[{id: 1}]`, or an empty list when the table has no
  ///   auto increment.
  /// - SQLite older than 3.35 (no RETURNING): one map with the id of the
  ///   last row.
  Future<List<Map<String, dynamic>>> insertMultiple(
    List<Map<String, dynamic>> list,
  ) {
    return _insert(list, helper.wrap(primaryKey));
  }

  /// insert many rows and read nothing back, like Laravel's bulk
  /// `insert()`. It returns true. An empty [rows] runs no query.
  ///
  /// ```
  /// await QueryBuilder.table('tag').insertMany([
  ///   {'name': 'dart'},
  ///   {'name': 'php'},
  /// ]);
  /// ```
  ///
  /// It has no `RETURNING`, so it also works on a table with no `id`
  /// column, like a pivot table. It fires no model events and sets no
  /// timestamps. On a model, keys that `fillable` and `guarded` do not
  /// allow are dropped from each row. The same column rules as
  /// [insertMultiple].
  Future<bool> insertMany(List<Map<String, dynamic>> rows) async {
    await _insert(rows, null);
    resetSubstitutionValues();
    return true;
  }

  /// insert one row and return its new id, like Laravel's
  /// `insertGetId()`. The id is the auto increment id, or the id in
  /// [data] when the table has no auto increment.
  ///
  /// ```
  /// dynamic id = await QueryBuilder.table('blog').insertGetId({
  ///   'title': 'Blog title',
  /// });
  /// ```
  ///
  /// It fires no model events and sets no timestamps. On a model, keys
  /// that `fillable` and `guarded` do not allow are dropped.
  Future<dynamic> insertGetId(Map<String, dynamic> data) async {
    List<Map<String, dynamic>> rows = await insertMultiple(
      <Map<String, dynamic>>[data],
    );
    resetSubstitutionValues();
    return (rows.isNotEmpty ? rows.first[primaryKey] : null) ??
        data[primaryKey];
  }

  /// insert [rows], or update the row that has the same [uniqueBy]
  /// values. [updateColumns] are the columns to update on a match, the
  /// default is every column that is not in [uniqueBy]. An empty
  /// [updateColumns] keeps the old row. It returns how many rows changed.
  ///
  /// ```
  /// await Flight().upsert(
  ///   [
  ///     {'from': 'Oakland', 'to': 'San Diego', 'price': 99},
  ///     {'from': 'Chicago', 'to': 'New York', 'price': 150},
  ///   ],
  ///   ['from', 'to'],
  ///   ['price'],
  /// );
  /// ```
  ///
  /// Every row must have the same keys. [uniqueBy] must be a primary key
  /// or a unique index.
  /// - Postgres and SQLite use `ON CONFLICT (...) DO UPDATE`, and count 1
  ///   for each new or updated row. Postgres throws when two rows of one
  ///   call have the same [uniqueBy] values.
  /// - MySQL and MariaDB use `ON DUPLICATE KEY UPDATE col = VALUES(col)`.
  ///   They do not read [uniqueBy]: any unique index of the table can
  ///   match. They count 1 for each new row, 2 for each updated row and
  ///   0 for a row that did not change.
  Future<int> upsert(
    List<Map<String, dynamic>> rows,
    List<String> uniqueBy, [
    List<String>? updateColumns,
  ]) async {
    if (rows.isEmpty) return 0;
    if (uniqueBy.isEmpty) {
      throw ArgumentError.value(uniqueBy, 'uniqueBy', 'must not be empty');
    }
    List<String> columns = _sameKeys(rows);
    List<String> update =
        updateColumns ??
        <String>[
          for (String column in columns)
            if (!uniqueBy.contains(column)) column,
        ];

    DBDriver driver = dbDriver;
    String q =
        "INSERT INTO ${helper.wrap(tableName)} ${_values(rows, columns)}";
    if (driver.getName() == Driver.mysql) {
      /// ponytail: `VALUES(col)` is old in MySQL 8 but works there and in
      /// MariaDB. The new `AS alias` form does not work in MariaDB.
      /// `col = col` on a match changes nothing.
      String first = helper.wrap(uniqueBy.first);
      List<String> sets = update.isEmpty
          ? <String>['$first = $first']
          : <String>[
              for (String column in update)
                '${helper.wrap(column)} = VALUES(${helper.wrap(column)})',
            ];
      q += " ON DUPLICATE KEY UPDATE ${sets.join(',')}";
    } else {
      String target = uniqueBy.map(helper.wrap).join(',');
      q += update.isEmpty
          ? " ON CONFLICT ($target) DO NOTHING"
          : " ON CONFLICT ($target) DO UPDATE SET ${<String>[for (String column in update) '${helper.wrap(column)} = excluded.${helper.wrap(column)}'].join(',')}";
    }
    int count = await runAffectingQuery(queryBuilder, q);
    resetSubstitutionValues();
    return count;
  }

  /// insert [rows], and skip a row that the database refuses, like a row
  /// with a duplicate primary key or unique value. It returns how many
  /// rows were inserted.
  ///
  /// ```
  /// int added = await QueryBuilder.table('tag').insertOrIgnore([
  ///   {'name': 'dart'},
  ///   {'name': 'php'},
  /// ]);
  /// ```
  ///
  /// Every row must have the same keys.
  /// - Postgres: `ON CONFLICT DO NOTHING`. It skips rows that clash with
  ///   a primary key, a unique index or an exclusion constraint.
  /// - SQLite: `INSERT OR IGNORE`. It also skips rows that break a
  ///   `NOT NULL` or `CHECK` rule.
  /// - MySQL and MariaDB: `INSERT IGNORE`. It also changes some bad
  ///   values to a warning, like text that is too long (it is cut).
  Future<int> insertOrIgnore(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return 0;
    String values = _values(rows, _sameKeys(rows));
    String table = helper.wrap(tableName);
    String q;
    switch (dbDriver.getName()) {
      case Driver.postgres:
        q = "INSERT INTO $table $values ON CONFLICT DO NOTHING";
      case Driver.mysql:
        q = "INSERT IGNORE INTO $table $values";
      case Driver.sqlite:
        q = "INSERT OR IGNORE INTO $table $values";
    }
    int count = await runAffectingQuery(queryBuilder, q);
    resetSubstitutionValues();
    return count;
  }

  /// the keys of the first row. it throws an [ArgumentError] when a row
  /// has other keys.
  static List<String> _sameKeys(List<Map<String, dynamic>> rows) {
    List<String> columns = rows.first.keys.toList();
    for (Map<String, dynamic> row in rows) {
      if (row.length != columns.length || !columns.every(row.containsKey)) {
        throw ArgumentError.value(
          rows,
          'rows',
          'every row must have the same keys',
        );
      }
    }
    return columns;
  }

  /// `(columns) VALUES (...),(...)` of [rows], with bound values
  String _values(List<Map<String, dynamic>> rows, List<String> columns) {
    DBDriver driver = dbDriver;
    List<String> values = <String>[];
    for (Map<String, dynamic> row in rows) {
      List<String> keys = <String>[];
      for (String column in columns) {
        String key = helper.parseColumnKey(column);
        keys.add(key);
        addSubstitutionValues(key, driver.columnValue(row[column]));
      }
      values.add("(${keys.join(',')})");
    }
    return "(${columns.map(helper.wrap).join(',')}) VALUES ${values.join(',')}";
  }

  /// the first row that matches all [where] pairs, or a new row made from
  /// [where] and [values] (with [create], so a model fires its events)
  ///
  /// ```
  /// User user = await User().firstOrCreate(
  ///   {'email': 'ann@example.com'},
  ///   {'name': 'Ann'},
  /// );
  /// ```
  ///
  /// The where and scopes of this query are used to find the row. Two
  /// calls at the same time can both create a row. Use a unique index and
  /// [upsert] when that matters.
  Future<T> firstOrCreate(
    Map<String, dynamic> where, [
    Map<String, dynamic> values = const <String, dynamic>{},
  ]) async {
    T? found = await _whereAll(where, 'firstOrCreate').getFirst();
    if (found != null) return found;
    resetSubstitutionValues();
    return await queryBuilder.create(<String, dynamic>{...where, ...values});
  }

  /// the first row that matches all [where] pairs, or a new row made
  /// from [where] and [values] that is not saved yet
  ///
  /// ```
  /// User user = await User().firstOrNew({'email': 'ann@example.com'});
  /// if (!user.exists) await user.save();
  /// ```
  Future<T> firstOrNew(
    Map<String, dynamic> where, [
    Map<String, dynamic> values = const <String, dynamic>{},
  ]) async {
    T? found = await _whereAll(where, 'firstOrNew').getFirst();
    return found ??
        _fromData(<String, dynamic>{...where, ...values}, saved: false);
  }

  /// update the first row that matches all [where] pairs with [values],
  /// or create a row from [where] and [values]. It returns the row as it
  /// is in the table.
  ///
  /// ```
  /// Map<String, dynamic> row = await QueryBuilder.table('settings')
  ///     .updateOrCreate({'key': 'theme'}, {'value': 'dark'});
  /// ```
  ///
  /// The row is updated by its primary key. A table without the primary
  /// key column is updated by the [where] pairs.
  Future<T> updateOrCreate(
    Map<String, dynamic> where,
    Map<String, dynamic> values,
  ) async {
    T? found = await _whereAll(where, 'updateOrCreate').getFirst();
    if (found == null) {
      resetSubstitutionValues();
      return await queryBuilder.create(<String, dynamic>{...where, ...values});
    }
    Map<String, dynamic> row = found as Map<String, dynamic>;
    dynamic id = row[primaryKey];
    QueryBuilder<T> q = QueryBuilder<T>()
      ..tableName = tableName
      ..primaryKey = primaryKey
      ..connection = connection;
    q.debug(shouldDebug);
    if (id != null) {
      q.where(primaryKey, id);
    } else {
      for (MapEntry<String, dynamic> e in where.entries) {
        q.where(e.key, e.value);
      }
    }
    await q.update(values);
    T? fresh = id == null ? null : await _readBack(id);
    return fresh ?? _fromData(<String, dynamic>{...row, ...values});
  }

  /// this query with `where(key, value)` for each pair of [where]
  /// it throws a [StateError] on a union() query: the where would go to
  /// the first part only.
  QueryBuilder<T> _whereAll(Map<String, dynamic> where, String method) {
    checkNoUnion(queryBuilder, method);
    for (MapEntry<String, dynamic> e in where.entries) {
      queryBuilder.where(e.key, e.value);
    }
    return queryBuilder;
  }

  /// insert [list] and return the [returning] columns of the new rows,
  /// when the driver supports RETURNING. A null [returning] reads nothing.
  Future<List<Map<String, dynamic>>> _insert(
    List<Map<String, dynamic>> list,
    String? returning,
  ) async {
    if (list.isEmpty) {
      return <Map<String, dynamic>>[];
    }
    List<String> columns = <String>{
      for (Map<String, dynamic> data in list) ...data.keys,
    }.toList();

    /// sqlite has no `DEFAULT` in VALUES, so rows with missing keys are
    /// inserted one by one
    if (queryBuilder.dbDriver.getName() == Driver.sqlite &&
        list.length > 1 &&
        list.any((Map<String, dynamic> d) => d.length != columns.length)) {
      List<Map<String, dynamic>> result = <Map<String, dynamic>>[];
      for (Map<String, dynamic> data in list) {
        result.addAll(await _insert(<Map<String, dynamic>>[data], returning));
        resetSubstitutionValues();
      }
      return result;
    }
    List<String> values = <String>[];
    DBDriver driver = queryBuilder.dbDriver;

    // creating values to insert (value1, val2);
    for (Map<String, dynamic> data in list) {
      List<String> ret = <String>[];

      /// follow the same column order for every row, so values do not go
      /// to the wrong column when rows have keys in a different order
      for (String key in columns) {
        if (!data.containsKey(key)) {
          ret.add('DEFAULT');
          continue;
        }
        String columnKey = helper.parseColumnKey(key);
        ret.add(columnKey);
        addSubstitutionValues(columnKey, driver.columnValue(data[key]));
      }
      values.add("(${ret.join(',')})");
    }

    String returningQuery =
        returning != null && queryBuilder.dbDriver.supportsReturning
        ? 'RETURNING $returning'
        : '';

    String query =
        "INSERT INTO ${helper.wrap(tableName)} (${columns.map(helper.wrap).join(',')}) VALUES ${values.join(',')} $returningQuery";
    return await helper.runQuery(query);
  }
}
