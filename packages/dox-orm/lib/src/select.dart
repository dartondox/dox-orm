import 'query_builder.dart';
import 'shared_mixin.dart';

mixin Select<T> implements SharedMixin<T> {
  String _select = '*';

  bool _distinct = false;

  /// the sub query of fromSub(), with its alias
  String? _fromSub;

  /// true when fromSub() was called
  bool get hasFromSub => _fromSub != null;

  /// the part after `FROM`: the table, or the sub query of fromSub()
  String getFromQuery() => _fromSub ?? helper.wrap(tableName);

  /// select from the rows of a sub query, named [alias], not from a
  /// table. the values of [query] are bound, like in this query.
  ///
  /// ```
  /// QueryBuilder<Map<String, dynamic>> totals = QueryBuilder.table('order')
  ///     .selectRaw('user_id, SUM(amount) as total')
  ///     .groupBy('user_id');
  /// // SELECT * FROM (SELECT user_id, ... GROUP BY "user_id") AS "totals"
  /// // WHERE "total" > @total_p0
  /// List<Map<String, dynamic>> rows = await QueryBuilder.table('totals')
  ///     .fromSub(totals, 'totals')
  ///     .where('total', '>', 100)
  ///     .get();
  /// ```
  /// [alias] is also the table name of this query, so `totals.total`
  /// works in where() and orderBy().
  /// [query] is built when it is added: a change to it after this call is
  /// not used.
  QueryBuilder<T> fromSub(QueryBuilder<dynamic> query, String alias) {
    _fromSub = '(${helper.subQuery(query)}) AS ${helper.wrap(alias)}';
    tableName = alias;

    /// a model reads its table name from its class, so the line above
    /// does nothing there. the alias field keeps [alias] for the
    /// columns that need the table in front, like `b.deleted_at`.
    tableAlias = alias;
    return queryBuilder;
  }

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
  /// await Blog().select(['title', 'body']).get();
  /// await Blog().select(['title', 'body as content']).get();
  /// ```
  /// [selection] can be string or array.
  /// a second call replaces the columns, like Laravel. so
  /// `select('title').select('body')` selects only `body`.
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
