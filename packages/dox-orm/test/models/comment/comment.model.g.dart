// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'comment.model.dart';

// **************************************************************************
// Generator: DoxModelBuilder
// **************************************************************************

// ignore_for_file: always_specify_types

class CommentGenerator extends Model<Comment> {
  @override
  String get primaryKey => 'id';

  @override
  Map<String, dynamic> get timestampsColumn => const <String, dynamic>{
    'created_at': 'created_at',
    'updated_at': 'updated_at',
  };

  int? get id => tempIdValue as int?;

  set id(int? val) => tempIdValue = val;

  Comment query() => Comment();

  @override
  bool get readsRowDates => true;

  @override
  List<String> get tableColumns => const <String>[
    'id',
    'body',
    'commentable_id',
    'commentable_type',
    'created_at',
    'updated_at',
  ];

  @override
  List<String> get preloadList => const <String>[];

  @override
  Map<String, Function> get relationsResultMatcher => const <String, Function>{
    'commentable': getCommentable,
  };

  @override
  Map<String, Function> get relationsQueryMatcher => const <String, Function>{
    'commentable': queryCommentable,
  };

  static Future<void> getCommentable(List<Model<Comment>> list) async {
    var result = await getMorphTo<Comment, Model<dynamic>>(
      queryCommentable(list),
      list,
    );
    for (dynamic i in list) {
      if (result[i.tempIdValue.toString()] != null) {
        i.commentable = result[i.tempIdValue.toString()]!;
      }
    }
  }

  static Model<dynamic>? queryCommentable(List<Model<Comment>> list) {
    return morphTo<Comment, Model<dynamic>>(list, name: 'commentable');
  }

  @override
  Comment fromMap(Map<String, dynamic> m) => Comment()
    ..id = m['id'] as int?
    ..body = m['body'] as String?
    ..commentableId = m['commentable_id'] as int?
    ..commentableType = m['commentable_type'] as String?
    ..createdAt = m['created_at'] is DateTime?
        ? m['created_at'] as DateTime?
        : DateTime.parse(m['created_at'] as String)
    ..updatedAt = m['updated_at'] is DateTime?
        ? m['updated_at'] as DateTime?
        : DateTime.parse(m['updated_at'] as String);
  @override
  Map<String, dynamic> columnsToMap() {
    Comment instance = this as Comment;
    Map<String, dynamic> map = <String, dynamic>{
      'id': instance.id,
      'body': instance.body,
      'commentable_id': instance.commentableId,
      'commentable_type': instance.commentableType,
      'created_at': instance.createdAt?.toIso8601String(),
      'updated_at': instance.updatedAt?.toIso8601String(),
    };

    return map;
  }

  @override
  Map<String, dynamic> convertToMap(dynamic i) {
    Comment instance = i as Comment;
    Map<String, dynamic> map = instance.columnsToMap();

    List<String> preload = getPreload();
    if (preload.contains('commentable')) {
      map['commentable'] = toMap(instance.commentable);
    }

    return map;
  }

  @override
  bool setColumnValue(String column, dynamic value) {
    Comment instance = this as Comment;
    switch (column) {
      case 'id':
        if (value is! int?) return false;
        instance.id = value;
        return true;
      case 'body':
        if (value is! String?) return false;
        instance.body = value;
        return true;
      case 'commentable_id':
        if (value is! int?) return false;
        instance.commentableId = value;
        return true;
      case 'commentable_type':
        if (value is! String?) return false;
        instance.commentableType = value;
        return true;
      case 'created_at':
        if (value is! DateTime?) return false;
        instance.createdAt = value;
        return true;
      case 'updated_at':
        if (value is! DateTime?) return false;
        instance.updatedAt = value;
        return true;
    }
    return false;
  }
}
