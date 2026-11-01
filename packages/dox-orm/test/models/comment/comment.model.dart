import 'package:dox_orm/dox_orm.dart';

part 'comment.model.g.dart';

@DoxModel()
class Comment extends CommentGenerator {
  /// test model: takes every key of a map
  @override
  List<String> get guarded => const <String>[];

  @Column()
  String? body;

  @Column()
  int? commentableId;

  @Column()
  String? commentableType;

  @MorphTo()
  Model<dynamic>? commentable;
}
