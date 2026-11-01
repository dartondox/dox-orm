import 'package:dox_orm/dox_orm.dart';

import '../artist/artist.model.dart';

part 'song.model.g.dart';

@DoxModel()
class Song extends SongGenerator {
  /// test model: takes every key of a map
  @override
  List<String> get guarded => const <String>[];
  @Column()
  String? title;

  @ManyToMany(Artist)
  List<Artist> artists = <Artist>[];
}
