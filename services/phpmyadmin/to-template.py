"""Build the phpMyAdmin values in template.json from the readable sources here.

    python3 to-template.py            # print both values
    python3 to-template.py --check    # exit 1 if template.json differs
    python3 to-template.py --write    # update template.json in place

- startCommand: pma-start.sh joined into one line (comments and blank lines
  dropped, lines joined with "; " unless they end in then/do/else), wrapped as
  /bin/bash -c '<script>' pma-start.
- PMA_USER_CONFIG_BASE64: config.user.inc.php, base64-encoded. The image's
  entrypoint decodes it into /etc/phpmyadmin/config.user.inc.php.
"""
import base64
import json
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
SCRIPT = HERE / "pma-start.sh"
CONFIG = HERE / "config.user.inc.php"
TEMPLATE = HERE.parent.parent / "template.json"
SERVICE = "phpMyAdmin"
PREFIX = "/bin/bash -c '"
SUFFIX = "' pma-start"
OPENERS = ("then", "do", "else")


def build_command() -> str:
    lines = []
    for raw in SCRIPT.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "'" in line or "\\" in line:
            raise SystemExit(f"single quote or backslash not allowed: {line}")
        lines.append(line)
    out = ""
    for i, line in enumerate(lines):
        out += line
        if i < len(lines) - 1:
            out += " " if line.split()[-1] in OPENERS else "; "
    return PREFIX + out + SUFFIX


def build_config() -> str:
    return base64.b64encode(CONFIG.read_bytes()).decode("ascii")


def main() -> int:
    command, config = build_command(), build_config()
    if "--check" not in sys.argv and "--write" not in sys.argv:
        print(command)
        print(config)
        return 0
    template = json.loads(TEMPLATE.read_text(encoding="utf-8"))
    service = template["services"][SERVICE]
    if "--write" in sys.argv:
        service["startCommand"] = command
        service["variables"]["PMA_USER_CONFIG_BASE64"]["defaultValue"] = config
        TEMPLATE.write_text(json.dumps(template, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        print(f"template.json {SERVICE} updated (startCommand {len(command)} chars, config {len(config)} chars)")
        return 0
    stale = []
    if service["startCommand"] != command:
        stale.append("startCommand")
    if service["variables"]["PMA_USER_CONFIG_BASE64"]["defaultValue"] != config:
        stale.append("PMA_USER_CONFIG_BASE64")
    if stale:
        print(f"template.json {SERVICE} is out of date ({', '.join(stale)}); run with --write")
        return 1
    print(f"OK: template.json {SERVICE} matches pma-start.sh ({len(command)} chars) and config.user.inc.php")
    return 0


if __name__ == "__main__":
    sys.exit(main())
