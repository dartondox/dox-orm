# dox-orm

The database packages of [Dox](https://dartondox.dev), a web backend framework for Dart.

| Package | What it is |
| --- | --- |
| [`dox_orm`](packages/dox-orm) | Models, relations and a query builder for PostgreSQL, MySQL, MariaDB and SQLite. |
| [`dox_migration`](packages/dox-migration) | Database migrations and seeders. |

Both share one version. Docs: [dartondox.dev](https://dartondox.dev/latest/database/).

## Local development

The repo is a [Dart pub workspace](https://dart.dev/tools/pub/workspaces).
One `dart pub get` at the root links all packages.

To use the Dox packages next to this repo (not pub.dev), clone
[dartondox/dox](https://github.com/dartondox/dox) into `../dox` and add a
`pubspec_overrides.yaml` at the root. It is in `.gitignore`:

```yaml
dependency_overrides:
  dox_annotation:
    path: ../dox/packages/dox-annotation
  dox_builder:
    path: ../dox/packages/dox-builder
  dox_validation:
    path: ../dox/packages/dox-validation
```

## Tests

SQLite needs no server:

```bash
cd packages/dox-orm
DRIVER=sqlite dart test --concurrency=1
```

Postgres and MySQL need a running server. `ci/start-services.sh` starts
them in docker, like CI does:

```bash
ci/start-services.sh postgres mariadb
ci/wait-services.sh postgres mariadb
cd packages/dox-orm
DRIVER=postgres DB_PORT=5432 dart test --concurrency=1
DRIVER=mysql DB_USER=dox DB_PORT=3306 dart test --concurrency=1
cd ../dox-migration
dart test --concurrency=1
```

## Release

1. Set the new `version:` in the root `pubspec.yaml`.
2. Run `bash bin/update_versions.sh`. It sets the version of every package and every sibling constraint.
3. Close the `## Unreleased` section in each `packages/*/CHANGELOG.md`.
4. Merge to `main` and wait for CI.
5. Push the tag: `git tag v<version> && git push origin v<version>`.

The Release workflow publishes the three packages in order. Packages that are already on pub.dev with this version are skipped.
To publish, each package needs automated publishing on pub.dev:
repo `dartondox/dox-orm`, tag pattern `v{{version}}`, environment `pub.dev`.

## License

MIT. See [LICENSE](LICENSE).
