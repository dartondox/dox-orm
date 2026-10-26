// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'writer.model.dart';

// **************************************************************************
// Generator: DoxModelBuilder
// **************************************************************************

// ignore_for_file: always_specify_types

class WriterGenerator extends Model<Writer> with SoftDeletes<Writer> {
  @override
  String get primaryKey => 'id';

  @override
  Map<String, dynamic> get timestampsColumn => const <String, dynamic>{
    'created_at': null,
    'updated_at': null,
  };

  @override
  String get tableName => 'writers';

  int? get id => tempIdValue as int?;

  set id(int? val) => tempIdValue = val;

  Writer query() => Writer();

  @override
  bool get readsRowDates => true;

  @override
  List<String> get tableColumns => const <String>['id', 'name', 'deleted_at'];

  @override
  List<String> get preloadList => const <String>[];

  @override
  Map<String, Function> get relationsResultMatcher => const <String, Function>{
    'articles': getArticles,
    'firstArticle': getFirstArticle,
    'publishedArticles': getPublishedArticles,
    'topics': getTopics,
  };

  @override
  Map<String, Function> get relationsQueryMatcher => const <String, Function>{
    'articles': queryArticles,
    'firstArticle': queryFirstArticle,
    'publishedArticles': queryPublishedArticles,
    'topics': queryTopics,
  };

  static Future<void> getArticles(List<Model<Writer>> list) async {
    var result = await getHasMany<Writer, Article>(queryArticles(list), list);
    for (dynamic i in list) {
      if (result[i.tempIdValue.toString()] != null) {
        i.articles = result[i.tempIdValue.toString()]!;
      }
    }
  }

  static Article? queryArticles(List<Model<Writer>> list) {
    return hasMany<Writer, Article>(list, () => Article());
  }

  static Future<void> getFirstArticle(List<Model<Writer>> list) async {
    var result = await getHasOne<Writer, Article>(
      queryFirstArticle(list),
      list,
    );
    for (dynamic i in list) {
      if (result[i.tempIdValue.toString()] != null) {
        i.firstArticle = result[i.tempIdValue.toString()]!;
      }
    }
  }

  static Article? queryFirstArticle(List<Model<Writer>> list) {
    return hasOne<Writer, Article>(list, () => Article());
  }

  static Future<void> getPublishedArticles(List<Model<Writer>> list) async {
    var result = await getHasMany<Writer, Article>(
      queryPublishedArticles(list),
      list,
    );
    for (dynamic i in list) {
      if (result[i.tempIdValue.toString()] != null) {
        i.publishedArticles = result[i.tempIdValue.toString()]!;
      }
    }
  }

  static Article? queryPublishedArticles(List<Model<Writer>> list) {
    return hasMany<Writer, Article>(
      list,
      () => Article(),
      onQuery: Writer.onlyPublished,
    );
  }

  static Future<void> getTopics(List<Model<Writer>> list) async {
    var result = await getManyToMany<Writer, Topic>(queryTopics(list), list);
    for (dynamic i in list) {
      if (result[i.tempIdValue.toString()] != null) {
        i.topics = result[i.tempIdValue.toString()]!;
      }
    }
  }

  static Topic? queryTopics(List<Model<Writer>> list) {
    return manyToMany<Writer, Topic>(list, () => Topic());
  }

  @override
  Writer fromMap(Map<String, dynamic> m) => Writer()
    ..id = m['id'] as int?
    ..name = m['name'] as String?
    ..deletedAt = m['deleted_at'] is DateTime?
        ? m['deleted_at'] as DateTime?
        : DateTime.parse(m['deleted_at'] as String);
  @override
  Map<String, dynamic> columnsToMap() {
    Writer instance = this as Writer;
    Map<String, dynamic> map = <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'deleted_at': instance.deletedAt?.toIso8601String(),
    };

    return map;
  }

  @override
  Map<String, dynamic> convertToMap(dynamic i) {
    Writer instance = i as Writer;
    Map<String, dynamic> map = instance.columnsToMap();

    List<String> preload = getPreload();
    if (preload.contains('articles')) {
      map['articles'] = toMap(instance.articles);
    }
    if (preload.contains('firstArticle')) {
      map['first_article'] = toMap(instance.firstArticle);
    }
    if (preload.contains('publishedArticles')) {
      map['published_articles'] = toMap(instance.publishedArticles);
    }
    if (preload.contains('topics')) {
      map['topics'] = toMap(instance.topics);
    }

    return map;
  }
}

// ignore_for_file: always_specify_types

class ArticleGenerator extends Model<Article> with SoftDeletes<Article> {
  @override
  String get primaryKey => 'id';

  @override
  Map<String, dynamic> get timestampsColumn => const <String, dynamic>{
    'created_at': null,
    'updated_at': null,
  };

  @override
  String get tableName => 'articles';

  int? get id => tempIdValue as int?;

  set id(int? val) => tempIdValue = val;

  Article query() => Article();

  @override
  bool get readsRowDates => true;

  @override
  List<String> get tableColumns => const <String>[
    'id',
    'title',
    'published',
    'writer_id',
    'deleted_at',
  ];

  @override
  List<String> get preloadList => const <String>[];

  @override
  Map<String, Function> get relationsResultMatcher => const <String, Function>{
    'writer': getWriter,
    'remarks': getRemarks,
  };

  @override
  Map<String, Function> get relationsQueryMatcher => const <String, Function>{
    'writer': queryWriter,
    'remarks': queryRemarks,
  };

  static Future<void> getWriter(List<Model<Article>> list) async {
    var result = await getBelongsTo<Article, Writer>(queryWriter(list), list);
    for (dynamic i in list) {
      if (result[i.tempIdValue.toString()] != null) {
        i.writer = result[i.tempIdValue.toString()]!;
      }
    }
  }

  static Writer? queryWriter(List<Model<Article>> list) {
    return belongsTo<Article, Writer>(list, () => Writer());
  }

  static Future<void> getRemarks(List<Model<Article>> list) async {
    var result = await getHasMany<Article, Remark>(queryRemarks(list), list);
    for (dynamic i in list) {
      if (result[i.tempIdValue.toString()] != null) {
        i.remarks = result[i.tempIdValue.toString()]!;
      }
    }
  }

  static Remark? queryRemarks(List<Model<Article>> list) {
    return hasMany<Article, Remark>(list, () => Remark());
  }

  static const _publishedCast = BoolCast();

  @override
  Article fromMap(Map<String, dynamic> m) => Article()
    ..id = m['id'] as int?
    ..title = m['title'] as String?
    ..published = _publishedCast.get(m['published'])
    ..writerId = m['writer_id'] as int?
    ..deletedAt = m['deleted_at'] is DateTime?
        ? m['deleted_at'] as DateTime?
        : DateTime.parse(m['deleted_at'] as String);
  @override
  Map<String, dynamic> columnsToMap() {
    Article instance = this as Article;
    Map<String, dynamic> map = <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'published': _publishedCast.set(instance.published),
      'writer_id': instance.writerId,
      'deleted_at': instance.deletedAt?.toIso8601String(),
    };

    return map;
  }

  @override
  Map<String, dynamic> convertToMap(dynamic i) {
    Article instance = i as Article;
    Map<String, dynamic> map = instance.columnsToMap();

    List<String> preload = getPreload();
    if (preload.contains('writer')) {
      map['writer'] = toMap(instance.writer);
    }
    if (preload.contains('remarks')) {
      map['remarks'] = toMap(instance.remarks);
    }

    return map;
  }
}

// ignore_for_file: always_specify_types

class TopicGenerator extends Model<Topic> with SoftDeletes<Topic> {
  @override
  String get primaryKey => 'id';

  @override
  Map<String, dynamic> get timestampsColumn => const <String, dynamic>{
    'created_at': null,
    'updated_at': null,
  };

  @override
  String get tableName => 'topics';

  int? get id => tempIdValue as int?;

  set id(int? val) => tempIdValue = val;

  Topic query() => Topic();

  @override
  bool get readsRowDates => true;

  @override
  List<String> get tableColumns => const <String>['id', 'name', 'deleted_at'];

  @override
  List<String> get preloadList => const <String>[];

  @override
  Map<String, Function> get relationsResultMatcher =>
      const <String, Function>{};

  @override
  Map<String, Function> get relationsQueryMatcher => const <String, Function>{};

  @override
  Topic fromMap(Map<String, dynamic> m) => Topic()
    ..id = m['id'] as int?
    ..name = m['name'] as String?
    ..deletedAt = m['deleted_at'] is DateTime?
        ? m['deleted_at'] as DateTime?
        : DateTime.parse(m['deleted_at'] as String);
  @override
  Map<String, dynamic> columnsToMap() {
    Topic instance = this as Topic;
    Map<String, dynamic> map = <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'deleted_at': instance.deletedAt?.toIso8601String(),
    };

    return map;
  }

  @override
  Map<String, dynamic> convertToMap(dynamic i) {
    Topic instance = i as Topic;
    Map<String, dynamic> map = instance.columnsToMap();

    return map;
  }
}

// ignore_for_file: always_specify_types

class RemarkGenerator extends Model<Remark> {
  @override
  String get primaryKey => 'id';

  @override
  Map<String, dynamic> get timestampsColumn => const <String, dynamic>{
    'created_at': null,
    'updated_at': null,
  };

  @override
  String get tableName => 'remarks';

  int? get id => tempIdValue as int?;

  set id(int? val) => tempIdValue = val;

  Remark query() => Remark();

  @override
  bool get readsRowDates => true;

  @override
  List<String> get tableColumns => const <String>['id', 'body', 'article_id'];

  @override
  List<String> get preloadList => const <String>[];

  @override
  Map<String, Function> get relationsResultMatcher =>
      const <String, Function>{};

  @override
  Map<String, Function> get relationsQueryMatcher => const <String, Function>{};

  @override
  Remark fromMap(Map<String, dynamic> m) => Remark()
    ..id = m['id'] as int?
    ..body = m['body'] as String?
    ..articleId = m['article_id'] as int?;
  @override
  Map<String, dynamic> columnsToMap() {
    Remark instance = this as Remark;
    Map<String, dynamic> map = <String, dynamic>{
      'id': instance.id,
      'body': instance.body,
      'article_id': instance.articleId,
    };

    return map;
  }

  @override
  Map<String, dynamic> convertToMap(dynamic i) {
    Remark instance = i as Remark;
    Map<String, dynamic> map = instance.columnsToMap();

    return map;
  }
}

// ignore_for_file: always_specify_types

class SectionGenerator extends Model<Section> with SoftDeletes<Section> {
  @override
  String get primaryKey => 'id';

  @override
  Map<String, dynamic> get timestampsColumn => const <String, dynamic>{
    'created_at': null,
    'updated_at': null,
  };

  @override
  String get tableName => 'sections';

  int? get id => tempIdValue as int?;

  set id(int? val) => tempIdValue = val;

  Section query() => Section();

  @override
  bool get readsRowDates => true;

  @override
  List<String> get tableColumns => const <String>[
    'id',
    'name',
    'parent_id',
    'deleted_at',
  ];

  @override
  List<String> get preloadList => const <String>[];

  @override
  Map<String, Function> get relationsResultMatcher => const <String, Function>{
    'parent': getParent,
    'children': getChildren,
  };

  @override
  Map<String, Function> get relationsQueryMatcher => const <String, Function>{
    'parent': queryParent,
    'children': queryChildren,
  };

  static Future<void> getParent(List<Model<Section>> list) async {
    var result = await getBelongsTo<Section, Section>(queryParent(list), list);
    for (dynamic i in list) {
      if (result[i.tempIdValue.toString()] != null) {
        i.parent = result[i.tempIdValue.toString()]!;
      }
    }
  }

  static Section? queryParent(List<Model<Section>> list) {
    return belongsTo<Section, Section>(
      list,
      () => Section(),
      foreignKey: 'parent_id',
    );
  }

  static Future<void> getChildren(List<Model<Section>> list) async {
    var result = await getHasMany<Section, Section>(queryChildren(list), list);
    for (dynamic i in list) {
      if (result[i.tempIdValue.toString()] != null) {
        i.children = result[i.tempIdValue.toString()]!;
      }
    }
  }

  static Section? queryChildren(List<Model<Section>> list) {
    return hasMany<Section, Section>(
      list,
      () => Section(),
      foreignKey: 'parent_id',
    );
  }

  @override
  Section fromMap(Map<String, dynamic> m) => Section()
    ..id = m['id'] as int?
    ..name = m['name'] as String?
    ..parentId = m['parent_id'] as int?
    ..deletedAt = m['deleted_at'] is DateTime?
        ? m['deleted_at'] as DateTime?
        : DateTime.parse(m['deleted_at'] as String);
  @override
  Map<String, dynamic> columnsToMap() {
    Section instance = this as Section;
    Map<String, dynamic> map = <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'parent_id': instance.parentId,
      'deleted_at': instance.deletedAt?.toIso8601String(),
    };

    return map;
  }

  @override
  Map<String, dynamic> convertToMap(dynamic i) {
    Section instance = i as Section;
    Map<String, dynamic> map = instance.columnsToMap();

    List<String> preload = getPreload();
    if (preload.contains('parent')) {
      map['parent'] = toMap(instance.parent);
    }
    if (preload.contains('children')) {
      map['children'] = toMap(instance.children);
    }

    return map;
  }
}
