import 'package:dox_orm/dox_orm.dart';

import 'keys.dart';

/// (foreign key value of each child, local key) used by each query, so
/// the result can be matched to the children. the values are read once:
/// a generated model makes a map of all its columns to read one.
final Expando<(List<dynamic>, String)> _keys =
    Expando<(List<dynamic>, String)>();

/// belongs to relationship query.
///
/// the default [foreignKey] comes from the owner class: `User` gives
/// `user_id`. With [OrmFlags.belongsToKeyFromRelation] and a
/// [relation] name, it comes from the relation name and the owner
/// primary key: `author` gives `author_id`.
M? belongsTo<T, M>(
  List<Model<T>> list,
  Model<M> Function() model, {
  String? foreignKey,
  String? localKey,
  dynamic onQuery,
  String? relation,
}) {
  if (list.isEmpty) return null;
  if (relationSubquery && aggregateSubquery) {
    throw UnsupportedError(
      'withCount() works with hasOne, hasMany and manyToMany relations.',
    );
  }

  PreloadQuery? preload = takePreloadQuery();
  Model<T> foreign = list.first;
  Model<M> owner = model().debug(foreign.shouldDebug);
  owner.useConnectionOf(foreign);
  localKey = localKey ?? owner.primaryKey;
  if (foreignKey == null &&
      relation != null &&
      SqlQueryBuilder().flags.belongsToKeyFromRelation) {
    foreignKey = '${owner.helper.toSnakeCase(relation)}_${owner.primaryKey}';
  }
  foreignKey ??= owner.foreignKeyName;

  List<dynamic> childKeys = const <dynamic>[];
  if (relationSubquery) {
    startSubquery(owner, foreign);
    owner.whereRaw(
      subqueryMatch(owner, '${tableRef(owner)}.$localKey', foreign, foreignKey),
    );
  } else {
    /// each owner once: no join to the children, so an owner with many
    /// children is one row, not one row per child
    childKeys = <dynamic>[for (Model<T> i in list) relationKey(i, foreignKey)];
    owner.whereIn('${owner.tableName}.$localKey', uniqueKeys(childKeys));
  }

  if (onQuery != null) {
    owner = onQuery(owner);
  }
  preload?.call(owner);
  _keys[owner] = (childKeys, localKey);
  return owner as M;
}

/// get result from belongs to relationship query
/// the result is keyed by each child primary key (tempIdValue).
Future<Map<String, M>> getBelongsTo<T, M>(
  dynamic q,
  List<Model<T>> list,
) async {
  if (q == null) return <String, M>{}; // coverage:ignore-line
  List<M> results = await q.get();
  var (List<dynamic> childKeys, String localKey) = _keys[q]!;

  /// owners by their local key value
  Map<String, M> owners = <String, M>{};
  for (M r in results) {
    owners[relationKey(r as Model<M>, localKey).toString()] = r;
  }

  /// match each child by its foreign key
  Map<String, M> ret = <String, M>{};
  for (int i = 0; i < list.length; i++) {
    M? owner = owners[childKeys[i].toString()];
    if (owner != null) {
      ret[list[i].tempIdValue.toString()] = owner;
    }
  }
  return ret;
}
