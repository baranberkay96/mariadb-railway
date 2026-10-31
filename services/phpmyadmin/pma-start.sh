#!/bin/bash
# Readable source of the phpMyAdmin service's start command. Nothing is built
# from this folder: the service runs the official image (phpmyadmin:5.2.3-apache)
# and template.json carries this script joined into one line:
#
#   /bin/bash -c '<this script>' pma-start
#
# Railway's start command replaces the image ENTRYPOINT, so the script ends by
# exec-ing the image's own /docker-entrypoint.sh apache2-foreground. That
# entrypoint also decodes PMA_USER_CONFIG_BASE64 into
# /etc/phpmyadmin/config.user.inc.php (source: config.user.inc.php here).
# Regenerate both template.json values with `python3 to-template.py --write`.
# Same one-line rules as the MariaDB script: no single quotes, no backslashes,
# comments on their own lines, every line complete or ending in then/do/else.
#
# At every start it:
#   1. keeps exactly one Apache MPM (prefork, needed by mod_php). The image
#      enables mpm_event in one layer and removes it with whiteout files in the
#      next; "AH00534: More than one MPM loaded" has been reported for stock
#      PHP/Apache images on Railway, so the links are checked before Apache starts;
#   2. sizes Apache for a container (PMA_APACHE_WORKERS prefork workers) and
#      hides the Apache and PHP versions;
#   3. turns off PHP display_errors (errors go to the log instead).
set -e
n() { case "$1" in ""|*[!0-9]*) echo $2 ;; *) echo $1 ;; esac; }
E=/etc/apache2/mods-enabled
N=$(ls $E/mpm_*.load 2>/dev/null | wc -l | tr -d " ")
if [ "$N" -ne 1 ] || [ ! -e $E/mpm_prefork.load ]; then
echo "pma-start: $N Apache MPM modules enabled, keeping mpm_prefork only"
rm -f $E/mpm_*.load $E/mpm_*.conf
a2enmod -q mpm_prefork
fi
W=$(n "$PMA_APACHE_WORKERS" 10)
if [ $W -lt 2 ]; then W=2; fi
if [ $W -gt 256 ]; then W=256; fi
A=/etc/apache2/conf-enabled/zz-railway.conf
echo "ServerTokens Prod" > $A
echo "ServerSignature Off" >> $A
echo "<IfModule mpm_prefork_module>" >> $A
echo "StartServers 2" >> $A
echo "MinSpareServers 1" >> $A
echo "MaxSpareServers 4" >> $A
echo "ServerLimit $W" >> $A
echo "MaxRequestWorkers $W" >> $A
echo "MaxConnectionsPerChild 500" >> $A
echo "</IfModule>" >> $A
I="${PHP_INI_DIR:-/usr/local/etc/php}/conf.d/zz-railway.ini"
echo "display_errors = Off" > $I
echo "log_errors = On" >> $I
echo "expose_php = Off" >> $I
echo "pma-start: Apache prefork MaxRequestWorkers $W, PMA_HOST ${PMA_HOST:-unset}:${PMA_PORT:-3306}, root login ${PMA_ALLOW_ROOT:-false}"
exec /docker-entrypoint.sh apache2-foreground
