import 'dart:convert';

import '/dox_orm.dart';
import 'schema/sqlite_rebuilder.dart';

export 'schema/grammars/mysql_grammar.dart';
export 'schema/grammars/postgres_grammar.dart';
export 'schema/grammars/schema_grammar.dart';
export 'schema/grammars/sqlite_grammar.dart';
export 'schema/table.column.dart';

/// create, change and drop tables, the same way on postgres, mysql,
/// mariadb and sqlite.
///
/// ```
/// Schema schema = Schema(); // uses the query builder connection
/// await schema.create('posts', (Table table) {
///   table.id();
///   table.foreignId('user_id').constrained().cascadeOnDelete();
///   table.string('title');
///   table.enumeration('status', <String>['draft', 'published'])
///       .defaultTo('draft');
///   table.timestamps();
/// });
/// await schema.table('posts', (Table table) {
///   table.text('body').nullable();
///   table.string('title', 500).change();
/// });
/// await schema.dropIfExists('posts');
/// ```
class Schema {
  final DBDriver driver;
  final SchemaGrammar grammar;

  /// the opt-in ORM behaviors for new tables, see
  /// [OrmFlags.laravelPostgresTypes]
  final OrmFlags flags;

  /// [driver] default is the query builder driver (`SqlQueryBuilder`).
  /// [flags] default is the query builder flags (`SqlQueryBuilder().flags`).
  factory Schema([DBDriver? driver, OrmFlags? flags]) {
    return Schema._(
      driver ?? SqlQueryBuilder().dbDriver,
      flags ?? SqlQueryBuilder().flags,
    );
  }

  Schema._(this.driver, this.flags)
    : grammar = SchemaGrammar.of(driver.getName());

  /// run [sql] on [driver], so the query listeners see it
  Future<List<Map<String, dynamic>>> _query(
    String sql, {
    Map<String, dynamic>? substitutionValues,
  }) => SqlQueryBuilder().queryOn(
    driver,
    sql,
    substitutionValues: substitutionValues,
  );

  Future<void> _execute(String sql) => SqlQueryBuilder().executeOn(driver, sql);

  /// create a table
  Future<void> create(String table, void Function(Table table) callback) {
    Table blueprint = Table(table, creating: true, flags: flags);
    callback(blueprint);
    return build(blueprint);
  }

  /// change a table: add columns, `change()` columns, indexes, keys
  Future<void> table(String table, void Function(Table table) callback) {
    Table blueprint = Table(table);
    callback(blueprint);
    return build(blueprint);
  }

  Future<void> drop(String table) => build(Table(table)..drop());

  Future<void> dropIfExists(String table) {
    return build(Table(table)..dropIfExists());
  }

  Future<void> rename(String from, String to) {
    return build(Table(from)..rename(to));
  }

  Future<bool> hasTable(String table) async {
    List<Map<String, dynamic>> rows = await _query(
      grammar.compileTableExists(),
      substitutionValues: <String, dynamic>{'table': table},
    );
    return rows.isNotEmpty;
  }

  Future<bool> hasColumn(String table, String column) async {
    return (await getColumnListing(table)).contains(column);
  }

  /// true when [table] has every one of [columns]
  Future<bool> hasColumns(String table, List<String> columns) async {
    return (await getColumnListing(table)).toSet().containsAll(columns);
  }

  /// true when [table] has the index [index]: an index name (a `String`),
  /// or a `List<String>` of its columns, in the order of the index. the
  /// primary key is named `primary` on mysql and sqlite.
  ///
  /// ```
  /// await schema.hasIndex('users', 'users_email_unique');
  /// await schema.hasIndex('users', <String>['first_name', 'last_name']);
  /// ```
  Future<bool> hasIndex(String table, Object index) async {
    if (index is! String && index is! List) {
      throw ArgumentError.value(index, 'index', 'must be a name or a list');
    }
    Map<String, List<String?>> indexes = <String, List<String?>>{};
    for (Map<String, dynamic> row in await _query(
      grammar.compileIndexListing(),
      substitutionValues: <String, dynamic>{'table': table},
    )) {
      (indexes[row['name'].toString()] ??= <String?>[]).add(
        row['col']?.toString(),
      );
    }
    if (index is String) return indexes.containsKey(index);
    String key = jsonEncode(index);
    return indexes.values.any((List<String?> c) => jsonEncode(c) == key);
  }

  /// turn the foreign key checks off, until [enableForeignKeyConstraints].
  /// [withoutForeignKeyConstraints] is the safe way to use it.
  ///
  /// - sqlite: `PRAGMA foreign_keys = OFF`. it is for the one connection
  ///   of this isolate, so other code of this isolate is not checked
  ///   either while it is off. inside a transaction it does nothing.
  /// - mysql and mariadb: `SET FOREIGN_KEY_CHECKS = 0`. it is a setting
  ///   of one pool connection, so it must run inside a transaction (a
  ///   migration runs in one), else a [StateError] is thrown. turn it on
  ///   again before the transaction ends: the connection goes back to the
  ///   pool with the setting.
  /// - postgres: `SET CONSTRAINTS ALL DEFERRED`, like Laravel. only keys
  ///   made `DEFERRABLE` (with raw sql) wait, and only until the commit.
  ///   it must run inside a transaction, else a [StateError] is thrown.
  Future<void> disableForeignKeyConstraints() async {
    await _foreignKeys(grammar.compileDisableForeignKeyConstraints());
  }

  /// turn the foreign key checks on again, see
  /// [disableForeignKeyConstraints]
  Future<void> enableForeignKeyConstraints() async {
    await _foreignKeys(grammar.compileEnableForeignKeyConstraints());
  }

  Future<void> _foreignKeys(String sql) async {
    if (grammar is! SqliteGrammar && !driver.hasOpenTransaction) {
      throw StateError(
        'the foreign key setting is for one connection: run it inside a '
        'transaction, or use withoutForeignKeyConstraints()',
      );
    }
    await _execute(sql);
  }

  /// run [callback] with the foreign key checks off, and turn them on
  /// again after it, also when it throws. see
  /// [disableForeignKeyConstraints] for each database.
  ///
  /// - mysql, mariadb and postgres: it runs in a transaction (a savepoint
  ///   inside a transaction), so every query uses the same connection.
  /// - sqlite: it must run outside a transaction. inside one the checks
  ///   stay on.
  ///
  /// ```
  /// await schema.withoutForeignKeyConstraints(() async {
  ///   await QueryBuilder.table('users').truncate();
  /// });
  /// ```
  Future<R> withoutForeignKeyConstraints<R>(
    Future<R> Function() callback,
  ) async {
    Future<R> run() async {
      await disableForeignKeyConstraints();
      R result;
      try {
        result = await callback();
      } catch (_) {
        try {
          await enableForeignKeyConstraints();
        } catch (_) {
          // keep the first error: it tells what went wrong
        }
        rethrow;
      }
      await enableForeignKeyConstraints();
      return result;
    }

    if (grammar is SqliteGrammar) return run();
    return driver.transaction(run);
  }

  Future<List<String>> getColumnListing(String table) async {
    List<Map<String, dynamic>> rows = await _query(
      grammar.compileColumnListing(),
      substitutionValues: <String, dynamic>{'table': table},
    );
    return <String>[
      for (Map<String, dynamic> row in rows) row.values.first.toString(),
    ];
  }

  /// run the sql of [table], one statement at a time
  Future<void> build(Table table) async {
    if (grammar is! SqliteGrammar) return await _run(grammar.compile(table));

    /// sqlite has no rename of an index, it is made again at the end
    List<TableCommand> renames = _take(
      table,
      (TableCommand c) => c.type == CommandType.renameIndex,
    );
    if (table.needsSqliteRebuild) {
      /// sqlite can not drop a column that a foreign key uses, so drop
      /// it after the rebuild dropped the key (dropConstrainedForeignId)
      Set<String> droppedKeys = <String>{
        for (TableCommand c in table.commands)
          if (c.type == CommandType.dropForeign) c.name!,
      };
      List<TableCommand> drops = _take(
        table,
        (TableCommand c) =>
            c.type == CommandType.dropColumn &&
            droppedKeys.contains(table.indexName('foreign', c.columns)),
      );
      await _run(grammar.compile(table.withoutSqliteRebuild()));
      await SqliteTableRebuilder(
        driver,
        grammar as SqliteGrammar,
      ).rebuild(table);
      await _run(grammar.compile(Table(table.name)..commands.addAll(drops)));
    } else {
      await _run(grammar.compile(table));
    }
    for (TableCommand c in renames) {
      await _renameSqliteIndex(c.name!, c.to!);
    }
  }

  /// removes the commands of [table] that pass [test] and returns them
  static List<TableCommand> _take(
    Table table,
    bool Function(TableCommand c) test,
  ) {
    List<TableCommand> taken = table.commands.where(test).toList();
    table.commands.removeWhere(test);
    return taken;
  }

  /// sqlite: make the index [from] again with the name [to], from its
  /// saved sql
  Future<void> _renameSqliteIndex(String from, String to) async {
    List<Map<String, dynamic>> rows = await _query(
      "SELECT sql FROM sqlite_schema WHERE type = 'index' AND name = @name",
      substitutionValues: <String, dynamic>{'name': from},
    );
    Object? sql = rows.isEmpty ? null : rows.first['sql'];
    if (sql == null) {
      throw StateError('sqlite: index $from not found, or it has no sql');
    }
    String created = '$sql'.replaceFirstMapped(_indexName, (Match m) {
      return '${m[1]}${grammar.wrap(to)}';
    });
    await driver.transaction(() async {
      await _execute('DROP INDEX ${grammar.wrap(from)}');
      await _execute(created);
    });
  }

  /// the name in `CREATE [UNIQUE] INDEX [IF NOT EXISTS] name`
  static final RegExp _indexName = RegExp(
    r'^(CREATE\s+(?:UNIQUE\s+)?INDEX\s+(?:IF\s+NOT\s+EXISTS\s+)?)("(?:[^"]|"")*"|`[^`]*`|\[[^\]]*\]|\S+)',
    caseSensitive: false,
  );

  Future<void> _run(List<String> statements) async {
    for (String sql in statements) {
      await _execute(sql);
    }
  }
}
