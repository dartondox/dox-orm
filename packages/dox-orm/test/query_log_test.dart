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
}
