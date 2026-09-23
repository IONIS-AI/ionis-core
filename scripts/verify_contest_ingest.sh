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
#     archive QSO: lines  ==  bronze rows
#
# Bronze takes every QSO: line upstream served, good, bad or otherwise (Judge,
# 2026-09-23). A line that parses lands with its columns filled; one that does not
# lands with parse_error set and raw_line holding its content; one dated outside its
# directory's year lands as sent, tagged off-declared-year. There is no quarantine
# and no skip any more, so there is nothing to add back: a contest that does not
# balance has lost lines between the file and the table, and the residual says how
# many. PARSE-FAILED and OFF-YEAR are shown for review; they are part of BRONZE, not
# terms of the identity.
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

printf '%-16s %14s %14s %12s %9s %10s\n' SERIES ARCHIVE BRONZE PARSE-FAILED OFF-YEAR RESIDUAL
printf '%s\n' "----------------------------------------------------------------------------------"

rc=0
total_a=0; total_b=0; total_f=0; total_o=0

for dir in "$SRC"/*/; do
  series=$(basename "$dir")
  [ -n "$FILTER" ] && [ "$series" != "$FILTER" ] && continue

  # The archive side: count QSO: lines under this series, one pass.
  # ^[[:space:]]*QSO: -- NOT ^QSO:. Some logs indent their records ("  QSO:  3532 CW
  # ..."), and a column-anchored pattern silently counts them as zero. The ingester has
  # always handled it, because parseFile does strings.TrimSpace before matching; it was
  # the MEASUREMENTS that were wrong, which is worse -- a reconciliation that undercounts
  # the archive reports a balanced series that is not.
  #
  # Measured 2026-09-23: 239,685 QSO lines across the corpus are indented, 237,226 of
  # them in cq-wpx alone, so the archive total this script compares against was low by
  # that much. cq-wpx/2020cw/lz9w.log is the clearest case -- 10,503 records, every one
  # indented, and the anchored pattern read the file as empty.
  # -i, because the ingester upper-cases the line before matching and therefore
  # accepts "qso:" and "Qso:". A case-sensitive count reads those files as short and
  # the series then reconciles NEGATIVE -- which looks like double-ingestion and is
  # not. cq-ww alone holds 1,284 such lines, and its residual was exactly -1,284.
  #
  # Match the PROGRAM's rule, not a reasonable-looking approximation of it. This is
  # the third time this pattern has been wrong in the same script: first the column
  # anchor, then the whitespace class, now case.
  archive=$(find "$dir" -type f -print0 2>/dev/null | xargs -0 grep -chiE '^[[:space:]]*qso:' 2>/dev/null | paste -sd+ | bc)
  archive=${archive:-0}

  # The database side, keyed by the source path rather than the contest label: a
  # series directory and a contest ID are not the same thing (cq-ww holds both
  # CQ-WW-CW and CQ-WW-SSB), and the file path is what the archive count covers.
  read -r bronze failed offyear < <(ch "SELECT count(), countIf(parse_error != ''),
      countIf(has(patches, 'off-declared-year'))
      FROM contest.bronze WHERE source LIKE '${series}/%' FORMAT TSV")
  bronze=${bronze:-0}; failed=${failed:-0}; offyear=${offyear:-0}

  residual=$(( archive - bronze ))
  mark=""
  if [ "$residual" -ne 0 ]; then mark="  <-- LOST"; rc=1; fi

  printf '%-16s %14s %14s %12s %9s %10s%s\n' \
    "$series" "$archive" "$bronze" "$failed" "$offyear" "$residual" "$mark"

  total_a=$((total_a+archive)); total_b=$((total_b+bronze))
  total_f=$((total_f+failed));  total_o=$((total_o+offyear))
done

printf '%s\n' "----------------------------------------------------------------------------------"
printf '%-16s %14s %14s %12s %9s %10s\n' TOTAL "$total_a" "$total_b" "$total_f" "$total_o" \
  "$(( total_a - total_b ))"

if [ "$rc" -eq 0 ]; then
  echo
  echo "every series balances: archive == bronze"
else
  echo
  echo "AT LEAST ONE SERIES DOES NOT BALANCE."
  echo "A positive residual is QSO lines the archive holds that bronze does not -- a"
  echo "file that failed whole (see the ingester's reject log), or a parser that stops"
  echo "reading early. A negative one is a line ingested twice."
fi
exit $rc
