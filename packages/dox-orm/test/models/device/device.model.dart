import 'package:dox_orm/dox_orm.dart';

part 'device.model.g.dart';

/// a model with a string (UUID) primary key
@DoxModel(primaryKey: 'uuid', primaryKeyType: String)
class Device extends DeviceGenerator {
  /// test model: takes every key of a map
  @override
  List<String> get guarded => const <String>[];
  @Column()
  String? name;
}
