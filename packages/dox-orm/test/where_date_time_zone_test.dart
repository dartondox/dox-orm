import 'package:dox_orm/dox_orm.dart';
import 'package:test/test.dart';

import 'connection.dart';

/// whereDate() and the others with a local `DateTime`, in a time zone that
/// is not UTC. It is skipped in UTC. CI runs it in the entries with
/// `TZ=Asia/Yangon` (+06:30), see ci/test-matrix.json. Locally:
/// `TZ=Asia/Yangon DRIVER=sqlite dart test test/where_date_time_zone_test.dart`
void main() async {
  bool utc = DateTime(2024).timeZoneOffset == Duration.zero;

  await initQueryBuilder();

  QueryBuilder<Map<String, dynamic>> rows() => QueryBuilder.table('qx_tz');

  group(
    'Date wheres, local time zone |',
    skip: utc ? 'runs only when TZ is not UTC' : false,
    () {
      /// 00:30 local is the day before in UTC, so a part taken from the
      /// wrong clock finds no row
      DateTime joined = DateTime(2024, 5, 1, 0, 30);

      setUp(() async {
        await Schema().dropIfExists('qx_tz');
        await Schema().create('qx_tz', (Table table) {
          table.id();
          table.dateTime('joined_at');
        });
        await rows().insert(<String, dynamic>{'joined_at': joined});
      });

      tearDown(() async {
        await Schema().dropIfExists('qx_tz');
      });

      test('a DateTime value is read like where() binds it', () async {
        expect(joined.toUtc().day, isNot(joined.day));
        expect(await rows().where('joined_at', joined).count(), 1);
        expect(await rows().whereDate('joined_at', joined).count(), 1);
        expect(await rows().whereTime('joined_at', joined).count(), 1);
        expect(await rows().whereYear('joined_at', joined).count(), 1);
        expect(await rows().whereMonth('joined_at', joined).count(), 1);
        expect(await rows().whereDay('joined_at', joined).count(), 1);
      });
    },
  );
}
