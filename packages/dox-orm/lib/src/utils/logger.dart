import 'package:dox_orm/dox_orm.dart';
import 'package:dox_orm/src/drivers/db_driver.dart';

class Logger {
  /// print [query] with each `@name` as `?`, and its values in the order
  /// of the `?`. values that the query does not use come last.
  void log(String query, [dynamic params]) {
    Map<String, dynamic> values =
        params as Map<String, dynamic>? ?? const <String, dynamic>{};
    List<String> redact = SqlQueryBuilder().logRedact;
    List<String> list = <String>[];
    Set<String> used = <String>{};
    StringBuffer out = StringBuffer();
    int copied = 0;
    for (SqlParam p in findSqlParams(query)) {
      out
        ..write(query.substring(copied, p.start))
        ..write('?');
      copied = p.end;
      if (values.containsKey(p.name)) {
        used.add(p.name);
        list.add(_show(p.name, values[p.name], redact));
      }
    }
    out.write(query.substring(copied));
    for (MapEntry<String, dynamic> e in values.entries) {
      if (!used.contains(e.key)) list.add(_show(e.key, e.value, redact));
    }
    SqlQueryBuilder().printer.log(out.toString(), list);
  }

  static String _show(String key, dynamic value, List<String> redact) =>
      _hidden(key, redact) ? '***' : value.toString();

  /// true when [key] (eg. `old_password_p3`) ends with a name in [redact]
  static bool _hidden(String key, List<String> redact) {
    if (redact.isEmpty) return false;
    String name = key.replaceFirst(_paramIndex, '').toLowerCase();
    for (String r in redact) {
      String word = r.replaceAll(_notWord, '').toLowerCase();
      if (word.isNotEmpty && name.endsWith(word)) return true;
    }
    return false;
  }

  /// the `_p12` that the query builder adds to each key
  static final RegExp _paramIndex = RegExp(r'_p\d+$');
  static final RegExp _notWord = RegExp(r'[^\w]');

  /// log the text using info color (lightblue)
  /// ```
  /// Logger.info('using dox is fun');
  /// ```
  static void info(dynamic text) {
    print('\x1B[36m$text\x1B[0m');
  }

  /// log the text using warn color (yellow)
  /// ```
  /// Logger.warn('careful!');
  ///
  static void warn(dynamic text) {
    print('\x1B[33m$text\x1B[0m');
  }

  /// log the text using success color (green)
  /// ```
  /// Logger.success('success');
  ///
  static void success(dynamic text) {
    print('\x1B[32m$text\x1B[0m');
  }

  /// log the text using danger color (red)
  /// ```
  /// Logger.danger('failed');
  ///
  static void danger(dynamic text) {
    print('\x1B[31m$text\x1B[0m');
  }
}
