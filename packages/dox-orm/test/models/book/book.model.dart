import 'package:dox_orm/dox_orm.dart';

part 'book.model.g.dart';

@DoxModel()
class Book extends BookGenerator {
  /// test model: takes every key of a map
  @override
  List<String> get guarded => const <String>[];
  @Column()
  String? title;

  @Column(name: 'author_code')
  String? authorCode;
}
