import 'dart:convert';
import 'dart:io';

import 'package:dox_core/dox_core.dart';
import 'package:dox_orm/dox_orm.dart' as orm;
import 'package:test/test.dart';

import 'dtos/member.dto.dart';

/// `@Unique` and `@Exists` on a DTO, in a real Dox app: the body of a
/// request is checked against the database. SQLite in memory.

class MemberRouter extends Router {
  @override
  void register() {
    Route.post('/members', (CreateMember body) {
      return <String, dynamic>{'email': body.email, 'tags': body.tagIds};
    });
    Route.put('/members/{id}', (int id, UpdateMember body) {
      return <String, dynamic>{'id': id, 'email': body.email};
    });
  }
}

/// does not log the errors the tests cause on purpose
class QuietExceptionHandler extends ExceptionHandler {
  const QuietExceptionHandler();

  @override
  void report(Object error, StackTrace stackTrace) {}
}

/// sends [body] as JSON and gives the status and the decoded body
Future<(int, Map<String, dynamic>)> send(
  String method,
  String path,
  Object body,
) async {
  HttpClient client = HttpClient();
  try {
    HttpClientRequest req = await client.openUrl(
      method,
      Uri.parse('http://127.0.0.1:${Dox().server.httpServer.port}$path'),
    );
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode(body));
    HttpClientResponse res = await req.close();
    String text = await utf8.decodeStream(res);
    return (res.statusCode, jsonDecode(text) as Map<String, dynamic>);
  } finally {
    client.close(force: true);
  }
}

void main() {
  setUpAll(() async {
    orm.SqlQueryBuilder().dbDriver = orm.ConnectionConfig(
      driver: orm.Driver.sqlite,
      database: ':memory:',
      debug: false,
    ).createDriver();
    await orm.Schema().create('members', (orm.Table table) {
      table.id();
      table.string('email');
      table.softDeletes();
    });
    await orm.Schema().create('teams', (orm.Table table) {
      table.id();
    });
    await orm.Schema().create('tags', (orm.Table table) {
      table.id();
    });
    await orm.QueryBuilder.table('members')
        .insert(<String, dynamic>{'email': 'taken@dox.dev'});
    await orm.QueryBuilder.table('members').insert(<String, dynamic>{
      'email': 'gone@dox.dev',
      'deleted_at': '2024-01-01 00:00:00',
    });
    await orm.QueryBuilder.table('teams').insert(<String, dynamic>{'id': 1});
    for (int id in <int>[1, 2]) {
      await orm.QueryBuilder.table('tags').insert(<String, dynamic>{'id': id});
    }
    Dox().initialize(
      AppConfig(
        appKey: '4HyiSrq4N5Nfg6bOadIhbFEI8zbUkpxt',
        // the OS picks a free port, so test files can run in parallel
        serverPort: 0,
        totalIsolate: 1,
        routers: <Router>[MemberRouter()],
        dtos: <DtoSchema<Object>>[$CreateMemberDto, $UpdateMemberDto],
        exceptionHandler: const QuietExceptionHandler(),
      ),
    );
    await Dox().startServer();
  });

  tearDownAll(() async {
    await Dox().server.close(force: true);
  });

  test('@Unique, @Exists and a list @Exists pass', () async {
    var (int status, Map<String, dynamic> body) = await send(
      'POST',
      '/members',
      <String, dynamic>{
        'email': 'new@dox.dev',
        'team_id': 1,
        'tag_ids': <int>[1, 2],
      },
    );
    expect(status, 200);
    expect(body, <String, dynamic>{
      'email': 'new@dox.dev',
      'tags': <int>[1, 2],
    });
  });

  test('@Unique, @Exists and each list item fail', () async {
    var (int status, Map<String, dynamic> body) = await send(
      'POST',
      '/members',
      <String, dynamic>{
        'email': 'taken@dox.dev',
        'team_id': 9,
        'tag_ids': <int>[1, 7, 8],
      },
    );
    expect(status, 422);
    expect(body, <String, dynamic>{
      'email': 'The email has already been taken',
      'team_id': 'The selected team_id is invalid',
      'tag_ids.1': 'The selected tag_ids is invalid',
      'tag_ids.2': 'The selected tag_ids is invalid',
    });
  });

  test('soft-deleted rows count for @Unique', () async {
    var (_, Map<String, dynamic> body) = await send(
      'POST',
      '/members',
      <String, dynamic>{'email': 'gone@dox.dev', 'team_id': 1},
    );
    expect(body, <String, dynamic>{
      'email': 'The email has already been taken',
    });
  });

  test('database rules do not run when a field rule failed', () async {
    var (_, Map<String, dynamic> body) = await send(
      'POST',
      '/members',
      <String, dynamic>{'email': 'not-an-email', 'team_id': 9},
    );
    expect(body, <String, dynamic>{'email': 'The email is not a valid email'});
  });

  test('ignoreParam skips the row being updated', () async {
    var (int own, _) = await send('PUT', '/members/1', <String, dynamic>{
      'email': 'taken@dox.dev',
    });
    expect(own, 200);
    var (int other, _) = await send('PUT', '/members/5', <String, dynamic>{
      'email': 'taken@dox.dev',
    });
    expect(other, 422);
  });
}
