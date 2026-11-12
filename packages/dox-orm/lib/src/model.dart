import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../dox_orm.dart';
import 'relationships/keys.dart';
import 'utils/plural.dart';
import 'union.dart';

/// the where of [Model.preload]
typedef _PreloadWhere = void Function(QueryBuilder<dynamic> query);

class Model<T> extends QueryBuilder<T> {
  static final Map<String, Model<dynamic> Function()> _morphModels =
      <String, Model<dynamic> Function()>{};
  static final Map<Type, String> _morphNames = <Type, String>{};

  /// the morph map: the type names that polymorphic relations store in
  /// the `<name>_type` column.
  /// A `@MorphTo` relation needs every model it can point to in this
  /// map. The map is kept per isolate, so call it in the `setup()` of a
  /// provider, which runs in every isolate.
  ///
  /// ```
  /// Model.morphMap({'post': Post.new, 'video': Video.new});
  /// ```
  ///
  /// Without it, `@MorphMany` and `@MorphOne` store the class name, like
  /// `Post`. [merge] false removes the names set before.
  static void morphMap(
    Map<String, Model<dynamic> Function()> map, {
    bool merge = true,
  }) {
    if (!merge) {
      _morphModels.clear();
      _morphNames.clear();
    }
    for (MapEntry<String, Model<dynamic> Function()> e in map.entries) {
      _morphModels[e.key] = e.value;
      _morphNames[e.value().runtimeType] = e.key;
    }
  }

  /// the morph type name of [model]: its name in the morph map, or its
  /// class name
  static String morphTypeOf(Model<dynamic> model) {
    return _morphNames[model.runtimeType] ?? model.runtimeType.toString();
  }

  /// a new model for the morph type name [type]. It throws a
  /// [StateError] when [type] is not in the morph map.
  static Model<dynamic> morphModel(String type) {
    Model<dynamic> Function()? make = _morphModels[type];
    if (make == null) {
      throw StateError(
        'no model for the morph type "$type". '
        'Add it with Model.morphMap()',
      );
    }
    return make();
  }

  /// primary key value, it can be any type (int, uuid string...)
  dynamic tempIdValue;
  DateTime? createdAt;
  DateTime? updatedAt;

  /// fields left out of toJson()
  List<String> get hidden => _hidden ??= <String>[];
  set hidden(List<String> value) => _hidden = value;
  List<String>? _hidden;

  /// the only fields that toJson() keeps, the opposite of [hidden].
  /// It is not named `visible`, so a model can keep a `visible` column
  /// or scope.
  /// Empty (the default) keeps every field. [hidden] still leaves a
  /// field out.
  ///
  /// ```
  /// @override
  /// List<String> get visibleFields => const <String>['id', 'name'];
  /// ```
  List<String> get visibleFields => const <String>[];

  /// the fields of [makeHidden] and [makeVisible] of this model:
  /// (hidden, shown). null when neither was called, so toJson() of a
  /// plain model reads one null field.
  (Set<String>, Set<String>)? _visibility;

  /// leaves [fields] out of toJson() of this model only, on top of
  /// [hidden]. It returns this model.
  ///
  /// ```
  /// return user.makeHidden(<String>['email']).toJson();
  /// ```
  Model<T> makeHidden(List<String> fields) {
    var (Set<String> hide, Set<String> show) = _visibility ??= (
      <String>{},
      <String>{},
    );
    hide.addAll(fields);
    show.removeAll(fields);
    return this;
  }

  /// keeps [fields] in toJson() of this model only, also when they are
  /// in [hidden] or not in [visibleFields]. It returns this model.
  ///
  /// ```
  /// return user.makeVisible(<String>['email']).toJson();
  /// ```
  Model<T> makeVisible(List<String> fields) {
    var (Set<String> hide, Set<String> show) = _visibility ??= (
      <String>{},
      <String>{},
    );
    show.addAll(fields);
    hide.removeAll(fields);
    return this;
  }

  /// removes the fields of [hidden], [visibleFields], [makeHidden] and
  /// [makeVisible] from [data]
  void _removeHidden(Map<String, dynamic> data) {
    (Set<String>, Set<String>)? v = _visibility;
    if (v == null) {
      for (String h in hidden) {
        data.remove(h);
      }
      List<String> only = visibleFields;
      if (only.isNotEmpty) _keepOnly(data, only, const <String>{});
      return;
    }
    var (Set<String> hide, Set<String> show) = v;
    for (String h in hidden) {
      if (!show.contains(h)) data.remove(h);
    }
    for (String h in hide) {
      data.remove(h);
    }
    List<String> only = visibleFields;
    if (only.isNotEmpty) _keepOnly(data, only, show);
  }

  /// removes the keys of [data] that are not in [only] or [show]
  static void _keepOnly(
    Map<String, dynamic> data,
    List<String> only,
    Set<String> show,
  ) {
    for (String key in data.keys.toList()) {
      if (!only.contains(key) && !show.contains(key)) data.remove(key);
    }
  }

  /// columns that create(), insert(), insertMultiple() and update() take
  /// from a map.
  ///
  /// A model is guarded by default: with no [fillable] and
  /// the default [guarded], a map with keys throws a
  /// [MassAssignmentException], so `User().create(req.body)` can not set
  /// `id` or `is_admin`. List the columns that users may set:
  ///
  /// ```
  /// @override
  /// List<String> get fillable => <String>['name', 'email'];
  /// ```
  List<String> get fillable => const <String>[];

  /// columns that create(), insert(), insertMultiple() and update() never
  /// take from a map. `'*'` (the default) means every column that is not
  /// in [fillable].
  ///
  /// To take every key of a map (not safe with user input), set it to an
  /// empty list:
  ///
  /// ```
  /// @override
  /// List<String> get guarded => const <String>[];
  /// ```
  List<String> get guarded => const <String>['*'];

  /// zone key that [unguarded] sets
  static const Symbol _unguardedKey = #doxOrmUnguarded;

  /// run [callback] with [fillable] and [guarded] turned off for every
  /// model. create(), update(),
  /// upsert() and the other writes take every key of a map inside it.
  /// It is not safe with user input.
  ///
  /// ```
  /// await Model.unguarded(() async {
  ///   await User().create({'name': 'Ann', 'is_admin': true});
  ///   await User().where('id', 1).update({'is_admin': true});
  /// });
  /// ```
  ///
  /// It uses a [Zone], so it covers every await inside [callback]. Other
  /// requests that run at the same time still use [fillable]. Work that
  /// starts inside [callback] and finishes later (a timer, a future that
  /// is not awaited, a stream listener) also runs with the check off, so
  /// await everything inside [callback].
  static R unguarded<R>(R Function() callback) {
    return runZoned(
      callback,
      zoneValues: <Object?, Object?>{_unguardedKey: true},
    );
  }

  /// true inside [unguarded]
  static bool get isUnguarded => Zone.current[_unguardedKey] == true;

  /// [data] without the keys that [fillable] and [guarded] do not allow
  Map<String, dynamic> _onlyFillable(Map<String, dynamic> data) {
    if (isUnguarded) return data;
    List<String> allowed = fillable;
    List<String> blocked = guarded;
    if (allowed.isEmpty && blocked.isEmpty) return data;
    bool blockAll = blocked.contains('*');
    if (allowed.isEmpty && blockAll) {
      if (data.isEmpty) return data;
      throw MassAssignmentException('$runtimeType', data.keys.toList());
    }
    Set<String> blockedNames = blocked.map(_columnName).toSet();
    List<String> columns = tableColumns;
    return <String, dynamic>{
      for (MapEntry<String, dynamic> e in data.entries)
        if (!blockedNames.contains(_columnName(e.key)) &&
            (allowed.contains(e.key) ||
                (allowed.isEmpty &&
                    !blockAll &&
                    (columns.isEmpty
                        ? _ascii.hasMatch(e.key)
                        : columns.contains(e.key)))))
          e.key: e.value,
    };
  }

  /// a key with only ASCII chars. With no [tableColumns], a key with
  /// other chars is dropped: MySQL folds case of more chars than Dart
  /// toLowerCase(), so `'İS_ADMIN'` could set `is_admin`.
  static final RegExp _ascii = RegExp(r'^[\x00-\x7F]*$');

  /// the column name that the database sees for [key]. The SQL builder
  /// trims the name, a table prefix points to the same column, and
  /// SQLite and MySQL match names without case. So `' IS_ADMIN'` and
  /// `'users.is_admin'` set `is_admin`, and [guarded] must catch them.
  static String _columnName(String key) {
    String name = key.trim();
    return name.substring(name.lastIndexOf('.') + 1).toLowerCase();
  }

  /// the generator overrides it with the model columns
  List<String> get tableColumns => _tableColumns ??= <String>[];
  set tableColumns(List<String> value) => _tableColumns = value;
  List<String>? _tableColumns;

  bool _debug = SqlQueryBuilder().debug;

  /// keys that create() got as null, written as NULL on the insert.
  /// Only set with [OrmFlags.createWritesNull].
  Set<String> _createNullKeys = const <String>{};

  /// values we last saved, so save() can tell when a field was set to null
  Map<String, dynamic>? _savedValues;

  /// columns the last write of this model changed, see [getChanges]
  Map<String, dynamic> _lastChanges = const <String, dynamic>{};

  /// true after save() or create() inserted this model as a new row.
  /// A model read from the table gives false.
  ///
  /// ```
  /// User user = await User().firstOrCreate({'email': 'ann@example.com'});
  /// if (user.wasRecentlyCreated) await sendWelcomeMail(user);
  /// ```
  bool get wasRecentlyCreated => _wasRecentlyCreated;
  bool _wasRecentlyCreated = false;

  /// true when the row is in the table: the model was read from it, or
  /// saved. save() inserts when it is false, so a model with a key you
  /// set yourself (like a UUID) is inserted, not updated.
  bool get exists => _savedValues != null || originalMap.isNotEmpty;

  /// the class name in snake case: `BlogPost` uses `blog_post`. With
  /// [OrmFlags.pluralTableNames] it is plural:
  /// `blog_posts`. `@DoxModel(table: ...)` sets a name of your own.
  @override
  String get tableName {
    String name = helper.tableNameOf(runtimeType);
    return SqlQueryBuilder().flags.pluralTableNames ? pluralName(name) : name;
  }

  /// the default foreign key that points to this model: the class name
  /// in snake case and `_id`. `User` gives `user_id`, also
  /// when the table is `users`.
  String get foreignKeyName => '${helper.tableNameOf(runtimeType)}_id';

  @override
  dynamic get self => this;

  // coverage:ignore-start
  Map<String, dynamic> get timestampsColumn => const <String, dynamic>{
    'created_at': 'created_at',
    'updated_at': 'updated_at',
  };
  // coverage:ignore-end

  @override
  Model<T> debug([bool? debug]) {
    _debug = debug ?? true;
    super.debug(debug);
    return this;
  }

  /// use a named connection. save(), delete() and the models this
  /// query returns use it too.
  ///
  /// ```
  /// Blog blog = Blog()..withConnection('mysql');
  /// await blog.save();
  /// ```
  @override
  Model<T> withConnection(String connectionName) {
    super.withConnection(connectionName);
    return this;
  }

  /// create new record in table
  ///
  /// ```
  /// Blog blog = new Blog();
  /// blog.title = 'blog title';
  /// await blog.save()
  /// ```
  ///
  /// It fires the model events (saving, creating or updating, then
  /// created or updated, then saved). It returns false when a hook
  /// throws [CancelModelEvent]. With [OrmFlags.skipCleanUpdateEvents],
  /// a saved model with no changes fires only saving and saved.
  Future<bool> save() async {
    if (!_eventsOn) {
      await _save();
      return true;
    }
    bool isNew = !exists;
    bool clean = false;
    try {
      await _fire(ModelEvent.saving);

      /// checked after saving: a saving hook can change a field
      clean =
          !isNew &&
          SqlQueryBuilder().flags.skipCleanUpdateEvents &&
          _changes().$1.isEmpty;
      if (!clean) {
        await _fire(isNew ? ModelEvent.creating : ModelEvent.updating);
      }
    } on CancelModelEvent {
      return false;
    }
    if (!clean) {
      await _save();
      await _fire(isNew ? ModelEvent.created : ModelEvent.updated);
    }
    await _fire(ModelEvent.saved);
    return true;
  }

  /// save without firing model events
  Future<void> saveQuietly() => _save();

  Future<void> _save() async {
    String? updatedAtColumn = timestampsColumn['updated_at'];

    if (!exists) {
      Map<String, dynamic> values = _newRowValues(_createNullKeys);
      _createNullKeys = const <String>{};

      /// only the new id is needed, so no select of the new row
      List<Map<String, dynamic>> res = await _newQuery<dynamic>()
          .insertMultiple(<Map<String, dynamic>>[values]);

      /// mysql only returns auto increment ids, so use the given id if any
      tempIdValue =
          (res.isNotEmpty ? res.first[primaryKey] : null) ?? values[primaryKey];
      _savedValues = <String, dynamic>{...values, primaryKey: tempIdValue};
      _wasRecentlyCreated = true;
      _lastChanges = const <String, dynamic>{};
    } else {
      var (Map<String, dynamic> values, dynamic id, bool keepUpdatedAt) =
          _changes();
      DateTime currentTime = now();
      Map<String, dynamic> saved = _savedValues ?? originalMap;

      /// nothing changed: no query, and updated_at stays as it is
      if (values.isEmpty) {
        _lastChanges = const <String, dynamic>{};
        return;
      }
      DateTime? oldUpdatedAt = updatedAt;
      bool stamp = updatedAtColumn != null && !keepUpdatedAt;
      if (stamp) {
        values[updatedAtColumn] = currentTime;
        updatedAt = currentTime;
      }

      try {
        await _newQuery<T>(this).where(primaryKey, id).update(values);
      } catch (_) {
        /// so a retry stamps a new time, not this one as if the user set it
        if (stamp) updatedAt = oldUpdatedAt;
        rethrow;
      }

      /// after the query: when it fails, the model stays dirty.
      /// save() always sends a map or a list column, so only the ones
      /// that really changed count as changes.
      _lastChanges = <String, dynamic>{
        for (MapEntry<String, dynamic> e in values.entries)
          if (!_sameValue(e.value, saved[e.key])) e.key: e.value,
      };
      _savedValues = <String, dynamic>{...saved, ...values};
    }
  }

  /// the columns of a saved model that changed since it was read or
  /// saved, without the primary key and created_at, then the primary
  /// key value, then true when the user set updated_at (it is kept).
  /// A field we never
  /// loaded or saved is skipped when it is null, so a model loaded with
  /// select() does not clear the other columns.
  (Map<String, dynamic>, dynamic, bool) _changes() {
    String? updatedAtColumn = timestampsColumn['updated_at'];
    Map<String, dynamic> values = toMap(removeRelations: true);
    dynamic id = values.remove(primaryKey);
    values.remove(timestampsColumn['created_at']);
    Map<String, dynamic> saved = _savedValues ?? originalMap;
    bool keepUpdatedAt =
        updatedAtColumn != null &&
        values[updatedAtColumn] != null &&
        !_sameTime(values[updatedAtColumn], saved[updatedAtColumn]);
    values.removeWhere((String key, dynamic value) {
      return (key == updatedAtColumn && !keepUpdatedAt) ||
          _same(value, saved[key]);
    });
    return (values, id, keepUpdatedAt);
  }

  /// the columns to insert for this new model: no null values, and
  /// created_at and updated_at set to now when they have no value yet.
  /// It sets the createdAt and updatedAt fields too.
  /// A key of [nullKeys] (not the primary key) is kept when it is null.
  Map<String, dynamic> _newRowValues([
    Set<String> nullKeys = const <String>{},
  ]) {
    String? createdAtColumn = timestampsColumn['created_at'];
    String? updatedAtColumn = timestampsColumn['updated_at'];
    Map<String, dynamic> values = toMap(removeRelations: true);
    values.removeWhere(
      (String key, dynamic value) =>
          value == null && (key == primaryKey || !nullKeys.contains(key)),
    );
    DateTime currentTime = now();
    if (createdAtColumn != null && values[createdAtColumn] == null) {
      values[createdAtColumn] = currentTime;
      createdAt = currentTime;
    }
    if (updatedAtColumn != null && values[updatedAtColumn] == null) {
      values[updatedAtColumn] = currentTime;
      updatedAt = currentTime;
    }
    return values;
  }

  /// true when [a] and [b] are the same time. A time can be a
  /// [DateTime] or a text, by driver, so both are read as a time first.
  static bool _sameTime(dynamic a, dynamic b) {
    DateTime? x = a is DateTime ? a : DateTime.tryParse('${a ?? ''}');
    DateTime? y = b is DateTime ? b : DateTime.tryParse('${b ?? ''}');
    if (x == null || y == null) return x == y;
    return x.isAtSameMomentAs(y);
  }

  /// true when the model value [a] is the same as the saved value [b].
  /// a map or a list is never the same, it can be changed in place.
  static bool _same(dynamic a, dynamic b) {
    if (a is Map || a is List || b is Map || b is List) return false;
    if (a is DateTime) a = a.toIso8601String();
    if (b is DateTime) b = b.toIso8601String();
    return a == b;
  }

  /// delete this record (soft delete when the model use SoftDeletes).
  /// It returns how many rows it deleted: 1, or 0 when the row was not
  /// there or a hook throws [CancelModelEvent].
  ///
  /// ```
  /// Blog? blog = await Blog().find(1);
  /// int count = await blog!.delete();
  /// ```
  ///
  /// It fires deleting and deleted. A soft delete that changed the row
  /// fires trashed after deleted. A query delete like
  /// `Blog().where('id', 1).delete()` fires no events, and returns how
  /// many rows it deleted.
  ///
  /// On a model with no primary key value (never saved, or read without
  /// the key) and no where(), it throws a [StateError], so it can not
  /// delete every row by mistake. forceDelete(), update(), increment()
  /// and decrement() do the same. To delete every row on purpose, use
  /// `Blog().whereRaw('1 = 1').delete()`: it keeps soft deletes and
  /// global scopes.
  @override
  Future<int> delete() async {
    /// a query delete: Blog().where('id', 1).delete()
    if (tempIdValue == null) {
      _needKeyOrWhere('delete');
      if (isSoftDeletes) {
        /// super.update(): deleted_at is not checked against fillable
        return await super.update(_softDeleteValues());
      }
      return await super.delete();
    }
    bool events = _eventsOn;
    if (events) {
      try {
        await _fire(ModelEvent.deleting);
      } on CancelModelEvent {
        return 0;
      }
    }
    int count;
    if (isSoftDeletes) {
      Map<String, dynamic> values = _softDeleteValues();
      count = await _thisRecord().update(values);
      if (count > 0) _setSoftDeleteFields(values);
    } else {
      count = await _thisRecord().forceDelete();
    }
    if (events) {
      await _fire(ModelEvent.deleted);
      if (isSoftDeletes && count > 0) await _fireTrashed();
    }
    return count;
  }

  /// the values of a soft delete: deleted_at, and updated_at when the
  /// model has timestamps
  Map<String, dynamic> _softDeleteValues() {
    DateTime time = now();
    String? updatedAtColumn = timestampsColumn['updated_at'];
    return <String, dynamic>{'deleted_at': time, ?updatedAtColumn: time};
  }

  /// the values of a restore: deleted_at null, and updated_at when the
  /// model has timestamps
  Map<String, dynamic> _restoreValues() {
    String? updatedAtColumn = timestampsColumn['updated_at'];
    return <String, dynamic>{'deleted_at': null, ?updatedAtColumn: now()};
  }

  /// set the fields of a soft delete or restore: the deletedAt field (by
  /// [setColumnValue]) and updatedAt
  void _setSoftDeleteFields(Map<String, dynamic> values) {
    String? updatedAtColumn = timestampsColumn['updated_at'];
    if (values.containsKey(updatedAtColumn)) {
      updatedAt = values[updatedAtColumn];
    }
    _setSavedColumns(values);
  }

  /// delete this record from the table, also when soft deleted.
  /// It returns how many rows it deleted: 1, or 0 when the row was not
  /// there or a hook throws [CancelModelEvent].
  /// It fires forceDeleting, deleting, deleted, then forceDeleted.
  ///
  /// ```
  /// Blog? blog = await Blog().withTrash().find(1);
  /// int count = await blog!.forceDelete();
  /// ```
  @override
  Future<int> forceDelete() async {
    if (tempIdValue == null) {
      _needKeyOrWhere('forceDelete');
      return await super.forceDelete();
    }
    bool events = _eventsOn;
    if (events) {
      try {
        await _fire(ModelEvent.forceDeleting);
        await _fire(ModelEvent.deleting);
      } on CancelModelEvent {
        return 0;
      }
    }
    int count = await _thisRecord().forceDelete();
    if (events) {
      await _fire(ModelEvent.deleted);
      await _fire(ModelEvent.forceDeleted);
    }
    return count;
  }

  /// add [amount] to [column] in one query, and set the [extra] columns
  /// too. It returns how many rows changed.
  ///
  /// ```
  /// await Blog().where('status', 'hot').increment('views');
  ///
  /// Blog? blog = await Blog().find(1);
  /// await blog!.increment('views', 2);
  /// ```
  ///
  /// On a model from the table it changes only that row, and it sets
  /// the Dart field of [column] (and of the [extra] columns) to the new
  /// value, with [setColumnValue]. A later save() does not send the old
  /// value back. Keys of [extra] that [fillable] and [guarded] do not
  /// allow are dropped. It fires no model events and does not set
  /// updated_at. With [OrmFlags.incrementFiresEvents] it fires saving,
  /// updating, updated and saved like save(), and sets updated_at.
  ///
  /// ponytail: a model made by an old dox_builder has no
  /// [setColumnValue], so its field keeps the old value. Run build_runner
  /// again, or read the model again to see the new value. A field that
  /// is null (eg. not in a select()) stays null.
  @override
  Future<int> increment(
    String column, [
    num amount = 1,
    Map<String, dynamic> extra = const <String, dynamic>{},
  ]) {
    return _step(column, amount, extra, true);
  }

  /// take [amount] from [column] in one query, like [increment]
  ///
  /// ```
  /// Product? product = await Product().find(1);
  /// await product!.decrement('stock');
  /// ```
  @override
  Future<int> decrement(
    String column, [
    num amount = 1,
    Map<String, dynamic> extra = const <String, dynamic>{},
  ]) {
    return _step(column, amount, extra, false);
  }

  /// the query form, or this row only when the model is from the table
  Future<int> _step(
    String column,
    num amount,
    Map<String, dynamic> extra,
    bool up,
  ) {
    extra = _onlyFillable(extra);
    if (tempIdValue != null) {
      return _stepThisRecord(column, amount, extra, up);
    }
    _needKeyOrWhere(up ? 'increment' : 'decrement');
    return up
        ? super.increment(column, amount, extra)
        : super.decrement(column, amount, extra);
  }

  /// increment or decrement this row, then set the fields to the new
  /// values when the row changed
  Future<int> _stepThisRecord(
    String column,
    num amount,
    Map<String, dynamic> extra,
    bool up,
  ) async {
    bool flag = SqlQueryBuilder().flags.incrementFiresEvents;
    bool events = flag && _eventsOn;
    if (events) {
      try {
        await _fire(ModelEvent.saving);
        await _fire(ModelEvent.updating);
      } on CancelModelEvent {
        return 0;
      }
    }
    String? updatedAtColumn = timestampsColumn['updated_at'];
    if (flag &&
        updatedAtColumn != null &&
        !extra.containsKey(updatedAtColumn)) {
      extra = <String, dynamic>{...extra, updatedAtColumn: now()};
    }
    int count = await _stepRow(column, amount, extra, up);
    if (events && count > 0) {
      await _fire(ModelEvent.updated);
      await _fire(ModelEvent.saved);
    }
    return count;
  }

  Future<int> _stepRow(
    String column,
    num amount,
    Map<String, dynamic> extra,
    bool up,
  ) async {
    QueryBuilder<T> row = _thisRecord();
    int count = up
        ? await row.increment(column, amount, extra)
        : await row.decrement(column, amount, extra);
    if (count == 0) return count;

    Map<String, dynamic> values = <String, dynamic>{...extra};
    dynamic old = columnsToMap()[column];
    if (old is num) {
      /// int + int stays an int, so an int field takes it
      values[column] = up ? old + amount : old - amount;
    }

    /// like update(): also for a custom column that setColumnValue does
    /// not know
    String? updatedAtColumn = timestampsColumn['updated_at'];
    if (SqlQueryBuilder().flags.incrementFiresEvents &&
        updatedAtColumn != null) {
      dynamic given = values[updatedAtColumn];
      DateTime? stamp = given is DateTime
          ? given
          : DateTime.tryParse('${given ?? ''}');
      if (stamp != null) updatedAt = stamp;
    }
    _setSavedColumns(values);
    return count;
  }

  /// set the fields of [values] (column name => value) and mark them as
  /// saved, so save() does not send them again. a column that
  /// [setColumnValue] does not take is skipped. The updated_at column
  /// is kept too: the caller set the updatedAt field, also for a custom
  /// column that setColumnValue does not know. Else the next save()
  /// sees a changed time and keeps the old one.
  void _setSavedColumns(Map<String, dynamic> values) {
    String? updatedAtColumn = timestampsColumn['updated_at'];
    List<String> done = <String>[
      for (MapEntry<String, dynamic> e in values.entries)
        if (setColumnValue(e.key, e.value) || e.key == updatedAtColumn) e.key,
    ];

    /// a model that was not read or saved keeps exists false
    if (done.isEmpty || !exists) return;
    Map<String, dynamic> map = columnsToMap();
    Map<String, dynamic> old = _savedValues ?? originalMap;
    _savedValues = <String, dynamic>{
      ...old,
      for (String key in done) key: map[key],
    };

    /// like save(): only the columns that got another value
    _lastChanges = <String, dynamic>{
      for (String key in done)
        if (!_sameValue(values[key], old[key])) key: values[key],
    };
  }

  /// set the Dart field of [column] (the column name, like `view_count`)
  /// to [value]. It returns true when it set the field, false when the
  /// model has no such column or [value] is not of the field type.
  ///
  /// ```
  /// blog.setColumnValue('view_count', 10); // blog.viewCount = 10
  /// ```
  ///
  /// The generator (dox_builder) overrides it for each @Column. The
  /// default sets nothing and returns false, so models made by an old
  /// generator work as before. increment() and decrement() on a model
  /// use it.
  bool setColumnValue(String column, dynamic value) => false;

  /// set every column field of this model to the field of [other], a
  /// model of the same class. It returns false when it set nothing.
  ///
  /// The generator (dox_builder) overrides it. [refresh] uses it. The
  /// default returns false, so a model made by an old generator works as
  /// before.
  bool $copyColumnsFrom(Model<T> other) => false;

  /// set the fields of [data] (column name => value) and ignore
  /// [fillable] and [guarded]. It does not
  /// save: call save() after it. It returns this model.
  ///
  /// ```
  /// User? user = await User().find(1);
  /// await user!.forceFill({'is_admin': true}).save();
  /// ```
  ///
  /// It uses [setColumnValue]. A key that is not in [tableColumns] is
  /// skipped. An ISO date text sets a `DateTime` field. A value that is
  /// not of the field type throws an [ArgumentError], and so does every
  /// column of a model with no [setColumnValue] (a hand-written model, or
  /// one made by an old dox_builder). Do not pass user input to it.
  Model<T> forceFill(Map<String, dynamic> data) {
    List<String> columns = tableColumns;
    for (MapEntry<String, dynamic> e in data.entries) {
      dynamic value = e.value;
      if (setColumnValue(e.key, value)) continue;
      DateTime? date = value is String ? DateTime.tryParse(value) : null;
      if (date != null && setColumnValue(e.key, date)) continue;
      if (columns.isNotEmpty && !columns.contains(e.key)) continue;
      throw ArgumentError.value(
        value,
        e.key,
        'forceFill() can not set this column of $runtimeType: the value is '
        'not of the field type, or the model has no setColumnValue() '
        '(a hand-written model, or one made by an old dox_builder: run '
        'build_runner again)',
      );
    }
    return this;
  }

  /// a write on a model with no primary key value and no where() would
  /// change every row of the table. It throws a [StateError] then, and
  /// runs no query.
  ///
  /// onlyTrashed() counts as a where: it picks only the soft deleted rows.
  /// A global scope that adds a condition counts too, so
  /// `Post().delete()` under a tenant scope deletes the tenant's rows. It
  /// does not count on a model read without its key: that model means
  /// one row, not every row in the scope.
  void _needKeyOrWhere(String method) {
    if (hasWhere || trashedOnly) return;
    if (!exists) {
      applyGlobalScopes();
      if (hasWhere) return;
    }
    throw StateError(
      '$method() was called on a model with no primary key value and no '
      'where(), so it would change every row. Use where() to pick the '
      "rows, or whereRaw('1 = 1') to change every row on purpose.",
    );
  }

  /// a new query on this row only, so the query state of this model
  /// (where, values of an old query) is not used again
  QueryBuilder<T> _thisRecord() {
    return _newQuery<T>(this).where(primaryKey, tempIdValue);
  }

  /// a new query on the table of this model, on the same connection.
  /// [self] is the model the query returns, null gives maps.
  QueryBuilder<R> _newQuery<R>([dynamic self]) {
    QueryBuilder<R> q = QueryBuilder<R>()
      ..tableName = tableName
      ..self = self
      ..primaryKey = primaryKey
      ..connection = connection;
    return q.debug(_debug);
  }

  /// restore this soft deleted record. It fires restoring and restored.
  ///
  /// ```
  /// Blog? blog = await Blog().withTrash().find(1);
  /// await blog?.restore();
  /// ```
  ///
  /// On a query, like `Blog().where('status', 'old').restore()`, it
  /// restores every soft deleted row of the query, with no events.
  /// It returns true when it changed a row. With no where(), it
  /// throws a [StateError], so it can not restore every row by mistake.
  @override
  Future<bool> restore() async {
    if (tempIdValue == null) {
      _needKeyOrWhere('restore');
      withTrash();

      /// only deleted rows, so every database counts the same rows (MySQL
      /// counts only changed rows, Postgres and SQLite every matched row).
      /// the UPDATE runs on the real table, so no alias of fromSub().
      whereNotNull('$tableName.deleted_at');

      /// super.update(): deleted_at is not checked against fillable
      return await super.update(_restoreValues()) > 0;
    }
    bool events = _eventsOn;
    if (events) {
      try {
        await _fire(ModelEvent.restoring);
      } on CancelModelEvent {
        return false;
      }
    }
    Map<String, dynamic> values = _restoreValues();
    await _thisRecord().update(values);
    _setSoftDeleteFields(values);
    if (events) await _fire(ModelEvent.restored);
    return true;
  }

  /// set updated_at (or [column]) to now, and return how many rows
  /// changed.
  ///
  /// ```
  /// Blog? blog = await Blog().find(1);
  /// await blog!.touch();
  /// await blog.touch('published_at');
  ///
  /// await Blog().where('status', 'draft').touch();
  /// ```
  ///
  /// On a model from the table it changes only that row, and it sets
  /// the field too. It fires saving, updating, updated and saved, like
  /// save(). It returns 0 when a hook throws [CancelModelEvent]. Use
  /// [touchQuietly] for no events.
  ///
  /// As a query, like `Blog().where('status', 'draft').touch()`, it
  /// changes every row of the query, and fires no events.
  ///
  /// On a model that has no primary key value (never saved, or read
  /// without the key) and no where(), it throws a [StateError], so it
  /// can not change every row by mistake.
  ///
  /// It returns 0 when the model has no updated_at column and no
  /// [column] is given.
  @override
  Future<int> touch([String? column]) async {
    String? updatedAtColumn = timestampsColumn['updated_at'];
    column ??= updatedAtColumn;
    if (column == null) return 0;
    if (tempIdValue == null) {
      _needKeyOrWhere('touch');
      return await super.touch(column);
    }
    bool events = _eventsOn;
    if (events) {
      try {
        await _fire(ModelEvent.saving);
        await _fire(ModelEvent.updating);
      } on CancelModelEvent {
        return 0;
      }
    }
    Map<String, dynamic> values = <String, dynamic>{column: now()};
    int count = await _thisRecord().update(values);
    if (count > 0) {
      if (column == updatedAtColumn) updatedAt = values[column];
      _setSavedColumns(values);
    }
    if (events) {
      await _fire(ModelEvent.updated);
      await _fire(ModelEvent.saved);
    }
    return count;
  }

  /// [touch] without model events
  ///
  /// ```
  /// await blog.touchQuietly();
  /// ```
  Future<int> touchQuietly([String? column]) {
    return withoutEvents(() => touch(column));
  }

  /// a new model with the column values of this model, not saved yet.
  /// It has no primary key, created_at and updated_at, so save()
  /// inserts a new row. The [except] columns are left out (set to
  /// null). Relations are not copied. It copies
  /// deleted_at, so a copy of a soft deleted model is soft deleted too.
  ///
  /// ```
  /// Blog? blog = await Blog().find(1);
  /// Blog copy = blog!.replicate()..title = 'Copy of ${blog.title}';
  /// await copy.save();
  ///
  /// Blog other = blog.replicate(<String>['slug']);
  /// ```
  ///
  /// It throws an [ArgumentError] when a column in [except] can not be
  /// null, or is not a column of the model.
  T replicate([List<String> except = const <String>[]]) {
    Model<T> model = fromMap(_dateTimesToString(columnsToMap())) as Model<T>
      ..tempIdValue = null
      ..createdAt = null
      ..updatedAt = null;
    for (String column in except) {
      if (!model.setColumnValue(column, null)) {
        throw ArgumentError.value(
          column,
          'except',
          'is not a column of $runtimeType that can be null',
        );
      }
    }
    model.debug(_debug);
    model.connection = connection;
    return model as T;
  }

  /// start ********** events

  /// true when the model class declares an on... hook.
  /// The generator sets it, so models without hooks skip all event work.
  bool get hasModelHooks => false;

  static Map<Type, List<ModelObserver<dynamic>>>? _observers;

  static final Object _quietKey = Object();

  /// add an observer for the model [M]. Observers run in the order
  /// they are added, after the model's own hook.
  ///
  /// ```
  /// Model.observe<User>(UserObserver());
  /// ```
  static void observe<M>(ModelObserver<M> observer) {
    (_observers ??= <Type, List<ModelObserver<dynamic>>>{})
        .putIfAbsent(M, () => <ModelObserver<dynamic>>[])
        .add(observer);
  }

  /// remove the observers of [M], or of every model when [M] is not given
  static void forgetObservers<M>() {
    if (M == dynamic) {
      _observers = null;
    } else {
      _observers?.remove(M);
      if (_observers?.isEmpty == true) _observers = null;
    }
  }

  /// run [callback] without firing model events
  ///
  /// ```
  /// await Model.withoutEvents(() => user.save());
  /// ```
  static Future<R> withoutEvents<R>(FutureOr<R> Function() callback) async {
    return await runZoned(
      callback,
      zoneValues: <Object, Object>{_quietKey: true},
    );
  }

  bool get _eventsOn =>
      (hasModelHooks || _observers?[runtimeType] != null) &&
      Zone.current[_quietKey] != true;

  Future<void> _fire(ModelEvent event) async {
    if (hasModelHooks) await _hook(event);
    List<ModelObserver<dynamic>>? list = _observers?[runtimeType];
    if (list == null) return;
    for (ModelObserver<dynamic> observer in list) {
      await observer.handle(event, this);
    }
  }

  /// the trashed event: not a [ModelEvent] value, so a switch on
  /// [ModelEvent] in an app keeps working. Observers get it only with
  /// [TrashedObserver].
  Future<void> _fireTrashed() async {
    if (hasModelHooks) await onTrashed();
    List<ModelObserver<dynamic>>? list = _observers?[runtimeType];
    if (list == null) return;
    for (ModelObserver<dynamic> observer in list) {
      if (observer is TrashedObserver) {
        await (observer as TrashedObserver<dynamic>).onTrashed(this);
      }
    }
  }

  FutureOr<void> _hook(ModelEvent event) {
    switch (event) {
      case ModelEvent.saving:
        return onSaving();
      case ModelEvent.saved:
        return onSaved();
      case ModelEvent.creating:
        return onCreating();
      case ModelEvent.created:
        return onCreated();
      case ModelEvent.updating:
        return onUpdating();
      case ModelEvent.updated:
        return onUpdated();
      case ModelEvent.deleting:
        return onDeleting();
      case ModelEvent.deleted:
        return onDeleted();
      case ModelEvent.restoring:
        return onRestoring();
      case ModelEvent.restored:
        return onRestored();
      case ModelEvent.forceDeleting:
        return onForceDeleting();
      case ModelEvent.forceDeleted:
        return onForceDeleted();
    }
  }

  // ponytail: named on... and not creating/deleted,
  // because deleted/created are common column names.
  FutureOr<void> onSaving() {}
  FutureOr<void> onSaved() {}
  FutureOr<void> onCreating() {}
  FutureOr<void> onCreated() {}
  FutureOr<void> onUpdating() {}
  FutureOr<void> onUpdated() {}
  FutureOr<void> onDeleting() {}
  FutureOr<void> onDeleted() {}
  FutureOr<void> onRestoring() {}
  FutureOr<void> onRestored() {}
  FutureOr<void> onForceDeleting() {}
  FutureOr<void> onForceDeleted() {}

  /// after a soft delete of this model, after onDeleted()
  FutureOr<void> onTrashed() {}

  /// end ********** events

  /// Reload eager relationship after new record created/updated.
  /// await Blog().reload()
  Future<void> reload() async {
    await initPreload(<Model<T>>[this]);
  }

  /// start ********** dirty tracking

  /// the values of the row as it was last read or saved, by column name.
  /// Empty for a new model.
  Map<String, dynamic> get _original => _savedValues ?? originalMap;

  /// the columns that changed since the model was read or saved, with
  /// their new values. Keys are column names, like `body`, not the Dart
  /// field names. A new model gives every column that has a value.
  ///
  /// ```
  /// Blog? blog = await Blog().find(1);
  /// blog!.title = 'New title';
  /// print(blog.getDirty()); // {title: New title}
  /// ```
  Map<String, dynamic> getDirty() {
    Map<String, dynamic> original = _original;
    return <String, dynamic>{
      for (MapEntry<String, dynamic> e in columnsToMap().entries)
        if (!_sameValue(e.value, original[e.key])) e.key: e.value,
    };
  }

  /// true when a column changed since the model was read or saved.
  /// [columns] is one column name or a list of them. With no
  /// [columns], any column counts.
  ///
  /// ```
  /// blog.title = 'New title';
  /// blog.isDirty(); // true
  /// blog.isDirty('title'); // true
  /// blog.isDirty(<String>['body', 'slug']); // false
  /// ```
  bool isDirty([Object? columns]) => _anyOf(getDirty(), columns);

  /// the opposite of [isDirty]
  ///
  /// ```
  /// blog.isClean('title'); // false after blog.title = 'New title'
  /// ```
  bool isClean([Object? columns]) => !isDirty(columns);

  /// the value of [column] as it was last read or saved, or all of
  /// them when no [column] is given. A new model gives null (or `{}`).
  ///
  /// ```
  /// blog.title = 'New title';
  /// print(blog.getOriginal('title')); // the old title
  /// ```
  dynamic getOriginal([String? column]) {
    Map<String, dynamic> original = _original;
    return column == null ? <String, dynamic>{...original} : original[column];
  }

  /// the columns that the last save() changed, with their new values.
  /// update(), increment(), decrement(), touch(), restore() and a soft
  /// delete on this model count as a save too. Empty after an insert,
  /// or a save with no changes.
  ///
  /// ```
  /// blog.title = 'New title';
  /// await blog.save();
  /// print(blog.getChanges()); // {title: New title, updated_at: ...}
  /// ```
  Map<String, dynamic> getChanges() => <String, dynamic>{..._lastChanges};

  /// true when the last save() changed a column. [columns] is one
  /// column name or a list of them, like [isDirty].
  ///
  /// ```
  /// await blog.save();
  /// if (blog.wasChanged('status')) notify(blog);
  /// ```
  bool wasChanged([Object? columns]) => _anyOf(_lastChanges, columns);

  /// true when [map] has [columns] (a name or a list of names), or any
  /// key when [columns] is null
  static bool _anyOf(Map<String, dynamic> map, Object? columns) {
    if (columns == null) return map.isNotEmpty;
    if (columns is String) return map.containsKey(columns);
    if (columns is Iterable<Object?>) return columns.any(map.containsKey);
    throw ArgumentError.value(
      columns,
      'columns',
      'must be a column name or a list of column names',
    );
  }

  /// true when the model value [a] is the same as the saved value [b].
  /// Unlike [_same], a map or a list is compared by its JSON, and a
  /// time by its moment.
  static bool _sameValue(dynamic a, dynamic b) {
    if (a is TypedData || b is TypedData) {
      return a is TypedData && b is TypedData && _sameBytes(a, b);
    }
    if (a is DateTime || b is DateTime) return _sameTime(a, b);
    if (a is Map || a is List || b is Map || b is List) {
      return _json(a) == _json(b);
    }
    return _same(a, b);
  }

  /// true when [a] and [b] hold the same bytes
  static bool _sameBytes(TypedData a, TypedData b) {
    if (identical(a, b)) return true;
    if (a.lengthInBytes != b.lengthInBytes) return false;
    Uint8List x = a.buffer.asUint8List(a.offsetInBytes, a.lengthInBytes);
    Uint8List y = b.buffer.asUint8List(b.offsetInBytes, b.lengthInBytes);
    for (int i = 0; i < x.length; i++) {
      if (x[i] != y[i]) return false;
    }
    return true;
  }

  /// [value] as JSON text. A text stays as it is (a JSON column can be
  /// read as text).
  static String _json(dynamic value) {
    if (value is String) return value;
    try {
      return jsonEncode(value);
    } catch (_) {
      return '$value';
    }
  }

  /// end ********** dirty tracking

  /// read the columns of this row from the database again, set the
  /// fields to them, and load the relations again like [reload]. The
  /// model is clean after it. It returns this model.
  ///
  /// ```
  /// Blog? blog = await Blog().find(1);
  /// // ... another request changes the row
  /// await blog!.refresh();
  /// ```
  ///
  /// It reads the row by its primary key from the write database, on the
  /// connection of the model. It finds a soft deleted row too, and global
  /// scopes are not used: the model already is that row.
  ///
  /// It throws a [StateError] on a model that is not in the table (no
  /// primary key value), and a [ModelNotFoundException] when the row is
  /// gone. A model made by an old dox_builder can not set a column with
  /// a cast or a beforeGet from the row: then it throws a [StateError]
  /// and changes nothing. Run build_runner again, or use [fresh].
  Future<T> refresh() async {
    if (tempIdValue == null || !exists) {
      throw StateError(
        'refresh() needs a model that is in the table, with a primary key '
        'value. This $runtimeType was not read or saved.',
      );
    }
    T? found = await _newQuery<T>(this).onWriteConnection().find(tempIdValue);
    if (found == null) {
      throw ModelNotFoundException(
        tableName,
        id: tempIdValue,
        column: primaryKey,
      );
    }
    Model<T> row = found as Model<T>;
    Map<String, dynamic> raw = row.originalMap;
    if (!$copyColumnsFrom(row)) _setFromRow(row);
    originalMap = raw;
    _savedValues = null;
    _lastChanges = const <String, dynamic>{};
    await reload();
    return this as T;
  }

  /// set the fields from the columns of [row] with [setColumnValue], for
  /// a model made by an old dox_builder (no [$copyColumnsFrom]). It
  /// throws a [StateError] and changes nothing when a column can not be
  /// set.
  void _setFromRow(Model<T> row) {
    Map<String, dynamic> raw = row.originalMap;
    Map<String, dynamic> want = row.columnsToMap();

    /// try it on the new row first: when a column can not be set to the
    /// same value, this model is not changed. The key and the timestamps
    /// are set below, by their own fields.
    Set<String?> own = <String?>{primaryKey, ...timestampsColumn.values};
    List<String> columns = <String>[
      for (String column in want.keys)
        if (raw.containsKey(column) && !own.contains(column)) column,
    ];
    List<String> failed = <String>[
      for (String column in columns)
        if (!row._setRaw(column, raw[column])) column,
    ];
    Map<String, dynamic> got = row.columnsToMap();
    failed.addAll(<String>[
      for (String column in columns)
        if (!failed.contains(column) && !_sameValue(got[column], want[column]))
          column,
    ]);
    if (failed.isNotEmpty) {
      throw StateError(
        'refresh() can not set the columns $failed of $runtimeType from the '
        'row: they have a cast or a beforeGet, and the model was made by an '
        'old dox_builder. Run build_runner again, or use fresh() to get a '
        'new model.',
      );
    }
    for (String column in columns) {
      _setRaw(column, raw[column]);
    }
    tempIdValue = row.tempIdValue;
    createdAt = row.createdAt;
    updatedAt = row.updatedAt;
  }

  /// set the field of [column] to [value] from a row. A date text sets
  /// a `DateTime` field, like [forceFill].
  /// It returns false when it could not set the field.
  bool _setRaw(String column, dynamic value) {
    if (setColumnValue(column, value)) return true;
    DateTime? date = value is String ? DateTime.tryParse(value) : null;
    return date != null && setColumnValue(column, date);
  }

  /// a new model with this row as it is in the database now, with the
  /// relations of this model. This model does not change. It gives null
  /// when the row is gone, or the model is not in the table yet.
  ///
  /// ```
  /// Blog? blog = await Blog().find(1);
  /// Blog? now = await blog!.fresh();
  /// ```
  ///
  /// It reads the row like [refresh]: by primary key, from the write
  /// database, also when it is soft deleted, and with no global scopes.
  Future<T?> fresh() async {
    if (!exists) return null;
    return await _findRow(tempIdValue);
  }

  /// support jsonEncode()
  ///
  /// ```
  /// Blog? blog = Blog().find(1);
  /// Map<String, dynamic> m = blog?.toJson();
  /// ```
  ///
  /// A model read by a `@ManyToMany` relation also has a `pivot` key with
  /// its [ManyToManyWrites.pivot] values. Put `'pivot'` in
  /// [hidden] to leave it out. A model with its own `pivot` column (or
  /// relation) keeps that value in the key: the pivot values are then
  /// only in [ManyToManyWrites.pivot].
  Map<String, dynamic> toJson() {
    Map<String, dynamic> data = toMap(removeHiddenField: true);
    if (manyToManyRow[this] != null && !data.containsKey('pivot')) {
      data['pivot'] = <String, dynamic>{
        for (MapEntry<String, dynamic> e in pivot.entries)
          e.key: e.value is DateTime
              ? (e.value as DateTime).toIso8601String()
              : e.value,
      };
    }

    /// again after pivot, and for a toMap() override that did not
    /// remove the hidden fields
    _removeHidden(data);
    return data;
  }

  /// convert model to map
  /// if you have custom select query, use original option with true value
  ///
  /// ```
  /// Blog? blog = Blog().find(1);
  /// Map<String, dynamic> m = blog?.toMap();
  /// Map<String, dynamic> m = blog?.toMap(original: true);
  /// ```
  Map<String, dynamic> toMap({
    bool original = false,
    bool removeHiddenField = false,
    bool removeRelations = false,
  }) {
    if (removeRelations == true) {
      return columnsToMap();
    }
    if (original == true && originalMap.isNotEmpty) {
      return _originalWithDateStrings();
    }
    Map<String, dynamic> data = convertToMap(this);
    setComputedValues(data);
    Map<String, dynamic>? aggregates = _aggregates;
    if (aggregates != null) data.addAll(aggregates);
    if (removeHiddenField) _removeHidden(data);
    return data;
  }

  /// the columns of this model, without relations.
  /// the generator overrides it with a map of the columns only.
  Map<String, dynamic> columnsToMap() {
    Set<String> columns = tableColumns.toSet();
    return convertToMap(this)
      ..removeWhere((String key, _) => !columns.contains(key));
  }

  /// true when fromMap() takes the DateTime values of a row as they are.
  /// The generator sets it when no column has beforeGet, so the rows of
  /// this model skip the date to string step.
  bool get readsRowDates => false;

  /// the row this model was made from, with dates as iso strings like
  /// before. a copy is made only when the row has a DateTime.
  Map<String, dynamic> _originalWithDateStrings() {
    Map<String, dynamic> row = originalMap;
    for (dynamic value in row.values) {
      if (value is DateTime) {
        return <String, dynamic>{
          for (MapEntry<String, dynamic> e in row.entries)
            e.key: e.value is DateTime
                ? (e.value as DateTime).toIso8601String()
                : e.value,
        };
      }
    }
    return row;
  }

  /// values of withCount(), withSum(), withMax() and the other with...()
  /// aggregates, by result key
  Map<String, dynamic>? _aggregates;

  /// sets a value of withCount(), withSum(), withMax() and the others.
  /// a number in a text (like a MySQL decimal) becomes a number.
  void setAggregate(String key, dynamic value) {
    (_aggregates ??= <String, dynamic>{})[key] = value is String
        ? num.tryParse(value) ?? value
        : value;
  }

  /// the number of related rows from withCount([relation])
  ///
  /// ```
  /// User? user = await User().withCount('posts').find(1);
  /// int posts = user!.countOf('posts');
  /// ```
  int countOf(String relation) {
    dynamic value = _aggregates?['${helper.toSnakeCase(relation)}_count'];
    return value is num ? value.toInt() : 0;
  }

  /// a value of withCount(), withSum(), withAvg(), withMin(), withMax()
  /// or withExists() by its result key, like `posts_count`,
  /// `posts_sum_views` or `posts_exists`
  dynamic aggregate(String key) => _aggregates?[key];

  /// adds the @Computed getters to [map].
  /// the generator overrides it only for models that have them.
  void setComputedValues(Map<String, dynamic> map) {}

  /// start ********** preload

  List<String> get preloadList => <String>[]; // coverage:ignore-line
  List<String> get customPreloadList =>
      _preloads ?? const <String>[]; // coverage:ignore-line

  /// made on the first preload(), most models never call it
  List<String>? _preloads;

  /// the dot paths of preload(), like `posts.comments`, and the names
  /// with a where, each with its where. null when there is none, so a
  /// plain preload() does no more work.
  List<(String, _PreloadWhere?)>? _preloadPaths;

  /// copies the preload() names and paths of [query] to this row, so
  /// toJson() and reload() of the row know them. get() calls it for each
  /// row of a query with preload().
  void $copyPreloads(Model<dynamic> query) {
    List<String>? names = query._preloads;
    if (names != null) _preloads = List<String>.of(names);
    List<(String, _PreloadWhere?)>? paths = query._preloadPaths;
    if (paths != null) {
      _preloadPaths = List<(String, _PreloadWhere?)>.of(paths);
    }
  }

  /// the generator overrides these with the relations of the model
  Map<String, Function> get relationsResultMatcher =>
      _resultMatcher ??= <String, Function>{};
  set relationsResultMatcher(Map<String, Function> value) =>
      _resultMatcher = value;
  Map<String, Function>? _resultMatcher;

  Map<String, Function> get relationsQueryMatcher =>
      _queryMatcher ??= <String, Function>{};
  set relationsQueryMatcher(Map<String, Function> value) =>
      _queryMatcher = value;
  Map<String, Function>? _queryMatcher;

  /// preload relationship
  /// ```
  /// Blog blog = await Blog().preload('comments').find(1);
  /// print(blog.comments);
  /// ```
  ///
  /// A dot path loads relations of the loaded rows too, one query for
  /// each level: `preload('posts.comments')` loads the posts, then the
  /// comments of all those posts. toJson() has both.
  ///
  /// [where] adds conditions to the query of the relation. With a dot
  /// path it is for the last relation of the path:
  ///
  /// ```
  /// await User().preload('posts', (QueryBuilder<dynamic> q) {
  ///   q.where('published', true).orderBy('id');
  /// }).get();
  ///
  /// // all posts, only the approved comments of each post
  /// await User().preload('posts.comments', (QueryBuilder<dynamic> q) {
  ///   q.where('approved', true);
  /// }).get();
  /// ```
  Model<T> preload(
    String key, [
    void Function(QueryBuilder<dynamic> query)? where,
  ]) {
    List<String> names = _preloads ??= <String>[];
    int dot = key.indexOf('.');
    if (dot < 0 && where == null) {
      names.add(key);
      return this;
    }
    String name = dot < 0 ? key : key.substring(0, dot);
    if (!names.contains(name)) names.add(name);
    (_preloadPaths ??= <(String, _PreloadWhere?)>[]).add((key, where));
    return this;
  }

  /// Get relation result
  /// ```
  /// Blog blog = await Blog()find(1);
  /// await blog.$getRelation('comments');
  /// print(blog.comments);
  /// `
  ///
  /// With [OrmFlags.toJsonLoadedRelations], toJson() then has the
  /// relation too, like a name given to [preload].
  Future<M?> $getRelation<M>(String name) async {
    M? result = await _getRelation(<Model<T>>[this], name) as M;
    if (SqlQueryBuilder().flags.toJsonLoadedRelations &&
        relationsResultMatcher[name] != null) {
      List<String> names = _preloads ??= <String>[];
      if (!names.contains(name)) names.add(name);
    }
    return result;
  }

  /// Get relation query
  /// ```
  /// Blog blog = await Blog()find(1);
  /// Comment comment = blog.related<Comment>('comments');
  /// await comment.get();
  /// `
  M? related<M>(String name) {
    if (relationsQueryMatcher[name] != null) {
      Function funcName = relationsQueryMatcher[name]!;
      return Function.apply(funcName, <dynamic>[
        <Model<T>>[this],
      ]);
    }
    return null;
  }

  Future<void> _getRelation(List<Model<T>> i, String name) async {
    Function? funcName = relationsResultMatcher[name];
    if (funcName == null) return;
    if (_preloadPaths == null) {
      return await Function.apply(funcName, <dynamic>[i]);
    }

    /// the relation query is made before the first await of funcName,
    /// so it takes [preloadQuery] while it is set
    preloadQuery = (QueryBuilder<dynamic> q) => _onRelationQuery(name, q);
    Future<dynamic> load;
    try {
      load = Function.apply(funcName, <dynamic>[i]) as Future<dynamic>;
    } finally {
      preloadQuery = null;
    }
    return await load;
  }

  /// adds the wheres and the nested paths of relation [name] to its
  /// query [q]
  void _onRelationQuery(String name, QueryBuilder<dynamic> q) {
    String prefix = '$name.';
    for ((String, _PreloadWhere?) p in _preloadPaths!) {
      String path = p.$1;
      if (path == name) {
        p.$2?.call(q);
      } else if (path.startsWith(prefix)) {
        String rest = path.substring(prefix.length);
        if (_otherMorphTypeHas(q as Model<dynamic>, rest)) continue;
        q.preload(rest, p.$2);
      }
    }
  }

  /// true when [q] is the query of one type of a morphTo, it does not
  /// have the first relation of [path], and another type does. Then
  /// [q] skips the path. When no type has it, it is a typo: [q] keeps
  /// it, so [OrmFlags.preloadUnknownThrows] can throw.
  bool _otherMorphTypeHas(Model<dynamic> q, String path) {
    List<Model<dynamic>>? types = morphTypeQueries;
    if (types == null) return false;
    int dot = path.indexOf('.');
    String name = dot < 0 ? path : path.substring(0, dot);
    if (q.relationsResultMatcher[name] != null) return false;
    for (Model<dynamic> t in types) {
      if (t.relationsResultMatcher[name] != null) return true;
    }
    return false;
  }

  @override
  List<String> getPreload() {
    List<String> list = preloadList;
    List<String>? custom = _preloads;
    if (custom == null) return list;
    return <String>{...list, ...custom}.toList();
  }

  @override
  Future<void> initPreload(List<Model<T>> list) async {
    List<String> pList = getPreload();
    if (pList.isNotEmpty && SqlQueryBuilder().flags.preloadUnknownThrows) {
      for (String key in pList) {
        if (relationsResultMatcher[key] == null) {
          throw ArgumentError.value(
            key,
            'relation',
            'is not a relation of $runtimeType',
          );
        }
      }
    }
    if (list.isEmpty) return;

    /// in a transaction the queries run one by one on one connection.
    /// outside, they run together, so the native drivers can send them
    /// in one batch.
    if (pList.length < 2 || DBDriver.inTransaction) {
      for (String key in pList) {
        await _getRelation(list, key);
      }
      return;
    }
    await Future.wait(<Future<void>>[
      for (String key in pList) _getRelation(list, key),
    ]);
  }

  /// create a record
  /// ```
  /// Blog blog = await Blog().create({
  ///   "title" : "Blog title",
  ///   "body" : "Lorem",
  /// });
  /// ````
  ///
  /// create() works like save() on a new model. It fills a new model
  /// from [data], so only @Column fields are saved, and beforeSave and
  /// the casts run. It sets created_at and updated_at when the model has
  /// timestamps and [data] has no value for them. Null values are not
  /// sent, so the column default is used. With
  /// [OrmFlags.createWritesNull], a key that is null in [data] is
  /// written as NULL.
  ///
  /// When the model has events, it calls save(), so the hooks run. When
  /// a hook cancels, it returns the unsaved model (its id is null).
  ///
  /// It never gives a map. When the new row can not be read (MySQL, no
  /// auto increment and no id in [data]), it gives a model made from
  /// [data], see [insert].
  @override
  Future<T> create(Map<String, dynamic> data) async {
    Map<String, dynamic> fill = _onlyFillable(data);
    Model<T> model = _newModel(fill);
    if (SqlQueryBuilder().flags.createWritesNull) {
      model._createNullKeys = <String>{
        for (MapEntry<String, dynamic> e in fill.entries)
          if (e.value == null) e.key,
      };
    }
    if (!_eventsOn) {
      T row = await super.insert(model._newRowValues(model._createNullKeys));
      if (row is Model) row._wasRecentlyCreated = true;
      return row;
    }
    if (!await model.save()) return model as T;
    T row = await _readBack(model);
    (row as Model<T>)._wasRecentlyCreated = true;
    return row;
  }

  /// a new model, not saved yet, made from [data]
  Model<T> _newModel(Map<String, dynamic> data) {
    /// a column that is not in [data] takes the value of this new model,
    /// like `bool done = false`. fromMap() needs a value for a field
    /// that is not nullable.
    if (!exists) {
      data = <String, dynamic>{...columnsToMap()..remove(primaryKey), ...data};
    }
    Model<T> model = fromMap(_dateTimesToString(data)) as Model<T>;
    model.debug(_debug);
    model.connection = connection;
    return model;
  }

  /// [model] as it is in the table now, read on a new query (no where,
  /// no global scopes) with the relations of this model. [model] itself
  /// when the row can not be read.
  Future<T> _readBack(Model<T> model) async {
    return await _findRow(model.tempIdValue) ?? model as T;
  }

  /// the row with primary key [id], read on a new query (no where, no
  /// global scopes, soft deleted rows too) from the write database, with
  /// the relations of this model. null when there is no such row.
  Future<T?> _findRow(dynamic id) async {
    if (id == null) return null;
    // the write database: a read replica may not have the row yet
    T? row = await _newQuery<T>(this).onWriteConnection().find(id);
    if (row == null) return null;
    if (getPreload().isNotEmpty) await initPreload(<Model<T>>[row as Model<T>]);
    return row;
  }

  /// the first row that matches all [where] pairs, or a new model made
  /// from [where] and [values] that is not saved yet. Keys that
  /// [fillable] and [guarded] do not allow are not set on the new model.
  ///
  /// ```
  /// User user = await User().firstOrNew({'email': 'ann@example.com'});
  /// if (!user.exists) await user.save();
  /// ```
  @override
  Future<T> firstOrNew(
    Map<String, dynamic> where, [
    Map<String, dynamic> values = const <String, dynamic>{},
  ]) async {
    checkNoUnion(this, 'firstOrNew');
    for (MapEntry<String, dynamic> e in where.entries) {
      this.where(e.key, e.value);
    }
    T? found = await getFirst();
    if (found != null) return found;
    return _newModel(_onlyFillable(<String, dynamic>{...where, ...values}))
        as T;
  }

  /// update the first row that matches all [where] pairs with [values],
  /// or create one from [where] and [values]. It returns the model as it
  /// is in the table.
  ///
  /// ```
  /// User user = await User().updateOrCreate(
  ///   {'email': 'ann@example.com'},
  ///   {'name': 'Ann'},
  /// );
  /// ```
  ///
  /// Both ways go through save(), so the model events fire (saving,
  /// creating or updating, ...). An update sends only the columns that
  /// changed. Keys that [fillable] and [guarded] do not allow are
  /// dropped. When a hook cancels an update, it returns the model as it
  /// is in the table. When a hook cancels a create, it returns the
  /// unsaved model (its id is null).
  @override
  Future<T> updateOrCreate(
    Map<String, dynamic> where,
    Map<String, dynamic> values,
  ) async {
    checkNoUnion(this, 'updateOrCreate');
    for (MapEntry<String, dynamic> e in where.entries) {
      this.where(e.key, e.value);
    }
    T? found = await getFirst();
    if (found == null) {
      resetSubstitutionValues();
      return await create(<String, dynamic>{...where, ...values});
    }
    Model<T> old = found as Model<T>;

    /// a model with the row and the new values, that knows the old row,
    /// so save() updates it and sends only what changed
    Model<T> model = _newModel(<String, dynamic>{
      ...old.originalMap,
      ..._onlyFillable(values),
    });
    model.originalMap = old.originalMap;
    if (!await model.save()) return found;
    T row = await _readBack(model);
    (row as Model<T>)._lastChanges = model._lastChanges;
    return row;
  }

  /// fromMap() reads dates as strings, like rows from the database
  Map<String, dynamic> _dateTimesToString(Map<String, dynamic> data) {
    return <String, dynamic>{
      for (MapEntry<String, dynamic> e in data.entries)
        e.key: e.value is DateTime
            ? (e.value as DateTime).toIso8601String()
            : e.value,
    };
  }

  /// create() that ignores [fillable] and [guarded]. Do not pass user input to it.
  ///
  /// ```
  /// User user = await User().forceCreate({'name': 'Ann', 'is_admin': true});
  /// ```
  Future<T> forceCreate(Map<String, dynamic> data) {
    return unguarded(() => create(data));
  }

  /// create a record
  /// ```
  /// Blog blog = await Blog().insert({
  ///   "title" : "Blog title",
  ///   "body" : "Lorem",
  /// });
  /// ````
  @override
  Future<T> insert(Map<String, dynamic> data) async {
    return await create(data);
  }

  /// update the rows of this query and return how many rows changed.
  /// keys that [fillable] and [guarded] do not allow are dropped.
  /// nothing runs when no key is left, and it returns 0.
  /// ```
  /// int count = await User().where('id', 1).update(req.body);
  /// ```
  ///
  /// On a model from the table (it has a primary key value and no
  /// where()), it changes only that row, and sets the
  /// fields to the new values. It sets updated_at too, when the model
  /// has timestamps and [data] has no value for it. It runs one query
  /// and fires no model events. Use save() for the events.
  ///
  /// ```
  /// User? user = await User().find(1);
  /// await user!.update({'name': 'Ann'}); // only user 1
  /// ```
  ///
  /// With a where() it does not set updated_at, unless
  /// [OrmFlags.updateSetsUpdatedAt] is on.
  ///
  /// With a where() it does not set updated_at, unless
  /// [OrmFlags.updateSetsUpdatedAt] is on.
  ///
  /// With no primary key value and no where(), it throws a [StateError],
  /// so it can not change every row by mistake. To change every row on
  /// purpose, use `whereRaw('1 = 1')`.
  ///
  /// To set a column that [fillable] does not allow, like `is_admin`,
  /// use [forceUpdate].
  @override
  Future<int> update(Map<String, dynamic> data) async {
    if (tempIdValue != null && !hasWhere) {
      data = _onlyFillable(data);
      if (data.isEmpty) return 0;
      String? updatedAtColumn = timestampsColumn['updated_at'];
      if (updatedAtColumn != null && !data.containsKey(updatedAtColumn)) {
        data = <String, dynamic>{...data, updatedAtColumn: now()};
      }
      int count = await _thisRecord().update(data);
      if (count > 0) {
        /// like save(): also for a custom column that setColumnValue
        /// does not know, and when [data] has the time
        dynamic given = data[updatedAtColumn];
        DateTime? stamp = given is DateTime
            ? given
            : DateTime.tryParse('${given ?? ''}');
        if (stamp != null) updatedAt = stamp;
        _setSavedColumns(data);
      }
      return count;
    }
    _needKeyOrWhere('update');
    data = _onlyFillable(data);
    if (data.isEmpty) return 0;
    String? updatedAtColumn = timestampsColumn['updated_at'];
    if (SqlQueryBuilder().flags.updateSetsUpdatedAt &&
        updatedAtColumn != null &&
        !data.containsKey(updatedAtColumn)) {
      data = <String, dynamic>{...data, updatedAtColumn: now()};
    }
    return await super.update(data);
  }

  /// update() that ignores [fillable] and [guarded]. Do not pass user input to it.
  ///
  /// ```
  /// await User().where('id', 1).forceUpdate({'is_admin': true});
  /// ```
  @override
  Future<int> forceUpdate(Map<String, dynamic> data) {
    return unguarded(() => update(data));
  }

  /// insert or update many rows in one query, see [QueryBuilder.upsert].
  /// keys that [fillable] and [guarded] do not allow are dropped from
  /// each row. created_at and updated_at are set when a row has no value
  /// for them, and an update sets updated_at (not created_at).
  ///
  /// ```
  /// await Flight().upsert(
  ///   [
  ///     {'from': 'Oakland', 'to': 'San Diego', 'price': 99},
  ///   ],
  ///   ['from', 'to'],
  /// );
  /// ```
  ///
  /// It fires no model events.
  @override
  Future<int> upsert(
    List<Map<String, dynamic>> rows,
    List<String> uniqueBy, [
    List<String>? updateColumns,
  ]) {
    String? createdAtColumn = timestampsColumn['created_at'];
    String? updatedAtColumn = timestampsColumn['updated_at'];
    DateTime currentTime = now();
    List<Map<String, dynamic>> list = <Map<String, dynamic>>[
      for (Map<String, dynamic> row in rows)
        <String, dynamic>{
          ?createdAtColumn: currentTime,
          ?updatedAtColumn: currentTime,
          ..._onlyFillable(row),
        },
    ];
    List<String>? update = updateColumns;
    if (update == null && list.isNotEmpty) {
      update = <String>[
        for (String column in list.first.keys)
          if (!uniqueBy.contains(column) && column != createdAtColumn) column,
      ];
    } else if (update != null &&
        update.isNotEmpty &&
        updatedAtColumn != null &&
        !update.contains(updatedAtColumn)) {
      update = <String>[...update, updatedAtColumn];
    }
    return super.upsert(list, uniqueBy, update);
  }

  /// insert rows and skip the ones the database refuses, see
  /// [QueryBuilder.insertOrIgnore]. keys that [fillable] and [guarded] do
  /// not allow are dropped from each row. It fires no model events.
  @override
  Future<int> insertOrIgnore(List<Map<String, dynamic>> rows) async {
    return await super.insertOrIgnore(<Map<String, dynamic>>[
      for (Map<String, dynamic> row in rows) _onlyFillable(row),
    ]);
  }

  /// insert many rows and read nothing back, see
  /// [QueryBuilder.insertMany]. keys that [fillable] and [guarded] do not
  /// allow are dropped from each row. It fires no model events.
  @override
  Future<bool> insertMany(List<Map<String, dynamic>> rows) async {
    return await super.insertMany(<Map<String, dynamic>>[
      for (Map<String, dynamic> row in rows) _onlyFillable(row),
    ]);
  }

  /// insert one row and return its new id, see
  /// [QueryBuilder.insertGetId]. keys that [fillable] and [guarded] do not
  /// allow are dropped first, so the id in [data] is used only when it was
  /// inserted. It fires no model events.
  @override
  Future<dynamic> insertGetId(Map<String, dynamic> data) {
    return super.insertGetId(_onlyFillable(data));
  }

  /// insert many rows. keys that [fillable] and [guarded] do not allow
  /// are dropped from each row.
  @override
  Future<List<Map<String, dynamic>>> insertMultiple(
    List<Map<String, dynamic>> list,
  ) async {
    return await super.insertMultiple(<Map<String, dynamic>>[
      for (Map<String, dynamic> data in list) _onlyFillable(data),
    ]);
  }
}

/// [Model.makeHidden] and [Model.makeVisible] for each model of a list
///
/// ```
/// List<User> users = await User().all();
/// return users.makeVisible(<String>['email']);
/// ```
extension ModelListVisibility<M extends Model<dynamic>> on List<M> {
  /// [Model.makeHidden] on each model. It returns this list.
  List<M> makeHidden(List<String> fields) {
    for (M m in this) {
      m.makeHidden(fields);
    }
    return this;
  }

  /// [Model.makeVisible] on each model. It returns this list.
  List<M> makeVisible(List<String> fields) {
    for (M m in this) {
      m.makeVisible(fields);
    }
    return this;
  }
}
