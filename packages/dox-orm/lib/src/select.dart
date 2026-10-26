import 'query_builder.dart';
import 'shared_mixin.dart';

mixin Select<T> implements SharedMixin<T> {
  String _select = '*';

  bool _distinct = false;

  /// true when distinct() was called
  bool get isDistinct => _distinct;

  /// the select part, with `DISTINCT` in front after distinct()
  String getSelectQuery() {
    return _distinct ? 'DISTINCT $_select' : _select;
  }

  /// select only rows that are not the same (`SELECT DISTINCT`).
  /// it works with select(). count() then counts the distinct rows,
  /// and sum() and avg() add up the distinct values.
  ///
  /// ```
  /// List<Map<String, dynamic>> rows = await QueryBuilder.table('blog')
  ///     .select('status')
  ///     .distinct()
  ///     .get();
  /// int statuses = await QueryBuilder.table('blog')
  ///     .select('status')
  ///     .distinct()
  ///     .count();
  /// ```
  QueryBuilder<T> distinct([bool distinct = true]) {
    _distinct = distinct;
    return queryBuilder;
  }

  /// Select query
  ///
  /// ```
  /// await Blog().select('title, body').get();
  /// await Blog().select('title').select('body').get();
  /// await Blog().select(['title', 'body']).get();
  /// await Blog().select(['title', 'body as content']).get();
  /// ```
  /// [selection] can be string or array.
  /// column names are quoted. it throws an [ArgumentError] when a part is
  /// not a plain name. use selectRaw() for expressions like `count(*)`.
  QueryBuilder<T> select(dynamic selection) {
    if (selection is List<String>) {
      _select = selection.map(helper.wrap).join(',');
    }
    if (selection is String) {
      _select = selection.split(',').map(helper.wrap).join(',');
    }
    return queryBuilder;
  }

  /// Select raw query, nothing is quoted
  ///
  /// ```
  /// await Blog().selectRaw('DISTINCT title').get();
  /// ```
  QueryBuilder<T> selectRaw(String query) {
    _select = query;
    return queryBuilder;
  }
}
