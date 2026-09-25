#!/usr/bin/env bash
# verify_goes_xrs_ingest.sh -- does solar.goes_xrs_1m_bronze hold what the mirror holds?
#
# TWO SECTIONS.
#
# 1. RECORDS, per satellite and year:   records in the mirror files == rows in bronze
#    Bronze takes every record of every file (DATA-DICTIONARY §0): nothing to add back.
#    The archive side is read with Unidata's `ncdump -h` (the record count of each file's
#    UNLIMITED time dimension), not with goes-xrs-ingest's parser, so the ingester is not
#    checked by its own code. A residual fails the audit.
#
# 2. COVERAGE, per satellite: every day inside the satellite's span with no file in the
#    mirror. Section 1 balances perfectly around a gap -- a missing file has no records to
#    miss -- so gaps are listed here, always, and never folded into a zero. Known: NOAA
#    publishes nothing for GOES-17 2018-08-06..09-13 and 2019-08-28..12-17. Coverage
#    gaps are reported, not failed; section 1 is the gate.
#
# Usage:
#   scripts/verify_goes_xrs_ingest.sh
#   CH_HOST=10.60.1.1 SRC=/mnt/solar-data/raw/goes-xrs TABLE=solar.goes_xrs_1m_bronze scripts/verify_goes_xrs_ingest.sh
#
# Exit 0 if every satellite and year balances, 1 otherwise.

set -uo pipefail

[ -r /usr/bin/ionis-env ] && . /usr/bin/ionis-env
CH_HOST="${CH_HOST:-${IONIS_CH_HOST:-10.60.1.1}}"
CH_HOST="${CH_HOST%%:*}"
SRC="${SRC:-${IONIS_SOLAR_DATA_DIR:-/mnt/solar-data/raw}/goes-xrs}"
TABLE="${TABLE:-solar.goes_xrs_1m_bronze}"
ch() { clickhouse-client --host "$CH_HOST" -q "$1" 2>/dev/null; }

command -v ncdump >/dev/null || { echo "ncdump not found: install the netcdf package (EPEL)"; exit 2; }
[ -d "$SRC" ] || { echo "no mirror at $SRC"; exit 2; }

rc=0
echo "== 1. RECORDS: mirror files vs $TABLE"
printf '%-8s %-6s %7s %12s %12s %10s\n' SAT YEAR FILES ARCHIVE BRONZE RESIDUAL
printf '%s\n' "-------------------------------------------------------------"
for sdir in "$SRC"/*/; do
  sat=$(basename "$sdir")
  for ydir in "$sdir"*/; do
    year=$(basename "$ydir")
    files=0; archive=0
    while IFS= read -r -d '' f; do
      n=$(ncdump -h "$f" 2>/dev/null | sed -n 's/.*time = UNLIMITED ; \/\/ (\([0-9]*\) currently).*/\1/p')
      if [ -z "$n" ]; then echo "  unreadable: $f"; rc=1; continue; fi
      files=$((files+1)); archive=$((archive+n))
    done < <(find "$ydir" -type f -name '*.nc' -print0)
    bronze=$(ch "SELECT count() FROM $TABLE WHERE file_path LIKE 'goes-xrs/${sat}/${year}/%'")
    bronze=${bronze:-0}
    residual=$((archive - bronze)); mark=""
    [ "$residual" -ne 0 ] && { mark="  <-- MISMATCH"; rc=1; }
    printf '%-8s %-6s %7s %12s %12s %10s%s\n' "$sat" "$year" "$files" "$archive" "$bronze" "$residual" "$mark"
  done
done

echo
echo "== 2. COVERAGE: days inside each satellite's span with no file (reported, not failed)"
for sdir in "$SRC"/*/; do
  sat=$(basename "$sdir")
  find "$sdir" -type f -name '*.nc' -printf '%f\n' | sed -n 's/.*_d\([0-9]\{8\}\)_.*/\1/p' | sort -u > /tmp/.xrs_days.$$
  first=$(head -1 /tmp/.xrs_days.$$); last=$(tail -1 /tmp/.xrs_days.$$)
  [ -z "$first" ] && continue
  span=$(( ( $(date -ud "$last" +%s) - $(date -ud "$first" +%s) ) / 86400 + 1 ))
  have=$(wc -l < /tmp/.xrs_days.$$)
  echo "$sat: $first .. $last  span $span days, files for $have days, missing $((span - have))"
  if [ "$have" -lt "$span" ]; then
    d="$first"; gap_start=""; prev=""
    while [ "$d" -le "$last" ]; do
      if ! grep -qx "$d" /tmp/.xrs_days.$$; then
        [ -z "$gap_start" ] && gap_start="$d"; prev="$d"
      elif [ -n "$gap_start" ]; then
        echo "    no file: $gap_start .. $prev"; gap_start=""
      fi
      d=$(date -ud "$d + 1 day" +%Y%m%d)
    done
    [ -n "$gap_start" ] && echo "    no file: $gap_start .. $prev"
  fi
  rm -f /tmp/.xrs_days.$$
done

echo
if [ "$rc" -eq 0 ]; then
  echo "every satellite and year balances: mirror records == bronze rows"
else
  echo "AT LEAST ONE SATELLITE/YEAR DOES NOT BALANCE (positive = records not in bronze; negative = loaded twice)"
fi
exit $rc
