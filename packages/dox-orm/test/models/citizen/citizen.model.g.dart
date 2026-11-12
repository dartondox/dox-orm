// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'citizen.model.dart';

// **************************************************************************
// Generator: DoxModelBuilder
// **************************************************************************

// ignore_for_file: always_specify_types

class CitizenGenerator extends Model<Citizen> with SoftDeletes<Citizen> {
  @override
  String get primaryKey => 'id';

  @override
  Map<String, dynamic> get timestampsColumn => const <String, dynamic>{
    'created_at': 'created_at',
    'updated_at': 'updated_at',
  };

  int? get id => tempIdValue as int?;

  set id(int? val) => tempIdValue = val;

  Citizen query() => Citizen();

  @override
  bool get readsRowDates => true;

  @override
  List<String> get tableColumns => const <String>[
    'id',
    'name',
    'country_id',
    'home_code',
    'ref',
    'manager_id',
    'deleted_at',
    'created_at',
    'updated_at',
  ];

  @override
  List<String> get preloadList => const <String>[];

  @override
  Map<String, Function> get relationsResultMatcher => const <String, Function>{
    'teamLetters': getTeamLetters,
  };

  @override
  Map<String, Function> get relationsQueryMatcher => const <String, Function>{
    'teamLetters': queryTeamLetters,
  };

  static Future<void> getTeamLetters(List<Model<Citizen>> list) async {
    var result = await getHasManyThrough<Citizen, Letter>(
      queryTeamLetters(list),
      list,
    );
    for (dynamic i in list) {
      i.teamLetters = result[i.tempIdValue.toString()] ?? <Letter>[];
    }
  }

  static Letter? queryTeamLetters(List<Model<Citizen>> list) {
    return hasManyThrough<Citizen, Letter>(
      list,
      () => Letter(),
      through: () => Citizen(),
      foreignKey: 'manager_id',
    );
  }

  @override
  Citizen fromMap(Map<String, dynamic> m) => Citizen()
    ..id = m['id'] as int?
    ..name = m['name'] as String?
    ..countryId = m['country_id'] as int?
    ..homeCode = m['home_code'] as String?
    ..ref = m['ref'] as String?
    ..managerId = m['manager_id'] as int?
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
    Citizen instance = this as Citizen;
    Map<String, dynamic> map = <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'country_id': instance.countryId,
      'home_code': instance.homeCode,
      'ref': instance.ref,
      'manager_id': instance.managerId,
      'deleted_at': instance.deletedAt?.toIso8601String(),
      'created_at': instance.createdAt?.toIso8601String(),
      'updated_at': instance.updatedAt?.toIso8601String(),
    };

    return map;
  }

  @override
  Map<String, dynamic> convertToMap(dynamic i) {
    Citizen instance = i as Citizen;
    Map<String, dynamic> map = instance.columnsToMap();

    List<String> preload = getPreload();
    if (preload.contains('teamLetters')) {
      map['team_letters'] = toMap(instance.teamLetters);
    }

    return map;
  }

  @override
  bool setColumnValue(String column, dynamic value) {
    Citizen instance = this as Citizen;
    switch (column) {
      case 'id':
        if (value is! int?) return false;
        instance.id = value;
        return true;
      case 'name':
        if (value is! String?) return false;
        instance.name = value;
        return true;
      case 'country_id':
        if (value is! int?) return false;
        instance.countryId = value;
        return true;
      case 'home_code':
        if (value is! String?) return false;
        instance.homeCode = value;
        return true;
      case 'ref':
        if (value is! String?) return false;
        instance.ref = value;
        return true;
      case 'manager_id':
        if (value is! int?) return false;
        instance.managerId = value;
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
