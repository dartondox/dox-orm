import 'package:dox_orm/dox_orm.dart';

import '../citizen/citizen.model.dart';
import '../letter/letter.model.dart';

part 'country.model.g.dart';

@DoxModel()
class Country extends CountryGenerator {
  /// test model: takes every key of a map
  @override
  List<String> get guarded => const <String>[];

  @Column()
  String? name;

  @Column()
  String? code;

  /// letters of the citizens of this country
  @HasManyThrough(Letter, through: Citizen)
  List<Letter> letters = <Letter>[];

  /// the letter with the highest id
  @HasOneThrough(Letter, through: Citizen, onQuery: newest)
  Letter? latestLetter;

  /// the same rows, matched by other columns
  @HasManyThrough(
    Letter,
    through: Citizen,
    foreignKey: 'home_code',
    localKey: 'code',
    throughForeignKey: 'writer_ref',
    throughLocalKey: 'ref',
  )
  List<Letter> lettersByCode = <Letter>[];

  static Model<Letter> newest(Letter q) {
    q.orderBy('letter.id');
    return q;
  }
}
