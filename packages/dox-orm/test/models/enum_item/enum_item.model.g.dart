// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'enum_item.model.dart';

// **************************************************************************
// Generator: DoxModelBuilder
// **************************************************************************

// ignore_for_file: always_specify_types

class EnumItemGenerator extends Model<EnumItem> {
  @override
  String get primaryKey => 'id';

  @override
  Map<String, dynamic> get timestampsColumn => const <String, dynamic>{
    'created_at': null,
    'updated_at': null,
  };

  int? get id => tempIdValue as int?;

  set id(int? val) => tempIdValue = val;

  EnumItem query() => EnumItem();

  @override
  bool get readsRowDates => true;

  @override
  List<String> get tableColumns => const <String>[
    'id',
    'title',
    'status',
    'level',
    'fallback',
    'kind',
  ];

  @override
  List<String> get preloadList => const <String>[];

  @override
  Map<String, Function> get relationsResultMatcher =>
      const <String, Function>{};

  @override
  Map<String, Function> get relationsQueryMatcher => const <String, Function>{};

  static const _statusCast = EnumCast(Status.values);
  static const _levelCast = EnumCast<Level>(Level.values, byIndex: true);
  static const _fallbackCast = EnumCast<Status>(
    Status.values,
    unknown: Status.draft,
  );
  static const _kindCast = EnumCast(Status.values);

  @override
  EnumItem fromMap(Map<String, dynamic> m) => EnumItem()
    ..id = m['id'] as int?
    ..title = m['title'] as String?
    ..status = _statusCast.get(m['status'])
    ..level = _levelCast.get(m['level'])
    ..fallback = _fallbackCast.get(m['fallback'])
    ..kind = _kindCast.get(m['kind']) as Status;
  @override
  Map<String, dynamic> columnsToMap() {
    EnumItem instance = this as EnumItem;
    Map<String, dynamic> map = <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'status': _statusCast.set(instance.status),
      'level': _levelCast.set(instance.level),
      'fallback': _fallbackCast.set(instance.fallback),
      'kind': _kindCast.set(instance.kind),
    };

    return map;
  }

  @override
  dynamic $columnValue(String column) {
    EnumItem instance = this as EnumItem;
    switch (column) {
      case 'id':
        return instance.id;
      case 'title':
        return instance.title;
      case 'status':
        return _statusCast.set(instance.status);
      case 'level':
        return _levelCast.set(instance.level);
      case 'fallback':
        return _fallbackCast.set(instance.fallback);
      case 'kind':
        return _kindCast.set(instance.kind);
    }
    return super.$columnValue(column);
  }

  @override
  Map<String, dynamic> convertToMap(dynamic i) {
    EnumItem instance = i as EnumItem;
    Map<String, dynamic> map = instance.columnsToMap();

    return map;
  }

  @override
  bool setColumnValue(String column, dynamic value) {
    EnumItem instance = this as EnumItem;
    switch (column) {
      case 'id':
        if (value is! int?) return false;
        instance.id = value;
        return true;
      case 'title':
        if (value is! String?) return false;
        instance.title = value;
        return true;
      case 'status':
        if (value is! Status?) return false;
        instance.status = value;
        return true;
      case 'level':
        if (value is! Level?) return false;
        instance.level = value;
        return true;
      case 'fallback':
        if (value is! Status?) return false;
        instance.fallback = value;
        return true;
      case 'kind':
        if (value is! Status) return false;
        instance.kind = value;
        return true;
    }
    return false;
  }

  @override
  bool $copyColumnsFrom(Model<EnumItem> other) {
    EnumItem o = other as EnumItem;
    (this as EnumItem)
      ..id = o.id
      ..title = o.title
      ..status = o.status
      ..level = o.level
      ..fallback = o.fallback
      ..kind = o.kind;
    return true;
  }
}
