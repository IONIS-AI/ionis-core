#!/usr/bin/env bash
# verify_kp_ingest.sh -- does solar.kp_bronze hold every data line of GFZ's Kp file?
#
# 1. LINES: the file's data-line numbers and the table's line_no agree in count,
#    sum and XOR, so a lost line cannot hide behind an extra one and an equal-count
#    swap is caught. File
#    side read with awk (non-blank, not '#'), not with solar-kp-ingest. Fails on a
#    difference.
# 2. COVERAGE: Kp is eight 3-hour intervals a day. Days in the file's span with any
#    other count of lines are listed. Reported, not failed.
#
# Usage: CH_HOST=10.60.1.1 SRC=/mnt/solar-data/raw TABLE=solar.kp_bronze scripts/verify_kp_ingest.sh
# Exit 0 if section 1 balances, 1 otherwise.
set -uo pipefail
[ -r /usr/bin/ionis-env ] && . /usr/bin/ionis-env
CH_HOST="${CH_HOST:-${IONIS_CH_HOST:-10.60.1.1}}"; CH_HOST="${CH_HOST%%:*}"
SRC="${SRC:-${IONIS_SOLAR_DATA_DIR:-/mnt/solar-data/raw}}"
TABLE="${TABLE:-solar.kp_bronze}"
FILE="$SRC/gfz_kp_ap_since_1932.txt"
ch() { clickhouse-client --host "$CH_HOST" -q "$1" 2>/dev/null; }
[ -r "$FILE" ] || { echo "no file at $FILE"; exit 2; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

awk '{t=$0; gsub(/^[ \t]+/,"",t)} t!="" && t !~ /^#/ {print NR}' "$FILE" > "$tmp/file.lines"
ch "SELECT count(), sum(line_no), groupBitXor(line_no) FROM $TABLE FORMAT TSV" > "$tmp/table.agg"
# BALANCE BY COUNT, SUM AND XOR of the line numbers, file side vs table side. A lost line
# cannot hide behind an extra one, and an equal-count swap changes the sum and the XOR.
# Replaces a comm(1) set-diff, which needed both sides in the same text collation and got
# it wrong once (numeric order fed to comm, 2026-09-25); this has no sort order at all.
# Every value stays exact in awk's doubles (the largest file, Kp, sums to ~4e10).
read -r fc fs fx < <(gawk '{ c++; s += $1; x = xor(x, $1) } END { printf "%d %d %d\n", c, s, x }' "$tmp/file.lines")
read -r tc ts tx < "$tmp/table.agg"
rc=0
echo "== 1. LINES: $FILE vs $TABLE"
printf '  file data lines %d · table rows %d · line-number sum %d / %d · xor %d / %d (file / table)\n' "$fc" "$tc" "$fs" "$ts" "$fx" "$tx"
{ [ "$fc" != "$tc" ] || [ "$fs" != "$ts" ] || [ "$fx" != "$tx" ]; } && rc=1
echo "  no Kp value (-1 -> NULL): $(ch "SELECT countIf(kp IS NULL AND parse_error = '') FROM $TABLE") · unreadable kept: $(ch "SELECT countIf(parse_error != '') FROM $TABLE")"

echo
echo "== 2. COVERAGE: days whose line count is not 8 (reported, not failed)"
awk '!/^#/ && NF {print $1$2$3}' "$FILE" | sort | uniq -c | awk '$1 != 8 {printf "    %s: %d lines\n", $2, $1}' > "$tmp/odd"
first=$(awk '!/^#/ && NF {print $1$2$3; exit}' "$FILE"); last=$(awk '!/^#/ && NF {d=$1$2$3} END{print d}' "$FILE")
span=$(( ( $(date -ud "$last" +%s) - $(date -ud "$first" +%s) ) / 86400 + 1 ))
have=$(awk '!/^#/ && NF {print $1$2$3}' "$FILE" | sort -u | wc -l)
echo "  $first .. $last  span $span days, lines on $have days, no line on $((span - have)) days, days not holding 8 lines: $(wc -l < "$tmp/odd")"
head -20 "$tmp/odd"
echo
[ "$rc" -eq 0 ] && echo "every data line is a row: file == table" || echo "FILE AND TABLE DIFFER"
exit $rc
