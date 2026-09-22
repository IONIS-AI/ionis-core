-- =============================================================================
-- File.........: 39-validation_sfi_audit.sql
-- Description..: SFI clamp audit runs and their TST-900 physics-gate outcomes
-- Engine.......: MergeTree (append-only audit history)
-- Population...: ionis-training on the M3 (not checked out on the control node)
--
-- Both tables were created by hand on 2026-02-23 during the SFI clamp
-- investigation and carried real audit history -- 7 runs and 43 gate results --
-- with no DDL in any repository. A clean rebuild of the schema would have
-- produced a database missing the record of how the clamp floor was decided.
--
-- sfi_audit_runs is one row per training run under audit: the recipe, the clamp
-- bounds it used, what the model achieved, and the measured SFI benefit and Kp
-- cost in sigma units. tst900_results is the per-test detail behind the
-- tst900_passed/tst900_total summary on that run -- joined on audit_id.
--
-- Background on what these measured: archive/planning/SFI-FIXED-POINT.md.
-- =============================================================================

CREATE TABLE IF NOT EXISTS validation.sfi_audit_runs
(
    audit_id          String,
    run_timestamp     DateTime DEFAULT now(),
    description       String,
    recipe            String  COMMENT 'v22-gamma, v23-alpha, etc.',
    dnn_dim           UInt8,
    iri_buckets       UInt8   COMMENT '0=no IRI, 18=10-unit, 35=5-unit',
    clamp_min         Float32,
    clamp_max         Float32,
    epochs            UInt16,
    best_rmse         Float32,
    best_pearson      Float32,
    final_sfi_benefit Float32 COMMENT 'sigma units',
    final_kp_cost     Float32 COMMENT 'sigma units',
    sun_fc1_min       Float32,
    sun_fc1_max       Float32,
    sun_fc2_min       Float32,
    sun_fc2_max       Float32,
    storm_fc1_min     Float32,
    storm_fc1_max     Float32,
    storm_fc2_min     Float32,
    storm_fc2_max     Float32,
    tst900_passed     UInt8,
    tst900_total      UInt8,
    training_minutes  Float32,
    notes             String
)
ENGINE = MergeTree
ORDER BY (audit_id, run_timestamp);

CREATE TABLE IF NOT EXISTS validation.tst900_results
(
    audit_id       String,
    run_timestamp  DateTime DEFAULT now(),
    test_id        String COMMENT 'TST-901, TST-902, etc.',
    test_name      String,
    passed         UInt8,
    measured_value Float32,
    threshold      Float32,
    notes          String
)
ENGINE = MergeTree
ORDER BY (audit_id, test_id);
