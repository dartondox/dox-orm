import 'dart:async';

import 'package:dox_orm/dox_orm.dart';

import 'limit.dart';
import 'shared_mixin.dart';

mixin Get<T> implements SharedMixin<T> {
  /// build query to run
  String _buildQuery() {
    if (queryBuilder.getRawQuery().isNotEmpty) {
      return queryBuilder.getRawQuery();
    }
    String q = "SELECT $selectQueryString FROM ${helper.wrap(tableName)}";
    q += helper.getCommonQuery();
    q += queryBuilder.getLockQuery();
    return q;
  }

  /// Find a record
  ///
  /// ```
  /// await Blog().find(1);
  /// await Blog().find('name', 'John');
  /// ```
  /// If only [arg1] is provided, it will as as id value,
  /// If both [arg1] and [arg2] ar provided, [arg1] is column name and
  /// [arg2] is value of column
  /// This cannot be use with other query such as, where, join, delete.
  /// It works with lockForUpdate() and sharedLock().
  Future<T?> find(dynamic arg1, [dynamic arg2]) {
    String column = arg2 == null ? primaryKey : arg1;
    dynamic value = arg2 ?? arg1;
    QueryBuilder<T> qb = queryBuilder;
    if (value == null || !_isPlain(qb)) {
      qb.where(column, value).limit(1);
      return _first(_buildQuery());
    }

    /// a plain find: the sql is the same every time, so build it once
    /// for each driver, table and column. a find with a lock is not
    /// plain, so it never uses or fills this cache.
    bool soft = isSoftDeletes && !withTrashed;
    Map<String, (String, String)> sqls =
        ((soft ? _softFindSql : _findSql)[dbDriver] ??=
                <String, Map<String, (String, String)>>{})[tableName] ??=
            <String, (String, String)>{};
    (String, String)? hit = sqls[column];
    qb.limit(1);
    if (hit == null) {
      qb.where(column, value);
      String sql = _buildQuery();

      /// the where value is the first, the LIMIT value comes after it
      String key = substitutionValues.keys.first;

      /// ponytail: cleared when full, column names are a small set
      if (sqls.length >= 100) sqls.clear();
      sqls[column] = (sql, key);
      return _first(sql);
    }
    substitutionValues[hit.$2] = value;
    substitutionValues[Limit.limitKey] = 1;
    return _first(hit.$1);
  }

  /// find sql of each driver, then table, then column: (sql, param key)
  static final Expando<Map<String, Map<String, (String, String)>>> _findSql =
      Expando<Map<String, Map<String, (String, String)>>>();

  /// the same, for soft delete models without trashed rows
  static final Expando<Map<String, Map<String, (String, String)>>>
  _softFindSql = Expando<Map<String, Map<String, (String, String)>>>();

  /// true when nothing was added to the query yet
  static bool _isPlain(QueryBuilder<dynamic> qb) {
    return !qb.hasWhere &&
        qb.substitutionValues.isEmpty &&
        qb.getRawQuery().isEmpty &&
        qb.getJoinQuery().isEmpty &&
        qb.getGroupByQuery().isEmpty &&
        qb.getOrderByQuery().isEmpty &&
        qb.getLimitQuery().isEmpty &&
        !qb.hasLock &&
        qb.getSelectQuery() == '*' &&
        !qb.hasAggregates &&
        !qb.hasGlobalScopes;
  }

  /// Get records
  ///
  /// ```
  /// List<Blog> blogs = await Blog().where('status', 'active').get();
  /// ```
  Future<List<T>> get() async {
    return _typed(
      await helper.formatResult(await helper.runQuery(_buildQuery())),
    );
  }

  /// a model query with groupBy() or rawQuery() gives plain rows (maps),
  /// not models. Say so, instead of a type error later.
  // ignore: always_specify_types
  List<T> _typed(List rows) {
    if (rows is List<T>) return rows;
    throw StateError(
      'This query gives plain rows, not $T models. '
      'Use QueryBuilder.table() for groupBy() and rawQuery().',
    );
  }

  /// paginate
  ///
  /// ```
  /// Pagination pagination = await Blog().paginate(
  ///  currentPage: 1,
  ///  perPage: 10,
  /// );
  /// ```
  /// [perPage] must be 1 or more, else it throws an [ArgumentError].
  /// a [currentPage] below 1 is read as page 1.
  Future<Pagination<T>> paginate({
    required int currentPage,
    required int perPage,
  }) async {
    if (perPage < 1) {
      throw ArgumentError.value(perPage, 'perPage', 'must be 1 or more');
    }
    if (currentPage < 1) currentPage = 1;
    int offset = (currentPage - 1) * perPage;

    int total = await queryBuilder.count();

    List<T> data = await queryBuilder.limit(perPage).offset(offset).get();

    return Pagination<T>(
      total: total,
      perPage: perPage,
      lastPage: (total / perPage).ceil(),
      currentPage: currentPage,
      data: data,
    );
  }

  /// Get records
  ///
  /// ```
  /// Blog? blog = await Blog().where('status', 'active').getFirst();
  /// ```
  Future<T?> getFirst() {
    queryBuilder.limit(1);
    return _first(_buildQuery());
  }

  /// the first row, like getFirst(), but it throws a
  /// [ModelNotFoundException] when no row matches
  ///
  /// ```
  /// Blog blog = await Blog().where('slug', slug).firstOrFail();
  /// ```
  Future<T> firstOrFail() async {
    T? row = await getFirst();
    if (row == null) throw ModelNotFoundException(tableName);
    return row;
  }

  /// find a record, like find(), but it throws a
  /// [ModelNotFoundException] when there is no such row
  ///
  /// ```
  /// Blog blog = await Blog().findOrFail(1);
  /// Blog blog = await Blog().findOrFail('slug', 'hello');
  /// ```
  Future<T> findOrFail(dynamic arg1, [dynamic arg2]) async {
    T? row = await find(arg1, arg2);
    if (row == null) {
      throw ModelNotFoundException(
        tableName,
        id: arg2 ?? arg1,
        column: arg2 == null ? primaryKey : arg1.toString(),
      );
    }
    return row;
  }

  /// the values of one [column] of the rows, as a list. it uses where,
  /// join, order by, limit, distinct and locks. dates are iso strings.
  ///
  /// ```
  /// List<dynamic> titles = await Blog().orderBy('title').pluck('title');
  /// ```
  Future<List<dynamic>> pluck(String column) async {
    List<Map<String, dynamic>> rows = await _pluckRows(<String>[column]);
    return <dynamic>[for (Map<String, dynamic> row in rows) row['dox_pluck0']];
  }

  /// the values of [column] of the rows, as a map by the value of [key].
  /// when two rows have the same key, the last one wins.
  ///
  /// ```
  /// Map<dynamic, dynamic> titles = await Blog().pluckMap('title', 'uid');
  /// // {1: 'first title', 2: 'second title'}
  /// ```
  Future<Map<dynamic, dynamic>> pluckMap(String column, String key) async {
    List<Map<String, dynamic>> rows = await _pluckRows(<String>[column, key]);
    return <dynamic, dynamic>{
      for (Map<String, dynamic> row in rows)
        row['dox_pluck1']: row['dox_pluck0'],
    };
  }

  /// the value of [column] of the first row, or null when no row
  /// matches
  ///
  /// it is not called value(), because `value` is a common column name,
  /// and a model field can not have the name of a query method.
  ///
  /// ```
  /// dynamic email = await User().where('id', 1).valueOf('email');
  /// ```
  Future<dynamic> valueOf(String column) async {
    queryBuilder.limit(1);
    List<Map<String, dynamic>> rows = await _pluckRows(<String>[column]);
    return rows.isEmpty ? null : rows.first['dox_pluck0'];
  }

  /// select only [columns], as `dox_pluck0`, `dox_pluck1`...
  Future<List<Map<String, dynamic>>> _pluckRows(List<String> columns) async {
    if (queryBuilder.getRawQuery().isNotEmpty) {
      throw StateError('pluck() and valueOf() can not be used with rawQuery()');
    }
    String select = <String>[
      for (int i = 0; i < columns.length; i++)
        '${helper.wrap(columns[i])} as ${helper.wrap('dox_pluck$i')}',
    ].join(',');
    String distinct = queryBuilder.isDistinct ? 'DISTINCT ' : '';
    String q =
        "SELECT $distinct$select FROM ${helper.wrap(tableName)}"
        "${helper.getCommonQuery()}${queryBuilder.getLockQuery()}";
    return helper.getMapResult(await helper.runQuery(q));
  }

  /// run [callback] on the rows, [size] rows at a time, so a big table
  /// does not fill the memory. it stops when [callback] returns false.
  /// it returns false when it was stopped, else true.
  /// with no orderBy() it orders by the primary key, so each page is
  /// the same. limit and offset are set by chunk().
  ///
  /// ```
  /// await Blog().where('status', 'active').chunk(100, (List<Blog> blogs) {
  ///   for (Blog blog in blogs) {
  ///     print(blog.title);
  ///   }
  /// });
  /// ```
  /// ponytail: it pages with OFFSET. when the callback adds, deletes or
  /// changes rows so they match or stop matching, rows are skipped or
  /// read twice. use chunkById() then.
  Future<bool> chunk(
    int size,
    FutureOr<bool?> Function(List<T> rows) callback,
  ) async {
    _checkChunkSize(size);
    QueryBuilder<T> qb = queryBuilder;
    if (qb.getOrderByQuery().isEmpty) {
      qb.orderBy(_qualified(primaryKey));
    }
    for (int page = 0; ; page++) {
      List<T> rows = await qb.limit(size).offset(page * size).get();
      if (rows.isEmpty) return true;
      if (await callback(rows) == false) return false;
      if (rows.length < size) return true;
    }
  }

  /// like chunk(), but each page is `WHERE column > last value`, ordered
  /// by [column] (the primary key by default). it is safe when the
  /// callback changes or deletes rows. the column must be unique, and the
  /// rows must have it (do not leave it out of select()).
  /// it throws a [StateError] when the query has an orderBy().
  ///
  /// ```
  /// await User().chunkById(100, (List<User> users) async {
  ///   for (User user in users) {
  ///     await user.delete();
  ///   }
  /// });
  /// ```
  Future<bool> chunkById(
    int size,
    FutureOr<bool?> Function(List<T> rows) callback, {
    String? column,
  }) async {
    _checkChunkSize(size);
    QueryBuilder<T> qb = queryBuilder;
    if (qb.getOrderByQuery().isNotEmpty) {
      throw StateError(
        'chunkById() orders by the id column itself. '
        'Remove orderBy() from the query.',
      );
    }
    String name = column ?? primaryKey;
    String qualified = _qualified(name);
    String key = name.split('.').last;
    qb.orderBy(qualified).limit(size).offset(0);
    bool hasLastWhere = false;
    while (true) {
      List<T> rows = await qb.get();
      if (rows.isEmpty) return true;
      if (await callback(rows) == false) return false;
      if (rows.length < size) return true;
      dynamic last = _valueOfRow(rows.last, key);
      if (last == null) {
        throw StateError('chunkById() needs the "$key" column in each row');
      }
      if (hasLastWhere) {
        substitutionValues[_chunkKey] = last;
        continue;
      }

      /// put the conditions so far in brackets, so an OR in them can not
      /// skip the new condition
      qb.applyGlobalScopes();
      qb.groupWheres(0);
      qb.whereRaw('${helper.wrap(qualified)} > @$_chunkKey', <String, dynamic>{
        _chunkKey: last,
      });
      hasLastWhere = true;
    }
  }

  /// param name of the last value of chunkById()
  static const String _chunkKey = 'dox_chunk_last';

  static void _checkChunkSize(int size) {
    if (size < 1) {
      throw ArgumentError.value(size, 'size', 'must be 1 or more');
    }
  }

  /// [column] with the table name in front, so a join can not make it
  /// ambiguous
  String _qualified(String column) {
    return column.contains('.') ? column : '$tableName.$column';
  }

  /// the value of [key] in a row: a map, or a model (its original row)
  static dynamic _valueOfRow(dynamic row, String key) {
    if (row is Map) return row[key];
    if (row is QueryBuilder) return row.originalMap[key];
    return null;
  }

  /// run [callback] on the query only when [condition] is true, else
  /// run [otherwise] when it is given. it keeps a query in one chain.
  ///
  /// ```
  /// List<Blog> blogs = await Blog()
  ///     .when(status != null, (QueryBuilder<Blog> q) {
  ///       q.where('status', status);
  ///     })
  ///     .get();
  /// ```
  QueryBuilder<T> when(
    bool condition,
    void Function(QueryBuilder<T> query) callback, [
    void Function(QueryBuilder<T> query)? otherwise,
  ]) {
    if (condition) {
      callback(queryBuilder);
    } else {
      otherwise?.call(queryBuilder);
    }
    return queryBuilder;
  }

  /// run [sql] and return the first row, or null
  Future<T?> _first(String sql) async {
    // ignore: always_specify_types
    FutureOr<List> rows = helper.formatResult(await helper.runQuery(sql));
    // ignore: always_specify_types
    List result = rows is Future<List> ? await rows : rows;
    return result.isEmpty ? null : _typed(result).first;
  }

  /// Get Sql string
  ///
  /// ```
  /// String query = Blog().where('status', 'active').toSql();
  /// ```
  String toSql() {
    String q = _buildQuery();
    Map<String, dynamic> values = queryBuilder.substitutionValues;
    return q.replaceAllMapped(RegExp(r'@(\w+)'), (Match m) {
      String key = m.group(1)!;
      return values.containsKey(key) ? values[key].toString() : m.group(0)!;
    });
  }

  /// Get all record from table
  ///
  /// ```
  /// List<Blog> blogs = await Blog().all();
  /// ```
  Future<List<T>> all() async {
    /// the where part adds soft deletes and global scopes
    String query =
        "SELECT $selectQueryString FROM ${helper.wrap(tableName)}"
        "${queryBuilder.getWhereQuery()}${queryBuilder.getLockQuery()}";
    return _typed(await helper.formatResult(await helper.runQuery(query)));
  }
}
