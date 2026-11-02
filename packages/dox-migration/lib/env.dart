/// The `.env` reader that migrations use. Tools like the dox CLI can use it
/// to read the same values the Migrator reads.
library;

export 'src/utils/env.dart' show loadEnv;
