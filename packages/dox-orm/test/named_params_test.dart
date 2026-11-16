import 'package:dox_orm/dox_orm.dart';
import 'package:dox_orm/src/drivers/db_driver.dart' show debugQuestionSqlCached;
import 'package:dox_orm/src/drivers/sqlite_driver.dart' show SqliteSchema;
import 'package:test/test.dart';

Object? _same(dynamic v) => v;

void main() {
  Map<String, dynamic> values = <String, dynamic>{'a': 1, 'b': 2};

  /// the sql, then the params
  List<Object?> run(String sql, {bool mysql = false}) {
    var (String out, List<Object?> params) = toPositionalParams(
      sql,
      values,
      _same,
      mysql: mysql,
    );
    return <Object?>[out, ...params];
  }

  group('@name to ? |', () {
    test('replaces names in order', () {
      expect(run('x = @b AND y = @a'), <Object?>['x = ? AND y = ?', 2, 1]);
    });

    test('skips strings, quoted names and comments', () {
      expect(
        run("x = '@a' AND \"@a\" = `@a` AND y = @b /* @a */ -- @a\nOR @a"),
        <Object?>[
          "x = '@a' AND \"@a\" = `@a` AND y = ? /* @a */ -- @a\nOR ?",
          2,
          1,
        ],
      );
    });

    test("'' stays inside the string", () {
      expect(run("x = 'it''s @a' AND y = @b"), <Object?>[
        "x = 'it''s @a' AND y = ?",
        2,
      ]);
    });

    test('sqlite: a backslash does not escape the quote', () {
      expect(run(r"x = 'c:\' AND y = @a"), <Object?>[
        r"x = 'c:\' AND y = ?",
        1,
      ]);
    });

    test('mysql: a backslash escapes the quote, # is a comment', () {
      expect(run(r"x = 'it\'s @a' AND y = @b # @a", mysql: true), <Object?>[
        r"x = 'it\'s @a' AND y = ? # @a",
        2,
      ]);
    });

    test('mysql: /*! */ and /*M! */ run, so their @name is found', () {
      expect(
        run('x = 1 /*!50100 AND y = @a */ /*M! AND z = @b */', mysql: true),
        <Object?>['x = 1 /*!50100 AND y = ? */ /*M! AND z = ? */', 1, 2],
      );
      // not mysql: a normal comment
      expect(run('x = @b /*! @a */'), <Object?>['x = ? /*! @a */', 2]);
    });

    test('mysql: -- with no space is not a comment', () {
      expect(run('x = 1--@a', mysql: true), <Object?>['x = 1--?', 1]);
    });

    test('unknown names are kept', () {
      expect(run('x = @a AND y = @@sql_mode AND z = @nope'), <Object?>[
        'x = ? AND y = @@sql_mode AND z = @nope',
        1,
      ]);
    });
  });

  group('sql caches skip long sql', () {
    test('? sql cache', () {
      String short = 'SELECT * FROM t WHERE a = @a';
      String long = '$short /* ${'x' * 5000} */';
      for (bool mysql in <bool>[false, true]) {
        var (String out, List<Object?> params) = toPositionalParams(
          long,
          values,
          _same,
          mysql: mysql,
        );
        expect(out, startsWith('SELECT * FROM t WHERE a = ?'));
        expect(params, <Object?>[1]);
        toPositionalParams(short, values, _same, mysql: mysql);
        expect(debugQuestionSqlCached(long, mysql), isFalse);
        expect(debugQuestionSqlCached(short, mysql), isTrue);
      }
    });

    test('sqlite kinds cache', () {
      SqliteSchema schema = SqliteSchema();
      String short = 'SELECT 1';
      String long = 'SELECT 1 /* ${'x' * 5000} */';
      expect(schema.kindsFor(long), isEmpty);
      expect(schema.kindsFor(short), isEmpty);
      expect(schema.debugCached(long), isFalse);
      expect(schema.debugCached(short), isTrue);
    });
  });
}
