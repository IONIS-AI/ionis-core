#!/usr/bin/env bash
# verify_dictionary_complete.sh -- is every live table described in the data dictionary?
#
# WHY THIS EXISTS
#
# verify_schema_complete.sh already answers "does every table have DDL". That is a
# weaker question than the one that matters. DDL says a table is allowed to exist; it
# does not say what the table IS, where it came from, or who reads it. A table can be
# perfectly well-formed and still be a mystery.
#
# The standard, set by Judge on 2026-09-23: for any table, the answer should be
#
#     this is what it is, this is how it got here, this is what it is used for
#
# and if it is not defined, it is not meant to be kept.
#
# This is an AUDIT, not a timer. It runs at a moment that matters -- before a tag,
# after an ingest, before a release -- and its exit status is a verdict someone acts
# on, not a notification nobody reads.
#
# IT WAS WRITTEN BECAUSE IT WAS NEEDED. On 2026-09-23 the dictionary was described as
# authoritative and covered 47 of 55 live tables. Six of the eight gaps had been
# created that same day by the agent who wrote the dictionary: four solar bronze
# tables, contest.parse_rejects, and a retained backup. Nothing noticed, because
# nothing asked.
#
# Usage:
#   scripts/verify_dictionary_complete.sh
#   CH_HOST=10.60.1.1 scripts/verify_dictionary_complete.sh
#
# Exit 0 if every live table is described, 1 otherwise.

set -uo pipefail

CH_HOST="${CH_HOST:-localhost}"
DICT="${DICT:-$(dirname "$0")/../docs/DATA-DICTIONARY.md}"
[ -f "$DICT" ] || { echo "no dictionary at $DICT"; exit 2; }

live=$(clickhouse-client --host "$CH_HOST" -q "
  SELECT database || '.' || name FROM system.tables
  WHERE database NOT IN ('system','INFORMATION_SCHEMA','information_schema')
    AND engine NOT LIKE '%View%'
  ORDER BY 1" 2>/dev/null)
[ -n "$live" ] || { echo "could not read system.tables from $CH_HOST"; exit 2; }

missing=""; n=0; covered=0
while read -r t; do
  [ -z "$t" ] && continue
  n=$((n+1))
  db=${t%%.*}
  # A table counts as described if it is named, OR if its database is covered
  # collectively -- `akb.*` points at another project's DDL and that is a legitimate
  # description. Matching only exact names is what produced a false 15-gap report.
  if grep -qF -- "\`$t\`" "$DICT" || grep -qF -- "\`$db.*\`" "$DICT"; then
    covered=$((covered+1))
  else
    missing="$missing $t"
  fi
done <<< "$live"

echo "live tables: $n    described: $covered"
if [ -z "$missing" ]; then
  echo
  echo "every live table is described in $(basename "$DICT")"
  exit 0
fi

echo
echo "NOT DESCRIBED:"
for t in $missing; do echo "    $t"; done
echo
echo "Each one is either defined -- what it is, how it got here, what it is used for --"
echo "or dropped. A table nobody can describe is not meant to be kept."
exit 1
