import 'package:dox_orm/dox_orm.dart';

/// prints each query on one line, with the values put into the SQL:
/// ```
/// ▌ [db:default] SELECT * FROM "users" WHERE "id" = 7;
/// ```
/// Only the `▌ [db:...]` tag has color, so a copy of the SQL is clean.
class PrettyQueryPrinter implements QueryPrinter {
  @Deprecated('not used any more')
  int logLength = 80;

  /// a query with `?` and its values. The ORM calls [logSql] instead.
  @override
  void log(String query, List<String> params) {
    String line = '${_tag('db')} ${_end(query)}';
    print(params.isEmpty ? line : '$line -- $params');
  }

  /// [sql] with the values already in it. [slowMs] is set for a slow query.
  void logSql(String sql, {required String connection, int? slowMs}) {
    String name = slowMs == null
        ? 'db:$connection'
        : 'db:$connection SLOW ${slowMs}ms';
    print('${_tag(name)} ${_end(sql)}');
  }

  /// dim cyan
  String _tag(String name) => '\x1B[2;36m▌ [$name]\x1B[0m';

  String _end(String sql) {
    String s = sql.trimRight();
    return s.endsWith(';') ? s : '$s;';
  }
}
