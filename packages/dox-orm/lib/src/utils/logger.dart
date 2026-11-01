import 'package:dox_orm/dox_orm.dart';

// coverage:ignore-file
class Logger {
  void log(String query, [dynamic params]) {
    query = query.replaceAll(RegExp(r'@\w+'), '?');
    params = _parseParams(params);
    QueryPrinter printer = SqlQueryBuilder().printer;
    printer.log(query, params);
  }

  List<String> _parseParams(dynamic params) {
    List<String> list = <String>[];
    if (params != null && (params as Map<String, dynamic>).isNotEmpty) {
      List<String> redact = SqlQueryBuilder().logRedact;
      params.forEach((String key, dynamic value) {
        list.add(_hidden(key, redact) ? '***' : value.toString());
      });
    }
    return list;
  }

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
    print('\x1B[34m$text\x1B[0m');
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
