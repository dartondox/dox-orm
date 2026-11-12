import 'package:dox_orm/dox_orm.dart';

import 'keys.dart';

/// the `where <name>_type = <type of the owner>` of [morphMany] and
/// [morphOne]
dynamic Function(dynamic) _whereType(
  String column,
  String type,
  dynamic onQuery,
) {
  return (dynamic q) {
    /// with the table name, so a join in onQuery can not make it unclear
    q.where('${tableRef(q as QueryBuilder<dynamic>)}.$column', type);
    return onQuery == null ? q : onQuery(q);
  };
}

/// polymorphic one to many relation query, like a post that has many
/// comments: `comment.commentable_id = post.id` and
/// `comment.commentable_type = 'post'`.
M? morphMany<T, M>(
  List<Model<T>> list,
  Model<M> Function() model, {
  required String name,
  String? typeColumn,
  String? idColumn,
  String? localKey,
  dynamic onQuery,
}) {
  if (list.isEmpty) return null;
  return hasMany<T, M>(
    list,
    model,
    foreignKey: idColumn ?? '${name}_id',
    localKey: localKey,
    onQuery: _whereType(
      typeColumn ?? '${name}_type',
      Model.morphTypeOf(list.first),
      onQuery,
    ),
  );
}

/// get the result of [morphMany], keyed by each owner primary key
Future<Map<String, List<M>>> getMorphMany<T, M>(
  dynamic q,
  List<Model<T>> list,
) {
  return getHasMany<T, M>(q, list);
}

/// polymorphic one to one relation query, see [morphMany]
M? morphOne<T, M>(
  List<Model<T>> list,
  Model<M> Function() model, {
  required String name,
  String? typeColumn,
  String? idColumn,
  String? localKey,
  dynamic onQuery,
}) {
  if (list.isEmpty) return null;
  return hasOne<T, M>(
    list,
    model,
    foreignKey: idColumn ?? '${name}_id',
    localKey: localKey,
    onQuery: _whereType(
      typeColumn ?? '${name}_type',
      Model.morphTypeOf(list.first),
      onQuery,
    ),
  );
}

/// get the result of [morphOne], keyed by each owner primary key
Future<Map<String, M>> getMorphOne<T, M>(dynamic q, List<Model<T>> list) {
  return getHasOne<T, M>(q, list);
}

/// the settings of each morphTo query, so [getMorphTo] can make the
/// queries of the other types
final Expando<(_MorphTo, String)> _morphTos = Expando<(_MorphTo, String)>();

class _MorphTo {
  final String typeColumn;
  final String idColumn;
  final String? ownerKey;
  final dynamic onQuery;

  const _MorphTo(this.typeColumn, this.idColumn, this.ownerKey, this.onQuery);

  /// the type of [m], null when it has none. An empty type is no type.
  String? typeOf(Model<dynamic> m) {
    String? type = relationKey(m, typeColumn)?.toString();
    return type == null || type.isEmpty ? null : type;
  }

  /// the query of the [type] models that [list] points to
  Model<dynamic> query(String type, List<Model<dynamic>> list) {
    Model<dynamic> owner = list.first;
    Model<dynamic> related = Model.morphModel(type);
    related.connection ??= owner.connection;
    related.debug(owner.shouldDebug);
    related.whereIn(
      ownerKey ?? related.primaryKey,
      uniqueKeys(<dynamic>[
        for (Model<dynamic> m in list)
          if (typeOf(m) == type) relationKey(m, idColumn),
      ]),
    );
    if (onQuery != null) related = onQuery(related);
    return related;
  }
}

/// the inverse of [morphMany] and [morphOne]: a comment that belongs to
/// a post or a video. The `<name>_type` column picks the model from the
/// morph map, see [Model.morphMap].
///
/// It is the query of the type of the first owner that has a type.
/// [getMorphTo] reads the other types too.
M? morphTo<T, M>(
  List<Model<T>> list, {
  required String name,
  String? typeColumn,
  String? idColumn,
  String? ownerKey,
  dynamic onQuery,
}) {
  if (relationSubquery) {
    throw UnsupportedError(
      'whereHas() and withCount() do not work with a morphTo relation',
    );
  }
  _MorphTo m = _MorphTo(
    typeColumn ?? '${name}_type',
    idColumn ?? '${name}_id',
    ownerKey,
    onQuery,
  );
  for (Model<T> owner in list) {
    String? type = m.typeOf(owner);
    if (type == null) continue;
    Model<dynamic> q = m.query(type, list);
    _morphTos[q] = (m, type);
    return q as M;
  }
  return null;
}

/// get the result of [morphTo], keyed by each owner primary key
Future<Map<String, M>> getMorphTo<T, M>(dynamic q, List<Model<T>> list) async {
  (_MorphTo, String)? first = q == null ? null : _morphTos[q as Object];
  if (first == null) return <String, M>{};
  _MorphTo m = first.$1;

  /// one query for each type, the first one is [q]
  Map<String, Model<dynamic>> queries = <String, Model<dynamic>>{
    first.$2: q as Model<dynamic>,
  };
  for (Model<T> owner in list) {
    String? type = m.typeOf(owner);
    if (type == null || queries.containsKey(type)) continue;
    queries[type] = m.query(type, list);
  }

  /// `type|key` => model. one query at a time, so it works in a
  /// transaction too.
  Map<String, M> found = <String, M>{};
  for (MapEntry<String, Model<dynamic>> e in queries.entries) {
    for (dynamic r in await e.value.get()) {
      Model<dynamic> row = r as Model<dynamic>;
      dynamic key = relationKey(row, m.ownerKey ?? row.primaryKey);
      found['${e.key}|$key'] = r as M;
    }
  }

  Map<String, M> byOwner = <String, M>{};
  for (Model<T> owner in list) {
    M? value = found['${m.typeOf(owner)}|${relationKey(owner, m.idColumn)}'];
    if (value != null) byOwner[owner.tempIdValue.toString()] = value;
  }
  return byOwner;
}
