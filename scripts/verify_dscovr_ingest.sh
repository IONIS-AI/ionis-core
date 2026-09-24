#!/usr/bin/env bash
# verify_dscovr_ingest.sh -- do the DSCOVR archive bronze tables hold what the mirror holds?
#
# The identity, per product and per year:
#
#     records in the archive files  ==  rows in solar.dscovr_<product>_bronze
#
# Bronze takes every record of every file (DATA-DICTIONARY §0), so there is nothing to
# add back: no skip, no quarantine. A residual is records lost between file and table.
#
# THE ARCHIVE SIDE IS COUNTED WITHOUT THE INGESTER'S CODE. A netCDF classic file stores
# its record count as a big-endian uint32 at bytes 4-7 of the header, so this reads it
# straight from each file with od. An audit that reused the ingester's own reader would
# agree with the ingester by construction.
#
# Usage:
#   scripts/verify_dscovr_ingest.sh
#   CH_HOST=10.60.1.1 SRC=/mnt/solar-data/raw/dscovr scripts/verify_dscovr_ingest.sh
#
# Exit 0 if every product and year balances, 1 otherwise -- so it can gate a release.

set -uo pipefail

[ -r /usr/bin/ionis-env ] && . /usr/bin/ionis-env
CH_HOST="${CH_HOST:-${IONIS_CH_HOST:-10.60.1.1}}"
CH_HOST="${CH_HOST%%:*}"
SRC="${SRC:-${IONIS_SOLAR_DATA_DIR:-/mnt/solar-data/raw}/dscovr}"
ch() { clickhouse-client --host "$CH_HOST" -q "$1" 2>/dev/null; }

[ -d "$SRC" ] || { echo "no archive mirror at $SRC"; exit 2; }

rc=0
printf '%-6s %-6s %8s %12s %12s %10s\n' PRODUCT YEAR FILES ARCHIVE BRONZE RESIDUAL
printf '%s\n' "------------------------------------------------------------"
for prod in f1m m1m; do
  [ -d "$SRC/$prod" ] || { echo "$prod: no mirror directory"; rc=1; continue; }
  for ydir in "$SRC/$prod"/*/; do
    year=$(basename "$ydir")
    files=0; archive=0
    while IFS= read -r -d '' f; do
      n=$(gzip -dc "$f" 2>/dev/null | head -c 8 | tail -c 4 | od -An -tu4 --endian=big | tr -d ' ')
      if [ -z "$n" ]; then echo "  unreadable: $f"; rc=1; continue; fi
      files=$((files+1)); archive=$((archive+n))
    done < <(find "$ydir" -type f -name '*.nc.gz' -print0)
    bronze=$(ch "SELECT count() FROM solar.dscovr_${prod}_bronze WHERE file_path LIKE 'dscovr/${prod}/${year}/%'")
    bronze=${bronze:-0}
    residual=$((archive - bronze))
    mark=""; [ "$residual" -ne 0 ] && { mark="  <-- MISMATCH"; rc=1; }
    printf '%-6s %-6s %8s %12s %12s %10s%s\n' "$prod" "$year" "$files" "$archive" "$bronze" "$residual" "$mark"
  done
done
echo
if [ "$rc" -eq 0 ]; then
  echo "every product and year balances: archive records == bronze rows"
else
  echo "AT LEAST ONE PRODUCT/YEAR DOES NOT BALANCE (positive = records not in bronze; negative = loaded twice)"
fi
exit $rc
