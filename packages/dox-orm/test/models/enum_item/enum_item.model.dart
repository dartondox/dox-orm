import 'package:dox_orm/dox_orm.dart';

import '../cast_item/cast_item.model.dart';

part 'enum_item.model.g.dart';

/// a model with enum columns, for stored values the enum does not have
@DoxModel(timestamps: false)
class EnumItem extends EnumItemGenerator {
  /// test model: takes every key of a map
  @override
  List<String> get guarded => const <String>[];

  @Column()
  String? title;

  @Column()
  Status? status;

  @Column(cast: EnumCast<Level>(Level.values, byIndex: true))
  Level? level;

  @Column(cast: EnumCast<Status>(Status.values, unknown: Status.draft))
  Status? fallback;

  /// not nullable, no fallback
  @Column()
  Status kind = Status.draft;
}
