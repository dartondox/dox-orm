import 'dart:async';

import 'package:dox_orm/dox_orm.dart';
import 'package:test/test.dart';

import 'connection.dart';
import 'models/blog/blog.model.dart';
import 'models/user/user.model.dart';

/// a user that only takes `name` from a map
class FillableUser extends User {
  @override
  List<String> get fillable => <String>['name'];
}

/// a user that never takes `is_admin` from a map
class GuardedUser extends User {
  @override
  List<String> get guarded => <String>['is_admin'];
}

/// a user model with the default fillable and guarded
class DefaultUser extends Model<DefaultUser> {
  int? get id => tempIdValue as int?;
  set id(int? value) => tempIdValue = value;

  String? name;
  int? isAdmin;

  @override
  String get tableName => 'users';

  @override
  List<String> get tableColumns => const <String>['id', 'name', 'is_admin'];

  @override
  DefaultUser fromMap(Map<String, dynamic> m) => DefaultUser()
    ..id = m['id'] as int?
    ..name = m['name'] as String?
    ..isAdmin = m['is_admin'] as int?;

  @override
  Map<String, dynamic> columnsToMap() => <String, dynamic>{
    'id': id,
    'name': name,
    'is_admin': isAdmin,
  };

  @override
  Map<String, dynamic> convertToMap(dynamic i) =>
      (i as DefaultUser).columnsToMap();

  @override
  bool setColumnValue(String column, dynamic value) {
    switch (column) {
      case 'name':
        if (value is! String?) return false;
        name = value;
        return true;
      case 'is_admin':
        if (value is! int?) return false;
        isAdmin = value;
        return true;
    }
    return false;
  }
}

/// the default user, but it takes `name` from a map
class DefaultFillableUser extends DefaultUser {
  @override
  List<String> get fillable => <String>['name'];
}

/// a hand-written model with no setColumnValue(), like a model made by
/// an old dox_builder
class NoSetterUser extends DefaultUser {
  @override
  bool setColumnValue(String column, dynamic value) => false;
}

void main() async {
  await initQueryBuilder();

  group('forceFill |', () {
    test('a model with no setColumnValue throws', () {
      expect(
        () => NoSetterUser().forceFill(<String, dynamic>{'name': 'a'}),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => '${e.message}',
            'message',
            contains('setColumnValue'),
          ),
        ),
      );
    });

    test('a value of the wrong type throws, a key that is not a column is '
        'skipped', () {
      expect(
        () => DefaultUser().forceFill(<String, dynamic>{'is_admin': 'yes'}),
        throwsArgumentError,
      );
      DefaultUser user = DefaultUser()
        ..forceFill(<String, dynamic>{'name': 'a', 'nope': 1});
      expect(user.name, 'a');
    });

    test('an ISO date text sets a DateTime field', () {
      Blog blog = Blog()
        ..forceFill(<String, dynamic>{
          'created_at': '2020-01-02T03:04:05.000Z',
          'title': '2020-01-02',
        });
      expect(blog.createdAt, DateTime.utc(2020, 1, 2, 3, 4, 5));
      expect(blog.title, '2020-01-02');
      expect(
        () => Blog().forceFill(<String, dynamic>{'created_at': 'not a date'}),
        throwsArgumentError,
      );
    });
  });

  group('Security', () {
    setUp(() async {
      await Schema().create('users', (Table table) {
        table.id();
        table.string('name');
        table.integer('is_admin').withDefault(0);
        table.softDeletes();
        table.timestamps();
      });
    });

    tearDown(() async {
      await Schema().dropIfExists('users');
    });

    test('column names with sql are refused', () {
      DBDriver driver = SqlQueryBuilder().dbDriver;
      expect(driver.wrap('users.name as n'), isNotEmpty);
      expect(driver.wrap(' users.* '), isNotEmpty);
      for (String bad in <String>[
        'count(*)',
        'name = (SELECT 1), is_admin = (1), name',
        'CASE WHEN (1=1) THEN id ELSE name END',
        'name; DROP TABLE users',
        'name"',
      ]) {
        expect(() => driver.wrap(bad), throwsArgumentError, reason: bad);
      }
      expect(
        () => QueryBuilder.table('users').update(<String, dynamic>{
          'name = (SELECT 1), is_admin = (1), name': 'x',
        }),
        throwsArgumentError,
      );
      expect(
        QueryBuilder.table('users').orderByRaw('count(*) desc').toSql(),
        contains('ORDER BY count(*) desc'),
      );
    });

    test('where and join operators are checked', () {
      expect(
        () => QueryBuilder.table('users').where('id', '= 0 OR 1=1 OR id =', 1),
        throwsArgumentError,
      );
      expect(
        () => QueryBuilder.table('users').join('x', 'x.id', 'OR 1=1 --', 'id'),
        throwsArgumentError,
      );
      expect(
        QueryBuilder.table('users').where('name', 'NOT LIKE', 'a%').toSql(),
        contains('NOT LIKE'),
      );
    });

    test('fillable and guarded stop mass assignment', () async {
      Map<String, dynamic> body = <String, dynamic>{'name': 'a', 'is_admin': 1};
      await FillableUser().create(body);
      await GuardedUser().create(body);
      await FillableUser().where('id', 1).update(body);
      await GuardedUser().where('id', 2).update(body);

      List<Map<String, dynamic>> rows = await QueryBuilder.table('users')
          .orderBy('id')
          .get();
      expect(rows.map((Map<String, dynamic> r) => r['is_admin']), <int>[0, 0]);

      /// a query soft delete still works when fillable is set
      await FillableUser().where('id', 1).delete();
      expect(await User().count(), 1);
    });

    test('a model is guarded by default', () async {
      expect(DefaultUser().guarded, <String>['*']);
      Map<String, dynamic> body = <String, dynamic>{
        'id': 99,
        'name': 'a',
        'is_admin': 1,
      };

      /// a map with keys throws, so no empty row is saved and no row is
      /// changed
      await QueryBuilder.table('users').insert(<String, dynamic>{'name': 'z'});
      Matcher massAssignment = throwsA(
        isA<MassAssignmentException>()
            .having(
              (MassAssignmentException e) => e.model,
              'model',
              'DefaultUser',
            )
            .having(
              (MassAssignmentException e) => '$e',
              'message',
              contains('fillable'),
            ),
      );
      await expectLater(DefaultUser().create(body), massAssignment);
      await expectLater(
        DefaultUser().where('name', 'z').update(body),
        massAssignment,
      );
      await expectLater(
        DefaultUser().firstOrCreate(<String, dynamic>{'name': 'new'}),
        massAssignment,
      );
      await expectLater(
        DefaultUser().insertMultiple(<Map<String, dynamic>>[body]),
        massAssignment,
      );
      List<Map<String, dynamic>> before = await QueryBuilder.table('users')
          .get();
      expect(before, hasLength(1));
      expect(before.first['name'], 'z');
      expect(before.first['is_admin'], 0);
      await QueryBuilder.table('users').forceDelete();

      /// an empty map is fine
      expect(
        await DefaultUser().where('name', 'z').update(<String, dynamic>{}),
        0,
      );

      /// only the fillable columns are taken, id and is_admin are not
      await DefaultFillableUser().create(body);
      List<Map<String, dynamic>> rows = await QueryBuilder.table('users').get();
      expect(rows, hasLength(1));
      expect(rows.first['name'], 'a');
      expect(rows.first['is_admin'], 0);
      expect(rows.first['id'], isNot(99));

      /// setting fields in code still works
      DefaultUser user = DefaultUser()
        ..name = 'c'
        ..isAdmin = 1;
      await user.save();
      expect(await QueryBuilder.table('users').where('is_admin', 1).count(), 1);
    });

    test('forceCreate, forceUpdate and forceFill ignore fillable', () async {
      Map<String, dynamic> body = <String, dynamic>{'name': 'a', 'is_admin': 1};

      /// the normal write still drops is_admin, and throws with no fillable
      User kept = await FillableUser().create(body);
      expect(
        await FillableUser().where('id', kept.id).update(<String, dynamic>{
          'is_admin': 1,
        }),
        0,
      );
      await expectLater(
        DefaultUser().where('name', 'a').update(body),
        throwsA(isA<MassAssignmentException>()),
      );
      expect(await QueryBuilder.table('users').where('is_admin', 1).count(), 0);

      DefaultUser created = await DefaultUser().forceCreate(body);
      expect(created.isAdmin, 1);
      expect(await DefaultUser().where('id', kept.id).forceUpdate(body), 1);
      expect(await QueryBuilder.table('users').where('is_admin', 1).count(), 2);

      /// forceFill sets a guarded field, save() writes it
      DefaultUser? user = await DefaultUser().find(kept.id);
      user!.forceFill(<String, dynamic>{'is_admin': 3, 'nope': 1});
      expect(user.isAdmin, 3);
      await user.save();
      expect((await DefaultUser().find(kept.id))!.isAdmin, 3);
    });

    test('Model.unguarded turns fillable off only inside it', () async {
      Map<String, dynamic> body = <String, dynamic>{'name': 'a', 'is_admin': 1};
      expect(Model.isUnguarded, isFalse);
      int count = await Model.unguarded(() async {
        expect(Model.isUnguarded, isTrue);
        await DefaultUser().create(body);
        await FillableUser().create(body);
        return await DefaultUser().where('name', 'a').update(<String, dynamic>{
          'is_admin': 2,
        });
      });
      expect(count, 2);
      expect(Model.isUnguarded, isFalse);
      expect(await QueryBuilder.table('users').where('is_admin', 2).count(), 2);
      await expectLater(
        DefaultUser().create(body),
        throwsA(isA<MassAssignmentException>()),
      );
    });

    test('a request at the same time keeps fillable', () async {
      Map<String, dynamic> body = <String, dynamic>{'name': 'a', 'is_admin': 1};
      Completer<void> wait = Completer<void>();
      Completer<void> started = Completer<void>();
      Future<DefaultUser> inside = Model.unguarded(() async {
        started.complete();
        await wait.future;
        return await DefaultFillableUser().create(body);
      });

      /// the unguarded callback is waiting now. a static flag would be
      /// on here, the zone is not.
      await started.future;
      expect(Model.isUnguarded, isFalse);
      DefaultUser outside = await DefaultFillableUser().create(body);
      await DefaultFillableUser().where('id', outside.id).update(body);
      wait.complete();
      DefaultUser forced = await inside;

      expect((await DefaultUser().find(outside.id))!.isAdmin, 0);
      expect((await DefaultUser().find(forced.id))!.isAdmin, 1);
    });

    test('update on a loaded model sets updated_at', () async {
      User user = await FillableUser().create(<String, dynamic>{'name': 'a'});
      DateTime old = DateTime.now().subtract(const Duration(days: 1));
      await QueryBuilder.table('users')
          .where('id', user.id)
          .update(<String, dynamic>{'updated_at': old});
      User? loaded = await FillableUser().find(user.id);
      expect(await loaded!.update(<String, dynamic>{'name': 'b'}), 1);
      expect(loaded.updatedAt!.isAfter(old), isTrue);
      User? fresh = await User().find(user.id);
      expect(fresh!.name, 'b');
      expect(fresh.updatedAt!.isAfter(old), isTrue);
    });

    test('insertOrIgnore on a model drops keys that are not allowed', () async {
      Map<String, dynamic> body = <String, dynamic>{'name': 'a', 'is_admin': 1};
      expect(
        await FillableUser().insertOrIgnore(<Map<String, dynamic>>[body, body]),
        2,
      );
      List<Map<String, dynamic>> rows = await QueryBuilder.table('users').get();
      expect(rows.map((Map<String, dynamic> r) => r['is_admin']), <int>[0, 0]);
      await expectLater(
        DefaultUser().insertOrIgnore(<Map<String, dynamic>>[body]),
        throwsA(isA<MassAssignmentException>()),
      );
      expect(await QueryBuilder.table('users').count(), 2);
    });

    test('insertMultiple on a model drops keys that are not allowed', () async {
      Map<String, dynamic> body = <String, dynamic>{'name': 'a', 'is_admin': 1};
      await FillableUser().insertMultiple(<Map<String, dynamic>>[body, body]);
      await GuardedUser().insertMultiple(<Map<String, dynamic>>[body]);

      List<Map<String, dynamic>> rows = await QueryBuilder.table('users').get();
      expect(rows.map((Map<String, dynamic> r) => r['is_admin']), <int>[
        0,
        0,
        0,
      ]);
    });

    test('a guarded column can not be set with a changed key', () async {
      /// the SQL builder trims the name, a table prefix points to the same
      /// column, and SQLite and MySQL match names without case
      for (String key in <String>[
        ' is_admin',
        'is_admin\t',
        'IS_ADMIN',
        'users.is_admin',
      ]) {
        Map<String, dynamic> body = <String, dynamic>{'name': 'b', key: 1};
        User user = await GuardedUser().create(<String, dynamic>{'name': 'a'});
        await GuardedUser().where('id', user.id).update(body);

        /// find() gives a User, so make the loaded model by hand
        await (GuardedUser()..id = user.id).update(body);
        await GuardedUser().insertMultiple(<Map<String, dynamic>>[body]);
        await GuardedUser().insertOrIgnore(<Map<String, dynamic>>[body]);
        await GuardedUser().upsert(
          <Map<String, dynamic>>[
            <String, dynamic>{'id': 1000, ...body},
          ],
          <String>['id'],
        );

        List<Map<String, dynamic>> rows = await QueryBuilder.table('users')
            .get();
        expect(rows, hasLength(4), reason: key);
        for (Map<String, dynamic> row in rows) {
          expect(row['name'], 'b', reason: key);
          expect(row['is_admin'], 0, reason: key);
        }
        await QueryBuilder.table('users').forceDelete();
      }
    });

    test('a fillable key must match the name exactly', () async {
      User user = await FillableUser().create(<String, dynamic>{'name': 'a'});
      await FillableUser().where('id', user.id).update(<String, dynamic>{
        'name': 'b',
        'NAME': 'c',
        ' name': 'd',
        'IS_ADMIN': 1,
        'users.is_admin': 1,
      });
      Map<String, dynamic> row = (await QueryBuilder.table(
        'users',
      ).get()).single;
      expect(row['name'], 'b');
      expect(row['is_admin'], 0);
    });

    test('tls modes', () {
      ConnectionConfig pg = ConnectionConfig.fromUrl(
        'postgres://u:p@db.example.com/app?sslmode=verify-full',
      );
      expect(pg.postgresSslMode, 'verify-full');
      expect(
        ConnectionConfig.fromUrl(
          'postgres://u:p@db.example.com/app?sslmode=verify-ca',
        ).postgresSslMode,
        'verify-ca',
      );

      /// like libpq: require encrypts but does not check the certificate,
      /// so Heroku style urls keep working
      expect(
        ConnectionConfig.fromUrl(
          'postgres://u:p@db.example.com/app?sslmode=require',
        ).postgresSslMode,
        'require',
      );
      expect(
        ConnectionConfig(
          driver: Driver.postgres,
          database: 'app',
          useSSL: true,
          debug: false,
        ).postgresSslMode,
        'require',
      );
      expect(
        ConnectionConfig(
          driver: Driver.postgres,
          database: 'app',
          useSSL: true,
          extra: <String, dynamic>{'sslMode': 'verify-full'},
          debug: false,
        ).postgresSslMode,
        'verify-full',
      );
      expect(
        ConnectionConfig.fromUrl('postgres://u:p@h/app').postgresSslMode,
        'disable',
      );

      /// mysql checks the certificate unless verifyCertificate=false
      ConnectionConfig dev = ConnectionConfig.fromUrl(
        'mysql://u:p@db.example.com/app?ssl=true&verifyCertificate=false',
      );
      expect(dev.useSSL, true);
      expect(dev.verifyCertificate, false);
      expect(pg.verifyCertificate, true);
    });

    test('postgres ca file', () {
      ConnectionConfig url = ConnectionConfig.fromUrl(
        'postgres://u:p@db.example.com/app?sslmode=verify-full'
        '&sslrootcert=%2Fetc%2Fssl%2Frds-ca.pem',
      );
      expect(url.postgresSslRootCert, '/etc/ssl/rds-ca.pem');
      expect(url.extra.containsKey('sslrootcert'), false);
      expect(
        ConnectionConfig(
          driver: Driver.postgres,
          database: 'app',
          extra: <String, dynamic>{'sslRootCert': 'certs/ca.pem'},
          debug: false,
        ).postgresSslRootCert,
        'certs/ca.pem',
      );
      expect(
        ConnectionConfig.fromUrl('postgres://u:p@h/app').postgresSslRootCert,
        null,
      );
    });
  });
}
