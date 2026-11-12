// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'letter.model.dart';

// **************************************************************************
// Generator: DoxModelBuilder
// **************************************************************************

// ignore_for_file: always_specify_types

class LetterGenerator extends Model<Letter> with SoftDeletes<Letter> {
  @override
  String get primaryKey => 'id';

  @override
  Map<String, dynamic> get timestampsColumn => const <String, dynamic>{
    'created_at': 'created_at',
    'updated_at': 'updated_at',
  };

  int? get id => tempIdValue as int?;

  set id(int? val) => tempIdValue = val;

  Letter query() => Letter();

  @override
  bool get readsRowDates => true;

  @override
  List<String> get tableColumns => const <String>[
    'id',
    'title',
    'citizen_id',
    'writer_ref',
    'deleted_at',
    'created_at',
    'updated_at',
  ];

  @override
  List<String> get preloadList => const <String>[];

  @override
  Map<String, Function> get relationsResultMatcher =>
      const <String, Function>{};

  @override
  Map<String, Function> get relationsQueryMatcher => const <String, Function>{};

  @override
  Letter fromMap(Map<String, dynamic> m) => Letter()
    ..id = m['id'] as int?
    ..title = m['title'] as String?
    ..citizenId = m['citizen_id'] as int?
    ..writerRef = m['writer_ref'] as String?
    ..deletedAt = m['deleted_at'] is DateTime?
        ? m['deleted_at'] as DateTime?
        : DateTime.parse(m['deleted_at'] as String)
    ..createdAt = m['created_at'] is DateTime?
        ? m['created_at'] as DateTime?
        : DateTime.parse(m['created_at'] as String)
    ..updatedAt = m['updated_at'] is DateTime?
        ? m['updated_at'] as DateTime?
        : DateTime.parse(m['updated_at'] as String);
  @override
  Map<String, dynamic> columnsToMap() {
    Letter instance = this as Letter;
    Map<String, dynamic> map = <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'citizen_id': instance.citizenId,
      'writer_ref': instance.writerRef,
      'deleted_at': instance.deletedAt?.toIso8601String(),
      'created_at': instance.createdAt?.toIso8601String(),
      'updated_at': instance.updatedAt?.toIso8601String(),
    };

    return map;
  }

  @override
  Map<String, dynamic> convertToMap(dynamic i) {
    Letter instance = i as Letter;
    Map<String, dynamic> map = instance.columnsToMap();

    return map;
  }

  @override
  bool setColumnValue(String column, dynamic value) {
    Letter instance = this as Letter;
    switch (column) {
      case 'id':
        if (value is! int?) return false;
        instance.id = value;
        return true;
      case 'title':
        if (value is! String?) return false;
        instance.title = value;
        return true;
      case 'citizen_id':
        if (value is! int?) return false;
        instance.citizenId = value;
        return true;
      case 'writer_ref':
        if (value is! String?) return false;
        instance.writerRef = value;
        return true;
      case 'deleted_at':
        if (value is! DateTime?) return false;
        instance.deletedAt = value;
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
