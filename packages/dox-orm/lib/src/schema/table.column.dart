import '../types/orm_flags.dart';
import 'table.dart';

/// column types of the schema builder.
/// each grammar maps a type to the sql type of its database.
enum ColumnType {
  bigIncrements,
  increments,
  char,
  string,
  text,
  mediumText,
  longText,
  integer,
  bigInteger,
  smallInteger,
  tinyInteger,
  float,
  double,
  decimal,
  boolean,
  date,
  dateTime,
  dateTimeTz,
  time,
  timestamp,
  timestampTz,
  json,
  jsonb,
  uuid,
  binary,
  enumeration,
  year,
}

const Set<ColumnType> _textTypes = <ColumnType>{
  ColumnType.char,
  ColumnType.string,
  ColumnType.text,
  ColumnType.mediumText,
  ColumnType.longText,
  ColumnType.enumeration,
};

/// one column of a table, made by the methods of [Table].
/// the modifiers return the column, so they can be chained:
/// `table.string('email').nullable().unique()`.
class ColumnDefinition {
  final String name;
  final ColumnType type;

  /// length of `char` and `string`
  final int? length;

  /// total digits and digits after the point of `decimal`
  final int? precision;
  final int? scale;

  /// allowed values of `enumeration`
  final List<String> allowed;

  bool isNullable = false;
  bool isUnsigned = false;
  bool isUnique = false;
  bool isIndex = false;
  bool isPrimary = false;
  bool isChange = false;
  bool autoIncrement = false;
  bool currentOnUpdate = false;

  /// true when [defaultTo] was called, so `defaultTo(null)` works
  bool hasDefault = false;
  Object? defaultValue;
  String? rawDefault;
  String? commentText;
  String? afterColumn;
  String? _collation;

  /// `JSON`, not `JSONB`, on postgres. `Table.json` sets it with
  /// [OrmFlags.laravelPostgresTypes].
  bool plainJson = false;

  ColumnDefinition(
    this.name,
    this.type, {
    this.length,
    this.precision,
    this.scale,
    this.allowed = const <String>[],
  });

  /// allow NULL. `nullable(false)` makes it NOT NULL again.
  ColumnDefinition nullable([bool value = true]) {
    isNullable = value;
    return this;
  }

  /// default value. it is escaped, so any string is safe.
  ColumnDefinition defaultTo(Object? value) {
    hasDefault = true;
    defaultValue = value;
    return this;
  }

  /// same as [defaultTo], kept for older code
  ColumnDefinition withDefault(Object? value) => defaultTo(value);

  /// default as a raw sql expression, it is NOT escaped.
  /// eg. `defaultRaw('CURRENT_TIMESTAMP')`
  ColumnDefinition defaultRaw(String sql) {
    rawDefault = sql;
    return this;
  }

  /// default to the current time
  ColumnDefinition useCurrent() => defaultRaw('CURRENT_TIMESTAMP');

  /// mysql only: set the current time on each update.
  /// postgres and sqlite ignore it.
  ColumnDefinition useCurrentOnUpdate() {
    currentOnUpdate = true;
    return this;
  }

  /// add a unique index on this column
  ColumnDefinition unique() {
    isUnique = true;
    return this;
  }

  /// add an index on this column
  ColumnDefinition index() {
    isIndex = true;
    return this;
  }

  /// make this column the primary key
  ColumnDefinition primary() {
    isPrimary = true;
    return this;
  }

  /// mysql only: UNSIGNED. postgres and sqlite ignore it.
  ColumnDefinition unsigned() {
    isUnsigned = true;
    return this;
  }

  /// the collation set by [collation], or null
  String? get collationName => _collation;

  /// mysql and mariadb only: `COLLATE <name>`, eg. `utf8mb4_bin` makes
  /// `A` and `a` two different keys. postgres and sqlite ignore it: their
  /// collation names are different, and their text compare is already case
  /// sensitive. [name] may have only letters, digits and `_`, or it throws
  /// an `ArgumentError`. Text columns only (`string`, `char`, the text
  /// types and `enumeration`): any other column throws an `ArgumentError`,
  /// because MySQL does not accept a collation on it.
  ///
  /// On MySQL, `.change()` is `MODIFY COLUMN`. Give `.collation(...)` again
  /// in the change, or the column goes back to the collation of the table.
  ColumnDefinition collation(String name) {
    if (!_textTypes.contains(type)) {
      throw ArgumentError(
        'collation() is for text columns only, column "${this.name}" is ${type.name}',
      );
    }
    if (!RegExp(r'^[A-Za-z0-9_]+$').hasMatch(name)) {
      throw ArgumentError.value(
        name,
        'name',
        'A collation name has only letters, digits and _',
      );
    }
    _collation = name;
    return this;
  }

  /// column comment. postgres and mysql only, sqlite ignores it.
  ColumnDefinition comment(String text) {
    commentText = text;
    return this;
  }

  /// mysql only: place the new column after [column]. others ignore it.
  ColumnDefinition after(String column) {
    afterColumn = column;
    return this;
  }

  /// in `Schema.table`: change this existing column instead of adding it.
  /// give all modifiers you want to keep (nullable, default, ...).
  ColumnDefinition change() {
    isChange = true;
    return this;
  }
}

/// column made by `foreignId` and `foreignUuid`, it can add its foreign key
class ForeignIdColumnDefinition extends ColumnDefinition {
  final Table _table;

  /// the table and key of the model of `foreignIdFor()`
  String? modelTable;
  String? modelKey;

  ForeignIdColumnDefinition(
    this._table,
    super.name,
    super.type, {
    super.length,
  });

  /// every modifier returns this type, so `.nullable().constrained()`
  /// and `.unique().constrained()` work
  @override
  ForeignIdColumnDefinition nullable([bool value = true]) {
    super.nullable(value);
    return this;
  }

  @override
  ForeignIdColumnDefinition index() {
    super.index();
    return this;
  }

  @override
  ForeignIdColumnDefinition comment(String text) {
    super.comment(text);
    return this;
  }

  @override
  ForeignIdColumnDefinition after(String column) {
    super.after(column);
    return this;
  }

  @override
  ForeignIdColumnDefinition defaultTo(Object? value) {
    super.defaultTo(value);
    return this;
  }

  @override
  ForeignIdColumnDefinition withDefault(Object? value) => defaultTo(value);

  @override
  ForeignIdColumnDefinition defaultRaw(String sql) {
    super.defaultRaw(sql);
    return this;
  }

  @override
  ForeignIdColumnDefinition useCurrent() => defaultRaw('CURRENT_TIMESTAMP');

  @override
  ForeignIdColumnDefinition useCurrentOnUpdate() {
    super.useCurrentOnUpdate();
    return this;
  }

  @override
  ForeignIdColumnDefinition unique() {
    super.unique();
    return this;
  }

  @override
  ForeignIdColumnDefinition primary() {
    super.primary();
    return this;
  }

  @override
  ForeignIdColumnDefinition unsigned() {
    super.unsigned();
    return this;
  }

  @override
  ForeignIdColumnDefinition change() {
    super.change();
    return this;
  }

  /// add a foreign key to [table] ([column], default `id`).
  /// without [table] the name is guessed: `user_id` => `users`.
  /// After `foreignIdFor()` it is the model table and key.
  ForeignKeyDefinition constrained([String? table, String? column]) {
    return references(column ?? modelKey ?? 'id')
        .on(table ?? modelTable ?? guessTable(name));
  }

  /// add a foreign key to [column], set the table with `on()`
  ForeignKeyDefinition references(String column) {
    return _table.foreign(name).references(column);
  }

  /// `user_id` => `users`, `category_id` => `categories`
  static String guessTable(String column) {
    String base = column.endsWith('_id')
        ? column.substring(0, column.length - 3)
        : column;
    if (RegExp(r'[^aeiou]y$').hasMatch(base)) {
      return '${base.substring(0, base.length - 1)}ies';
    }
    if (RegExp(r'(s|x|z|ch|sh)$').hasMatch(base)) {
      return '${base}es';
    }
    return '${base}s';
  }
}

/// a foreign key, made by `table.foreign(...)` or `foreignId(...).constrained()`
class ForeignKeyDefinition {
  final List<String> columns;
  final String name;
  String? onTable;
  List<String> referenceColumns = <String>['id'];
  String? deleteAction;
  String? updateAction;

  ForeignKeyDefinition(this.columns, this.name);

  /// referenced column or columns (String or `List<String>`)
  ForeignKeyDefinition references(Object columns) {
    referenceColumns = columnList(columns);
    return this;
  }

  /// referenced table
  ForeignKeyDefinition on(String table) {
    onTable = table;
    return this;
  }

  /// eg. `cascade`, `set null`, `restrict`, `no action`
  ForeignKeyDefinition onDelete(String action) {
    deleteAction = action;
    return this;
  }

  ForeignKeyDefinition onUpdate(String action) {
    updateAction = action;
    return this;
  }

  ForeignKeyDefinition cascadeOnDelete() => onDelete('cascade');
  ForeignKeyDefinition nullOnDelete() => onDelete('set null');
  ForeignKeyDefinition restrictOnDelete() => onDelete('restrict');
  ForeignKeyDefinition cascadeOnUpdate() => onUpdate('cascade');
  ForeignKeyDefinition nullOnUpdate() => onUpdate('set null');
  ForeignKeyDefinition restrictOnUpdate() => onUpdate('restrict');
}

/// String or `List<String>` to `List<String>`
List<String> columnList(Object columns) {
  if (columns is String) {
    return <String>[columns];
  }
  return (columns as List<Object?>).cast<String>();
}
