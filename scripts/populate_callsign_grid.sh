#!/bin/bash
# ==============================================================================
# populate_callsign_grid.sh — Callsign→Grid Rosetta Stone
# ==============================================================================
#
# Populates wspr.callsign_grid from multiple sources:
#   Step 1: WSPR TX callsigns (callsign → grid) — ~3.5M entries
#   Step 2: WSPR RX reporters (reporter → reporter_grid) — ~50K new entries
#   Step 3: PSKR senders (sender_call → sender_grid) — ~27K new entries
#   Step 4: PSKR receivers (receiver_call → receiver_grid) — ~4K new entries
#   Step 5: OPTIMIZE FINAL (ReplacingMergeTree dedup by most recent last_seen)
#
# The Rosetta Stone is the foundation for:
#   - RBN grid enrichment (525M spots geolocated)
#   - Contest grid enrichment (37M QSOs geolocated)
#   - Balloon/telemetry detection (type2_telemetry flag requires this table)
#   - Coverage analysis (grid counting)
#
# PSKR enrichment: PSK Reporter data provides callsign→grid for FT8/CW/RTTY
# operators who never used WSPR. This adds ~30K callsigns critical for contest
# and RBN signature coverage. Without PSKR, contest signatures drop from ~6M
# to ~340K and RBN signatures from ~57M to ~27M.
#
# SAFEGUARD: Post-population assertion checks row count >= 3,000,000.
# If the table has fewer rows than expected, it likely means wspr.bronze
# was truncated without repopulating this table. This script MUST be re-run
# after any wspr.bronze re-ingest operation.
#
# Prerequisites:
#   - wspr.callsign_grid table exists (07-callsign_grid.sql)
#   - wspr.bronze populated (10.8B rows expected)
#   - pskr.bronze populated (optional, ~100M+ spots for grid enrichment)
#
# Expected result: ~3.6M unique callsign→grid mappings
# Total time on 9975WX: ~3-5 min
#
# Usage:
#   bash populate_callsign_grid.sh
#   CH_HOST=10.60.1.1 bash populate_callsign_grid.sh
#
# ==============================================================================
set -e

CH_HOST="${CH_HOST:-192.168.1.90}"
MIN_EXPECTED_ROWS=3000000

echo "============================================================"
echo "Populating wspr.callsign_grid (Rosetta Stone)"
echo "Host: ${CH_HOST}"
echo "============================================================"
echo ""

# --------------------------------------------------------------------------
# Pre-flight: verify wspr.bronze has data
# --------------------------------------------------------------------------
BRONZE_COUNT=$(clickhouse-client --host "$CH_HOST" --query \
    "SELECT count() FROM wspr.bronze")
if [ "$BRONZE_COUNT" -lt 1000000000 ]; then
    echo "WARNING: wspr.bronze has ${BRONZE_COUNT} rows (expected ~10.8B)"
    echo "Callsign_grid will be incomplete. Continue? (y/n)"
    read -r CONFIRM
    if [ "$CONFIRM" != "y" ]; then
        echo "Aborted."
        exit 1
    fi
fi
echo "Pre-flight: wspr.bronze has ${BRONZE_COUNT} spots"

EXISTING=$(clickhouse-client --host "$CH_HOST" --query \
    "SELECT count() FROM wspr.callsign_grid")
echo "Pre-flight: callsign_grid currently has ${EXISTING} rows"
echo ""

# --------------------------------------------------------------------------
# Step 1: TX callsigns (callsign → grid)
# --------------------------------------------------------------------------
echo "[1/5] WSPR TX callsigns (callsign → grid)..."
T0=$(date +%s)

clickhouse-client --host "$CH_HOST" --query "
    INSERT INTO wspr.callsign_grid
    SELECT
        replaceAll(toString(callsign), '\0', '')                        AS callsign,
        substring(replaceAll(toString(grid), '\0', ''), 1, 6)           AS grid,
        substring(replaceAll(toString(grid), '\0', ''), 1, 4)           AS grid_4,
        count()                                                          AS spot_count,
        max(toDate(timestamp))                                           AS last_seen
    FROM wspr.bronze
    WHERE length(replaceAll(toString(grid), '\0', '')) >= 4
      AND match(replaceAll(toString(grid), '\0', ''), '^[A-R]{2}[0-9]{2}')
    GROUP BY callsign, grid
    SETTINGS max_threads = 32, max_memory_usage = 40000000000
"

TX_COUNT=$(clickhouse-client --host "$CH_HOST" --query "SELECT count() FROM wspr.callsign_grid")
T1=$(date +%s)
echo "  Done ($(( T1 - T0 ))s): ${TX_COUNT} total rows after TX insert"
echo ""

# --------------------------------------------------------------------------
# Step 2: RX reporters (reporter → reporter_grid)
# --------------------------------------------------------------------------
echo "[2/5] WSPR RX reporters (reporter → reporter_grid)..."
T0=$(date +%s)

clickhouse-client --host "$CH_HOST" --query "
    INSERT INTO wspr.callsign_grid
    SELECT
        replaceAll(toString(reporter), '\0', '')                         AS callsign,
        substring(replaceAll(toString(reporter_grid), '\0', ''), 1, 6)   AS grid,
        substring(replaceAll(toString(reporter_grid), '\0', ''), 1, 4)   AS grid_4,
        count()                                                           AS spot_count,
        max(toDate(timestamp))                                            AS last_seen
    FROM wspr.bronze
    WHERE length(replaceAll(toString(reporter_grid), '\0', '')) >= 4
      AND match(replaceAll(toString(reporter_grid), '\0', ''), '^[A-R]{2}[0-9]{2}')
    GROUP BY reporter, reporter_grid
    SETTINGS max_threads = 32, max_memory_usage = 40000000000
"

RX_COUNT=$(clickhouse-client --host "$CH_HOST" --query "SELECT count() FROM wspr.callsign_grid")
T1=$(date +%s)
echo "  Done ($(( T1 - T0 ))s): ${RX_COUNT} total rows after RX insert"
echo ""

# --------------------------------------------------------------------------
# Step 3: PSKR senders (sender_call → sender_grid)
# --------------------------------------------------------------------------
PSKR_COUNT=$(clickhouse-client --host "$CH_HOST" --query \
    "SELECT count() FROM pskr.bronze" 2>/dev/null || echo "0")

if [ "$PSKR_COUNT" -gt 0 ]; then
    echo "[3/5] PSKR senders (sender_call → sender_grid)..."
    T0=$(date +%s)

    clickhouse-client --host "$CH_HOST" --query "
        INSERT INTO wspr.callsign_grid
        SELECT
            sender_call                                    AS callsign,
            substring(sender_grid, 1, 6)                   AS grid,
            substring(sender_grid, 1, 4)                   AS grid_4,
            count()                                         AS spot_count,
            max(toDate(timestamp))                          AS last_seen
        FROM pskr.bronze
        WHERE length(sender_grid) >= 4
          AND match(sender_grid, '^[A-R]{2}[0-9]{2}')
        GROUP BY sender_call, sender_grid
        SETTINGS max_threads = 32, max_memory_usage = 40000000000
    "

    PSKR_TX=$(clickhouse-client --host "$CH_HOST" --query "SELECT count() FROM wspr.callsign_grid")
    T1=$(date +%s)
    echo "  Done ($(( T1 - T0 ))s): ${PSKR_TX} total rows after PSKR sender insert"
    echo ""

    # --------------------------------------------------------------------------
    # Step 4: PSKR receivers (receiver_call → receiver_grid)
    # --------------------------------------------------------------------------
    echo "[4/5] PSKR receivers (receiver_call → receiver_grid)..."
    T0=$(date +%s)

    clickhouse-client --host "$CH_HOST" --query "
        INSERT INTO wspr.callsign_grid
        SELECT
            receiver_call                                   AS callsign,
            substring(receiver_grid, 1, 6)                  AS grid,
            substring(receiver_grid, 1, 4)                  AS grid_4,
            count()                                          AS spot_count,
            max(toDate(timestamp))                           AS last_seen
        FROM pskr.bronze
        WHERE length(receiver_grid) >= 4
          AND match(receiver_grid, '^[A-R]{2}[0-9]{2}')
        GROUP BY receiver_call, receiver_grid
        SETTINGS max_threads = 32, max_memory_usage = 40000000000
    "

    PSKR_RX=$(clickhouse-client --host "$CH_HOST" --query "SELECT count() FROM wspr.callsign_grid")
    T1=$(date +%s)
    echo "  Done ($(( T1 - T0 ))s): ${PSKR_RX} total rows after PSKR receiver insert"
    echo ""
else
    echo "[3/5] PSKR senders — skipped (pskr.bronze empty or not found)"
    echo "[4/5] PSKR receivers — skipped (pskr.bronze empty or not found)"
    echo ""
fi

# --------------------------------------------------------------------------
# Step 5: OPTIMIZE FINAL (deduplicate)
# --------------------------------------------------------------------------
echo "[5/5] OPTIMIZE FINAL (ReplacingMergeTree dedup)..."
T0=$(date +%s)

clickhouse-client --host "$CH_HOST" --query \
    "OPTIMIZE TABLE wspr.callsign_grid FINAL"

FINAL_COUNT=$(clickhouse-client --host "$CH_HOST" --query "SELECT count() FROM wspr.callsign_grid")
T1=$(date +%s)
echo "  Done ($(( T1 - T0 ))s): ${FINAL_COUNT} unique entries after dedup"
echo ""

# --------------------------------------------------------------------------
# SAFEGUARD: Post-population assertion
# --------------------------------------------------------------------------
if [ "$FINAL_COUNT" -lt "$MIN_EXPECTED_ROWS" ]; then
    echo "============================================================"
    echo "ASSERTION FAILED"
    echo "============================================================"
    echo "callsign_grid has ${FINAL_COUNT} rows (minimum: ${MIN_EXPECTED_ROWS})"
    echo ""
    echo "This likely means wspr.bronze was truncated without"
    echo "repopulating callsign_grid. Check wspr.bronze row count."
    echo "============================================================"
    exit 1
fi

UNIQUE_CS=$(clickhouse-client --host "$CH_HOST" --query \
    "SELECT uniqExact(callsign) FROM wspr.callsign_grid")
WITH_SPOTS=$(clickhouse-client --host "$CH_HOST" --query \
    "SELECT countIf(spot_count > 0) FROM wspr.callsign_grid")

echo "============================================================"
echo "Population Complete — ASSERTION PASSED"
echo "============================================================"
echo "Total rows:        ${FINAL_COUNT}"
echo "Unique callsigns:  ${UNIQUE_CS}"
echo "With spot counts:  ${WITH_SPOTS}"
echo "From headers only: $(( FINAL_COUNT - WITH_SPOTS ))"
echo "============================================================"
echo ""
echo "REMINDER: This script must be re-run after any wspr.bronze"
echo "re-ingest (Operation Clean Slate or similar)."
echo "============================================================"
