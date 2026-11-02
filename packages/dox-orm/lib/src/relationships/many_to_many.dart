import 'package:dox_orm/dox_orm.dart';

import 'keys.dart';
import 'pivot_ids.dart';

/// local key used by each query, so the result can be matched to owners
final Expando<String> _localKeys = Expando<String>();

/// many to many relationship query
M? manyToMany<T, M>(
  List<Model<T>> list,
  Model<M> Function() model, {
  dynamic onQuery,
  String? localKey,
  String? relatedKey,
  String? pivotForeignKey,
  String? pivotRelatedForeignKey,
  String? pivotTable,
  List<String>? withPivot,
  bool withTimestamps = false,
}) {
  if (list.isEmpty) return null;

  Model<T> local = list.first;
  Model<M> related = model();
  related.connection ??= local.connection;
  if (relationSubquery) startSubquery(related, local);

  localKey = localKey ?? local.primaryKey;
  relatedKey = relatedKey ?? related.primaryKey;

  String relatedTable = tableRef(related);

  /// the defaults use the model names, like Laravel:
  /// Artist and Song give artist_song, artist_id and song_id
  String localName = local.helper.tableNameOf(local.runtimeType);
  String relatedName = related.helper.tableNameOf(related.runtimeType);
  pivotTable = pivotTable ?? _sortTableByAlphabet(relatedName, localName);

  pivotForeignKey = pivotForeignKey ?? local.foreignKeyName;
  pivotRelatedForeignKey = pivotRelatedForeignKey ?? related.foreignKeyName;

  List<dynamic> ids = relationKeys(list, localKey);

  /// the extra pivot columns to read, see [ManyToManyWrites.pivot].
  /// with no withPivot and no withTimestamps the select is the same as
  /// before, so an `onQuery` with groupBy() keeps working.
  /// select() quotes each name.
  List<String> pivotColumns = <String>{
    ...?withPivot,
    if (withTimestamps) ...<String>['created_at', 'updated_at'],
  }.toList();
  String pivotSelect = <String>[
    for (String c in pivotColumns) ', $pivotTable.$c as $_pivotPrefix$c',
  ].join();

  QueryBuilder<M> q = related
      .debug(local.shouldDebug)
      .select(
        '$relatedTable.*, $pivotTable.$pivotForeignKey as _owner_id'
        '$pivotSelect',
      )
      .leftJoin(
        pivotTable,
        '$pivotTable.$pivotRelatedForeignKey',
        '$relatedTable.$relatedKey',
      );
  if (relationSubquery) {
    q.whereRaw(
      subqueryMatch(related, '$pivotTable.$pivotForeignKey', local, localKey),
    );
  } else {
    q.whereIn('$pivotTable.$pivotForeignKey', ids);
  }

  if (onQuery != null) {
    q = onQuery(q);
  }
  _localKeys[q] = localKey;
  manyToManyQuery[q] = _Pivot(
    owner: local,
    ownerKey: localKey,
    relatedKey: relatedKey,
    table: pivotTable,
    foreignKey: pivotForeignKey,
    relatedForeignKey: pivotRelatedForeignKey,
    withTimestamps: withTimestamps,
  );
  return q as M;
}

/// sort two names alphabetically
/// blog and category , blog_category
/// song and artist, artist_song
String _sortTableByAlphabet(String firstTable, String secondTable) {
  List<String> tables = <String>[firstTable, secondTable];
  tables.sort();
  return '${tables[0]}_${tables[1]}';
}

/// get result of many to many relationship query
/// the result is keyed by each owner primary key (tempIdValue).
Future<Map<String, List<M>>> getManyToMany<T, M>(
  dynamic q,
  List<Model<T>> list,
) async {
  if (q == null) return <String, List<M>>{}; // coverage:ignore-line
  List<M> results = await q.get();

  Map<String, List<M>> ret = <String, List<M>>{};

  /// filter matched values with local id value
  for (M r in results) {
    String ownerId = (r as Model<M>).originalMap['_owner_id'].toString();
    if (ret[ownerId] == null) {
      ret[ownerId] = <M>[];
    }
    ret[ownerId]?.add(r);
  }

  /// match each owner by its local key, and use an empty list
  /// instead of null when there is no result
  String? localKey = _localKeys[q];
  Map<String, List<M>> byOwner = <String, List<M>>{};
  for (Model<T> i in list) {
    dynamic key = localKey == null ? i.tempIdValue : relationKey(i, localKey);
    byOwner[i.tempIdValue.toString()] = ret[key.toString()] ?? <M>[];
  }
  return byOwner;
}

/// pivot columns are read with this prefix, like `_pivot_role`
const String _pivotPrefix = '_pivot_';

class _Pivot {
  final Model<dynamic> owner;
  final String ownerKey;
  final String relatedKey;
  final String table;
  final String foreignKey;
  final String relatedForeignKey;
  final bool withTimestamps;

  /// true when the last [records] dropped a null id or a model that is
  /// not saved
  bool skipped = false;

  _Pivot({
    required this.owner,
    required this.ownerKey,
    required this.relatedKey,
    required this.table,
    required this.foreignKey,
    required this.relatedForeignKey,
    required this.withTimestamps,
  });

  /// the key value of the owner. it must be saved first.
  dynamic get ownerValue {
    dynamic value = relationKey(owner, ownerKey);
    if (value == null) {
      throw StateError(
        'save the ${owner.runtimeType} before you change its pivot rows',
      );
    }
    return value;
  }

  /// a new query on the pivot table
  QueryBuilder<Map<String, dynamic>> newTable() {
    return QueryBuilder.table(table)
      ..connection = owner.connection
      ..debug(owner.shouldDebug)
      // a pivot table often has no id column, so the insert returns
      // this column
      ..primaryKey = foreignKey;
  }

  /// a new query on the pivot rows of the owner
  QueryBuilder<Map<String, dynamic>> query() {
    return newTable().where(foreignKey, ownerValue);
  }

  /// the pivot rows of the owner
  Future<List<Map<String, dynamic>>> rows() => query().get();

  /// the row of [rows] whose related id is [id] by value, see [sameId].
  /// A row that is not in [used] wins, and of those a row with the same
  /// text (`1` and `'1'`) wins. So on a text key `[1, '01']` finds the rows
  /// `'1'` and `'01'`. A row of [used] is only returned when no other row
  /// matches.
  Map<String, dynamic>? match(
    List<Map<String, dynamic>> rows,
    dynamic id,
    Set<Map<String, dynamic>> used,
  ) {
    Map<String, dynamic>? near;
    Map<String, dynamic>? found;
    for (Map<String, dynamic> r in rows) {
      dynamic stored = r[relatedForeignKey];
      if (!sameId(id, stored)) continue;
      if (used.contains(r)) {
        found ??= r;
      } else if ('$stored' == '$id') {
        /// the same text wins, so on a text key `1` finds `'1'`, not `'01'`
        return r;
      } else {
        near ??= r;
      }
    }
    return near ?? found;
  }

  /// [ids] as `id => extra pivot values`. [ids] can be one id, one
  /// model, a list of ids or models, or a map of `id => values`.
  ///
  /// Like Laravel, null means no ids, and a null id (or a model without
  /// a key) is skipped. A whole number like `2.0` becomes the int `2`,
  /// because Postgres does not take `2.0` for an integer column. Any other
  /// double (`1.5`, NaN, infinity, or past ±2^53 like `1e20`) throws an
  /// [ArgumentError]. An id with the same text (`1`, `1.0` and `'1'`) is
  /// kept once, the first one wins: it is one row on a text key and on a
  /// number key. Ids that only match by [sameId], like
  /// `1` and `'01'`, are all kept here, because on a text key they are
  /// two rows. [unique] drops them for an insert.
  Map<dynamic, Map<String, dynamic>> records(
    dynamic ids, [
    Map<String, dynamic> values = const <String, dynamic>{},
  ]) {
    Iterable<MapEntry<dynamic, dynamic>> entries;
    if (ids == null) {
      entries = const <MapEntry<dynamic, dynamic>>[];
    } else if (ids is Map) {
      entries = ids.entries;
    } else {
      List<dynamic> list = ids is Iterable ? ids.toList() : <dynamic>[ids];
      entries = <MapEntry<dynamic, dynamic>>[
        for (dynamic id in list) MapEntry<dynamic, dynamic>(id, null),
      ];
    }
    skipped = false;
    Map<dynamic, Map<String, dynamic>> out = <dynamic, Map<String, dynamic>>{};
    Set<String> texts = <String>{};
    for (MapEntry<dynamic, dynamic> e in entries) {
      dynamic id = _id(e.key);
      if (id == null) skipped = true;
      if (id == null || !texts.add('$id')) continue;
      out[id] = <String, dynamic>{
        ...values,

        /// an untyped map literal like `{1: {'role': 'x'}}` works too
        ...?(e.value as Map<dynamic, dynamic>?)?.cast<String, dynamic>(),
      };
    }
    return out;
  }

  /// [records] without an id that is the same, by [sameId], as an id
  /// before it. So `attach([1, '01'])` adds one row. The first one wins.
  Map<dynamic, Map<String, dynamic>> unique(
    Map<dynamic, Map<String, dynamic>> records,
  ) {
    Map<dynamic, Map<String, dynamic>> out = <dynamic, Map<String, dynamic>>{};
    for (MapEntry<dynamic, Map<String, dynamic>> e in records.entries) {
      // ponytail: O(n²) scan of the ids of one call, fine for normal lists
      if (!_hasSame(out.keys, e.key)) out[e.key] = e.value;
    }
    return out;
  }

  dynamic _id(dynamic id) {
    if (id is Model) id = relationKey(id, relatedKey);

    /// like main and the databases: true is 1 and false is 0
    if (id is bool) return id ? 1 : 0;
    if (id is BigInt) {
      if (id.isValidInt) return id.toInt();
      throw ArgumentError.value(id, 'ids', 'does not fit in an int');
    }
    if (id is double) {
      return intId(id) ??
          (throw ArgumentError.value(id, 'ids', 'is not a whole number id'));
    }
    if (id == null || id is int || id is String) return id;

    /// another type would be matched by its toString() on main, and not at
    /// all here, so it could lose a link
    throw ArgumentError.value(id, 'ids', 'must be an int, a String or a model');
  }

  /// adds a pivot row for each of [records]
  Future<void> insert(Map<dynamic, Map<String, dynamic>> records) async {
    if (records.isEmpty) return;
    DateTime time = now();
    dynamic ownerId = ownerValue;
    List<Map<String, dynamic>> rows = <Map<String, dynamic>>[
      for (MapEntry<dynamic, Map<String, dynamic>> e in records.entries)
        <String, dynamic>{
          if (withTimestamps) ...<String, dynamic>{
            'created_at': time,
            'updated_at': time,
          },
          ...e.value,
          foreignKey: ownerId,
          relatedForeignKey: e.key,
        },
    ];
    await newTable().insertMultiple(rows);
  }

  /// deletes the pivot rows of [ids], or all rows of the owner when
  /// [ids] is null.
  ///
  /// [keep] are the ids that must stay. On a text key they are left out
  /// by the database compare, so a column that compares without case
  /// (MySQL, MariaDB) does not delete the kept row `'ABC'` when it
  /// deletes `'abc'`.
  Future<int> delete(
    List<dynamic>? ids, {
    Iterable<dynamic> keep = const <dynamic>[],
  }) async {
    if (ids != null && ids.isEmpty) return 0;
    QueryBuilder<Map<String, dynamic>> q = query();
    if (ids != null) {
      q.whereIn(relatedForeignKey, ids);
      if (keep.isNotEmpty && ids.every(_isText)) {
        q.whereNotIn(relatedForeignKey, <String>[for (dynamic k in keep) '$k']);
      }
    }
    return await q.delete();
  }

  /// the rows of [current] that the database sees as the same as each
  /// text id of [ids], as `id => rows`. An id that the database sees as
  /// no row is not in the map.
  ///
  /// The ids were not matched in Dart. A column that compares without
  /// case or without end spaces (MySQL, MariaDB, SQLite `COLLATE NOCASE`)
  /// can still see `'abc'` as the row `'ABC'`. One query reads the rows
  /// of all ids, then each row goes to the ids it matches without case
  /// and end spaces, like the database. A row with the exact text of an
  /// id goes only to that id. Only when a row matches no id that way
  /// (like `'é'` and `'e'` on an accent-insensitive column) are the ids
  /// with no row checked one by one.
  Future<Map<dynamic, List<Map<String, dynamic>>>> sameInDatabase(
    List<Map<String, dynamic>> current,
    Iterable<dynamic> ids,
  ) async {
    Map<dynamic, List<Map<String, dynamic>>> out =
        <dynamic, List<Map<String, dynamic>>>{};
    List<String> texts = <String>[
      for (dynamic id in ids)
        if (id is String) id,
    ];
    if (current.isEmpty || texts.isEmpty) return out;
    Set<String> found = await _stored(
      query().whereIn(relatedForeignKey, texts),
    );
    if (found.isEmpty) return out;
    Set<String> given = texts.toSet();
    Set<String> claimed = <String>{};
    List<String> left = <String>[];
    for (String id in texts) {
      Set<String> mine = <String>{
        for (String s in found)
          if (s == id || (!given.contains(s) && _fold(s) == _fold(id))) s,
      };
      claimed.addAll(mine);
      if (!_put(out, current, id, mine)) left.add(id);
    }
    if (claimed.length == found.length) return out;
    for (String id in left) {
      _put(
        out,
        current,
        id,
        await _stored(query().where(relatedForeignKey, id)),
      );
    }
    return out;
  }

  /// the related key texts of the rows of [q]
  Future<Set<String>> _stored(QueryBuilder<Map<String, dynamic>> q) async {
    return <String>{
      for (Map<String, dynamic> r in await q.get()) '${r[relatedForeignKey]}',
    };
  }

  /// puts the rows of [current] whose key text is in [found] into [out]
  /// as the rows of [id]. It returns false when there is no such row.
  bool _put(
    Map<dynamic, List<Map<String, dynamic>>> out,
    List<Map<String, dynamic>> current,
    String id,
    Set<String> found,
  ) {
    List<Map<String, dynamic>> rows = <Map<String, dynamic>>[
      for (Map<String, dynamic> c in current)
        if (found.contains('${c[relatedForeignKey]}')) c,
    ];
    if (rows.isNotEmpty) out[id] = rows;
    return rows.isNotEmpty;
  }

  /// a text like a column that compares without case and end spaces
  static String _fold(String s) => s.toLowerCase().trimRight();

  /// sets [values] on the pivot rows of [ids]
  Future<int> update(List<dynamic> ids, Map<String, dynamic> values) async {
    if (ids.isEmpty) return 0;
    return await query().whereIn(relatedForeignKey, ids).update(
      <String, dynamic>{
        ...values,
        if (withTimestamps && !values.containsKey('updated_at'))
          'updated_at': now(),
      },
    );
  }
}

/// the result of [ManyToManyWrites.sync] and [ManyToManyWrites.toggle]
class PivotSyncResult {
  /// the related ids that got a new pivot row
  final List<dynamic> attached;

  /// the related ids whose pivot row was deleted
  final List<dynamic> detached;

  /// the related ids whose pivot row got new values
  final List<dynamic> updated;

  const PivotSyncResult({
    this.attached = const <dynamic>[],
    this.detached = const <dynamic>[],
    this.updated = const <dynamic>[],
  });

  @override
  String toString() =>
      'PivotSyncResult(attached: $attached, detached: $detached, '
      'updated: $updated)';
}

/// writes to the pivot table of a `@ManyToMany` relation, like Laravel.
/// [relation] is the field name of the relation, like `'songs'`.
///
/// ```
/// await artist.attach('songs', 1);
/// await artist.attach('songs', [1, 2], {'role': 'singer'});
/// await artist.attach('songs', {1: {'role': 'singer'}, 2: {}});
/// await artist.detach('songs', [1]);
/// await artist.detach('songs'); // all songs
/// PivotSyncResult r = await artist.sync('songs', [1, 2, 3]);
/// await artist.toggle('songs', [1, 2]);
/// await artist.updateExistingPivot('songs', 1, {'role': 'writer'});
/// ```
///
/// The ids can be ids, models, a list of them, or a map of
/// `id => extra pivot values`. The model must be saved first.
extension ManyToManyWrites<T> on Model<T> {
  /// the pivot columns of a model that a many to many relation read
  /// (with `preload`, `$getRelation`, `eager` or `related().get()`):
  /// the two keys, the `withPivot` columns, and `created_at` and
  /// `updated_at` with `withTimestamps`. It is empty for a model that was
  /// not read by a many to many relation.
  ///
  /// ```
  /// @ManyToMany(Song, withPivot: ['role'])
  /// List<Song> songs = <Song>[];
  ///
  /// Artist artist = await Artist().preload('songs').find(1);
  /// print(artist.songs.first.pivot['role']);
  /// ```
  Map<String, dynamic> get pivot {
    _Pivot? p = manyToManyRow[this] as _Pivot?;
    return <String, dynamic>{
      /// the join makes `_owner_id` the owner key and the related key
      /// the pivot related key, so they are not read again
      if (p != null) ...<String, dynamic>{
        p.foreignKey: originalMap['_owner_id'],
        p.relatedForeignKey: relationKey(this, p.relatedKey),
      },
      for (MapEntry<String, dynamic> e in originalMap.entries)
        if (e.key.startsWith(_pivotPrefix))
          e.key.substring(_pivotPrefix.length): e.value,
    };
  }

  _Pivot _pivotOf(String relation) {
    _Pivot? p;
    dynamic q = related<dynamic>(relation);
    if (q != null) p = manyToManyQuery[q as Object] as _Pivot?;
    if (p == null) {
      throw ArgumentError.value(
        relation,
        'relation',
        'is not a many to many relation of $runtimeType',
      );
    }
    return p;
  }

  /// adds pivot rows for [ids]. [values] are extra pivot columns for
  /// every new row.
  Future<void> attach(
    String relation,
    dynamic ids, [
    Map<String, dynamic> values = const <String, dynamic>{},
  ]) async {
    _Pivot p = _pivotOf(relation);
    await p.insert(p.unique(p.records(ids, values)));
  }

  /// deletes the pivot rows of [ids]. With no [ids] it deletes every
  /// pivot row of this model. `null` is no ids, so it deletes nothing.
  /// It returns how many rows it deleted.
  Future<int> detach(String relation, [Object? ids = _allIds]) async {
    _Pivot p = _pivotOf(relation);
    if (identical(ids, _allIds)) return await p.delete(null);
    return await p.delete(p.records(ids).keys.toList());
  }

  /// sets the pivot values of the related rows of [ids]. It returns
  /// how many rows changed.
  Future<int> updateExistingPivot(
    String relation,
    dynamic ids,
    Map<String, dynamic> values,
  ) async {
    _Pivot p = _pivotOf(relation);
    return await p.update(p.records(ids).keys.toList(), values);
  }

  /// makes the pivot rows match [ids]: it adds the missing rows, deletes
  /// the other rows (only when [detaching] is true), and sets the extra
  /// values of the rows that are already there.
  Future<PivotSyncResult> sync(
    String relation,
    dynamic ids, {
    bool detaching = true,
  }) async {
    _Pivot p = _pivotOf(relation);
    Map<dynamic, Map<String, dynamic>> records = p.records(ids);

    /// a null id or a model that is not saved is a mistake here: it would
    /// delete every other link. null or [] alone is asked for, so it is ok.
    if (detaching && p.skipped) {
      throw ArgumentError.value(
        ids,
        'ids',
        'has a null id or a model that is not saved',
      );
    }
    List<Map<String, dynamic>> current = await p.rows();

    /// match by value, so `'01'` keeps the row of `1`. Each id finds its
    /// own row when it can, so on a text key `[1, '01']` sets the values
    /// of the rows `'1'` and `'01'`. When two ids match one row (`'1'` and
    /// `'01'` on a number key), the first one wins. An id with no row is
    /// added once, by [sameId].
    Map<dynamic, Map<String, dynamic>> attach =
        <dynamic, Map<String, dynamic>>{};
    List<MapEntry<dynamic, Map<String, dynamic>>> changes =
        <MapEntry<dynamic, Map<String, dynamic>>>[];
    Set<Map<String, dynamic>> used = Set<Map<String, dynamic>>.identity();
    for (MapEntry<dynamic, Map<String, dynamic>> e in records.entries) {
      Map<String, dynamic>? row = p.match(current, e.key, used);
      if (row == null) {
        if (!_hasSame(attach.keys, e.key)) attach[e.key] = e.value;
        continue;
      }
      if (!used.add(row)) continue;
      if (_changes(row, e.value)) {
        changes.add(
          MapEntry<dynamic, Map<String, dynamic>>(
            row[p.relatedForeignKey],
            e.value,
          ),
        );
      }
    }

    /// an id that the database sees as a stored row (`'abc'` and `'ABC'`
    /// on a column that compares without case) keeps that row
    Map<dynamic, List<Map<String, dynamic>>> same = await p.sameInDatabase(
      current,
      attach.keys,
    );
    for (MapEntry<dynamic, List<Map<String, dynamic>>> e in same.entries) {
      Map<String, dynamic> values = attach.remove(e.key)!;
      Map<String, dynamic>? row = _firstNotIn(e.value, used);
      if (row == null) continue;
      used.add(row);
      if (_changes(row, values)) {
        changes.add(
          MapEntry<dynamic, Map<String, dynamic>>(
            row[p.relatedForeignKey],
            values,
          ),
        );
      }
    }

    /// a stored row is deleted only when no given id matches it, so a
    /// row is never deleted by a near match of another id
    List<dynamic> detached = <dynamic>[
      if (detaching)
        for (Map<String, dynamic> r in current)
          if (!used.contains(r) &&
              !_hasGiven(records.keys, r[p.relatedForeignKey]))
            r[p.relatedForeignKey],
    ];

    /// every id is checked above, so a bad id throws before any write
    List<dynamic> updated = <dynamic>[];
    for (MapEntry<dynamic, Map<String, dynamic>> c in changes) {
      await p.update(<dynamic>[c.key], c.value);
      updated.add(c.key);
    }

    /// insert first and delete last, so a failed insert keeps the old
    /// links. The delete keeps the new and the kept ids, so a database
    /// that sees two ids as one does not delete them.
    await p.insert(attach);
    await p.delete(
      detached,
      keep: <dynamic>[
        ...attach.keys,
        for (Map<String, dynamic> r in used) r[p.relatedForeignKey],
      ],
    );
    return PivotSyncResult(
      attached: _keys(attach.keys),
      detached: _keys(detached),
      updated: _keys(updated),
    );
  }

  /// [sync] that does not delete rows
  Future<PivotSyncResult> syncWithoutDetaching(String relation, dynamic ids) {
    return sync(relation, ids, detaching: false);
  }

  /// adds a pivot row for each of [ids] that has none, and deletes the
  /// row of each of [ids] that has one
  Future<PivotSyncResult> toggle(String relation, dynamic ids) async {
    _Pivot p = _pivotOf(relation);
    Map<dynamic, Map<String, dynamic>> records = p.records(ids);
    List<Map<String, dynamic>> current = await p.rows();
    List<dynamic> detached = <dynamic>[];
    Map<dynamic, Map<String, dynamic>> attach =
        <dynamic, Map<String, dynamic>>{};

    /// each id finds its own row when it can (on a text key `[1, '01']`
    /// detaches `'1'` and `'01'`). A row is used once, so on a number key
    /// `['1', '01']` detaches the row of `1` once and adds nothing.
    Set<Map<String, dynamic>> used = Set<Map<String, dynamic>>.identity();
    for (MapEntry<dynamic, Map<String, dynamic>> e in records.entries) {
      Map<String, dynamic>? row = p.match(current, e.key, used);
      if (row != null) {
        if (used.add(row)) detached.add(row[p.relatedForeignKey]);
      } else if (!_hasSame(attach.keys, e.key)) {
        attach[e.key] = e.value;
      }
    }

    /// an id that the database sees as a stored row (`'abc'` and `'ABC'`
    /// on a column that compares without case) detaches that row
    Map<dynamic, List<Map<String, dynamic>>> same = await p.sameInDatabase(
      current,
      attach.keys,
    );
    for (MapEntry<dynamic, List<Map<String, dynamic>>> e in same.entries) {
      attach.remove(e.key);
      Map<String, dynamic>? row = _firstNotIn(e.value, used);
      if (row != null && used.add(row)) detached.add(row[p.relatedForeignKey]);
    }

    /// insert first, so a failed insert keeps the old links. The delete
    /// keeps the new ids, see [_Pivot.delete].
    await p.insert(attach);
    await p.delete(detached, keep: attach.keys);
    return PivotSyncResult(
      attached: _keys(attach.keys),
      detached: _keys(detached),
    );
  }
}

/// [ids] with one type, each once: a number id is an int. A text id
/// becomes an int only when it is the plain text of that int (`'4'`), so a
/// text key like `'04'` or `'007'` stays text. Other ids stay as they are.
/// Two stored rows of one id (`1` and `1`) give the id once.
List<dynamic> _keys(Iterable<dynamic> ids) {
  return <dynamic>{
    for (dynamic id in ids)
      if (id is String && '${int.tryParse(id)}' == id) int.parse(id) else id,
  }.toList();
}

/// the default of [ManyToManyWrites.detach]: no ids given, detach all
const Object _allIds = Object();

/// true when [id] is a text
bool _isText(dynamic id) => id is String;

/// the first of [rows] that is not in [used], or null
Map<String, dynamic>? _firstNotIn(
  List<Map<String, dynamic>> rows,
  Set<Map<String, dynamic>> used,
) {
  for (Map<String, dynamic> r in rows) {
    if (!used.contains(r)) return r;
  }
  return null;
}

/// true when one of the given [ids] matches the stored value [stored]
bool _hasGiven(Iterable<dynamic> ids, dynamic stored) {
  for (dynamic i in ids) {
    if (sameId(i, stored)) return true;
  }
  return false;
}

/// true when [ids] has a given id that is the same as the given [id].
/// Both can throw, see [intId].
bool _hasSame(Iterable<dynamic> ids, dynamic id) {
  for (dynamic i in ids) {
    if (sameId(i, id)) return true;
  }
  return false;
}

/// true when [values] has a value that is not the same in [row]
bool _changes(Map<String, dynamic> row, Map<String, dynamic> values) {
  for (MapEntry<String, dynamic> e in values.entries) {
    if (!_same(row[e.key], e.value)) return true;
  }
  return false;
}

/// true when the database value [stored] is the same as [value]. MySQL
/// and SQLite read a bool as 1 or 0, and a date can come back as text.
bool _same(dynamic stored, dynamic value) {
  if (stored == value) return true;
  if (stored == null || value == null) return false;
  if (value is bool) value = value ? 1 : 0;
  if (stored is bool) stored = stored ? 1 : 0;
  if (value is DateTime || stored is DateTime) {
    DateTime? a = stored is DateTime ? stored : DateTime.tryParse('$stored');
    DateTime? b = value is DateTime ? value : DateTime.tryParse('$value');
    return a != null && b != null && a.isAtSameMomentAs(b);
  }
  if (value is num || stored is num) {
    num? a = stored is num ? stored : num.tryParse('$stored');
    num? b = value is num ? value : num.tryParse('$value');
    return a != null && a == b;
  }
  return '$stored' == '$value';
}
