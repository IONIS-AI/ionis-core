#!/bin/bash
# =============================================================================
# populate_solar_silver.sh — all solar parameters onto one 3-hour grid
# =============================================================================
#
# Run after the four bronze loads. Rebuilds from bronze, so it is derived state
# and safe to drop and recreate at any time.
#
# THE GRID IS Kp's. Kp is defined on 3-hour intervals and cannot be interpolated,
# so it is the spine; everything else is aligned onto it. SFI and SSN are daily-ish
# and carried across that day's eight buckets — F10.7 varies on solar-rotation
# timescales, so a daily value on a 3-hour grid is faithful, not a smear.
#
# Usage:
#   bash populate_solar_silver.sh
#   CH_HOST=10.60.1.1 bash populate_solar_silver.sh
# =============================================================================
set -e

# shellcheck source=/dev/null
[ -r /usr/bin/ionis-env ] && . /usr/bin/ionis-env
CH_HOST="${CH_HOST:-localhost}"
Q() { clickhouse-client --host "$CH_HOST" --query "$1"; }

echo "============================================================"
echo "Populating solar.silver  (host: ${CH_HOST})"
echo "============================================================"
for t in kp_bronze sfi_bronze ssn_bronze xray_bronze; do
    printf "  solar.%-12s %s rows\n" "$t" "$(Q "SELECT count() FROM solar.$t")"
done

Q "TRUNCATE TABLE IF EXISTS solar.silver"

# Kp is the spine: one row per 3-hour bucket, so LEFT JOIN from it.
#
# join_use_nulls=1 IS LOad-BEARING, NOT A TUNING FLAG. Without it a ClickHouse LEFT
# JOIN fills unmatched rows with the column DEFAULT — 0 — not NULL. That is exactly
# the defect this rebuild exists to remove: the first run of this script reported
# SFI present on all 276,784 rows when Penticton only starts in 2004, and X-ray
# present on all of them when we hold 57 buckets. Zero-filled, and it looked like
# full coverage.
Q "
SET join_use_nulls = 1;
INSERT INTO solar.silver (observed_at, kp, ap, sfi_observed, sfi_adjusted, ssn, xray_short_max, xray_long_max)
SELECT
    k.observed_at,
    k.kp,
    k.ap,
    f.obs,
    f.adj,
    s.ssn,
    x.short_max,
    x.long_max
FROM solar.kp_bronze k
LEFT JOIN (
    SELECT toDate(observed_at) AS d, avg(observed_flux) AS obs, avg(adjusted_flux) AS adj
    FROM solar.sfi_bronze GROUP BY d
) f ON toDate(k.observed_at) = f.d
LEFT JOIN (
    SELECT observed_on AS d, ssn FROM solar.ssn_bronze
) s ON toDate(k.observed_at) = s.d
LEFT JOIN (
    SELECT observed_at, short_max, long_max FROM solar.xray_bronze
) x ON k.observed_at = x.observed_at
WHERE k.observed_at >= '1932-01-01'
"

ROWS=$(Q "SELECT count() FROM solar.silver")
echo "------------------------------------------------------------"
printf "  solar.silver: %s rows\n" "$ROWS"
Q "
SELECT
    'coverage' AS x,
    toString(min(observed_at)) AS first,
    toString(max(observed_at)) AS last,
    countIf(kp IS NOT NULL) AS with_kp,
    countIf(sfi_observed IS NOT NULL) AS with_sfi,
    countIf(ssn IS NOT NULL) AS with_ssn,
    countIf(xray_long_max IS NOT NULL) AS with_xray
FROM solar.silver FORMAT Vertical" | sed 's/^/  /'

# A rebuild that loses Kp rows means the join dropped something it should not have.
KP_B=$(Q "SELECT count() FROM solar.kp_bronze")
if [ "$ROWS" != "$KP_B" ]; then
    echo "WARNING: silver has $ROWS rows but kp_bronze has $KP_B — the spine lost rows." >&2
    exit 1
fi
echo "  spine intact: silver row count equals kp_bronze"
