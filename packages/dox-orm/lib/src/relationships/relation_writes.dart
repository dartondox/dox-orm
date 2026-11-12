import 'package:dox_orm/dox_orm.dart';

import 'keys.dart';

/// writes through a relation that set the foreign key for you.
/// The relation is named by its field name, like `attach()` of a many to
/// many relation.
///
/// ```
/// Blog blog = (await Blog().find(1))!;
/// Comment c = await blog.createRelated<Comment>('comments', {'body': 'hi'});
/// await blog.saveRelated('comments', Comment()..body = 'hi');
/// await blog.saveManyRelated('comments', [c1, c2]);
///
/// comment.associate('blog', blog);
/// comment.dissociate('blog');
/// await comment.save();
/// ```
///
/// `createRelated`, `saveRelated` and `saveManyRelated` work with
/// `@HasMany`, `@HasOne`, `@MorphMany` and `@MorphOne`. A morph relation
/// also sets the type column. `associate` and `dissociate` work with
/// `@BelongsTo`. The child model needs a `@Column` for the foreign key.
extension RelationWrites<T> on Model<T> {
  /// the keys of [relation], or an [ArgumentError] when it is not one of
  /// [kinds]
  RelationKeys _relationKeys(String relation, List<String> kinds) {
    relationKeysFound = null;
    findRelationKeys = true;
    try {
      /// makes the relation query, which sets relationKeysFound
      related<dynamic>(relation);
    } finally {
      findRelationKeys = false;
    }
    RelationKeys? k = relationKeysFound;
    relationKeysFound = null;
    if (k == null || !kinds.contains(k.kind)) {
      throw ArgumentError.value(
        relation,
        'relation',
        'is not a ${kinds.join(' or ')} relation of $runtimeType',
      );
    }
    return k;
  }

  /// the foreign key values that [relation] sets on a child
  (RelationKeys, Map<String, dynamic>) _childKeys(String relation) {
    RelationKeys k = _relationKeys(relation, const <String>[
      'hasMany',
      'hasOne',
    ]);
    dynamic value = relationKey(this, k.localKey);
    if (value == null) {
      throw StateError(
        '$runtimeType has no ${k.localKey} value: save it before you '
        'write to its $relation relation',
      );
    }
    return (k, <String, dynamic>{k.foreignKey: value, ...k.extra});
  }

  /// sets [keys] on [child], and checks that they are set: a model with
  /// no field for a key would save the row without it
  static void _setKeys(Model<dynamic> child, Map<String, dynamic> keys) {
    child.forceFill(keys);
    for (MapEntry<String, dynamic> e in keys.entries) {
      if (relationKey(child, e.key) != e.value) {
        throw StateError(
          '${child.runtimeType} has no field for ${e.key}: add a @Column '
          'for it',
        );
      }
    }
  }

  /// creates a row of [relation] from [data] with the foreign key of this
  /// model, and gives the new model. [data] goes through `create()`, so
  /// `fillable`, `guarded`, events and timestamps work as usual. The
  /// foreign key does not need to be in `fillable`. A foreign key (or
  /// morph type) in [data] is not used: the one of this model wins.
  Future<M> createRelated<M>(String relation, Map<String, dynamic> data) async {
    var (RelationKeys k, Map<String, dynamic> keys) = _childKeys(relation);
    Model<dynamic> child = k.model()..useConnectionOf(this);
    _setKeys(child, keys);

    /// the keys of this model always win over the same keys in [data]
    Map<String, dynamic> rest = <String, dynamic>{...data};
    for (String key in keys.keys) {
      rest.remove(key);
    }
    return await child.create(rest) as M;
  }

  /// sets the foreign key of this model on [child] and saves it. It
  /// gives the result of `save()`: false when a hook stops it.
  Future<bool> saveRelated(String relation, Model<dynamic> child) async {
    var (_, Map<String, dynamic> keys) = _childKeys(relation);
    _setKeys(child, keys);
    return await child.save();
  }

  /// [saveRelated] for each of [children], one by one. It gives true
  /// when every save went through.
  Future<bool> saveManyRelated(
    String relation,
    List<Model<dynamic>> children,
  ) async {
    var (_, Map<String, dynamic> keys) = _childKeys(relation);
    bool all = true;
    for (Model<dynamic> child in children) {
      _setKeys(child, keys);
      if (!await child.save()) all = false;
    }
    return all;
  }

  /// sets the foreign key of the `@BelongsTo` [relation] to the key of
  /// [parent]. It does not save: call `save()` after it. The relation
  /// field (like `comment.blog`) does not change. It returns this model.
  Model<T> associate(String relation, Model<dynamic> parent) {
    RelationKeys k = _relationKeys(relation, const <String>['belongsTo']);
    dynamic value = relationKey(parent, k.localKey);
    if (value == null) {
      throw StateError(
        '${parent.runtimeType} has no ${k.localKey} value: save it before '
        'you associate it',
      );
    }
    _setKeys(this, <String, dynamic>{k.foreignKey: value});
    return this;
  }

  /// sets the foreign key of the `@BelongsTo` [relation] to null. It does
  /// not save: call `save()` after it. It returns this model.
  Model<T> dissociate(String relation) {
    RelationKeys k = _relationKeys(relation, const <String>['belongsTo']);
    _setKeys(this, <String, dynamic>{k.foreignKey: null});
    return this;
  }
}
