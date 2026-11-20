import 'dart:collection';

import '../model.dart';
import 'logger.dart';

/// One stored value that a cast did not know, like `"archived"` for an
/// enum with no `archived`.
typedef _Unknown = ({String column, Object value, Object? result, String type});

/// Reads rows into models, and handles stored values that a cast does
/// not know (see `EnumCast`). A cast only gets the value, not the
/// column. So a row is read once as normal. Only when a cast saw an
/// unknown value, the row is read again with a map that tells which
/// column the cast is reading. Normal rows pay one bool check.
class CastReads {
  /// a cast saw an unknown value in this read
  static bool _seen = false;

  /// the map of the second read, and the unknown values it found
  static _KeyMap? _map;
  static List<_Unknown>? _found;

  /// warned (table, column, value) keys, so the log is not spammed
  static final Set<String> _warned = <String>{};

  // ponytail: at most this many warned keys, then no more warnings. A
  // table full of different bad values can not grow the set without end.
  static const int _maxWarned = 1000;

  /// model => column => the cast value it got for an unknown stored
  /// value. save() skips such a column while the field still has that
  /// value, so the stored value is not overwritten.
  static final Expando<Map<String, dynamic>> _unknownColumns =
      Expando<Map<String, dynamic>>();

  /// a cast calls it for a stored [value] it does not know. [result] is
  /// what the cast gives back for it (null, or a fallback). [type] is
  /// the name of the Dart type, like `Status`.
  static void unknown(Object value, Object? result, String type) {
    _seen = true;
    _KeyMap? map = _map;
    if (map == null) return;
    (_found ??= <_Unknown>[]).add((
      column: map.lastKey,
      value: value,
      result: result,
      type: type,
    ));
  }

  /// [self].fromMap([row]), with the unknown values handled. A row from
  /// the database is lenient. [input] are the keys of [row] that the app
  /// gave (create, fill): an unknown value there throws an
  /// [ArgumentError], so bad input is never saved. null: a database row.
  static Model<dynamic> read(
    Model<dynamic> self,
    Map<String, dynamic> row, {
    Iterable<String>? input,
  }) {
    _seen = false;
    try {
      Model<dynamic> model = self.fromMap(row);
      if (!_seen) return model;
    } on TypeError {
      /// a field that can not be null got null for an unknown value
      if (!_seen) rethrow;
    }
    return _readAgain(self, row, input?.toSet());
  }

  /// the columns of [model] that got a cast value for an unknown stored
  /// value, with that value. null when there are none.
  static Map<String, dynamic>? unknownColumns(Model<dynamic> model) =>
      _unknownColumns[model];

  /// set the unknown columns of [model], see [unknownColumns]
  static void setUnknownColumns(
    Model<dynamic> model,
    Map<String, dynamic>? columns,
  ) => _unknownColumns[model] = columns;

  /// the second read: now each unknown value knows its column
  static Model<dynamic> _readAgain(
    Model<dynamic> self,
    Map<String, dynamic> row,
    Set<String>? input,
  ) {
    _KeyMap map = _KeyMap(row);
    List<_Unknown> found = <_Unknown>[];
    _map = map;
    _found = found;
    Model<dynamic> model;
    try {
      model = self.fromMap(map);
    } on TypeError {
      _Unknown? last = found.isEmpty ? null : found.last;
      if (last != null && input != null && input.contains(last.column)) {
        throw _badInput(self, last);
      }

      /// the cast of the last read column gave null for an unknown value,
      /// and the field can not be null
      if (last != null && last.column == map.lastKey && last.result == null) {
        throw StateError(
          '${_where(self, last)}: the stored value "${last.value}" is not '
          'a ${last.type} value, and the field can not be null. Make the '
          'field nullable, or give the cast a fallback, like '
          'EnumCast(${last.type}.values, unknown: ...).',
        );
      }
      rethrow;
    } finally {
      _map = null;
      _found = null;
    }
    if (input != null) {
      for (_Unknown u in found) {
        if (input.contains(u.column)) throw _badInput(self, u);
      }
    }
    Map<String, dynamic> columns = model.columnsToMap();
    _unknownColumns[model] = <String, dynamic>{
      for (_Unknown u in found) u.column: columns[u.column],
    };
    for (_Unknown u in found) {
      _warn(self, u);
    }
    return model;
  }

  /// a value that the app gave and the cast does not know
  static ArgumentError _badInput(Model<dynamic> self, _Unknown u) =>
      ArgumentError(
        '${_where(self, u)}: "${u.value}" is not a ${u.type} value.',
      );

  /// one warning for each table, column and value
  static void _warn(Model<dynamic> self, _Unknown u) {
    try {
      String key = '${self.tableName}\n${u.column}\n${u.value}';
      if (_warned.contains(key) || _warned.length >= _maxWarned) return;
      _warned.add(key);
      Object? result = u.result;
      String reads = result is Enum ? '${u.type}.${result.name}' : '$result';
      Logger.warn(
        '${_where(self, u)}: the stored value "${u.value}" is not a '
        '${u.type} value. It reads as $reads. Saving the model does not '
        'change it, unless you set the field.',
      );
    } catch (_) {
      /// a warning must never fail the app
    }
  }

  static String _where(Model<dynamic> self, _Unknown u) {
    String table = self.tableName;
    return table.isEmpty
        ? '${self.runtimeType}, column "${u.column}"'
        : 'Table "$table", column "${u.column}"';
  }

  /// forget the warned keys. It is for tests.
  static void resetWarnings() => _warned.clear();
}

/// a row that remembers the last key that was read
class _KeyMap extends MapView<String, dynamic> {
  _KeyMap(super.map);

  String lastKey = '';

  @override
  dynamic operator [](Object? key) {
    if (key is String) lastKey = key;
    return super[key];
  }
}
