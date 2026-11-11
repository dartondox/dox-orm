import 'main.dart';
import 'query_builder.dart';
import 'shared_mixin.dart';
import 'types/orm_flags.dart';

/// removes the selectRaw() values of [qb] from its values. count() and
/// the other queries that do not use the select part call it, so
/// Postgres does not get values that the sql does not use. it is a
/// function, not a query method, so it can not clash with a model field.
void dropSelectValues(QueryBuilder<dynamic> qb) {
  Map<String, dynamic>? values = qb._selectValues;
  if (values == null || !qb._selectValuesAdded) return;
  for (String key in values.keys) {
    qb.substitutionValues.remove(key);
  }
  qb._selectValuesAdded = false;
}

mixin Select<T> implements SharedMixin<T> {
  String _select = '*';

  /// the values of selectRaw(). they are added when the select part is
  /// used, see [dropSelectValues].
  Map<String, dynamic>? _selectValues;

  /// true while the [_selectValues] are in the values of the query
  bool _selectValuesAdded = false;

  /// true after select() or selectRaw(), see [OrmFlags.selectRawAdds]
  bool _selectSet = false;

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
    Map<String, dynamic>? values = _selectValues;
    if (values != null) {
      Map<String, dynamic> all = substitutionValues;
      for (MapEntry<String, dynamic> e in values.entries) {
        /// a name that another part of the query uses too would get one
        /// value in both places, and count() would drop it from both
        if (all.containsKey(e.key) &&
            !(_selectValuesAdded && all[e.key] == e.value)) {
          throw ArgumentError.value(
            e.key,
            'selectRaw',
            'is a value name that the query uses already. '
                'Use unique names for the selectRaw() values',
          );
        }
      }
      all.addAll(values);
      _selectValuesAdded = true;
    }
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
    dropSelectValues(queryBuilder);
    _selectValues = null;
    _selectSet = true;
    return queryBuilder;
  }

  /// Select raw query, nothing is quoted. never put user input in
  /// [query]. pass user values in [params] as `@name`, they are bound
  /// safely, like whereRaw(). use unique names: a name that the query
  /// uses in another place (eg. in whereRaw() or an other selectRaw())
  /// throws an [ArgumentError]. a name may not start with `dox_`: the
  /// ORM uses it for its own values.
  ///
  /// ```
  /// await Blog().selectRaw('DISTINCT title').get();
  /// await Blog().selectRaw('views * @rate as score', {'rate': 2}).get();
  /// ```
  /// it replaces the select list (and its values). With
  /// [OrmFlags.selectRawAdds] it adds to it, so
  /// `select('a').selectRaw('count(*) c')` selects both.
  QueryBuilder<T> selectRaw(String query, [dynamic params]) {
    bool adds = _selectSet && SqlQueryBuilder().flags.selectRawAdds;
    _select = adds ? '$_select,$query' : query;
    if (!adds) {
      dropSelectValues(queryBuilder);
      _selectValues = null;
    }
    if (params is Map<String, dynamic> && params.isNotEmpty) {
      Map<String, dynamic> values = _selectValues ??= <String, dynamic>{};
      for (String key in params.keys) {
        /// the ORM names its own values `dox_...`, eg. `dox_limit`
        if (key.startsWith('dox_')) {
          throw ArgumentError.value(
            key,
            'selectRaw',
            'starts with dox_, which the ORM uses for its own values',
          );
        }
        if (values.containsKey(key)) {
          throw ArgumentError.value(
            key,
            'selectRaw',
            'is a value name that the query uses already. '
                'Use unique names for the selectRaw() values',
          );
        }
      }
      values.addAll(params);
    }
    _selectSet = true;
    return queryBuilder;
  }
}
