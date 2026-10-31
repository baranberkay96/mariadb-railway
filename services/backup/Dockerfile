# MariaDB Backup (Railway cron job): mariadb-dump + zstd from the official
# MariaDB image, rclone from the official rclone image.
#
# The base is the same image and tag as the MariaDB service, so mariadb-dump
# always matches the server version. When the MariaDB service moves to a new
# tag, change it here in the same commit.
FROM rclone/rclone:1.75.2 AS rclone

FROM mariadb:12.3.3

# rclone is a static Go binary (CGO_ENABLED=0 in its Dockerfile).
COPY --from=rclone /usr/local/bin/rclone /usr/local/bin/rclone
COPY --chmod=755 mariadb-bucket-backup.sh /usr/local/bin/mariadb-bucket-backup

# Fail the build early if a tool is missing or the script does not parse.
RUN mariadb-dump --version \
 && mariadb --version \
 && mariadb-admin --version \
 && zstd --version \
 && rclone version \
 && date -u -d @0 +%Y > /dev/null \
 && bash -n /usr/local/bin/mariadb-bucket-backup

# Run as the image's unprivileged mysql user; temporary files go to /tmp.
ENV HOME=/tmp
USER mysql

ENTRYPOINT ["/usr/local/bin/mariadb-bucket-backup"]
CMD ["backup"]
