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
        <int>[1],
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

    test('a long list needs a few queries, not one per item', () async {
      List<String> many = <String>[
        for (int i = 0; i < 499; i++) 'new$i@dox.dev',
      ]..insert(250, 'TAKEN@dox.dev');
      bool inDb =
          (await QueryBuilder.table('rule_emails')
              .where('email', 'TAKEN@dox.dev')
              .count()) >
          0;
      CountingFinder finder = CountingFinder();
      expect(
        await Unique(
          'rule_emails',
          column: 'email',
          finder: finder,
        ).failedItems(many, context()),
        inDb ? <int>[250] : <int>[],
      );
      expect(finder.calls, lessThanOrEqualTo(22));
      // one exact hit and 499 new items: 2 queries at most
      many[250] = 'taken@dox.dev';
      finder.calls = 0;
      expect(
        await Unique(
          'rule_emails',
          column: 'email',
          finder: finder,
        ).failedItems(many, context()),
        <int>[250],
      );
      expect(finder.calls, lessThanOrEqualTo(2));
      // a bad value for a number id in a long list (Postgres)
      List<Object?> ids = <Object?>[for (int i = 1; i <= 499; i++) i]
        ..insert(300, 'abc');
      finder.calls = 0;
      List<int> missing = await Exists(
        'rule_emails',
        finder: finder,
      ).failedItems(ids, context());
      expect(missing.contains(0), isFalse); // the row with id 1
      expect(missing.contains(300), isTrue);
      expect(missing, hasLength(499));
      expect(finder.calls, lessThanOrEqualTo(40));
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
        // the next query of the app still works
        await QueryBuilder.table('rule_emails')
            .insert(<String, dynamic>{'email': 'in-tx@dox.dev'});
        return QueryBuilder.table('rule_emails').count();
      });
      expect(count, 2);
      expect(await QueryBuilder.table('rule_emails').count(), 2);
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
