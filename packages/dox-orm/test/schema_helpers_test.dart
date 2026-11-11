import 'package:dox_orm/dox_orm.dart';
import 'package:test/test.dart';

import 'connection.dart';

/// hasColumns, hasIndex and the foreign key switches, on a real database
void main() async {
  await initQueryBuilder();
  Schema schema = Schema();
  Driver driver = SqlQueryBuilder().dbDriver.getName();

  Future<void> clean() async {
    await schema.dropIfExists('sh_post');
    await schema.dropIfExists('sh_user');
  }

  setUp(() async {
    await clean();
    await schema.create('sh_user', (Table table) {
      table.id();
      table.string('email').unique();
      table.string('first');
      table.string('last');
      table.index(<String>['first', 'last']);
    });
    await schema.create('sh_post', (Table table) {
      table.id();
      table.foreignId('user_id').constrained('sh_user');
    });
  });
  tearDown(clean);

  Future<void> orphan() =>
      QueryBuilder.table('sh_post').insert(<String, dynamic>{'user_id': 99});

  Future<int> posts() => QueryBuilder.table('sh_post').count();

  test('hasColumns', () async {
    expect(await schema.hasColumns('sh_user', <String>['email', 'id']), isTrue);
    expect(await schema.hasColumns('sh_user', <String>[]), isTrue);
    expect(
      await schema.hasColumns('sh_user', <String>['email', 'nope']),
      isFalse,
    );
    expect(await schema.hasColumns('nope', <String>['id']), isFalse);
  });

  test('hasIndex by name and by columns', () async {
    expect(await schema.hasIndex('sh_user', 'sh_user_email_unique'), isTrue);
    expect(
      await schema.hasIndex('sh_user', 'sh_user_first_last_index'),
      isTrue,
    );
    expect(await schema.hasIndex('sh_user', 'nope'), isFalse);
    expect(await schema.hasIndex('sh_user', <String>['email']), isTrue);
    expect(await schema.hasIndex('sh_user', <String>['first', 'last']), isTrue);
    expect(await schema.hasIndex('sh_user', <String>['id']), isTrue);

    /// the order of the columns counts, and a part is not the index
    expect(
      await schema.hasIndex('sh_user', <String>['last', 'first']),
      isFalse,
    );
    expect(await schema.hasIndex('sh_user', <String>['first']), isFalse);
    expect(await schema.hasIndex('nope', <String>['id']), isFalse);
    expect(() => schema.hasIndex('sh_user', 1), throwsArgumentError);
  });

  test('withoutForeignKeyConstraints lets a row miss its parent', () async {
    Future<void> run() => schema.withoutForeignKeyConstraints(orphan);
    if (driver == Driver.postgres) {
      /// postgres: the key is not DEFERRABLE, so it is checked at once
      await expectLater(run(), throwsA(isA<PgServerException>()));
      expect(await posts(), 0);
    } else {
      await run();
      expect(await posts(), 1);
    }

    /// the checks are on again, on every connection
    for (int i = 0; i < 3; i++) {
      await expectLater(orphan(), throwsA(anything));
    }
  });

  test('withoutForeignKeyConstraints turns them on after an error', () async {
    await expectLater(
      schema.withoutForeignKeyConstraints(() async {
        throw StateError('stop');
      }),
      throwsStateError,
    );
    await expectLater(orphan(), throwsA(anything));
  });

  test('disable and enable inside a transaction', () async {
    Future<void> run() => QueryBuilder.transaction(() async {
      await schema.disableForeignKeyConstraints();
      await orphan();
      await schema.enableForeignKeyConstraints();
    });
    if (driver == Driver.mysql) {
      await run();
      expect(await posts(), 1);
    } else {
      /// sqlite: the pragma does nothing inside a transaction.
      /// postgres: the key is not DEFERRABLE.
      await expectLater(run(), throwsA(anything));
      expect(await posts(), 0);
    }
    await expectLater(orphan(), throwsA(anything));
  });

  test('sqlite: disable and enable outside a transaction', () async {
    await schema.disableForeignKeyConstraints();
    try {
      await orphan();
    } finally {
      await schema.enableForeignKeyConstraints();
    }
    expect(await posts(), 1);
    await expectLater(orphan(), throwsA(anything));
  }, skip: driver == Driver.sqlite ? null : 'sqlite only');

  test('postgres: a DEFERRABLE key waits until it is on again', () async {
    await QueryBuilder.query(
      'ALTER TABLE sh_post ALTER CONSTRAINT sh_post_user_id_foreign '
      'DEFERRABLE',
    );

    /// the child first, then its parent
    await schema.withoutForeignKeyConstraints(() async {
      await QueryBuilder.table('sh_post')
          .insert(<String, dynamic>{'user_id': 50});
      await QueryBuilder.table('sh_user').insert(<String, dynamic>{
        'id': 50,
        'email': 'a',
        'first': 'a',
        'last': 'a',
      });
    });
    expect(await posts(), 1);

    /// a row that still misses its parent fails when they are on again
    await expectLater(
      schema.withoutForeignKeyConstraints(orphan),
      throwsA(isA<PgServerException>()),
    );
    expect(await posts(), 1);
  }, skip: driver == Driver.postgres ? null : 'postgres only');

  test('mysql and postgres: outside a transaction it throws', () async {
    await expectLater(schema.disableForeignKeyConstraints(), throwsStateError);
    await expectLater(schema.enableForeignKeyConstraints(), throwsStateError);
  }, skip: driver == Driver.sqlite ? 'sqlite runs it' : null);
}
