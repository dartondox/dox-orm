import 'package:dox_orm/dox_orm.dart';

part 'artist_song.model.g.dart';

@DoxModel()
class ArtistSong extends ArtistSongGenerator {
  /// test model: takes every key of a map
  @override
  List<String> get guarded => const <String>[];
  @Column(name: 'blog_id')
  int? songId;

  @Column(name: 'artist_id')
  int? artistId;
}
