import 'dart:async';
import 'dart:io';

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

  test(
    'FileQueryPrinter writes every line, in order, without blocking',
    () async {
      Directory dir = await Directory.systemTemp.createTemp('dox_log');
      File file = File('${dir.path}/sub/query.log');
      FileQueryPrinter printer = FileQueryPrinter(file: file);
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
    List<String> lines = <String>[];
    runZoned(
      _warn,
      zoneSpecification: ZoneSpecification(
        print: (Zone self, ZoneDelegate parent, Zone zone, String line) {
          lines.add(line);
        },
      ),
    );
    expect(lines, <String>['\x1B[33mcareful\x1B[0m']);
  });
}

void _warn() => Logger.warn('careful');
