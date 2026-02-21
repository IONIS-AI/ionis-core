#!/bin/bash
# ==============================================================================
# populate_training_runs.sh — Backfill Training Run Audit Trail
# ==============================================================================
#
# Populates training.runs with historical training run metadata from V20, V21.
# Reads config JSON from ionis-training repo (sibling directory) and combines
# with known metrics from metadata JSON files and MEMORY.
#
# Each run gets a hardcoded UUID for stable cross-session references:
#   V20:        00000000-0020-4000-8000-000000000001
#   V21-alpha:  00000000-0021-4000-8000-000000000001
#   V21-beta:   00000000-0021-4000-8000-000000000002
#
# Uses TRUNCATE + re-INSERT for idempotent reruns.
# Epoch data for these historical runs is lost (console-only output).
#
# Prerequisites:
#   - ClickHouse accessible at CH_HOST
#   - DDL 32-training_runs.sql applied (script applies it if found)
#   - ionis-training repo at ../../ionis-training/ (for config JSON files)
#
# Expected result: 3 rows in training.runs, 0 rows in training.epochs
#
# Usage:
#   bash populate_training_runs.sh
#   CH_HOST=10.60.1.1 bash populate_training_runs.sh
#
# ==============================================================================
set -e

CH_HOST="${CH_HOST:-192.168.1.90}"

START_TIME=$(date +%s)
SCRIPT_DIR="$(dirname "$0")"

# --------------------------------------------------------------------------
# Locate ionis-training for config JSON files
# --------------------------------------------------------------------------
TRAINING_DIR=""
if [ -d "$SCRIPT_DIR/../../ionis-training/versions" ]; then
    TRAINING_DIR="$SCRIPT_DIR/../../ionis-training/versions"
elif [ -d "/mnt/ai-stack/ionis-ai/ionis-training/versions" ]; then
    TRAINING_DIR="/mnt/ai-stack/ionis-ai/ionis-training/versions"
fi

# --------------------------------------------------------------------------
# Create tables if not exists (ddl/ = RPM, src/ = git repo)
# --------------------------------------------------------------------------
for DDL_FILE in 32-training_runs.sql; do
    if [ -f "$SCRIPT_DIR/../ddl/$DDL_FILE" ]; then
        clickhouse-client --host "$CH_HOST" --multiquery < "$SCRIPT_DIR/../ddl/$DDL_FILE" 2>/dev/null || true
    elif [ -f "$SCRIPT_DIR/../src/$DDL_FILE" ]; then
        clickhouse-client --host "$CH_HOST" --multiquery < "$SCRIPT_DIR/../src/$DDL_FILE" 2>/dev/null || true
    fi
done

echo "============================================================"
echo "Populating training.runs (historical backfill)"
echo "============================================================"
echo "Host:           ${CH_HOST}"
echo "Training repo:  ${TRAINING_DIR:-NOT FOUND}"
echo "Runs to load:   3 (V20, V21-alpha, V21-beta)"
echo "============================================================"
echo ""

# --------------------------------------------------------------------------
# Read config JSON files (or use empty string if not available)
# --------------------------------------------------------------------------
CONFIG_V20=""
CONFIG_V21=""
if [ -n "$TRAINING_DIR" ]; then
    if [ -f "$TRAINING_DIR/v20/config_v20.json" ]; then
        CONFIG_V20=$(cat "$TRAINING_DIR/v20/config_v20.json")
        echo "  Read config_v20.json ($(echo "$CONFIG_V20" | wc -c) bytes)"
    fi
    if [ -f "$TRAINING_DIR/v21/config_v21.json" ]; then
        CONFIG_V21=$(cat "$TRAINING_DIR/v21/config_v21.json")
        echo "  Read config_v21.json ($(echo "$CONFIG_V21" | wc -c) bytes)"
    fi
    echo ""
fi

if [ -z "$CONFIG_V20" ]; then
    echo "WARNING: config_v20.json not found — config_json will be empty for V20"
fi
if [ -z "$CONFIG_V21" ]; then
    echo "WARNING: config_v21.json not found — config_json will be empty for V21 runs"
fi

# --------------------------------------------------------------------------
# Truncate for idempotent re-run
# --------------------------------------------------------------------------
echo "Truncating training.runs..."
clickhouse-client --host "$CH_HOST" --query \
    "TRUNCATE TABLE IF EXISTS training.runs"

echo "Truncating training.epochs..."
clickhouse-client --host "$CH_HOST" --query \
    "TRUNCATE TABLE IF EXISTS training.epochs"
echo ""

# --------------------------------------------------------------------------
# Stable UUIDs for historical runs
# --------------------------------------------------------------------------
UUID_V20="00000000-0020-4000-8000-000000000001"
UUID_V21A="00000000-0021-4000-8000-000000000001"
UUID_V21B="00000000-0021-4000-8000-000000000002"

# --------------------------------------------------------------------------
# V20 — Production (2026-02-11)
# --------------------------------------------------------------------------
echo "[1/3] V20 (production) ..."

# Escape single quotes in config JSON for SQL (JSON has none, but be safe)
CONFIG_V20_ESC="${CONFIG_V20//\'/\'\'}"

clickhouse-client --host "$CH_HOST" --query "
    INSERT INTO training.runs (
        run_id, version, variant, status, hostname, git_sha,
        started_at, completed_at, wall_seconds,
        config_json,
        dnn_dim, hidden_dim, input_dim, training_epochs, batch_size,
        trunk_lr, sidecar_lr,
        wspr_sample, rbn_full_sample, rbn_dx_upsample, contest_upsample,
        total_train_rows, total_val_rows, data_date_min, data_date_max,
        features,
        val_rmse, val_pearson, sfi_benefit, storm_cost, best_epoch,
        tst_900_score, tst_901_delta,
        notes
    ) VALUES (
        '${UUID_V20}', 'v20', '', 'completed', 'm3-ultra', '',
        '2026-02-11 00:00:00', '2026-02-11 04:16:00', 15360,
        '${CONFIG_V20_ESC}',
        11, 256, 13, 100, 65536,
        1e-5, 1e-3,
        20000000, 0, 50, 1,
        24722028, 6180507, '2008-03-11', '2026-02-01',
        ['distance','freq_log','hour_sin','hour_cos','az_sin','az_cos','lat_diff','midpoint_lat','season_sin','season_cos','day_night_est','sfi','kp_penalty'],
        0.8617, 0.4879, 0.4818, 3.4869, NULL,
        '', NULL,
        'V16 physics replication in clean config-driven codebase. Backfilled from ionis_v20_meta.json.'
    )
"
echo "      done"

# --------------------------------------------------------------------------
# V21-alpha — vertex_lat only, rbn=0 (2026-02-20)
# --------------------------------------------------------------------------
echo "[2/3] V21-alpha (vertex_lat only) ..."

CONFIG_V21_ESC="${CONFIG_V21//\'/\'\'}"

clickhouse-client --host "$CH_HOST" --query "
    INSERT INTO training.runs (
        run_id, version, variant, status, hostname, git_sha,
        started_at, completed_at, wall_seconds,
        config_json,
        dnn_dim, hidden_dim, input_dim, training_epochs, batch_size,
        trunk_lr, sidecar_lr,
        wspr_sample, rbn_full_sample, rbn_dx_upsample, contest_upsample,
        total_train_rows, total_val_rows, data_date_min, data_date_max,
        features,
        val_rmse, val_pearson, sfi_benefit, storm_cost, best_epoch,
        tst_900_score, tst_901_delta,
        notes
    ) VALUES (
        '${UUID_V21A}', 'v21', 'alpha', 'completed', 'm3-ultra', '',
        '2026-02-20 10:00:00', '2026-02-20 14:00:00', NULL,
        '${CONFIG_V21_ESC}',
        13, 256, 15, 100, 65536,
        1e-5, 1e-3,
        20000000, 0, 50, 1,
        31008071, 7752018, '2008-03-11', '2026-02-20',
        ['distance','freq_log','hour_sin','hour_cos','az_sin','az_cos','lat_diff','midpoint_lat','season_sin','season_cos','mutual_darkness','mutual_daylight','vertex_lat','sfi','kp_penalty'],
        0.8234, 0.4636, 0.4818, 3.0636, NULL,
        '2/10', NULL,
        'First vertex_lat experiment. No physics gates. Backfilled from ionis_v21_alpha_meta.json.'
    )
"
echo "      done"

# --------------------------------------------------------------------------
# V21-beta — vertex_lat + physics gates, rbn=0 (2026-02-21)
# --------------------------------------------------------------------------
echo "[3/3] V21-beta (vertex_lat + physics gates) ..."

clickhouse-client --host "$CH_HOST" --query "
    INSERT INTO training.runs (
        run_id, version, variant, status, hostname, git_sha,
        started_at, completed_at, wall_seconds,
        config_json,
        dnn_dim, hidden_dim, input_dim, training_epochs, batch_size,
        trunk_lr, sidecar_lr,
        wspr_sample, rbn_full_sample, rbn_dx_upsample, contest_upsample,
        total_train_rows, total_val_rows, data_date_min, data_date_max,
        features,
        val_rmse, val_pearson, sfi_benefit, storm_cost, best_epoch,
        tst_900_score, tst_901_delta,
        notes
    ) VALUES (
        '${UUID_V21B}', 'v21', 'beta', 'completed', 'm3-ultra', '',
        '2026-02-21 00:00:00', '2026-02-21 04:00:00', NULL,
        '${CONFIG_V21_ESC}',
        13, 256, 15, 100, 65536,
        1e-5, 1e-3,
        20000000, 0, 50, 1,
        31008071, 7752018, '2008-03-11', '2026-02-20',
        ['distance','freq_log','hour_sin','hour_cos','az_sin','az_cos','lat_diff','midpoint_lat','season_sin','season_cos','mutual_darkness','mutual_daylight','vertex_lat','sfi','kp_penalty'],
        0.8307, 0.4638, 0.4818, 1.2870, NULL,
        '4/10', 0.0,
        'Physics gates (sigmoid timing). Kp distilled +3.49 to +1.29 (~63% temporal contamination). TST-901 FAIL: 0.0 dB day/night delta. Backfilled from ionis_v21_meta.json.'
    )
"
echo "      done"
echo ""

# --------------------------------------------------------------------------
# Verification
# --------------------------------------------------------------------------
FINAL_COUNT=$(clickhouse-client --host "$CH_HOST" --query \
    "SELECT count() FROM training.runs")
EPOCH_COUNT=$(clickhouse-client --host "$CH_HOST" --query \
    "SELECT count() FROM training.epochs")

if [ "$FINAL_COUNT" -ne 3 ]; then
    echo "============================================================"
    echo "ASSERTION FAILED"
    echo "============================================================"
    echo "training.runs has ${FINAL_COUNT} rows (expected: 3)"
    exit 1
fi

END_TIME=$(date +%s)
WALL=$(( END_TIME - START_TIME ))

echo "============================================================"
echo "Population Complete — Training Runs"
echo "============================================================"
echo "Runs:       ${FINAL_COUNT}"
echo "Epochs:     ${EPOCH_COUNT} (expected 0 — historical epoch data lost)"
echo "Wall time:  ${WALL}s"
echo "============================================================"
echo ""

echo "Cross-run comparison:"
clickhouse-client --host "$CH_HOST" --query "
    SELECT
        version,
        variant,
        round(val_pearson, 4)  AS pearson,
        round(val_rmse, 3)     AS rmse,
        round(sfi_benefit, 3)  AS sfi,
        round(storm_cost, 3)   AS kp,
        tst_900_score          AS tst900
    FROM training.runs FINAL
    ORDER BY started_at
    FORMAT PrettyCompact
"
echo ""
echo "============================================================"
echo "Future runs: instrument train_vXX.py to INSERT at start/end."
echo "Epoch data: INSERT into training.epochs after each epoch."
echo "============================================================"
