// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'photo.model.dart';

// **************************************************************************
// Generator: DoxModelBuilder
// **************************************************************************

// ignore_for_file: always_specify_types

class PhotoGenerator extends Model<Photo> {
  @override
  String get primaryKey => 'id';

  @override
  Map<String, dynamic> get timestampsColumn => const <String, dynamic>{
    'created_at': 'created_at',
    'updated_at': 'updated_at',
  };

  int? get id => tempIdValue as int?;

  set id(int? val) => tempIdValue = val;

  Photo query() => Photo();

  @override
  bool get readsRowDates => true;

  @override
  List<String> get tableColumns => const <String>[
    'id',
    'title',
    'created_at',
    'updated_at',
  ];

  @override
  List<String> get preloadList => const <String>[];

  @override
  Map<String, Function> get relationsResultMatcher => const <String, Function>{
    'comments': getComments,
    'latestComment': getLatestComment,
  };

  @override
  Map<String, Function> get relationsQueryMatcher => const <String, Function>{
    'comments': queryComments,
    'latestComment': queryLatestComment,
  };

  static Future<void> getComments(List<Model<Photo>> list) async {
    var result = await getMorphMany<Photo, Comment>(queryComments(list), list);
    for (dynamic i in list) {
      i.comments = result[i.tempIdValue.toString()] ?? <Comment>[];
    }
  }

  static Comment? queryComments(List<Model<Photo>> list) {
    return morphMany<Photo, Comment>(
      list,
      () => Comment(),
      name: 'commentable',
    );
  }

  static Future<void> getLatestComment(List<Model<Photo>> list) async {
    var result = await getMorphOne<Photo, Comment>(
      queryLatestComment(list),
      list,
    );
    for (dynamic i in list) {
      i.latestComment = result[i.tempIdValue.toString()];
    }
  }

  static Comment? queryLatestComment(List<Model<Photo>> list) {
    return morphOne<Photo, Comment>(
      list,
      () => Comment(),
      name: 'commentable',
      onQuery: Photo.newest,
    );
  }

  @override
  Photo fromMap(Map<String, dynamic> m) => Photo()
    ..id = m['id'] as int?
    ..title = m['title'] as String?
    ..createdAt = m['created_at'] is DateTime?
        ? m['created_at'] as DateTime?
        : DateTime.parse(m['created_at'] as String)
    ..updatedAt = m['updated_at'] is DateTime?
        ? m['updated_at'] as DateTime?
        : DateTime.parse(m['updated_at'] as String);
  @override
  Map<String, dynamic> columnsToMap() {
    Photo instance = this as Photo;
    Map<String, dynamic> map = <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'created_at': instance.createdAt?.toIso8601String(),
      'updated_at': instance.updatedAt?.toIso8601String(),
    };

    return map;
  }

  @override
  Map<String, dynamic> convertToMap(dynamic i) {
    Photo instance = i as Photo;
    Map<String, dynamic> map = instance.columnsToMap();

    List<String> preload = getPreload();
    if (preload.contains('comments')) {
      map['comments'] = toMap(instance.comments);
    }
    if (preload.contains('latestComment')) {
      map['latest_comment'] = toMap(instance.latestComment);
    }

    return map;
  }

  @override
  bool setColumnValue(String column, dynamic value) {
    Photo instance = this as Photo;
    switch (column) {
      case 'id':
        if (value is! int?) return false;
        instance.id = value;
        return true;
      case 'title':
        if (value is! String?) return false;
        instance.title = value;
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
