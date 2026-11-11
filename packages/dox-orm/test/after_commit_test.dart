import 'dart:async';

import 'package:dox_orm/dox_orm.dart';
import 'package:test/test.dart';

import 'connection.dart';
import 'models/blog/blog.model.dart';

void main() async {
  await initQueryBuilder();

  group('afterCommit |', () {
    setUp(() async {
      await Schema().create('blog', (Table table) {
        table.id('uid');
        table.string('title');
        table.string('status').withDefault('active');
        table.text('body');
        table.string('slug').nullable();
        table.softDeletes();
        table.timestamps();
      });
    });

    tearDown(() async {
      await Schema().dropIfExists('blog');
    });

    Future<void> add(String title) =>
        QueryBuilder.table('blog')
            .setPrimaryKey('uid')
            .insert(<String, dynamic>{'title': title, 'body': 'b'});

    test('runs after commit, in order, with the data saved', () async {
      List<String> log = <String>[];
      await QueryBuilder.transaction(() async {
        await add('a');
        await QueryBuilder.afterCommit(() async {
          expect(DBDriver.inTransaction, false);
          log.add('first ${await Blog().count()}');
        });
        await QueryBuilder.afterCommit(() => log.add('second'));
        log.add('body');
      });
      expect(log, <String>['body', 'first 1', 'second']);
    });

    test('runs at once outside a transaction', () async {
      List<String> log = <String>[];
      await QueryBuilder.afterCommit(() => log.add('now'));
      expect(log, <String>['now']);
    });

    test('rollback drops the callbacks', () async {
      List<String> log = <String>[];
      await expectLater(
        QueryBuilder.transaction(() async {
          await QueryBuilder.afterCommit(() => log.add('x'));
          throw StateError('stop');
        }),
        throwsStateError,
      );
      expect(log, isEmpty);
    });

    test('nested commit runs after the outer commit', () async {
      List<String> log = <String>[];
      await QueryBuilder.transaction(() async {
        await QueryBuilder.transaction(() async {
          await QueryBuilder.afterCommit(() => log.add('inner'));
        });
        log.add('outer body');
      });
      expect(log, <String>['outer body', 'inner']);
    });

    test('nested rollback drops only its callbacks', () async {
      List<String> log = <String>[];
      await QueryBuilder.transaction(() async {
        await QueryBuilder.afterCommit(() => log.add('outer'));
        try {
          await QueryBuilder.transaction(() async {
            await QueryBuilder.afterCommit(() => log.add('inner'));
            await QueryBuilder.transaction(() async {
              await QueryBuilder.afterCommit(() => log.add('deep'));
            });
            throw StateError('stop');
          });
        } on StateError {
          // the outer transaction goes on
        }
        await QueryBuilder.transaction(() async {
          await QueryBuilder.afterCommit(() => log.add('later'));
        });
      });
      expect(log, <String>['outer', 'later']);
    });

    test('a throwing callback keeps the commit and the others', () async {
      List<String> log = <String>[];
      await expectLater(
        QueryBuilder.transaction(() async {
          await add('saved');
          await QueryBuilder.afterCommit(() => throw StateError('first'));
          await QueryBuilder.afterCommit(() => log.add('second'));
          await QueryBuilder.afterCommit(() => throw ArgumentError('third'));
        }),
        throwsA(isA<StateError>()),
      );
      expect(log, <String>['second']);
      expect(await Blog().count(), 1);
    });

    test('the transaction waits for async callbacks', () async {
      List<String> log = <String>[];
      await QueryBuilder.transaction(() async {
        await QueryBuilder.afterCommit(() async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          log.add('slow');
        });
        await QueryBuilder.afterCommit(() => log.add('fast'));
      });
      expect(log, <String>['slow', 'fast']);
    });

    test('a callback can open a transaction and add callbacks', () async {
      List<String> log = <String>[];
      await QueryBuilder.transaction(() async {
        await QueryBuilder.afterCommit(() async {
          await QueryBuilder.afterCommit(() => log.add('at once'));
          await QueryBuilder.transaction(() async {
            await add('from callback');
            await QueryBuilder.afterCommit(() => log.add('second commit'));
          });
        });
      });
      expect(log, <String>['at once', 'second commit']);
      expect(await Blog().count(), 1);
    });

    test('a Timer that fires after the commit runs at once', () async {
      Completer<String> done = Completer<String>();
      await QueryBuilder.transaction(() async {
        Timer(const Duration(milliseconds: 20), () {
          QueryBuilder.afterCommit(() => done.complete('ran'));
        });
      });
      expect(await done.future.timeout(const Duration(seconds: 5)), 'ran');
    });

    test('a future that ends after the body runs at once', () async {
      List<String> log = <String>[];
      Future<void>? late;
      await QueryBuilder.transaction(() async {
        late = Future<void>.delayed(
          const Duration(milliseconds: 20),
          () => QueryBuilder.afterCommit(() => log.add('late')),
        );
      });
      expect(log, isEmpty);
      await late;
      expect(log, <String>['late']);
    });

    test('a late call after a rollback is dropped', () async {
      List<String> log = <String>[];
      Completer<void> called = Completer<void>();
      await expectLater(
        QueryBuilder.transaction(() async {
          Timer(const Duration(milliseconds: 20), () async {
            await QueryBuilder.afterCommit(() => log.add('late'));
            called.complete();
          });
          throw StateError('stop');
        }),
        throwsStateError,
      );
      await called.future.timeout(const Duration(seconds: 5));

      /// a later transaction must not pick it up
      await QueryBuilder.transaction(() => add('next'));
      expect(log, isEmpty);
    });

    test('a callback that throws outside a transaction throws', () async {
      await expectLater(
        QueryBuilder.afterCommit(() => throw StateError('x')),
        throwsStateError,
      );
    });
  });
}
