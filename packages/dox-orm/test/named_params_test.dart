import 'package:dox_orm/dox_orm.dart';
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
}
