import 'package:dox_orm/dox_orm.dart';

import 'utils/helper.dart';

/// the query building state of a [QueryBuilder]: where, order, limit and
/// the other parts. A query makes it on the first query method. A model
/// row from get() never makes it, so each row stays small.
///
/// It is not exported by the package. The fields are public only so the
/// query files (each one its own library) can read them.
class QueryState<T> {
  QueryBuilderHelper<T>? helper;
  Map<String, dynamic>? substitutionValues;
  dynamic self;

  /// null means `id`
  String? primaryKey;

  /// null means [SqlQueryBuilder.debug]
  bool? debug;
  bool onWrite = false;

  /// strict mode: an eager load query of the ORM, it never warns about a
  /// big result
  bool strictSkip = false;

  /// null means the default of the class
  bool? isSoftDeletes;
  bool withTrashed = false;
  bool trashedOnly = false;

  /// null means an empty name
  String? tableName;
  String? tableAlias;
  QueryCancelToken? cancelToken;
  bool keySet = false;
  bool globalScopesDone = false;
  bool noGlobalScopes = false;
  Set<String>? skippedScopes;

  // limit.dart, the lock is a private enum there
  int? limit;
  int? offset;
  Object? lock;

  // where.dart
  List<String>? wheres;
  int subqueryCount = 0;

  /// the first where when it is a plain `column = value`, its column and
  /// its param key. getFirst() uses it only while it is still the one
  /// where of the query.
  String? firstWhere;
  String? firstWhereColumn;
  String? firstWhereKey;

  // select.dart
  String select = '*';
  Map<String, dynamic>? selectValues;
  bool selectValuesAdded = false;
  bool selectSet = false;
  bool distinct = false;
  String? fromSub;

  // order_by.dart
  List<String>? orderBy;
  List<(String, bool)>? orderColumns;
  bool rawOrder = false;

  // group_by.dart
  String groupBy = '';
  List<String>? havings;

  // join.dart, raw.dart, union.dart
  List<String>? joins;
  String rawQuery = '';
  List<String>? unions;

  // with_count.dart, a list of a private class there
  Object? aggregates;
  int hasCount = 0;
}
