#!/usr/bin/env bash
# verify_schema_complete.sh — every live table has DDL here, and every DDL file lands a table.
#
# THE AUDIT THIS AUTOMATES. On 2026-09-22 the live database held five objects that no
# repository created: wspr.bronze_uniform (a view that silently changes what "all WSPR
# spots" means), wspr.dup_fix, validation.sfi_audit_runs, validation.tst900_results, and
# contest.log_metadata. They were found by hand, by diffing system.tables against a grep
# of src/*.sql. That diff is this script, so the next one is found in seconds and not in
# an afternoon.
#
# It answers two questions, and they fail for opposite reasons:
#
#   ORPHAN  live, created by nothing version-controlled. Survives only because nobody
#           drops it; a rebuild from this repo produces a database without it, and
#           whatever reads it then fails against a schema that calls itself complete.
#   GHOST   DDL here, not live. Either the schema was never applied, or somebody dropped
#           the table and left the file, in which case the next apply brings it back --
#           src/*.sql is globbed by the Makefile AND by ionis-core.spec, so every file in
#           that directory is applied, no exceptions.
#
# Databases owned by other repositories are declared below rather than ignored silently.
# "Not ours" is a claim, and it belongs in the source where it can be argued with.
#
#   usage:  scripts/verify_schema_complete.sh [--host 10.60.1.1]
#   exit:   0 clean · 1 orphans or ghosts found · 2 could not reach ClickHouse
set -euo pipefail

# Site configuration and shared defaults. Sourced rather than redeclared: this line
# used to be CH_HOST="${CH_HOST:-192.168.1.90}" in each of sixteen scripts, so one
# host's address was the shipped default sixteen times over and a site had sixteen
# places to change it. ionis-env reads /etc/ionis-core/ionis-core.conf first, so a
# site sets it once. An explicit CH_HOST in the environment still wins.
# shellcheck source=/dev/null
[ -r /usr/bin/ionis-env ] && . /usr/bin/ionis-env
CH_HOST="${CH_HOST:-localhost}"
[[ "${1:-}" == "--host" ]] && CH_HOST="$2"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/src"

# Schema owned elsewhere. Each entry names the repository that owns it, because an
# unexplained exclusion list is how a real orphan hides in plain sight.
FOREIGN=(
  'akb'       # fiducial-mesh/core/python/akb/schema/ddl/
  'messages'  # ki7mt-ai-lab-devel/shared-context/agent-message-queue.sql
  'system' 'INFORMATION_SCHEMA' 'information_schema' 'default'
)

q() { clickhouse-client --host "$CH_HOST" --query "$1"; }
q "SELECT 1" >/dev/null 2>&1 || { echo "cannot reach ClickHouse at $CH_HOST"; exit 2; }

filter=$(printf "'%s'," "${FOREIGN[@]}"); filter="${filter%,}"
q "SELECT database||'.'||name FROM system.tables WHERE database NOT IN ($filter) ORDER BY 1" \
  | LC_ALL=C sort > /tmp/.schema_live.$$

# Commented-out DDL is not DDL. Strip line comments before matching, or a disabled
# CREATE (01-wspr_schema_v2.sql ships one) reads as a ghost forever.
sed 's/--.*$//' "$SRC"/*.sql \
  | grep -oiP 'CREATE\s+(OR REPLACE\s+)?(MATERIALIZED\s+)?(TABLE|VIEW)\s+(IF NOT EXISTS\s+)?`?[A-Za-z0-9_]+\.[A-Za-z0-9_]+' \
  | awk '{print tolower($NF)}' | tr -d '`' | LC_ALL=C sort -u > /tmp/.schema_ddl.$$

orphans=$(LC_ALL=C comm -23 /tmp/.schema_live.$$ /tmp/.schema_ddl.$$)
ghosts=$(LC_ALL=C comm -13 /tmp/.schema_live.$$ /tmp/.schema_ddl.$$)
rm -f /tmp/.schema_live.$$ /tmp/.schema_ddl.$$

rc=0
if [[ -n "$orphans" ]]; then
  rc=1
  echo "ORPHAN — live on $CH_HOST, created by no DDL in src/:"
  sed 's/^/    /' <<< "$orphans"
  echo "    -> write the DDL (and a docs/DATA-DICTIONARY.md entry), or drop the table."
fi
if [[ -n "$ghosts" ]]; then
  rc=1
  [[ -n "$orphans" ]] && echo
  echo "GHOST — DDL in src/, no such table on $CH_HOST:"
  sed 's/^/    /' <<< "$ghosts"
  echo "    -> apply the schema, or delete the file. Leaving it means the next apply recreates it."
fi
[[ $rc -eq 0 ]] && echo "schema complete: every live table has DDL, every DDL file has a table ($CH_HOST)"
exit $rc
