# MariaDB 12.3 LTS with phpMyAdmin and Backups: Railway template spec

## Listing

| Field | Value |
|---|---|
| Name | **MariaDB 12.3 LTS with phpMyAdmin and Backups** (44 chars). The brief proposed "11.8 LTS"; 12.3 is the newest LTS series and is GA (see Pinned versions), so the label was changed as instructed. |
| Description | MySQL-compatible MariaDB LTS, tuned, with phpMyAdmin and daily backups. (71 chars) |
| Category | Storage |
| Tags | mariadb, mysql, database, sql, phpmyadmin, backups, lts |
| Icon | `https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/mariadb.svg` (200, image/svg+xml) |

The listing is delivered as written: "MySQL-compatible" = Railway MySQL's variable names (`MYSQL_URL`, `MYSQL_PUBLIC_URL`, `MYSQLHOST`, ...) and a collation every MySQL client knows; "tuned" = memory-aware InnoDB and connection sizing at every boot; "phpMyAdmin" = pre-connected web UI; "daily backups" = the cron job that dumps to a Railway Bucket with retention.

## Base market templates

Read with `template(code:)` on `backboard.railway.com/graphql/v2` on 2026-10-31; saved in `../_market/`.

| Market template | Topology | Kept | Problems fixed |
|---|---|---|---|
| `mysql` "MySQL" (Railway's own, 222k active) | `mysql:8`, volume `/var/lib/mysql`, start command `docker-entrypoint.sh mysqld --innodb-use-native-aio=0 --disable-log-bin --performance_schema=0 --innodb-buffer-pool-size=1G` | **Base for the variable contract**: `MYSQLHOST/PORT/USER/PASSWORD/DATABASE`, `MYSQL_URL`, `MYSQL_DATABASE`, `MYSQL_ROOT_PASSWORD`, letters-only style secrets; `innodb_use_native_aio=0` | MySQL, not MariaDB; the URLs log in as **root**; fixed 1 GB buffer pool whatever the memory limit; no admin UI, no off-volume backups. (Railway's MySQL docs say `MYSQL_PUBLIC_URL` is populated once public access via the TCP proxy is enabled; it is not in the serialized config, so this template defines it next to its TCP proxy.) |
| `Onvy0F` "MariaDB" (313 active, 2023) | `mariadb:latest`, volume, TCP proxy, `MARIADB_*` variables and `MARIADB_PRIVATE_URL` / `MARIADB_PUBLIC_URL` | **Base for the MariaDB side**: official image, app user + database, TCP proxy, public URL variable | `latest` now resolves to **13.0** (a rolling, non-LTS series) and major jumps happen without `MARIADB_AUTO_UPGRADE`; it sets `MARIADB_HOST` on the server itself, which MariaDB's own clients read as their default host (see below); no tuning, no UI, no backups, no Railway-MySQL names |
| `BrjaHe` "MariaDB Starter Package" (49 active) | repo `railwayapp-templates/mariaDB` (`FROM mariadb:latest`) + `adminer:latest` with a public domain | Idea of a bundled web UI | User, password and database are empty required inputs; floating tags on both services; Adminer's public login page lets any visitor try any server address (no server lock); no backups |
| `phpmyadmin` (35 active) | `linuxserver/phpmyadmin` (untagged), public domain, `PMA_ARBITRARY=1` | phpMyAdmin as the UI | Arbitrary-server login on a public page (anyone can probe hosts on the private network), untagged image, s6-overlay image (Rule 8.3 risk), no database |

Upstream used for everything else: `MariaDB/mariadb-docker` (`12.3/Dockerfile`, `12.3/docker-entrypoint.sh`), `MariaDB/server` at tag `mariadb-12.3.3` (`sql/mysqld.cc`, `sql/sys_vars.cc`, `storage/innobase/handler/ha_innodb.cc`, `client/mysqldump.cc`, `client/mysql.cc`, `mysys/my_default.c`, `mysys/my_getopt.c`, `sql/charset_collations.cc`, `debian/additions/*`), `phpmyadmin/docker` (`config.inc.php`, `docker-entrypoint.sh`, `apache/Dockerfile`) and `phpmyadmin/phpmyadmin` at `RELEASE_5_2_3` (`libraries/config.default.php`, `Config.php`, `Logging.php`, `AuthenticationPlugin.php`). No market README text was reused.

## Pinned versions

| Service | Image / build | Version | Released | Checked |
|---|---|---|---|---|
| MariaDB | `mariadb:12.3.3` (digest `sha256:d46e102f…`, amd64 + arm64; same digest as the `lts` tag) | MariaDB Server 12.3.3 (`MARIADB_VERSION=1:12.3.3+maria~ubu2404`), Ubuntu 24.04 base | 12.3.3: 2026-08-22; image rebuilt 2026-10-26 | 2026-10-31 |
| phpMyAdmin | `phpmyadmin:5.2.3-apache` (digest `sha256:fb0cb638…`) | phpMyAdmin 5.2.3 (latest release, 2025-10-08) on PHP 8.3.36 + Apache | image rebuilt 2026-10-28 | 2026-10-31 |
| MariaDB Backup | repo `baranberkay96/mariadb-railway`, `/services/backup`: `FROM mariadb:12.3.3` + rclone from `rclone/rclone:1.75.2` | mariadb-dump 12.3.3, zstd (Ubuntu), rclone 1.75.2 (latest release) | rclone 1.75.2: 2026-10-09 | 2026-10-31 |

**Why 12.3 and not 11.8.** mariadb.org's maintenance policy names one LTS per year; the downloads REST API lists **12.3 as "Stable, Long Term Support"** (12.3.2 GA on 2026-05-29, after 12.3.0 preview and 12.3.1 RC) with community end of life **2029-06-12**, and the official image's `lts` tag points at 12.3.3. 13.0 is a rolling release and 13.1 is an RC. The mariadb.org policy page and the REST API disagree on 11.8's end of life (2028-06-04 vs 2030-02-13); 12.3's date is the same in both.

**Upgrade.** Patch releases: change the tag on MariaDB and in `services/backup/Dockerfile` in one change; `MARIADB_AUTO_UPGRADE=1` makes the entrypoint back up the system tables (`system_mysql_backup_*.sql.zst` in the volume) and run `mariadb-upgrade`. Moving to the next LTS is the same step with a backup taken first. phpMyAdmin: change the tag.

## Architecture

```
 Apps on Railway ── MYSQL_URL / MARIADB_URL ──► MariaDB :3306 (private, IPv4 + IPv6 listeners)
                                                  │  volume /var/lib/mysql
 External clients ── MYSQL_PUBLIC_URL ─────────► │  TCP proxy → 3306 (TLS offered, self-signed)
                                                  │  start command: zz-railway.cnf from cgroup limits
 Browser ── https://{phpmyadmin domain} ──► phpMyAdmin :80 ──private──► MariaDB
              (cookie login with a MariaDB account; root off; no free-text server field)
                                                  ▲
 MariaDB Backup (cron 03:30 UTC) ─────────────────┘ mariadb-dump --system=users + --single-transaction per database
        │ zstd → rclone rcat (streamed, nothing on local disk)
        ▼
 Bucket (Railway Bucket, private S3): mariadb/{UTC timestamp}/users.sql.zst, {db}.sql.zst, MANIFEST.txt
```

## Services

### MariaDB

| Setting | Value |
|---|---|
| Source | image `mariadb:12.3.3` |
| Start command | `/bin/bash -c '{tuning script}' mariadb-start mariadbd` (2,360 chars; readable source `services/mariadb/mariadb-tune.sh`, regenerate with `services/mariadb/to-start-command.py --write`) |
| Volume | `/var/lib/mysql` (the image's datadir) |
| Networking | private `mariadb.railway.internal:3306`; **TCP proxy on 3306** for the public URLs |
| Healthcheck | none (not HTTP) |
| Restart | ON_FAILURE, 10 retries; `RAILWAY_DEPLOYMENT_DRAINING_SECONDS=60` for a clean InnoDB shutdown |

Railway's start command replaces the image ENTRYPOINT, so the script ends with `exec docker-entrypoint.sh mariadbd ${DB_EXTRA_ARGS}`: first-boot initialisation, user/database creation, `gosu` to the `mysql` user and auto-upgrade all stay the image's. Before that it writes `/etc/mysql/conf.d/zz-railway.cnf` (`[mariadbd]`). The image reads `mariadb.conf.d/` first and `conf.d/` last (checked in the image layer), so the file overrides the packaged defaults; `DB_EXTRA_ARGS` on the command line overrides the file. The deploy log shows one `mariadb-tune: ...` line with every value.

Always written:

| Setting | Value | Why |
|---|---|---|
| `character_set_server` / `collation_server` | `utf8mb4` / `DB_COLLATION` (default `utf8mb4_unicode_ci`) | MariaDB 12.3's own default is `utf8mb4_uca1400_ai_ci`, whose collation IDs older MySQL drivers do not know and whose dumps MySQL cannot import. `utf8mb4_unicode_ci` exists in MySQL 5.7/8 and MariaDB. |
| `character_set_collations` | `utf8mb4=` the same collation (skipped for `utf8mb4_uca1400_ai_ci`) | Otherwise a bare `CHARSET utf8mb4` in a migration maps to uca1400 (MariaDB 11.5+ default map), not to the server collation. |
| `max_allowed_packet` | 64M | MySQL 8's default (MariaDB: 16M); large rows and imports. |
| `innodb_use_native_aio` | 0 | Same as Railway's MySQL; avoids `io_setup()` limits on shared hosts. |
| `ignore_db_dirs` | `lost+found` | Railway volumes are ext4 with `lost+found` at the root; otherwise it shows up as database `#mysql50#lost+found`. |
| Slow query log | only with `DB_SLOW_QUERY_LOG=on`: `log_output=TABLE`, `log_slow_query=ON`, `log_slow_query_time=DB_LONG_QUERY_TIME` (2 s) | Readable as `SELECT * FROM mysql.slow_log` (root, or phpMyAdmin with root enabled). |

Sizing with `DB_TUNING=auto` (B = budget in MB: `DB_MEMORY_LIMIT_MB`, else the cgroup v2/v1 memory limit capped at 8192, at least 256):

| Setting | Rule | 1 GB limit | 2 GB | 8 GB or more |
|---|---|---|---|---|
| `innodb_buffer_pool_size` | `DB_BUFFER_POOL_MB`, else B/2 (min 128 MB) | 512M | 1024M | 4096M |
| `innodb_log_file_size` | pool/4, 96–512 MB | 128M | 256M | 512M |
| `max_connections` | `DB_MAX_CONNECTIONS`, else B/8 within 100–500 | 128 | 256 | 500 |
| `tmp_table_size` = `max_heap_table_size` | B/64, 16–64 MB | 16M | 32M | 64M |
| `innodb_io_capacity` / `_max` | fixed | 1000 / 2000 | | |

The buffer pool is reserved, not filled: pages are allocated as data is read, so a 4 GB pool on a 200 MB database costs 200 MB. The 8 GB auto cap stops a plan-sized cgroup limit (e.g. 48 GB) from sizing caches for RAM the database never uses; raise it with `DB_MEMORY_LIMIT_MB` after resizing the service.

No `bind-address` is written on purpose. In `sql/mysqld.cc` (12.3.3), without one `getaddrinfo(NULL, AI_PASSIVE)` returns both wildcards and mariadbd opens a `0.0.0.0` and a `::` socket (IPv4 + IPv6, a failed IPv6 socket is only a warning). With `bind-address=::` it would set `IPV6_V6ONLY` and stop answering on IPv4. The image already comments out the packaged `bind-address = 127.0.0.1`.

**Why there is no `MARIADB_HOST` / `MARIADB_PORT` variable** (the brief asked for `MARIADB_*` equivalents): the `mariadb`, `mariadb-dump` and `mariadb-admin` clients in 12.3 read `MARIADB_HOST` as their default host (`client/mysql.cc`, `client/mysqldump.cc`, `client/mysqladmin.cc`). The image's upgrade step runs `mariadb-dump --socket=...` without `-h` while the temporary server has `--skip-networking`; a `MARIADB_HOST` on this service would turn that into a TCP connection to the private domain and stop the container on the next version upgrade. Apps use `MYSQLHOST`/`MYSQLPORT` or the URLs instead.

Connection variables (reference them as `${{MariaDB.NAME}}`):

| Variable | Value | Notes |
|---|---|---|
| `MYSQL_URL` | `mysql://railway:{pw}@mariadb.railway.internal:3306/railway` | Same name and format as Railway MySQL |
| `MYSQL_PUBLIC_URL` | `mysql://railway:{pw}@{proxy domain}:{proxy port}/railway` | TCP proxy; egress billed |
| `MYSQLHOST`, `MYSQLPORT`, `MYSQLUSER`, `MYSQLPASSWORD`, `MYSQLDATABASE` | private host, 3306, app user, its password, `railway` | Railway MySQL names (Data panel) |
| `MYSQL_DATABASE`, `MYSQL_ROOT_PASSWORD` | = `MARIADB_DATABASE`, `MARIADB_ROOT_PASSWORD` | Railway MySQL names; the entrypoint also reads them as aliases (same values) |
| `MARIADB_URL`, `MARIADB_PUBLIC_URL` | `mariadb://...` private / proxy | For MariaDB connectors |
| `MARIADB_USER`, `MARIADB_PASSWORD`, `MARIADB_DATABASE`, `MARIADB_ROOT_PASSWORD` | `railway`, `secret(32)`, `railway`, `secret(32)` | Entrypoint inputs, first boot only |

Difference to Railway MySQL: `MYSQLUSER` and the URLs use the **app user** (all privileges on `railway` only), not root. An app that must create other databases can switch to root by setting `MYSQLUSER=root` and `MYSQLPASSWORD=${{MARIADB_ROOT_PASSWORD}}`; every URL follows.

### phpMyAdmin

| Setting | Value |
|---|---|
| Source | image `phpmyadmin:5.2.3-apache` |
| Start command | `/bin/bash -c '{script}' pma-start` (1,195 chars; source `services/phpmyadmin/pma-start.sh`, regenerate with `services/phpmyadmin/to-template.py --write`), then the image's `/docker-entrypoint.sh apache2-foreground` |
| Networking | public HTTPS domain → port 80; `PORT=80` |
| Healthcheck | `/` (login page, PHP must run), 120 s |
| Restart | ON_FAILURE, 10 retries |

- **Pre-connected:** `PMA_HOST=${{MariaDB.RAILWAY_PRIVATE_DOMAIN}}`, `PMA_PORT=${{MariaDB.MYSQLPORT}}`. The upstream `config.inc.php` builds one server with cookie authentication.
- **Auth = MariaDB accounts.** There is no separate phpMyAdmin user or setup page: the official image deletes `setup/` at build time (checked: absent from the image layer), and every page past the login needs valid database credentials. Log in with `MARIADB_USER` / `MARIADB_PASSWORD`.
- **Hardening** (`services/phpmyadmin/config.user.inc.php`, shipped as `PMA_USER_CONFIG_BASE64`, which the image's entrypoint decodes to `/etc/phpmyadmin/config.user.inc.php` at every start): `AllowRoot` only when `PMA_ALLOW_ROOT=true` (default **false**); `AllowNoPassword=false` (upstream's config sets true); `AllowArbitraryServer=false` regardless of `PMA_ARBITRARY`; `hide_connection_errors=true`; `AuthLog='php'`, so `user denied: {name} (...)` lines appear in the service log (the default `auto` picks syslog, which has no daemon in the container); `SendErrorReports='never'`.
- **Root off by default:** the web UI is public, and the root password unlocks every database and account. Day-to-day work happens as the app user. For server-wide tasks (users, other databases, `mysql.slow_log`) set `PMA_ALLOW_ROOT=true`, redeploy, and set it back afterwards; or use `mariadb` with `MYSQL_PUBLIC_URL`'s host and port.
- **Start script:** keeps exactly one Apache MPM. The image enables `mpm_event` in one layer and removes it with whiteout files (`.wh.mpm_event.load`) in the next (checked in the layers); "AH00534: More than one MPM loaded" has been reported for stock PHP/Apache images on Railway, and the guard re-enables `mpm_prefork` only if the count is wrong. It also caps prefork workers (`PMA_APACHE_WORKERS`, default 10), sets `ServerTokens Prod`, and turns PHP `display_errors` off.
- HTTPS is detected from Railway's `X-Forwarded-Proto` (phpMyAdmin `Config::isHttps()`), so cookies are `Secure` and custom domains work without `PMA_ABSOLUTE_URI`.
- No 2FA: phpMyAdmin's two-factor login needs its configuration storage database; not set up by the template.

### MariaDB Backup

| Setting | Value |
|---|---|
| Source | repo `baranberkay96/mariadb-railway`, root `/services/backup` (Dockerfile `FROM mariadb:12.3.3`, rclone binary copied from `rclone/rclone:1.75.2`, runs as user `mysql`) |
| Cron | `30 3 * * *` (daily 03:30 UTC; Railway skips a run while the previous one is active) |
| Restart | NEVER (each run exits; failures show as `CRASHED` in Cron Runs) |

Each run (`services/backup/mariadb-bucket-backup.sh`):

1. Validates every setting, writes the client options (host, port, user, escaped password, TLS mode) to a 0600 file so the password is not in the process list, waits up to `BACKUP_WAIT_SECONDS` for `mariadb-admin ping`, then checks the login with `SELECT VERSION()` (fails fast on a wrong password) and warns if server and client minor versions differ.
2. `mariadb-dump --system=users --insert-ignore` → `users.sql.zst` (accounts, roles, grants as `CREATE USER IF NOT EXISTS` + `GRANT`).
3. One `mariadb-dump --single-transaction --quick --routines --events --triggers --hex-blob --default-character-set=utf8mb4 --max-allowed-packet=1G --databases {db}` per database (all except `information_schema`, `performance_schema`, `sys`, `mysql`, or `BACKUP_DATABASES`), piped through `zstd -{BACKUP_ZSTD_LEVEL} -T{1..4, from cpu.max}` to `rclone rcat`. Any failing step of the pipe fails that database (`pipefail`).
4. With `BACKUP_VERIFY=true`, reads each object back, decompresses it (zstd frame checksums) and requires mariadb-dump's `-- Dump completed` footer as the last line. Then writes `MANIFEST.txt` last.
5. Retention: deletes complete runs older than `BACKUP_RETENTION_DAYS` (14) but always keeps the newest `BACKUP_KEEP_MIN` (3, including the run just made); deletes incomplete runs older than 2 days; ignores folders that are not run timestamps. A failed run deletes nothing.

`--single-transaction` gives a consistent snapshot per database for InnoDB tables without a global lock; MyISAM/Aria tables are dumped without one. Run on demand: `railway cron run --service "MariaDB Backup"` (or the Cron Runs tab).

TLS to MariaDB: `BACKUP_TLS=verify` (default) uses MariaDB 11.4+'s zero-configuration TLS: the server generates a self-signed certificate and the client checks it through the password (`include/sslopt-vars.h`). `require` skips the check; `off` uses plain TCP on the private network.

### Bucket

Railway Bucket named `Bucket` (private, S3-compatible, virtual-hosted URLs). The backup job references `BUCKET`, `ENDPOINT`, `REGION`, `ACCESS_KEY_ID` and `SECRET_ACCESS_KEY`. Buckets have no lifecycle rules, which is why retention lives in the job.

## Restore

1. Bucket → Files → `mariadb/{timestamp}/`, download `{database}.sql.zst` (`MANIFEST.txt` lists the files of a complete run).
2. Replay with a **MariaDB** client (10.6.18+/11.4.2+); the dump's first line is MariaDB's sandbox-mode marker, which MySQL's `mysql` client rejects (drop it with `tail -n +2` if you must use MySQL's client):
   `zstd -dc railway.sql.zst | mariadb --host={proxy domain} --port={proxy port} --user=root --password railway`
   The dump contains `CREATE DATABASE IF NOT EXISTS` and `USE`, and `DROP TABLE IF EXISTS` before each table, so it restores into the same database name. To restore under another name, remove those two statements first: `zstd -dc railway.sql.zst | sed -e '/^CREATE DATABASE/d' -e '/^USE /d' | mariadb ... other_db`.
3. `users.sql.zst` recreates accounts and grants on a **fresh** server (`CREATE USER IF NOT EXISTS`: existing accounts, including root, keep their current passwords).
4. phpMyAdmin's Import tab can also load a decompressed dump up to `UPLOAD_LIMIT` (64 MB); it does not read `.zst`.

Railway's volume backups (MariaDB → Backups) are complementary: they snapshot the volume, these dumps are portable SQL.

## Required input

None. Passwords come from `secret(32)` (letters and digits, URL-safe), the Bucket is created by the template, and every cross-service value is a reference.

## First login

1. Open the phpMyAdmin domain, log in with `MARIADB_USER` (`railway`) and `MARIADB_PASSWORD` from the MariaDB service's Variables tab.
2. The `railway` database is empty and ready; `SHOW VARIABLES LIKE 'collation_server'` shows `utf8mb4_unicode_ci`.
3. In another Railway service, set `DATABASE_URL=${{MariaDB.MYSQL_URL}}` (or the individual `MYSQL*` references).
4. From your machine: `mariadb --host={RAILWAY_TCP_PROXY_DOMAIN} --port={RAILWAY_TCP_PROXY_PORT} --user=railway --password railway`.

## Improvements over market templates

1. **Current LTS, pinned**: MariaDB 12.3.3 (community support to 2029-06) instead of `mariadb:latest`, which now resolves to the 13.0 rolling series; `MARIADB_AUTO_UPGRADE=1` so patch and LTS upgrades run `mariadb-upgrade` with a system-table backup.
2. **Drop-in Railway MySQL variables** (`MYSQL_URL`, `MYSQL_PUBLIC_URL`, `MYSQLHOST`, ... `MYSQL_ROOT_PASSWORD`) plus `MARIADB_URL`/`MARIADB_PUBLIC_URL`, with the app user instead of root in every URL.
3. **Memory-aware tuning** from the cgroup limit (buffer pool, redo log, connections, temp tables) instead of MariaDB's 128 MB pool or Railway MySQL's fixed 1 GB; every value overridable.
4. **MySQL-compatible character set**: utf8mb4 with `utf8mb4_unicode_ci` for both the server and bare `CHARSET utf8mb4`, 64 MB packets, `lost+found` hidden.
5. **IPv4 + IPv6 listeners** checked in the server source; no `MARIADB_HOST` trap on the server.
6. **phpMyAdmin pre-connected and locked to that server**: no arbitrary-server field (the market phpMyAdmin template enables it on a public page), root login off by default, no empty passwords, failed logins in the log, MPM guard, pinned image.
7. **Daily verified backups** to a Railway Bucket: accounts + every database, zstd, read-back verification, manifest, age + minimum-count retention. No market template backs up.
8. Optional slow query log, descriptions on every variable, no required input.

## Resource estimate

Railway prices: RAM $10/GB-month, vCPU $20/vCPU-month, volume $0.15/GB-month, Bucket $0.015/GB-month, egress $0.05/GB (uploads to a Bucket count as service egress). Not measured (no container was run for this package); based on typical footprints of these images.

| Service | Idle RAM / CPU | Typical RAM / CPU | Notes |
|---|---|---|---|
| MariaDB | 0.15 GB / 0.01 | 1.0 GB / 0.2 | Buffer pool grows with the working set up to its size; restarts reload the hot page list |
| phpMyAdmin | 0.05 GB / ~0 | 0.08 GB / 0.01 | 2 prefork workers idle, up to `PMA_APACHE_WORKERS` |
| MariaDB Backup | 0 between runs | ~0.15 GB / 0.5 vCPU for a few minutes a day | < $0.10/month |
| Volume | 0.7 GB (system tables + redo log, 512 MB redo at 8 GB budget) | 3 GB | Hobby volumes start at 5 GB |
| Bucket | ~0 | ~6 GB (14 daily runs of a ~0.3 GB compressed dump + minimum runs) | + ~9 GB/month upload egress |

Estimated monthly cost: **idle ≈ $2.70** (0.2 GB × $10 + 0.01 vCPU × $20 + 0.7 GB × $0.15 + small backup runs), **typical ≈ $16** (1.08 GB × $10 + 0.21 vCPU × $20 + 3 GB × $0.15 + 6 GB × $0.015 + 9 GB × $0.05).

Minimum plan: **Trial** boots it (1 GB RAM → 512 MB pool, 128 MB redo; fits a 0.5 GB volume while the data is small); **Hobby** recommended for real data (5 GB volume, more RAM for the pool).

## Verification checklist

Static checks done this round: see `_reports/round7/89-mariadb.md`. On the first Railway deploy:

- [ ] All three services deploy; the Backup image builds (its `RUN` line prints the mariadb-dump, zstd and rclone versions).
- [ ] MariaDB log: `mariadb-tune: budget ...MB (container ...MB, host ...MB)`, the settings line, `Server socket created on IP: '0.0.0.0'` **and** `'::'`, `ready for connections`, version `12.3.3-MariaDB`. No `unknown variable` error.
- [ ] `mariadb` via `MYSQL_PUBLIC_URL`'s host/port as `railway`: `SHOW VARIABLES WHERE Variable_name IN ('innodb_buffer_pool_size','max_connections','collation_server','character_set_collations','innodb_use_native_aio','have_ssl')` matches the log; `SHOW DATABASES` has no `#mysql50#lost+found`; `\s` shows an SSL cipher.
- [ ] `CREATE TABLE t (s VARCHAR(10)) CHARSET utf8mb4; SHOW CREATE TABLE t;` → `COLLATE=utf8mb4_unicode_ci`.
- [ ] From another Railway service: connect with `${{MariaDB.MYSQL_URL}}` (Node `mysql2` and PHP `mysqli` if possible).
- [ ] phpMyAdmin: healthcheck green; log shows `pma-start: Apache prefork MaxRequestWorkers 10` and no `AH00534`; login as `railway` works; login as root shows "Access denied" and the log has `user denied: root (root-denied)`; there is no server field on the login page; `/setup/` returns 404.
- [ ] `railway cron run --service "MariaDB Backup"` → `EXITED`; Bucket has `mariadb/{timestamp}/users.sql.zst`, `railway.sql.zst`, `MANIFEST.txt`; the log says `read back and verified`; restore `railway.sql.zst` with step 2 of Restore into a scratch database.
- [ ] Redeploy MariaDB: data still there; `zz-railway.cnf` rewritten; change `DB_MEMORY_LIMIT_MB=2048` → pool 1024M after redeploy.
- [ ] `DB_SLOW_QUERY_LOG=on`, redeploy, `SELECT SLEEP(3)`, then `SELECT * FROM mysql.slow_log` as root shows it.

## Open questions

- **Railway Data panel** for a MariaDB image: the variables match Railway MySQL's, but whether the panel recognises the service is not verified.
- **Inherited `VOLUME /var/lib/mysql`** in the Backup image (`FROM mariadb`): Rule 8.17 concerns a `VOLUME` instruction in our Dockerfile (there is none). The WordPress template builds `FROM wordpress` (which declares `VOLUME`) and deploys, so this is expected to work; confirm on the first build.
- **Zero-configuration TLS check from the backup job** (`BACKUP_TLS=verify`) relies on root using `mysql_native_password` (MariaDB's default) and the server's auto-generated certificate. If the run fails with a TLS error, set `BACKUP_TLS=require`.
- **cgroup values on Railway**: `memory.max` may be the plan maximum; the 8 GB cap and `DB_MEMORY_LIMIT_MB` cover it. The deploy log shows what was detected.
- **Collation default**: `utf8mb4_unicode_ci` favours MySQL compatibility over MariaDB's newer `uca1400` rules; users who want the latter set `DB_COLLATION=utf8mb4_uca1400_ai_ci` before the first boot (existing tables keep their collation).
- **AH00534 root cause** on Railway is not publicly confirmed; the guard covers lost whiteout files, which is the mechanism visible in the image layers.
- **Large databases**: dumps stream in 16 MiB parts (up to ~150 GiB compressed per database); read-back verification downloads each dump once more. Logical restores of tens of GB take hours; use Railway volume backups for fast full restores.
