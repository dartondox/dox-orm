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
  Future<int> delete() async {
    if (isSoftDeletes) {
      return await queryBuilder.update(<String, dynamic>{'deleted_at': now()});
    }
    return await forceDelete();
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
    q += helper.getCommonQuery();
    return await runAffectingQuery(queryBuilder, q);
  }
}
