import 'dart:io';
import 'dart:isolate';

import 'package:dox_migration/dox_migration.dart';
import 'package:dox_migration/src/utils/db_connection.dart';
import 'package:test/test.dart';

/// runs `migrate()` on the SQLite file [path], in the isolate that the
/// test starts
Future<void> runMigrate(String path) async {
  await Migrator(
    directory: Directory(File(path).parent.path),
    config: DbConnection.config(<String, String>{
      'DB_CONNECTION': 'sqlite',
      'DB_DATABASE': path,
    }),
  ).migrate();
}

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('dox_group_worker_'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('the name of a Dox isolate group is known', () {
    expect(Migrator.isGroupWorker('dox-group-2-8-123456'), isTrue);
    expect(Migrator.isGroupWorker('dox-group-3-4--98765'), isTrue);
    expect(Migrator.isGroupWorker('main'), isFalse);
    expect(Migrator.isGroupWorker('isolateHandler'), isFalse);
    expect(Migrator.isGroupWorker(null), isFalse);
  });

  test('migrate() opens no database in a Dox isolate group', () async {
    String path = '${dir.path}/app.db';
    await Isolate.run(() => runMigrate(path), debugName: 'dox-group-2-3-1');
    expect(File(path).existsSync(), isFalse);
  });

  test('migrate() runs in any other isolate', () async {
    String path = '${dir.path}/app.db';
    await Isolate.run(() => runMigrate(path), debugName: 'worker');
    expect(File(path).existsSync(), isTrue);
  });
}
