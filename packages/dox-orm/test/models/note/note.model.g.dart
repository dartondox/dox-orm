// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'note.model.dart';

// **************************************************************************
// Generator: DoxModelBuilder
// **************************************************************************

// ignore_for_file: always_specify_types

class NoteGenerator extends Model<Note> {
  @override
  String get primaryKey => 'id';

  @override
  Map<String, dynamic> get timestampsColumn => const <String, dynamic>{
    'created_at': 'created_at',
    'updated_at': 'updated_at',
  };

  @override
  String get tableName => 'notes';

  int? get id => tempIdValue as int?;

  set id(int? val) => tempIdValue = val;

  Note query() => Note();

  @override
  bool get readsRowDates => true;

  @override
  List<String> get tableColumns => const <String>[
    'id',
    'slug',
    'title',
    'pinned',
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

  static const _pinnedCast = BoolCast();

  @override
  Note fromMap(Map<String, dynamic> m) => Note()
    ..id = m['id'] as int?
    ..slug = m['slug'] as String?
    ..title = m['title'] as String?
    ..pinned = _pinnedCast.get(m['pinned'])
    ..createdAt = m['created_at'] is DateTime?
        ? m['created_at'] as DateTime?
        : DateTime.parse(m['created_at'] as String)
    ..updatedAt = m['updated_at'] is DateTime?
        ? m['updated_at'] as DateTime?
        : DateTime.parse(m['updated_at'] as String);
  @override
  Map<String, dynamic> columnsToMap() {
    Note instance = this as Note;
    Map<String, dynamic> map = <String, dynamic>{
      'id': instance.id,
      'slug': instance.slug,
      'title': instance.title,
      'pinned': _pinnedCast.set(instance.pinned),
      'created_at': instance.createdAt?.toIso8601String(),
      'updated_at': instance.updatedAt?.toIso8601String(),
    };
    map['slug'] = Note.slugOf(map);

    return map;
  }

  @override
  Map<String, dynamic> convertToMap(dynamic i) {
    Note instance = i as Note;
    Map<String, dynamic> map = instance.columnsToMap();

    return map;
  }

  @override
  bool setColumnValue(String column, dynamic value) {
    Note instance = this as Note;
    switch (column) {
      case 'id':
        if (value is! int?) return false;
        instance.id = value;
        return true;
      case 'slug':
        if (value is! String?) return false;
        instance.slug = value;
        return true;
      case 'title':
        if (value is! String?) return false;
        instance.title = value;
        return true;
      case 'pinned':
        if (value is! bool?) return false;
        instance.pinned = value;
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
