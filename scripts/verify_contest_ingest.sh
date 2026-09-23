#!/usr/bin/env bash
# verify_contest_ingest.sh -- does contest.bronze hold what the archive holds?
#
# WHY THIS EXISTS
#
# "824,862 files, 384 million rows" is a throughput number, not a correctness one. It
# says nothing about whether the rows are the rows the archive contains, and for a
# long time they were not: the parser stopped at the first END-OF-LOG and lost 179
# whole logs, kept everything before the first "/" and lost 1,607,413 compound
# callsigns, required a trailing letter and lost every QSO worked with 7Q1, and
# treated a misplaced END-OF-LOG as a boundary and lost 893 files whole. Every one of
# those ran to completion and reported success.
#
# So the check is an identity, per contest, against the files themselves:
#
#     archive QSO: lines  ==  bronze rows  +  quarantined  +  skipped
#
# Each QSO line has exactly one fate. It parses and lands in bronze; or it parses and
# the date guard holds it in quarantine; or it does not parse and is skipped, counted
# in ingest_log.skipped_rows and sampled in parse_rejects. Nothing else may happen to
# it. A contest that does not balance has lost rows somewhere between the file and
# the table, and the residual says how many.
#
# skipped_rows is used rather than counting parse_rejects because parse_rejects is
# capped at 100 lines per file; the watermark count is not capped and is therefore
# the one that can appear in an identity.
#
# AND THIS IS WHY THE RESIDUAL IS THE ONLY CHECK THAT FINDS EVERYTHING. A file that
# fails ENTIRELY is left unwatermarked for retry, so it writes no ingest_log row at
# all -- it contributes nothing to row_count and nothing to skipped_rows. Its loss is
# invisible in every counter the ingester keeps. Measured on the run of 2026-09-23:
# arrl-dx-cw reported 19,251,563 rows and 0 skipped while the archive held
# 19,336,552, because 159 files had died whole. The counters all agreed with each
# other and all of them were wrong. Only counting the archive catches that.
#
# Usage:
#   scripts/verify_contest_ingest.sh                 # all contests
#   scripts/verify_contest_ingest.sh cq-ww           # one series
#   CH_HOST=10.60.1.1 SRC=/mnt/contest-logs/_v2 scripts/verify_contest_ingest.sh
#
# Exit 0 if every contest balances, 1 otherwise -- so it can gate a release.

set -uo pipefail

CH_HOST="${CH_HOST:-10.60.1.1}"
SRC="${SRC:-/mnt/contest-logs/_v2}"
FILTER="${1:-}"
ch() { clickhouse-client --host "$CH_HOST" -q "$1" 2>/dev/null; }

[ -d "$SRC" ] || { echo "no archive at $SRC"; exit 2; }

printf '%-16s %14s %14s %11s %9s %12s\n' SERIES ARCHIVE BRONZE QUARANTINE SKIPPED RESIDUAL
printf '%s\n' "----------------------------------------------------------------------------------"

rc=0
total_a=0; total_b=0; total_q=0; total_s=0

for dir in "$SRC"/*/; do
  series=$(basename "$dir")
  [ -n "$FILTER" ] && [ "$series" != "$FILTER" ] && continue

  # The archive side: count QSO: lines under this series, one pass.
  archive=$(find "$dir" -type f -print0 2>/dev/null | xargs -0 grep -ch '^QSO:' 2>/dev/null | paste -sd+ | bc)
  archive=${archive:-0}

  # The database side, keyed by the source path rather than the contest label: a
  # series directory and a contest ID are not the same thing (cq-ww holds both
  # CQ-WW-CW and CQ-WW-SSB), and the file path is what the archive count covers.
  bronze=$(ch "SELECT count() FROM contest.bronze WHERE source LIKE '${series}/%'")
  quar=$(ch   "SELECT count() FROM contest.quarantine WHERE file_path LIKE '${series}/%'")
  skip=$(ch   "SELECT sum(skipped_rows) FROM contest.ingest_log WHERE file_path LIKE '${series}/%'")
  bronze=${bronze:-0}; quar=${quar:-0}; skip=${skip:-0}
  [ "$skip" = "\\N" ] && skip=0

  residual=$(( archive - bronze - quar - skip ))
  mark=""
  if [ "$residual" -ne 0 ]; then mark="  <-- LOST"; rc=1; fi

  printf '%-16s %14s %14s %11s %9s %12s%s\n' \
    "$series" "$archive" "$bronze" "$quar" "$skip" "$residual" "$mark"

  total_a=$((total_a+archive)); total_b=$((total_b+bronze))
  total_q=$((total_q+quar));    total_s=$((total_s+skip))
done

printf '%s\n' "----------------------------------------------------------------------------------"
printf '%-16s %14s %14s %11s %9s %12s\n' TOTAL "$total_a" "$total_b" "$total_q" "$total_s" \
  "$(( total_a - total_b - total_q - total_s ))"

if [ "$rc" -eq 0 ]; then
  echo
  echo "every series balances: archive == bronze + quarantine + skipped"
else
  echo
  echo "AT LEAST ONE SERIES DOES NOT BALANCE."
  echo "A positive residual is QSO lines the archive holds and nothing accounts for --"
  echo "not ingested, not quarantined, not even recorded as skipped. Start with"
  echo "contest.v_parse_rejects_by_reason, then the reject log for file-level failures."
fi
exit $rc
