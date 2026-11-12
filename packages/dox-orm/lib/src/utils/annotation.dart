import '../casts.dart';

class Column {
  final String? name;
  final Function? beforeSave;
  final Function? beforeGet;

  /// changes the value between the database and Dart, see [Cast]
  final Cast<dynamic>? cast;

  const Column({this.name, this.beforeSave, this.beforeGet, this.cast});
}

/// Marks a static method of a model as a query scope.
/// The method takes the query first, and can take more arguments.
/// The generator adds it as a method on the query of the model.
///
/// ```
/// @Scope()
/// static QueryBuilder<User> active(QueryBuilder<User> q) =>
///     q.where('active', true);
///
/// await User().active().get();
/// ```
///
/// `global: true` adds it to every query of the model. Remove it with
/// `withoutGlobalScope('name')` or `withoutGlobalScopes()`.
class Scope {
  final bool global;

  const Scope({this.global = false});
}

/// Adds a getter to toJson() and toMap(). It is never a table column.
///
/// ```
/// @Computed()
/// String get fullName => '$firstName $lastName'; // key: full_name
///
/// @Computed(name: 'display')
/// String get displayName => name ?? '';
/// ```
class Computed {
  /// json key, the default is the getter name in snake_case
  final String? name;

  const Computed({this.name});
}

/// one to one relation. when an owner has many child rows, eager loading
/// keeps the last row the query returns. add an `orderBy` in [onQuery] to
/// pick the row, see `hasOne()`.
class HasOne {
  final Type model;
  final String? foreignKey;
  final String? localKey;
  final Function? onQuery;
  final bool? eager;

  const HasOne(
    this.model, {
    this.foreignKey,
    this.localKey,
    this.onQuery,
    this.eager,
  });
}

class HasMany {
  final Type model;
  final String? foreignKey;
  final String? localKey;
  final Function? onQuery;
  final bool? eager;

  const HasMany(
    this.model, {
    this.foreignKey,
    this.localKey,
    this.onQuery,
    this.eager,
  });
}

class BelongsTo {
  final Type model;
  final String? foreignKey;
  final String? localKey;
  final Function? onQuery;
  final bool? eager;

  const BelongsTo(
    this.model, {
    this.foreignKey,
    this.localKey,
    this.onQuery,
    this.eager,
  });
}

class ManyToMany {
  final Type model;
  final Function? onQuery;
  final bool? eager;

  /// id column on artist table
  final String? localKey;

  /// id column on song table
  final String? relatedKey;

  /// artist_id column on related table
  final String? pivotForeignKey;

  /// artist_id column on related table
  final String? pivotRelatedForeignKey;

  /// song_artist table
  final String? pivotTable;

  /// extra pivot columns to read, like `['role']`. Read them with
  /// `song.pivot['role']`.
  final List<String>? withPivot;

  /// true when the pivot table has `created_at` and `updated_at`.
  /// attach() and sync() then set them, and `pivot` reads them.
  final bool withTimestamps;

  const ManyToMany(
    this.model, {
    this.eager,
    this.onQuery,
    this.localKey,
    this.relatedKey,
    this.pivotForeignKey,
    this.pivotRelatedForeignKey,
    this.pivotTable,
    this.withPivot,
    this.withTimestamps = false,
  });
}

/// many far rows found through a model in the middle, like a country
/// with the posts of its users. `users.country_id` points to the
/// country and `posts.user_id` points to the user.
///
/// ```
/// @HasManyThrough(Post, through: User)
/// List<Post> posts = <Post>[];
/// ```
class HasManyThrough {
  final Type model;

  /// the model in the middle, like `User`
  final Type through;

  /// the column on the through table that points to this model,
  /// default `country_id`
  final String? foreignKey;

  /// the column of this model, default its primary key
  final String? localKey;

  /// the column on the far table that points to the through model,
  /// default `user_id`
  final String? throughForeignKey;

  /// the column of the through model, default its primary key
  final String? throughLocalKey;
  final Function? onQuery;
  final bool? eager;

  const HasManyThrough(
    this.model, {
    required this.through,
    this.foreignKey,
    this.localKey,
    this.throughForeignKey,
    this.throughLocalKey,
    this.onQuery,
    this.eager,
  });
}

/// one far row found through a model in the middle, see
/// [HasManyThrough]. When there are many far rows, eager loading keeps
/// the last row the query returns. Add an `orderBy` in [onQuery] to pick
/// the row.
///
/// ```
/// @HasOneThrough(Post, through: User)
/// Post? post;
/// ```
class HasOneThrough {
  final Type model;
  final Type through;
  final String? foreignKey;
  final String? localKey;
  final String? throughForeignKey;
  final String? throughLocalKey;
  final Function? onQuery;
  final bool? eager;

  const HasOneThrough(
    this.model, {
    required this.through,
    this.foreignKey,
    this.localKey,
    this.throughForeignKey,
    this.throughLocalKey,
    this.onQuery,
    this.eager,
  });
}

/// polymorphic one to many relation, like a post with many comments.
/// [name] is the morph name: the related table has `<name>_id` and
/// `<name>_type` columns (see `table.morphs(name)`).
///
/// ```
/// @MorphMany(Comment, 'commentable')
/// List<Comment> comments = <Comment>[];
/// ```
class MorphMany {
  final Type model;
  final String name;

  /// the type column, default `<name>_type`
  final String? typeColumn;

  /// the id column, default `<name>_id`
  final String? idColumn;

  /// the key of this model that `<name>_id` points to, default the
  /// primary key
  final String? localKey;
  final Function? onQuery;
  final bool? eager;

  const MorphMany(
    this.model,
    this.name, {
    this.typeColumn,
    this.idColumn,
    this.localKey,
    this.onQuery,
    this.eager,
  });
}

/// polymorphic one to one relation, like a post with one image.
/// see [MorphMany].
class MorphOne {
  final Type model;
  final String name;
  final String? typeColumn;
  final String? idColumn;
  final String? localKey;
  final Function? onQuery;
  final bool? eager;

  const MorphOne(
    this.model,
    this.name, {
    this.typeColumn,
    this.idColumn,
    this.localKey,
    this.onQuery,
    this.eager,
  });
}

/// the inverse of [MorphMany] and [MorphOne], like a comment that
/// belongs to a post or a video. The field type is `Model<dynamic>?`.
/// Every model it can point to must be in the morph map, see
/// `Model.morphMap()`.
///
/// ```
/// @MorphTo()
/// Model<dynamic>? commentable;
/// ```
class MorphTo {
  /// the morph name, default the field name in snake_case
  final String? name;

  /// the type column, default `<name>_type`
  final String? typeColumn;

  /// the id column, default `<name>_id`
  final String? idColumn;

  /// the key of the related model that `<name>_id` points to, default
  /// its primary key
  final String? ownerKey;

  /// a static function that changes the query. It runs for the query of
  /// every type, so it must take and return `Model<dynamic>`:
  ///
  /// ```
  /// static Model<dynamic> notDeleted(Model<dynamic> q) {
  ///   q.whereNull('hidden_at');
  ///   return q;
  /// }
  /// ```
  final Function? onQuery;
  final bool? eager;

  const MorphTo({
    this.name,
    this.typeColumn,
    this.idColumn,
    this.ownerKey,
    this.onQuery,
    this.eager,
  });
}
