import 'dart:typed_data';

import 'package:dox_orm/dox_orm.dart';
import 'package:dox_orm/src/drivers/db_driver.dart';

class Logger {
  /// print [query] with each `@name` as `?`, and its values in the order
  /// of the `?`. values that the query does not use come last. values
  /// named in `logRedact` of the default connection or of the named
  /// [connection] show as `***`. [prefix] goes before the query text,
  /// eg. the time of a slow query.
  ///
  /// a [PrettyQueryPrinter] gets one line with the values put into the
  /// SQL instead, with [slowMs] (the time of a slow query) in its tag.
  void log(
    String query, [
    dynamic params,
    String? connection,
    String prefix = '',
    int? slowMs,
  ]) {
    Map<String, dynamic> values =
        params as Map<String, dynamic>? ?? const <String, dynamic>{};
    List<String> redact = SqlQueryBuilder().logRedactOf(connection);
    QueryPrinter printer = SqlQueryBuilder().printer;
    // ponytail: exact type only, so a subclass that overrides log() keeps
    // getting the `?` query and the values, as before
    if (printer.runtimeType == PrettyQueryPrinter &&
        _logPretty(
          printer as PrettyQueryPrinter,
          query,
          values,
          connection,
          redact,
          slowMs,
        )) {
      return;
    }
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
    SqlQueryBuilder().printer.log('$prefix$out', list);
  }

  /// print [query] as one line with the values in it. False when this
  /// fails, so the caller logs it the old way: a log must never fail a
  /// query that worked.
  bool _logPretty(
    PrettyQueryPrinter printer,
    String query,
    Map<String, dynamic> values,
    String? connection,
    List<String> redact,
    int? slowMs,
  ) {
    String filled;
    String name;
    try {
      SqlQueryBuilder sql = SqlQueryBuilder();
      filled = fillSql(
        query,
        values,
        sql.getDBDriver(connection).getName(),
        redact,
      );
      name = connection ?? sql.databaseConfig?.connection ?? 'default';
    } catch (_) {
      return false;
    }
    printer.logSql(filled, connection: name, slowMs: slowMs);
    return true;
  }

  /// [query] with each `@name` replaced by its value as a SQL literal of
  /// [driver], like `toRawSql()`. A value named in [redact] shows as
  /// `'***'`. Bytes show as a hex literal. A name with no value stays.
  static String fillSql(
    String query,
    Map<String, dynamic> values,
    Driver driver,
    List<String> redact,
  ) {
    SchemaGrammar grammar = SchemaGrammar.of(driver);
    StringBuffer out = StringBuffer();
    int copied = 0;
    for (SqlParam p in findSqlParams(query, mysql: driver == Driver.mysql)) {
      out.write(query.substring(copied, p.start));
      copied = p.end;
      dynamic value = values[p.name];
      if (!values.containsKey(p.name)) {
        out.write(query.substring(p.start, p.end));
      } else if (_hidden(p.name, redact)) {
        out.write("'***'");
      } else if (value is Uint8List) {
        out.write(_hex(value, driver));
      } else {
        out.write(grammar.literal(value));
      }
    }
    out.write(query.substring(copied));
    return out.toString();
  }

  /// `X'0102'`, or `'\x0102'` on postgres
  static String _hex(Uint8List bytes, Driver driver) {
    StringBuffer hex = StringBuffer();
    for (int b in bytes) {
      hex.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return driver == Driver.postgres ? "'\\x$hex'" : "X'$hex'";
  }

  /// a copy of [values] where each value named in `logRedact` of the
  /// default connection or of [connection] is `***`
  static Map<String, dynamic> redact(
    Map<String, dynamic>? values,
    String? connection,
  ) {
    if (values == null || values.isEmpty) return <String, dynamic>{};
    List<String> redact = SqlQueryBuilder().logRedactOf(connection);
    return <String, dynamic>{
      for (MapEntry<String, dynamic> e in values.entries)
        e.key: _hidden(e.key, redact) ? '***' : e.value,
    };
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
