import 'query_builder.dart';
import 'shared_mixin.dart';
import 'where.dart' show missingArg, nullCheck;

/// the conditions of a join with a callback, see `join()`. each call adds
/// one condition, joined to the ones before with AND (or OR for orOn()
/// and orWhere()).
///
/// ```
/// List users = await User()
///     .join('contact', (JoinClause j) {
///       j
///           .on('contact.user_id', 'user.id')
///           .orOn('contact.owner_id', 'user.id')
///           .where('contact.active', true);
///     })
///     .get();
/// ```
class JoinClause {
  JoinClause._(this._query);

  /// the query of the join: values go into it
  final QueryBuilder<dynamic> _query;

  final List<String> _conditions = <String>[];

  /// `first = second`, or `first operator second` with 3 args. both are
  /// column names, like join().
  JoinClause on(String first, String arg2, [String? arg3]) {
    return _on('AND', first, arg2, arg3);
  }

  /// or `first = second`, see [on]
  JoinClause orOn(String first, String arg2, [String? arg3]) {
    return _on('OR', first, arg2, arg3);
  }

  /// `column = value`, or `column operator value` with 3 args, like
  /// where(). the value is bound. a null value is `IS NULL` with `=` and
  /// `IS NOT NULL` with `!=` or `<>`.
  JoinClause where(String column, dynamic arg2, [dynamic arg3 = missingArg]) {
    return _where('AND', column, arg2, arg3);
  }

  /// or `column = value`, see [where]
  JoinClause orWhere(String column, dynamic arg2, [dynamic arg3 = missingArg]) {
    return _where('OR', column, arg2, arg3);
  }

  JoinClause _on(String type, String first, String arg2, String? arg3) {
    String operator = arg3 == null ? '=' : _query.helper.operator(arg2);
    String second = arg3 ?? arg2;
    return _add(
      type,
      '${_query.helper.wrap(first)} $operator ${_query.helper.wrap(second)}',
    );
  }

  JoinClause _where(String type, String column, dynamic arg2, dynamic arg3) {
    String operator = '=';
    dynamic value = arg2;
    if (!identical(arg3, missingArg)) {
      operator = _query.helper.operator(arg2);
      value = arg3;
    }
    String name = _query.helper.wrap(column);
    if (value == null) {
      return _add(type, '$name ${nullCheck(operator)}');
    }
    String key = _query.helper.parseColumnKey(column);
    _query.addSubstitutionValues(key, value);
    return _add(type, '$name $operator $key');
  }

  JoinClause _add(String type, String condition) {
    _conditions.add(_conditions.isEmpty ? condition : '$type $condition');
    return this;
  }
}

mixin Join<T> implements SharedMixin<T> {
  /// made on the first join, most rows never need it
  List<String>? _joins;

  String getJoinQuery() {
    List<String>? joins = _joins;
    if (joins != null) {
      return " ${joins.join(' ')}";
    }
    return '';
  }

  /// left join
  ///
  /// ```
  /// List admins = await Admin().leftJoin('admin_info', 'admin_info.admin_id', 'admin.id').get();
  /// ```
  QueryBuilder<T> leftJoin(
    String arg1,
    Object arg2, [
    String? arg3,
    dynamic arg4,
  ]) {
    return _query('LEFT JOIN', arg1, arg2, arg3, arg4);
  }

  /// right join
  ///
  /// ```
  /// List admins = await Admin().rightJoin('admin_info', 'admin_info.admin_id', 'admin.id').get();
  /// ```
  QueryBuilder<T> rightJoin(
    String arg1,
    Object arg2, [
    String? arg3,
    dynamic arg4,
  ]) {
    return _query('RIGHT JOIN', arg1, arg2, arg3, arg4);
  }

  /// join
  ///
  /// ```
  /// List admins = await Admin().join('admin_info', 'admin_info.admin_id', 'admin.id').get();
  /// ```
  ///
  /// With a callback in place of the columns, the join can have many
  /// conditions, see [JoinClause]. It works the same for leftJoin() and
  /// rightJoin(). Give the callback arg its type: `(JoinClause j) {...}`.
  ///
  /// ```
  /// // JOIN "contact" on "contact"."user_id" = "user"."id"
  /// //   AND "contact"."active" = @contactactive_p0
  /// List users = await User()
  ///     .join('contact', (JoinClause j) {
  ///       j.on('contact.user_id', 'user.id').where('contact.active', true);
  ///     })
  ///     .get();
  /// ```
  QueryBuilder<T> join(String arg1, Object arg2, [String? arg3, dynamic arg4]) {
    return _query('JOIN', arg1, arg2, arg3, arg4);
  }

  /// cross join: each row with each row of [table]
  ///
  /// ```
  /// // SELECT * FROM "size" CROSS JOIN "color"
  /// List rows = await QueryBuilder.table('size').crossJoin('color').get();
  /// ```
  QueryBuilder<T> crossJoin(String table) {
    (_joins ??= <String>[]).add('CROSS JOIN ${helper.wrap(table)}');
    return queryBuilder;
  }

  /// join the rows of a sub query, named [alias]. the values of [query]
  /// are bound, like in this query. the other args are like join().
  /// [query] is built when it is added: a change to it after this call is
  /// not used.
  ///
  /// ```
  /// QueryBuilder<Map<String, dynamic>> latest = QueryBuilder.table('post')
  ///     .selectRaw('user_id, MAX(created_at) as last_post')
  ///     .groupBy('user_id');
  /// // JOIN (SELECT ...) AS "latest" on "latest"."user_id" = "user"."id"
  /// List users = await User()
  ///     .joinSub(latest, 'latest', 'latest.user_id', 'user.id')
  ///     .get();
  /// ```
  QueryBuilder<T> joinSub(
    QueryBuilder<dynamic> query,
    String alias,
    String first,
    String arg2, [
    String? arg3,
  ]) {
    return _on('JOIN', _sub(query, alias), first, arg2, arg3);
  }

  /// left join the rows of a sub query, see [joinSub]
  ///
  /// ```
  /// List users = await User()
  ///     .leftJoinSub(latest, 'latest', 'latest.user_id', 'user.id')
  ///     .get();
  /// ```
  QueryBuilder<T> leftJoinSub(
    QueryBuilder<dynamic> query,
    String alias,
    String first,
    String arg2, [
    String? arg3,
  ]) {
    return _on('LEFT JOIN', _sub(query, alias), first, arg2, arg3);
  }

  /// join raw
  ///
  /// ```
  /// List admins = await Admin().joinRaw('admin_info on admin_info.admin_id = admin.id').get();
  /// ```
  QueryBuilder<T> joinRaw(String rawQuery, [dynamic params]) {
    return _rawQuery('JOIN', rawQuery, params);
  }

  /// left join raw
  ///
  /// ```
  /// List admins = await Admin().leftJoinRaw('admin_info on admin_info.admin_id = admin.id').get();
  /// ```
  QueryBuilder<T> leftJoinRaw(String rawQuery, [dynamic params]) {
    return _rawQuery('LEFT JOIN', rawQuery, params);
  }

  /// right join raw
  ///
  /// ```
  /// List admins = await Admin().rightJoinRaw('admin_info on admin_info.admin_id = admin.id').get();
  /// ```
  QueryBuilder<T> rightJoinRaw(String rawQuery, [dynamic params]) {
    return _rawQuery('RIGHT JOIN', rawQuery, params);
  }

  QueryBuilder<T> _query(
    String type,
    String arg1,
    Object arg2,
    String? arg3,
    dynamic arg4,
  ) {
    if (arg2 is void Function(JoinClause join)) {
      JoinClause clause = JoinClause._(queryBuilder);
      arg2(clause);
      if (clause._conditions.isEmpty) {
        throw ArgumentError.value(
          arg1,
          'join',
          'needs a condition: call on() or where() in the callback',
        );
      }
      (_joins ??= <String>[]).add(
        '$type ${helper.wrap(arg1)} on ${clause._conditions.join(' ')}',
      );
      return queryBuilder;
    }
    if (arg2 is! String || arg3 == null) {
      throw ArgumentError.value(
        arg2,
        'join',
        'needs two columns, or a void Function(JoinClause)',
      );
    }
    return _on(type, helper.wrap(arg1), arg2, arg3, arg4);
  }

  /// `(sub query) AS "alias"`
  String _sub(QueryBuilder<dynamic> query, String alias) {
    return '(${helper.subQuery(query)}) AS ${helper.wrap(alias)}';
  }

  /// add `type table on first = second`. [table] is ready sql.
  QueryBuilder<T> _on(
    String type,
    String table,
    String first,
    String arg3, [
    dynamic arg4,
  ]) {
    String condition = '=';
    String second = arg3;
    if (arg4 != null) {
      condition = helper.operator(arg3);
      second = arg4;
    }
    (_joins ??= <String>[]).add(
      "$type $table on ${helper.wrap(first)} $condition ${helper.wrap(second)}",
    );
    return queryBuilder;
  }

  QueryBuilder<T> _rawQuery(String type, String rawQuery, [dynamic params]) {
    (_joins ??= <String>[]).add('$type $rawQuery');
    if (params != null && params is Map<String, dynamic>) {
      params.forEach((String key, dynamic value) {
        addSubstitutionValues(key, value);
      });
    }
    return queryBuilder;
  }
}
