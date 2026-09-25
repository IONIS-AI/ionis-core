#!/usr/bin/env bash
# verify_sfi_ingest.sh -- does solar.sfi_bronze hold every line of Penticton's file?
#
# 1. LINES: the file's data lines == the table's rows, and the SET of line numbers is
#    identical -- so a lost line cannot be hidden by a duplicated one. The file side is
#    read with awk, not with solar-sfi-ingest's parser. A mismatch fails the audit.
#    (Until #46 the table collapsed 49 real observations that share a rounded
#    fluxtime; a count of distinct times would have "balanced" around that loss.)
#
# 2. COVERAGE: days between the first and last observation with no line in the file,
#    as ranges. Penticton has quiet days; they are reported, never folded into a zero.
#    Reported, not failed.
#
# Usage: CH_HOST=10.60.1.1 SRC=/mnt/solar-data/raw TABLE=solar.sfi_bronze scripts/verify_sfi_ingest.sh
# Exit 0 if section 1 balances, 1 otherwise.

set -uo pipefail
[ -r /usr/bin/ionis-env ] && . /usr/bin/ionis-env
CH_HOST="${CH_HOST:-${IONIS_CH_HOST:-10.60.1.1}}"; CH_HOST="${CH_HOST%%:*}"
SRC="${SRC:-${IONIS_SOLAR_DATA_DIR:-/mnt/solar-data/raw}}"
TABLE="${TABLE:-solar.sfi_bronze}"
FILE="$SRC/penticton_fluxtable.txt"
ch() { clickhouse-client --host "$CH_HOST" -q "$1" 2>/dev/null; }
[ -r "$FILE" ] || { echo "no file at $FILE"; exit 2; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
# Data lines = every non-blank line that is not one of the two header lines.
awk '{t=$0; gsub(/^[ \t]+|[ \t]+$/,"",t)} t!="" && t !~ /^fluxdate/ && t !~ /^---/ {print NR}' "$FILE" > "$tmp/file.lines"
ch "SELECT line_no FROM $TABLE FORMAT TSV" > "$tmp/table.lines"
# comm needs both sides in the SAME text collation; numeric order is not that (10 < 9
# as text). Sort both with sort(1), or comm warns and its missing/extra counts are wrong.
LC_ALL=C sort -o "$tmp/file.lines" "$tmp/file.lines"
LC_ALL=C sort -o "$tmp/table.lines" "$tmp/table.lines"

f=$(wc -l < "$tmp/file.lines"); t=$(wc -l < "$tmp/table.lines")
only_file=$(LC_ALL=C comm -23 "$tmp/file.lines" "$tmp/table.lines" | wc -l)
only_table=$(LC_ALL=C comm -13 "$tmp/file.lines" "$tmp/table.lines" | wc -l)
rc=0
echo "== 1. LINES: $FILE vs $TABLE"
printf '  file data lines %d · table rows %d · lines missing from table %d · rows with no such line %d\n' "$f" "$t" "$only_file" "$only_table"
[ "$f" -ne "$t" ] || [ "$only_file" -ne 0 ] || [ "$only_table" -ne 0 ] && rc=1
unread=$(ch "SELECT countIf(parse_error != '') FROM $TABLE")
echo "  unreadable lines kept (parse_error set): ${unread:-?}"

echo
echo "== 2. COVERAGE: days with no observation line (reported, not failed)"
awk '{t=$0; gsub(/^[ \t]+/,"",t)} t ~ /^[0-9]{8} / {print substr(t,1,8)}' "$FILE" | sort -u > "$tmp/days"
first=$(head -1 "$tmp/days"); last=$(tail -1 "$tmp/days")
span=$(( ( $(date -ud "$last" +%s) - $(date -ud "$first" +%s) ) / 86400 + 1 )); have=$(wc -l < "$tmp/days")
echo "  $first .. $last  span $span days, lines for $have days, no line on $((span - have)) days"
d="$first"; gs=""; prev=""; n=0
while [ "$d" -le "$last" ]; do
  if ! grep -qx "$d" "$tmp/days"; then [ -z "$gs" ] && gs="$d"; prev="$d"
  elif [ -n "$gs" ]; then n=$((n+1)); [ "$n" -le 40 ] && echo "    no line: $gs .. $prev"; gs=""; fi
  d=$(date -ud "$d + 1 day" +%Y%m%d)
done
[ -n "$gs" ] && { n=$((n+1)); echo "    no line: $gs .. $prev"; }
[ "$n" -gt 40 ] && echo "    ... $n gap ranges in total"

echo
[ "$rc" -eq 0 ] && echo "every data line is a row: file == table" || echo "FILE AND TABLE DIFFER (see counts above)"
exit $rc
