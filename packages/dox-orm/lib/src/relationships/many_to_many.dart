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

  /// the row of [rows] whose related id is [id] by value, see [sameId]
  Map<String, dynamic>? match(List<Map<String, dynamic>> rows, dynamic id) {
    for (Map<String, dynamic> r in rows) {
      if (sameId(r[relatedForeignKey], id)) return r;
    }
    return null;
  }

  /// [ids] as `id => extra pivot values`. [ids] can be one id, one
  /// model, a list of ids or models, or a map of `id => values`.
  ///
  /// Like Laravel, null means no ids, and a null id (or a model without
  /// a key) is skipped. A whole number like `2.0` becomes the int `2`,
  /// because Postgres does not take `2.0` for an integer column. Any other
  /// double (`1.5`, NaN, infinity, or past ±2^53 like `1e20`) throws an
  /// [ArgumentError]. An id
  /// is kept once, by [sameId]: `[1, '01', 1.0]` gives one id, the first
  /// one wins. Every write uses these ids, so they all match the same way.
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
    for (MapEntry<dynamic, dynamic> e in entries) {
      dynamic id = _id(e.key);
      if (id == null) skipped = true;
      // ponytail: O(n²) scan of the ids of one call, fine for normal lists
      if (id == null || _hasSame(out.keys, id)) continue;
      out[id] = <String, dynamic>{
        ...values,

        /// an untyped map literal like `{1: {'role': 'x'}}` works too
        ...?(e.value as Map<dynamic, dynamic>?)?.cast<String, dynamic>(),
      };
    }
    return out;
  }

  dynamic _id(dynamic id) {
    if (id is Model) id = relationKey(id, relatedKey);
    if (id is! double) return id;
    return intId(id) ??
        (throw ArgumentError.value(id, 'ids', 'is not a whole number id'));
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
  /// [ids] is null
  Future<int> delete(List<dynamic>? ids) async {
    if (ids != null && ids.isEmpty) return 0;
    QueryBuilder<Map<String, dynamic>> q = query();
    if (ids != null) q.whereIn(relatedForeignKey, ids);
    return await q.delete();
  }

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
    await p.insert(p.records(ids, values));
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

    /// match by value, so `'01'` keeps the row of `1`. Two texts like
    /// `'1'` and `'01'` are two ids, but they can match the same row of a
    /// number key. A row is used once, the first id wins.
    Map<dynamic, Map<String, dynamic>> attach =
        <dynamic, Map<String, dynamic>>{};
    List<dynamic> updated = <dynamic>[];
    List<dynamic> kept = <dynamic>[];
    Set<Map<String, dynamic>> used = Set<Map<String, dynamic>>.identity();
    for (MapEntry<dynamic, Map<String, dynamic>> e in records.entries) {
      Map<String, dynamic>? row = p.match(current, e.key);
      if (row == null) {
        attach[e.key] = e.value;
        continue;
      }
      if (!used.add(row)) continue;
      kept.add(row[p.relatedForeignKey]);
      if (_changes(row, e.value)) {
        await p.update(<dynamic>[row[p.relatedForeignKey]], e.value);
        updated.add(row[p.relatedForeignKey]);
      }
    }
    List<dynamic> detached = <dynamic>[
      if (detaching)
        for (Map<String, dynamic> r in current)
          if (!_hasSame(kept, r[p.relatedForeignKey])) r[p.relatedForeignKey],
    ];

    /// insert first and delete last, so a failed insert keeps the old
    /// links. The ids of the two never overlap.
    await p.insert(attach);
    await p.delete(detached);
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

    /// a row is used once: `['1', '01']` detaches the row of `1` once
    Set<Map<String, dynamic>> used = Set<Map<String, dynamic>>.identity();
    for (MapEntry<dynamic, Map<String, dynamic>> e in records.entries) {
      Map<String, dynamic>? row = p.match(current, e.key);
      if (row != null) {
        if (used.add(row)) detached.add(row[p.relatedForeignKey]);
      } else {
        attach[e.key] = e.value;
      }
    }

    /// insert first, so a failed insert keeps the old links
    await p.insert(attach);
    await p.delete(detached);
    return PivotSyncResult(
      attached: _keys(attach.keys),
      detached: _keys(detached),
    );
  }
}

/// [ids] with one type: a number id is an int. A text id becomes an int
/// only when it is the plain text of that int (`'4'`), so a text key like
/// `'04'` or `'007'` stays text. Other ids stay as they are.
List<dynamic> _keys(Iterable<dynamic> ids) {
  return <dynamic>[
    for (dynamic id in ids)
      if (id is String && '${int.tryParse(id)}' == id) int.parse(id) else id,
  ];
}

/// the default of [ManyToManyWrites.detach]: no ids given, detach all
const Object _allIds = Object();

/// true when [ids] has an id that is the same as [id] by value
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
