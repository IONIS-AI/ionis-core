#!/usr/bin/env bash
# verify_sfi_ingest.sh -- does solar.sfi_bronze hold every line of Penticton's file?
#
# 1. LINES: the file's data lines and the table's line_no agree in count, sum and XOR
#    -- so a lost line cannot be hidden by a duplicated one, and an equal-count swap is caught. The file side is
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
