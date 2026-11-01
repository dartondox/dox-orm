/// thrown when a model with no `fillable` (and the default `guarded`)
/// gets a map in create(), insert(), update() and the like. Such a model
/// takes no key from a map, so it throws instead of saving an empty row.
///
/// To fix it, list the columns that may be set from a map:
///
/// ```
/// @override
/// List<String> get fillable => <String>['name', 'email'];
/// ```
///
/// or take every key (not safe with user input):
///
/// ```
/// @override
/// List<String> get guarded => const <String>[];
/// ```
class MassAssignmentException implements Exception {
  /// the model class, like `User`
  final String model;

  /// the keys of the map
  final List<String> keys;

  const MassAssignmentException(this.model, this.keys);

  @override
  String toString() =>
      'MassAssignmentException: $model has no fillable columns, so it can '
      'not take ${keys.join(', ')} from a map. Add `fillable` to $model '
      'with the columns that may be set, or set `guarded` to an empty '
      'list to take every key.';
}
