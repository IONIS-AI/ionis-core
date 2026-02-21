-- ============================================================================
-- ionis-core: Training Run Audit Trail
-- ============================================================================
-- Two tables tracking every model training run and its epoch-by-epoch metrics.
--
-- training.runs — one row per training run:
--   - Config is source of truth (full JSON blob stored as config_json)
--   - Denormalized fields for easy cross-run queries without JSON parsing
--   - ReplacingMergeTree(updated_at): INSERT at start (status='running'),
--     INSERT again at completion (status='completed', all metrics filled).
--     If training crashes, the 'running' row persists — visible as abandoned.
--     FINAL gives the latest state per run_id.
--   - ~10-50 runs/year — no PARTITION BY needed
--
-- training.epochs — one row per epoch per run:
--   - Append-only event stream during training
--   - Rows appearing = training alive (live monitoring)
--   - ~100-200 per run, never updated
-- ============================================================================

CREATE DATABASE IF NOT EXISTS training;

CREATE TABLE IF NOT EXISTS training.runs (
    -- Identity
    run_id          UUID                        COMMENT 'Unique run identifier, generated at training start',
    version         LowCardinality(String)      COMMENT 'Model version: v20, v21, v22',
    variant         String          DEFAULT ''  COMMENT 'Run variant: alpha, beta, gamma, or empty for final',
    status          LowCardinality(String)      COMMENT 'running, completed, failed',
    hostname        LowCardinality(String)      COMMENT 'Training host: m3-ultra, 9975wx',
    git_sha         String          DEFAULT ''  COMMENT 'Git commit SHA at training start',

    -- Timing
    started_at      DateTime                    COMMENT 'When training began (UTC)',
    completed_at    Nullable(DateTime)          COMMENT 'When training finished (NULL if running/failed)',
    wall_seconds    Nullable(UInt32)            COMMENT 'Total training wall-clock seconds',

    -- Config (source of truth — full JSON blob)
    config_json     String                      COMMENT 'Complete config_vXX.json contents',

    -- Denormalized config fields (for easy querying without JSON parsing)
    dnn_dim         UInt8                       COMMENT 'DNN trunk input dimension',
    hidden_dim      UInt16                      COMMENT 'Hidden layer dimension from config',
    input_dim       UInt8                       COMMENT 'Total model input dimension (dnn + sidecars)',
    training_epochs UInt16                      COMMENT 'Configured number of epochs',
    batch_size      UInt32                      COMMENT 'Training batch size',
    trunk_lr        Float64                     COMMENT 'Trunk learning rate',
    sidecar_lr      Float64                     COMMENT 'Sidecar learning rate',
    wspr_sample     UInt32                      COMMENT 'WSPR rows sampled',
    rbn_full_sample UInt32                      COMMENT 'RBN Full rows sampled (0 = disabled)',
    rbn_dx_upsample UInt16                      COMMENT 'DXpedition upsample factor',
    contest_upsample UInt16                     COMMENT 'Contest upsample factor',

    -- Data manifest (actual rows loaded)
    total_train_rows UInt32         DEFAULT 0   COMMENT 'Actual training set rows after sampling/split',
    total_val_rows   UInt32         DEFAULT 0   COMMENT 'Actual validation set rows',
    data_date_min    Nullable(Date)             COMMENT 'Earliest date in training data',
    data_date_max    Nullable(Date)             COMMENT 'Latest date in training data',
    features         Array(String)              COMMENT 'Ordered feature list from config',

    -- Final validation metrics (filled at completion)
    val_rmse        Nullable(Float32)           COMMENT 'Best validation RMSE (sigma)',
    val_pearson     Nullable(Float32)           COMMENT 'Best validation Pearson correlation',
    sfi_benefit     Nullable(Float32)           COMMENT 'SFI sidecar benefit (sigma)',
    storm_cost      Nullable(Float32)           COMMENT 'Kp sidecar storm cost (sigma)',
    best_epoch      Nullable(UInt16)            COMMENT 'Epoch with lowest validation loss',

    -- Test results (filled after test runs)
    tst_900_score   String          DEFAULT ''  COMMENT 'TST-900 result: e.g. 8/10',
    tst_901_delta   Nullable(Float32)           COMMENT '10m day/night SNR delta (dB)',

    -- Metadata
    notes           String          DEFAULT ''  COMMENT 'Free-form annotations',
    updated_at      DateTime        DEFAULT now() COMMENT 'ReplacingMergeTree version key'
) ENGINE = ReplacingMergeTree(updated_at)
ORDER BY (run_id)
COMMENT 'Training run audit trail — one row per run, config + metrics + test results';

CREATE TABLE IF NOT EXISTS training.epochs (
    run_id          UUID                        COMMENT 'Links to training.runs',
    epoch           UInt16                      COMMENT 'Epoch number (1-based)',
    train_loss      Float32                     COMMENT 'Training loss (Huber)',
    val_loss        Float32                     COMMENT 'Validation loss (Huber)',
    val_rmse        Float32                     COMMENT 'Validation RMSE (sigma)',
    val_pearson     Float32                     COMMENT 'Validation Pearson correlation',
    sfi_benefit     Float32                     COMMENT 'SFI sidecar benefit (sigma)',
    storm_cost      Float32                     COMMENT 'Kp sidecar storm cost (sigma)',
    epoch_seconds   Float32                     COMMENT 'Wall-clock time for this epoch',
    is_best         UInt8                       COMMENT '1 if lowest val_loss so far',
    recorded_at     DateTime        DEFAULT now() COMMENT 'When this row was inserted'
) ENGINE = MergeTree()
ORDER BY (run_id, epoch)
COMMENT 'Per-epoch training metrics — append-only, one row per epoch per run';
