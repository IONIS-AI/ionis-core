-- ============================================================================
-- ionis-core: DSCOVR L1 Solar Wind Data
-- ============================================================================
-- Real-time solar wind measurements from the DSCOVR satellite at the Sun-Earth
-- L1 Lagrange point (~1.5M km upstream). Data arrives 15-45 minutes before the
-- solar wind hits Earth's magnetosphere, giving predictive lead over Kp.
--
-- Source: NOAA SWPC rolling 7-day JSON
--   - Magnetometer: Bz (southward = storm coupling), Bt, Bx, By (nT, GSM coords)
--   - Plasma: bulk speed (km/s), proton density (p/cm³), temperature (K)
--
-- Ingested by `dscovr-ingest` every 15 minutes. 1-minute resolution, ~10K rows
-- per 7-day window. ReplacingMergeTree handles overlapping windows automatically.
--
-- Key column for V23 model: bz_gsm (southward Bz drives geomagnetic storms)
-- ============================================================================

-- MISSING IS NULL, NOT 0 (2026-09-24, IONIS-AI/ionis-apps#35). The measurements were
-- Float32 DEFAULT 0 and the ingester wrote 0 when the feed sent null, so a missing reading
-- became a measurement: 7,049 speed, 6,433 density and 5,265 Bz zeros in 219,242 rows.
-- New rows keep NULL. Zeros already stored before the change cannot be told apart from
-- real zeros, so they stay; the archive tables are the clean record for those dates.
-- MIGRATION on an existing host:
--   ALTER TABLE solar.dscovr MODIFY COLUMN <col> Nullable(Float32)   -- for each of the 7
CREATE TABLE IF NOT EXISTS solar.dscovr (
    -- Time
    date            Date32                      COMMENT 'Date component',
    time            DateTime                    COMMENT 'Minute-level UTC timestamp',

    -- Magnetometer (GSM coordinates, nanoTesla)
    bz_gsm          Nullable(Float32)       COMMENT 'IMF Bz, GSM coords (nT). Southward (negative) = storm coupling',
    bt              Nullable(Float32)       COMMENT 'Total magnetic field magnitude (nT)',
    bx_gsm          Nullable(Float32)       COMMENT 'IMF Bx, GSM coords (nT)',
    by_gsm          Nullable(Float32)       COMMENT 'IMF By, GSM coords (nT)',

    -- Plasma
    speed           Nullable(Float32)       COMMENT 'Solar wind bulk speed (km/s)',
    density         Nullable(Float32)       COMMENT 'Solar wind proton density (protons/cm³)',
    temperature     Nullable(Float32)       COMMENT 'Solar wind proton temperature (K)',

    -- Metadata
    source_file     LowCardinality(String)      COMMENT 'Source: rtsw-1m/<spacecraft> (SOLAR1 = DSCOVR, ACE, IMAP)',
    updated_at      DateTime    DEFAULT now()   COMMENT 'ReplacingMergeTree version key'
)
ENGINE = ReplacingMergeTree(updated_at)
ORDER BY (date, time)
COMMENT 'DSCOVR L1 solar wind: magnetometer (Bz/Bt/Bx/By) + plasma (speed/density/temperature). 1-min resolution, live RTSW feed from NOAA SWPC (~24 h window). Missing = NULL. Archive history: solar.dscovr_{f1m,m1m}_bronze.';
