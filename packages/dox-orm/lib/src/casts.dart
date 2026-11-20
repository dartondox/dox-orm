import 'dart:convert';

import 'utils/cast_reads.dart' show CastReads;

/// Changes a column value between the database and Dart.
/// Use it with `@Column(cast: ...)`. The class needs a const constructor.
///
/// ```
/// class MoneyCast extends Cast<Money> {
///   const MoneyCast();
///
///   @override
///   Money? get(dynamic value) => value == null ? null : Money(value as int);
///
///   @override
///   dynamic set(Money? value) => value?.cents;
/// }
///
/// @Column(cast: MoneyCast())
/// Money? price;
/// ```
abstract class Cast<T> {
  const Cast();

  /// the value from the database to the Dart value
  T? get(dynamic value);

  /// the Dart value to the value for the database (and toJson)
  dynamic set(T? value);
}

/// A json column (or json text) to a map or list.
/// The drivers save a map or list as json text.
class JsonCast extends Cast<dynamic> {
  const JsonCast();

  @override
  dynamic get(dynamic value) => value is String ? jsonDecode(value) : value;

  @override
  dynamic set(dynamic value) => value;
}

/// A json column (or json text) to a typed list, like `List<String>`.
class ListCast<E> extends Cast<List<E>> {
  const ListCast();

  @override
  List<E>? get(dynamic value) {
    dynamic list = value is String ? jsonDecode(value) : value;
    return list == null ? null : List<E>.from(list as List<dynamic>);
  }

  @override
  dynamic set(List<E>? value) => value;
}

/// A bool from a bool, a number (like tinyint 0 and 1) or a text
/// (`1`, `0`, `true`, `false`, `t`, `f`).
/// A `bool` field gets it without `cast`.
class BoolCast extends Cast<bool> {
  const BoolCast();

  @override
  bool? get(dynamic value) {
    if (value == null || value is bool) return value as bool?;
    if (value is num) return value != 0;
    String text = value.toString().toLowerCase();
    return text == '1' || text == 'true' || text == 't';
  }

  @override
  dynamic set(bool? value) => value;
}

/// An enum, saved by its name, or by its index with `byIndex: true`.
/// An enum field gets `EnumCast(values)` (by name) without `cast`.
///
/// ```
/// @Column(cast: EnumCast(Status.values, byIndex: true))
/// Status? status;
/// ```
///
/// A stored value that the enum does not have (an old name, or an index
/// out of range) does not fail the query. The field gets [unknown], or
/// null, and the ORM logs one warning for each table, column and value.
/// A field that can not be null and has no [unknown] throws a
/// [StateError] that names the column and the value. Saving the model
/// does not overwrite the stored value, unless you set the field.
///
/// ```
/// @Column(cast: EnumCast(Status.values, unknown: Status.other))
/// Status? status;
/// ```
class EnumCast<E extends Enum> extends Cast<E> {
  final List<E> values;
  final bool byIndex;

  /// the value for a stored value that the enum does not have
  final E? unknown;

  const EnumCast(this.values, {this.byIndex = false, this.unknown});

  @override
  E? get(dynamic value) {
    if (value == null) return null;
    E? found = byIndex ? _byIndex(value) : _byName(value.toString());
    if (found != null) return found;
    CastReads.unknown(value as Object, unknown, '$E');
    return unknown;
  }

  E? _byIndex(dynamic value) {
    int? index = int.tryParse(value.toString());
    if (index == null || index < 0 || index >= values.length) return null;
    return values[index];
  }

  E? _byName(String name) {
    for (E value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  @override
  dynamic set(E? value) => byIndex ? value?.index : value?.name;
}
