import 'package:dox_orm/dox_orm.dart';

import '../comment/comment.model.dart';

part 'video.model.g.dart';

@DoxModel()
class Video extends VideoGenerator {
  /// test model: takes every key of a map
  @override
  List<String> get guarded => const <String>[];

  @Column()
  String? title;

  @MorphMany(
    Comment,
    'commentable',
    typeColumn: 'commentable_type',
    idColumn: 'commentable_id',
  )
  List<Comment> comments = <Comment>[];
}
