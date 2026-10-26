import 'package:dox_orm/dox_orm.dart';

import 'shared_mixin.dart';

/// run [query] of [qb] and return the number of rows it changed
Future<int> runAffectingQuery(QueryBuilder<dynamic> qb, String query) {
  Map<String, dynamic> values = qb.substitutionValues;
  if (qb.shouldDebug) qb.logger.log(query, values);
  return qb.dbDriver.affectingStatement(query, substitutionValues: values);
}

mixin Update<T> implements SharedMixin<T> {
  /// update the rows of this query and return how many rows changed.
  /// an empty [data] runs no query and returns 0.
  ///
  /// ```
  /// int count = await Blog().where('id', 1).update({
  ///   "title" : "new title",
  /// });
  /// ```
  ///
  /// Postgres and SQLite count the rows the where matched. MySQL and
  /// MariaDB count only the rows that really changed: a row that already
  /// has the new values counts 0.
  Future<int> update(Map<String, dynamic> data) {
    return _update(data, const <String>[]);
  }

  /// add [amount] to [column] in one query, and set the [extra] columns
  /// too. It returns how many rows changed.
  ///
  /// ```
  /// await Blog().where('id', 1).increment('views');
  /// await Blog().where('id', 1).increment('views', 5, {'status': 'hot'});
  /// ```
  ///
  /// A null column stays null, like in SQL.
  Future<int> increment(
    String column, [
    num amount = 1,
    Map<String, dynamic> extra = const <String, dynamic>{},
  ]) {
    return _step(column, amount, extra, '+');
  }

  /// take [amount] from [column] in one query, and set the [extra]
  /// columns too. It returns how many rows changed.
  ///
  /// ```
  /// await Product().where('id', 1).decrement('stock');
  /// await Product().where('id', 1).decrement('stock', 2);
  /// ```
  Future<int> decrement(
    String column, [
    num amount = 1,
    Map<String, dynamic> extra = const <String, dynamic>{},
  ]) {
    return _step(column, amount, extra, '-');
  }

  /// `column = column + @amount` (or `-`), plus [extra]
  Future<int> _step(
    String column,
    num amount,
    Map<String, dynamic> extra,
    String sign,
  ) {
    String wrapped = helper.wrap(column);
    String key = helper.parseColumnKey(column);
    addSubstitutionValues(key, amount);
    return _update(extra, <String>['$wrapped = $wrapped $sign $key']);
  }

  /// UPDATE with the [sets] that are ready, then the [data] columns
  Future<int> _update(Map<String, dynamic> data, List<String> sets) async {
    List<String> columnToUpdate = <String>[...sets];
    data.forEach((String column, dynamic value) {
      String columnKey = helper.parseColumnKey(column);
      columnToUpdate.add("${helper.wrap(column)} = $columnKey");
      addSubstitutionValues(
        columnKey,
        queryBuilder.dbDriver.columnValue(value),
      );
    });

    /// `UPDATE t SET` with nothing to set is not valid sql
    if (columnToUpdate.isEmpty) return 0;
    String q =
        "UPDATE ${helper.wrap(tableName)} SET ${columnToUpdate.join(',')}";
    q += helper.getCommonQuery();
    return await runAffectingQuery(queryBuilder, q);
  }
}
