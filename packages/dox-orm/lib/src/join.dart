import 'query_builder.dart';
import 'shared_mixin.dart';

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
    String arg2,
    String arg3, [
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
    String arg2,
    String arg3, [
    dynamic arg4,
  ]) {
    return _query('RIGHT JOIN', arg1, arg2, arg3, arg4);
  }

  /// join
  ///
  /// ```
  /// List admins = await Admin().join('admin_info', 'admin_info.admin_id', 'admin.id').get();
  /// ```
  QueryBuilder<T> join(String arg1, String arg2, String arg3, [dynamic arg4]) {
    return _query('JOIN', arg1, arg2, arg3, arg4);
  }

  /// join the rows of a sub query, named [alias]. the values of [query]
  /// are bound, like in this query. the other args are like join().
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
    String arg2,
    String arg3, [
    dynamic arg4,
  ]) {
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
