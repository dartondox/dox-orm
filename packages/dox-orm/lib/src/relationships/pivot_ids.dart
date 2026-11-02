/// How many to many writes match related ids. Not exported: only
/// many_to_many.dart and its tests use it.
library;

/// [id] as an int when it is a whole number that fits in an int, or a
/// text of a whole number, else null. The text can have a `+` or `-`, a
/// `.0` end, and spaces around it, because the databases store `'+1'`,
/// `'1.0'` and `' 1'` as `1` in a number column. A double out of the int range, like
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
    Match? m = _wholeNumber.firstMatch(text);
    if (m != null) return int.tryParse(m[1]!);
  }
  return null;
}

/// 2^63, the first double that does not fit in a 64-bit int
const double _intLimit = 9223372036854775808.0;

/// a whole number text; group 1 is the part before the `.0`
final RegExp _wholeNumber = RegExp(r'^([+-]?[0-9]+)(\.0+)?$');

/// true when the ids [a] and [b] are the same.
///
/// When one of them is a number (`int` or `double`), the number rule of
/// [intId] is used: `1`, `1.0`, `'01'` and `' 1'` are the same id. The
/// database reads a number key as a number, so this is how it matches.
///
/// Two texts only match by the exact text, so `'007'` and `'7'` are two
/// ids. The ORM does not know the type of the key column, and on a text
/// key they are two rows. The cost: `['1', '01']` on a number key gives
/// two ids.
bool sameId(dynamic a, dynamic b) {
  if (a == b) return true;
  if (a is! num && b is! num) return false;
  int? x = intId(a);
  return x != null && x == intId(b);
}
