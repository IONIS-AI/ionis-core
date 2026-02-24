#!/bin/bash
# ==============================================================================
# populate_dxpedition_contest_paths.sh — DXpedition-Contest Path Observations
# ==============================================================================
#
# Cross-references dxpedition.catalog with contest.bronze to find observations
# of DXpedition callsigns during their active operation windows. Each row is
# a one-sided observation (contester logged working the DXpedition callsign)
# enriched with contester grid (from callsign_grid) and solar conditions.
#
# Only rows where the contester grid can be resolved are included — we need
# both ends of the path for IONIS model validation.
#
# Prerequisites:
#   - dxpedition.catalog populated (332 entries)
#   - contest.bronze populated (234M QSOs)
#   - wspr.callsign_grid populated
#   - solar.bronze populated
#   - validation database exists (35-dxpedition_contest_paths.sql)
#
# Expected result: ~100K-110K rows (observations with resolved grids)
#
# Usage:
#   bash populate_dxpedition_contest_paths.sh
#   CH_HOST=10.60.1.1 bash populate_dxpedition_contest_paths.sh
#
# ==============================================================================
set -e

CH_HOST="${CH_HOST:-192.168.1.90}"
MIN_EXPECTED_ROWS=50000

START_TIME=$(date +%s)
SCRIPT_DIR="$(dirname "$0")"

echo "============================================================"
echo "Populating validation.dxpedition_contest_paths"
echo "============================================================"
echo "Host:           ${CH_HOST}"
echo "============================================================"
echo ""

# --------------------------------------------------------------------------
# Create table if not exists
# --------------------------------------------------------------------------
DDL_FILE="35-dxpedition_contest_paths.sql"
if [ -f "$SCRIPT_DIR/../ddl/$DDL_FILE" ]; then
    clickhouse-client --host "$CH_HOST" --multiquery < "$SCRIPT_DIR/../ddl/$DDL_FILE" 2>/dev/null || true
elif [ -f "$SCRIPT_DIR/../src/$DDL_FILE" ]; then
    clickhouse-client --host "$CH_HOST" --multiquery < "$SCRIPT_DIR/../src/$DDL_FILE" 2>/dev/null || true
fi

# --------------------------------------------------------------------------
# Pre-flight: check source tables
# --------------------------------------------------------------------------
echo "Pre-flight checks..."

DXE_COUNT=$(clickhouse-client --host "$CH_HOST" --query \
    "SELECT count() FROM dxpedition.catalog")
echo "  dxpedition.catalog:   ${DXE_COUNT} entries"
[ "$DXE_COUNT" -gt 0 ] || { echo "ERROR: dxpedition.catalog is empty"; exit 1; }

CONTEST_COUNT=$(clickhouse-client --host "$CH_HOST" --query \
    "SELECT count() FROM contest.bronze")
echo "  contest.bronze:       ${CONTEST_COUNT} rows"
[ "$CONTEST_COUNT" -gt 0 ] || { echo "ERROR: contest.bronze is empty"; exit 1; }

GRID_COUNT=$(clickhouse-client --host "$CH_HOST" --query \
    "SELECT count() FROM wspr.callsign_grid")
echo "  wspr.callsign_grid:   ${GRID_COUNT} callsigns"
[ "$GRID_COUNT" -gt 0 ] || { echo "ERROR: wspr.callsign_grid is empty"; exit 1; }

SOLAR_COUNT=$(clickhouse-client --host "$CH_HOST" --query \
    "SELECT count(DISTINCT date) FROM solar.bronze")
echo "  solar.bronze:         ${SOLAR_COUNT} dates"
[ "$SOLAR_COUNT" -gt 0 ] || { echo "ERROR: solar.bronze is empty"; exit 1; }

echo ""

# --------------------------------------------------------------------------
# Truncate for idempotent re-run
# --------------------------------------------------------------------------
echo "Truncating validation.dxpedition_contest_paths..."
clickhouse-client --host "$CH_HOST" --query \
    "TRUNCATE TABLE IF EXISTS validation.dxpedition_contest_paths"
echo ""

# --------------------------------------------------------------------------
# Populate: JOIN contest × dxpedition × callsign_grid × solar
# --------------------------------------------------------------------------
echo "Populating observations (this may take a few minutes)..."
T0=$(date +%s)

clickhouse-client --host "$CH_HOST" --query "
INSERT INTO validation.dxpedition_contest_paths
    (dxe_callsign, dxe_entity, dxe_grid,
     ctr_callsign, ctr_grid,
     band, timestamp, hour_utc, month, day_of_year,
     contest, mode, sfi, kp, distance_km)
SELECT
    d.callsign                          AS dxe_callsign,
    d.entity                            AS dxe_entity,
    CAST(d.grid AS FixedString(4))      AS dxe_grid,

    -- Contester is whichever side is NOT the DXpedition
    if(c.call_1 = d.callsign, c.call_2, c.call_1) AS ctr_callsign,
    CAST(cg.grid_4 AS FixedString(4))              AS ctr_grid,

    c.band                              AS band,
    c.timestamp                         AS timestamp,
    toHour(c.timestamp)                 AS hour_utc,
    toMonth(c.timestamp)                AS month,
    toDayOfYear(c.timestamp)            AS day_of_year,
    c.contest                           AS contest,
    c.mode                              AS mode,

    -- Solar: daily aggregate (one SFI per day, mean Kp across 3-hour buckets)
    s_agg.avg_sfi                       AS sfi,
    s_agg.avg_kp                        AS kp,

    -- Great-circle distance from grid centroids (km)
    greatCircleDistance(
        -- DXpedition grid → lon, lat
        (reinterpretAsUInt8(substring(d.grid, 1, 1)) - 65) * 20
            + CAST(substring(d.grid, 3, 1) AS UInt8) * 2 + 1 - 180,
        (reinterpretAsUInt8(substring(d.grid, 2, 1)) - 65) * 10
            + CAST(substring(d.grid, 4, 1) AS UInt8) + 0.5 - 90,
        -- Contester grid → lon, lat
        (reinterpretAsUInt8(substring(cg.grid_4, 1, 1)) - 65) * 20
            + CAST(substring(cg.grid_4, 3, 1) AS UInt8) * 2 + 1 - 180,
        (reinterpretAsUInt8(substring(cg.grid_4, 2, 1)) - 65) * 10
            + CAST(substring(cg.grid_4, 4, 1) AS UInt8) + 0.5 - 90
    ) / 1000                            AS distance_km

FROM contest.bronze c

-- Match contest QSOs to DXpedition callsigns within operation window
JOIN dxpedition.catalog d
    ON (c.call_2 = d.callsign OR c.call_1 = d.callsign)
    AND c.timestamp BETWEEN d.start_ts AND d.end_ts

-- Resolve contester grid (INNER JOIN = only rows with known grids)
JOIN wspr.callsign_grid cg
    ON cg.callsign = if(c.call_1 = d.callsign, c.call_2, c.call_1)

-- Solar conditions: pre-aggregate to one row per date
JOIN (
    SELECT
        date,
        avg(observed_flux) AS avg_sfi,
        avg(kp_index)      AS avg_kp
    FROM solar.bronze
    GROUP BY date
) s_agg
    ON toDate(c.timestamp) = s_agg.date

-- Filter: both grids must be valid 4-char Maidenhead
WHERE length(d.grid) = 4
    AND length(cg.grid_4) = 4
    AND cg.grid_4 != ''
    -- Skip ground-wave paths (< 500 km not useful for ionospheric validation)
    AND greatCircleDistance(
        (reinterpretAsUInt8(substring(d.grid, 1, 1)) - 65) * 20
            + CAST(substring(d.grid, 3, 1) AS UInt8) * 2 + 1 - 180,
        (reinterpretAsUInt8(substring(d.grid, 2, 1)) - 65) * 10
            + CAST(substring(d.grid, 4, 1) AS UInt8) + 0.5 - 90,
        (reinterpretAsUInt8(substring(cg.grid_4, 1, 1)) - 65) * 20
            + CAST(substring(cg.grid_4, 3, 1) AS UInt8) * 2 + 1 - 180,
        (reinterpretAsUInt8(substring(cg.grid_4, 2, 1)) - 65) * 10
            + CAST(substring(cg.grid_4, 4, 1) AS UInt8) + 0.5 - 90
    ) / 1000 >= 500
"

T1=$(date +%s)
echo "  Done ($((T1 - T0))s)"
echo ""

# --------------------------------------------------------------------------
# SAFEGUARD: Post-population assertion
# --------------------------------------------------------------------------
FINAL_COUNT=$(clickhouse-client --host "$CH_HOST" --query \
    "SELECT count() FROM validation.dxpedition_contest_paths")

if [ "$FINAL_COUNT" -lt "$MIN_EXPECTED_ROWS" ]; then
    echo "============================================================"
    echo "ASSERTION FAILED"
    echo "============================================================"
    echo "validation.dxpedition_contest_paths has ${FINAL_COUNT} rows"
    echo "  (minimum expected: ${MIN_EXPECTED_ROWS})"
    echo "============================================================"
    exit 1
fi

# --------------------------------------------------------------------------
# Summary statistics
# --------------------------------------------------------------------------
UNIQUE_ENTITIES=$(clickhouse-client --host "$CH_HOST" --query \
    "SELECT uniqExact(dxe_entity) FROM validation.dxpedition_contest_paths")
UNIQUE_DXES=$(clickhouse-client --host "$CH_HOST" --query \
    "SELECT uniqExact(dxe_callsign) FROM validation.dxpedition_contest_paths")
UNIQUE_CONTESTERS=$(clickhouse-client --host "$CH_HOST" --query \
    "SELECT uniqExact(ctr_callsign) FROM validation.dxpedition_contest_paths")

BAND_DIST=$(clickhouse-client --host "$CH_HOST" --query "
    SELECT
        multiIf(band=102,'160m', band=103,'80m', band=105,'40m',
                band=107,'20m', band=109,'15m', band=111,'10m', 'other') AS b,
        count() AS n
    FROM validation.dxpedition_contest_paths
    GROUP BY b ORDER BY n DESC
    FORMAT TSV")

AVG_DIST=$(clickhouse-client --host "$CH_HOST" --query \
    "SELECT round(avg(distance_km)) FROM validation.dxpedition_contest_paths")
SFI_RANGE=$(clickhouse-client --host "$CH_HOST" --query \
    "SELECT concat(toString(round(min(sfi))), '-', toString(round(max(sfi)))) FROM validation.dxpedition_contest_paths")

END_TIME=$(date +%s)
WALL=$(( END_TIME - START_TIME ))

echo "============================================================"
echo "Population Complete — DXpedition-Contest Path Observations"
echo "============================================================"
echo "Total observations:   ${FINAL_COUNT}"
echo "DXpeditions matched:  ${UNIQUE_DXES}"
echo "DXCC entities:        ${UNIQUE_ENTITIES}"
echo "Unique contesters:    ${UNIQUE_CONTESTERS}"
echo "Average distance:     ${AVG_DIST} km"
echo "SFI range:            ${SFI_RANGE}"
echo ""
echo "Band distribution:"
echo "${BAND_DIST}" | while IFS=$'\t' read -r band count; do
    printf "  %-6s %s\n" "$band" "$count"
done
echo ""
echo "Wall time:            ${WALL}s"
echo "============================================================"
