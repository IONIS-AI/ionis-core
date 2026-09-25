#!/usr/bin/env bash
# verify_kp_ingest.sh -- does solar.kp_bronze hold every data line of GFZ's Kp file?
#
# 1. LINES: the SET of data-line numbers in the file == the SET of line_no in the
#    table, compared both ways, so a lost line cannot hide behind an extra one. File
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
ch "SELECT line_no FROM $TABLE FORMAT TSV" > "$tmp/table.lines"
# comm needs both sides in the SAME text collation; numeric order is not that (10 < 9
# as text). Sort both with sort(1), or comm warns and its missing/extra counts are wrong.
LC_ALL=C sort -o "$tmp/file.lines" "$tmp/file.lines"
LC_ALL=C sort -o "$tmp/table.lines" "$tmp/table.lines"
f=$(wc -l < "$tmp/file.lines"); t=$(wc -l < "$tmp/table.lines")
mf=$(LC_ALL=C comm -23 "$tmp/file.lines" "$tmp/table.lines" | wc -l); mt=$(LC_ALL=C comm -13 "$tmp/file.lines" "$tmp/table.lines" | wc -l)
rc=0
echo "== 1. LINES: $FILE vs $TABLE"
printf '  file data lines %d · table rows %d · lines missing from table %d · rows with no such line %d\n' "$f" "$t" "$mf" "$mt"
{ [ "$f" -ne "$t" ] || [ "$mf" -ne 0 ] || [ "$mt" -ne 0 ]; } && rc=1
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
