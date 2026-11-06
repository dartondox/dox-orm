import 'dart:async';

import '../dox_orm.dart';
import 'union.dart';

class Model<T> extends QueryBuilder<T> {
  static final Map<String, Model<dynamic> Function()> _morphModels =
      <String, Model<dynamic> Function()>{};
  static final Map<Type, String> _morphNames = <Type, String>{};

  /// the morph map: the type names that polymorphic relations store in
  /// the `<name>_type` column, like Laravel's `Relation::morphMap()`.
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

  /// columns that create(), insert(), insertMultiple() and update() take
  /// from a map.
  ///
  /// A model is guarded by default, like Laravel: with no [fillable] and
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
  /// model, like Laravel's `Model::unguarded()`. create(), update(),
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
    return <String, dynamic>{
      for (MapEntry<String, dynamic> e in data.entries)
        if (!blocked.contains(e.key) &&
            (allowed.contains(e.key) || (allowed.isEmpty && !blockAll)))
          e.key: e.value,
    };
  }

  /// the generator overrides it with the model columns
  List<String> get tableColumns => _tableColumns ??= <String>[];
  set tableColumns(List<String> value) => _tableColumns = value;
  List<String>? _tableColumns;

  bool _debug = SqlQueryBuilder().debug;

  /// values we last saved, so save() can tell when a field was set to null
  Map<String, dynamic>? _savedValues;

  /// true when the row is in the table: the model was read from it, or
  /// saved. save() inserts when it is false, so a model with a key you
  /// set yourself (like a UUID) is inserted, not updated.
  bool get exists => _savedValues != null || originalMap.isNotEmpty;

  @override
  String get tableName => helper.tableNameOf(runtimeType);

  /// the default foreign key that points to this model: the class name
  /// in snake case and `_id`, like Laravel. `User` gives `user_id`, also
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
  /// throws [CancelModelEvent].
  Future<bool> save() async {
    if (!_eventsOn) {
      await _save();
      return true;
    }
    bool isNew = !exists;
    try {
      await _fire(ModelEvent.saving);
      await _fire(isNew ? ModelEvent.creating : ModelEvent.updating);
    } on CancelModelEvent {
      return false;
    }
    await _save();
    await _fire(isNew ? ModelEvent.created : ModelEvent.updated);
    await _fire(ModelEvent.saved);
    return true;
  }

  /// save without firing model events
  Future<void> saveQuietly() => _save();

  Future<void> _save() async {
    String? createdAtColumn = timestampsColumn['created_at'];
    String? updatedAtColumn = timestampsColumn['updated_at'];

    if (!exists) {
      Map<String, dynamic> values = _newRowValues();

      /// only the new id is needed, so no select of the new row
      List<Map<String, dynamic>> res = await _newQuery<dynamic>()
          .insertMultiple(<Map<String, dynamic>>[values]);

      /// mysql only returns auto increment ids, so use the given id if any
      tempIdValue =
          (res.isNotEmpty ? res.first[primaryKey] : null) ?? values[primaryKey];
      _savedValues = <String, dynamic>{...values, primaryKey: tempIdValue};
    } else {
      Map<String, dynamic> values = toMap(removeRelations: true);
      DateTime currentTime = now();
      dynamic id = values[primaryKey];
      values.remove(primaryKey);
      values.remove(createdAtColumn);

      /// only send the columns that changed since the model was read or
      /// saved. a field we never loaded or saved is skipped when it is
      /// null, so a model loaded with select() does not clear the other
      /// columns.
      Map<String, dynamic> saved = _savedValues ?? originalMap;
      values.removeWhere((String key, dynamic value) {
        return key == updatedAtColumn || _same(value, saved[key]);
      });

      /// nothing changed: no query, and updated_at stays as it is
      if (values.isEmpty) return;
      if (updatedAtColumn != null) {
        values[updatedAtColumn] = currentTime;
        updatedAt = currentTime;
      }
      _savedValues = <String, dynamic>{...saved, ...values};

      await _newQuery<T>(this).where(primaryKey, id).update(values);
    }
  }

  /// the columns to insert for this new model: no null values, and
  /// created_at and updated_at set to now when they have no value yet.
  /// It sets the createdAt and updatedAt fields too.
  Map<String, dynamic> _newRowValues() {
    String? createdAtColumn = timestampsColumn['created_at'];
    String? updatedAtColumn = timestampsColumn['updated_at'];
    Map<String, dynamic> values = toMap(removeRelations: true);
    values.removeWhere((String key, dynamic value) => value == null);
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
  /// It fires deleting and deleted. A query delete like
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
    if (events) await _fire(ModelEvent.deleted);
    return count;
  }

  /// the values of a soft delete: deleted_at, and updated_at when the
  /// model has timestamps, like Laravel
  Map<String, dynamic> _softDeleteValues() {
    DateTime time = now();
    String? updatedAtColumn = timestampsColumn['updated_at'];
    return <String, dynamic>{'deleted_at': time, ?updatedAtColumn: time};
  }

  /// the values of a restore: deleted_at null, and updated_at when the
  /// model has timestamps, like Laravel
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
  /// updated_at.
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
    _setSavedColumns(values);
    return count;
  }

  /// set the fields of [values] (column name => value) and mark them as
  /// saved, so save() does not send them again. a column that
  /// [setColumnValue] does not take is skipped.
  void _setSavedColumns(Map<String, dynamic> values) {
    List<String> done = <String>[
      for (MapEntry<String, dynamic> e in values.entries)
        if (setColumnValue(e.key, e.value)) e.key,
    ];

    /// a model that was not read or saved keeps exists false
    if (done.isEmpty || !exists) return;
    Map<String, dynamic> map = columnsToMap();
    _savedValues = <String, dynamic>{
      ...(_savedValues ?? originalMap),
      for (String key in done) key: map[key],
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

  /// set the fields of [data] (column name => value) and ignore
  /// [fillable] and [guarded], like Laravel's `forceFill()`. It does not
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
  /// A global scope that adds a condition counts too, like Laravel, so
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
  /// restores every soft deleted row of the query, with no events, like
  /// Laravel. It returns true when it changed a row. With no where(), it
  /// throws a [StateError], so it can not restore every row by mistake.
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
  /// null). Relations are not copied. Like Laravel, it copies
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

  // ponytail: named on... and not creating/deleted like Laravel,
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

  /// end ********** events

  /// Reload eager relationship after new record created/updated.
  /// await Blog().reload()
  Future<void> reload() async {
    await initPreload(<Model<T>>[this]);
  }

  /// support jsonEncode()
  ///
  /// ```
  /// Blog? blog = Blog().find(1);
  /// Map<String, dynamic> m = blog?.toJson();
  /// ```
  Map<String, dynamic> toJson() {
    Map<String, dynamic> data = toMap(removeHiddenField: true);
    for (String h in hidden) {
      data.remove(h);
    }
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
    if (removeHiddenField) {
      for (String h in hidden) {
        data.remove(h);
      }
    }
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
  Model<T> preload(String key) {
    (_preloads ??= <String>[]).add(key);
    return this;
  }

  /// Get relation result
  /// ```
  /// Blog blog = await Blog()find(1);
  /// await blog.$getRelation('comments');
  /// print(blog.comments);
  /// `
  Future<M?> $getRelation<M>(String name) async {
    return await _getRelation(<Model<T>>[this], name) as M;
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
    if (relationsResultMatcher[name] != null) {
      Function funcName = relationsResultMatcher[name]!;
      return await Function.apply(funcName, <dynamic>[i]);
    }
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
  /// sent, so the column default is used.
  ///
  /// When the model has events, it calls save(), so the hooks run. When
  /// a hook cancels, it returns the unsaved model (its id is null).
  ///
  /// It never gives a map. When the new row can not be read (MySQL, no
  /// auto increment and no id in [data]), it gives a model made from
  /// [data], see [insert].
  @override
  Future<T> create(Map<String, dynamic> data) async {
    Model<T> model = _newModel(_onlyFillable(data));
    if (!_eventsOn) return await super.insert(model._newRowValues());
    if (!await model.save()) return model as T;
    return await _readBack(model);
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
    dynamic id = model.tempIdValue;
    if (id == null) return model as T;
    T? row = await _newQuery<T>(this).find(id);
    if (row == null) return model as T;
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
    return await _readBack(model);
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

  /// create() that ignores [fillable] and [guarded], like Laravel's
  /// `forceCreate()`. Do not pass user input to it.
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
  /// where()), it changes only that row, like Laravel, and sets the
  /// fields to the new values. It sets updated_at too, when the model
  /// has timestamps and [data] has no value for it. It runs one query
  /// and fires no model events. Use save() for the events.
  ///
  /// ```
  /// User? user = await User().find(1);
  /// await user!.update({'name': 'Ann'}); // only user 1
  /// ```
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
      DateTime? time;
      if (updatedAtColumn != null && !data.containsKey(updatedAtColumn)) {
        time = now();
        data = <String, dynamic>{...data, updatedAtColumn: time};
      }
      int count = await _thisRecord().update(data);
      if (count > 0) {
        /// like save(): also for a custom column that setColumnValue
        /// does not know
        if (time != null) updatedAt = time;
        _setSavedColumns(data);
      }
      return count;
    }
    _needKeyOrWhere('update');
    data = _onlyFillable(data);
    if (data.isEmpty) return 0;
    return await super.update(data);
  }

  /// update() that ignores [fillable] and [guarded]. Laravel's query
  /// update works like this. Do not pass user input to it.
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
