import 'package:dox_core/dox_core.dart';
import 'package:dox_orm/dox_orm.dart';
import 'package:test/test.dart';

/// the ORM provider of an app: it closes the database on shutdown
class OrmProvider extends DoxProvider {
  @override
  void setup() {
    SqlQueryBuilder.initializeWithDatabaseConfig(
      DatabaseConfig(
        connection: 'sqlite',
        url: '',
        connections: <String, ConnectionConfig>{
          'sqlite': ConnectionConfig(
            driver: Driver.sqlite,
            database: ':memory:',
            debug: false,
          ),
        },
      ),
    );
  }

  @override
  Future<void> shutdown() => SqlQueryBuilder.close();
}

void main() {
  test('Dox().stop() closes the database of an ORM provider', () async {
    Dox().initialize(
      AppConfig(
        appKey: '4HyiSrq4N5Nfg6bOadIhbFEI8zbUkpxt',
        // the OS picks a free port, so test files can run in parallel
        serverPort: 0,
        totalIsolate: 1,
        providers: <DoxProvider>[OrmProvider()],
      ),
    );
    await Dox().startServer();
    expect(
      await SqlQueryBuilder().dbDriver.query('SELECT 1 AS n'),
      <Map<String, dynamic>>[
        <String, dynamic>{'n': 1},
      ],
    );
    await Dox().stop();
    expect(() => SqlQueryBuilder().dbDriver, throwsStateError);
  });
}
