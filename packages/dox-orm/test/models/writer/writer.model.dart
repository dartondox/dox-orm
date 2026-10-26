import 'package:dox_orm/dox_orm.dart';

part 'writer.model.g.dart';

/// models for the whereHas() test. Writers, articles and topics are soft
/// deleted, so the test can check that deleted rows do not count.
/// The default keys use the model name: writer_id, article_id and the
/// pivot table topic_writer.
@DoxModel(table: 'writers', softDelete: true, timestamps: false)
class Writer extends WriterGenerator {
  @Column()
  String? name;

  @Column(name: 'deleted_at')
  DateTime? deletedAt;

  @HasMany(Article)
  List<Article> articles = <Article>[];

  @HasOne(Article)
  Article? firstArticle;

  /// onQuery adds a param, so the test can check its key does not clash
  /// with the keys of the parent query
  @HasMany(Article, onQuery: onlyPublished)
  List<Article> publishedArticles = <Article>[];

  @ManyToMany(Topic)
  List<Topic> topics = <Topic>[];

  static Model<Article> onlyPublished(Article q) {
    return q..where('published', true);
  }
}

@DoxModel(table: 'articles', softDelete: true, timestamps: false)
class Article extends ArticleGenerator {
  @Column()
  String? title;

  @Column()
  bool? published;

  @Column()
  int? writerId;

  @Column(name: 'deleted_at')
  DateTime? deletedAt;

  @BelongsTo(Writer)
  Writer? writer;

  @HasMany(Remark)
  List<Remark> remarks = <Remark>[];
}

@DoxModel(table: 'topics', softDelete: true, timestamps: false)
class Topic extends TopicGenerator {
  @Column()
  String? name;

  @Column(name: 'deleted_at')
  DateTime? deletedAt;
}

@DoxModel(table: 'remarks', timestamps: false)
class Remark extends RemarkGenerator {
  @Column()
  String? body;

  @Column()
  int? articleId;
}

/// a model with relations to its own table, for whereHas() and
/// withCount() on the same table
@DoxModel(table: 'sections', softDelete: true, timestamps: false)
class Section extends SectionGenerator {
  @Column()
  String? name;

  @Column()
  int? parentId;

  @Column(name: 'deleted_at')
  DateTime? deletedAt;

  @BelongsTo(Section, foreignKey: 'parent_id')
  Section? parent;

  @HasMany(Section, foreignKey: 'parent_id')
  List<Section> children = <Section>[];
}
