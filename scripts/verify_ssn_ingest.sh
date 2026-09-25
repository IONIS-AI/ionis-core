#!/usr/bin/env bash
# verify_ssn_ingest.sh -- does solar.ssn_bronze hold every line of SIDC's daily file?
#
# 1. LINES: the SET of non-blank line numbers in the file == the SET of line_no in the
#    table, compared both ways. File side read with awk, not solar-ssn-ingest. Fails on
#    a difference.
# 2. COVERAGE: one line per day. Days in the file's span with no line, or with more
#    than one, are listed. Reported, not failed. (Unobserved days are lines with -1 and
#    are rows with NULL ssn -- they are not gaps.)
#
# Usage: CH_HOST=10.60.1.1 SRC=/mnt/solar-data/raw TABLE=solar.ssn_bronze scripts/verify_ssn_ingest.sh
# Exit 0 if section 1 balances, 1 otherwise.
set -uo pipefail
[ -r /usr/bin/ionis-env ] && . /usr/bin/ionis-env
CH_HOST="${CH_HOST:-${IONIS_CH_HOST:-10.60.1.1}}"; CH_HOST="${CH_HOST%%:*}"
SRC="${SRC:-${IONIS_SOLAR_DATA_DIR:-/mnt/solar-data/raw}}"
TABLE="${TABLE:-solar.ssn_bronze}"
FILE="$SRC/sidc_ssn_daily.csv"
ch() { clickhouse-client --host "$CH_HOST" -q "$1" 2>/dev/null; }
[ -r "$FILE" ] || { echo "no file at $FILE"; exit 2; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

awk 'NF {print NR}' "$FILE" > "$tmp/file.lines"
ch "SELECT line_no FROM $TABLE FORMAT TSV" > "$tmp/table.lines"
# comm needs both sides in the SAME text collation; numeric order is not that (10 < 9
# as text). Sort both with sort(1), or comm warns and its missing/extra counts are wrong.
LC_ALL=C sort -o "$tmp/file.lines" "$tmp/file.lines"
LC_ALL=C sort -o "$tmp/table.lines" "$tmp/table.lines"
f=$(wc -l < "$tmp/file.lines"); t=$(wc -l < "$tmp/table.lines")
mf=$(LC_ALL=C comm -23 "$tmp/file.lines" "$tmp/table.lines" | wc -l); mt=$(LC_ALL=C comm -13 "$tmp/file.lines" "$tmp/table.lines" | wc -l)
rc=0
echo "== 1. LINES: $FILE vs $TABLE"
printf '  file lines %d · table rows %d · lines missing from table %d · rows with no such line %d\n' "$f" "$t" "$mf" "$mt"
{ [ "$f" -ne "$t" ] || [ "$mf" -ne 0 ] || [ "$mt" -ne 0 ]; } && rc=1
echo "  unobserved days (-1 -> NULL): $(ch "SELECT countIf(ssn IS NULL AND parse_error = '') FROM $TABLE") · unreadable kept: $(ch "SELECT countIf(parse_error != '') FROM $TABLE")"

echo
echo "== 2. COVERAGE: one line per day (reported, not failed)"
awk -F';' 'NF {gsub(/ /,""); print $1$2$3}' "$FILE" > "$tmp/days"
first=$(head -1 "$tmp/days"); last=$(tail -1 "$tmp/days")
span=$(( ( $(date -ud "$last" +%s) - $(date -ud "$first" +%s) ) / 86400 + 1 ))
have=$(sort -u "$tmp/days" | wc -l); dup=$(sort "$tmp/days" | uniq -d | wc -l)
echo "  $first .. $last  span $span days, lines for $have distinct days, no line on $((span - have)) days, days with >1 line: $dup"
echo
[ "$rc" -eq 0 ] && echo "every line is a row: file == table" || echo "FILE AND TABLE DIFFER"
exit $rc
