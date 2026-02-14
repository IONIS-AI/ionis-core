#!/bin/bash
# ==============================================================================
# populate_dxpedition_paths.sh — RBN × DXpedition Cross-Reference + Signatures
# ==============================================================================
#
# Two-stage population script for rare DXCC propagation paths:
#
# Stage 1 — rbn.dxpedition_paths (~2.52M rows):
#   Cross-references GDXF DXpedition catalog callsigns with RBN skimmer spots
#   during active operation windows. Multi-callsign entries (e.g. "3D22, 3D2V")
#   are split via arrayJoin. Skimmer grids come from wspr.callsign_grid.
#   These are one-way observations, NOT confirmed QSOs.
#
# Stage 2 — rbn.dxpedition_signatures (~91K rows):
#   Aggregates dxpedition_paths into signatures matching wspr.signatures_v1
#   schema for UNION in training. Per-band loop with solar JOIN, distance and
#   azimuth from 4-char grid centroids. SNR filtered -20 to 80 dB.
#   Used in V13+ training: 91K × 50x upsample = 4.55M effective examples.
#
# Prerequisites:
#   - dxpedition.catalog populated (>= 300 rows)
#   - rbn.bronze populated (2.18B spots)
#   - wspr.callsign_grid populated (>= 3M rows)
#   - solar.bronze populated (2000-2026)
#   - DDLs: 19-dxpedition_synthesis.sql, 29-rbn_dxpedition_signatures.sql
#
# Expected result: ~2.52M paths, ~91K signatures
#
# Usage:
#   bash populate_dxpedition_paths.sh
#   CH_HOST=10.60.1.1 bash populate_dxpedition_paths.sh
#
# ==============================================================================
set -e

CH_HOST="${CH_HOST:-192.168.1.90}"

START_TIME=$(date +%s)
SCRIPT_DIR="$(dirname "$0")"

# --------------------------------------------------------------------------
# Pre-flight checks
# --------------------------------------------------------------------------
CAT_COUNT=$(clickhouse-client --host "$CH_HOST" --query \
    "SELECT count() FROM dxpedition.catalog")
if [ "$CAT_COUNT" -lt 300 ]; then
    echo "ERROR: dxpedition.catalog has only ${CAT_COUNT} rows (expected >= 300)"
    echo "Run populate_dxpedition_catalog.sh first."
    exit 1
fi

CG_COUNT=$(clickhouse-client --host "$CH_HOST" --query \
    "SELECT count() FROM wspr.callsign_grid")
if [ "$CG_COUNT" -lt 3000000 ]; then
    echo "ERROR: wspr.callsign_grid has only ${CG_COUNT} rows (expected >= 3M)"
    exit 1
fi

SOLAR_MIN=$(clickhouse-client --host "$CH_HOST" --query \
    "SELECT min(date) FROM solar.bronze WHERE observed_flux > 0")
if [ "$SOLAR_MIN" \> "2010-01-01" ]; then
    echo "WARNING: Solar data starts at ${SOLAR_MIN} — DXpeditions go back to 2009"
    echo "Run solar-backfill -start 2000-01-01 first for full coverage."
fi

RBN_COUNT=$(clickhouse-client --host "$CH_HOST" --query \
    "SELECT count() FROM rbn.bronze")

echo "============================================================"
echo "Populating rbn.dxpedition_paths + rbn.dxpedition_signatures"
echo "============================================================"
echo "Host:           ${CH_HOST}"
echo "Catalog:        ${CAT_COUNT} entries"
echo "Callsign grid:  ${CG_COUNT} entries"
echo "Solar from:     ${SOLAR_MIN}"
echo "RBN spots:      ${RBN_COUNT}"
echo "============================================================"
echo ""

# --------------------------------------------------------------------------
# Create tables if not exists (ddl/ = RPM, src/ = git repo)
# --------------------------------------------------------------------------
for DDL_FILE in 19-dxpedition_synthesis.sql 29-rbn_dxpedition_signatures.sql; do
    if [ -f "$SCRIPT_DIR/../ddl/$DDL_FILE" ]; then
        clickhouse-client --host "$CH_HOST" --multiquery < "$SCRIPT_DIR/../ddl/$DDL_FILE" 2>/dev/null || true
    elif [ -f "$SCRIPT_DIR/../src/$DDL_FILE" ]; then
        clickhouse-client --host "$CH_HOST" --multiquery < "$SCRIPT_DIR/../src/$DDL_FILE" 2>/dev/null || true
    fi
done

# ==========================================================================
# STAGE 1: rbn.dxpedition_paths
# ==========================================================================
echo "============================================================"
echo "Stage 1: rbn.dxpedition_paths"
echo "============================================================"
echo ""

# Truncate for idempotent re-run
echo "Truncating rbn.dxpedition_paths..."
clickhouse-client --host "$CH_HOST" --query \
    "TRUNCATE TABLE IF EXISTS rbn.dxpedition_paths"
echo ""

echo "Cross-referencing RBN × DXpedition catalog..."
T0=$(date +%s)

clickhouse-client --host "$CH_HOST" --query "
    INSERT INTO rbn.dxpedition_paths
    SELECT
        r.timestamp,
        dx.call                               AS dx_call,
        dx.entity                             AS dx_entity,
        dx.grid                               AS dx_grid,
        r.de_call                             AS skimmer_call,
        cg.grid_4                             AS skimmer_grid,
        r.band,
        r.frequency,
        r.snr,
        r.tx_mode,
        'rbn-dxpedition-synthesis'            AS source_type
    FROM (
        SELECT
            arrayJoin(splitByString(', ', callsign)) AS call,
            entity,
            grid,
            start_ts,
            end_ts
        FROM dxpedition.catalog
    ) dx
    INNER JOIN rbn.bronze r
        ON r.dx_call = dx.call
        AND r.timestamp >= dx.start_ts
        AND r.timestamp < dx.end_ts
    INNER JOIN wspr.callsign_grid cg
        ON r.de_call = cg.callsign
    WHERE cg.grid_4 != ''
    SETTINGS
        max_threads = 64,
        max_memory_usage = 80000000000,
        max_bytes_before_external_group_by = 20000000000,
        max_partitions_per_insert_block = 300,
        join_use_nulls = 0
"

T1=$(date +%s)
PATHS_COUNT=$(clickhouse-client --host "$CH_HOST" --query \
    "SELECT count() FROM rbn.dxpedition_paths")
echo "  Done ($((T1 - T0))s): ${PATHS_COUNT} paths"
echo ""

# Stage 1 assertion
if [ "$PATHS_COUNT" -lt 2000000 ]; then
    echo "============================================================"
    echo "ASSERTION FAILED — Stage 1"
    echo "============================================================"
    echo "rbn.dxpedition_paths has ${PATHS_COUNT} rows (minimum: 2,000,000)"
    echo ""
    echo "Check that dxpedition.catalog time windows overlap with"
    echo "rbn.bronze data range, and wspr.callsign_grid is populated."
    echo "============================================================"
    exit 1
fi

UNIQUE_DX=$(clickhouse-client --host "$CH_HOST" --query \
    "SELECT uniq(dx_call) FROM rbn.dxpedition_paths")
UNIQUE_ENT=$(clickhouse-client --host "$CH_HOST" --query \
    "SELECT uniq(dx_entity) FROM rbn.dxpedition_paths")
echo "Unique DX calls:    ${UNIQUE_DX}"
echo "Unique entities:    ${UNIQUE_ENT}"
echo ""

# ==========================================================================
# STAGE 2: rbn.dxpedition_signatures
# ==========================================================================
echo "============================================================"
echo "Stage 2: rbn.dxpedition_signatures"
echo "============================================================"
echo ""

# Truncate for idempotent re-run
echo "Truncating rbn.dxpedition_signatures..."
clickhouse-client --host "$CH_HOST" --query \
    "TRUNCATE TABLE IF EXISTS rbn.dxpedition_signatures"
echo ""

# --------------------------------------------------------------------------
# Population: per-band sequential (matches rbn.signatures pattern)
# --------------------------------------------------------------------------
TOTAL=0

for band in 102 103 104 105 106 107 108 109 110 111; do
    case $band in
        102) bname="160m" ;; 103) bname="80m"  ;; 104) bname="60m"  ;;
        105) bname="40m"  ;; 106) bname="30m"  ;; 107) bname="20m"  ;;
        108) bname="17m"  ;; 109) bname="15m"  ;; 110) bname="12m"  ;;
        111) bname="10m"  ;;
    esac

    band_idx=$(( band - 101 ))
    printf "[%2d/10] Band %d (%s) ... " "$band_idx" "$band" "$bname"

    T0=$(date +%s%N)

    clickhouse-client --host "$CH_HOST" --query "
        INSERT INTO rbn.dxpedition_signatures
        SELECT
            substring(p.dx_grid, 1, 4)              AS tx_grid_4,
            substring(p.skimmer_grid, 1, 4)         AS rx_grid_4,
            p.band,
            toHour(p.timestamp)                     AS hour,
            toMonth(p.timestamp)                    AS month,

            -- REAL machine-measured SNR
            medianExact(p.snr)                      AS median_snr,

            count()                                 AS spot_count,
            stddevPop(p.snr)                        AS snr_std,
            1.0                                     AS reliability,

            -- Solar conditions (3-hour bucket join)
            avg(sol.observed_flux)                  AS avg_sfi,
            avg(sol.kp_index)                       AS avg_kp,

            -- Distance from 4-char grid centroids (km)
            toUInt32(avg(
                greatCircleDistance(
                    -- TX lon, lat (DXpedition entity-level grid)
                    (reinterpretAsUInt8(upper(substring(toString(substring(p.dx_grid, 1, 4)), 1, 1))) - 65) * 20
                        + (reinterpretAsUInt8(substring(toString(substring(p.dx_grid, 1, 4)), 3, 1)) - 48) * 2 - 180 + 1.0,
                    (reinterpretAsUInt8(upper(substring(toString(substring(p.dx_grid, 1, 4)), 2, 1))) - 65) * 10
                        + (reinterpretAsUInt8(substring(toString(substring(p.dx_grid, 1, 4)), 4, 1)) - 48) - 90 + 0.5,
                    -- RX lon, lat (skimmer from callsign_grid)
                    (reinterpretAsUInt8(upper(substring(toString(substring(p.skimmer_grid, 1, 4)), 1, 1))) - 65) * 20
                        + (reinterpretAsUInt8(substring(toString(substring(p.skimmer_grid, 1, 4)), 3, 1)) - 48) * 2 - 180 + 1.0,
                    (reinterpretAsUInt8(upper(substring(toString(substring(p.skimmer_grid, 1, 4)), 2, 1))) - 65) * 10
                        + (reinterpretAsUInt8(substring(toString(substring(p.skimmer_grid, 1, 4)), 4, 1)) - 48) - 90 + 0.5
                ) / 1000
            ))                                      AS avg_distance,

            -- Azimuth from TX to RX (degrees)
            toUInt16(avg(
                (degrees(atan2(
                    sin(radians(
                        ((reinterpretAsUInt8(upper(substring(toString(substring(p.skimmer_grid, 1, 4)), 1, 1))) - 65) * 20
                            + (reinterpretAsUInt8(substring(toString(substring(p.skimmer_grid, 1, 4)), 3, 1)) - 48) * 2 - 180 + 1.0)
                        - ((reinterpretAsUInt8(upper(substring(toString(substring(p.dx_grid, 1, 4)), 1, 1))) - 65) * 20
                            + (reinterpretAsUInt8(substring(toString(substring(p.dx_grid, 1, 4)), 3, 1)) - 48) * 2 - 180 + 1.0)
                    )) * cos(radians(
                        (reinterpretAsUInt8(upper(substring(toString(substring(p.skimmer_grid, 1, 4)), 2, 1))) - 65) * 10
                            + (reinterpretAsUInt8(substring(toString(substring(p.skimmer_grid, 1, 4)), 4, 1)) - 48) - 90 + 0.5
                    )),
                    cos(radians(
                        (reinterpretAsUInt8(upper(substring(toString(substring(p.dx_grid, 1, 4)), 2, 1))) - 65) * 10
                            + (reinterpretAsUInt8(substring(toString(substring(p.dx_grid, 1, 4)), 4, 1)) - 48) - 90 + 0.5
                    )) * sin(radians(
                        (reinterpretAsUInt8(upper(substring(toString(substring(p.skimmer_grid, 1, 4)), 2, 1))) - 65) * 10
                            + (reinterpretAsUInt8(substring(toString(substring(p.skimmer_grid, 1, 4)), 4, 1)) - 48) - 90 + 0.5
                    )) - sin(radians(
                        (reinterpretAsUInt8(upper(substring(toString(substring(p.dx_grid, 1, 4)), 2, 1))) - 65) * 10
                            + (reinterpretAsUInt8(substring(toString(substring(p.dx_grid, 1, 4)), 4, 1)) - 48) - 90 + 0.5
                    )) * cos(radians(
                        (reinterpretAsUInt8(upper(substring(toString(substring(p.skimmer_grid, 1, 4)), 2, 1))) - 65) * 10
                            + (reinterpretAsUInt8(substring(toString(substring(p.skimmer_grid, 1, 4)), 4, 1)) - 48) - 90 + 0.5
                    )) * cos(radians(
                        ((reinterpretAsUInt8(upper(substring(toString(substring(p.skimmer_grid, 1, 4)), 1, 1))) - 65) * 20
                            + (reinterpretAsUInt8(substring(toString(substring(p.skimmer_grid, 1, 4)), 3, 1)) - 48) * 2 - 180 + 1.0)
                        - ((reinterpretAsUInt8(upper(substring(toString(substring(p.dx_grid, 1, 4)), 1, 1))) - 65) * 20
                            + (reinterpretAsUInt8(substring(toString(substring(p.dx_grid, 1, 4)), 3, 1)) - 48) * 2 - 180 + 1.0)
                    ))
                )) + 360) % 360
            ))                                      AS avg_azimuth

        FROM rbn.dxpedition_paths p
        LEFT JOIN solar.bronze sol
            ON toDate(p.timestamp) = sol.date
            AND intDiv(toHour(p.timestamp), 3) = intDiv(toHour(sol.time), 3)
        WHERE p.band = ${band}
          AND p.snr BETWEEN -20 AND 80
          AND length(p.dx_grid) >= 4
          AND length(p.skimmer_grid) >= 4
        GROUP BY tx_grid_4, rx_grid_4, p.band, hour, month
        HAVING spot_count >= 5
        SETTINGS
            max_threads = 64,
            max_memory_usage = 80000000000,
            max_bytes_before_external_group_by = 20000000000,
            join_use_nulls = 0
    "

    BAND_ROWS=$(clickhouse-client --host "$CH_HOST" --query "
        SELECT count() FROM rbn.dxpedition_signatures WHERE band = ${band}
    ")

    T1=$(date +%s%N)
    ELAPSED=$(( (T1 - T0) / 1000000 ))
    TOTAL=$(( TOTAL + BAND_ROWS ))
    printf "done (%d.%ds) | %s rows | cumulative: %s\n" \
        "$((ELAPSED/1000))" "$((ELAPSED%1000/100))" \
        "$(printf '%d' "$BAND_ROWS")" "$(printf '%d' $TOTAL)"
done

END_TIME=$(date +%s)
WALL=$(( END_TIME - START_TIME ))

TOTAL_SIGS=$(clickhouse-client --host "$CH_HOST" --query \
    "SELECT count() FROM rbn.dxpedition_signatures")

# Stage 2 assertion
if [ "$TOTAL_SIGS" -lt 80000 ]; then
    echo ""
    echo "============================================================"
    echo "ASSERTION FAILED — Stage 2"
    echo "============================================================"
    echo "rbn.dxpedition_signatures has ${TOTAL_SIGS} rows (minimum: 80,000)"
    echo ""
    echo "Check that rbn.dxpedition_paths has sufficient data and"
    echo "solar.bronze covers the DXpedition time windows."
    echo "============================================================"
    exit 1
fi

echo ""
echo "============================================================"
echo "Population Complete — DXpedition Paths + Signatures"
echo "============================================================"
echo "Paths:            ${PATHS_COUNT}"
echo "Signatures:       ${TOTAL_SIGS}"
echo "Unique DX calls:  ${UNIQUE_DX}"
echo "Unique entities:  ${UNIQUE_ENT}"
echo "Wall time:        ${WALL}s"
echo "============================================================"
echo ""

# SNR distribution check
echo "SNR distribution (p10 / p50 / p90):"
clickhouse-client --host "$CH_HOST" --query "
    SELECT
        round(quantile(0.1)(median_snr), 1) AS p10,
        round(quantile(0.5)(median_snr), 1) AS p50,
        round(quantile(0.9)(median_snr), 1) AS p90
    FROM rbn.dxpedition_signatures
"
echo ""

# Per-band summary
echo "Per-band breakdown:"
clickhouse-client --host "$CH_HOST" --query "
    SELECT
        band,
        count()                             AS signatures,
        round(avg(median_snr), 1)           AS avg_snr,
        round(avg(spot_count), 0)           AS avg_spots,
        round(avg(avg_distance), 0)         AS avg_dist_km
    FROM rbn.dxpedition_signatures
    GROUP BY band
    ORDER BY band
    FORMAT PrettyCompact
"
echo ""

# Solar coverage
SOLAR_PCT=$(clickhouse-client --host "$CH_HOST" --query \
    "SELECT round(countIf(avg_sfi > 0) * 100.0 / count(), 1) FROM rbn.dxpedition_signatures")
echo "Solar coverage:       ${SOLAR_PCT}%"
echo ""

echo "============================================================"
echo "Ready for training: 91K sigs × 50x upsample = 4.55M examples"
echo "covering 152 rare DXCC entities with zero WSPR presence."
echo "============================================================"
