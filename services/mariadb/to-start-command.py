"""Print the MariaDB start command built from mariadb-tune.sh.

    python3 to-start-command.py            # print the start command
    python3 to-start-command.py --check    # exit 1 if template.json differs
    python3 to-start-command.py --write    # update template.json in place

The script is joined into one line (comments and blank lines dropped, lines
joined with "; " unless they end in then/do/else) and wrapped so that it runs
before the image's own entrypoint: bash -c '<script>' -> docker-entrypoint.sh mariadbd.
"""
import json
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
SCRIPT = HERE / "mariadb-tune.sh"
TEMPLATE = HERE.parent.parent / "template.json"
SERVICE = "MariaDB"
PREFIX = "/bin/bash -c '"
SUFFIX = "' mariadb-start mariadbd"
OPENERS = ("then", "do", "else")


def build() -> str:
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


def main() -> int:
    command = build()
    if "--check" in sys.argv or "--write" in sys.argv:
        template = json.loads(TEMPLATE.read_text(encoding="utf-8"))
        current = template["services"][SERVICE]["startCommand"]
        if "--write" in sys.argv:
            template["services"][SERVICE]["startCommand"] = command
            TEMPLATE.write_text(json.dumps(template, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
            print(f"template.json {SERVICE}.startCommand updated ({len(command)} chars)")
            return 0
        if current != command:
            print(f"template.json {SERVICE}.startCommand is out of date; run with --write")
            return 1
        print(f"OK: template.json {SERVICE}.startCommand matches mariadb-tune.sh ({len(command)} chars)")
        return 0
    print(command)
    return 0


if __name__ == "__main__":
    sys.exit(main())
