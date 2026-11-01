import 'dart:io';

import 'package:dox_orm/dox_orm.dart';
import 'package:dox_validation/dox_validation.dart' hide Schema;
import 'package:test/test.dart';

import 'connection.dart';

/// `@Unique`, `@Exists` and the fluent `unique()` / `exists()` on every
/// database. Run with DRIVER=sqlite, postgres or mysql.
/// counts the queries of [RowFinder] (each `found` call is one query)
class CountingFinder extends RowFinder {
  CountingFinder();

  int calls = 0;

  @override
  Future<Set<String>> found(
    String table,
    String column,
    List<Object?> values, {
    String? exceptColumn,
    Object? exceptValue,
    String? connection,
  }) {
    calls++;
    return super.found(
      table,
      column,
      values,
      exceptColumn: exceptColumn,
      exceptValue: exceptValue,
      connection: connection,
    );
  }
}

void main() async {
  await initQueryBuilder();

  RuleContext context() {
    return RuleContext(
      state: ParseState(root: <String, dynamic>{}),
      path: const <Object>['email'],
    );
  }

  group('database rules |', () {
    setUp(() async {
      await Schema().create('rule_emails', (Table table) {
        table.id();
        table.string('email');
        table.integer('n').withDefault(1);
      });
      await QueryBuilder.table('rule_emails')
          .insert(<String, dynamic>{'email': 'taken@dox.dev'});
    });

    tearDown(() async {
      await Schema().dropIfExists('rule_emails');
    });

    test('the ORM is the PresenceVerifier', () {
      expect(PresenceVerifier.instance, isA<RowFinder>());
    });

    test('one value: the database match decides', () async {
      for (String value in <String>[
        'taken@dox.dev',
        'TAKEN@dox.dev',
        'new@dox.dev',
      ]) {
        // what the database says, with its own collation
        bool inDb =
            (await QueryBuilder.table('rule_emails')
                .where('email', value)
                .count()) >
            0;
        expect(
          await const Unique('rule_emails').checkAsync(value, context()),
          !inDb,
          reason: '@Unique $value',
        );
        // @Exists keeps the 3.0.1 rule: the exact text must be found
        expect(
          await const Exists(
            'rule_emails',
            column: 'email',
          ).checkAsync(value, context()),
          value == 'taken@dox.dev',
          reason: '@Exists $value',
        );
        ParseResult<String> fluent = await v
            .string()
            .unique('rule_emails', column: 'email')
            .safeParseAsync(value);
        expect(fluent.success, !inDb, reason: 'unique() $value');
      }
    });

    test('one @Exists value needs its exact text, like 3.0.1', () async {
      Exists id = const Exists('rule_emails');
      expect(await id.checkAsync(1, context()), isTrue);
      expect(await id.checkAsync('1', context()), isTrue);
      // these find the row 1 on some databases, but they are not `1`
      for (String value in <String>['01', ' 1', '1abc']) {
        expect(await id.checkAsync(value, context()), isFalse, reason: value);
      }
    });

    test('a list is one query, the database does the matching', () async {
      // what the database says for TAKEN@ (MySQL and MariaDB ignore case)
      bool caseFree =
          (await QueryBuilder.table('rule_emails')
              .where('email', 'TAKEN@dox.dev')
              .count()) >
          0;
      Unique unique = const Unique('rule_emails', column: 'email');
      Exists exists = const Exists('rule_emails', column: 'email');
      Future<List<int>> u(List<Object?> values) {
        return unique.failedItems(values, context());
      }

      Future<List<int>> e(List<Object?> values) {
        return exists.failedItems(values, context());
      }

      // any row found: every item fails (one query can not tell which)
      expect(await u(<Object?>['new@dox.dev', 'taken@dox.dev']), <int>[0, 1]);
      expect(await e(<Object?>['taken@dox.dev', 'nope@dox.dev']), <int>[1]);
      expect(await e(<Object?>['taken@dox.dev', 'taken@dox.dev']), <int>[]);
      // only the database matched: it can not tell which, so all fail
      expect(
        await u(<Object?>['new@dox.dev', 'TAKEN@dox.dev']),
        caseFree ? <int>[0, 1] : <int>[],
      );
      expect(
        await e(<Object?>['TAKEN@dox.dev', 'TAKEN@dox.dev']),
        <int>[0, 1], // an item passes only when its exact text is found
      );
    });

    test('a list never lets a wrong value pass (MySQL ignores case)', () async {
      await QueryBuilder.table('rule_emails')
          .insert(<String, dynamic>{'email': 'other@dox.dev'});
      // OTHER@ is taken on MySQL and MariaDB, but it matches no row as
      // text: every item must fail
      expect(
        await const Unique(
          'rule_emails',
          column: 'email',
        ).failedItems(<Object?>['taken@dox.dev', 'OTHER@dox.dev'], context()),
        <int>[0, 1],
      );
      await Schema().create('rule_people', (Table table) {
        table.id();
        table.string('name');
      });
      try {
        for (String name in <String>['bob', 'Bob']) {
          await QueryBuilder.table('rule_people')
              .insert(<String, dynamic>{'name': name});
        }
        // `bob` finds two rows on MySQL: `nobody` must still fail
        expect(
          await const Exists(
            'rule_people',
            column: 'name',
          ).failedItems(<Object?>['bob', 'nobody'], context()),
          <int>[1],
        );
      } finally {
        await Schema().dropIfExists('rule_people');
      }
    });

    test('a value that does not fit the column is not found', () async {
      // `abc` and `1.0` for a bigint id, and a number too big for it
      expect(
        (await v.string().exists('rule_emails').safeParseAsync('abc')).success,
        isFalse,
      );
      expect(
        (await v
                .string()
                .unique('rule_emails', column: 'id')
                .safeParseAsync('abc'))
            .success,
        isTrue,
      );
      expect(
        await const Exists('rule_emails').checkAsync(1.5, context()),
        isFalse,
      );
      // a list with a bad value: Postgres can not compare it, so every
      // item fails (the safe side). The others just do not find `abc`.
      bool postgres = Platform.environment['DRIVER'] == 'postgres';
      expect(
        await const Exists('rule_emails')
            .failedItems(<Object?>['abc', 1], context()),
        postgres ? <int>[0, 1] : <int>[0],
      );
      expect(
        await const Unique(
          'rule_emails',
          column: 'id',
        ).failedItems(<Object?>['abc', 1], context()),
        <int>[0, 1], // Postgres can not compare, the others find id 1
      );
      // too big for an int column (Postgres 22003)
      expect(
        await const Exists(
          'rule_emails',
          column: 'n',
        ).checkAsync(99999999999, context()),
        isFalse,
      );
    });

    test('an ignore value that does not fit the column is dropped', () async {
      // `/members/abc`: the id param is not a number
      RuleContext withParam = RuleContext(
        state: ParseState(
          root: <String, dynamic>{},
          params: <String, String>{'id': 'abc'},
        ),
        path: const <Object>['email'],
      );
      Unique rule = const Unique(
        'rule_emails',
        column: 'email',
        ignoreParam: 'id',
      );
      expect(await rule.checkAsync('taken@dox.dev', withParam), isFalse);
      expect(await rule.checkAsync('new@dox.dev', withParam), isTrue);
      expect(
        await rule.failedItems(<Object?>[
          'new@dox.dev',
          'taken@dox.dev',
        ], withParam),
        <int>[0, 1],
      );
      expect(
        (await v
                .string()
                .unique('rule_emails', column: 'email', ignore: 'abc')
                .safeParseAsync('taken@dox.dev'))
            .success,
        isFalse,
      );
      // an ignore value that fits still skips its row
      expect(
        (await v
                .string()
                .unique('rule_emails', column: 'email', ignore: 1)
                .safeParseAsync('taken@dox.dev'))
            .success,
        isTrue,
      );
    });

    test('text with a NUL byte is not found', () async {
      expect(
        (await v
                .string()
                .exists('rule_emails', column: 'email')
                .safeParseAsync('a\u0000b'))
            .success,
        isFalse,
      );
      expect(
        (await v
                .string()
                .unique('rule_emails', column: 'email')
                .safeParseAsync('a\u0000b'))
            .success,
        isTrue,
      );
    });

    test('a long list is one query', () async {
      List<String> many = <String>[
        for (int i = 0; i < 499; i++) 'new$i@dox.dev',
      ]..insert(250, 'taken@dox.dev');
      CountingFinder finder = CountingFinder();
      expect(
        await Unique(
          'rule_emails',
          column: 'email',
          finder: finder,
        ).failedItems(many, context()),
        hasLength(500),
      );
      List<int> missing = await Exists(
        'rule_emails',
        column: 'email',
        finder: finder,
      ).failedItems(many, context());
      expect(missing, hasLength(499));
      expect(missing.contains(250), isFalse);
      expect(
        await Exists(
          'rule_emails',
          column: 'email',
          finder: finder,
        ).failedItems(List<String>.filled(500, 'taken@dox.dev'), context()),
        <int>[],
      );
      // a bad value for a number id in a long list (Postgres)
      List<Object?> ids = <Object?>[for (int i = 1; i <= 499; i++) i]
        ..insert(300, 'abc');
      List<int> idsMissing = await Exists(
        'rule_emails',
        finder: finder,
      ).failedItems(ids, context());
      // Postgres can not compare `abc` with a number: every item fails.
      // The others find the row with id 1.
      bool postgres = Platform.environment['DRIVER'] == 'postgres';
      expect(idsMissing, hasLength(postgres ? 500 : 499));
      expect(idsMissing.contains(300), isTrue);
      expect(finder.calls, 4);
    });

    test('a bad date for a date column is not found', () async {
      await Schema().create('rule_days', (Table table) {
        table.id();
        table.date('day');
      });
      try {
        await QueryBuilder.table('rule_days')
            .insert(<String, dynamic>{'day': '2024-01-31'});
        for (String value in <String>['abc', '2020-13-45']) {
          expect(
            await const Exists(
              'rule_days',
              column: 'day',
            ).checkAsync(value, context()),
            isFalse,
            reason: value,
          );
        }
      } finally {
        await Schema().dropIfExists('rule_days');
      }
    });

    test('a bad value in a transaction does not break it', () async {
      int count = await QueryBuilder.transaction(() async {
        expect(
          await const Exists('rule_emails').checkAsync('abc', context()),
          isFalse,
        );
        expect(
          await const Unique(
            'rule_emails',
            column: 'email',
            ignoreParam: 'id',
          ).checkAsync(
            'taken@dox.dev',
            RuleContext(
              state: ParseState(
                root: <String, dynamic>{},
                params: <String, String>{'id': 'abc'},
              ),
              path: const <Object>['email'],
            ),
          ),
          isFalse,
        );
        // a list with a bad value too
        expect(
          await const Exists('rule_emails')
              .failedItems(<Object?>['abc', 1], context()),
          isNotEmpty,
        );
        // the next query of the app still works
        await QueryBuilder.table('rule_emails')
            .insert(<String, dynamic>{'email': 'in-tx@dox.dev'});
        return QueryBuilder.table('rule_emails').count();
      });
      expect(count, 2);
      expect(await QueryBuilder.table('rule_emails').count(), 2);
    });

    test('a caught error does not leave its savepoint open', () async {
      Object? releaseError;
      try {
        await QueryBuilder.transaction(() async {
          try {
            await QueryBuilder.transaction(() async {
              throw StateError('undo this');
            });
          } on StateError {
            // caught, like RowFinder does
          }
          try {
            // sp_1 must be gone: ROLLBACK TO is followed by RELEASE
            await QueryBuilder.query('RELEASE SAVEPOINT sp_1');
          } catch (error) {
            releaseError = error;
          }
        });
      } catch (_) {
        // Postgres may end the transaction after the failed RELEASE
      }
      expect(releaseError, isNotNull);
    });

    test('a dotted column name reads the right key', () async {
      Exists exists = const Exists('rule_emails', column: 'rule_emails.email');
      expect(
        await exists.failedItems(<Object?>[
          'taken@dox.dev',
          'nope@dox.dev',
        ], context()),
        <int>[1],
      );
      // before, the found text was `null`, so the item `null` passed
      expect(await exists.failedItems(<Object?>['null'], context()), <int>[0]);
      expect(await exists.checkAsync('taken@dox.dev', context()), isTrue);
      Unique unique = const Unique('rule_emails', column: 'rule_emails.email');
      expect(
        await unique.failedItems(<Object?>['new@dox.dev'], context()),
        <int>[],
      );
      expect(
        await unique.failedItems(<Object?>[
          'new@dox.dev',
          'taken@dox.dev',
        ], context()),
        <int>[0, 1],
      );
      expect(await unique.checkAsync('taken@dox.dev', context()), isFalse);
    });

    test('values are bound, not put into the SQL', () async {
      expect(
        await const Exists(
          'rule_emails',
          column: 'email',
        ).checkAsync("x' OR '1'='1", context()),
        isFalse,
      );
      expect(await QueryBuilder.table('rule_emails').count(), 1);
    });

    test('names the ORM allows still work, unsafe names throw', () async {
      // a name that starts with a digit worked before, it still does
      await Schema().create('2fa_codes', (Table table) {
        table.id();
        table.string('code');
      });
      try {
        expect(
          await const Unique(
            '2fa_codes',
            column: 'code',
          ).checkAsync('x', context()),
          isTrue,
        );
      } finally {
        await Schema().dropIfExists('2fa_codes');
      }
      await expectLater(
        const RowFinder().found('rule_emails; DROP TABLE x', 'email', <Object?>[
          'a',
        ]),
        throwsA(anything),
      );
      expect(await QueryBuilder.table('rule_emails').count(), 1);
    });
  });
}
