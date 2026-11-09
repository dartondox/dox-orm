#!/usr/bin/env bash
# CI only. Makes the sqlite3 build hook use the SQLite library of the
# runner (libsqlite3.so), so it does not download one from GitHub
# releases. GitHub downloads fail now and then (503/504), and the hook
# does not check the HTTP status.
#
# It adds the `hooks` block to each pubspec.yaml given as an argument
# (the root pubspec of a workspace or an app). Never commit that block to
# a package that is published to pub.dev: users would get it too.
# Run it before `dart pub get`.
set -euo pipefail

# libsqlite3.so (no version in the name) comes from the -dev package.
# grep reads all lines (no -q), so ldconfig gets no SIGPIPE: under
# pipefail that would fail the check and run apt-get for nothing.
if [ "$(uname)" = Linux ] && ! ldconfig -p | grep 'libsqlite3\.so ' >/dev/null; then
  sudo apt-get install -y libsqlite3-dev
fi

for file in "$@"; do
  if grep -q '^hooks:' "$file"; then
    echo "::warning file=$file::has a hooks block already, so sqlite3 was not set to the system library. Add 'sqlite3: source: system' under its user_defines by hand."
    continue
  fi
  printf '\nhooks:\n  user_defines:\n    sqlite3:\n      source: system\n' >> "$file"
  echo "$file: sqlite3 uses the system library"
done
