import 'package:dox_orm/dox_orm.dart';
import 'package:dox_orm/src/drivers/db_driver.dart'
    show SqlParam, findSqlParams;

/// prints each query on one line, with the values put into the SQL:
/// ```
/// [db:default] SELECT * FROM "users" WHERE "id" = 7;
/// ```
/// The tag is dim and the SQL is cyan (yellow for a slow query).
class PrettyQueryPrinter implements QueryPrinter {
  /// a query with `?` and its values. The ORM calls [logSql] instead.
  @override
  void log(String query, List<String> params) {
    String line = _line('db', _end(query), 36);
    print(params.isEmpty ? line : '$line -- $params');
  }

  /// [sql] with the values already in it. [slowMs] is set for a slow query.
  /// [mysql] reads `#` as a comment, like MySQL.
  void logSql(
    String sql, {
    required String connection,
    int? slowMs,
    bool mysql = false,
  }) {
    String name = slowMs == null
        ? 'db:$connection'
        : 'db:$connection SLOW ${slowMs}ms';
    print(_line(name, _end(sql, mysql: mysql), slowMs == null ? 36 : 33));
  }

  /// dim `[tag]`, then the text in [color]
  String _line(String tag, String text, int color) =>
      '\x1B[2m[$tag]\x1B[0m \x1B[${color}m$text\x1B[0m';

  /// add `;` at the end. When the SQL ends inside a comment (`--`, or
  /// `#` for [mysql]), the `;` goes on a new line.
  String _end(String sql, {bool mysql = false}) {
    String s = sql.trimRight();
    if (s.endsWith(';')) return s;
    // ponytail: a marker at the end is found only when it is not inside
    // a comment or a string, so the quote and comment rules stay in one place
    List<SqlParam> found = findSqlParams('$s@dox_end', mysql: mysql);
    bool open = found.isEmpty || found.last.start != s.length;
    return open ? '$s\n;' : '$s;';
  }
}
