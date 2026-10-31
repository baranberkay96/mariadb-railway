#!/bin/bash
# Readable source of the MariaDB service's start command. Nothing is built from
# this folder: the MariaDB service runs the official image (mariadb:12.3.3) and
# template.json carries this script joined into one line:
#
#   /bin/bash -c '<this script>' mariadb-start mariadbd
#
# Railway's start command replaces the image ENTRYPOINT, so the script ends by
# exec-ing the image's own entrypoint (docker-entrypoint.sh mariadbd). Regenerate
# the line with `python3 to-start-command.py` after editing (`--check` compares it
# with template.json). Rules that keep the one-line form valid: no single quotes,
# no backslashes, comments only on their own lines, and every line is a complete
# command or ends in then/do/else.
#
# At every boot it writes /etc/mysql/conf.d/zz-railway.cnf. The image reads
# /etc/mysql/mariadb.conf.d/ first and /etc/mysql/conf.d/ last, so this file
# wins over the packaged defaults; DB_EXTRA_ARGS (mariadbd command-line options)
# wins over this file.
#   Always:  utf8mb4 server character set with DB_COLLATION, max_allowed_packet
#            64M, innodb_use_native_aio=0 (as Railway's own MySQL), the volume's
#            lost+found directory ignored as a database, optional slow query log.
#   DB_TUNING=auto (default): InnoDB buffer pool, redo log, max_connections and
#            in-memory temp tables sized from the container memory limit
#            (cgroup v2 memory.max, v1 limit_in_bytes), not from the host's RAM.
# No bind-address is written on purpose: without one mariadbd opens separate
# 0.0.0.0 and :: listeners (IPv4 + IPv6). bind-address=:: would be IPv6 only,
# because mariadbd sets IPV6_V6ONLY on its IPv6 socket.
set -e
F=/etc/mysql/conf.d/zz-railway.cnf
X=/tmp/zz-railway.cnf
# k VALUE MIN MAX: clamp. n VALUE FALLBACK: VALUE if it is a whole number. w KEY VALUE: add a setting.
k() { v=$1; if [ $v -lt $2 ]; then v=$2; fi; if [ $v -gt $3 ]; then v=$3; fi; echo $v; }
n() { case "$1" in ""|*[!0-9]*) echo $2 ;; *) echo $1 ;; esac; }
w() { echo "$1 = $2" >> $X; }
echo "# Railway template: rewritten at every boot from the DB_* variables; DB_EXTRA_ARGS overrides it" > $X
echo "[mariadbd]" >> $X
# Character set: utf8mb4 everywhere. utf8mb4_unicode_ci by default because MySQL
# 5.7/8 and every MySQL driver know it; character_set_collations makes a bare
# CHARSET utf8mb4 (common in migrations) use the same collation.
COL="${DB_COLLATION:-utf8mb4_unicode_ci}"
case "$COL" in utf8mb4_) COL=bad ;; utf8mb4_*[!a-z0-9_]*) COL=bad ;; utf8mb4_*) ;; *) COL=bad ;; esac
if [ "$COL" = bad ]; then
echo "mariadb-tune: DB_COLLATION=${DB_COLLATION} is not a utf8mb4 collation name, using utf8mb4_unicode_ci"
COL=utf8mb4_unicode_ci
fi
w character_set_server utf8mb4
w collation_server $COL
if [ "$COL" != utf8mb4_uca1400_ai_ci ]; then
w character_set_collations utf8mb4=$COL
fi
w max_allowed_packet 64M
w innodb_use_native_aio 0
w ignore_db_dirs lost+found
# Slow query log into the mysql.slow_log table (readable with SQL or phpMyAdmin as root).
case "${DB_SLOW_QUERY_LOG:-off}" in on|ON|On|true|TRUE|True|yes|1) SLOW=on ;; *) SLOW=off ;; esac
if [ $SLOW = on ]; then
LQT="${DB_LONG_QUERY_TIME:-2}"
case "$LQT" in ""|.|*[!0-9.]*|*.*.*) LQT=2 ;; esac
w log_output TABLE
w log_slow_query ON
w log_slow_query_time $LQT
fi
if [ "${DB_TUNING:-auto}" = off ]; then
echo "mariadb-tune: DB_TUNING=off, MariaDB defaults apply to memory and connections"
else
# Host RAM in MB (the container sees all of it), then the cgroup limit in MB.
H=$(( $(n "$(grep -m 1 MemTotal /proc/meminfo | tr -s " " | cut -d " " -f 2)" 1048576) / 1024 ))
L=$(cat /sys/fs/cgroup/memory.max 2>/dev/null || cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null || echo max)
M=$(( $(n "$L" $((H * 1048576))) / 1048576 ))
if [ $M -gt $H ]; then M=$H; fi
# Budget: DB_MEMORY_LIMIT_MB, or auto = container limit capped at 8192 MB.
B=$(k $(n "$DB_MEMORY_LIMIT_MB" $(k $M 256 8192)) 256 4194304)
# Buffer pool: DB_BUFFER_POOL_MB, or half the budget. Pages are only allocated as data is read.
P=$(k $(n "$DB_BUFFER_POOL_MB" $(k $((B / 2)) 128 2097152)) 32 4194304)
# Connections: DB_MAX_CONNECTIONS, or budget/8 between 100 and 500.
C=$(k $(n "$DB_MAX_CONNECTIONS" $(k $((B / 8)) 100 500)) 10 100000)
T=$(k $((B / 64)) 16 64)
w innodb_buffer_pool_size ${P}M
w innodb_log_file_size $(k $((P / 4)) 96 512)M
w max_connections $C
w tmp_table_size ${T}M
w max_heap_table_size ${T}M
w innodb_io_capacity 1000
w innodb_io_capacity_max 2000
echo "mariadb-tune: budget ${B}MB (container ${M}MB, host ${H}MB)"
fi
mkdir -p /etc/mysql/conf.d
install -m 644 $X $F
echo "mariadb-tune: $(grep -v "^#" $X | paste -sd " " -)"
# DB_EXTRA_ARGS is split on spaces and passed to mariadbd (no globbing).
set -f
exec docker-entrypoint.sh "$@" ${DB_EXTRA_ARGS:-}
