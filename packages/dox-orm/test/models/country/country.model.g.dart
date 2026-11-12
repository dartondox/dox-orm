// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'country.model.dart';

// **************************************************************************
// Generator: DoxModelBuilder
// **************************************************************************

// ignore_for_file: always_specify_types

class CountryGenerator extends Model<Country> {
  @override
  String get primaryKey => 'id';

  @override
  Map<String, dynamic> get timestampsColumn => const <String, dynamic>{
    'created_at': 'created_at',
    'updated_at': 'updated_at',
  };

  int? get id => tempIdValue as int?;

  set id(int? val) => tempIdValue = val;

  Country query() => Country();

  @override
  bool get readsRowDates => true;

  @override
  List<String> get tableColumns => const <String>[
    'id',
    'name',
    'code',
    'created_at',
    'updated_at',
  ];

  @override
  List<String> get preloadList => const <String>[];

  @override
  Map<String, Function> get relationsResultMatcher => const <String, Function>{
    'letters': getLetters,
    'latestLetter': getLatestLetter,
    'lettersByCode': getLettersByCode,
  };

  @override
  Map<String, Function> get relationsQueryMatcher => const <String, Function>{
    'letters': queryLetters,
    'latestLetter': queryLatestLetter,
    'lettersByCode': queryLettersByCode,
  };

  static Future<void> getLetters(List<Model<Country>> list) async {
    var result = await getHasManyThrough<Country, Letter>(
      queryLetters(list),
      list,
    );
    for (dynamic i in list) {
      i.letters = result[i.tempIdValue.toString()] ?? <Letter>[];
    }
  }

  static Letter? queryLetters(List<Model<Country>> list) {
    return hasManyThrough<Country, Letter>(
      list,
      () => Letter(),
      through: () => Citizen(),
    );
  }

  static Future<void> getLatestLetter(List<Model<Country>> list) async {
    var result = await getHasOneThrough<Country, Letter>(
      queryLatestLetter(list),
      list,
    );
    for (dynamic i in list) {
      i.latestLetter = result[i.tempIdValue.toString()];
    }
  }

  static Letter? queryLatestLetter(List<Model<Country>> list) {
    return hasOneThrough<Country, Letter>(
      list,
      () => Letter(),
      through: () => Citizen(),
      onQuery: Country.newest,
    );
  }

  static Future<void> getLettersByCode(List<Model<Country>> list) async {
    var result = await getHasManyThrough<Country, Letter>(
      queryLettersByCode(list),
      list,
    );
    for (dynamic i in list) {
      i.lettersByCode = result[i.tempIdValue.toString()] ?? <Letter>[];
    }
  }

  static Letter? queryLettersByCode(List<Model<Country>> list) {
    return hasManyThrough<Country, Letter>(
      list,
      () => Letter(),
      through: () => Citizen(),
      foreignKey: 'home_code',
      localKey: 'code',
      throughForeignKey: 'writer_ref',
      throughLocalKey: 'ref',
    );
  }

  @override
  Country fromMap(Map<String, dynamic> m) => Country()
    ..id = m['id'] as int?
    ..name = m['name'] as String?
    ..code = m['code'] as String?
    ..createdAt = m['created_at'] is DateTime?
        ? m['created_at'] as DateTime?
        : DateTime.parse(m['created_at'] as String)
    ..updatedAt = m['updated_at'] is DateTime?
        ? m['updated_at'] as DateTime?
        : DateTime.parse(m['updated_at'] as String);
  @override
  Map<String, dynamic> columnsToMap() {
    Country instance = this as Country;
    Map<String, dynamic> map = <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'code': instance.code,
      'created_at': instance.createdAt?.toIso8601String(),
      'updated_at': instance.updatedAt?.toIso8601String(),
    };

    return map;
  }

  @override
  Map<String, dynamic> convertToMap(dynamic i) {
    Country instance = i as Country;
    Map<String, dynamic> map = instance.columnsToMap();

    List<String> preload = getPreload();
    if (preload.contains('letters')) {
      map['letters'] = toMap(instance.letters);
    }
    if (preload.contains('latestLetter')) {
      map['latest_letter'] = toMap(instance.latestLetter);
    }
    if (preload.contains('lettersByCode')) {
      map['letters_by_code'] = toMap(instance.lettersByCode);
    }

    return map;
  }

  @override
  bool setColumnValue(String column, dynamic value) {
    Country instance = this as Country;
    switch (column) {
      case 'id':
        if (value is! int?) return false;
        instance.id = value;
        return true;
      case 'name':
        if (value is! String?) return false;
        instance.name = value;
        return true;
      case 'code':
        if (value is! String?) return false;
        instance.code = value;
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
