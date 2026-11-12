import 'package:dox_orm/dox_orm.dart';

part 'letter.model.g.dart';

@DoxModel(softDelete: true)
class Letter extends LetterGenerator {
  /// test model: takes every key of a map
  @override
  List<String> get guarded => const <String>[];

  @Column()
  String? title;

  @Column(name: 'citizen_id')
  int? citizenId;

  @Column(name: 'writer_ref')
  String? writerRef;

  @Column(name: 'deleted_at')
  DateTime? deletedAt;
}
