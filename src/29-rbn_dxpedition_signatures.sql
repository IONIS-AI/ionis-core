-- ==============================================================================
-- Name..........: @PROGRAM@ - RBN DXpedition Signatures
-- Version.......: @VERSION@
-- Copyright.....: @COPYRIGHT@
-- Description...: Aggregated signatures from RBN DXpedition synthesis.
--                 Schema matches wspr.signatures_v1 for UNION in training.
--                 Source: rbn.dxpedition_paths (2.52M one-way skimmer
--                 observations, NOT confirmed QSOs).
--
--                 Used in V13+ training: 91K rows × 50x upsample = 4.55M
--                 effective training examples for rare DXCC path coverage.
--
-- Depends on...: 19-dxpedition_synthesis.sql (rbn.dxpedition_paths)
-- ==============================================================================

CREATE TABLE IF NOT EXISTS rbn.dxpedition_signatures (
    tx_grid_4      FixedString(4)  COMMENT '4-char TX Maidenhead grid (DXpedition entity-level approximation)',
    rx_grid_4      FixedString(4)  COMMENT '4-char RX Maidenhead grid (skimmer from callsign_grid)',
    band           Int32           COMMENT 'ADIF band ID (102-111)',
    hour           UInt8           COMMENT 'Hour of day UTC (0-23)',
    month          UInt8           COMMENT 'Month (1-12)',
    median_snr     Float32         COMMENT 'medianExact(snr) - machine-measured from RBN skimmers',
    spot_count     UInt32          COMMENT 'Spots in bucket (min 5)',
    snr_std        Float32         COMMENT 'SNR standard deviation dB',
    reliability    Float32         COMMENT 'Fraction of spots with SNR > -20 dB',
    avg_sfi        Float32         COMMENT 'Average Solar Flux Index for bucket',
    avg_kp         Float32         COMMENT 'Average Kp index for bucket',
    avg_distance   UInt32          COMMENT 'Average great-circle distance km',
    avg_azimuth    UInt16          COMMENT 'Average azimuth degrees'
) ENGINE = MergeTree()
ORDER BY (band, hour, tx_grid_4, rx_grid_4)
COMMENT 'DERIVED: Aggregated signatures from RBN DXpedition synthesis. Schema matches wspr.signatures_v1 for UNION in V13 training. Source: rbn.dxpedition_paths (2.52M one-way skimmer observations, NOT confirmed QSOs).';
