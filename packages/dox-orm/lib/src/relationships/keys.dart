import 'package:dox_orm/dox_orm.dart';

/// the value of [key] in [model]. the primary key is read without
/// making a map.
dynamic relationKey(Model<dynamic> model, String key) {
  return key == model.primaryKey
      ? model.tempIdValue
      : model.columnsToMap()[key];
}

/// the values of [key] in [list], each once and without null
List<dynamic> relationKeys(List<Model<dynamic>> list, String key) {
  return uniqueKeys(<dynamic>[
    for (Model<dynamic> i in list) relationKey(i, key),
  ]);
}

/// [keys] each once and without null
List<dynamic> uniqueKeys(List<dynamic> keys) {
  return keys.toSet().where(_notNull).toList();
}

bool _notNull(dynamic value) => value != null;

/// the local key of each hasOne, hasMany or through query, so the
/// result can be matched to the owners
final Expando<String> relationLocalKeys = Expando<String>();

/// true while withCount() or whereHas() makes a relation query. the
/// relation query then matches the parent row with a column compare (not
/// with the ids of loaded models), so it can run as a subquery.
bool relationSubquery = false;

/// the param key prefix of the relation query made while
/// [relationSubquery] is true. it is set before `onQuery` runs, so the
/// keys of `onQuery` do not clash with the keys of the parent query.
String subqueryKeyPrefix = '';

/// true while withCount() makes a relation query. withCount() does not
/// work with belongsTo, whereHas() does.
bool aggregateSubquery = false;

/// adds the where and the nested relations of `preload()` to a
/// relation query
typedef PreloadQuery = void Function(QueryBuilder<dynamic> query);

/// the [PreloadQuery] for the relation query that is made now. `Model`
/// sets it only while a relation load starts, and only when `preload()`
/// has a dot path or a where. See [takePreloadQuery].
PreloadQuery? preloadQuery;

/// gives [preloadQuery] and clears it. A relation query takes it first,
/// before its `onQuery` runs, so a relation query made inside `onQuery`
/// (like a `whereHas()`) does not get it.
PreloadQuery? takePreloadQuery() {
  PreloadQuery? f = preloadQuery;
  preloadQuery = null;
  return f;
}

/// starts the subquery of [child]. it sets the param key prefix, and
/// an alias when [child] and [parent] use the same table (like a parent
/// category), so the subquery rows and the parent rows have their own
/// names.
void startSubquery(Model<dynamic> child, Model<dynamic> parent) {
  child.helper.keyPrefix = subqueryKeyPrefix;
  if (child.tableName == parent.tableName) {
    child.tableAlias = '${subqueryKeyPrefix}t';
  }
}

/// the name of the table of [q] in the sql: its alias or its table name
String tableRef(QueryBuilder<dynamic> q) => q.tableAlias ?? q.tableName;

/// the table of [q] for `FROM`, like `"category" AS "dox_has0_t"`
String fromTable(QueryBuilder<dynamic> q) {
  String table = q.helper.wrap(q.tableName);
  String? alias = q.tableAlias;
  return alias == null ? table : '$table AS ${q.helper.wrap(alias)}';
}

/// the condition `child.foreignKey = parent.localKey` of a subquery
String subqueryMatch(
  Model<dynamic> child,
  String childColumn,
  Model<dynamic> parent,
  String parentColumn,
) {
  return '${child.helper.wrap(childColumn)} = '
      '${child.helper.wrap('${tableRef(parent)}.$parentColumn')}';
}

/// the pivot settings of a many to many query
final Expando<Object> manyToManyQuery = Expando<Object>();

/// the pivot settings of a row that such a query read. get() copies it
/// from the query, so `pivot` has the two keys for `related().get()`
/// too. It is a second Expando because a row is also a query: a new
/// query made from a row must not give its rows the settings.
final Expando<Object> manyToManyRow = Expando<Object>();
