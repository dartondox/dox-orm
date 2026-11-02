import 'query_builder.dart';
import 'shared_mixin.dart';

mixin Union<T> implements SharedMixin<T> {
  /// made on the first union, most queries never need it
  List<String>? _unions;

  /// true when union() or unionAll() was called
  bool get hasUnion => _unions != null;

  /// the union parts, they go after the where and group by parts
  String getUnionQuery() => _unions?.join() ?? '';

  /// add the rows of [query] to the rows of this query, without the
  /// rows that are the same (`UNION`).
  ///
  /// ```
  /// // SELECT * FROM "blog" WHERE "status" = @status_p0
  /// // UNION SELECT * FROM (SELECT * FROM "blog" WHERE ...) AS "dox_union0"
  /// // ORDER BY "id"
  /// List<Blog> blogs = await Blog()
  ///     .where('status', 'draft')
  ///     .union(Blog().where('views', '>', 100))
  ///     .orderBy('id')
  ///     .get();
  /// ```
  /// - both queries must select the same number of columns.
  /// - orderBy(), limit() and offset() of this query sort and cut the
  ///   whole result. use a plain column name in orderBy(), not
  ///   `table.column`. [query] can have its own orderBy() and limit().
  /// - count(), paginate(), sum(), avg(), min() and max() use the whole
  ///   result, like Laravel: `SELECT SUM(col) FROM (<union>) AS ...`.
  ///   sum() and the others keep limit() and offset(), count() does not.
  /// - [query] is built when it is added: a change to it after this call
  ///   is not used.
  QueryBuilder<T> union(QueryBuilder<dynamic> query) {
    return _union('UNION', query);
  }

  /// like [union], but it keeps the rows that are the same
  /// (`UNION ALL`). it is faster.
  ///
  /// ```
  /// List<Map<String, dynamic>> rows = await QueryBuilder.table('blog')
  ///     .select('title')
  ///     .unionAll(QueryBuilder.table('news').select('title'))
  ///     .get();
  /// ```
  QueryBuilder<T> unionAll(QueryBuilder<dynamic> query) {
    return _union('UNION ALL', query);
  }

  QueryBuilder<T> _union(String type, QueryBuilder<dynamic> query) {
    List<String> unions = _unions ??= <String>[];

    /// each part is wrapped, so it can have its own ORDER BY and LIMIT
    /// on every driver (sqlite has no brackets around a union part)
    String alias = helper.wrap('dox_union${unions.length}');
    unions.add(' $type SELECT * FROM (${helper.subQuery(query)}) AS $alias');
    return queryBuilder;
  }
}
