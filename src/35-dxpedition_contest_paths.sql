-- ============================================================================
-- ionis-core: DXpedition-Contest Path Observations
-- ============================================================================
-- Cross-references DXpedition catalog with contest QSO logs to find
-- observations of DXpedition callsigns during their active dates. Each row
-- is a one-sided observation: a contester logged working a DXpedition
-- callsign within the operation window. We do NOT have the DXpedition's
-- log to confirm the other side — these are observations, not confirmed QSOs.
--
-- These paths are HIGH-VALUE validation data: rare grids (Kermadec, Andaman,
-- Madagascar, etc.) that WSPR beacons and RBN skimmers will never cover.
-- Each observation represents a path where propagation was physically
-- possible — the contester decoded or copied the DXpedition signal.
--
-- Populated by: populate_dxpedition_contest_paths.sh
-- Sources:      contest.bronze × dxpedition.catalog × callsign_grid × solar.bronze
-- ============================================================================

CREATE DATABASE IF NOT EXISTS validation;

CREATE TABLE IF NOT EXISTS validation.dxpedition_contest_paths (
    -- DXpedition side
    dxe_callsign    String          COMMENT 'DXpedition callsign from GDXF catalog',
    dxe_entity      String          COMMENT 'DXCC entity name',
    dxe_grid        FixedString(4)  COMMENT 'DXpedition grid (from catalog)',

    -- Contester side (observer)
    ctr_callsign    String          COMMENT 'Contester callsign (observer)',
    ctr_grid        FixedString(4)  COMMENT 'Contester grid (from callsign_grid)',

    -- Path metadata
    band            Int32           COMMENT 'ADIF band ID',
    timestamp       DateTime        COMMENT 'Observation timestamp UTC',
    hour_utc        UInt8           COMMENT 'Hour of observation (0-23)',
    month           UInt8           COMMENT 'Month of observation (1-12)',
    day_of_year     UInt16          COMMENT 'Day of year (1-366)',
    contest         LowCardinality(String) COMMENT 'Contest ID',
    mode            LowCardinality(String) COMMENT 'CW, PH, RY, DG',

    -- Solar conditions (daily values for the observation date)
    sfi             Float32         COMMENT 'Observed solar flux (F10.7) for observation date',
    kp              Float32         COMMENT 'Kp index for observation date (daily mean)',

    -- Computed at insert time
    distance_km     Float32         COMMENT 'Great-circle distance (km)',

    updated_at      DateTime DEFAULT now()
) ENGINE = ReplacingMergeTree(updated_at)
ORDER BY (dxe_callsign, ctr_callsign, band, timestamp)
COMMENT 'DXpedition path observations from contest logs — rare-grid validation data';
