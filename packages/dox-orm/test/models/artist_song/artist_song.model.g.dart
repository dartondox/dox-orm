// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'artist_song.model.dart';

// **************************************************************************
// Generator: DoxModelBuilder
// **************************************************************************

// ignore_for_file: always_specify_types

class ArtistSongGenerator extends Model<ArtistSong> {
  @override
  String get primaryKey => 'id';

  @override
  Map<String, dynamic> get timestampsColumn => const <String, dynamic>{
    'created_at': 'created_at',
    'updated_at': 'updated_at',
  };

  int? get id => tempIdValue as int?;

  set id(int? val) => tempIdValue = val;

  ArtistSong query() => ArtistSong();

  @override
  bool get readsRowDates => true;

  @override
  List<String> get tableColumns => const <String>[
    'id',
    'blog_id',
    'artist_id',
    'created_at',
    'updated_at',
  ];

  @override
  List<String> get preloadList => const <String>[];

  @override
  Map<String, Function> get relationsResultMatcher =>
      const <String, Function>{};

  @override
  Map<String, Function> get relationsQueryMatcher => const <String, Function>{};

  @override
  ArtistSong fromMap(Map<String, dynamic> m) => ArtistSong()
    ..id = m['id'] as int?
    ..songId = m['blog_id'] as int?
    ..artistId = m['artist_id'] as int?
    ..createdAt = switch (m['created_at']) {
      DateTime? v => v,
      Object? v => DateTime.parse(v as String),
    }
    ..updatedAt = switch (m['updated_at']) {
      DateTime? v => v,
      Object? v => DateTime.parse(v as String),
    };
  @override
  Map<String, dynamic> columnsToMap() {
    ArtistSong instance = this as ArtistSong;
    Map<String, dynamic> map = <String, dynamic>{
      'id': instance.id,
      'blog_id': instance.songId,
      'artist_id': instance.artistId,
      'created_at': instance.createdAt?.toIso8601String(),
      'updated_at': instance.updatedAt?.toIso8601String(),
    };

    return map;
  }

  @override
  dynamic $columnValue(String column) {
    ArtistSong instance = this as ArtistSong;
    switch (column) {
      case 'id':
        return instance.id;
      case 'blog_id':
        return instance.songId;
      case 'artist_id':
        return instance.artistId;
      case 'created_at':
        return instance.createdAt?.toIso8601String();
      case 'updated_at':
        return instance.updatedAt?.toIso8601String();
    }
    return super.$columnValue(column);
  }

  @override
  Map<String, dynamic> convertToMap(dynamic i) {
    ArtistSong instance = i as ArtistSong;
    Map<String, dynamic> map = instance.columnsToMap();

    return map;
  }

  @override
  bool setColumnValue(String column, dynamic value) {
    ArtistSong instance = this as ArtistSong;
    switch (column) {
      case 'id':
        if (value is! int?) return false;
        instance.id = value;
        return true;
      case 'blog_id':
        if (value is! int?) return false;
        instance.songId = value;
        return true;
      case 'artist_id':
        if (value is! int?) return false;
        instance.artistId = value;
        return true;
      case 'created_at':
        if (value is! DateTime?) return false;
        instance.createdAt = value;
        return true;
      case 'updated_at':
        if (value is! DateTime?) return false;
        instance.updatedAt = value;
        return true;
    }
    return false;
  }

  @override
  bool $copyColumnsFrom(Model<ArtistSong> other) {
    ArtistSong o = other as ArtistSong;
    (this as ArtistSong)
      ..id = o.id
      ..songId = o.songId
      ..artistId = o.artistId
      ..createdAt = o.createdAt
      ..updatedAt = o.updatedAt;
    return true;
  }
}
