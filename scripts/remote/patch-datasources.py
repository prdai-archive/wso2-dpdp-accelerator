#!/usr/bin/env python3
"""Point the accelerator's deployment.toml datasources at MySQL.

The accelerator ships a deployment.toml whose four datasources are all H2
URLs, and bin/configure.sh only ever rewrote them for the embedded H2 case -
for any other DB_TYPE it prints "apply these by hand" and stops. This does
that edit in place, rather than by templating the shipped file, because
everything above the accelerator banner in that file has to stay byte-identical
to stock WSO2 IS so the diff against a fresh pack stays reviewable.

Line-oriented on purpose: a TOML round-trip would reformat (and silently drop
the comments in) a file whose exact contents we do not own. Only the keys
listed below are touched; every other line is preserved verbatim. Safe to
re-run - it sets values rather than appending them.
"""

import argparse
import json
import re
import shutil
import sys
from datetime import datetime

TABLE_RE = re.compile(r"^\[([^\[].*)\]\s*$")
KEY_RE = re.compile(r"^([A-Za-z0-9_.-]+)\s*=\s*(.*?)\s*$")

# [database.*] takes the decomposed form WSO2 documents for identity/shared DBs
# (type drives the driver lookup), and must not also carry a url - with both
# present it is not documented which one wins.
DECOMPOSED_KEYS = ("type", "hostname", "name", "port", "username", "password")
DECOMPOSED_DROP = ("url",)

# [datasource.*] has no type-driven driver lookup, so it keeps the jdbc url and
# names the driver class explicitly.
URL_KEYS = ("url", "username", "password", "driver")
URL_DROP = ()


def table_span(lines, name):
    """Return (start, end) line indices for table `name`, or (None, None)."""
    start = None
    for index, line in enumerate(lines):
        match = TABLE_RE.match(line)
        if not match:
            continue
        if start is not None:
            return start, index
        if match.group(1).strip() == name:
            start = index
    if start is not None:
        return start, len(lines)
    return None, None


def rewrite_block(body, values, drop):
    out = []
    trailing = []
    seen = set()

    # Keep appended keys inside the block rather than after its trailing blank
    # lines, which would read as belonging to whatever table comes next.
    while body and not body[-1].strip():
        trailing.insert(0, body.pop())

    for line in body:
        match = KEY_RE.match(line)
        if match:
            key = match.group(1)
            if key in drop:
                seen.add(key)
                continue
            if key in values:
                out.append("%s = %s\n" % (key, json.dumps(values[key])))
                seen.add(key)
                continue
        out.append(line)

    for key, value in values.items():
        if key not in seen:
            out.append("%s = %s\n" % (key, json.dumps(value)))

    return out + trailing


def patch(lines, table, values, drop):
    start, end = table_span(lines, table)
    if start is None:
        sys.exit("ERROR: no [%s] table in deployment.toml - did the shipped template change?" % table)
    lines[start + 1:end] = rewrite_block(lines[start + 1:end], values, drop)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--deployment-toml", required=True)
    parser.add_argument("--host", required=True)
    parser.add_argument("--port", default="3306")
    parser.add_argument("--user", required=True)
    parser.add_argument("--password", required=True)
    parser.add_argument("--identity-db", required=True)
    parser.add_argument("--shared-db", required=True)
    parser.add_argument("--agent-db", required=True)
    parser.add_argument("--dpdp-db", required=True)
    args = parser.parse_args()

    path = args.deployment_toml
    with open(path, encoding="utf-8") as handle:
        lines = handle.readlines()

    def decomposed(db):
        return {
            "type": "mysql",
            "hostname": args.host,
            "name": db,
            "port": args.port,
            "username": args.user,
            "password": args.password,
        }

    def url_form(db):
        return {
            "url": "jdbc:mysql://%s:%s/%s?useSSL=false" % (args.host, args.port, db),
            "username": args.user,
            "password": args.password,
            "driver": "com.mysql.cj.jdbc.Driver",
        }

    patch(lines, "database.identity_db", decomposed(args.identity_db), DECOMPOSED_DROP)
    patch(lines, "database.shared_db", decomposed(args.shared_db), DECOMPOSED_DROP)
    patch(lines, "datasource.AgentIdentity", url_form(args.agent_db), URL_DROP)
    patch(lines, "datasource.WSO2DPDP_DB", url_form(args.dpdp_db), URL_DROP)

    backup = "%s.bak-%s" % (path, datetime.now().strftime("%Y%m%d%H%M%S"))
    shutil.copy2(path, backup)

    with open(path, "w", encoding="utf-8") as handle:
        handle.writelines(lines)

    print("patched %s (previous copy: %s)" % (path, backup))
    for table, db in (
        ("database.identity_db", args.identity_db),
        ("database.shared_db", args.shared_db),
        ("datasource.AgentIdentity", args.agent_db),
        ("datasource.WSO2DPDP_DB", args.dpdp_db),
    ):
        print("  %-28s -> mysql://%s:%s/%s" % (table, args.host, args.port, db))


if __name__ == "__main__":
    main()
