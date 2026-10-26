import 'dart:io';
import 'dart:isolate';

import 'package:dox_orm/dox_orm.dart';
import 'package:test/test.dart';

/// opens [path] like one server isolate does on start.
Future<void> openInIsolate(String path) {
  return Isolate.run(() async {
    ConnectionConfig config = ConnectionConfig(
      driver: Driver.sqlite,
      database: path,
      debug: false,
    );
    DBDriver driver = config.createDriver();
    await driver.close();
  });
}

void main() {
  test('many isolates can open a new sqlite file at the same time', () async {
    Directory dir = Directory.systemTemp.createTempSync('dox_sqlite_open_');
    addTearDown(() => dir.deleteSync(recursive: true));

    for (int round = 0; round < 5; round++) {
      String path = '${dir.path}/app_$round.sqlite';
      await Future.wait(<Future<void>>[
        for (int i = 0; i < 16; i++) openInIsolate(path),
      ]);
    }
  });
}
