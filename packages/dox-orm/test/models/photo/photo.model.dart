import 'package:dox_orm/dox_orm.dart';

import '../comment/comment.model.dart';

part 'photo.model.g.dart';

@DoxModel()
class Photo extends PhotoGenerator {
  /// test model: takes every key of a map
  @override
  List<String> get guarded => const <String>[];

  @Column()
  String? title;

  @MorphMany(Comment, 'commentable')
  List<Comment> comments = <Comment>[];

  @MorphOne(Comment, 'commentable', onQuery: newest)
  Comment? latestComment;

  static Model<Comment> newest(Comment q) {
    q.orderBy('id');
    return q;
  }
}
