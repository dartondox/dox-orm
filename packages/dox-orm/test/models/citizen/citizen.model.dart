import 'package:dox_orm/dox_orm.dart';

import '../letter/letter.model.dart';

part 'citizen.model.g.dart';

@DoxModel(softDelete: true)
class Citizen extends CitizenGenerator {
  /// test model: takes every key of a map
  @override
  List<String> get guarded => const <String>[];

  @Column()
  String? name;

  @Column(name: 'country_id')
  int? countryId;

  @Column(name: 'home_code')
  String? homeCode;

  @Column()
  String? ref;

  @Column(name: 'manager_id')
  int? managerId;

  @Column(name: 'deleted_at')
  DateTime? deletedAt;

  /// letters of the citizens this citizen manages. the through table is
  /// the same as the parent table.
  @HasManyThrough(Letter, through: Citizen, foreignKey: 'manager_id')
  List<Letter> teamLetters = <Letter>[];
}
