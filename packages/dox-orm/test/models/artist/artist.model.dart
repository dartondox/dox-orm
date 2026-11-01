import 'package:dox_orm/dox_orm.dart';

import '../song/song.model.dart';

part 'artist.model.g.dart';

@DoxModel()
class Artist extends ArtistGenerator {
  /// test model: takes every key of a map
  @override
  List<String> get guarded => const <String>[];
  @Column()
  String? name;

  @ManyToMany(
    Song,
    localKey: 'id',
    relatedKey: 'id',
    pivotForeignKey: 'artist_id',
    pivotRelatedForeignKey: 'song_id',
    pivotTable: 'artist_song',
    withPivot: <String>['role'],
    withTimestamps: true,
    onQuery: onQuery,
  )
  List<Song> songs = <Song>[];

  static Model<Song> onQuery(Song q) {
    return q.debug(false);
  }
}
