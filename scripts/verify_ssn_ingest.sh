#!/usr/bin/env bash
# verify_ssn_ingest.sh -- does solar.ssn_bronze hold every line of SIDC's daily file?
#
# 1. LINES: the file's non-blank line numbers and the table's line_no agree in count,
#    sum and XOR (an equal-count swap is caught). File side read with awk, not solar-ssn-ingest. Fails on
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
