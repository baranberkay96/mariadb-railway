<?php
/*
 * phpMyAdmin settings added by the Railway template "MariaDB 12.3 LTS with
 * phpMyAdmin and Backups".
 *
 * The official image's /etc/phpmyadmin/config.inc.php configures one server
 * from PMA_HOST / PMA_PORT (cookie login, arbitrary servers only when
 * PMA_ARBITRARY=1) and then includes /etc/phpmyadmin/config.user.inc.php with
 * $i pointing at that server. The image's entrypoint writes this file there
 * from the PMA_USER_CONFIG_BASE64 variable at every start.
 *
 * Edit this file, then run `python3 to-template.py --write` to refresh
 * PMA_USER_CONFIG_BASE64 in template.json.
 */

$railwayEnvTrue = ['1', 'true', 'yes', 'on'];

/* MariaDB's root account cannot log in through the web UI unless PMA_ALLOW_ROOT=true. */
$cfg['Servers'][$i]['AllowRoot'] = in_array(
    strtolower(trim((string) getenv('PMA_ALLOW_ROOT'))),
    $railwayEnvTrue,
    true
);

/* Every login needs a password (the image's config.inc.php allows empty ones). */
$cfg['Servers'][$i]['AllowNoPassword'] = false;

/* Never offer a free-text server field, whatever PMA_ARBITRARY says. */
$cfg['AllowArbitraryServer'] = false;

/* Do not show MariaDB host names or driver errors on the login page. */
$cfg['Servers'][$i]['hide_connection_errors'] = true;

/* Failed logins are written to the service log ("user denied: ..."). */
$cfg['AuthLog'] = 'php';
$cfg['AuthLogSuccess'] = false;

/* No error reports to phpmyadmin.net, no Git revision or phpinfo() in the UI. */
$cfg['SendErrorReports'] = 'never';
$cfg['ShowGitRevision'] = false;
$cfg['ShowPhpInfo'] = false;

unset($railwayEnvTrue);
