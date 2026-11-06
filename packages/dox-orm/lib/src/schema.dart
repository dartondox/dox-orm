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

  /// [driver] default is the query builder driver (`SqlQueryBuilder`)
  factory Schema([DBDriver? driver]) {
    return Schema._(driver ?? SqlQueryBuilder().dbDriver);
  }

  Schema._(this.driver) : grammar = SchemaGrammar.of(driver.getName());

  /// create a table
  Future<void> create(String table, void Function(Table table) callback) {
    Table blueprint = Table(table, creating: true);
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
    List<Map<String, dynamic>> rows = await driver.query(
      grammar.compileTableExists(),
      substitutionValues: <String, dynamic>{'table': table},
    );
    return rows.isNotEmpty;
  }

  Future<bool> hasColumn(String table, String column) async {
    return (await getColumnListing(table)).contains(column);
  }

  Future<List<String>> getColumnListing(String table) async {
    List<Map<String, dynamic>> rows = await driver.query(
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
    List<Map<String, dynamic>> rows = await driver.query(
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
      await driver.execute('DROP INDEX ${grammar.wrap(from)}');
      await driver.execute(created);
    });
  }

  /// the name in `CREATE [UNIQUE] INDEX [IF NOT EXISTS] name`
  static final RegExp _indexName = RegExp(
    r'^(CREATE\s+(?:UNIQUE\s+)?INDEX\s+(?:IF\s+NOT\s+EXISTS\s+)?)("(?:[^"]|"")*"|`[^`]*`|\[[^\]]*\]|\S+)',
    caseSensitive: false,
  );

  Future<void> _run(List<String> statements) async {
    for (String sql in statements) {
      await driver.execute(sql);
    }
  }
}
