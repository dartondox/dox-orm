import 'package:dox_orm/dox_orm.dart';

import 'shared_mixin.dart';
import 'update.dart';

mixin Delete<T> implements SharedMixin<T> {
  /// delete the rows of this query and return how many rows it deleted
  ///
  /// if SoftDeletes is used in model it will act as soft delete,
  /// otherwise it will delete completely from record.
  /// a soft delete skips rows that are already soft deleted.
  ///
  /// ```
  /// int count = await Blog().where('id', 1).delete();
  /// ```
  ///
  /// With join(), orderBy() or limit(), the rows are picked by the primary
  /// key, so the table needs that column (MySQL with no join and no offset
  /// does not). groupBy() and having() throw an [ArgumentError].
  Future<int> delete() async {
    if (isSoftDeletes) {
      return await queryBuilder.update(<String, dynamic>{'deleted_at': now()});
    }
    return await forceDelete();
  }

  /// restore the soft deleted rows of this query, like
  /// `Blog().where('status', 'old').restore()`. It sets `deleted_at` to
  /// null and fires no events. It returns true when it
  /// changed a row. A model also sets `updated_at` and has an instance
  /// `blog.restore()`, see [Model.restore].
  ///
  /// With no soft deletes (like a `QueryBuilder.table()` query) it throws
  /// a [StateError].
  Future<bool> restore() async {
    if (!isSoftDeletes) {
      throw StateError(
        'restore() needs a model with soft deletes, like '
        '@DoxModel(softDelete: true).',
      );
    }
    withTrashed = true;

    /// only deleted rows, so every database counts the same rows
    queryBuilder.whereNotNull('$tableName.deleted_at');
    return await queryBuilder.update(<String, dynamic>{'deleted_at': null}) > 0;
  }

  /// force delete the rows of this query and return how many rows it
  /// deleted
  ///
  /// if SoftDeletes is used in model and if you would like to delete
  /// completely from the record, use forceDelete()
  ///
  /// ```
  /// int count = await Blog().where('id', 1).forceDelete();
  /// ```
  Future<int> forceDelete() async {
    /// also delete rows that are already soft deleted
    withTrashed = true;
    String q;
    q = "DELETE FROM ${helper.wrap(tableName)}";
    q += helper.getWriteQuery();
    return await runAffectingQuery(queryBuilder, q);
  }
}
