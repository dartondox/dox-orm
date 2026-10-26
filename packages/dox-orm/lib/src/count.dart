import 'shared_mixin.dart';

mixin Count<T> implements SharedMixin<T> {
  /// count the record
  /// count() cannot use with select(), but with distinct() it counts
  /// the distinct rows of select().
  /// limit, offset and order by are not used.
  /// with groupBy() it returns the number of groups.
  /// ```
  /// await Blog().count();
  /// await QueryBuilder.table('blog').select('status').distinct().count();
  /// ```
  // ignore: always_specify_types
  Future<int> count() async {
    String table = helper.wrap(tableName);
    String q = "SELECT count(*) as total FROM $table";
    q += helper.getCommonQuery(isCountQuery: true);
    if (queryBuilder.isDistinct) {
      q =
          "SELECT count(*) as total FROM (SELECT ${queryBuilder.getSelectQuery()}"
          " FROM $table${helper.getCommonQuery(isCountQuery: true)}) as dox_count";
    } else if (queryBuilder.getGroupByQuery().isNotEmpty) {
      q =
          "SELECT count(*) as total FROM (SELECT 1 as one FROM $table"
          "${helper.getCommonQuery(isCountQuery: true)}) as dox_count";
    }
    List<dynamic> result = helper.getMapResult(await helper.runQuery(q));
    if (result.isNotEmpty) {
      if (result.first['total'] != null) {
        return int.parse(result.first['total'].toString());
      }
    }
    return 0;
  }

  /// true when the query matches at least one row. it reads one row at
  /// most, so it is faster than `count() > 0`. limit, offset, order by and
  /// select are not used.
  ///
  /// it is not called exists(), because a model already has the getter
  /// `exists` (true when the model row is in the table).
  ///
  /// ```
  /// bool taken = await User().where('email', email).hasRows();
  /// ```
  Future<bool> hasRows() async {
    String q =
        "SELECT 1 as one FROM ${helper.wrap(tableName)}"
        "${helper.getCommonQuery(isCountQuery: true)} LIMIT 1";
    return (await helper.runQuery(q)).isNotEmpty;
  }

  /// true when the query matches no row, the opposite of hasRows()
  ///
  /// ```
  /// if (await User().where('email', email).hasNoRows()) {
  ///   await User().create(<String, dynamic>{'email': email});
  /// }
  /// ```
  Future<bool> hasNoRows() async => !await hasRows();

  /// the sum of [column] of the rows. it is null when no row matches.
  /// like count(), it uses where, join and soft deletes, but not limit,
  /// offset or order by. after distinct() it adds up distinct values.
  ///
  /// it is a num: an int or a double, by driver (mysql gives a double
  /// for the sum of an int column). use `==`, toInt() or toDouble().
  /// postgres and mysql send decimals as text, it is changed to num.
  ///
  /// ```
  /// num? total = await Order().where('paid', true).sum('amount');
  /// ```
  /// it throws a [StateError] with groupBy(), use selectRaw() then.
  Future<num?> sum(String column) async {
    return _toNum(await _aggregate('SUM', column));
  }

  /// the average of [column] of the rows, as a double. it is null when
  /// no row matches. the same rules as sum().
  ///
  /// ```
  /// double? average = await Order().avg('amount');
  /// ```
  Future<double?> avg(String column) async {
    return _toNum(await _aggregate('AVG', column))?.toDouble();
  }

  /// the smallest value of [column], or null when no row matches.
  /// the same rules as sum(). the value is what the driver gives: a
  /// number, a string, or a date as an iso string. a postgres or mysql
  /// decimal column gives a string.
  ///
  /// ```
  /// dynamic cheapest = await Product().min('price');
  /// dynamic first = await Blog().min('created_at');
  /// ```
  Future<dynamic> min(String column) => _aggregate('MIN', column);

  /// the biggest value of [column], or null when no row matches.
  /// the same rules as min().
  ///
  /// ```
  /// dynamic newest = await Blog().max('created_at');
  /// ```
  Future<dynamic> max(String column) => _aggregate('MAX', column);

  /// run `SELECT <function>(<column>)` with the where and join parts
  Future<dynamic> _aggregate(String function, String column) async {
    if (queryBuilder.getGroupByQuery().isNotEmpty) {
      throw StateError(
        '${function.toLowerCase()}() can not be used with groupBy() or '
        'having(). Use selectRaw() and get() instead.',
      );
    }
    String distinct =
        queryBuilder.isDistinct && (function == 'SUM' || function == 'AVG')
        ? 'DISTINCT '
        : '';
    String q =
        "SELECT $function($distinct${helper.wrap(column)}) as dox_aggregate"
        " FROM ${helper.wrap(tableName)}"
        "${helper.getCommonQuery(isCountQuery: true)}";
    List<Map<String, dynamic>> rows = helper.getMapResult(
      await helper.runQuery(q),
    );
    return rows.isEmpty ? null : rows.first['dox_aggregate'];
  }

  /// a number from the driver: an int, a double, or a decimal as text
  static num? _toNum(dynamic value) {
    if (value == null || value is num) return value as num?;
    return num.parse(value.toString());
  }
}
