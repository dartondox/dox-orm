import 'package:dox_postgres_native/dox_postgres_native.dart'
    show PgServerException;
import 'package:dox_validation/dox_validation.dart';

import '../drivers/db_driver.dart';
import '../main.dart';
import '../query_builder.dart';

/// Reads rows for [Unique] and [Exists], and for `v.string().exists()`
/// and `.unique()` of the fluent schemas: the ORM sets it as the
/// [PresenceVerifier] when the database starts. Soft-deleted rows count
/// too, because it reads the table, not the model.
///
/// The values are bound as query parameters. Table and column names are
/// quoted by the driver, which refuses unsafe names.
class RowFinder extends PresenceVerifier {
  const RowFinder();

  /// The values of [values] that are in [column] of [table], as text.
  /// When [exceptColumn] is set, rows where it equals [exceptValue] are
  /// left out. One `WHERE IN` query.
  @override
  Future<Set<String>> found(
    String table,
    String column,
    List<Object?> values, {
    String? exceptColumn,
    Object? exceptValue,
    String? connection,
  }) async {
    QueryBuilder<dynamic> query = QueryBuilder.table(table)
        .select(column)
        .whereIn(column, values);
    if (exceptColumn != null) {
      query = query.where(exceptColumn, '!=', exceptValue);
    }
    if (connection != null) query = query.withConnection(connection);
    List<dynamic> rows;
    try {
      rows = await _get(query, connection);
    } on PgServerException catch (error) {
      // A value that does not fit the column can not be in the column.
      // Postgres says so with a "data exception" (SQLSTATE class 22):
      // `abc` or `1.0` for a bigint (22P02), a number that is too big
      // (22003), text with a NUL byte (22021), a bad date (22007, 22008).
      // In this query they almost always come from the bound values.
      // (A view that divides by zero gives one too: it is then "not
      // found", which is rare.) Other errors, like a lost connection,
      // still throw. MySQL and SQLite give no error for these, only no
      // rows.
      if (!_notFit(error)) rethrow;
      // The ignore value can be the bad one (it comes from the URL). Then
      // no row has it, so there is nothing to skip: drop it and ask again.
      if (exceptColumn != null &&
          !await _fits(table, exceptColumn, exceptValue, connection)) {
        return this.found(table, column, values, connection: connection);
      }
      if (values.length == 1) return <String>{};
      // one bad value fails the whole query, so it is not known which
      // items are in the table. The list rules then fail every item.
      throw PresenceUnknown('${error.code}: ${error.message}');
    }
    Set<String> found = <String>{};
    for (dynamic row in rows) {
      // a row has the key `name` for the column `t.name`
      if (row is Map) {
        found.add('${row[column.substring(column.lastIndexOf('.') + 1)]}');
      }
    }
    return found;
  }

  static bool _notFit(PgServerException error) {
    return error.code.startsWith('22');
  }

  /// Run [query]. On Postgres inside a transaction it runs in a savepoint
  /// (a nested transaction). There a failed query aborts the whole
  /// transaction, so without it the next query of the app would fail
  /// with 25P02. With it, only this one query is rolled back. MySQL and
  /// SQLite give no error here, so they skip the 2 extra statements.
  static Future<List<dynamic>> _get(
    QueryBuilder<dynamic> query,
    String? connection,
  ) {
    if (!DBDriver.inTransaction ||
        SqlQueryBuilder().getDBDriver(connection).getName() !=
            Driver.postgres) {
      return query.get();
    }
    return QueryBuilder.transaction(query.get, connection: connection);
  }

  /// `false` when [value] does not fit [column] of [table] (Postgres).
  Future<bool> _fits(
    String table,
    String column,
    Object? value,
    String? connection,
  ) async {
    QueryBuilder<dynamic> query = QueryBuilder.table(table)
        .select(column)
        .where(column, value)
        .limit(1);
    if (connection != null) query = query.withConnection(connection);
    try {
      await _get(query, connection);
      return true;
    } on PgServerException catch (error) {
      if (_notFit(error)) return false;
      rethrow;
    }
  }
}

/// No row in [table] has this value.
///
/// ```dart
/// @Unique('users', column: 'email')
/// final String email;
///
/// // PUT /users/{id}: skip the row being updated
/// @Unique('users', column: 'email', ignoreParam: 'id')
/// final String email;
/// ```
/// [column] defaults to the input key. On a `List` field the whole list
/// is one query.
class Unique extends AsyncRule<Object?> {
  const Unique(
    this.table, {
    this.column,
    this.ignoreParam,
    this.ignoreColumn = 'id',
    this.connection,
    this.finder = const RowFinder(),
    super.message,
  });

  final String table;
  final String? column;

  /// A path param name. The row where [ignoreColumn] equals it is skipped.
  final String? ignoreParam;
  final String ignoreColumn;

  /// A `dox_orm` connection name. Default: the default connection.
  final String? connection;
  final RowFinder finder;

  @override
  String get name => 'unique';

  @override
  String get defaultMessage => 'The {field} has already been taken';

  /// One value: the database decides what matches. MySQL ignores case,
  /// so any row found means the value is taken.
  @override
  Future<bool> checkAsync(Object? value, RuleContext context) async {
    return (await _found(<Object?>[value], context)).isEmpty;
  }

  /// Many values: one query for the whole list. See
  /// [PresenceVerifier.takenItems].
  @override
  Future<List<int>> failedItems(List<Object?> values, RuleContext context) {
    return PresenceVerifier.takenItems(
      values,
      (List<Object?> items) => _found(items, context),
    );
  }

  Future<Set<String>> _found(List<Object?> values, RuleContext context) {
    String? param = ignoreParam;
    String? skip = param == null ? null : context.state.params[param];
    return finder.found(
      table,
      column ?? context.field,
      values,
      exceptColumn: skip == null ? null : ignoreColumn,
      exceptValue: skip == null ? null : (int.tryParse(skip) ?? skip),
      connection: connection,
    );
  }
}

/// A row in [table] has this value: `@Exists('teams')`.
/// [column] defaults to `id`.
/// On a `List` field the whole list is one query.
class Exists extends AsyncRule<Object?> {
  const Exists(
    this.table, {
    this.column = 'id',
    this.connection,
    this.finder = const RowFinder(),
    super.message,
  });

  final String table;
  final String column;

  /// A `dox_orm` connection name. Default: the default connection.
  final String? connection;
  final RowFinder finder;

  @override
  String get name => 'exists';

  @override
  String get defaultMessage => 'The selected {field} is invalid';

  /// One value: it passes only when the database finds its exact text,
  /// the same as in 3.0.1. So `'01'` does not find the id `1`, and on
  /// MySQL `'1abc'` or `team-a` for `TEAM-A` do not pass either.
  @override
  Future<bool> checkAsync(Object? value, RuleContext context) async {
    return (await _found(<Object?>[value])).contains('$value');
  }

  Future<Set<String>> _found(List<Object?> values) {
    return finder.found(table, column, values, connection: connection);
  }

  /// Many values: one query for the whole list. See
  /// [PresenceVerifier.missingItems].
  @override
  Future<List<int>> failedItems(List<Object?> values, RuleContext context) {
    return PresenceVerifier.missingItems(values, _found);
  }
}
