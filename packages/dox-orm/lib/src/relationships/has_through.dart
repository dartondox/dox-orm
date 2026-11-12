import 'package:dox_orm/dox_orm.dart';

import 'keys.dart';

/// has many through relationship query: the far rows of this model,
/// found through a model in the middle.
///
/// A country has many posts through its users:
/// `users.country_id` points to `countries.id`, and
/// `posts.user_id` points to `users.id`.
///
/// - [foreignKey]: the column on the through table that points to this
///   model, default `country_id`.
/// - [localKey]: the column of this model, default its primary key.
/// - [throughForeignKey]: the column on the far table that points to the
///   through model, default `user_id`.
/// - [throughLocalKey]: the column of the through model, default its
///   primary key.
///
/// It is one query with a join to the through table. Soft deleted
/// through rows and soft deleted far rows are left out.
M? hasManyThrough<T, M>(
  List<Model<T>> list,
  Model<M> Function() model, {
  required Model<dynamic> Function() through,
  String? foreignKey,
  String? localKey,
  String? throughForeignKey,
  String? throughLocalKey,
  dynamic onQuery,
}) {
  if (list.isEmpty) return null;
  PreloadQuery? preload = takePreloadQuery();

  Model<T> owner = list.first;
  Model<M> far = model().debug(owner.shouldDebug);
  far.useConnectionOf(owner);
  Model<dynamic> middle = through();

  localKey ??= owner.primaryKey;
  foreignKey ??= owner.foreignKeyName;
  throughForeignKey ??= middle.foreignKeyName;
  throughLocalKey ??= middle.primaryKey;

  if (relationSubquery) startSubquery(far, owner);
  String farTable = tableRef(far);

  /// the through table gets an alias when the parent or the far table
  /// has the same name, like a user with the posts of the users it
  /// manages
  String throughTable = middle.tableName;
  String joinTable = throughTable;
  if (throughTable == owner.tableName || throughTable == far.tableName) {
    throughTable = '${subqueryKeyPrefix}through';
    joinTable = '${middle.tableName} as $throughTable';
  }

  far
      .select('$farTable.*, $throughTable.$foreignKey as _owner_id')
      .join(
        joinTable,
        '$throughTable.$throughLocalKey',
        '$farTable.$throughForeignKey',
      );
  if (middle.isSoftDeletes) far.whereNull('$throughTable.deleted_at');

  if (relationSubquery) {
    far.whereRaw(
      subqueryMatch(far, '$throughTable.$foreignKey', owner, localKey),
    );
  } else {
    far.whereIn('$throughTable.$foreignKey', relationKeys(list, localKey));
  }

  if (onQuery != null) {
    far = onQuery(far);
  }
  preload?.call(far);
  relationLocalKeys[far] = localKey;
  return far as M;
}

/// has one through relationship query, see [hasManyThrough].
///
/// when an owner has many far rows, eager loading keeps the last row the
/// query returns. add an `orderBy` in `onQuery` to pick the row, see
/// `hasOne()`.
M? hasOneThrough<T, M>(
  List<Model<T>> list,
  Model<M> Function() model, {
  required Model<dynamic> Function() through,
  String? foreignKey,
  String? localKey,
  String? throughForeignKey,
  String? throughLocalKey,
  dynamic onQuery,
}) {
  return hasManyThrough<T, M>(
    list,
    model,
    through: through,
    foreignKey: foreignKey,
    localKey: localKey,
    throughForeignKey: throughForeignKey,
    throughLocalKey: throughLocalKey,
    onQuery: onQuery,
  );
}

/// get the result of a has many through query, keyed by each owner
/// primary key (tempIdValue)
Future<Map<String, List<M>>> getHasManyThrough<T, M>(
  dynamic q,
  List<Model<T>> list,
) {
  return getHasMany<T, M>(q, list);
}

/// get the result of a has one through query, keyed by each owner
/// primary key (tempIdValue)
Future<Map<String, M>> getHasOneThrough<T, M>(dynamic q, List<Model<T>> list) {
  return getHasOne<T, M>(q, list);
}
