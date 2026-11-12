import 'dart:async';

import 'package:dox_orm/dox_orm.dart';

import '../drivers/db_driver.dart' show SqlParam, findSqlParams;
import '../get.dart' show selectSql;
import '../limit.dart';
import '../relationships/keys.dart';
import '../select.dart' show dropSelectValues;

final RegExp _notWord = RegExp(r'[^\w]');

/// compare operators allowed in where() and join()
const Set<String> _operators = <String>{
  '=',
  '!=',
  '<>',
  '<',
  '>',
  '<=',
  '>=',
  'like',
  'not like',
  'ilike',
};

/// column name without the non word characters, made once
final Map<String, String> _keyNames = <String, String>{};

/// snake case table name of each model type, made once
final Map<Type, String> _snakeNames = <Type, String>{};

class QueryBuilderHelper<T> {
  final QueryBuilder<T> queryBuilder;
  QueryBuilderHelper(this.queryBuilder);

  /// number of param keys made by this query
  int _paramCount = 0;

  /// put before each param key. a subquery uses it, so its keys do not
  /// clash with the keys of the main query.
  String keyPrefix = '';

  /// a param key that is unique in this query. the same query gives the
  /// same keys every time, so the sql text is the same and the drivers can
  /// reuse their prepared statements.
  String parseColumnKey(String column) {
    String? name = _keyNames[column];
    if (name == null) {
      /// ponytail: cleared when full, column names are a small set
      if (_keyNames.length >= 1000) _keyNames.clear();
      name = _keyNames[column] = column.replaceAll(_notWord, '');
    }
    return '@$keyPrefix${name}_p${_paramCount++}';
  }

  /// number of sub queries added by subQuery()
  int _subCount = 0;

  /// the select sql of [sub], to put in this query as a sub query.
  /// its param keys get a new prefix, so they can not clash with the keys
  /// of this query. its values are added to this query.
  String subQuery(QueryBuilder<dynamic> sub) {
    String sql = selectSql(sub);
    Map<String, dynamic> values = sub.substitutionValues;
    String prefix = '${keyPrefix}dox_sub${_subCount++}_';
    bool mysql = queryBuilder.dbDriver.getName() == Driver.mysql;
    StringBuffer out = StringBuffer();
    int copied = 0;
    for (SqlParam p in findSqlParams(sql, mysql: mysql)) {
      if (!values.containsKey(p.name)) continue;
      out
        ..write(sql.substring(copied, p.start))
        ..write('@$prefix${p.name}');
      copied = p.end;
      queryBuilder.addSubstitutionValues('$prefix${p.name}', values[p.name]);
    }
    out.write(sql.substring(copied));
    return out.toString();
  }

  /// quote a table or column name for the current driver
  String wrap(String value) => queryBuilder.dbDriver.wrap(value);

  /// [wrap] for a column that is written (insert, update, upsert). a json
  /// path (`meta->a`) can only be read, so it throws an [ArgumentError].
  String wrapWrite(String value) {
    if (value.contains('->')) {
      throw ArgumentError.value(
        value.trim(),
        'name',
        'is not a plain column name',
      );
    }
    return wrap(value);
  }

  /// [op] when it is a known compare operator, else it throws an
  /// [ArgumentError], so user input can not add sql to a where or join
  String operator(dynamic op) {
    String value = op.toString().trim();
    if (!_operators.contains(value.toLowerCase())) {
      throw ArgumentError.value(op, 'operator', 'is not allowed');
    }
    return value;
  }

  /// count query do not need order by, limit and offset
  String getCommonQuery({bool isCountQuery = false}) {
    String query = "";
    query += queryBuilder.getJoinQuery();
    query += queryBuilder.getWhereQuery();
    query += queryBuilder.getGroupByQuery();
    if (!isCountQuery) {
      /// orderBy and limit come after the unions: they sort and cut the
      /// whole result
      query += queryBuilder.getUnionQuery();
      query += queryBuilder.getOrderByQuery();
      query += queryBuilder.getLimitQuery();
    } else {
      /// a count has no LIMIT and no select, so it must not send their
      /// values
      queryBuilder.substitutionValues
        ..remove(Limit.limitKey)
        ..remove(Limit.offsetKey);
      dropSelectValues(queryBuilder);
    }
    return query;
  }

  /// the part after `UPDATE t SET ...` or `DELETE FROM t`.
  ///
  /// Postgres and SQLite do not take JOIN, ORDER BY or LIMIT in an UPDATE
  /// or DELETE. When the query has one of them, the rows are picked by
  /// their primary key in a sub query, so the table needs that column. The
  /// sub query is wrapped once more, so MySQL can also read the table it
  /// changes and use LIMIT. MySQL keeps its own `ORDER BY ... LIMIT` when
  /// there is no JOIN and no OFFSET, so a table with no primary key works
  /// there as before.
  ///
  /// GROUP BY and HAVING mean nothing in an UPDATE or DELETE, so they throw
  /// an [ArgumentError].
  ///
  /// A union() query throws a [StateError]: the write would change only
  /// the rows of the first query (or fail on Postgres).
  String getWriteQuery() {
    if (queryBuilder.hasUnion) {
      throw StateError(
        'update() and delete() can not be used on a union() query. '
        'Write to each query on its own.',
      );
    }
    if (queryBuilder.getGroupByQuery().isNotEmpty) {
      throw ArgumentError(
        'groupBy() and having() can not be used with update() or delete()',
      );
    }
    String join = queryBuilder.getJoinQuery();
    String orderBy = queryBuilder.getOrderByQuery();
    String limit = queryBuilder.getLimitQuery();
    String where = queryBuilder.getWhereQuery(write: true);
    if (join.isEmpty && orderBy.isEmpty && limit.isEmpty) {
      return where;
    }
    if (join.isEmpty &&
        !limit.contains('OFFSET') &&
        queryBuilder.dbDriver.getName() == Driver.mysql) {
      return '$where$orderBy$limit';
    }
    String table = queryBuilder.tableName;
    String key = wrap(queryBuilder.primaryKey);
    String rows =
        'SELECT ${wrap('$table.${queryBuilder.primaryKey}')} AS $key '
        'FROM ${wrap(table)}$join$where$orderBy$limit';
    return ' WHERE $key IN (SELECT $key FROM ($rows) AS dox_rows)';
  }

  /// run [query] with [values], or with the values of this query
  Future<List<Map<String, dynamic>>> runQuery(
    String query, [
    Map<String, dynamic>? values,
  ]) {
    values ??= queryBuilder.substitutionValues;
    String? connection = queryBuilder.connection;
    if (queryBuilder.shouldDebug) {
      queryBuilder.logger.log(query, values, connection);
    }
    SqlQueryBuilder sql = SqlQueryBuilder();
    Stopwatch? watch = sql.startQueryWatch(connection);
    QueryCancelToken? token = queryBuilder.cancelToken;
    return sql.timeQuery(
      // no closure for the common case: a query with no token
      token == null
          ? queryBuilder.dbDriver.query(
              query,
              substitutionValues: values,
              primaryKey: queryBuilder.primaryKey,
            )
          : DBDriver.withCancelToken(
              token,
              () => queryBuilder.dbDriver.query(
                query,
                substitutionValues: values,
                primaryKey: queryBuilder.primaryKey,
              ),
            ),
      watch,
      query,
      values,
      connection,
    );
  }

  /// dates become iso strings (models read them as strings).
  /// the rows are new maps from the driver, so they are changed in place.
  List<Map<String, dynamic>> getMapResult(
    List<Map<String, dynamic>> queryResult,
  ) {
    for (Map<String, dynamic> data in queryResult) {
      for (MapEntry<String, dynamic> e in data.entries) {
        if (e.value is DateTime) {
          data[e.key] = (e.value as DateTime).toIso8601String();
        }
      }
    }
    return queryResult;
  }

  /// rows to models. It is sync when there are no relations to load,
  /// so the caller does not wait one more microtask.
  // ignore: always_specify_types
  FutureOr<List> formatResult(List<Map<String, dynamic>> queryResult) {
    dynamic self = queryBuilder.self;
    if (self is! Model ||
        queryBuilder.getRawQuery().isNotEmpty ||
        queryBuilder.getGroupByQuery().isNotEmpty) {
      return getMapResult(queryResult);
    }

    /// a generated fromMap() reads the dates of the driver as they are
    List<Map<String, dynamic>> result = self.readsRowDates
        ? queryResult
        : getMapResult(queryResult);
    List<String> preloads = self.customPreloadList;
    List<String> aggregateKeys = queryBuilder.aggregateKeys;
    Set<String> existsKeys = aggregateKeys.isEmpty
        ? const <String>{}
        : queryBuilder.existsKeys;
    List<T> ret = <T>[];

    /// a many to many query: each row keeps the pivot settings
    Object? pivot = manyToManyQuery[queryBuilder];
    bool onWrite = queryBuilder.usesWriteConnection;
    for (Map<String, dynamic> e in result) {
      Model<dynamic> res = self.fromMap(e);
      res.originalMap = e;
      if (pivot != null) manyToManyRow[res] = pivot;

      /// so save() and delete() on this model use the same connection
      res.connection = queryBuilder.connection;

      /// so its relations read from the same database
      if (onWrite) res.onWriteConnection();
      for (String preload in preloads) {
        res.preload(preload);
      }
      for (String key in aggregateKeys) {
        dynamic value = e[key];

        /// mysql and sqlite give 1 or 0 for EXISTS
        if (existsKeys.contains(key)) {
          value = value == true || value == 1 || value == '1';
        }
        res.setAggregate(key, value);
      }
      ret.add(res as T);
    }

    /// no relations to load: skip the preload work
    if (ret.isNotEmpty && queryBuilder.getPreload().isNotEmpty) {
      return _preload(ret);
    }
    return ret;
  }

  Future<List<T>> _preload(List<T> ret) async {
    List<Model<T>> models = ret as List<Model<T>>;
    QueryCancelToken? token = queryBuilder.cancelToken;
    if (token == null) {
      await queryBuilder.initPreload(models);
      return ret;
    }

    /// the relation queries take the token from the models. only while
    /// they are made: a later save() of a model does not use it.
    for (Model<T> m in models) {
      m.cancelToken = token;
    }
    try {
      await queryBuilder.initPreload(models);
    } finally {
      for (Model<T> m in models) {
        m.cancelToken = null;
      }
    }
    return ret;
  }

  /// snake case name of the model type, eg. `BlogInfo` is `blog_info`
  String tableNameOf(Type type) {
    return _snakeNames[type] ??= toSnakeCase(type.toString());
  }

  String toSnakeCase(String input) {
    String snakeCase = '';
    for (int i = 0; i < input.length; i++) {
      String char = input[i];
      // only letters have an upper case: digits and `_` stay as they are
      if (char != char.toLowerCase() && i > 0) {
        snakeCase += '_'; // Add an underscore if it's uppercase and not the first character
      }
      snakeCase += char.toLowerCase(); // Convert the character to lowercase and add it to the result
    }
    return snakeCase.replaceAll(RegExp(r'_+'), '_');
  }
}
