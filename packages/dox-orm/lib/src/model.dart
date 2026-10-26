import 'dart:async';

import '../dox_orm.dart';

class Model<T> extends QueryBuilder<T> {
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
  /// empty means every column. set it to stop mass assignment, eg. so
  /// `User().create(req.body)` can not set `is_admin`.
  ///
  /// ```
  /// @override
  /// List<String> get fillable => <String>['name', 'email'];
  /// ```
  List<String> get fillable => const <String>[];

  /// columns that create(), insert(), insertMultiple() and update() never
  /// take from a map
  List<String> get guarded => const <String>[];

  /// [data] without the keys that [fillable] and [guarded] do not allow
  Map<String, dynamic> _onlyFillable(Map<String, dynamic> data) {
    List<String> allowed = fillable;
    List<String> blocked = guarded;
    if (allowed.isEmpty && blocked.isEmpty) return data;
    return <String, dynamic>{
      for (MapEntry<String, dynamic> e in data.entries)
        if ((allowed.isEmpty || allowed.contains(e.key)) &&
            !blocked.contains(e.key))
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

    Map<String, dynamic> values = toMap(removeRelations: true);
    DateTime currentTime = now();
    if (!exists) {
      values.removeWhere((String key, dynamic value) => value == null);

      if (createdAtColumn != null) {
        values[createdAtColumn] = currentTime;
        createdAt = values[createdAtColumn];
      }

      if (updatedAtColumn != null) {
        values[updatedAtColumn] = currentTime;
        updatedAt = values[updatedAtColumn];
      }

      /// only the new id is needed, so no select of the new row
      List<Map<String, dynamic>> res = await _newQuery<dynamic>()
          .insertMultiple(<Map<String, dynamic>>[values]);

      /// mysql only returns auto increment ids, so use the given id if any
      tempIdValue =
          (res.isNotEmpty ? res.first[primaryKey] : null) ?? values[primaryKey];
      _savedValues = <String, dynamic>{...values, primaryKey: tempIdValue};
    } else {
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
  @override
  Future<int> delete() async {
    /// a query delete: Blog().where('id', 1).delete()
    if (tempIdValue == null) {
      if (isSoftDeletes) {
        /// super.update(): deleted_at is not checked against fillable
        return await super.update(<String, dynamic>{'deleted_at': now()});
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
    int count = isSoftDeletes
        ? await _thisRecord().update(<String, dynamic>{'deleted_at': now()})
        : await _thisRecord().forceDelete();
    if (events) await _fire(ModelEvent.deleted);
    return count;
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
  /// On a model from the table it changes only that row. Keys of [extra]
  /// that [fillable] and [guarded] do not allow are dropped. It fires no
  /// model events and does not set updated_at.
  ///
  /// ponytail: the Dart field of the model is not changed, because a
  /// model has no setter by column name. Read the model again to see the
  /// new value. save() does not send the old value back, because the
  /// field did not change.
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
      QueryBuilder<T> row = _thisRecord();
      return up
          ? row.increment(column, amount, extra)
          : row.decrement(column, amount, extra);
    }
    return up
        ? super.increment(column, amount, extra)
        : super.decrement(column, amount, extra);
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
  Future<bool> restore() async {
    bool events = _eventsOn;
    if (events) {
      try {
        await _fire(ModelEvent.restoring);
      } on CancelModelEvent {
        return false;
      }
    }
    await _thisRecord().update(<String, dynamic>{'deleted_at': null});
    if (events) await _fire(ModelEvent.restored);
    return true;
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

  /// values of withCount(), withSum() and withMax(), by result key
  Map<String, dynamic>? _aggregates;

  /// sets a value of withCount(), withSum() or withMax(). a number in a
  /// text (like a MySQL decimal) becomes a number.
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

  /// a value of withCount(), withSum() or withMax() by its result key,
  /// like `posts_count` or `posts_sum_views`
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
  /// When the model has events, create() fills a new model from [data]
  /// and calls save(), so the hooks run. Only @Column fields are saved
  /// then. When a hook cancels, it returns the unsaved model (its id is
  /// null).
  ///
  /// It never gives a map. When the new row can not be read (MySQL, no
  /// auto increment and no id in [data]), it gives a model made from
  /// [data], see [insert].
  @override
  Future<T> create(Map<String, dynamic> data) async {
    data = _onlyFillable(data);
    if (!_eventsOn) return await super.insert(data);
    Model<T> model = _newModel(data);
    if (!await model.save()) return model as T;
    return await _readBack(model);
  }

  /// a new model, not saved yet, made from [data]
  Model<T> _newModel(Map<String, dynamic> data) {
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
    T found = await super.firstOrNew(where, values);
    if ((found as Model<T>).exists) return found;
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
  @override
  Future<int> update(Map<String, dynamic> data) async {
    data = _onlyFillable(data);
    if (data.isEmpty) return 0;
    return await super.update(data);
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
