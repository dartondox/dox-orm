import 'dart:async';
import 'dart:convert';

import 'package:dox_orm/dox_orm.dart';

import 'count.dart';
import 'limit.dart';
import 'order_by.dart';
import 'where.dart';
import 'shared_mixin.dart';

/// the select sql of [qb], as get() runs it. it is a function, not a
/// query method, so it can not clash with the name of a model field.
String selectSql(QueryBuilder<dynamic> qb) => qb._buildQuery();

mixin Get<T> implements SharedMixin<T> {
  /// build query to run
  String _buildQuery() {
    if (queryBuilder.getRawQuery().isNotEmpty) {
      return queryBuilder.getRawQuery();
    }
    String q = "SELECT $selectQueryString FROM ${queryBuilder.getFromQuery()}";
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
  /// [arg2] is value of column. `find('email', null)` finds the row
  /// where email IS NULL.
  /// This cannot be use with other query such as, where, join, delete.
  /// It works with lockForUpdate() and sharedLock().
  Future<T?> find(dynamic arg1, [dynamic arg2 = missingArg]) {
    bool idOnly = identical(arg2, missingArg);
    String column = idOnly ? primaryKey : arg1;
    dynamic value = idOnly ? arg1 : arg2;
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
        !qb.hasUnion &&
        !qb.hasFromSub &&
        qb.getSelectQuery() == '*' &&
        !qb.hasAggregates &&
        !qb.trashedOnly &&
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
    _checkPerPage(perPage);
    if (currentPage < 1) currentPage = 1;
    int offset = (currentPage - 1) * perPage;
    QueryBuilder<T> qb = queryBuilder;

    /// the count gets its own copy of the values, because the page query
    /// adds LIMIT and OFFSET to them
    String countSql = countQuery(qb);
    Map<String, dynamic> countValues = Map<String, dynamic>.of(
      substitutionValues,
    );
    Future<int> total = Future<int>.sync(
      () => helper.runQuery(countSql, countValues).then(countTotal),
    );

    /// count and page run at the same time, on two connections. in a
    /// transaction (one connection) and on sqlite (sync) they run one
    /// after the other.
    if (DBDriver.inTransaction || dbDriver.getName() == Driver.sqlite) {
      await total;
    }
    Future<List<T>> page = qb.limit(perPage).offset(offset).get();
    int rowCount;
    List<T> data;
    try {
      (rowCount, data) = await (total, page).wait;
    } on ParallelWaitError<(int?, List<T>?), (AsyncError?, AsyncError?)> catch (
      e
    ) {
      /// throw the error itself, like one query does
      AsyncError error = e.errors.$1 ?? e.errors.$2!;
      Error.throwWithStackTrace(error.error, error.stackTrace);
    }

    return Pagination<T>(
      total: rowCount,
      perPage: perPage,
      lastPage: (rowCount / perPage).ceil(),
      currentPage: currentPage,
      data: data,
    );
  }

  /// a page of rows without the total count, so it runs one query, not
  /// two. It reads one row more to know if there is a next page.
  ///
  /// ```
  /// SimplePagination<Blog> page = await Blog().simplePaginate(
  ///   currentPage: 2,
  ///   perPage: 10,
  /// );
  /// page.hasMorePages;
  /// ```
  /// [perPage] must be 1 or more, else it throws an [ArgumentError].
  /// a [currentPage] below 1 is read as page 1.
  Future<SimplePagination<T>> simplePaginate({
    required int currentPage,
    required int perPage,
  }) async {
    _checkPerPage(perPage);
    if (currentPage < 1) currentPage = 1;
    List<T> rows = await queryBuilder
        .limit(perPage + 1)
        .offset((currentPage - 1) * perPage)
        .get();
    bool more = rows.length > perPage;
    return SimplePagination<T>(
      perPage: perPage,
      currentPage: currentPage,
      hasMorePages: more,
      data: more ? rows.sublist(0, perPage) : rows,
    );
  }

  /// a page of rows after (or before) a cursor, like Laravel. It is
  /// fast on big tables, because it uses `WHERE column > value`, not
  /// OFFSET.
  ///
  /// ```
  /// CursorPagination<Blog> page = await Blog()
  ///     .orderBy('created_at', 'desc')
  ///     .cursorPaginate(perPage: 10, cursor: req.input('cursor'));
  /// page.nextCursor; // give it back as cursor to read the next page
  /// ```
  ///
  /// The rows are ordered by the orderBy() columns (asc and desc can
  /// be mixed). With no orderBy(), [column] (the primary key by default)
  /// and [direction] (`asc` or `desc`) give the order. The primary key
  /// is added last when it is not in the order, so rows with the same
  /// values are never skipped. The order columns must be in the select
  /// and have no null values. orderByRaw(), inRandomOrder(), or
  /// orderBy() together with [column] throw a [StateError].
  ///
  /// The cursor is a base64 text from [CursorPagination.nextCursor] or
  /// [CursorPagination.prevCursor]. It is safe to take it from a user:
  /// the columns and the order come from the code, and its values are
  /// only sent as query values. A cursor that is not valid gives the
  /// first page: bad base64 or JSON, made for other columns, or values
  /// that do not fit the columns (checked against the rows, and a
  /// Postgres "data exception" is caught).
  ///
  /// It throws a [StateError] on a union() or fromSub() query.
  Future<CursorPagination<T>> cursorPaginate({
    required int perPage,
    String? cursor,
    String? column,
    String direction = 'asc',
  }) async {
    _checkNoSub('cursorPaginate');
    _checkPerPage(perPage);
    String dir = direction.toLowerCase();
    if (dir != 'asc' && dir != 'desc') {
      throw ArgumentError.value(direction, 'direction', 'must be asc or desc');
    }
    QueryBuilder<T> qb = queryBuilder;
    List<(String, bool)>? order = orderColumnsOf(qb);
    if (order == null) {
      throw StateError(
        'cursorPaginate() can not use orderByRaw() or inRandomOrder(). '
        'Use orderBy().',
      );
    }
    if (order.isNotEmpty && column != null) {
      throw StateError(
        'cursorPaginate(): give the order with orderBy() or with column, '
        'not both.',
      );
    }
    List<(String, bool)> columns = order.isEmpty
        ? <(String, bool)>[(column ?? primaryKey, dir == 'desc')]
        : <(String, bool)>[...order];
    bool hasKey = false;
    for ((String, bool) c in columns) {
      if (_keyOf(c.$1) == _keyOf(primaryKey)) hasKey = true;
    }
    if (!hasKey) columns.add((primaryKey, false));
    List<String> names = <String>[for ((String, bool) c in columns) c.$1];

    (List<dynamic>, bool)? at = _readCursor(cursor, names);
    List<T> rows;
    (rows, at) = await _cursorRows(qb, columns, at, perPage);
    bool forward = at?.$2 ?? true;
    bool more = rows.length > perPage;
    if (more) rows = rows.sublist(0, perPage);

    /// going back, the rows come in the other order
    if (!forward) rows = rows.reversed.toList();
    bool hasNext = forward ? more : at != null;
    bool hasPrev = forward ? at != null : more;
    return CursorPagination<T>(
      perPage: perPage,
      nextCursor: hasNext && rows.isNotEmpty
          ? _makeCursor(rows.last, names, true)
          : null,
      prevCursor: hasPrev && rows.isNotEmpty
          ? _makeCursor(rows.first, names, false)
          : null,
      data: rows,
    );
  }

  /// the rows of one cursor page, one more than [perPage], and the
  /// cursor that was used: null when [at] did not fit, then it is the
  /// first page
  Future<(List<T>, (List<dynamic>, bool)?)> _cursorRows(
    QueryBuilder<T> qb,
    List<(String, bool)> columns,
    (List<dynamic>, bool)? at,
    int perPage,
  ) async {
    bool forward = at?.$2 ?? true;

    /// going back, read the rows in the other order
    setOrderOf(qb, <(String, bool)>[
      for ((String, bool) c in columns)
        (_qualified(c.$1), forward ? c.$2 : !c.$2),
    ]);
    qb.limit(perPage + 1);
    if (at == null) return (await qb.get(), null);

    /// put the conditions so far in brackets, so an OR in them can not
    /// skip the cursor condition
    qb.applyGlobalScopes();
    qb.groupWheres(0);
    qb.whereRaw(_cursorWhere(columns, forward), <String, dynamic>{
      for (int i = 0; i < at.$1.length; i++) '$_cursorKey$i': at.$1[i],
    });
    List<T>? rows;
    try {
      rows = await _getInSavepoint(qb);
      if (rows.isNotEmpty && _cursorFits(rows, columns, at.$1)) {
        return (rows, at);
      }
    } on PgServerException catch (error) {
      /// a value that does not fit its column, like `abc` for an int
      if (!error.code.startsWith('22')) rethrow;
    }

    /// the cursor does not fit, or the page is empty: drop the cursor,
    /// and read the first page
    dropLastWhere(qb);
    for (int i = 0; i < at.$1.length; i++) {
      substitutionValues.remove('$_cursorKey$i');
    }
    (List<T>, Object?) first = await _cursorRows(qb, columns, null, perPage);

    /// an empty page is real when the cursor fits the rows of the first
    /// page. ponytail: one more query, only for an empty page.
    if (rows != null && _cursorFits(first.$1, columns, at.$1)) {
      return (rows, at);
    }
    return (first.$1, null);
  }

  /// get() in a savepoint on Postgres in a transaction, so a failed
  /// query does not break the transaction of the app
  Future<List<T>> _getInSavepoint(QueryBuilder<T> qb) {
    if (!DBDriver.inTransaction || dbDriver.getName() != Driver.postgres) {
      return qb.get();
    }
    return QueryBuilder.transaction(qb.get, connection: connection);
  }

  /// `(a > @c0) OR (a = @c0 AND b < @c1) OR ...`: the rows after the
  /// cursor, by the order of [columns]
  String _cursorWhere(List<(String, bool)> columns, bool forward) {
    List<String> ors = <String>[];
    for (int i = 0; i < columns.length; i++) {
      List<String> ands = <String>[
        for (int j = 0; j < i; j++)
          '${helper.wrap(_qualified(columns[j].$1))} = @$_cursorKey$j',
      ];
      String op = columns[i].$2 != forward ? '>' : '<';
      ands.add('${helper.wrap(_qualified(columns[i].$1))} $op @$_cursorKey$i');
      ors.add('(${ands.join(' AND ')})');
    }
    return '(${ors.join(' OR ')})';
  }

  /// param name start of the cursor values of cursorPaginate()
  static const String _cursorKey = 'dox_cursor';

  static void _checkPerPage(int perPage) {
    if (perPage < 1) {
      throw ArgumentError.value(perPage, 'perPage', 'must be 1 or more');
    }
  }

  /// the column name without the table, like `id` for `blog.id`
  static String _keyOf(String column) => column.split('.').last;

  /// the kind of a cursor value: n (number), s (text), d (date), or
  /// null when it can not be in a cursor
  static String? _kindOf(dynamic value) {
    if (value is num) return 'n';
    if (value is String) return 's';
    if (value is DateTime) return 'd';
    return null;
  }

  /// true when each cursor value has the kind of the same column in the
  /// rows. no rows: nothing to check.
  static bool _cursorFits(
    List<dynamic> rows,
    List<(String, bool)> columns,
    List<dynamic> values,
  ) {
    if (rows.isEmpty) return true;
    for (int i = 0; i < columns.length; i++) {
      dynamic value = _valueOfRow(rows.first, _keyOf(columns[i].$1));
      if (_kindOf(value) != _kindOf(values[i])) return false;
    }
    return true;
  }

  /// the cursor of [row]: base64 of
  /// `{"c": [columns], "v": [values], "t": "kinds", "n": next}`.
  /// a date value is an iso text with the kind `d`.
  static String _makeCursor(dynamic row, List<String> names, bool next) {
    List<dynamic> values = <dynamic>[];
    String kinds = '';
    for (String name in names) {
      dynamic value = _valueOfRow(row, _keyOf(name));
      String? kind = _kindOf(value);
      if (kind == null) {
        throw StateError(
          'cursorPaginate() needs the "${_keyOf(name)}" column in each row, '
          'as a number, a text or a date, never null',
        );
      }
      values.add(value is DateTime ? value.toIso8601String() : value);
      kinds += kind;
    }
    Map<String, dynamic> data = <String, dynamic>{
      'c': names,
      'v': values,
      't': kinds,
      'n': next,
    };
    return base64Url.encode(utf8.encode(jsonEncode(data))).replaceAll('=', '');
  }

  /// the values and the direction (true is next) in [cursor], or null
  /// when [cursor] is empty, not valid, or made for other columns.
  /// the values are only used as query params, never in the sql.
  static (List<dynamic>, bool)? _readCursor(
    String? cursor,
    List<String> names,
  ) {
    if (cursor == null || cursor.isEmpty || cursor.length > 1024) return null;
    try {
      Object? data = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(cursor))),
      );
      if (data is! Map) return null;
      dynamic c = data['c'];
      dynamic v = data['v'];
      dynamic t = data['t'];
      dynamic next = data['n'];
      if (next is! bool || c is! List || v is! List || t is! String) {
        return null;
      }
      int n = names.length;
      if (c.length != n || v.length != n || t.length != n) return null;
      List<dynamic> values = <dynamic>[];
      for (int i = 0; i < n; i++) {
        dynamic value = v[i];
        if (c[i] != names[i]) return null;
        switch (t[i]) {
          case 'n' when value is num:
          case 's' when value is String:
            values.add(value);
          case 'd' when value is String:
            values.add(DateTime.parse(value));
          default:
            return null;
        }
      }
      return (values, next);
    } on FormatException {
      return null;
    }
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
  Future<T> findOrFail(dynamic arg1, [dynamic arg2 = missingArg]) async {
    T? row = await find(arg1, arg2);
    if (row == null) {
      bool idOnly = identical(arg2, missingArg);
      throw ModelNotFoundException(
        tableName,
        id: idOnly ? arg1 : arg2,
        column: idOnly ? primaryKey : arg1.toString(),
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
        "SELECT $distinct$select FROM ${queryBuilder.getFromQuery()}"
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
  /// it throws a [StateError] when the query has an orderBy(), and on a
  /// union() or fromSub() query.
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
    _checkNoSub('chunkById');
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

  /// [method] adds its where to this query only, so on a union it would
  /// page the first part only. it throws a [StateError] then.
  void _checkNoSub(String method) {
    if (queryBuilder.hasUnion || queryBuilder.hasFromSub) {
      throw StateError(
        '$method() can not be used with union() or fromSub(). '
        'Use paginate(), simplePaginate() or chunk().',
      );
    }
  }

  static void _checkChunkSize(int size) {
    if (size < 1) {
      throw ArgumentError.value(size, 'size', 'must be 1 or more');
    }
  }

  /// [column] with the table name in front, so a join can not make it
  /// ambiguous
  String _qualified(String column) {
    /// the ORDER BY of a union takes only the plain output name
    if (column.contains('.') || queryBuilder.hasUnion) return column;
    return '$tableName.$column';
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
  ///
  /// It throws a [StateError] on a union() query, it would read only the
  /// first query. Use get() then.
  Future<List<T>> all() async {
    if (queryBuilder.hasUnion) {
      throw StateError('all() can not be used on a union() query. Use get().');
    }

    /// the where part adds soft deletes and global scopes
    String query =
        "SELECT $selectQueryString FROM ${queryBuilder.getFromQuery()}"
        "${queryBuilder.getWhereQuery()}${queryBuilder.getLockQuery()}";
    return _typed(await helper.formatResult(await helper.runQuery(query)));
  }
}
