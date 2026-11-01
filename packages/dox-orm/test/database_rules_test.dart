import 'package:dox_orm/dox_orm.dart';
import 'package:dox_validation/dox_validation.dart' hide Schema;
import 'package:test/test.dart';

import 'connection.dart';

/// `@Unique`, `@Exists` and the fluent `unique()` / `exists()` on every
/// database. Run with DRIVER=sqlite, postgres or mysql.
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
        expect(
          await const Exists(
            'rule_emails',
            column: 'email',
          ).checkAsync(value, context()),
          inDb,
          reason: '@Exists $value',
        );
        ParseResult<String> fluent = await v
            .string()
            .unique('rule_emails', column: 'email')
            .safeParseAsync(value);
        expect(fluent.success, !inDb, reason: 'unique() $value');
      }
    });

    test('a list: the database match decides for each item', () async {
      List<String> values = <String>[
        'new@dox.dev',
        'TAKEN@dox.dev',
        'taken@dox.dev',
      ];
      List<int> inDb = <int>[];
      for (int i = 0; i < values.length; i++) {
        int count = await QueryBuilder.table('rule_emails')
            .where('email', values[i])
            .count();
        if (count > 0) inDb.add(i);
      }
      expect(
        await const Unique(
          'rule_emails',
          column: 'email',
        ).failedItems(values, context()),
        inDb,
      );
      expect(
        await const Exists(
          'rule_emails',
          column: 'email',
        ).failedItems(values, context()),
        <int>[
          for (int i = 0; i < values.length; i++)
            if (!inDb.contains(i)) i,
        ],
      );
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
      expect(
        await const Exists('rule_emails')
            .failedItems(<Object?>['abc', 1], context()),
        <int>[0],
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
