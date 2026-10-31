# Deploy and Host MariaDB with Railway

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/mariadb-123-lts-with-phpmyadmin-and-back?referralCode=20H68q)

MariaDB is an open-source relational database that speaks the MySQL protocol and SQL dialect. This community template runs MariaDB 12.3 LTS on Railway with Railway-MySQL-compatible connection variables, memory-aware tuning, a pre-connected phpMyAdmin web UI and daily verified backups to a Railway Bucket.

## About Hosting MariaDB

A production MariaDB needs more than the container. The InnoDB buffer pool should match the memory the service actually has, the character set should work with every MySQL driver your apps use, the admin UI must not become an open door, and the data needs copies outside the volume. This template pins the 12.3 long-term-support release, sizes the buffer pool, redo log and connection limit from the container's memory limit at every boot, uses utf8mb4 with a MySQL-compatible collation, listens on IPv4 and IPv6, and exposes the same variable names as Railway's MySQL, so apps written for it connect without code changes. A cron job writes compressed, read-back-verified `mariadb-dump` backups with retention.

## Common Use Cases

- A MySQL-compatible database for WordPress, Laravel, Drupal, Strapi, Directus, Nextcloud or your own app
- Moving an app off Railway MySQL to an open-source GPL database with a long support window
- A shared SQL server for several services, managed through phpMyAdmin
- Development and staging databases that can be reset from yesterday's backup

## Dependencies for MariaDB Hosting

- MariaDB Server 12.3 (included: official `mariadb:12.3.3` image)
- phpMyAdmin 5.2 (included: official `phpmyadmin:5.2.3-apache` image)
- A Railway Bucket for backups (included, created by the template)

### Deployment Dependencies

- MariaDB release and maintenance policy: https://mariadb.org/about/
- MariaDB Docker image: https://hub.docker.com/_/mariadb (source: https://github.com/MariaDB/mariadb-docker)
- mariadb-dump: https://mariadb.com/docs/server/clients-and-utilities/backup-restore-and-import-clients/mariadb-dump
- phpMyAdmin documentation: https://docs.phpmyadmin.net/en/latest/ (image: https://hub.docker.com/_/phpmyadmin)
- Railway TCP Proxy: https://docs.railway.com/networking/tcp-proxy
- Railway Storage Buckets: https://docs.railway.com/storage-buckets
- Railway cron jobs: https://docs.railway.com/cron-jobs

### Implementation Details

| Service | Image | Purpose |
|---|---|---|
| MariaDB | `mariadb:12.3.3` | MariaDB 12.3 LTS, volume at `/var/lib/mysql`, private port 3306 (IPv4 + IPv6), TCP proxy for external clients |
| phpMyAdmin | `phpmyadmin:5.2.3-apache` | Web UI on a public HTTPS domain, connected to MariaDB over the private network |
| MariaDB Backup | built from this repo (`services/backup`) | Daily cron (03:30 UTC): accounts + every database with `mariadb-dump`, zstd, verified, 14-day retention (minimum 3 runs kept) |
| Bucket | Railway Bucket | Private S3 storage for the backups |

**Connection variables** (on the MariaDB service, reference them as `${{MariaDB.NAME}}`):

- `MYSQL_URL`: private URL, same name and format as Railway MySQL, e.g. `DATABASE_URL=${{MariaDB.MYSQL_URL}}`
- `MYSQL_PUBLIC_URL`: from outside Railway through the TCP proxy (egress is billed)
- `MYSQLHOST`, `MYSQLPORT`, `MYSQLUSER`, `MYSQLPASSWORD`, `MYSQLDATABASE`, `MYSQL_DATABASE`, `MYSQL_ROOT_PASSWORD`: Railway MySQL's names
- `MARIADB_URL`, `MARIADB_PUBLIC_URL` (`mariadb://` scheme), `MARIADB_USER`, `MARIADB_PASSWORD`, `MARIADB_DATABASE`, `MARIADB_ROOT_PASSWORD`

One difference to Railway MySQL: the URLs log in as the app user `railway` (all privileges on the `railway` database), not as root. If an app must create its own databases, set `MYSQLUSER=root` and `MYSQLPASSWORD=${{MARIADB_ROOT_PASSWORD}}` on the MariaDB service; the URLs follow.

**First login**

1. Open the phpMyAdmin service's domain.
2. Log in with `MARIADB_USER` (`railway`) and `MARIADB_PASSWORD` from the MariaDB service's Variables tab.
3. Point your app at `${{MariaDB.MYSQL_URL}}`, or connect from your machine with `mariadb --host={proxy domain} --port={proxy port} --user=railway --password railway`.

**Security defaults**: every password is generated at deploy. phpMyAdmin only talks to this MariaDB (no free-text server field), refuses empty passwords, has no setup page, and does not accept the root account unless you set `PMA_ALLOW_ROOT=true` on the phpMyAdmin service (turn it back off when done). Failed logins are written to the phpMyAdmin log. The TCP proxy is on for drop-in compatibility; remove it under MariaDB → Settings → Networking for a private-only database.

**Tuning**: at every boot the start command writes `zz-railway.cnf` and logs it: buffer pool = half the memory limit (auto budget capped at 8 GB), redo log, `max_connections` and temp tables scale with it, `max_allowed_packet` is 64 MB and the collation is `utf8mb4_unicode_ci`. Override with `DB_MEMORY_LIMIT_MB`, `DB_BUFFER_POOL_MB`, `DB_MAX_CONNECTIONS`, `DB_COLLATION` or any server option in `DB_EXTRA_ARGS` (e.g. `--sql-mode=TRADITIONAL`). `DB_SLOW_QUERY_LOG=on` logs queries slower than `DB_LONG_QUERY_TIME` seconds to the `mysql.slow_log` table. Buffer pool memory is used only as data is read.

**Backups and restore**: dumps land in the Bucket under `mariadb/{timestamp}/` with a `MANIFEST.txt`. Trigger one now with `railway cron run --service "MariaDB Backup"`. To restore, download `{database}.sql.zst` from the Bucket's Files tab and run, with a MariaDB client: `zstd -dc railway.sql.zst | mariadb --host={proxy domain} --port={proxy port} --user=root --password`. The dump recreates its database and tables; `users.sql.zst` recreates accounts on a fresh server. Use the `mariadb` client, not MySQL's `mysql`, which stops at the dump's first line.

**Scaling**: raise the MariaDB service's memory and CPU, then set `DB_MEMORY_LIMIT_MB` to match so the buffer pool grows. Raise `DB_MAX_CONNECTIONS` for many app instances. Hobby volumes start at 5 GB; Pro volumes at 50 GB and can be resized. MariaDB runs as one primary; phpMyAdmin and the backup job do not need scaling.

**Versions and upgrades**: all images are pinned. To move to a newer MariaDB release, change the tag on the MariaDB service and in `services/backup/Dockerfile` together; `MARIADB_AUTO_UPGRADE=1` backs up the system tables and runs `mariadb-upgrade` on the next boot. Take a backup first. phpMyAdmin upgrades by changing its tag.

**Cost**: roughly $3 per month idle and about $16 per month for a few GB of data with daily backups at Railway's usage prices.

### Why Deploy MariaDB on Railway?

Railway runs the database, its admin UI and the backup job together on a private network with persistent volumes and managed buckets, so you get a tuned MariaDB with backups in a few minutes without operating servers. The connection variables match Railway MySQL, and the database grows by raising the service limits and the volume size.
