#!/usr/bin/env bash
# Starts test services as docker containers, in the background.
# They boot while the next steps run. Use ci/wait-services.sh to wait.
#
# Args: the services to start: postgres, mariadb, mysql84.
set -euo pipefail

for s in "$@"; do
  case $s in
    postgres)
      docker run -d --name postgres -p 5432:5432 \
        -e POSTGRES_DB=postgres -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=postgres \
        --health-cmd pg_isready --health-interval 2s postgres:16 ;;
    mariadb)
      docker run -d --name mariadb -p 3306:3306 \
        -e MYSQL_USER=dox -e MYSQL_PASSWORD=password -e MYSQL_DATABASE=dox-framework -e MYSQL_ROOT_PASSWORD=password \
        --health-cmd "healthcheck.sh --connect --innodb_initialized" --health-interval 2s mariadb:11 ;;
    # MySQL 8.4 with the default caching_sha2_password login
    mysql84)
      docker run -d --name mysql84 -p 3307:3306 \
        -e MYSQL_USER=dox -e MYSQL_PASSWORD=password -e MYSQL_DATABASE=dox-framework -e MYSQL_ROOT_PASSWORD=password \
        --health-cmd "mysqladmin ping -h127.0.0.1 -udox -ppassword" --health-interval 2s mysql:8.4 ;;
  esac
done
