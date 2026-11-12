import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dox_orm/dox_orm.dart';

import 'count.dart';
import 'limit.dart';
import 'order_by.dart';
import 'where.dart';
import 'shared_mixin.dart';
import 'union.dart';

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
  /// where email IS NULL. With two args, [arg1] that is not a text (like
  /// `find(5, null)`) throws an [ArgumentError].
  /// This cannot be use with other query such as, where, join, delete.
  /// It works with lockForUpdate() and sharedLock().
  /// It throws a [StateError] on a union() query: the id would only be
  /// checked in the first part. Use get() then.
  Future<T?> find(dynamic arg1, [dynamic arg2 = missingArg]) {
    bool idOnly = identical(arg2, missingArg);
    try {
      checkNoUnion(queryBuilder, 'find');
      if (!idOnly && arg1 is! String) {
        throw ArgumentError.value(
          arg1,
          'arg1',
          'must be a column name when a second arg is given. '
              'Use find(id) to find by id',
        );
      }
    } catch (e, s) {
      /// find() is not async, so give the error in the Future, like
      /// findOrFail()
      return Future<T?>.error(e, s);
    }
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
  /// with no rows, `lastPage` is 0, or 1 with
  /// [OrmFlags.lastPageAtLeastOne].
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
      lastPage: rowCount == 0 && SqlQueryBuilder().flags.lastPageAtLeastOne
          ? 1
          : (rowCount / perPage).ceil(),
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

  /// a page of rows after (or before) a cursor. It is
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

    /// the key of this table only: `author.id` on a join is not it
    bool hasKey = false;
    for ((String, bool) c in columns) {
      if (_isOwnKey(c.$1)) hasKey = true;
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

  /// true when [column] is the primary key of this table: `id`,
  /// `blog.id`, or `alias.id` when the table has an alias
  bool _isOwnKey(String column) {
    String key = _keyOf(primaryKey);
    return column == primaryKey ||
        column == key ||
        column == '$tableName.$key' ||
        (tableAlias != null && column == '$tableAlias.$key');
  }

  /// the kind of a cursor value: n (number), s (text), d (date), or
  /// null when it can not be in a cursor
  static String? _kindOf(dynamic value) {
    if (value is num) return 'n';
    if (value is String) return 's';
    if (value is DateTime) return 'd';
    return null;
  }

  /// true when each cursor value has the kind of the same column in the
  /// rows. no rows: nothing to check. A null in the rows is skipped, so a
  /// null in the first row does not make a good cursor give page 1 (a
  /// client would loop on page 1).
  static bool _cursorFits(
    List<dynamic> rows,
    List<(String, bool)> columns,
    List<dynamic> values,
  ) {
    for (int i = 0; i < columns.length; i++) {
      for (dynamic row in rows) {
        dynamic value = _valueOfRow(row, _keyOf(columns[i].$1));
        if (value == null) continue;
        if (_kindOf(value) != _kindOf(values[i])) return false;
        break;
      }
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

  /// the first row, or null. The same as [getFirst].
  ///
  /// ```
  /// Blog? blog = await Blog().where('status', 'active').first();
  /// ```
  Future<T?> first() => getFirst();

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

  /// the only row of the query. it throws a [ModelNotFoundException] when
  /// no row matches, and a [MultipleRecordsFoundException] when more than
  /// one row matches. it reads 2 rows at most.
  ///
  /// ```
  /// Blog blog = await Blog().where('slug', slug).sole();
  /// ```
  Future<T> sole() async {
    List<T> rows = await queryBuilder.limit(2).get();
    if (rows.isEmpty) throw ModelNotFoundException(tableName);
    if (rows.length > 1) throw MultipleRecordsFoundException(tableName);
    return rows.first;
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
  /// it throws a [StateError] on a union() query: only the first part
  /// would get the select.
  Future<List<Map<String, dynamic>>> _pluckRows(List<String> columns) async {
    checkNoUnion(queryBuilder, 'pluck(), pluckMap() and valueOf');
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
    await for (List<T> rows in _pagesByOffset(size)) {
      if (await callback(rows) == false) return false;
    }
    return true;
  }

  /// the pages of [chunk]: [size] rows each, by LIMIT and OFFSET.
  /// [keepLimit]: start at the offset() of the query and stop after its
  /// limit(). chunk() sets its own, as before.
  Stream<List<T>> _pagesByOffset(int size, {bool keepLimit = false}) async* {
    _checkChunkSize(size);
    QueryBuilder<T> qb = queryBuilder;
    var (int? limit, int? offset) = keepLimit
        ? limitAndOffset(qb)
        : (null, null);
    String key = _qualified(primaryKey);
    String orderBy = qb.getOrderByQuery();
    if (orderBy.isEmpty) {
      qb.orderBy(key);
    } else if (!qb.hasUnion &&
        !qb.hasFromSub &&
        !qb.isDistinct &&
        qb.getGroupByQuery().isEmpty &&
        !orderBy.contains(helper.wrap(key))) {
      /// the primary key last: rows with the same value of the other
      /// order columns keep one order, so no row is read twice or
      /// skipped. ponytail: not with distinct or groupBy, where the
      /// database may not allow it.
      qb.orderBy(key);
    }
    int read = 0;
    for (int page = 0; ; page++) {
      int take = limit == null ? size : min(size, limit - read);
      if (take <= 0) return;
      List<T> rows = await qb
          .limit(take)
          .offset((offset ?? 0) + page * size)
          .get();
      if (rows.isEmpty) return;
      read += rows.length;
      yield rows;
      if (rows.length < take) return;
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
    await for (List<T> rows in _pagesById(size, column, 'chunkById', false)) {
      if (await callback(rows) == false) return false;
    }
    return true;
  }

  /// the pages of [chunkById]: [size] rows each, `WHERE column > last`.
  /// [keepLimit]: start at the offset() of the query and stop after its
  /// limit(). chunkById() sets its own, as before.
  Stream<List<T>> _pagesById(
    int size,
    String? column,
    String method,
    bool keepLimit,
  ) async* {
    _checkNoSub(method);
    _checkChunkSize(size);
    QueryBuilder<T> qb = queryBuilder;
    if (qb.getOrderByQuery().isNotEmpty) {
      throw StateError(
        '$method() orders by the id column itself. '
        'Remove orderBy() from the query.',
      );
    }
    String name = column ?? primaryKey;
    String qualified = _qualified(name);
    String key = name.split('.').last;
    var (int? limit, int? offset) = keepLimit
        ? limitAndOffset(qb)
        : (null, null);
    qb.orderBy(qualified).offset(offset ?? 0);
    bool hasLastWhere = false;
    int read = 0;
    while (true) {
      int take = limit == null ? size : min(size, limit - read);
      if (take <= 0) return;
      List<T> rows = await qb.limit(take).get();
      if (rows.isEmpty) return;
      read += rows.length;
      yield rows;
      if (rows.length < take) return;

      /// the offset is for the first page only: the next pages start
      /// after the last value
      qb.offset(0);
      dynamic last = _valueOfRow(rows.last, key);
      if (last == null) {
        throw StateError('$method() needs the "$key" column in each row');
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

  /// the rows of this query one by one, read [chunkSize] rows at a time,
  /// so a big table does not fill the memory. Relations of `preload()`
  /// are loaded for each chunk.
  ///
  /// - with no orderBy() it reads by the primary key, like [lazyById]: each
  ///   chunk is `WHERE id > last id`. it is safe when you change or delete
  ///   rows while you read. the rows must have the primary key.
  /// - with an orderBy() (or on a union() or fromSub() query) it pages
  ///   with LIMIT and OFFSET, like [chunk], so the order is kept. The
  ///   primary key is added as the last order column, so rows with the
  ///   same order value are not read twice or skipped.
  /// - limit() and offset() of the query are kept: it starts at the
  ///   offset and stops after the limit (by LIMIT and OFFSET paging).
  ///
  /// Stop reading (eg. `break` in `await for`, or `take(3)`) to stop the
  /// queries. Use [cursor] for one query with no paging.
  ///
  /// ```
  /// await for (User user in User().where('active', true).lazy()) {
  ///   await sendMail(user);
  /// }
  /// ```
  Stream<T> lazy({int chunkSize = 1000}) async* {
    QueryBuilder<T> qb = queryBuilder;
    var (int? limit, int? offset) = limitAndOffset(qb);
    Stream<List<T>> pages =
        qb.getOrderByQuery().isEmpty &&
            !qb.hasUnion &&
            !qb.hasFromSub &&
            limit == null &&
            offset == null
        ? _pagesById(chunkSize, null, 'lazy', true)
        : _pagesByOffset(chunkSize, keepLimit: true);
    await for (List<T> rows in pages) {
      for (T row in rows) {
        yield row;
      }
    }
  }

  /// like [lazy], but always by [column] (the primary key by default):
  /// each chunk is `WHERE column > last value`, ordered by [column]. the
  /// column must be unique, and the rows must have it. it throws a
  /// [StateError] when the query has an orderBy(), and on a union() or
  /// fromSub() query. limit() and offset() of the query are kept.
  ///
  /// ```
  /// await for (User user in User().lazyById(chunkSize: 500)) {
  ///   await user.delete();
  /// }
  /// ```
  Stream<T> lazyById({int chunkSize = 1000, String? column}) async* {
    await for (List<T> rows in _pagesById(
      chunkSize,
      column,
      'lazyById',
      true,
    )) {
      for (T row in rows) {
        yield row;
      }
    }
  }

  /// the rows of this query one by one, from ONE query. the driver reads
  /// the rows from the database [chunkSize] at a time, only when you are
  /// ready for them, so a big result does not fill the memory:
  /// - Postgres: a server-side portal. MySQL: the rows as they come.
  /// - SQLite: a statement cursor, also with `background` on.
  ///
  /// Each row is a model with its casts, like get(). It works in a
  /// transaction. Stop reading (eg. `break`, or `take(3)`) to stop the
  /// query. `cancelWith()` works on Postgres and MySQL.
  ///
  /// Relations of `preload()` are loaded for each chunk. On Postgres and
  /// MySQL inside a transaction this throws a [StateError] then: the
  /// transaction has one connection, and it is busy with the cursor. Use
  /// [lazy] there. For the same reason, do not run other queries of the
  /// same transaction inside the loop on Postgres or MySQL: they wait
  /// until the cursor ends.
  ///
  /// Query listeners and the slow query log see the query once, when the
  /// first chunk comes (or the end, for no rows). Its time is the time to
  /// the first chunk, not to the last row.
  ///
  /// A driver of your own that does not override [DBDriver.stream] reads
  /// all rows at once.
  ///
  /// ```
  /// await for (Order order in Order().where('year', 2025).cursor()) {
  ///   total += order.amount;
  /// }
  /// ```
  Stream<T> cursor({int chunkSize = 1000}) async* {
    _checkChunkSize(chunkSize);
    QueryBuilder<T> qb = queryBuilder;
    DBDriver driver = dbDriver;
    if (qb.getPreload().isNotEmpty &&
        driver.getName() != Driver.sqlite &&
        DBDriver.inTransaction) {
      throw StateError(
        'cursor() can not load relations inside a transaction on '
        'Postgres or MySQL. Use lazy(), or leave out preload().',
      );
    }
    String sql = _buildQuery();
    Map<String, dynamic> values = substitutionValues;
    if (shouldDebug) logger.log(sql, values, connection);
    Stream<List<Map<String, dynamic>>> chunks = DBDriver.withCancelToken(
      qb.cancelToken,
      () =>
          driver.stream(sql, substitutionValues: values, chunkSize: chunkSize),
    );
    SqlQueryBuilder orm = SqlQueryBuilder();
    Stopwatch? watch = orm.startQueryWatch(connection);
    await for (List<Map<String, dynamic>> rows in chunks) {
      if (watch != null) {
        await orm.timeQuery(
          Future<void>.value(),
          watch,
          sql,
          values,
          connection,
        );
        watch = null;
      }
      for (T row in _typed(await helper.formatResult(rows))) {
        yield row;
      }
    }
    // an empty result: no chunk came
    if (watch != null) {
      await orm.timeQuery(Future<void>.value(), watch, sql, values, connection);
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
    return '${tableAlias ?? tableName}.$column';
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

  /// run [callback] on the query only when [condition] is false, else
  /// run [otherwise] when it is given. The opposite of [when].
  ///
  /// ```
  /// List<Blog> blogs = await Blog()
  ///     .unless(showDrafts, (QueryBuilder<Blog> q) {
  ///       q.where('status', 'published');
  ///     })
  ///     .get();
  /// ```
  QueryBuilder<T> unless(
    bool condition,
    void Function(QueryBuilder<T> query) callback, [
    void Function(QueryBuilder<T> query)? otherwise,
  ]) {
    return when(!condition, callback, otherwise);
  }

  /// run [callback] with [value] when [value] is not null, else run
  /// [otherwise] when it is given. The callback gets the value, and the value is not null in it.
  ///
  /// ```
  /// List<Blog> blogs = await Blog()
  ///     .whenValue(req.query['status'], (QueryBuilder<Blog> q, status) {
  ///       q.where('status', status);
  ///     })
  ///     .get();
  /// ```
  QueryBuilder<T> whenValue<V>(
    V? value,
    void Function(QueryBuilder<T> query, V value) callback, [
    void Function(QueryBuilder<T> query)? otherwise,
  ]) {
    if (value != null) {
      callback(queryBuilder, value);
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
  /// The values are put in as they are, with no quotes, like
  /// `status = active`. Use [toRawSql] for SQL with quoted values.
  String toSql() => _withValues((dynamic value) => value.toString());

  /// the SQL with each value quoted for the database. It is for logs and debugging: run queries with
  /// bound values, not with this text.
  ///
  /// ```
  /// // SELECT * FROM "blog" WHERE "status" = 'it''s'
  /// String sql = Blog().where('status', "it's").toRawSql();
  /// ```
  String toRawSql() {
    SchemaGrammar grammar = SchemaGrammar.of(dbDriver.getName());
    return _withValues((dynamic value) => grammar.literal(value));
  }

  /// the SQL with each `@name` replaced by [show] of its value
  String _withValues(String Function(dynamic value) show) {
    String q = _buildQuery();
    Map<String, dynamic> values = queryBuilder.substitutionValues;
    return q.replaceAllMapped(RegExp(r'@(\w+)'), (Match m) {
      String key = m.group(1)!;
      return values.containsKey(key) ? show(values[key]) : m.group(0)!;
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
