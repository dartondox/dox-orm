import 'package:dox_orm/dox_orm.dart';

import 'keys.dart';

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

  /// the pivot columns to read, see [ManyToManyWrites.pivot]
  List<String> pivotColumns = <String>[
    pivotForeignKey,
    pivotRelatedForeignKey,
    ...?withPivot,
    if (withTimestamps) ...<String>['created_at', 'updated_at'],
  ];
  String pivotSelect = <String>[
    for (String c in pivotColumns.toSet()) '$pivotTable.$c as $_pivotPrefix$c',
  ].join(', ');

  QueryBuilder<M> q = related
      .debug(local.shouldDebug)
      .select(
        '$relatedTable.*, $pivotTable.$pivotForeignKey as _owner_id, '
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
  _pivots[q] = _Pivot(
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

/// the pivot table of each many to many query, for the write methods
final Expando<_Pivot> _pivots = Expando<_Pivot>();

class _Pivot {
  final Model<dynamic> owner;
  final String ownerKey;
  final String relatedKey;
  final String table;
  final String foreignKey;
  final String relatedForeignKey;
  final bool withTimestamps;

  const _Pivot({
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

  /// the rows of the owner, keyed by the related id as a string
  Future<Map<String, Map<String, dynamic>>> rows() async {
    List<Map<String, dynamic>> list = await query().get();
    return <String, Map<String, dynamic>>{
      for (Map<String, dynamic> r in list) '${r[relatedForeignKey]}': r,
    };
  }

  /// [ids] as `id => extra pivot values`. [ids] can be one id, one
  /// model, a list of ids or models, or a map of `id => values`.
  Map<dynamic, Map<String, dynamic>> records(
    dynamic ids, [
    Map<String, dynamic> values = const <String, dynamic>{},
  ]) {
    if (ids is Map) {
      return <dynamic, Map<String, dynamic>>{
        for (MapEntry<dynamic, dynamic> e in ids.entries)
          _id(e.key): <String, dynamic>{
            ...values,
            ...(e.value as Map<String, dynamic>? ?? <String, dynamic>{}),
          },
      };
    }
    List<dynamic> list = ids is Iterable ? ids.toList() : <dynamic>[ids];
    return <dynamic, Map<String, dynamic>>{
      for (dynamic id in list) _id(id): values,
    };
  }

  dynamic _id(dynamic id) => id is Model ? relationKey(id, relatedKey) : id;

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

  /// sets [values] on the pivot row of [id]
  Future<int> update(dynamic id, Map<String, dynamic> values) async {
    return await query().where(relatedForeignKey, id).update(<String, dynamic>{
      ...values,
      if (withTimestamps && !values.containsKey('updated_at'))
        'updated_at': now(),
    });
  }
}

/// the result of [ManyToManyWrites.sync] and [ManyToManyWrites.toggle]
class SyncResult {
  /// the related ids that got a new pivot row
  final List<dynamic> attached;

  /// the related ids whose pivot row was deleted
  final List<dynamic> detached;

  /// the related ids whose pivot row got new values
  final List<dynamic> updated;

  const SyncResult({
    this.attached = const <dynamic>[],
    this.detached = const <dynamic>[],
    this.updated = const <dynamic>[],
  });

  @override
  String toString() =>
      'SyncResult(attached: $attached, detached: $detached, '
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
/// SyncResult r = await artist.sync('songs', [1, 2, 3]);
/// await artist.toggle('songs', [1, 2]);
/// await artist.updateExistingPivot('songs', 1, {'role': 'writer'});
/// ```
///
/// The ids can be ids, models, a list of them, or a map of
/// `id => extra pivot values`. The model must be saved first.
extension ManyToManyWrites<T> on Model<T> {
  /// the extra pivot columns of a model that a many to many relation
  /// read: the two keys, the `withPivot` columns, and `created_at` and
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
  Map<String, dynamic> get pivot => <String, dynamic>{
    for (MapEntry<String, dynamic> e in originalMap.entries)
      if (e.key.startsWith(_pivotPrefix))
        e.key.substring(_pivotPrefix.length): e.value,
  };

  _Pivot _pivotOf(String relation) {
    _Pivot? p;
    dynamic q = related<dynamic>(relation);
    if (q != null) p = _pivots[q as Object];
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

  /// deletes the pivot rows of [ids], or every pivot row of this model
  /// when [ids] is null. It returns how many rows it deleted.
  Future<int> detach(String relation, [dynamic ids]) async {
    _Pivot p = _pivotOf(relation);
    return await p.delete(ids == null ? null : p.records(ids).keys.toList());
  }

  /// sets the pivot values of one related row
  Future<int> updateExistingPivot(
    String relation,
    dynamic id,
    Map<String, dynamic> values,
  ) async {
    _Pivot p = _pivotOf(relation);
    return await p.update(p.records(id).keys.first, values);
  }

  /// makes the pivot rows match [ids]: it adds the missing rows, deletes
  /// the other rows (only when [detaching] is true), and sets the extra
  /// values of the rows that are already there.
  Future<SyncResult> sync(
    String relation,
    dynamic ids, {
    bool detaching = true,
  }) async {
    _Pivot p = _pivotOf(relation);
    Map<dynamic, Map<String, dynamic>> records = p.records(ids);
    Map<String, Map<String, dynamic>> current = await p.rows();
    Set<String> wanted = <String>{for (dynamic id in records.keys) '$id'};

    List<dynamic> detached = <dynamic>[
      if (detaching)
        for (MapEntry<String, Map<String, dynamic>> e in current.entries)
          if (!wanted.contains(e.key)) e.value[p.relatedForeignKey],
    ];
    await p.delete(detached);

    Map<dynamic, Map<String, dynamic>> attach =
        <dynamic, Map<String, dynamic>>{};
    List<dynamic> updated = <dynamic>[];
    for (MapEntry<dynamic, Map<String, dynamic>> e in records.entries) {
      Map<String, dynamic>? row = current['${e.key}'];
      if (row == null) {
        attach[e.key] = e.value;
      } else if (_changes(row, e.value)) {
        await p.update(e.key, e.value);
        updated.add(e.key);
      }
    }
    await p.insert(attach);
    return SyncResult(
      attached: attach.keys.toList(),
      detached: detached,
      updated: updated,
    );
  }

  /// [sync] that does not delete rows
  Future<SyncResult> syncWithoutDetaching(String relation, dynamic ids) {
    return sync(relation, ids, detaching: false);
  }

  /// adds a pivot row for each of [ids] that has none, and deletes the
  /// row of each of [ids] that has one
  Future<SyncResult> toggle(String relation, dynamic ids) async {
    _Pivot p = _pivotOf(relation);
    Map<dynamic, Map<String, dynamic>> records = p.records(ids);
    Map<String, Map<String, dynamic>> current = await p.rows();
    List<dynamic> detached = <dynamic>[
      for (dynamic id in records.keys)
        if (current.containsKey('$id')) id,
    ];
    Map<dynamic, Map<String, dynamic>> attach = <dynamic, Map<String, dynamic>>{
      for (MapEntry<dynamic, Map<String, dynamic>> e in records.entries)
        if (!current.containsKey('${e.key}')) e.key: e.value,
    };
    await p.delete(detached);
    await p.insert(attach);
    return SyncResult(attached: attach.keys.toList(), detached: detached);
  }
}

/// true when [values] has a value that is not the same in [row]
bool _changes(Map<String, dynamic> row, Map<String, dynamic> values) {
  for (MapEntry<String, dynamic> e in values.entries) {
    if ('${row[e.key]}' != '${e.value}') return true;
  }
  return false;
}
