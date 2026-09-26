#!/usr/bin/env bash
# verify_pskr_capture_ingest.sh -- does pskr.capture_bronze hold every line pskr-capture wrote?
#
# WHAT THIS CAN PROVE, AND WHAT IT CANNOT. PSK Reporter publishes no archive: once a
# message has passed, nothing upstream can be re-read. So:
#
#   1. BALANCE -- proven: every line of every capture file is a row (CAPTURE == BRONZE).
#      Per file, the line count is read with zcat|awk (not the ingester), and the table's
#      count(), sum(line_no) and XOR of line_no must equal those of 1..n -- so a lost line
#      cannot hide behind an extra one, and an equal-count swap is caught. XOR, not a sum
#      of squares: an hour is ~1.3M lines, its sum of squares ~1e18, past what awk's
#      doubles hold exactly; count, sum (~1e12) and XOR all stay exact. Fails on any
#      difference.
#   2. COVERAGE -- measured, reported, not failed: hours with no capture file, crashed
#      hours (.partial), connection events, messages dropped by a full buffer, and the
#      sequence-number (sq) gaps. An sq gap is NOT a measure of our loss: PSK Reporter
#      assigns sq to more than it publishes on MQTT. Measured 2026-09-26 with a second,
#      independent client over the same 90 s: 606 of 43,718 numbers (1.39%) reached
#      neither client, and the capture missed 0 that the other client received. So sq
#      gaps are an UPPER BOUND on capture loss, reported as such.
#   3. COMPLETENESS against the live feed -- NOT provable after the fact, and not claimed.
#
# Files still being written (.partial touched within STALE minutes) are skipped, the
# same rule pskr-capture-ingest uses.
#
# PENDING, NOT FAILED. The capture closes a file every hour and the ingest timer runs
# hourly, so for most of every hour one finished file is waiting for the next run. Before
# this rule the audit failed during that wait, and an audit that usually fails is an audit
# nobody reads. A closed file missing from the table is now PENDING if it closed less than
# PENDING minutes ago (default 70: one timer period plus margin). Older than that it still
# FAILS, so a stuck ingest cannot hide behind the rule.
#
# Usage: CH_HOST=10.60.1.1 SRC=/mnt/pskr-data/capture TABLE=pskr.capture_bronze scripts/verify_pskr_capture_ingest.sh
# Exit 0 if section 1 balances, 1 otherwise.
set -uo pipefail
[ -r /usr/bin/ionis-env ] && . /usr/bin/ionis-env
CH_HOST="${CH_HOST:-${IONIS_CH_HOST:-10.60.1.1}}"; CH_HOST="${CH_HOST%%:*}"
SRC="${SRC:-${IONIS_PSKR_DATA_DIR:-/mnt/pskr-data}/capture}"
TABLE="${TABLE:-pskr.capture_bronze}"
STALE="${STALE:-120}"
PENDING="${PENDING:-70}"
ch() { clickhouse-client --host "$CH_HOST" -q "$1" 2>/dev/null; }
[ -d "$SRC" ] || { echo "no capture root at $SRC"; exit 2; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# Files the ingester would have loaded: completed hours, and .partial untouched for STALE minutes.
{ find "$SRC" -type f -name 'capture-*.jsonl.gz'; find "$SRC" -type f -name 'capture-*.jsonl.gz.partial' -mmin +"$STALE"; } | sort > "$tmp/files"
active=$(find "$SRC" -type f -name 'capture-*.jsonl.gz.partial' -mmin -"$STALE" | wc -l)
# Closed within PENDING minutes: allowed to be absent from the table (see PENDING above).
find "$SRC" -type f -name 'capture-*.jsonl.gz' -mmin -"$PENDING" | sed "s|^$SRC/||" | sort > "$tmp/pending"
while read -r f; do
  n=$(zcat "$f" 2>/dev/null | awk 'END{print NR}')
  printf '%s\t%s\n' "${f#$SRC/}" "$n"
done < "$tmp/files" | sort > "$tmp/file.n"
ch "SELECT file_path, count(), sum(line_no), groupBitXor(line_no) FROM $TABLE GROUP BY file_path FORMAT TSV" | sort > "$tmp/table.agg"

rc=0
echo "== 1. BALANCE: capture files vs $TABLE (proven)"
gawk -F'\t' 'function x1n(k) { r = k % 4; return r == 0 ? k : r == 1 ? 1 : r == 2 ? k + 1 : 0 }
FILENAME==ARGV[1] {pend[$1]=1; next} FILENAME==ARGV[2] {n[$1]=$2; next} {t[$1]=$2" "$3" "$4} END {
  files=0; lines=0; bad=0; pending=0
  for (f in n) { files++; lines+=n[f]; k=n[f]; want=sprintf("%d %d %d", k, k*(k+1)/2, x1n(k))
    if (!(f in t) && (f in pend)) { pending++; print "  PENDING: " f " (" k " lines; closed under '"$PENDING"' min ago, the next hourly ingest loads it)"; continue }
    if (!(f in t)) { bad++; if (bad<=10) print "  NOT IN TABLE: " f " (" k " lines; closed over '"$PENDING"' min ago)"; continue }
    if (t[f] != want) { bad++; if (bad<=10) print "  MISMATCH: " f "  file 1.." k " wants " want "  table count,sum,xor = " t[f] }
  }
  for (f in t) if (!(f in n)) { bad++; if (bad<=10) print "  IN TABLE, NOT ON DISK: " f }
  printf "  files %d · lines %d · pending %d · files that do not balance %d\n", files, lines, pending, bad
  exit (bad > 0)
}' "$tmp/pending" "$tmp/file.n" "$tmp/table.agg" || rc=1
echo "  still being written (skipped): $active"

echo
echo "== 2. COVERAGE: measured loss (reported, not failed)"
echo "  crashed hours (.partial loaded):"
grep -c '\.partial' "$tmp/file.n" | sed 's/^/    count: /'
grep '\.partial' "$tmp/file.n" | sed 's/^/    /' | head -10
echo "  gaps between capture files (next file starts > 65 min after the previous):"
sed -n 's#.*\([0-9]\{4\}\)/\([0-9]\{2\}\)/\([0-9]\{2\}\)/capture-\([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\).*#\1-\2-\3 \4:\5:\6#p' "$tmp/files" | sort | \
  while read -r d t; do date -ud "$d $t" +%s; done | awk 'NR>1 && $1-p > 3900 {g++; printf "    %s -> %s (%d min)\n", strftime("%F %T",p,1), strftime("%F %T",$1,1), ($1-p)/60} {p=$1} END {printf "    gaps: %d\n", g+0}'
echo "  events in the capture:"
ch "SELECT event, count(), min(rx), max(rx), sum(ifNull(event_count, 0)) FROM $TABLE WHERE event != '' GROUP BY event ORDER BY event FORMAT TSV" | awk -F'\t' '{printf "    %-18s %6d   first %s   last %s   dropped-count %s\n", $1, $2, $3, $4, $5}'
echo "  sequence numbers (sq) not received -- an UPPER BOUND on capture loss, not a measure of it:"
echo "    (PSK Reporter numbers more than it publishes; a parallel client on 2026-09-26 missed the same numbers)"
ch "SELECT toDate(rx) d, count() got, uniqExact(sq) distinct_sq, max(sq) - min(sq) + 1 span, span - distinct_sq missing, round(100 * distinct_sq / span, 2) pct FROM $TABLE WHERE sq IS NOT NULL GROUP BY d ORDER BY d FORMAT TSV" | awk -F'\t' '{printf "    %s  received %d  sq span %d  not received %d  (%.2f%% of the span received)\n", $1, $2, $4, $5, $6}'
echo "  unreadable lines kept (parse_error): $(ch "SELECT countIf(parse_error != '') FROM $TABLE")"

echo
echo "== 3. COMPLETENESS against the live feed: NOT PROVABLE after the fact."
echo "  PSK Reporter keeps no archive. Section 1 proves bronze holds every line captured;"
echo "  section 2 measures what is known to be missing. Neither proves nothing else was lost."
echo
[ "$rc" -eq 0 ] && echo "every capture line is a row: capture == bronze (files still pending load are listed above)" || echo "CAPTURE AND BRONZE DIFFER (see section 1)"
exit $rc
