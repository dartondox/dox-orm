import 'dart:async';

import 'package:dox_orm/dox_orm.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;
import 'package:test/test.dart';

import 'connection.dart';

/// a deadlock, like the server sends it
PgServerException deadlock() =>
    PgServerException('deadlock detected', code: '40P01', severity: 'ERROR');

void main() async {
  await initQueryBuilder();
  Driver driver = SqlQueryBuilder().dbDriver.getName();

  setUp(() async {
    await Schema().create('tx_retry', (Table table) {
      table.id();
      table.string('title');
    });
  });

  tearDown(() async {
    await Schema().dropIfExists('tx_retry');
  });

  Future<void> add(String title) =>
      QueryBuilder.table('tx_retry').insert(<String, dynamic>{'title': title});

  Future<List<String>> titles() async {
    List<Map<String, dynamic>> rows = await QueryBuilder.table('tx_retry')
        .orderBy('id')
        .get();
    return <String>[for (Map<String, dynamic> r in rows) r['title'] as String];
  }

  group('transaction attempts |', () {
    test('isConcurrencyError knows the codes of each database', () {
      bool check(Object e) => DatabaseTransaction.isConcurrencyError(e);
      expect(check(deadlock()), isTrue);
      expect(
        check(PgServerException('x', code: '40001', severity: 'ERROR')),
        isTrue,
      );
      expect(
        check(PgServerException('x', code: '23505', severity: 'ERROR')),
        isFalse,
      );
      expect(check(MysqlException('x', code: 1213)), isTrue);
      expect(check(MysqlException('x', code: 1205)), isTrue);
      expect(check(MysqlException('x', code: 1020)), isTrue);
      expect(check(MysqlException('x', sqlState: '40001')), isTrue);
      expect(check(MysqlException('x', code: 1062)), isFalse);
      expect(
        check(SqliteException(extendedResultCode: 5, message: 'locked')),
        isTrue,
      );
      // SQLITE_BUSY_SNAPSHOT is an extended code of SQLITE_BUSY
      expect(
        check(SqliteException(extendedResultCode: 517, message: 'busy')),
        isTrue,
      );
      expect(
        check(SqliteException(extendedResultCode: 19, message: 'unique')),
        isFalse,
      );
      expect(check(StateError('deadlock detected')), isFalse);
    });

    test('without attempts it runs once, like before', () async {
      int runs = 0;
      await expectLater(
        QueryBuilder.transaction(() async {
          runs++;
          await add('a');
          throw deadlock();
        }),
        throwsA(isA<PgServerException>()),
      );
      expect(runs, 1);
      expect(await titles(), isEmpty);
    });

    test('runs again after a deadlock, keeps only the last run', () async {
      int runs = 0;
      List<String> log = <String>[];
      String result = await QueryBuilder.transaction(() async {
        runs++;
        await add('run $runs');
        await QueryBuilder.afterCommit(() => log.add('after $runs'));
        if (runs < 3) throw deadlock();
        return 'done';
      }, attempts: 3);
      expect(result, 'done');
      expect(runs, 3);
      expect(await titles(), <String>['run 3']);
      expect(log, <String>['after 3']);
    });

    test('throws the last error when all attempts fail', () async {
      int runs = 0;
      await expectLater(
        QueryBuilder.transaction(() async {
          runs++;
          throw deadlock();
        }, attempts: 2),
        throwsA(isA<PgServerException>()),
      );
      expect(runs, 2);
    });

    test('other errors are not run again', () async {
      int runs = 0;
      await expectLater(
        QueryBuilder.transaction(() async {
          runs++;
          throw StateError('stop');
        }, attempts: 5),
        throwsStateError,
      );
      expect(runs, 1);
    });

    test(
      'a nested transaction does not run again, the outer one does',
      () async {
        int outer = 0;
        int inner = 0;
        await QueryBuilder.transaction(() async {
          outer++;
          await add('outer $outer');
          await QueryBuilder.transaction(() async {
            inner++;
            if (inner < 2) throw deadlock();
          }, attempts: 5);
        }, attempts: 3);
        expect(outer, 2);
        expect(inner, 2);
        expect(await titles(), <String>['outer 2']);
      },
    );

    test('an error after the commit does not run it again', () async {
      int runs = 0;
      await expectLater(
        QueryBuilder.transaction(() async {
          runs++;
          await add('a');
          await QueryBuilder.afterCommit(() => throw deadlock());
        }, attempts: 3),
        throwsA(isA<PgServerException>()),
      );
      expect(runs, 1);
      expect(await titles(), <String>['a']);
    });

    test(
      'a real deadlock of two transactions is run again',
      () async {
        await add('a');
        await add('b');
        Completer<void> firstLocked = Completer<void>();
        Completer<void> secondLocked = Completer<void>();
        int runs = 0;

        /// each one locks one row, waits for the other, then wants the
        /// other row: the database kills one of them
        /// by id: an update by an other column locks every row it reads
        Future<void> swap(
          int first,
          int second,
          Completer<void> mine,
          Completer<void> other,
        ) {
          return QueryBuilder.transaction(() async {
            runs++;
            await QueryBuilder.table('tx_retry')
                .where('id', first)
                .update(<String, dynamic>{'title': 'x'});
            if (!mine.isCompleted) mine.complete();
            await other.future;
            await QueryBuilder.table('tx_retry')
                .where('id', second)
                .update(<String, dynamic>{'title': 'y'});
          }, attempts: 3);
        }

        await Future.wait(<Future<void>>[
          swap(1, 2, firstLocked, secondLocked),
          swap(2, 1, secondLocked, firstLocked),
        ]);
        expect(runs, 3);
      },
      skip: driver == Driver.sqlite
          ? 'sqlite has one connection per isolate: no deadlock'
          : null,
    );

    test('attempts 0 and below run once', () async {
      for (int attempts in <int>[0, -1]) {
        int runs = 0;
        await expectLater(
          QueryBuilder.transaction(() async {
            runs++;
            throw deadlock();
          }, attempts: attempts),
          throwsA(isA<PgServerException>()),
        );
        expect(runs, 1);
      }
    });

    test('an error that wraps a deadlock is not run again', () async {
      int runs = 0;
      await expectLater(
        QueryBuilder.transaction(() async {
          runs++;
          throw _Wrapped(deadlock());
        }, attempts: 3),
        throwsA(isA<_Wrapped>()),
      );
      expect(runs, 1);
    });

    test(
      'a serialization failure at COMMIT is run again',
      () async {
        Completer<void> firstWrote = Completer<void>();
        Completer<void> secondWrote = Completer<void>();
        Completer<void> firstCommitted = Completer<void>();
        int runs = 0;
        int finished = 0;

        /// write skew: each one reads the table, then adds a row. under
        /// SERIALIZABLE the second COMMIT fails with 40001.
        Future<void> addOne(
          String title,
          Completer<void> mine,
          Future<void> waitFor,
        ) {
          return QueryBuilder.transaction(() async {
            runs++;
            await QueryBuilder.query(
              'SET TRANSACTION ISOLATION LEVEL SERIALIZABLE',
            );
            await QueryBuilder.table('tx_retry').count();
            await add(title);
            if (!mine.isCompleted) mine.complete();
            await waitFor;
            finished++;
          }, attempts: 3);
        }

        Future<void> first = addOne(
          'first',
          firstWrote,
          secondWrote.future,
        ).then((_) => firstCommitted.complete());
        Future<void> second = addOne(
          'second',
          secondWrote,
          firstCommitted.future,
        );
        await Future.wait(<Future<void>>[first, second]);

        /// every callback ended, so the failed run failed at its COMMIT
        expect(runs, 3);
        expect(finished, 3);
        expect(await titles(), <String>['first', 'second']);
      },
      skip: driver == Driver.postgres
          ? null
          : 'only postgres fails a COMMIT with a serialization failure',
    );
  });

  group('beginTransaction |', () {
    test('commit saves the work of run(), with afterCommit', () async {
      List<String> log = <String>[];
      DatabaseTransaction tx = await QueryBuilder.beginTransaction();
      expect(tx.isOpen, isTrue);
      await tx.run(() async {
        expect(DBDriver.inTransaction, isTrue);
        await add('a');
        await QueryBuilder.afterCommit(() => log.add('after'));
      });
      expect(DBDriver.inTransaction, isFalse);
      await tx.run(() => add('b'));
      expect(log, isEmpty);
      await tx.commit();
      expect(tx.isOpen, isFalse);
      expect(log, <String>['after']);
      expect(await titles(), <String>['a', 'b']);
    });

    test('rollBack undoes the work and drops afterCommit', () async {
      List<String> log = <String>[];
      DatabaseTransaction tx = await QueryBuilder.beginTransaction();
      await tx.run(() async {
        await add('a');
        await QueryBuilder.afterCommit(() => log.add('after'));
      });
      await tx.rollBack();
      await tx.rollBack(); // a second call does nothing
      expect(log, isEmpty);
      expect(await titles(), isEmpty);
      expect(() => tx.run(() => add('b')), throwsStateError);
      expect(tx.commit(), throwsStateError);
    });

    test('a nested transaction inside run() is a savepoint', () async {
      DatabaseTransaction tx = await QueryBuilder.beginTransaction();
      await tx.run(() async {
        await add('a');
        try {
          await QueryBuilder.transaction(() async {
            await add('b');
            throw StateError('stop');
          });
        } on StateError {
          // only b is undone
        }
      });
      await tx.commit();
      expect(await titles(), <String>['a']);
    });

    test('rollBack in finally does nothing after commit', () async {
      DatabaseTransaction tx = await QueryBuilder.beginTransaction();
      try {
        await tx.run(() => add('a'));
        await tx.commit();
      } finally {
        await tx.rollBack();
      }
      expect(await titles(), <String>['a']);
    });

    test('it is rolled back after the timeout', () async {
      DatabaseTransaction tx = await QueryBuilder.beginTransaction(
        timeout: const Duration(milliseconds: 50),
      );
      await tx.run(() => add('a'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(tx.isOpen, isFalse);
      expect(await titles(), isEmpty);
      expect(tx.commit(), throwsStateError);
      await tx.rollBack();
    });

    test('it can not begin inside a transaction', () async {
      await QueryBuilder.transaction(() async {
        await expectLater(QueryBuilder.beginTransaction(), throwsStateError);
      });
    });

    test('queries outside run() do not join it', () async {
      DatabaseTransaction tx = await QueryBuilder.beginTransaction();
      await tx.run(() => add('a'));
      Future<void> outside = add('b');
      if (driver != Driver.sqlite) {
        // another pool connection: it does not see the open work
        await outside;
        expect(await titles(), <String>['b']);
      }
      await tx.rollBack();
      // sqlite: the outside insert waited for the transaction to end
      await outside;
      expect(await titles(), <String>['b']);
    });
  });
}

/// an app error that keeps the database error inside
class _Wrapped implements Exception {
  final Object cause;
  _Wrapped(this.cause);
}
