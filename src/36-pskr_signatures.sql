-- ==============================================================================
-- Name..........: @PROGRAM@ - PSK Reporter Aggregated Signatures
-- Version.......: @VERSION@
-- Copyright.....: @COPYRIGHT@
-- Description...: Aggregated PSKR signatures with REAL machine-decoded SNR.
--
--                 PSK Reporter spots carry real SNR from FT8/FT4/WSPR/CW
--                 decoders (same quality as WSPR). 88.8% FT8, 9.1% WSPR.
--                 548M+ spots aggregated into ~9M signatures.
--
--                 Unlike RBN, PSKR has both grids in the payload — no
--                 callsign_grid enrichment needed. Grids truncated to 4-char
--                 for UNION ALL compatibility with WSPR/RBN/Contest signatures.
--
--                 Used for independent validation (never in training):
--                 every decoded PSKR spot proves the path was open. If the
--                 model predicts "closed", that's a false negative (model bug).
--
--                 SNR filter: -30 to +30 dB (machine-decoded range).
--                 Ground-wave filter: distance > 500 km.
--                 Min bucket: 3 spots.
--                 Solar: 3-hour bucket JOIN from solar.bronze.
--
--                 Date range: Oct 2025 – present (forward-only MQTT).
--                 Seasonal limitation: no summer data until collection continues.
--
--                 Schema matches wspr.signatures_v2_terrestrial,
--                 rbn.signatures, and contest.signatures exactly for
--                 UNION ALL compatibility and engineer_features() use.
--
--                 Population: scripts/populate_pskr_signatures.py
-- ==============================================================================

CREATE TABLE IF NOT EXISTS pskr.signatures (
    tx_grid_4    FixedString(4)  COMMENT '4-char TX Maidenhead grid (sender)',
    rx_grid_4    FixedString(4)  COMMENT '4-char RX Maidenhead grid (receiver/monitor)',
    band         Int32           COMMENT 'ADIF band ID (102-111)',
    hour         UInt8           COMMENT 'Hour of day UTC (0-23)',
    month        UInt8           COMMENT 'Month (1-12)',
    median_snr   Float32         COMMENT 'quantile(0.5)(snr) — REAL machine-decoded SNR',
    spot_count   UInt32          COMMENT 'Spots in bucket (min 3)',
    snr_std      Float32         COMMENT 'stddevPop(snr) — REAL variance',
    reliability  Float32         COMMENT 'Fraction of spots with SNR > -20 dB',
    avg_sfi      Float32         COMMENT 'Average Solar Flux Index for bucket',
    avg_kp       Float32         COMMENT 'Average Kp index for bucket',
    avg_distance UInt32          COMMENT 'Great-circle distance km (from grid centroids)',
    avg_azimuth  UInt16          COMMENT 'Azimuth degrees (from grid centroids)'
) ENGINE = MergeTree()
ORDER BY (band, hour, tx_grid_4, rx_grid_4)
COMMENT 'PSKR aggregated signatures — real machine-decoded SNR from 548M+ FT8/FT4/WSPR/CW spots';
