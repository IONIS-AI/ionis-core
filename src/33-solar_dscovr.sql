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

CREATE TABLE IF NOT EXISTS solar.dscovr (
    -- Time
    date            Date32                      COMMENT 'Date component',
    time            DateTime                    COMMENT 'Minute-level UTC timestamp',

    -- Magnetometer (GSM coordinates, nanoTesla)
    bz_gsm          Float32     DEFAULT 0       COMMENT 'IMF Bz, GSM coords (nT). Southward (negative) = storm coupling',
    bt              Float32     DEFAULT 0       COMMENT 'Total magnetic field magnitude (nT)',
    bx_gsm          Float32     DEFAULT 0       COMMENT 'IMF Bx, GSM coords (nT)',
    by_gsm          Float32     DEFAULT 0       COMMENT 'IMF By, GSM coords (nT)',

    -- Plasma
    speed           Float32     DEFAULT 0       COMMENT 'Solar wind bulk speed (km/s)',
    density         Float32     DEFAULT 0       COMMENT 'Solar wind proton density (protons/cm³)',
    temperature     Float32     DEFAULT 0       COMMENT 'Solar wind proton temperature (K)',

    -- Metadata
    source_file     LowCardinality(String)      COMMENT 'Source identifier: dscovr-7day',
    updated_at      DateTime    DEFAULT now()   COMMENT 'ReplacingMergeTree version key'
)
ENGINE = ReplacingMergeTree(updated_at)
ORDER BY (date, time)
COMMENT 'DSCOVR L1 solar wind: magnetometer (Bz/Bt/Bx/By) + plasma (speed/density/temperature). 1-min resolution, 7-day rolling from NOAA SWPC.';
