import 'model.dart';
import 'shared_mixin.dart';

mixin SoftDeletes<T> implements SharedMixin<T> {
  @override
  bool isSoftDeletes = true;

  /// true when this model is soft deleted: its `deleted_at` is set.
  ///
  /// ```
  /// Blog? blog = await Blog().withTrash().find(1);
  /// if (blog!.trashed()) await blog.restore();
  /// ```
  bool trashed() {
    Model<T> model = this as Model<T>;
    Map<String, dynamic> columns = model.columnsToMap();

    /// a model with no field for deleted_at keeps it in the saved values
    dynamic value = columns.containsKey('deleted_at')
        ? columns['deleted_at']
        : model.getOriginal('deleted_at');
    return value != null;
  }
}
