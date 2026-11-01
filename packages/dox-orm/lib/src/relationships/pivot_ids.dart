/// How many to many writes match related ids. Not exported: only
/// many_to_many.dart and its tests use it.
library;

/// [id] as an int when it is a whole number that fits in an int, or a
/// text of only digits (with an optional `-`, and spaces around it, like
/// the database reads it), else null. A double out of the int range, like
/// `1e20`, is not a number id: `toInt()` would clamp it to the max int.
int? intId(dynamic id) {
  if (id is int) return id;
  if (id is double &&
      id == id.truncateToDouble() &&
      id > -_intLimit &&
      id < _intLimit) {
    return id.toInt();
  }
  if (id is String) {
    String text = id.trim();
    if (_digits.hasMatch(text)) return int.tryParse(text);
  }
  return null;
}

/// 2^63, the first double that does not fit in a 64-bit int
const double _intLimit = 9223372036854775808.0;

final RegExp _digits = RegExp(r'^-?[0-9]+$');

/// true when the ids [a] and [b] are the same. Two number ids (see
/// [intId]) are the same when their int is the same, so `'01'`, `1.0`
/// and `1` are the same id. Any other ids must be equal, so `'1.5'` or
/// `'abc'` only match the same text.
bool sameId(dynamic a, dynamic b) {
  if (a == b) return true;
  int? x = intId(a);
  return x != null && x == intId(b);
}
