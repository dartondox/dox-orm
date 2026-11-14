import 'dart:io';

import 'package:dox_migration/src/utils/env.dart';
import 'package:test/test.dart';

void main() {
  group('loadEnv', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('dox_migration_env_');
    });

    tearDown(() => dir.deleteSync(recursive: true));

    test('real env wins over .env, .env fills the rest', () {
      File('${dir.path}/.env').writeAsStringSync(
        'DB_HOST=from-file\nDB_PORT=5432\nDB_NAME="dox"\n'
        'DATABASE_URL=postgres://u:p@h/d?sslmode=disable\n',
      );
      Map<String, String> env = loadEnv(
        environment: <String, String>{'DB_HOST': 'from-env'},
        dir: dir.path,
      );
      expect(env['DB_HOST'], 'from-env');
      expect(env['DB_PORT'], '5432');
      expect(env['DB_NAME'], 'dox');
      // a second `=` is kept
      expect(env['DATABASE_URL'], 'postgres://u:p@h/d?sslmode=disable');
    });

    test('no .env file: the real env only', () {
      Map<String, String> env = loadEnv(
        environment: <String, String>{'DB_HOST': 'h'},
        dir: dir.path,
      );
      expect(env, <String, String>{'DB_HOST': 'h'});
    });

    Map<String, String> read(String text, [Map<String, String>? shell]) {
      File('${dir.path}/.env').writeAsStringSync(text);
      return loadEnv(environment: shell ?? <String, String>{}, dir: dir.path);
    }

    test('a comment after a space or tab is not part of the value', () {
      Map<String, String> env = read(
        'APP_ENV=production # live\n'
        'DB_HOST=db.example.com\t# prod db\n'
        'COLOR=#fff\n'
        'TAG=abc#def\n'
        'EMPTY= # nothing here\n',
      );
      expect(env['APP_ENV'], 'production');
      expect(env['DB_HOST'], 'db.example.com');
      expect(env['COLOR'], '#fff');
      expect(env['TAG'], 'abc#def');
      // only a comment: empty, so missing
      expect(env.containsKey('EMPTY'), isFalse);
    });

    test('export prefix and spaces around =', () {
      Map<String, String> env = read(
        'export APP_ENV=production\n'
        'export  DB_HOST = h1\n'
        '  DB_PORT =  5432  \n',
      );
      expect(env['APP_ENV'], 'production');
      expect(env['DB_HOST'], 'h1');
      expect(env['DB_PORT'], '5432');
    });

    test('only one pair of surrounding quotes is removed', () {
      Map<String, String> env = read(
        'DB_PASSWORD=it\'s"q\n'
        'A="a # b"\n'
        "B='say \"hi\"' # note\n"
        'C=`x`\n'
        'D="no end\n'
        'E="x"y"\n',
      );
      expect(env['DB_PASSWORD'], 'it\'s"q');
      expect(env['A'], 'a # b');
      expect(env['B'], 'say "hi"');
      expect(env['C'], 'x');
      expect(env['D'], '"no end');
      expect(env['E'], 'x');
    });

    test('CRLF, BOM, blank and comment lines, last key wins', () {
      Map<String, String> env = read(
        '﻿DB_HOST=a\r\n'
        '\r\n'
        '# DB_PORT=1\r\n'
        '   # DB_NAME=x\r\n'
        'DB_HOST=b\r\n'
        'not a pair\r\n',
      );
      expect(env, <String, String>{'DB_HOST': 'b'});
    });

    test('a real environment variable wins over the parsed value', () {
      Map<String, String> env = read(
        'APP_ENV=production # live\n',
        <String, String>{'APP_ENV': 'development'},
      );
      expect(env['APP_ENV'], 'development');
    });

    test('empty and null values count as missing', () {
      File('${dir.path}/.env').writeAsStringSync('DB_HOST=\nDB_PORT=null\n');
      Map<String, String> env = loadEnv(
        environment: <String, String>{'DB_USERNAME': ' '},
        dir: dir.path,
      );
      expect(env, isEmpty);
    });
  });
}
