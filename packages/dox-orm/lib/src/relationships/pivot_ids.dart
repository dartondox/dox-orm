/// How many to many writes match related ids. Not exported: only
/// many_to_many.dart and its tests use it.
library;

/// 2^53: past it, a double can not hold every whole number
const double _maxSafe = 9007199254740992.0;

/// [id] as an int, or null.
///
/// An int is itself. A double is an int when it is a whole number within
/// ±2^53. A text is read like the databases read it, with
/// `int.tryParse` first (`' 1'`, `'+1'`, `'01'`, `'0x1'`), then
/// `double.tryParse` (`'1.0'`, `'1.'`, `'1e0'`), and the same double rule.
int? intId(dynamic id) {
  if (id is int) return id;
  if (id is String) {
    String text = id.trim();
    int? i = int.tryParse(text);
    if (i != null) return i;
    id = double.tryParse(text);
  }
  if (id is double && id == id.truncateToDouble() && id.abs() <= _maxSafe) {
    return id.toInt();
  }
  return null;
}

/// true when the ids [a] and [b] are the same.
///
/// Two texts only match by the exact text, so `'007'` and `'7'` are two
/// ids. The ORM does not know the type of the key column, and on a text
/// key they are two rows. The cost: `['1', '01']` on a number key are two
/// ids.
///
/// When one of them is a number (`int` or `double`), the text is read as
/// a number (see [intId]), so `1`, `1.0`, `'01'`, `'1e0'` and `'0x1'` are
/// the same id. A number key comes back from the database as a number, so
/// this is how the database matches it. A number that is not a whole id,
/// like a stored `1.5` (SQLite), matches the same finite double.
bool sameId(dynamic a, dynamic b) {
  /// no `a == b` first: Dart says `9007199254740993 == 9007199254740992.0`
  if (a is! num && b is! num) return a == b;
  int? x = intId(a);
  int? y = intId(b);
  if (x != null || y != null) return x == y;
  double? c = _double(a);
  double? d = _double(b);
  return c != null && c.isFinite && c == d;
}

double? _double(dynamic id) {
  if (id is num) return id.toDouble();
  if (id is String) return double.tryParse(id.trim());
  return null;
}
