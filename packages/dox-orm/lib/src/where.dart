import 'drivers/db_driver.dart';
import 'query_builder.dart';
import 'shared_mixin.dart';

/// the default of the optional where() args. It tells a missing arg
/// from a null value, so `where('a', '!=', null)` is the 3 args form.
class _Missing {
  const _Missing();
}

const _Missing _missing = _Missing();

mixin Where<T> implements SharedMixin<T> {
  /// made on the first where, most rows never need it
  List<String>? _wheres;

  /// number of whereExists() subqueries so far, for their param keys
  int _subqueryCount = 0;

  /// true when a where condition was added
  bool get hasWhere => _wheres != null;

  /// number of where conditions so far
  int get whereCount => _wheres?.length ?? 0;

  /// puts the conditions from index [from] to the end in one bracket,
  /// joined to the ones before with AND
  void groupWheres(int from) => _wrapFrom(from, 'AND', '');

  /// puts the conditions from index [from] to the end in one bracket,
  /// with [prefix] (eg. `NOT `) before it, joined to the ones before
  /// with [type]. nothing happens when no condition was added.
  void _wrapFrom(int from, String type, String prefix) {
    List<String>? wheres = _wheres;
    if (wheres == null || wheres.length <= from) return;
    List<String> added = wheres.sublist(from);
    if (from > 0) added[0] = added[0].replaceFirst(_leadingType, '');
    wheres.removeRange(from, wheres.length);
    String group = '$prefix(${added.join(' ')})';
    wheres.add(from == 0 ? group : '$type $group');
  }

  static final RegExp _leadingType = RegExp(r'^(AND|OR) ');

  String getWhereQuery() {
    queryBuilder.applyGlobalScopes();
    List<String>? wheres = _wheres;

    /// wrap user conditions in brackets so an OR can not skip the
    /// soft delete check.
    if (isSoftDeletes && !withTrashed) {
      String softDelete =
          "${helper.wrap('${tableAlias ?? tableName}.deleted_at')} IS NULL";
      if (wheres == null) {
        return " WHERE $softDelete";
      }
      return " WHERE (${wheres.join(' ')}) AND $softDelete";
    }
    if (wheres != null) {
      return " WHERE ${wheres.join(' ')}";
    }
    return '';
  }

  /// where condition. With 2 args it is `column = value`, with 3 args the
  /// middle one is the operator. A null value becomes `IS NULL` with `=`
  /// (or 2 args) and `IS NOT NULL` with `!=` or `<>`. Other operators
  /// with null throw an [ArgumentError].
  ///
  /// ```
  /// List blogs = await where('id', 1).get();
  /// List blogs = await where('views', '>', 10).get();
  /// List blogs = await where('slug', '!=', null).get();
  /// ```
  QueryBuilder<T> where(
    String arg1, [
    dynamic arg2 = _missing,
    dynamic arg3 = _missing,
  ]) {
    return _query('AND', arg1, arg2, arg3);
  }

  /// or where condition, see [where]
  ///
  /// ```
  /// List blogs = await where('id', 1).orWhere('id', 2).get();
  /// List blogs = await where('id', 1).orWhere('slug', '!=', null).get();
  /// ```
  QueryBuilder<T> orWhere(
    String arg1, [
    dynamic arg2 = _missing,
    dynamic arg3 = _missing,
  ]) {
    return _query('OR', arg1, arg2, arg3);
  }

  /// where conditions in one bracket. [callback] gets this query and
  /// adds where conditions to it. Groups can nest. An empty group adds
  /// nothing.
  ///
  /// ```
  /// // WHERE "status" = @status_p0 AND ("views" > @views_p1 OR "pinned" = @pinned_p2)
  /// List blogs = await Blog()
  ///     .where('status', 'active')
  ///     .whereGroup((QueryBuilder<Blog> q) {
  ///       q.where('views', '>', 100).orWhere('pinned', true);
  ///     })
  ///     .get();
  /// ```
  /// ponytail: [callback] gets the same query, so only add where
  /// conditions in it. eg. an orderBy() in it is on the whole query.
  QueryBuilder<T> whereGroup(void Function(QueryBuilder<T> query) callback) {
    return _group('AND', '', callback);
  }

  /// or where conditions in one bracket, see [whereGroup]
  ///
  /// ```
  /// // WHERE "id" = @id_p0 OR ("status" = @status_p1 AND "views" > @views_p2)
  /// List blogs = await Blog()
  ///     .where('id', 1)
  ///     .orWhereGroup((QueryBuilder<Blog> q) {
  ///       q.where('status', 'active').where('views', '>', 100);
  ///     })
  ///     .get();
  /// ```
  QueryBuilder<T> orWhereGroup(void Function(QueryBuilder<T> query) callback) {
    return _group('OR', '', callback);
  }

  /// where the conditions in the bracket are not true, see [whereGroup]
  ///
  /// ```
  /// // WHERE NOT ("status" = @status_p0 OR "views" < @views_p1)
  /// List blogs = await Blog()
  ///     .whereNot((QueryBuilder<Blog> q) {
  ///       q.where('status', 'draft').orWhere('views', '<', 10);
  ///     })
  ///     .get();
  /// ```
  /// A row where a column in the bracket is null can match neither the
  /// bracket nor NOT of it (sql null rules).
  QueryBuilder<T> whereNot(void Function(QueryBuilder<T> query) callback) {
    return _group('AND', 'NOT ', callback);
  }

  /// or where the conditions in the bracket are not true, see [whereNot]
  ///
  /// ```
  /// List blogs = await Blog()
  ///     .where('id', 1)
  ///     .orWhereNot((QueryBuilder<Blog> q) => q.where('status', 'draft'))
  ///     .get();
  /// ```
  QueryBuilder<T> orWhereNot(void Function(QueryBuilder<T> query) callback) {
    return _group('OR', 'NOT ', callback);
  }

  /// where column is between [values] (from and to, both included)
  ///
  /// ```
  /// List blogs = await Blog().whereBetween('views', [10, 100]).get();
  /// ```
  QueryBuilder<T> whereBetween(String column, List<dynamic> values) {
    return _between('AND', column, values, false);
  }

  /// or where column is between [values], see [whereBetween]
  ///
  /// ```
  /// List blogs = await Blog()
  ///     .where('id', 1)
  ///     .orWhereBetween('views', [10, 100])
  ///     .get();
  /// ```
  QueryBuilder<T> orWhereBetween(String column, List<dynamic> values) {
    return _between('OR', column, values, false);
  }

  /// where column is not between [values] (from and to)
  ///
  /// ```
  /// List blogs = await Blog().whereNotBetween('views', [10, 100]).get();
  /// ```
  QueryBuilder<T> whereNotBetween(String column, List<dynamic> values) {
    return _between('AND', column, values, true);
  }

  /// or where column is not between [values], see [whereNotBetween]
  ///
  /// ```
  /// List blogs = await Blog()
  ///     .where('id', 1)
  ///     .orWhereNotBetween('views', [10, 100])
  ///     .get();
  /// ```
  QueryBuilder<T> orWhereNotBetween(String column, List<dynamic> values) {
    return _between('OR', column, values, true);
  }

  /// compare two columns. With 2 args it is `first = second`, with 3 args
  /// the middle one is the operator. Both are column names, not values.
  ///
  /// ```
  /// List blogs = await Blog().whereColumn('created_at', 'updated_at').get();
  /// List blogs = await Blog().whereColumn('updated_at', '>', 'created_at').get();
  /// ```
  QueryBuilder<T> whereColumn(String first, String arg2, [String? arg3]) {
    return _column('AND', first, arg2, arg3);
  }

  /// or compare two columns, see [whereColumn]
  ///
  /// ```
  /// List blogs = await Blog()
  ///     .where('id', 1)
  ///     .orWhereColumn('updated_at', '>', 'created_at')
  ///     .get();
  /// ```
  QueryBuilder<T> orWhereColumn(String first, String arg2, [String? arg3]) {
    return _column('OR', first, arg2, arg3);
  }

  /// where the subquery on [table] has a row. [callback] gets a new
  /// query on [table] and adds where conditions (and joins) to it.
  ///
  /// ```
  /// // WHERE EXISTS (SELECT 1 FROM "post" WHERE "post"."user_id" = "user"."id")
  /// List users = await User()
  ///     .whereExists('post', (QueryBuilder<Map<String, dynamic>> q) {
  ///       q.whereColumn('post.user_id', 'user.id');
  ///     })
  ///     .get();
  /// ```
  /// ponytail: the subquery has no global scopes and no soft deletes,
  /// add those conditions in [callback], eg. `q.whereNull('deleted_at')`.
  QueryBuilder<T> whereExists(
    String table,
    void Function(QueryBuilder<Map<String, dynamic>> query) callback,
  ) {
    return _exists('AND', table, callback, false);
  }

  /// or where the subquery has a row, see [whereExists]
  ///
  /// ```
  /// List users = await User()
  ///     .where('admin', true)
  ///     .orWhereExists('post', (QueryBuilder<Map<String, dynamic>> q) {
  ///       q.whereColumn('post.user_id', 'user.id');
  ///     })
  ///     .get();
  /// ```
  QueryBuilder<T> orWhereExists(
    String table,
    void Function(QueryBuilder<Map<String, dynamic>> query) callback,
  ) {
    return _exists('OR', table, callback, false);
  }

  /// where the subquery has no row, see [whereExists]
  ///
  /// ```
  /// List users = await User()
  ///     .whereNotExists('post', (QueryBuilder<Map<String, dynamic>> q) {
  ///       q.whereColumn('post.user_id', 'user.id');
  ///     })
  ///     .get();
  /// ```
  QueryBuilder<T> whereNotExists(
    String table,
    void Function(QueryBuilder<Map<String, dynamic>> query) callback,
  ) {
    return _exists('AND', table, callback, true);
  }

  /// or where the subquery has no row, see [whereExists]
  ///
  /// ```
  /// List users = await User()
  ///     .where('admin', true)
  ///     .orWhereNotExists('post', (QueryBuilder<Map<String, dynamic>> q) {
  ///       q.whereColumn('post.user_id', 'user.id');
  ///     })
  ///     .get();
  /// ```
  QueryBuilder<T> orWhereNotExists(
    String table,
    void Function(QueryBuilder<Map<String, dynamic>> query) callback,
  ) {
    return _exists('OR', table, callback, true);
  }

  /// where column matches the like pattern [value] (`%` is any text,
  /// `_` is one character). It does not care about case, unless
  /// [caseSensitive] is true:
  /// - postgres: `ILIKE`, or `LIKE` when case sensitive.
  /// - mysql: `LIKE`, it follows the column collation (the default ones
  ///   do not care about case), or `LIKE BINARY` when case sensitive.
  /// - sqlite: `LIKE` (does not care about case for ASCII letters only),
  ///   or `GLOB` when case sensitive (the pattern is changed to glob).
  ///
  /// ```
  /// List blogs = await Blog().whereLike('title', '%dart%').get();
  /// List blogs = await Blog()
  ///     .whereLike('title', 'Dart%', caseSensitive: true)
  ///     .get();
  /// ```
  QueryBuilder<T> whereLike(
    String column,
    String value, {
    bool caseSensitive = false,
  }) {
    return _like('AND', column, value, caseSensitive, false);
  }

  /// or where column matches the like pattern, see [whereLike]
  ///
  /// ```
  /// List blogs = await Blog()
  ///     .where('id', 1)
  ///     .orWhereLike('title', '%dart%')
  ///     .get();
  /// ```
  QueryBuilder<T> orWhereLike(
    String column,
    String value, {
    bool caseSensitive = false,
  }) {
    return _like('OR', column, value, caseSensitive, false);
  }

  /// where column does not match the like pattern, see [whereLike]
  ///
  /// ```
  /// List blogs = await Blog().whereNotLike('title', '%draft%').get();
  /// ```
  QueryBuilder<T> whereNotLike(
    String column,
    String value, {
    bool caseSensitive = false,
  }) {
    return _like('AND', column, value, caseSensitive, true);
  }

  /// or where column does not match the like pattern, see [whereLike]
  ///
  /// ```
  /// List blogs = await Blog()
  ///     .where('id', 1)
  ///     .orWhereNotLike('title', '%draft%')
  ///     .get();
  /// ```
  QueryBuilder<T> orWhereNotLike(
    String column,
    String value, {
    bool caseSensitive = false,
  }) {
    return _like('OR', column, value, caseSensitive, true);
  }

  /// where in condition. an empty list match no rows.
  ///
  /// ```
  /// List blogs = await whereIn('id', [1, 2, 3]).get();
  /// ```
  QueryBuilder<T> whereIn(String column, List<dynamic> values) {
    return _whereIn('AND', column, values, false);
  }

  /// or where in condition. an empty list match no rows.
  ///
  /// ```
  /// List blogs = await where('id', 1).orWhereIn('id', [2, 3]).get();
  /// ```
  QueryBuilder<T> orWhereIn(String column, List<dynamic> values) {
    return _whereIn('OR', column, values, false);
  }

  /// where not in condition. an empty list match all rows.
  ///
  /// ```
  /// List blogs = await whereNotIn('id', [1, 2, 3]).get();
  /// ```
  QueryBuilder<T> whereNotIn(String column, List<dynamic> values) {
    return _whereIn('AND', column, values, true);
  }

  /// or where not in condition. an empty list match all rows.
  ///
  /// ```
  /// List blogs = await where('id', 1).orWhereNotIn('id', [2, 3]).get();
  /// ```
  QueryBuilder<T> orWhereNotIn(String column, List<dynamic> values) {
    return _whereIn('OR', column, values, true);
  }

  /// where column is null
  ///
  /// ```
  /// List blogs = await whereNull('deleted_at').get();
  /// ```
  QueryBuilder<T> whereNull(String column) {
    return _rawQuery('AND', '${helper.wrap(column)} IS NULL');
  }

  /// or where column is null
  ///
  /// ```
  /// List blogs = await where('id', 1).orWhereNull('slug').get();
  /// ```
  QueryBuilder<T> orWhereNull(String column) {
    return _rawQuery('OR', '${helper.wrap(column)} IS NULL');
  }

  /// where column is not null
  ///
  /// ```
  /// List blogs = await whereNotNull('slug').get();
  /// ```
  QueryBuilder<T> whereNotNull(String column) {
    return _rawQuery('AND', '${helper.wrap(column)} IS NOT NULL');
  }

  /// or where column is not null
  ///
  /// ```
  /// List blogs = await where('id', 1).orWhereNotNull('slug').get();
  /// ```
  QueryBuilder<T> orWhereNotNull(String column) {
    return _rawQuery('OR', '${helper.wrap(column)} IS NOT NULL');
  }

  /// where raw condition
  ///
  /// ```
  /// List blogs = await whereRaw('id = @id', {"id" : 1}).get();
  /// ```
  QueryBuilder<T> whereRaw(String rawQuery, [dynamic params]) {
    return _rawQuery('AND', rawQuery, params);
  }

  /// where raw condition
  ///
  /// ```
  /// List blogs = await orWhereRaw('id = @id', {"id" : 1}).get();
  /// ```
  QueryBuilder<T> orWhereRaw(String rawQuery, [dynamic params]) {
    return _rawQuery('OR', rawQuery, params);
  }

  QueryBuilder<T> _whereIn(
    String type,
    String column,
    List<dynamic> values,
    bool not,
  ) {
    /// `in ()` is not valid sql, so an empty list becomes
    /// "no rows" for IN and "all rows" for NOT IN
    if (values.isEmpty) {
      return _rawQuery(type, not ? '1 = 1' : '1 = 0');
    }

    /// postgres: one array param, so every list size gives the same sql
    if (dbDriver.getName() == Driver.postgres && _sameType(values)) {
      String columnKey = helper.parseColumnKey(column);
      addSubstitutionValues(columnKey, values.toList());
      return _rawQuery(
        type,
        "${helper.wrap(column)} ${not ? '<> ALL' : '= ANY'}($columnKey)",
      );
    }
    List<String> keys = <String>[];
    for (dynamic value in values) {
      String columnKey = helper.parseColumnKey(column);
      keys.add(columnKey);
      addSubstitutionValues(columnKey, value);
    }
    String operator = not ? 'NOT IN' : 'IN';
    return _rawQuery(
      type,
      "${helper.wrap(column)} $operator (${keys.join(',')})",
    );
  }

  /// true when every value is an int, or every value is a String.
  /// postgres reads these as an array of the column type. other lists
  /// (mixed types, nulls) keep one param per value.
  static bool _sameType(List<dynamic> values) {
    return values.every(_isInt) || values.every(_isString);
  }

  static bool _isInt(dynamic value) => value is int;

  static bool _isString(dynamic value) => value is String;

  QueryBuilder<T> _query(
    String type,
    String column,
    dynamic arg2,
    dynamic arg3,
  ) {
    if (identical(arg2, _missing)) {
      throw ArgumentError.value(column, 'where', 'needs a value');
    }
    String condition = '=';
    dynamic value = arg2;
    if (!identical(arg3, _missing)) {
      condition = helper.operator(arg2);
      value = arg3;
    }

    /// `= null` never match in sql, use IS NULL
    if (value == null) {
      return _rawQuery(type, '${helper.wrap(column)} ${_nullCheck(condition)}');
    }
    String columnKey = helper.parseColumnKey(column);
    addSubstitutionValues(columnKey, value);
    return _rawQuery(type, "${helper.wrap(column)} $condition $columnKey");
  }

  /// `IS NULL` for `=` and `IS NOT NULL` for `!=` and `<>`
  static String _nullCheck(String operator) {
    switch (operator) {
      case '=':
        return 'IS NULL';
      case '!=':
      case '<>':
        return 'IS NOT NULL';
    }
    throw ArgumentError.value(
      operator,
      'operator',
      'can not compare with null, use =, != or <>',
    );
  }

  QueryBuilder<T> _group(
    String type,
    String prefix,
    void Function(QueryBuilder<T> query) callback,
  ) {
    int from = whereCount;
    callback(queryBuilder);
    _wrapFrom(from, type, prefix);
    return queryBuilder;
  }

  QueryBuilder<T> _between(
    String type,
    String column,
    List<dynamic> values,
    bool not,
  ) {
    if (values.length != 2 || values[0] == null || values[1] == null) {
      throw ArgumentError.value(
        values,
        'values',
        'needs two values that are not null',
      );
    }
    String fromKey = helper.parseColumnKey(column);
    addSubstitutionValues(fromKey, values[0]);
    String toKey = helper.parseColumnKey(column);
    addSubstitutionValues(toKey, values[1]);
    String operator = not ? 'NOT BETWEEN' : 'BETWEEN';
    return _rawQuery(
      type,
      '${helper.wrap(column)} $operator $fromKey AND $toKey',
    );
  }

  QueryBuilder<T> _column(
    String type,
    String first,
    String arg2,
    String? arg3,
  ) {
    String operator = arg3 == null ? '=' : helper.operator(arg2);
    String second = arg3 ?? arg2;
    return _rawQuery(
      type,
      '${helper.wrap(first)} $operator ${helper.wrap(second)}',
    );
  }

  QueryBuilder<T> _exists(
    String type,
    String table,
    void Function(QueryBuilder<Map<String, dynamic>> query) callback,
    bool not,
  ) {
    QueryBuilder<Map<String, dynamic>> q = QueryBuilder.table(table);
    q.connection = connection;

    /// the prefix of this query goes first, so a subquery in a subquery
    /// has its own keys too. the count keeps the sql the same each time.
    q.helper.keyPrefix = '${helper.keyPrefix}dox_ex${_subqueryCount++}_';
    callback(q);
    String sql =
        'SELECT 1 FROM ${q.helper.wrap(q.tableName)}'
        '${q.helper.getCommonQuery(isCountQuery: true)}';
    substitutionValues.addAll(q.substitutionValues);
    return _rawQuery(type, "${not ? 'NOT EXISTS' : 'EXISTS'} ($sql)");
  }

  QueryBuilder<T> _like(
    String type,
    String column,
    String value,
    bool caseSensitive,
    bool not,
  ) {
    String operator = 'LIKE';
    dynamic param = value;
    Driver driver = dbDriver.getName();
    if (driver == Driver.postgres && !caseSensitive) {
      operator = 'ILIKE';
    } else if (driver == Driver.mysql && caseSensitive) {
      operator = 'LIKE BINARY';
    } else if (driver == Driver.sqlite && caseSensitive) {
      operator = 'GLOB';
      param = _likeToGlob(value);
    }
    String columnKey = helper.parseColumnKey(column);
    addSubstitutionValues(columnKey, param);
    return _rawQuery(
      type,
      "${helper.wrap(column)} ${not ? 'NOT ' : ''}$operator $columnKey",
    );
  }

  /// a like pattern as a sqlite glob pattern: the glob characters
  /// `*`, `?` and `[` are made plain, then `%` is `*` and `_` is `?`
  static String _likeToGlob(String value) {
    StringBuffer out = StringBuffer();
    for (int i = 0; i < value.length; i++) {
      String char = value[i];
      switch (char) {
        case '*':
        case '?':
        case '[':
          out.write('[$char]');
        case '%':
          out.write('*');
        case '_':
          out.write('?');
        default:
          out.write(char);
      }
    }
    return out.toString();
  }

  QueryBuilder<T> _rawQuery(String type, String rawQuery, [dynamic params]) {
    List<String>? wheres = _wheres;
    if (wheres == null) {
      _wheres = <String>[rawQuery];
    } else {
      wheres.add("$type $rawQuery");
    }
    if (params is Map<String, dynamic>) {
      params.forEach((String key, dynamic value) {
        addSubstitutionValues(key, value);
      });
    }
    return queryBuilder;
  }
}
