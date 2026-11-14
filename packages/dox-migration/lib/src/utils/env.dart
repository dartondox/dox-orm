import 'dart:io';

/// The env for migrations: the `.env` file and the real environment.
///
/// Same rule as `Env.get()` of dox_core: a real environment variable wins
/// over the `.env` file. An empty value, or the text `null`, counts as
/// missing. [environment] and [dir] are for tests.
Map<String, String> loadEnv({Map<String, String>? environment, String? dir}) {
  environment ??= Platform.environment;
  Map<String, String> data = <String, String>{};

  File envFile = File('${dir ?? Directory.current.path}/.env');
  if (envFile.existsSync()) data.addAll(parseEnv(envFile.readAsStringSync()));
  data.addAll(environment);
  data.removeWhere(_missing);
  return data;
}

bool _missing(String key, String value) {
  String text = value.trim();
  return text.isEmpty || text.toLowerCase() == 'null';
}

/// Reads the text of a `.env` file, the same way as `Env.parse()` of
/// dox_core for a plain file (no `${VAR}` expansion).
/// - `KEY=value`, one per line. Blank lines and lines that start with
///   `#` are skipped. `export KEY=value` is read like `KEY=value`.
/// - `KEY=value # note`: a `#` after a space or tab starts a comment.
///   `KEY=#fff` and `KEY=abc#def` keep the `#`.
/// - `KEY="a # b"`: one pair of quotes (`"`, `'` or `` ` ``) around the
///   value is removed. The text inside stays as it is, also a `#` or a
///   quote. A later key with the same name wins.
Map<String, String> parseEnv(String contents) {
  Map<String, String> data = <String, String>{};
  // trim() also drops a `\r` and a BOM
  for (String line in contents.split('\n')) {
    String text = line.trim().replaceFirst(_export, '');
    if (text.isEmpty || text.startsWith('#')) continue;
    int equal = text.indexOf('=');
    if (equal < 1) continue;
    data[text.substring(0, equal).trim()] = _value(text.substring(equal + 1));
  }
  return data;
}

final RegExp _export = RegExp(r'^export\s+');

/// a `#` after a space or tab
final RegExp _comment = RegExp(r'\s#');

String _value(String raw) {
  String value = raw.trim();
  if (value.isNotEmpty && '"\'`'.contains(value[0])) {
    int end = value.indexOf(value[0], 1);
    if (end > 0) return value.substring(1, end);
  }
  Match? comment = _comment.firstMatch(raw);
  if (comment != null) value = raw.substring(0, comment.start);
  return value.trim();
}
