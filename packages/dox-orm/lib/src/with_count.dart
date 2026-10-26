import 'package:dox_orm/dox_orm.dart';

import 'relationships/keys.dart';
import 'shared_mixin.dart';

/// one withCount(), withSum() or withMax() of a query
class _Aggregate {
  final String relation;
  final String function;
  final String column;
  final String key;
  final void Function(QueryBuilder<dynamic> query)? where;

  const _Aggregate(
    this.relation,
    this.function,
    this.column,
    this.key,
    this.where,
  );
}

mixin WithCount<T> implements SharedMixin<T> {
  List<_Aggregate>? _aggregates;

  /// true when the query has a withCount(), withSum() or withMax()
  bool get hasAggregates => _aggregates != null;

  /// the result keys, like `posts_count`
  List<String> get aggregateKeys => <String>[
    for (_Aggregate a in _aggregates ?? const <_Aggregate>[]) a.key,
  ];

  /// adds `<relation>_count`, the number of related rows, with a
  /// subquery. Works with hasOne, hasMany and manyToMany relations.
  /// [where] adds conditions to the related rows.
  /// `'posts as published_count'` sets the key.
  ///
  /// ```
  /// List<User> users = await User().withCount('posts').get();
  /// users.first.countOf('posts');
  ///
  /// await User()
  ///     .withCount('posts as published_count', (QueryBuilder<dynamic> q) {
  ///       q.where('published', true);
  ///     })
  ///     .get();
  /// users.first.aggregate('published_count');
  /// ```
  QueryBuilder<T> withCount(
    String relation, [
    void Function(QueryBuilder<dynamic> query)? where,
  ]) {
    return _add(relation, 'count', '*', where);
  }

  /// adds `<relation>_sum_<column>`, the sum of [column] of the related
  /// rows. It is null when there is no related row.
  ///
  /// ```
  /// User? user = await User().withSum('posts', 'views').find(1);
  /// user?.aggregate('posts_sum_views');
  /// ```
  QueryBuilder<T> withSum(
    String relation,
    String column, [
    void Function(QueryBuilder<dynamic> query)? where,
  ]) {
    return _add(relation, 'sum', column, where);
  }

  /// adds `<relation>_max_<column>`, the biggest [column] of the
  /// related rows. It is null when there is no related row.
  QueryBuilder<T> withMax(
    String relation,
    String column, [
    void Function(QueryBuilder<dynamic> query)? where,
  ]) {
    return _add(relation, 'max', column, where);
  }

  QueryBuilder<T> _add(
    String relation,
    String function,
    String column,
    void Function(QueryBuilder<dynamic> query)? where,
  ) {
    List<String> parts = relation.split(RegExp(r'\s+as\s+'));
    String name = parts.first.trim();
    String snake = helper.toSnakeCase(name);
    String key = parts.length > 1
        ? parts[1].trim()
        : function == 'count'
        ? '${snake}_count'
        : '${snake}_${function}_$column';
    (_aggregates ??= <_Aggregate>[]).add(
      _Aggregate(name, function, column, key, where),
    );
    return queryBuilder;
  }

  /// the subqueries for the select part, like
  /// `, (SELECT COUNT(*) FROM post WHERE ...) AS "posts_count"`
  String aggregateSelects() {
    List<_Aggregate>? list = _aggregates;
    if (list == null) return '';
    QueryBuilder<T> owner = queryBuilder;
    if (owner is! Model<T>) {
      throw StateError('withCount() needs a model query, like User().');
    }
    String sql = '';
    for (int i = 0; i < list.length; i++) {
      _Aggregate a = list[i];
      QueryBuilder<dynamic> q = _relationQuery(
        owner,
        a.relation,
        'dox_agg${i}_',
        aggregate: true,
      );
      a.where?.call(q);
      String column = a.column == '*'
          ? '*'
          : q.helper.wrap(
              a.column.contains('.') ? a.column : '${tableRef(q)}.${a.column}',
            );
      String inner =
          'SELECT ${a.function.toUpperCase()}($column) '
          'FROM ${fromTable(q)}'
          '${q.helper.getCommonQuery(isCountQuery: true)}';
      substitutionValues.addAll(q.substitutionValues);
      sql += ', ($inner) AS ${helper.wrap(a.key)}';
    }
    return sql;
  }

  /// the query of [relation], matched to the parent row by a column.
  /// its param keys start with [keyPrefix].
  QueryBuilder<dynamic> _relationQuery(
    Model<T> owner,
    String relation,
    String keyPrefix, {
    bool aggregate = false,
  }) {
    Function? make = owner.relationsQueryMatcher[relation];
    if (make == null) {
      throw ArgumentError.value(relation, 'relation', 'is not a relation');
    }
    relationSubquery = true;
    aggregateSubquery = aggregate;
    subqueryKeyPrefix = keyPrefix;
    try {
      QueryBuilder<dynamic> q = Function.apply(make, <dynamic>[
        <Model<T>>[owner],
      ]) as QueryBuilder<dynamic>;
      q.helper.keyPrefix = keyPrefix;
      return q;
    } finally {
      relationSubquery = false;
      aggregateSubquery = false;
      subqueryKeyPrefix = '';
    }
  }

  /// number of whereHas() subqueries so far, so each one gets its own
  /// param key prefix
  int _hasCount = 0;

  /// compare operators allowed in has()
  static const Set<String> _countOperators = <String>{
    '=',
    '!=',
    '<>',
    '<',
    '>',
    '<=',
    '>=',
  };

  /// keeps the rows that have at least one related row of [relation].
  /// [where] adds conditions to the related rows. Soft deleted related
  /// rows do not count. Works with hasOne, hasMany, belongsTo and
  /// manyToMany relations. `'posts.comments'` checks a relation of a
  /// relation.
  ///
  /// ```
  /// List<User> users = await User().whereHas('posts').get();
  ///
  /// await User().whereHas('posts', (QueryBuilder<dynamic> q) {
  ///   q.where('published', true);
  /// }).get();
  /// ```
  QueryBuilder<T> whereHas(
    String relation, [
    void Function(QueryBuilder<dynamic> query)? where,
  ]) {
    return _addHas('AND', relation, '>=', 1, where);
  }

  /// the same as [whereHas], joined to the conditions before with OR
  ///
  /// ```
  /// await User().where('name', 'Ada').orWhereHas('posts').get();
  /// ```
  QueryBuilder<T> orWhereHas(
    String relation, [
    void Function(QueryBuilder<dynamic> query)? where,
  ]) {
    return _addHas('OR', relation, '>=', 1, where);
  }

  /// keeps the rows that have no related row of [relation].
  /// [where] adds conditions to the related rows.
  ///
  /// ```
  /// List<User> users = await User().whereDoesntHave('posts').get();
  ///
  /// await User().whereDoesntHave('posts', (QueryBuilder<dynamic> q) {
  ///   q.where('published', true);
  /// }).get();
  /// ```
  QueryBuilder<T> whereDoesntHave(
    String relation, [
    void Function(QueryBuilder<dynamic> query)? where,
  ]) {
    return _addHas('AND', relation, '<', 1, where);
  }

  /// the same as [whereDoesntHave], joined to the conditions before
  /// with OR
  ///
  /// ```
  /// await User().where('name', 'Ada').orWhereDoesntHave('posts').get();
  /// ```
  QueryBuilder<T> orWhereDoesntHave(
    String relation, [
    void Function(QueryBuilder<dynamic> query)? where,
  ]) {
    return _addHas('OR', relation, '<', 1, where);
  }

  /// keeps the rows where the number of related rows of [relation]
  /// matches [operator] and [count]. The default is at least one.
  /// [where] adds conditions to the related rows.
  /// For `'posts.comments'` the count is the comments of one post.
  ///
  /// ```
  /// await User().has('posts').get();
  /// await User().has('posts', '>=', 3).get();
  /// await User().has('posts', '>', 1, (QueryBuilder<dynamic> q) {
  ///   q.where('published', true);
  /// }).get();
  /// ```
  QueryBuilder<T> has(
    String relation, [
    String operator = '>=',
    int count = 1,
    void Function(QueryBuilder<dynamic> query)? where,
  ]) {
    return _addHas('AND', relation, operator, count, where);
  }

  /// adds `EXISTS (SELECT 1 FROM ...)`, `NOT EXISTS (...)` or
  /// `(SELECT COUNT(*) FROM ...) >= @key` to the where of this query.
  QueryBuilder<T> _addHas(
    String type,
    String relation,
    String operator,
    int count,
    void Function(QueryBuilder<dynamic> query)? where,
  ) {
    QueryBuilder<T> owner = queryBuilder;
    if (owner is! Model<T>) {
      throw StateError('whereHas() needs a model query, like User().');
    }
    String op = helper.operator(operator);
    if (!_countOperators.contains(op)) {
      throw ArgumentError.value(operator, 'operator', 'is not allowed');
    }
    bool exists = op == '>=' && count == 1;
    bool notExists = op == '<' && count == 1;

    /// `posts.comments`: the posts that have the comments
    int dot = relation.indexOf('.');
    String name = dot < 0 ? relation : relation.substring(0, dot);
    QueryBuilder<dynamic> q = _relationQuery(
      owner,
      name,
      '${helper.keyPrefix}dox_has${_hasCount++}_',
    );
    if (dot < 0) {
      where?.call(q);
    } else {
      String rest = relation.substring(dot + 1);
      if (notExists) {
        q._addHas('AND', rest, '>=', 1, where);
      } else {
        q._addHas('AND', rest, op, count, where);
        exists = true;
      }
    }

    String from =
        'FROM ${fromTable(q)}'
        '${q.helper.getCommonQuery(isCountQuery: true)}';
    Map<String, dynamic> params = q.substitutionValues;
    String sql;
    if (exists || notExists) {
      sql = '${notExists ? 'NOT ' : ''}EXISTS (SELECT 1 $from)';
    } else {
      String key = helper.parseColumnKey('dox_has_count');
      params[key.substring(1)] = count;
      sql = '(SELECT COUNT(*) $from) $op $key';
    }
    return type == 'OR'
        ? queryBuilder.orWhereRaw(sql, params)
        : queryBuilder.whereRaw(sql, params);
  }
}
