import 'package:dox_orm/dox_orm.dart';

import 'keys.dart';

/// has many relationships query
M? hasMany<T, M>(
  List<Model<T>> list,
  Model<M> Function() model, {
  String? foreignKey,
  String? localKey,
  dynamic onQuery,
}) {
  if (list.isEmpty) return null;

  Model<T> owner = list.first;
  localKey = localKey ?? owner.primaryKey;
  foreignKey = foreignKey ?? owner.foreignKeyName;

  List<dynamic> ids = relationKeys(list, localKey);

  Model<M> m = model().debug(owner.shouldDebug);
  m.useConnectionOf(owner);

  if (relationSubquery) {
    startSubquery(m, owner);
    m.whereRaw(subqueryMatch(m, '${tableRef(m)}.$foreignKey', owner, localKey));
  } else {
    m.select('*, $foreignKey as _owner_id').whereIn(foreignKey, ids);
  }

  if (onQuery != null) {
    m = onQuery(m);
  }
  takePreloadQuery(m);
  relationLocalKeys[m] = localKey;
  return m as M;
}

/// get has many relationships result
/// the result is keyed by each owner primary key (tempIdValue).
Future<Map<String, List<M>>> getHasMany<T, M>(
  dynamic q,
  List<Model<T>> list,
) async {
  if (q == null) return <String, List<M>>{}; // coverage:ignore-line
  List<M> results = await q.get();

  Map<String, List<M>> ret = <String, List<M>>{};

  /// filter matched values with local id value
  for (M r in results) {
    String ownerId = (r as Model<M>).originalMap['_owner_id'].toString();
    if (ret[ownerId] == null) {
      ret[ownerId] = <M>[];
    }
    ret[ownerId]?.add(r);
  }

  /// match each owner by its local key, and use an empty list
  /// instead of null when there is no result
  String? localKey = relationLocalKeys[q];
  Map<String, List<M>> byOwner = <String, List<M>>{};
  for (Model<T> i in list) {
    dynamic key = localKey == null ? i.tempIdValue : relationKey(i, localKey);
    byOwner[i.tempIdValue.toString()] = ret[key.toString()] ?? <M>[];
  }
  return byOwner;
}
