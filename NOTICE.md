# NOTICE

This Railway template is a community package. It is not affiliated with or endorsed by the MariaDB Foundation, MariaDB plc, the phpMyAdmin project, the rclone project or Railway.

## What this template runs

| Component | Source | License |
|---|---|---|
| MariaDB Server 12.3.3 | official Docker image `mariadb:12.3.3` (packages from archive.mariadb.org, Ubuntu 24.04 base), used unmodified | GPL-2.0 (MariaDB Server, https://github.com/MariaDB/server) |
| MariaDB container image and entrypoint | `MariaDB/mariadb-docker` (`12.3/Dockerfile`, `docker-entrypoint.sh`, `healthcheck.sh`), used unmodified through the image | GPL-2.0 (repository LICENSE) |
| phpMyAdmin 5.2.3 | official Docker image `phpmyadmin:5.2.3-apache` (PHP 8.3 + Apache on Debian), used unmodified | GPL-2.0-only (phpMyAdmin, https://github.com/phpmyadmin/phpmyadmin; image label `org.opencontainers.image.licenses`) |
| phpMyAdmin container packaging | `phpmyadmin/docker` (`config.inc.php`, `docker-entrypoint.sh`, `helpers.php`), used unmodified through the image | GPL-3.0 (repository license) |
| rclone 1.75.2 | binary copied from the official image `rclone/rclone:1.75.2` into the backup image | MIT, Copyright (C) 2012 by Nick Craig-Wood |
| Backup image base | `mariadb:12.3.3` (mariadb-dump, mariadb, mariadb-admin from MariaDB Server; zstd, bash, coreutils from Ubuntu) | GPL-2.0 (MariaDB client programs); zstd BSD-3-Clause or GPL-2.0; bash and coreutils GPL-3.0-or-later |
| Icons | `homarr-labs/dashboard-icons` via jsDelivr (mariadb, phpmyadmin, rclone) | Apache-2.0 (icon collection); the logos are trademarks of their owners |

The template only references these images by tag; it does not modify or redistribute MariaDB or phpMyAdmin source code. The backup image adds a shell script and the rclone binary on top of the unmodified MariaDB image; its source is in `services/backup/`.

## Files written for this template

- `services/mariadb/mariadb-tune.sh` and `services/mariadb/to-start-command.py`: the MariaDB start command (readable source and the generator that joins it into `template.json`). It re-invokes the image's own `docker-entrypoint.sh mariadbd`; no file from the image or its repository is copied.
- `services/phpmyadmin/pma-start.sh`, `services/phpmyadmin/config.user.inc.php` and `services/phpmyadmin/to-template.py`: the phpMyAdmin start command and the settings file the image's entrypoint installs from `PMA_USER_CONFIG_BASE64`. The settings use phpMyAdmin's documented `$cfg` keys; no phpMyAdmin file is copied.
- `services/backup/Dockerfile` and `services/backup/mariadb-bucket-backup.sh`: the backup job. Its structure (bucket layout, manifest, retention rules, rclone environment configuration) follows the PostgreSQL backup job written for this template collection (`56-pgvector`), rewritten for `mariadb-dump`.
- `TEMPLATE.md`, `README.md`, `template.json`, this file.

## Reused or not reused

- The four marketplace templates in `../_market/` (`mysql`, `Onvy0F`, `BrjaHe`, `phpmyadmin`) were read for their settings only. Railway's `mysql` template contributed the variable names and the `innodb_use_native_aio=0` setting; no README or description text from any of them is reused.
- `railwayapp-templates/mariaDB` (MIT), the source of `BrjaHe`, was read only (it builds `FROM mariadb:latest` and `FROM adminer:latest`); nothing was copied.

## Upstream material checked (2026-10-31)

- MariaDB downloads REST API (`/rest-api/mariadb/`): 12.3 "Stable", "Long Term Support", end of life 2029-06-12; 12.3.2 released 2026-05-29, 12.3.3 on 2026-08-22; 13.0 Stable/Rolling, 13.1 RC. mariadb.org maintenance policy page (LTS cadence, 12.3 GA 2026-05-28, community EOL 2029-06-12).
- Docker Hub: `mariadb:12.3.3` = `lts` (digest `sha256:d46e102fa8b9b72bfcdeb56f9dd538742092119dc8b11f31fe662605cd234cd9`, image config: entrypoint `docker-entrypoint.sh`, cmd `mariadbd`, `VOLUME /var/lib/mysql`); image layers read for `/etc/mysql/mariadb.cnf` (include order), `mariadb.conf.d/*.cnf`, empty `conf.d/`, `zstd`, `gosu`. `phpmyadmin:5.2.3-apache` (digest `sha256:fb0cb638f7d1c2529407921d86679b2b2faf5bb8542314821e9f16e7e3d2954f`); layers read for Apache `mods-enabled` (mpm_event whiteouts, mpm_prefork), PHP ini files and the absence of `setup/`. `rclone/rclone:1.75.2` (digest `sha256:2687085f718d3c628f7fdfb77c52a1d344332aed543110bb88088f2c70d43eb5`).
- `MariaDB/mariadb-docker` at `bdfe6414` (2026-08-22, "release version bump 2026Q3p2"): `12.3/Dockerfile`, `12.3/docker-entrypoint.sh`.
- `MariaDB/server` at tag `mariadb-12.3.3`: `sql/mysqld.cc` (TCP listeners, `character-set-collations` option, SSL defaults), `sql/sys_vars.cc`, `storage/innobase/handler/ha_innodb.cc`, `sql/charset_collations.cc`, `sql/sql_acl.cc` (default auth plugin), `client/mysqldump.cc` (`--system=users`, footer, sandbox marker), `client/mysql.cc`, `client/mysqladmin.cc` (`MARIADB_HOST`), `include/sslopt-*.h`, `mysys/my_default.c`, `mysys/my_getopt.c`, `debian/additions/`.
- `phpmyadmin/docker` at `4f7341b0` (2026-10-23): `config.inc.php`, `docker-entrypoint.sh`, `apache/Dockerfile`. `phpmyadmin/phpmyadmin` at `RELEASE_5_2_3`: `libraries/config.default.php`, `libraries/classes/Config.php` (`isHttps`), `Logging.php`, `Plugins/AuthenticationPlugin.php`, `Controllers/HomeController.php`. phpMyAdmin version feed: 5.2.3 (2025-10-08) is the current release.
- `rclone/rclone` v1.75.2 `Dockerfile` (`CGO_ENABLED=0`, binary at `/usr/local/bin/rclone`).
