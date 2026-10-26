import 'package:dox_orm/dox_orm.dart';

part 'note.model.g.dart';

/// a model with a beforeSave and no hooks, for the create() test
@DoxModel(table: 'notes')
class Note extends NoteGenerator {
  @Column(beforeSave: slugOf)
  String? slug;

  @Column()
  String? title;

  @Column()
  bool? pinned;

  /// the slug is the title in lower case, with dashes for spaces
  static String? slugOf(Map<String, dynamic> map) {
    String? title = map['title'] as String?;
    return title?.toLowerCase().replaceAll(' ', '-');
  }
}
