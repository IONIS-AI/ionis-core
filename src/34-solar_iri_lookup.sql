-- ============================================================================
-- ionis-core: IRI-2020 Ionospheric Parameter Lookup Table
-- ============================================================================
-- Pre-computed IRI-2020 ionospheric parameters (foF2, hmF2, foE) for every
-- unique 4-char Maidenhead grid in the training pool. Keyed by grid, UTC hour,
-- month, and SFI bucket so training scripts can look up path-specific
-- ionospheric state without calling PyIRI in the training loop.
--
-- Populated by: populate_iri_lookup.py (one-time, ~3 hours on 32 cores)
-- Source:       PyIRI (pure Python IRI-2020, BSD license)
--
-- V23 features derived from this table:
--   foF2_freq_ratio = foF2_mid / freq_mhz  (above 1 = band open)
--   foE_mid         = E-layer critical freq (D/E absorption proxy)
--   hmF2_mid        = F2 peak height        (skip geometry)
-- ============================================================================

CREATE TABLE IF NOT EXISTS solar.iri_lookup (
    grid_4       FixedString(4)  COMMENT '4-char Maidenhead grid',
    hour         UInt8           COMMENT 'UTC hour (0-23)',
    month        UInt8           COMMENT 'Month (1-12)',
    sfi_bucket   UInt16          COMMENT 'SFI bucket center (70-240, step 10)',
    foF2         Float32         COMMENT 'F2 critical frequency (MHz)',
    hmF2         Float32         COMMENT 'F2 peak height (km)',
    foE          Float32         COMMENT 'E-layer critical frequency (MHz)',
    updated_at   DateTime DEFAULT now()
) ENGINE = ReplacingMergeTree(updated_at)
ORDER BY (grid_4, hour, month, sfi_bucket)
COMMENT 'IRI-2020 ionospheric parameters pre-computed by PyIRI for training feature lookup';
