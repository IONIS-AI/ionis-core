#!/bin/bash
# ==============================================================================
# populate_dxpedition_catalog.sh — GDXF Mega DXpeditions Honor Roll
# ==============================================================================
#
# Loads the static dxpedition catalog (332 curated entries) from a TSV file
# into dxpedition.catalog. The catalog contains callsign, entity, approximate
# grid, year, QSO count, and operation time windows from GDXF Mega DXpeditions
# Honor Roll.
#
# The catalog is curated reference data — grids are entity-level approximations
# assigned manually, dates were parsed from GDXF free-text. Multi-callsign
# entries (e.g. "3D22, 3D2V") are stored as-is; splitting happens downstream
# in populate_dxpedition_paths.sh.
#
# Prerequisites:
#   - dxpedition.catalog table exists (19-dxpedition_synthesis.sql)
#   - dxpedition-catalog.tsv data file in ../data/ (RPM) or ../data/ (git)
#
# Expected result: 332 rows
#
# Usage:
#   bash populate_dxpedition_catalog.sh
#   CH_HOST=10.60.1.1 bash populate_dxpedition_catalog.sh
#
# ==============================================================================
set -e

CH_HOST="${CH_HOST:-192.168.1.90}"
MIN_EXPECTED_ROWS=300

START_TIME=$(date +%s)
SCRIPT_DIR="$(dirname "$0")"

echo "============================================================"
echo "Populating dxpedition.catalog"
echo "============================================================"
echo "Host:           ${CH_HOST}"
echo "============================================================"
echo ""

# --------------------------------------------------------------------------
# Create table if not exists (ddl/ = RPM, src/ = git repo)
# --------------------------------------------------------------------------
DDL_FILE="19-dxpedition_synthesis.sql"
if [ -f "$SCRIPT_DIR/../ddl/$DDL_FILE" ]; then
    clickhouse-client --host "$CH_HOST" --multiquery < "$SCRIPT_DIR/../ddl/$DDL_FILE" 2>/dev/null || true
elif [ -f "$SCRIPT_DIR/../src/$DDL_FILE" ]; then
    clickhouse-client --host "$CH_HOST" --multiquery < "$SCRIPT_DIR/../src/$DDL_FILE" 2>/dev/null || true
fi

# --------------------------------------------------------------------------
# Locate data file (data/ works for both RPM and git)
# --------------------------------------------------------------------------
DATA_FILE=""
if [ -f "$SCRIPT_DIR/../data/dxpedition-catalog.tsv" ]; then
    DATA_FILE="$SCRIPT_DIR/../data/dxpedition-catalog.tsv"
else
    echo "ERROR: dxpedition-catalog.tsv not found in $SCRIPT_DIR/../data/"
    exit 1
fi
echo "Data file:      ${DATA_FILE}"
echo ""

# --------------------------------------------------------------------------
# Truncate for idempotent re-run
# --------------------------------------------------------------------------
echo "Truncating dxpedition.catalog..."
clickhouse-client --host "$CH_HOST" --query \
    "TRUNCATE TABLE IF EXISTS dxpedition.catalog"
echo ""

# --------------------------------------------------------------------------
# Load TSV (skip header line)
# --------------------------------------------------------------------------
echo "Loading catalog from TSV..."
T0=$(date +%s)

clickhouse-client --host "$CH_HOST" --query \
    "INSERT INTO dxpedition.catalog FORMAT TabSeparatedWithNames" \
    < "$DATA_FILE"

T1=$(date +%s)
echo "  Done ($((T1 - T0))s)"
echo ""

# --------------------------------------------------------------------------
# SAFEGUARD: Post-population assertion
# --------------------------------------------------------------------------
FINAL_COUNT=$(clickhouse-client --host "$CH_HOST" --query \
    "SELECT count() FROM dxpedition.catalog")

if [ "$FINAL_COUNT" -lt "$MIN_EXPECTED_ROWS" ]; then
    echo "============================================================"
    echo "ASSERTION FAILED"
    echo "============================================================"
    echo "dxpedition.catalog has ${FINAL_COUNT} rows (minimum: ${MIN_EXPECTED_ROWS})"
    echo ""
    echo "Check that dxpedition-catalog.tsv is present and not corrupt."
    echo "============================================================"
    exit 1
fi

UNIQUE_ENTITIES=$(clickhouse-client --host "$CH_HOST" --query \
    "SELECT uniqExact(entity) FROM dxpedition.catalog")
MULTI_CS=$(clickhouse-client --host "$CH_HOST" --query \
    "SELECT countIf(position(callsign, ', ') > 0) FROM dxpedition.catalog")
YEAR_RANGE=$(clickhouse-client --host "$CH_HOST" --query \
    "SELECT concat(toString(min(year)), '-', toString(max(year))) FROM dxpedition.catalog")

END_TIME=$(date +%s)
WALL=$(( END_TIME - START_TIME ))

echo "============================================================"
echo "Population Complete — DXpedition Catalog"
echo "============================================================"
echo "Total entries:      ${FINAL_COUNT}"
echo "Unique entities:    ${UNIQUE_ENTITIES}"
echo "Multi-callsign:     ${MULTI_CS} entries"
echo "Year range:         ${YEAR_RANGE}"
echo "Wall time:          ${WALL}s"
echo "============================================================"
echo ""
echo "Next: run populate_dxpedition_paths.sh to cross-reference"
echo "catalog with RBN spots and generate signatures."
echo "============================================================"
