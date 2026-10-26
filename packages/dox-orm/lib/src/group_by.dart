import 'query_builder.dart';
import 'shared_mixin.dart';

mixin GroupBy<T> implements SharedMixin<T> {
  String _groupBy = '';

  /// made on the first having(), most queries never need it
  List<String>? _havings;

  /// the GROUP BY part, then the HAVING part
  String getGroupByQuery() {
    List<String>? havings = _havings;
    if (havings == null) return _groupBy;
    return '$_groupBy HAVING ${havings.join(' ')}';
  }

  /// Group by query
  ///
  /// ```
  /// String query = await Blog()
  ///   .selectRaw('count(*) as total, status')
  ///   .groupBy('status')
  ///   .get();
  /// ```
  QueryBuilder<T> groupBy(dynamic column) {
    if (column is String) {
      _groupBy = ' GROUP BY ${helper.wrap(column)}';
    }
    if (column is List) {
      _groupBy =
          ' GROUP BY ${column.map((dynamic c) => helper.wrap(c.toString())).join(',')}';
    }
    return queryBuilder;
  }

  /// group by raw query, nothing is quoted. never put user input in it.
  ///
  /// ```
  /// await QueryBuilder.table('blog').groupByRaw('date(created_at)').get();
  /// ```
  QueryBuilder<T> groupByRaw(String query) {
    _groupBy = ' GROUP BY $query';
    return queryBuilder;
  }

  /// having condition, it goes after GROUP BY. like where(), it takes
  /// a column and a value, or a column, an operator and a value.
  /// the value is a param, the column is quoted.
  ///
  /// ```
  /// await QueryBuilder.table('blog')
  ///     .selectRaw('status, count(*) as total')
  ///     .groupBy('status')
  ///     .having('status', '!=', 'draft')
  ///     .get();
  /// ```
  /// ponytail: postgres does not allow a select alias (like `total`) in
  /// HAVING. use havingRaw('count(*) > @n', {'n': 1}) for aggregates.
  QueryBuilder<T> having(String column, dynamic arg2, [dynamic arg3]) {
    return _having('AND', column, arg2, arg3);
  }

  /// or having condition
  ///
  /// ```
  /// await QueryBuilder.table('blog')
  ///     .selectRaw('status, count(*) as total')
  ///     .groupBy('status')
  ///     .having('status', 'active')
  ///     .orHaving('status', 'draft')
  ///     .get();
  /// ```
  QueryBuilder<T> orHaving(String column, dynamic arg2, [dynamic arg3]) {
    return _having('OR', column, arg2, arg3);
  }

  /// having raw condition, nothing is quoted. put user values in
  /// [params], never in [query].
  ///
  /// ```
  /// await QueryBuilder.table('blog')
  ///     .selectRaw('status, count(*) as total')
  ///     .groupBy('status')
  ///     .havingRaw('count(*) > @min', <String, dynamic>{'min': 1})
  ///     .get();
  /// ```
  QueryBuilder<T> havingRaw(String query, [Map<String, dynamic>? params]) {
    return _havingRaw('AND', query, params);
  }

  /// or having raw condition, nothing is quoted
  ///
  /// ```
  /// await QueryBuilder.table('blog')
  ///     .selectRaw('status, count(*) as total')
  ///     .groupBy('status')
  ///     .havingRaw('count(*) > @min', <String, dynamic>{'min': 5})
  ///     .orHavingRaw('status = @s', <String, dynamic>{'s': 'draft'})
  ///     .get();
  /// ```
  QueryBuilder<T> orHavingRaw(String query, [Map<String, dynamic>? params]) {
    return _havingRaw('OR', query, params);
  }

  QueryBuilder<T> _having(
    String type,
    String column,
    dynamic arg2, [
    dynamic arg3,
  ]) {
    String condition = '=';
    dynamic value = arg2;
    if (arg3 != null) {
      condition = helper.operator(arg2);
      value = arg3;
    }

    /// `= null` never match in sql, use IS NULL
    if (value == null) {
      return _havingRaw(type, '${helper.wrap(column)} IS NULL');
    }
    String key = helper.parseColumnKey(column);
    addSubstitutionValues(key, value);
    return _havingRaw(type, '${helper.wrap(column)} $condition $key');
  }

  QueryBuilder<T> _havingRaw(
    String type,
    String query, [
    Map<String, dynamic>? params,
  ]) {
    List<String>? havings = _havings;
    if (havings == null) {
      _havings = <String>[query];
    } else {
      havings.add('$type $query');
    }
    params?.forEach(addSubstitutionValues);
    return queryBuilder;
  }
}
