// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cast_item.model.dart';

// **************************************************************************
// Generator: DoxModelBuilder
// **************************************************************************

// ignore_for_file: always_specify_types

class CastItemGenerator extends Model<CastItem> {
  @override
  String get primaryKey => 'id';

  @override
  Map<String, dynamic> get timestampsColumn => const <String, dynamic>{
    'created_at': null,
    'updated_at': null,
  };

  int? get id => tempIdValue as int?;

  set id(int? val) => tempIdValue = val;

  CastItem query() => CastItem();

  @override
  bool get readsRowDates => true;

  @override
  List<String> get tableColumns => const <String>[
    'id',
    'meta',
    'tags',
    'active',
    'done',
    'status',
    'level',
    'price',
  ];

  @override
  List<String> get preloadList => const <String>[];

  @override
  Map<String, Function> get relationsResultMatcher =>
      const <String, Function>{};

  @override
  Map<String, Function> get relationsQueryMatcher => const <String, Function>{};

  static const _metaCast = JsonCast();
  static const _tagsCast = ListCast<String>();
  static const _activeCast = BoolCast();
  static const _doneCast = BoolCast();
  static const _statusCast = EnumCast(Status.values);
  static const _levelCast = EnumCast<Level>(Level.values, byIndex: true);
  static const _priceCast = MoneyCast();

  @override
  CastItem fromMap(Map<String, dynamic> m) => CastItem()
    ..id = m['id'] as int?
    ..meta = _metaCast.get(m['meta'])
    ..tags = _tagsCast.get(m['tags'])
    ..active = _activeCast.get(m['active'])
    ..done = _doneCast.get(m['done']) as bool
    ..status = _statusCast.get(m['status'])
    ..level = _levelCast.get(m['level'])
    ..price = _priceCast.get(m['price']);
  @override
  Map<String, dynamic> columnsToMap() {
    CastItem instance = this as CastItem;
    Map<String, dynamic> map = <String, dynamic>{
      'id': instance.id,
      'meta': _metaCast.set(instance.meta),
      'tags': _tagsCast.set(instance.tags),
      'active': _activeCast.set(instance.active),
      'done': _doneCast.set(instance.done),
      'status': _statusCast.set(instance.status),
      'level': _levelCast.set(instance.level),
      'price': _priceCast.set(instance.price),
    };

    return map;
  }

  @override
  Map<String, dynamic> convertToMap(dynamic i) {
    CastItem instance = i as CastItem;
    Map<String, dynamic> map = instance.columnsToMap();

    return map;
  }

  @override
  bool setColumnValue(String column, dynamic value) {
    CastItem instance = this as CastItem;
    switch (column) {
      case 'id':
        if (value is! int?) return false;
        instance.id = value;
        return true;
      case 'meta':
        if (value is! Map<String, dynamic>?) return false;
        instance.meta = value;
        return true;
      case 'tags':
        if (value is! List<String>?) return false;
        instance.tags = value;
        return true;
      case 'active':
        if (value is! bool?) return false;
        instance.active = value;
        return true;
      case 'done':
        if (value is! bool) return false;
        instance.done = value;
        return true;
      case 'status':
        if (value is! Status?) return false;
        instance.status = value;
        return true;
      case 'level':
        if (value is! Level?) return false;
        instance.level = value;
        return true;
      case 'price':
        if (value is! Money?) return false;
        instance.price = value;
        return true;
    }
    return false;
  }

  @override
  bool $copyColumnsFrom(Model<CastItem> other) {
    CastItem o = other as CastItem;
    (this as CastItem)
      ..id = o.id
      ..meta = o.meta
      ..tags = o.tags
      ..active = o.active
      ..done = o.done
      ..status = o.status
      ..level = o.level
      ..price = o.price;
    return true;
  }
}
