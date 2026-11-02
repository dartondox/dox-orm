/// How many to many writes match related ids. Not exported: only
/// many_to_many.dart and its tests use it.
library;

/// 2^53: past it, a double can not hold every whole number
const double _maxSafe = 9007199254740992.0;

/// a `.0` or `.000` at the end of a number text
final RegExp _zeroEnd = RegExp(r'\.0+$');

/// [id] as an int, or null.
///
/// An int is itself. A double is an int when it is a whole number within
/// ±2^53. A text is read in Dart: it is trimmed, a `.0` end is dropped,
/// then `int.tryParse` reads it (`' 1'`, `'+1'`, `'01'`, `'1.0'`,
/// `'9007199254740993.0'`), else `double.tryParse` with the same double
/// rule (`'1.'`, `'1e0'`). This is only how Dart matches a text to a
/// number id. The databases read some texts in other ways: `int.tryParse`
/// takes `'0x1'` as 1, Postgres does too, MariaDB reads it as 0 and MySQL
/// throws.
///
/// A text that only reads as a double at or past ±2^53 (like `'1e20'`,
/// `'9007199254740993.'` or `'9007199254740993.5'`) is not exact, so it
/// could match the wrong row. With [strict] (a given id) it throws an
/// [ArgumentError]. Without it (a stored value) it is null, so it does
/// not match a number.
int? intId(dynamic id, {bool strict = true}) {
  if (id is int) return id;
  if (id is String) {
    String text = id.trim();
    int? i = int.tryParse(text.replaceFirst(_zeroEnd, ''));
    if (i != null) return i;
    double? d = double.tryParse(text);
    if (d != null && d.isFinite && d.abs() >= _maxSafe) {
      if (!strict) return null;
      throw ArgumentError.value(id, 'ids', 'is a number that is not exact');
    }
    id = d;
  }
  if (id is double && id == id.truncateToDouble() && id.abs() <= _maxSafe) {
    return id.toInt();
  }
  return null;
}

/// true when the ids [given] and [stored] are the same.
///
/// Two texts only match by the exact text, so `'007'` and `'7'` are two
/// ids. The ORM does not know the type of the key column, and on a text
/// key they are two rows. The cost: `['1', '01']` on a number key are two
/// ids.
///
/// When one of them is a number (`int` or `double`), the text is read as
/// a number (see [intId]), so `1`, `1.0`, `'01'` and `'1e0'` are the same
/// id. A number key comes back from the database as a number, so this keeps
/// the stored rows of a number key. A number that is not a whole id,
/// like a stored `1.5` (SQLite), matches the same finite double.
///
/// [stored] is a value read from the table. It never throws (see [intId]),
/// so a long digit text in a text key column does not stop a write. Only
/// [given], an id from the call, can throw.
bool sameId(dynamic given, dynamic stored) {
  dynamic a = given;
  dynamic b = stored;

  /// no `a == b` first: Dart says `9007199254740993 == 9007199254740992.0`
  if (a is! num && b is! num) return a == b;
  int? x = intId(a);
  int? y = intId(b, strict: false);
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
