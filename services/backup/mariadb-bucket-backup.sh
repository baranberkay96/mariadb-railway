#!/bin/bash
# Logical backups of the MariaDB service to a Railway Bucket (S3), with retention.
# Runs once and exits: the "MariaDB Backup" service is a Railway cron job.
#
#   mariadb-bucket-backup backup   users + every database -> Bucket, verify, prune (default)
#   mariadb-bucket-backup list     list the backup runs stored in the Bucket
#
# Layout in the Bucket (one folder per run, UTC timestamp):
#   {BACKUP_PREFIX}/20261031T033000Z/users.sql.zst         accounts, roles, grants (mariadb-dump --system=users)
#   {BACKUP_PREFIX}/20261031T033000Z/{database}.sql.zst    mariadb-dump --single-transaction --databases {database}
#   {BACKUP_PREFIX}/20261031T033000Z/MANIFEST.txt          written last; a run without it is incomplete
#
# Retention: complete runs older than BACKUP_RETENTION_DAYS are deleted, but the
# newest BACKUP_KEEP_MIN complete runs are always kept. Incomplete runs older than
# two days are deleted. A failed run deletes nothing.
set -Eeuo pipefail

PREFIX="${BACKUP_PREFIX:-mariadb}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-14}"
KEEP_MIN="${BACKUP_KEEP_MIN:-3}"
ZSTD_LEVEL="${BACKUP_ZSTD_LEVEL:-3}"
DATABASES="${BACKUP_DATABASES:-}"
WAIT_SECONDS="${BACKUP_WAIT_SECONDS:-300}"
TLS_MODE="${BACKUP_TLS:-verify}"
VERIFY="${BACKUP_VERIFY:-true}"
DB_PORT="${BACKUP_DB_PORT:-3306}"
INCOMPLETE_GRACE_DAYS=2
RUN_RE='^[0-9]{8}T[0-9]{6}Z$'
SYSTEM_DBS=" information_schema performance_schema sys mysql "
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
CNF="${WORK}/client.cnf"
REMOTE=""
ZSTD_THREADS=1
CURRENT_RUN=""

log() { printf '[backup] %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }
die() { log "ERROR: $*" >&2; exit 1; }

require_uint() {
  local name="$1" value="$2" min="$3" max="$4"
  [[ "${value}" =~ ^[0-9]+$ ]] && [ "${value}" -ge "${min}" ] && [ "${value}" -le "${max}" ] \
    || die "${name} must be a whole number from ${min} to ${max} (got '${value}')"
}

validate_settings() {
  require_uint BACKUP_RETENTION_DAYS "${RETENTION_DAYS}" 1 36500
  require_uint BACKUP_KEEP_MIN "${KEEP_MIN}" 1 10000
  require_uint BACKUP_WAIT_SECONDS "${WAIT_SECONDS}" 0 86400
  require_uint BACKUP_ZSTD_LEVEL "${ZSTD_LEVEL}" 1 19
  require_uint BACKUP_DB_PORT "${DB_PORT}" 1 65535
  [[ "${PREFIX}" =~ ^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$ ]] && [[ "/${PREFIX}/" != */./* ]] && [[ "/${PREFIX}/" != */../* ]] \
    || die "BACKUP_PREFIX must be a folder path of letters, digits, '.', '_' and '-' (no '.' or '..' segments)"
  case "${TLS_MODE}" in verify|require|off) ;; *) die "BACKUP_TLS must be verify, require or off (got '${TLS_MODE}')" ;; esac
  case "${VERIFY}" in true|false) ;; *) die "BACKUP_VERIFY must be true or false (got '${VERIFY}')" ;; esac
  local var missing=()
  for var in BACKUP_DB_HOST BACKUP_DB_USER BACKUP_DB_PASSWORD; do
    [ -n "${!var:-}" ] || missing+=("${var}")
  done
  [ "${#missing[@]}" -eq 0 ] || die "MariaDB connection not configured (missing: ${missing[*]})"
  [[ "${BACKUP_DB_HOST}" =~ ^[A-Za-z0-9.:_-]+$ ]] || die "BACKUP_DB_HOST looks invalid: '${BACKUP_DB_HOST}'"
  [[ "${BACKUP_DB_USER}" =~ ^[A-Za-z0-9._@-]+$ ]] || die "BACKUP_DB_USER looks invalid: '${BACKUP_DB_USER}'"
  [[ "${BACKUP_DB_PASSWORD}" != *$'\n'* ]] || die "BACKUP_DB_PASSWORD must not contain a newline"
}

# Client options in a 0600 file, so the password never appears in the process list.
write_client_config() {
  local password="${BACKUP_DB_PASSWORD//\\/\\\\}"
  password="${password//\"/\\\"}"
  (
    umask 077
    {
      printf '[client]\n'
      printf 'host=%s\nport=%s\nuser=%s\npassword="%s"\n' "${BACKUP_DB_HOST}" "${DB_PORT}" "${BACKUP_DB_USER}" "${password}"
      printf 'protocol=TCP\nconnect-timeout=10\n'
      case "${TLS_MODE}" in
        # MariaDB 11.4+ clients verify the server's self-signed certificate through the password.
        verify) printf 'ssl\n' ;;
        require) printf 'ssl\nssl-verify-server-cert=0\n' ;;
        off) printf 'skip-ssl\n' ;;
      esac
    } > "${CNF}"
  )
}

configure_remote() {
  local var missing=()
  for var in BACKUP_S3_BUCKET BACKUP_S3_ENDPOINT BACKUP_S3_ACCESS_KEY_ID BACKUP_S3_SECRET_ACCESS_KEY; do
    [ -n "${!var:-}" ] || missing+=("${var}")
  done
  [ "${#missing[@]}" -eq 0 ] || die "Bucket not configured (missing: ${missing[*]})"
  # rclone remote "bucket", configured only through the environment. Railway
  # Buckets use virtual-hosted-style URLs (path style is rejected).
  export RCLONE_CONFIG="${WORK}/rclone.conf"
  : > "${RCLONE_CONFIG}"
  export RCLONE_CONFIG_BUCKET_TYPE=s3
  export RCLONE_CONFIG_BUCKET_PROVIDER=Other
  export RCLONE_CONFIG_BUCKET_ENDPOINT="${BACKUP_S3_ENDPOINT}"
  export RCLONE_CONFIG_BUCKET_REGION="${BACKUP_S3_REGION:-auto}"
  export RCLONE_CONFIG_BUCKET_ACCESS_KEY_ID="${BACKUP_S3_ACCESS_KEY_ID}"
  export RCLONE_CONFIG_BUCKET_SECRET_ACCESS_KEY="${BACKUP_S3_SECRET_ACCESS_KEY}"
  export RCLONE_CONFIG_BUCKET_FORCE_PATH_STYLE="${BACKUP_S3_FORCE_PATH_STYLE:-false}"
  export RCLONE_CONFIG_BUCKET_NO_CHECK_BUCKET=true
  # 16 MiB parts: streams of unknown size up to ~150 GiB (10,000 parts).
  export RCLONE_CONFIG_BUCKET_CHUNK_SIZE=16M
  REMOTE="bucket:${BACKUP_S3_BUCKET}/${PREFIX}"
}

# zstd threads from the container's CPU quota (not the host's cores), 1 to 4.
detect_threads() {
  local n quota period
  n="$(nproc 2>/dev/null || echo 1)"
  if read -r quota period 2>/dev/null < /sys/fs/cgroup/cpu.max \
     && [[ "${quota}" =~ ^[0-9]+$ ]] && [[ "${period}" =~ ^[0-9]+$ ]] && [ "${period}" -gt 0 ]; then
    quota=$(( (quota + period - 1) / period ))
    if [ "${quota}" -lt "${n}" ]; then n="${quota}"; fi
  fi
  if [ "${n}" -gt 4 ]; then n=4; fi
  if [ "${n}" -lt 1 ]; then n=1; fi
  ZSTD_THREADS="${n}"
}

sql() {
  mariadb --defaults-extra-file="${CNF}" --batch --skip-column-names -e "$1"
}

wait_for_mariadb() {
  local waited=0
  until mariadb-admin --defaults-extra-file="${CNF}" ping > /dev/null 2>&1; do
    [ "${waited}" -ge "${WAIT_SECONDS}" ] && die "MariaDB at ${BACKUP_DB_HOST}:${DB_PORT} not reachable after ${WAIT_SECONDS}s"
    log "waiting for MariaDB at ${BACKUP_DB_HOST}:${DB_PORT}"
    sleep 10
    waited=$((waited + 10))
  done
  # ping succeeds even on a wrong password; this query checks the login itself.
  SERVER_VERSION="$(sql 'SELECT VERSION()')" || die "cannot log in to MariaDB as ${BACKUP_DB_USER} (see the error above)"
}

check_versions() {
  local server_mm client_version client_mm
  client_version="$(mariadb-dump --version | sed -nE 's/.* ([0-9]+\.[0-9]+\.[0-9]+)-MariaDB.*/\1/p')"
  server_mm="$(printf '%s' "${SERVER_VERSION}" | sed -nE 's/^([0-9]+\.[0-9]+).*/\1/p')"
  client_mm="$(printf '%s' "${client_version}" | sed -nE 's/^([0-9]+\.[0-9]+).*/\1/p')"
  CLIENT_VERSION="${client_version:-unknown}"
  log "server MariaDB ${SERVER_VERSION}, mariadb-dump ${CLIENT_VERSION}, zstd -${ZSTD_LEVEL} with ${ZSTD_THREADS} thread(s)"
  if [ -n "${server_mm}" ] && [ -n "${client_mm}" ] && [ "${server_mm}" != "${client_mm}" ]; then
    log "WARNING: server ${server_mm} and mariadb-dump ${client_mm} differ; rebuild this service from the same mariadb tag as the MariaDB service"
  fi
}

list_databases() {
  local db names=()
  if [ -n "${DATABASES}" ]; then
    IFS=',' read -r -a names <<< "${DATABASES}"
    for db in ${names[@]+"${names[@]}"}; do
      db="${db#"${db%%[![:space:]]*}"}"
      db="${db%"${db##*[![:space:]]}"}"
      if [ -n "${db}" ]; then printf '%s\n' "${db}"; fi
    done
    return 0
  fi
  while IFS= read -r db; do
    [ -n "${db}" ] || continue
    case "${SYSTEM_DBS}" in *" ${db} "*) continue ;; esac
    case "${db}" in '#'*) continue ;; esac
    printf '%s\n' "${db}"
  done < <(sql 'SHOW DATABASES')
}

# Object name for a database: keep it readable, never let it escape the run folder.
object_name() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'
}

# Compress stdin and stream it to the Bucket; fails if any step of the pipe fails.
upload_stream() {
  zstd -q -T"${ZSTD_THREADS}" -"${ZSTD_LEVEL}" | rclone rcat --retries 1 "$1"
}

# Read the object back: zstd checks every frame checksum and the dump must end
# with mariadb-dump's footer. (The exit status of mariadb-dump is checked when it
# runs; the footer catches an upload that was cut short.)
verify_object() {
  [ "${VERIFY}" = true ] || return 0
  rclone cat "$1" | zstd -dcq | tail -n 1 | grep -q '^-- Dump completed'
}

object_size() {
  rclone size --json "$1" 2>/dev/null | sed -nE 's/.*"bytes":[[:space:]]*([0-9]+).*/\1/p'
}

DUMP_OPTS=(
  --single-transaction --quick --routines --events --triggers --hex-blob
  --default-character-set=utf8mb4 --max-allowed-packet=1G
)

run_backup() {
  local run_id dest db obj failed=0 dumped=() size checked=""
  [ "${VERIFY}" = true ] && checked=", read back and verified"
  run_id="$(date -u +%Y%m%dT%H%M%SZ)"
  dest="${REMOTE}/${run_id}"
  log "starting run ${run_id} -> ${PREFIX}/${run_id}/ in bucket ${BACKUP_S3_BUCKET}"

  if mariadb-dump --defaults-extra-file="${CNF}" --system=users --insert-ignore \
       | upload_stream "${dest}/users.sql.zst" && verify_object "${dest}/users.sql.zst"; then
    log "users.sql.zst uploaded"
  else
    log "ERROR: accounts and grants dump failed"; failed=1
  fi

  while IFS= read -r db; do
    [ -n "${db}" ] || continue
    obj="$(object_name "${db}").sql.zst"
    log "dumping database ${db} -> ${obj}"
    if mariadb-dump --defaults-extra-file="${CNF}" "${DUMP_OPTS[@]}" --databases "${db}" \
         | upload_stream "${dest}/${obj}" \
       && verify_object "${dest}/${obj}"; then
      size="$(object_size "${dest}/${obj}")"
      log "database ${db} done (${size:-?} bytes compressed${checked})"
      dumped+=("${db}:${obj}:${size:-0}")
    else
      log "ERROR: database ${db} failed"; failed=1
    fi
  done < <(list_databases)

  [ "${#dumped[@]}" -gt 0 ] || { log "ERROR: no database was dumped"; failed=1; }
  if [ "${failed}" -ne 0 ]; then
    die "run ${run_id} is incomplete (no MANIFEST.txt); older backups were left untouched"
  fi

  {
    printf 'run=%s\nserver_version=%s\nmariadb_dump_version=%s\ncompression=zstd-%s\n' \
      "${run_id}" "${SERVER_VERSION}" "${CLIENT_VERSION}" "${ZSTD_LEVEL}"
    printf 'users=users.sql.zst\n'
    printf 'database=%s\n' "${dumped[@]}"
  } | rclone rcat --retries 1 "${dest}/MANIFEST.txt"
  log "run ${run_id} complete: ${#dumped[@]} database(s)"
  CURRENT_RUN="${run_id}"
}

list_runs() {
  # Folder names of every run, oldest first (non-matching folders are ignored).
  rclone lsf --dirs-only "${REMOTE}/" 2>/dev/null | sed 's#/$##' | grep -E "${RUN_RE}" | sort || true
}

list_complete_runs() {
  rclone lsf -R --files-only --max-depth 2 --include 'MANIFEST.txt' "${REMOTE}/" 2>/dev/null \
    | sed 's#/MANIFEST.txt$##' | grep -E "${RUN_RE}" | sort || true
}

prune() {
  local now cutoff incomplete_cutoff complete=() run keep protected=" " total
  now="$(date -u +%s)"
  cutoff="$(date -u -d "@$((now - RETENTION_DAYS * 86400))" +%Y%m%dT%H%M%SZ)"
  incomplete_cutoff="$(date -u -d "@$((now - INCOMPLETE_GRACE_DAYS * 86400))" +%Y%m%dT%H%M%SZ)"
  while IFS= read -r run; do [ -n "${run}" ] && complete+=("${run}"); done < <(list_complete_runs)
  total="${#complete[@]}"
  keep=$((total - KEEP_MIN))
  for run in ${complete[@]+"${complete[@]}"}; do
    # The newest KEEP_MIN complete runs are protected regardless of age.
    if [ "${keep}" -le 0 ]; then protected="${protected}${run} "; fi
    keep=$((keep - 1))
  done
  log "retention: ${total} complete run(s), keep ${RETENTION_DAYS} days (older than ${cutoff}), at least ${KEEP_MIN}"
  while IFS= read -r run; do
    [ -n "${run}" ] || continue
    [ "${run}" = "${CURRENT_RUN}" ] && continue
    case "${protected}" in *" ${run} "*) continue ;; esac
    if printf '%s\n' ${complete[@]+"${complete[@]}"} | grep -qx "${run}"; then
      [[ "${run}" < "${cutoff}" ]] || continue
      log "deleting expired run ${run}"
    else
      [[ "${run}" < "${incomplete_cutoff}" ]] || continue
      log "deleting incomplete run ${run}"
    fi
    rclone purge "${REMOTE}/${run}" || log "WARNING: could not delete ${run}"
  done < <(list_runs)
}

show_runs() {
  local complete=" " run
  while IFS= read -r run; do complete="${complete}${run} "; done < <(list_complete_runs)
  while IFS= read -r run; do
    [ -n "${run}" ] || continue
    case "${complete}" in *" ${run} "*) printf '%s complete\n' "${run}" ;; *) printf '%s incomplete\n' "${run}" ;; esac
  done < <(list_runs)
}

main() {
  local cmd="${1:-backup}"
  case "${cmd}" in
    backup)
      validate_settings
      write_client_config
      configure_remote
      detect_threads
      wait_for_mariadb
      check_versions
      run_backup
      prune
      log "done"
      ;;
    list)
      configure_remote
      show_runs
      ;;
    *)
      die "unknown command '${cmd}' (use: backup, list)"
      ;;
  esac
}

main "$@"
