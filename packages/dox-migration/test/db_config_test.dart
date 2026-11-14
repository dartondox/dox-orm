import 'package:dox_migration/src/utils/db_connection.dart';
import 'package:dox_orm/dox_orm.dart';
import 'package:test/test.dart';

void main() {
  group('DbConnection.config', () {
    test('a bad DATABASE_URL never shows its secret in the error', () {
      const String secret = 'S3cretPw';
      for (String url in <String>[
        'postgres://app:$secret@db.example.com:54x2/blog',
        'postgres://h:x/d?password=$secret',
        'postgres://u@h:x/d#$secret',
        'postgres:user:$secret@host/db',
        'redis://app:$secret@db.example.com/0',
      ]) {
        Object? error;
        try {
          DbConnection.config(<String, String>{'DATABASE_URL': url});
        } catch (e) {
          error = e;
        }
        expect(error, isA<FormatException>(), reason: url);
        expect(error.toString(), contains('DATABASE_URL'), reason: url);
        expect(error.toString(), isNot(contains(secret)), reason: url);
      }
    });

    test('DATABASE_URL wins over DB_* keys', () {
      ConnectionConfig c = DbConnection.config(<String, String>{
        'DB_CONNECTION': 'mysql',
        'DB_HOST': 'ignored',
        'DATABASE_URL': 'postgres://app:s%40cret@/blog?host=/cloudsql/p:r:i',
      });
      expect(c.driver, Driver.postgres);
      expect(c.password, 's@cret');
      expect(c.host, '/cloudsql/p:r:i');
    });

    test('mysql DB_HOST socket file', () {
      ConnectionConfig c = DbConnection.config(<String, String>{
        'DB_CONNECTION': 'mysql',
        'DB_HOST': '/cloudsql/p:r:i',
      });
      expect(c.driver, Driver.mysql);
      expect(c.isUnixSocket, isTrue);
    });

    /// the same defaults as the app template, so an empty .env gives the
    /// same database to the app and to the migrations
    test('empty env is sqlite with db/dox.sqlite', () {
      ConnectionConfig c = DbConnection.config(<String, String>{});
      expect(c.driver, Driver.sqlite);
      expect(c.database, 'db/dox.sqlite');

      ConnectionConfig named = DbConnection.config(<String, String>{
        'DB_NAME': 'data/app.sqlite',
      });
      expect(named.driver, Driver.sqlite);
      expect(named.database, 'data/app.sqlite');
    });

    test('unknown DB_CONNECTION throws', () {
      expect(
        () => DbConnection.config(<String, String>{'DB_CONNECTION': 'oracle'}),
        throwsArgumentError,
      );
    });

    test('DB_* keys and their defaults', () {
      ConnectionConfig pg = DbConnection.config(<String, String>{
        'DB_CONNECTION': 'postgres',
      });
      expect(pg.driver, Driver.postgres);
      expect(pg.port, 5432);
      expect(pg.user, 'postgres');
      expect(pg.database, 'dox');

      ConnectionConfig my = DbConnection.config(<String, String>{
        'DB_CONNECTION': 'mysql',
        'DB_DATABASE': 'a',
        'DB_NAME': 'b',
      });
      expect(my.port, 3306);
      expect(my.user, 'root');
      expect(my.password, '');
      expect(my.database, 'a');
    });

    test('opens sqlite from DATABASE_URL', () async {
      DbConnection db = await DbConnection.open(<String, String>{
        'DATABASE_URL': 'sqlite::memory:',
      });
      expect(await db.execute('SELECT 1 AS n'), <Map<String, dynamic>>[
        <String, dynamic>{'n': 1},
      ]);
      await db.close();
    });
  });
}
