// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'device.model.dart';

// **************************************************************************
// Generator: DoxModelBuilder
// **************************************************************************

// ignore_for_file: always_specify_types

class DeviceGenerator extends Model<Device> {
  @override
  String get primaryKey => 'uuid';

  @override
  Map<String, dynamic> get timestampsColumn => const <String, dynamic>{
    'created_at': 'created_at',
    'updated_at': 'updated_at',
  };

  String? get uuid => tempIdValue as String?;

  set uuid(String? val) => tempIdValue = val;

  Device query() => Device();

  @override
  bool get readsRowDates => true;

  @override
  List<String> get tableColumns => const <String>[
    'uuid',
    'name',
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
  Device fromMap(Map<String, dynamic> m) => Device()
    ..uuid = m['uuid'] as String?
    ..name = m['name'] as String?
    ..createdAt = switch (m['created_at']) {
      DateTime? v => v,
      Object? v => DateTime.parse(v as String),
    }
    ..updatedAt = switch (m['updated_at']) {
      DateTime? v => v,
      Object? v => DateTime.parse(v as String),
    };
  @override
  Map<String, dynamic> columnsToMap() {
    Device instance = this as Device;
    Map<String, dynamic> map = <String, dynamic>{
      'uuid': instance.uuid,
      'name': instance.name,
      'created_at': instance.createdAt?.toIso8601String(),
      'updated_at': instance.updatedAt?.toIso8601String(),
    };

    return map;
  }

  @override
  dynamic $columnValue(String column) {
    Device instance = this as Device;
    switch (column) {
      case 'uuid':
        return instance.uuid;
      case 'name':
        return instance.name;
      case 'created_at':
        return instance.createdAt?.toIso8601String();
      case 'updated_at':
        return instance.updatedAt?.toIso8601String();
    }
    return super.$columnValue(column);
  }

  @override
  Map<String, dynamic> convertToMap(dynamic i) {
    Device instance = i as Device;
    Map<String, dynamic> map = instance.columnsToMap();

    return map;
  }

  @override
  bool setColumnValue(String column, dynamic value) {
    Device instance = this as Device;
    switch (column) {
      case 'uuid':
        if (value is! String?) return false;
        instance.uuid = value;
        return true;
      case 'name':
        if (value is! String?) return false;
        instance.name = value;
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

  @override
  bool $copyColumnsFrom(Model<Device> other) {
    Device o = other as Device;
    (this as Device)
      ..uuid = o.uuid
      ..name = o.name
      ..createdAt = o.createdAt
      ..updatedAt = o.updatedAt;
    return true;
  }
}
