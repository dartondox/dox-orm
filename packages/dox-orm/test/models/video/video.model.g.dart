// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'video.model.dart';

// **************************************************************************
// Generator: DoxModelBuilder
// **************************************************************************

// ignore_for_file: always_specify_types

class VideoGenerator extends Model<Video> {
  @override
  String get primaryKey => 'id';

  @override
  Map<String, dynamic> get timestampsColumn => const <String, dynamic>{
    'created_at': 'created_at',
    'updated_at': 'updated_at',
  };

  int? get id => tempIdValue as int?;

  set id(int? val) => tempIdValue = val;

  Video query() => Video();

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
  };

  @override
  Map<String, Function> get relationsQueryMatcher => const <String, Function>{
    'comments': queryComments,
  };

  static Future<void> getComments(List<Model<Video>> list) async {
    var result = await getMorphMany<Video, Comment>(queryComments(list), list);
    for (dynamic i in list) {
      if (result[i.tempIdValue.toString()] != null) {
        i.comments = result[i.tempIdValue.toString()]!;
      }
    }
  }

  static Comment? queryComments(List<Model<Video>> list) {
    return morphMany<Video, Comment>(
      list,
      () => Comment(),
      name: 'commentable',
      typeColumn: 'commentable_type',
      idColumn: 'commentable_id',
    );
  }

  @override
  Video fromMap(Map<String, dynamic> m) => Video()
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
    Video instance = this as Video;
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
    Video instance = i as Video;
    Map<String, dynamic> map = instance.columnsToMap();

    List<String> preload = getPreload();
    if (preload.contains('comments')) {
      map['comments'] = toMap(instance.comments);
    }

    return map;
  }

  @override
  bool setColumnValue(String column, dynamic value) {
    Video instance = this as Video;
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
