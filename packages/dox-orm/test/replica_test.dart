import 'package:dox_orm/dox_orm.dart';
import 'package:test/test.dart';

import 'connection.dart';
import 'models/blog/blog.model.dart';

/// a driver that runs every query on [inner] and keeps its sql, so a test
/// can see which host got a query
class CountingDriver extends DBDriver {
  CountingDriver(this.inner);

  final DBDriver inner;
  final List<String> sqls = <String>[];

  @override
  Driver getName() => inner.getName();

  @override
  bool get supportsReturning => inner.supportsReturning;

  @override
  Object? columnValue(dynamic value) => inner.columnValue(value);

  @override
  Future<List<Map<String, dynamic>>> query(
    String query, {
    String? primaryKey,
    Map<String, dynamic>? substitutionValues,
  }) {
    sqls.add(query);
    return inner.query(
      query,
      primaryKey: primaryKey,
      substitutionValues: substitutionValues,
    );
  }

  @override
  Stream<List<Map<String, dynamic>>> stream(
    String query, {
    Map<String, dynamic>? substitutionValues,
    int chunkSize = 1000,
  }) {
    sqls.add(query);
    return inner.stream(
      query,
      substitutionValues: substitutionValues,
      chunkSize: chunkSize,
    );
  }

  @override
  Future<void> execute(
    String query, {
    Map<String, dynamic>? substitutionValues,
  }) {
    sqls.add(query);
    return inner.execute(query, substitutionValues: substitutionValues);
  }

  @override
  Future<int> affectingStatement(
    String query, {
    Map<String, dynamic>? substitutionValues,
  }) {
    sqls.add(query);
    return inner.affectingStatement(
      query,
      substitutionValues: substitutionValues,
    );
  }

  @override
  Future<R> transaction<R>(Future<R> Function() callback) {
    sqls.add('BEGIN');
    return inner.transaction(callback);
  }

  @override
  bool get hasOpenTransaction => inner.hasOpenTransaction;

  @override
  Future<void> afterCommit(AfterCommitCallback callback) =>
      inner.afterCommit(callback);
}

void main() async {
  await initQueryBuilder();
  DBDriver real = SqlQueryBuilder().dbDriver;
  late CountingDriver w;
  late CountingDriver r1;
  late CountingDriver r2;
  late ReplicaDriver replica;

  /// the counts of: writer, reader 1, reader 2. then it clears them.
  List<int> counts() {
    List<int> c = <int>[w.sqls.length, r1.sqls.length, r2.sqls.length];
    for (CountingDriver d in <CountingDriver>[w, r1, r2]) {
      d.sqls.clear();
    }
    return c;
  }

  void useReplica({bool sticky = false}) {
    w = CountingDriver(real);
    r1 = CountingDriver(real);
    r2 = CountingDriver(real);
    replica = ReplicaDriver(
      writer: w,
      readers: <DBDriver>[r1, r2],
      sticky: sticky,
    );
    SqlQueryBuilder().dbDriver = replica;
  }

  QueryBuilder<Map<String, dynamic>> item() => QueryBuilder.table('rep_item');

  setUp(() async {
    SqlQueryBuilder().dbDriver = real;
    await Schema().dropIfExists('rep_item');
    await Schema().create('rep_item', (Table table) {
      table.id();
      table.string('name');
    });
    await item().insert(<String, dynamic>{'name': 'a'});
  });

  tearDown(() async {
    SqlQueryBuilder().dbDriver = real;
    await Schema().dropIfExists('rep_item');
  });

  group('routing |', () {
    test('selects go to the readers in turn', () async {
      useReplica();
      await item().get();
      expect(counts(), <int>[0, 1, 0]);
      await item().where('name', 'a').first();
      expect(counts(), <int>[0, 0, 1]);
      await item().count();
      expect(counts(), <int>[0, 1, 0]);
      await QueryBuilder.query('SELECT 1 AS n');
      expect(counts(), <int>[0, 0, 1]);
    });

    test('writes go to the writer', () async {
      useReplica();
      // MySQL reads the new row back, on the writer too
      Map<String, dynamic> row = await item().insert(<String, dynamic>{
        'name': 'b',
      });
      expect(row['name'], 'b');
      await item().where('name', 'b').update(<String, dynamic>{'name': 'c'});
      await item().where('name', 'c').delete();
      await QueryBuilder.query(
        'UPDATE rep_item SET name = @n WHERE id = 0',
        substitutionValues: <String, dynamic>{'n': 'x'},
      );
      List<int> c = counts();
      expect(c[0], real.supportsReturning ? 4 : 5);
      expect(c.sublist(1), <int>[0, 0]);
    });

    test('schema changes and schema reads go to the writer', () async {
      useReplica();
      await Schema().create('rep_other', (Table table) {
        table.id();
      });
      expect(await Schema().hasTable('rep_other'), isTrue);
      await Schema().drop('rep_other');
      List<int> c = counts();
      expect(c[0], greaterThan(0));
      expect(c.sublist(1), <int>[0, 0]);
    });

    test('every query of a transaction goes to the writer', () async {
      useReplica();
      await QueryBuilder.transaction(() async {
        await item().insert(<String, dynamic>{'name': 'b'});
        expect(await item().count(), 2);
        expect(await item().cursor().length, 2);
      });
      List<int> c = counts();
      expect(c[0], real.supportsReturning ? 4 : 5);
      expect(c.sublist(1), <int>[0, 0]);
    });

    test('afterCommit waits for the commit of the writer', () async {
      useReplica();
      List<String> log = <String>[];
      await QueryBuilder.transaction(() async {
        await QueryBuilder.afterCommit(() => log.add('after'));
        log.add('inside');
      });
      expect(log, <String>['inside', 'after']);
    });

    test('a lock or SELECT INTO goes to the writer', () {
      for (String sql in <String>[
        'SELECT * FROM t FOR UPDATE',
        'SELECT * FROM t FOR SHARE',
        'select * from t for no key update',
        'SELECT * FROM t LOCK IN SHARE MODE',
        'SELECT * INTO t2 FROM t',
        'INSERT INTO t VALUES (1)',
        'WITH x AS (DELETE FROM t RETURNING *) SELECT * FROM x',
        'update t set a = 1',
      ]) {
        expect(ReplicaDriver.isReadQuery(sql), isFalse, reason: sql);
      }
      for (String sql in <String>[
        'SELECT * FROM t',
        '  select 1',
        '(SELECT a FROM t) UNION (SELECT a FROM u)',
      ]) {
        expect(ReplicaDriver.isReadQuery(sql), isTrue, reason: sql);
      }
    });

    test('lockForUpdate() goes to the writer', () async {
      useReplica();
      await QueryBuilder.transaction(() async {
        await item().lockForUpdate().get();
      });
      await item().lockForUpdate().get();
      List<int> c = counts();
      // SQLite has no lock sql: outside a transaction it is a plain read
      expect(
        c,
        real.getName() == Driver.sqlite ? <int>[2, 1, 0] : <int>[3, 0, 0],
      );
    });

    test('onWriteConnection() sends reads to the writer', () async {
      useReplica();
      await item().onWriteConnection().get();
      await item().onWriteConnection().count();
      expect(counts(), <int>[2, 0, 0]);
    });

    test('cursor() and lazy() read from a reader', () async {
      useReplica();
      expect(await item().cursor().length, 1);
      expect(await item().lazy().length, 1);
      expect(counts(), <int>[0, 1, 1]);
    });

    test('models read from a reader and save on the writer', () async {
      await Schema().dropIfExists('blog');
      await Schema().dropIfExists('blog_info');
      await Schema().create('blog', (Table table) {
        table.id('uid');
        table.string('title');
        table.string('status').withDefault('active');
        table.text('body');
        table.string('slug').nullable();
        table.softDeletes();
        table.timestamps();
      });
      await Schema().create('blog_info', (Table table) {
        table.id();
        table.json('info');
        table.integer('blog_id');
        table.timestamps();
      });
      addTearDown(() async {
        SqlQueryBuilder().dbDriver = real;
        await Schema().dropIfExists('blog');
        await Schema().dropIfExists('blog_info');
      });
      useReplica();
      Blog blog = await Blog().create(<String, dynamic>{
        'title': 't',
        'body': 'b',
      });
      // the insert (and the read back on MySQL). the eager relations are
      // then read from a reader.
      expect(counts()[0], real.supportsReturning ? 1 : 2);

      Blog? found = await Blog().find(blog.uid);
      expect(found?.title, 't');
      expect(counts()[0], 0);
    });
  });

  group('sticky |', () {
    test('after a write, reads of the scope go to the writer', () async {
      useReplica(sticky: true);
      await ReplicaDriver.stickyScope(() async {
        await item().get();
        expect(counts(), <int>[0, 1, 0]);
        await item().insert(<String, dynamic>{'name': 'b'});
        await item().get();
        await item().count();
        expect(counts(), <int>[real.supportsReturning ? 3 : 4, 0, 0]);
      });

      /// a new scope, or no scope, reads from the readers again
      await ReplicaDriver.stickyScope(() async {
        await item().get();
      });
      await item().insert(<String, dynamic>{'name': 'c'});
      await item().get();
      expect(counts(), <int>[real.supportsReturning ? 1 : 2, 1, 1]);
    });

    test('without sticky, reads after a write go to the readers', () async {
      useReplica();
      await ReplicaDriver.stickyScope(() async {
        await item().insert(<String, dynamic>{'name': 'b'});
        await item().get();
      });
      expect(counts(), <int>[real.supportsReturning ? 1 : 2, 1, 0]);
    });
  });

  group('config |', () {
    test('read and write hosts make a ReplicaDriver', () {
      List<ConnectionConfig> made = <ConnectionConfig>[];
      DBDriver factory(ConnectionConfig c) {
        made.add(c);
        return CountingDriver(real);
      }

      ConnectionConfig config = ConnectionConfig(
        driver: Driver.postgres,
        host: 'primary',
        user: 'app',
        password: 'secret',
        database: 'app',
        debug: false,
        extra: <String, dynamic>{'maxConnectionCount': 5, 'a': 1},
        driverFactory: factory,
        write: <String, dynamic>{'port': 6432},
        read: <Map<String, dynamic>>[
          <String, dynamic>{'host': 'replica-1'},
          <String, dynamic>{
            'host': 'replica-2',
            'user': 'reader',
            'extra': <String, dynamic>{'maxConnectionCount': 20},
          },
        ],
        sticky: true,
      );
      DBDriver driver = config.createDriver();
      expect(driver, isA<ReplicaDriver>());
      ReplicaDriver r = driver as ReplicaDriver;
      expect(r.readers.length, 2);
      expect(r.sticky, isTrue);

      expect(made.map((ConnectionConfig c) => c.host), <String>[
        'primary',
        'replica-1',
        'replica-2',
      ]);
      expect(made[0].port, 6432);
      expect(made[1].port, 0);
      expect(made[1].user, 'app');
      expect(made[2].user, 'reader');
      expect(made[2].password, 'secret');
      expect(made[2].extra, <String, dynamic>{
        'maxConnectionCount': 20,
        'a': 1,
      });
      expect(made.every((ConnectionConfig c) => c.read == null), isTrue);
    });

    test('no read hosts: a plain driver', () {
      ConnectionConfig config = ConnectionConfig(
        driver: Driver.sqlite,
        database: ':memory:',
        debug: false,
        read: <Map<String, dynamic>>[],
      );
      DBDriver driver = config.createDriver();
      addTearDown(driver.close);
      expect(driver, isNot(isA<ReplicaDriver>()));
    });

    test('a wrong host key throws', () {
      ConnectionConfig config = ConnectionConfig(
        driver: Driver.sqlite,
        database: ':memory:',
        debug: false,
        read: <Map<String, dynamic>>[
          <String, dynamic>{'hots': 'x'},
        ],
      );
      expect(config.createDriver, throwsArgumentError);
    });
  });

  test('real hosts: write on the primary, read on the replica', () async {
    ConnectionConfig base = databaseConfig.getConnectionConfig();
    ConnectionConfig config = ConnectionConfig(
      driver: base.driver,
      host: base.host,
      port: base.port,
      user: base.user,
      password: base.password,
      database: base.database,
      debug: false,
      extra: base.extra,
      // the same database, by another name: a pool of its own
      read: <Map<String, dynamic>>[
        <String, dynamic>{'host': '127.0.0.1'},
      ],
    );
    ReplicaDriver driver = config.createDriver() as ReplicaDriver;
    addTearDown(driver.close);
    expect(driver.writer, isNot(same(driver.readers.single)));
    expect(
      driver.readers.single,
      base.driver == Driver.postgres
          ? isA<PostgresNativeDriver>()
          : isA<MysqlNativeDriver>(),
    );
    SqlQueryBuilder().dbDriver = driver;
    await item().insert(<String, dynamic>{'name': 'real'});
    expect(await item().where('name', 'real').count(), 1);
    await QueryBuilder.transaction(() async {
      await item().where('name', 'real').delete();
      expect(await item().where('name', 'real').count(), 0);
    });
    expect(await item().where('name', 'real').count(), 0);
  }, skip: real.getName() == Driver.sqlite ? 'Postgres and MySQL only' : false);
}
