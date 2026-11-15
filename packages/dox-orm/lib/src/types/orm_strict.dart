import 'package:dox_orm/src/utils/logger.dart';

/// Strict mode for development. When it is on, the ORM logs a warning
/// for two slow mistakes:
///
/// - N+1: the same relation is loaded row by row (with `$getRelation()`
///   or `related()`) many times in a short time. Use `preload()` to load
///   it for all rows in one query.
/// - Big result: `get()` or `all()` with no `limit()` reads more rows
///   into memory than [maxRows]. Use `paginate()`, `chunk()`, `lazy()`
///   or `cursor()`.
///
/// It is off by default. A warning only logs, it never throws.
///
/// ```
/// DatabaseConfig databaseConfig = DatabaseConfig(
///   connection: 'postgres',
///   connections: connections,
///   strict: OrmStrict(enabled: appConfig.isDevelopment),
/// );
/// ```
class OrmStrict {
  /// turn the warnings on
  final bool enabled;

  /// warn when one relation of one model is loaded row by row this many
  /// times in a short time (about one second)
  final int nPlusOneCount;

  /// warn when one `get()` or `all()` reads more rows than this
  final int maxRows;

  const OrmStrict({
    this.enabled = true,
    this.nPlusOneCount = 5,
    this.maxRows = 1000,
  });

  /// strict mode off, the default
  const OrmStrict.off() : this(enabled: false);
}

/// counts the row by row relation loads of strict mode. Nothing is kept
/// on the rows. The ORM calls it only when strict mode is on.
class StrictWatch {
  // ponytail: a fixed 1 second window, not one per request. Two requests
  // at the same time that each load a relation a few times can add up
  // to one warning. Add a per request scope if that is too noisy.
  static const int _windowMs = 1000;

  /// at most this many (model, relation) keys in one window, so a big
  /// app can not grow the map without end
  static const int _maxKeys = 200;

  static final Stopwatch _clock = Stopwatch()..start();
  static int _windowStart = 0;
  static final Map<(Type, String), int> _counts = <(Type, String), int>{};

  /// a relation [name] of [model] was loaded for one row
  static void relationLoad(Type model, String name, OrmStrict strict) {
    try {
      int now = _clock.elapsedMilliseconds;
      if (now - _windowStart > _windowMs) {
        _counts.clear();
        _windowStart = now;
      }
      (Type, String) key = (model, name);
      int? old = _counts[key];
      if (old == null && _counts.length >= _maxKeys) return;
      int count = (old ?? 0) + 1;
      _counts[key] = count;

      /// == and not >=, so it warns once per window, not once per row
      if (count == strict.nPlusOneCount) {
        Logger.warn(
          'Strict mode: possible N+1 query. The relation "$name" of '
          '$model was loaded row by row $count times in a short time. '
          "Load it for all rows in one query with preload('$name').",
        );
      }
    } catch (_) {
      /// a warning must never fail the app
    }
  }

  /// a `get()` or `all()` on [table] read [rows] rows
  static void bigResult(String table, int rows, OrmStrict strict) {
    if (rows <= strict.maxRows) return;
    try {
      String name = table.isEmpty ? 'a raw query' : 'table "$table"';
      Logger.warn(
        'Strict mode: one query on $name read $rows rows into memory '
        '(the limit is ${strict.maxRows}). '
        'Use paginate(), chunk(), lazy() or cursor() for big results.',
      );
    } catch (_) {
      /// a warning must never fail the app
    }
  }

  /// forget the counts. It is for tests.
  static void reset() => _counts.clear();
}
