/// thrown by firstOrFail() and findOrFail() when no row matches
///
/// ```
/// try {
///   Blog blog = await Blog().findOrFail(1);
/// } on ModelNotFoundException catch (e) {
///   print(e.table); // blog
///   print(e.id); // 1
/// }
/// ```
class ModelNotFoundException implements Exception {
  /// the table of the query
  final String table;

  /// the value that findOrFail() looked for. null for firstOrFail().
  final dynamic id;

  /// the column that findOrFail() looked in, like `id`.
  /// null for firstOrFail().
  final String? column;

  const ModelNotFoundException(this.table, {this.id, this.column});

  @override
  String toString() {
    if (column == null) {
      return 'ModelNotFoundException: no row found in table "$table"';
    }
    return 'ModelNotFoundException: no row found in table "$table" '
        'where $column = $id';
  }
}
