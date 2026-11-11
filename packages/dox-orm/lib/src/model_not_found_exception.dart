import 'package:dox_annotation/dox_annotation.dart';

/// thrown by firstOrFail() and findOrFail() when no row matches
///
/// In a Dox app it answers 404 with
/// `{"code": "not_found", "message": "Not Found"}`, like Laravel.
/// The table, column and id are not sent to the client.
///
/// ```
/// try {
///   Blog blog = await Blog().findOrFail(1);
/// } on ModelNotFoundException catch (e) {
///   print(e.table); // blog
///   print(e.id); // 1
/// }
/// ```
class ModelNotFoundException extends IHttpException implements Exception {
  /// the table of the query
  final String table;

  /// the value that findOrFail() looked for. null for firstOrFail().
  final dynamic id;

  /// the column that findOrFail() looked in, like `id`.
  /// null for firstOrFail().
  final String? column;

  /// not `const`: [IHttpException] has fields that can change.
  ModelNotFoundException(this.table, {this.id, this.column}) {
    code = 404;
    errorCode = 'not_found';
    message = 'Not Found';
  }

  @override
  String toString() {
    if (column == null) {
      return 'ModelNotFoundException: no row found in table "$table"';
    }
    return 'ModelNotFoundException: no row found in table "$table" '
        'where $column = $id';
  }
}

/// thrown by sole() when more than one row matches
///
/// ```
/// try {
///   Blog blog = await Blog().where('status', 'active').sole();
/// } on MultipleRecordsFoundException catch (e) {
///   print(e.table); // blog
/// }
/// ```
class MultipleRecordsFoundException implements Exception {
  /// the table of the query
  final String table;

  const MultipleRecordsFoundException(this.table);

  @override
  String toString() =>
      'MultipleRecordsFoundException: more than one row found in table '
      '"$table"';
}
