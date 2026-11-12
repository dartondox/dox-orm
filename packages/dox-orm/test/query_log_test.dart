import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dox_orm/dox_orm.dart';
import 'package:dox_orm/src/utils/logger.dart';
import 'package:test/test.dart';

/// keeps the last logged query and params
class _Capture implements QueryPrinter {
  String query = '';
  List<String> params = <String>[];

  @override
  void log(String query, List<String> params) {
    this.query = query;
    this.params = params;
  }
}

void main() {
  late _Capture capture;
  late QueryPrinter oldPrinter;

  setUp(() {
    oldPrinter = SqlQueryBuilder().printer;
    capture = _Capture();
    SqlQueryBuilder().printer = capture;
  });

  tearDown(() {
    SqlQueryBuilder().printer = oldPrinter;
    SqlQueryBuilder().logRedact = <String>[];
  });

  group('log order', () {
    test('values follow the order of the ?, not of the map', () {
      // where(...).update(...) adds the WHERE value first
      Logger().log(
        'UPDATE "t" SET "name" = @name_p2 WHERE "id" = @id_p1',
        <String, dynamic>{'id_p1': 7, 'name_p2': 'new'},
      );
      expect(capture.query, 'UPDATE "t" SET "name" = ? WHERE "id" = ?');
      expect(capture.params, <String>['new', '7']);
    });

    test('a name used twice shows twice, unused values come last', () {
      Logger().log('x = @a OR y = @a', <String, dynamic>{'b': 2, 'a': 1});
      expect(capture.params, <String>['1', '1', '2']);
    });
  });

  group('log redaction', () {
    test('shows every value by default', () {
      Logger().log(
        'UPDATE users SET password = @password_p1',
        <String, dynamic>{'password_p1': 'hash'},
      );
      expect(capture.params, <String>['hash']);
    });

    test('hides values whose key ends with a listed name', () {
      SqlQueryBuilder().logRedact = <String>['password', 'Token'];
      Logger().log(
        'UPDATE users SET old_password = @old_password_p1, '
        'remember_token = @remember_token_p2, name = @name_p3 '
        'WHERE users.password = @userspassword_p4',
        <String, dynamic>{
          'old_password_p1': 'a',
          'remember_token_p2': 'b',
          'name_p3': 'c',
          'userspassword_p4': 'd',
        },
      );
      expect(capture.params, <String>['***', '***', 'c', '***']);
    });

    test('a named connection uses its own logRedact too', () async {
      SqlQueryBuilder sql = SqlQueryBuilder();
      DatabaseConfig? oldConfig = sql.databaseConfig;
      sql.logRedact = <String>['password'];
      sql.databaseConfig = DatabaseConfig(
        connection: 'main',
        url: '',
        connections: <String, ConnectionConfig>{
          'main': ConnectionConfig(
            driver: Driver.sqlite,
            database: ':memory:',
            debug: false,
          ),
          'other': ConnectionConfig(
            driver: Driver.sqlite,
            database: ':memory:',
            debug: false,
            logRedact: <String>['token'],
          ),
        },
      );
      try {
        String q = 'UPDATE t SET password = @password_p1, token = @token_p2';
        Map<String, dynamic> values = <String, dynamic>{
          'password_p1': 'a',
          'token_p2': 'b',
        };
        Logger().log(q, values);
        expect(capture.params, <String>['***', 'b']);
        Logger().log(q, values, 'other');
        expect(capture.params, <String>['***', '***']);
      } finally {
        sql.databaseConfig = oldConfig;
      }
    });

    test('ConnectionConfig.logRedact is read on initialize', () async {
      ConnectionConfig config = ConnectionConfig(
        driver: Driver.sqlite,
        database: ':memory:',
        debug: false,
        logRedact: <String>['secret'],
      );
      SqlQueryBuilder.initializeWithDatabaseConfig(
        DatabaseConfig(
          connection: 'log',
          connections: <String, ConnectionConfig>{'log': config},
          url: '',
        ),
      );
      expect(SqlQueryBuilder().logRedact, <String>['secret']);
      await SqlQueryBuilder.close();
      expect(
        ConnectionConfig.fromUrl(
          'sqlite::memory:',
          logRedact: <String>['secret'],
        ).logRedact,
        <String>['secret'],
      );
    });
  });

  test('FileQueryPrinter writes each line before log() returns', () async {
    Directory dir = await Directory.systemTemp.createTemp('dox_log');
    File file = File('${dir.path}/sub/query.log');
    FileQueryPrinter printer = FileQueryPrinter(file: file);
    printer.log('q1', <String>['1']);
    printer.log('q2', <String>['2']);
    // no flush: the lines are already in the file
    List<String> lines = file.readAsLinesSync();
    expect(lines.length, 2);
    expect(lines.last, contains('"q2"'));
    await dir.delete(recursive: true);
  });

  test(
    'FileQueryPrinter buffered writes every line, in order, without blocking',
    () async {
      Directory dir = await Directory.systemTemp.createTemp('dox_log');
      File file = File('${dir.path}/sub/query.log');
      FileQueryPrinter printer = FileQueryPrinter(file: file, buffered: true);
      for (int i = 0; i < 500; i++) {
        printer.log('q$i', <String>['$i']);
      }
      // nothing is written yet: the query did not wait for the disk
      expect(file.existsSync(), isFalse);
      await printer.flush();
      printer.log('last', <String>[]);
      await printer.flush();
      List<String> lines = file.readAsLinesSync();
      expect(lines.length, 501);
      expect(lines.first, contains('"q0"'));
      expect(lines[499], contains('"q499"'));
      expect(lines.last, contains('"last"'));
      await dir.delete(recursive: true);
    },
  );

  test('Logger.warn prints yellow', () {
    expect(_prints(() => Logger.warn('careful')), <String>[
      '\x1B[33mcareful\x1B[0m',
    ]);
  });

  test('Logger info, success and danger use their colors', () {
    expect(
      _prints(() {
        Logger.info('a');
        Logger.success('b');
        Logger.danger('c');
      }),
      <String>['\x1B[36ma\x1B[0m', '\x1B[32mb\x1B[0m', '\x1B[31mc\x1B[0m'],
    );
  });

  test('ConsoleQueryPrinter prints one json line', () {
    List<String> lines = _prints(
      () => ConsoleQueryPrinter().log('SELECT ?', <String>['1']),
    );
    expect(lines.length, 1);
    Map<String, dynamic> json = jsonDecode(lines.first) as Map<String, dynamic>;
    expect(json['level'], 'INFO');
    expect(json['message'], 'SELECT ?');
    expect(json['payload'], <String, dynamic>{
      'query': 'SELECT ?',
      'params': <String>['1'],
    });
  });

  test('ConsoleQueryPrinter filter changes the line', () {
    List<String> lines = _prints(
      () =>
          ConsoleQueryPrinter(filter: (String s) => 'x')
              .log('SELECT ?', <String>[]),
    );
    expect(lines, <String>['x']);
  });

  test('FileQueryPrinter filter changes the line', () async {
    Directory dir = await Directory.systemTemp.createTemp('dox_log');
    File file = File('${dir.path}/query.log');
    FileQueryPrinter(
      file: file,
      filter: (String s) => 'x',
    ).log('q', <String>[]);
    expect(file.readAsLinesSync(), <String>['x']);
    await dir.delete(recursive: true);
  });

  test(
    'FileQueryPrinter buffered does not throw when the write fails',
    () async {
      Directory dir = await Directory.systemTemp.createTemp('dox_log');
      File blocker = File('${dir.path}/blocker')..writeAsStringSync('x');
      FileQueryPrinter printer = FileQueryPrinter(
        file: File('${blocker.path}/query.log'),
        buffered: true,
      );
      printer.log('q', <String>[]);
      await printer.flush();
      expect(File('${blocker.path}/query.log').existsSync(), isFalse);
      await dir.delete(recursive: true);
    },
  );

  group('PrettyQueryPrinter', () {
    const String tag = '\x1B[2;36m▌ [db:main]\x1B[0m ';

    setUp(() {
      SqlQueryBuilder.initializeWithDatabaseConfig(
        DatabaseConfig(
          connection: 'main',
          url: '',
          connections: <String, ConnectionConfig>{
            'main': ConnectionConfig(
              driver: Driver.sqlite,
              database: ':memory:',
              debug: false,
              logRedact: <String>['password'],
            ),
            'other': ConnectionConfig(
              driver: Driver.sqlite,
              database: ':memory:',
              debug: false,
              logRedact: <String>['token'],
              slowQueryMs: 0,
            ),
          },
        ),
      );
      SqlQueryBuilder().printer = PrettyQueryPrinter();
    });

    tearDown(() async {
      SqlQueryBuilder().slowQueryMs = null;
      await SqlQueryBuilder.close();
    });

    test('puts each value into the SQL as a literal', () {
      List<String> lines = _prints(
        () => Logger().log(
          'SELECT * FROM "t" WHERE a = @a AND b = @b AND c = @c '
          'AND d = @d AND e = @e AND f = @f AND g = @g AND h = @missing',
          <String, dynamic>{
            'a': "it's",
            'b': null,
            'c': true,
            'd': 42,
            'e': DateTime.utc(2026, 1, 2),
            'f': <String, dynamic>{'k': 1},
            'g': <int>[1, 2],
          },
        ),
      );
      expect(lines, <String>[
        '${tag}SELECT * FROM "t" WHERE a = \'it\'\'s\' AND b = NULL '
            "AND c = TRUE AND d = 42 AND e = '2026-01-02T00:00:00.000Z' "
            "AND f = '{\"k\":1}' AND g = '[1,2]' AND h = @missing;",
      ]);
    });

    test('a redacted value shows as quoted ***', () {
      List<String> lines = _prints(
        () => Logger().log(
          'UPDATE "users" SET "password" = @password_p1 WHERE "id" = @id_p2',
          <String, dynamic>{'password_p1': 'secret', 'id_p2': 7},
        ),
      );
      expect(lines, <String>[
        '${tag}UPDATE "users" SET "password" = \'***\' WHERE "id" = 7;',
      ]);
    });

    test('does not add a second ;', () {
      List<String> lines = _prints(() => Logger().log('SELECT 1;'));
      expect(lines, <String>['${tag}SELECT 1;']);
    });

    test('a slow query shows SLOW and the time in the tag', () async {
      SqlQueryBuilder().slowQueryMs = 0;
      List<String> lines = await _printsAsync(
        () => QueryBuilder.query(
          'SELECT 1 WHERE @id_p1 = @id_p1',
          substitutionValues: <String, dynamic>{'id_p1': 5},
        ),
      );
      expect(lines.length, 1);
      expect(
        lines.first,
        matches(
          RegExp(
            r'^\x1B\[2;36m▌ \[db:main SLOW \d+ms\]\x1B\[0m '
            r'SELECT 1 WHERE 5 = 5;$',
          ),
        ),
      );
    });

    test('a named connection shows its name and uses its logRedact', () {
      List<String> lines = _prints(
        () => Logger().log(
          'UPDATE t SET password = @password_p1, token = @token_p2, '
              'name = @name_p3',
          <String, dynamic>{
            'password_p1': 'a',
            'token_p2': 'b',
            'name_p3': 'c',
          },
          'other',
        ),
      );
      expect(lines, <String>[
        "\x1B[2;36m▌ [db:other]\x1B[0m UPDATE t SET password = '***', "
            "token = '***', name = 'c';",
      ]);
    });

    test('a slow query of a named connection shows its name', () async {
      List<String> lines = await _printsAsync(
        () => QueryBuilder.query(
          'SELECT @token_p1',
          substitutionValues: <String, dynamic>{'token_p1': 'x'},
          connection: 'other',
        ),
      );
      expect(lines.length, 1);
      expect(
        lines.first,
        matches(
          RegExp(
            r"^\x1B\[2;36m▌ \[db:other SLOW \d+ms\]\x1B\[0m SELECT '\*\*\*';$",
          ),
        ),
      );
    });

    test('a subclass that overrides log() gets the ? query and values', () {
      _MyPretty mine = _MyPretty();
      SqlQueryBuilder().printer = mine;
      Logger().log('x = @a', <String, dynamic>{'a': 1});
      expect(mine.query, 'x = ?');
      expect(mine.params, <String>['1']);
    });

    test('falls back to the ? line when the values can not be filled', () {
      // an unknown connection makes the driver lookup throw
      List<String> lines = _prints(
        () => Logger().log('x = @a', <String, dynamic>{'a': 1}, 'nope'),
      );
      expect(lines, <String>['\x1B[2;36m▌ [db]\x1B[0m x = ?; -- [1]']);
    });

    test('puts the ; on a new line after a -- comment', () {
      List<String> lines = _prints(() => Logger().log('SELECT 1 -- note'));
      expect(lines, <String>['${tag}SELECT 1 -- note\n;']);
    });

    test('mysql: literal rules and backslash in raw SQL', () {
      expect(
        Logger.fillSql(
          r"SELECT `a` FROM `t` WHERE `s` = 'x\'' AND `b` = @b AND `c` = @c",
          <String, dynamic>{'b': true, 'c': r'a\b'},
          Driver.mysql,
          <String>[],
        ),
        r"SELECT `a` FROM `t` WHERE `s` = 'x\'' AND `b` = 1 AND `c` = 'a\\b'",
      );
    });

    test('bytes show as a hex literal', () {
      Map<String, dynamic> values = <String, dynamic>{
        'b': Uint8List.fromList(<int>[1, 2, 255]),
      };
      expect(
        Logger.fillSql('x = @b', values, Driver.sqlite, <String>[]),
        "x = X'0102ff'",
      );
      expect(
        Logger.fillSql('x = @b', values, Driver.mysql, <String>[]),
        "x = X'0102ff'",
      );
      expect(
        Logger.fillSql('x = @b', values, Driver.postgres, <String>[]),
        r"x = '\x0102ff'",
      );
    });

    test('log() called directly prints one line with the params', () {
      expect(
        _prints(() => PrettyQueryPrinter().log('SELECT 1', <String>[])),
        <String>['\x1B[2;36m▌ [db]\x1B[0m SELECT 1;'],
      );
      expect(
        _prints(() => PrettyQueryPrinter().log('x = ?', <String>['p1'])),
        <String>['\x1B[2;36m▌ [db]\x1B[0m x = ?; -- [p1]'],
      );
    });
  });
}

Future<List<String>> _printsAsync(Future<void> Function() body) async {
  List<String> lines = <String>[];
  await runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      print: (Zone self, ZoneDelegate parent, Zone zone, String line) {
        lines.add(line);
      },
    ),
  );
  return lines;
}

/// a subclass with its own log(), like user code may have
class _MyPretty extends PrettyQueryPrinter {
  String query = '';
  List<String> params = <String>[];

  @override
  void log(String query, List<String> params) {
    this.query = query;
    this.params = params;
  }
}

List<String> _prints(void Function() body) {
  List<String> lines = <String>[];
  runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      print: (Zone self, ZoneDelegate parent, Zone zone, String line) {
        lines.add(line);
      },
    ),
  );
  return lines;
}
