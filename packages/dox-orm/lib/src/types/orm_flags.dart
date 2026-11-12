/// opt-in ORM behaviors. Each one is off by
/// default, so the ORM works as it always does. Turn one on with its
/// field, or turn all of them on with [OrmFlags.all].
///
/// Pass it to [DatabaseConfig] (or `SqlQueryBuilder.initialize`). The
/// ORM keeps it in `SqlQueryBuilder().flags`, one per isolate. Each
/// isolate sets up its own config, so each isolate gets the flags.
///
/// ```
/// DatabaseConfig databaseConfig = DatabaseConfig(
///   connection: 'postgres',
///   connections: connections,
///   flags: OrmFlags.all(),
/// );
/// ```
class OrmFlags {
  /// `save()` on a model with no changes fires `saving` and `saved`,
  /// but not `updating` and `updated`. Off: it fires all four.
  /// A model with a `Map` or `List` field always counts as changed: the
  /// field can be changed in place, so the ORM can not see that it is
  /// the same.
  /// The clean check reads the columns, so `beforeSave` runs once for
  /// it. When the model did change, `beforeSave` runs again for the
  /// UPDATE, after the `updating` hook, so a change made by that hook is
  /// saved. A clean save runs it once.
  // NEXT MAJOR: make this the default, then remove the flag.
  final bool skipCleanUpdateEvents;

  /// the default foreign key of a `belongsTo` relation comes from the
  /// relation name: `@BelongsTo(User) User? author` uses `author_id`.
  /// Off: it comes from the class name (`user_id`).
  // NEXT MAJOR: make this the default, then remove the flag.
  final bool belongsToKeyFromRelation;

  /// the default table name is plural: `User` uses `users`,
  /// `BlogPost` uses `blog_posts`. Off: `user` and `blog_post`. The
  /// last word gets the English plural.
  // NEXT MAJOR: make this the default, then remove the flag.
  final bool pluralTableNames;

  /// `create()` writes NULL for a key that is null in its data.
  /// Off: a null key is not sent, so the column default is used.
  // NEXT MAJOR: make this the default, then remove the flag.
  final bool createWritesNull;

  /// `sum()` gives 0 when no row matches. Off: it gives null.
  // NEXT MAJOR: make this the default, then remove the flag.
  final bool sumReturnsZero;

  /// `selectRaw()` adds to the select list, so
  /// `select('a').selectRaw('count(*) c')` selects both.
  /// Off: it replaces the list.
  // NEXT MAJOR: make this the default, then remove the flag.
  final bool selectRawAdds;

  /// a second `groupBy()` or `groupByRaw()` adds to the first.
  /// Off: it replaces the first.
  // NEXT MAJOR: make this the default, then remove the flag.
  final bool groupByAdds;

  /// `paginate()` gives `lastPage` 1 when there are no rows.
  /// Off: it gives 0.
  // NEXT MAJOR: make this the default, then remove the flag.
  final bool lastPageAtLeastOne;

  /// on Postgres, a new table made with `Schema.create` gets
  /// `TIMESTAMP` (no time zone) for `timestamps()` and `softDeletes()`,
  /// and `JSON` for `json()`. Off: `TIMESTAMPTZ` and `JSONB`. It never
  /// changes a table that is already there. MySQL and SQLite do not
  /// change.
  // NEXT MAJOR: make this the default, then remove the flag.
  final bool laravelPostgresTypes;

  /// the query form of `update()` on a model, like
  /// `User().where('id', 1).update({...})`, also sets `updated_at` when
  /// the model has timestamps and the data has no value for it.
  /// Off: it does not. `update()` on a model read from the table, and
  /// `save()`, always set it.
  // NEXT MAJOR: make this the default, then remove the flag.
  final bool updateSetsUpdatedAt;

  /// `increment()` and `decrement()` on a model read from the table fire
  /// `saving`, `updating`, `updated` and `saved`, like `save()`, and set
  /// `updated_at`. A hook can stop it with `CancelModelEvent`: then it
  /// changes nothing and returns 0. Off: no events, and `updated_at`
  /// stays as it is. The query form (with `where()`) does not change.
  // NEXT MAJOR: make this the default, then remove the flag.
  final bool incrementFiresEvents;

  /// `preload()` with a name that is not a relation of the model, like
  /// `preload('typo')`, throws an `ArgumentError` when the query runs,
  /// also with no rows. With a dot path, each level is checked when
  /// that level has rows. Off: an unknown name loads
  /// nothing.
  // NEXT MAJOR: make this the default, then remove the flag.
  final bool preloadUnknownThrows;

  /// `toJson()` and `toMap()` also have the relations loaded with
  /// `$getRelation()`, not only the ones named in `preload()`. The name
  /// then counts like a `preload()` name, so `reload()` loads it again
  /// too. `hidden` still leaves it out. Off: only `preload()` names and
  /// eager relations are in it.
  // NEXT MAJOR: make this the default, then remove the flag.
  final bool toJsonLoadedRelations;

  const OrmFlags({
    this.skipCleanUpdateEvents = false,
    this.belongsToKeyFromRelation = false,
    this.pluralTableNames = false,
    this.createWritesNull = false,
    this.sumReturnsZero = false,
    this.selectRawAdds = false,
    this.groupByAdds = false,
    this.lastPageAtLeastOne = false,
    this.laravelPostgresTypes = false,
    this.updateSetsUpdatedAt = false,
    this.incrementFiresEvents = false,
    this.preloadUnknownThrows = false,
    this.toJsonLoadedRelations = false,
  });

  /// every flag on
  const OrmFlags.all()
    : skipCleanUpdateEvents = true,
      belongsToKeyFromRelation = true,
      pluralTableNames = true,
      createWritesNull = true,
      sumReturnsZero = true,
      selectRawAdds = true,
      groupByAdds = true,
      lastPageAtLeastOne = true,
      laravelPostgresTypes = true,
      updateSetsUpdatedAt = true,
      incrementFiresEvents = true,
      preloadUnknownThrows = true,
      toJsonLoadedRelations = true;
}
