import 'package:dox_orm/dox_orm.dart';

part 'tag.model.g.dart';

@DoxModel()
class Tag extends TagGenerator {
  /// test model: takes every key of a map
  @override
  List<String> get guarded => const <String>[];
  @Column()
  String? title;
}
