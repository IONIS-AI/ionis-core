-- ============================================================================
-- ionis-core: PSK Reporter Raw Spots Schema v1
-- ============================================================================
-- PSK Reporter MQTT reception reports: FT8/FT4/WSPR/JS8/CW spots from
-- 27K+ active monitors worldwide. Collected via pskr-collector (MQTT
-- subscriber → gzip JSONL files → this table via pskr-ingest).
--
-- FROZEN 2026-09-26. Holds 2026-02-10 .. 2026-09-26 15:24:47 UTC, 7,246,715,981 rows,
-- and receives nothing more. pskr-collector and pskr-ingest were retired (ionis-apps
-- 4.9.0) because the collector was not faithful: its grid regex erased valid ADIF
-- grids (uppercase subsquares, 8/10-character grids, lowercase fields), so 6.75 B rows
-- have no usable grid pair; it also dropped non-HF spots and 5 of 13 payload fields.
-- Live PSK Reporter data is pskr.capture_bronze (50-pskr_capture_bronze.sql), every
-- message as received, since 2026-09-26 14:11 UTC. The last spots file was loaded and
-- reconciled line for line before the freeze (#37).
--
-- Design notes:
--   - Separate 'pskr' database — clean separation from wspr/rbn/contest
--   - ADIF band IDs (Int32) via bands.GetBand(freq/1e6) for cross-dataset joins
--   - Frequency in Hz (UInt64) — PSK Reporter native unit, no precision loss
--   - Both grids come from the MQTT payload (unlike RBN which needs enrichment)
--   - String for grids — PSK Reporter sends 4 or 6 char, variable length
--   - LowCardinality(String) for mode — small cardinality (FT8, FT4, WSPR, etc.)
--   - ORDER BY matches signature query pattern (band → time → grids)
--   - Monthly partitioning consistent with wspr/rbn/contest
--   - SNR is machine-decoded (FT8/FT4/WSPR) — same quality as WSPR SNR
-- ============================================================================

-- 1. Create database
CREATE DATABASE IF NOT EXISTS pskr;

-- 2. Create raw spots table
CREATE TABLE IF NOT EXISTS pskr.bronze (
    timestamp      DateTime                COMMENT 'Spot timestamp UTC',
    sender_call    String                  COMMENT 'Transmitting callsign',
    sender_grid    String                  COMMENT 'Sender grid as the old collector kept it: EMPTY wherever its regex rejected a valid grid (uppercase subsquare, 8/10 chars, lowercase field)',
    receiver_call  String                  COMMENT 'Receiving/monitoring callsign',
    receiver_grid  String                  COMMENT 'Receiver grid as the old collector kept it: EMPTY wherever its regex rejected a valid grid (uppercase subsquare, 8/10 chars, lowercase field)',
    frequency      UInt64                  COMMENT 'Frequency in Hz (PSK Reporter native)',
    band           Int32                   COMMENT 'Lab band code (102..111 = 160m..10m) from bands.GetBand(); NOT an ADIF value: ADIF Band is a string such as 20m',
    mode           LowCardinality(String)  COMMENT 'FT8, FT4, WSPR, JS8, CW, etc.',
    snr            Int16                   COMMENT 'Signal-to-noise ratio dB (machine-decoded)'
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(timestamp)
ORDER BY (band, timestamp, sender_grid, receiver_grid)
SETTINGS index_granularity = 8192
COMMENT 'FROZEN 2026-09-26: PSK Reporter spots 2026-02-10..2026-09-26 15:24:47 UTC via the retired pskr-collector (HF only, grids erased by its regex). Live data: pskr.capture_bronze';

-- 3. The table already exists on every host, so the comments above reach it only through
--    these (idempotent, metadata-only) statements.
ALTER TABLE pskr.bronze MODIFY COMMENT 'FROZEN 2026-09-26: PSK Reporter spots 2026-02-10..2026-09-26 15:24:47 UTC via the retired pskr-collector (HF only, grids erased by its regex). Live data: pskr.capture_bronze';
ALTER TABLE pskr.bronze COMMENT COLUMN sender_grid 'Sender grid as the old collector kept it: EMPTY wherever its regex rejected a valid grid (uppercase subsquare, 8/10 chars, lowercase field)';
ALTER TABLE pskr.bronze COMMENT COLUMN receiver_grid 'Receiver grid as the old collector kept it: EMPTY wherever its regex rejected a valid grid (uppercase subsquare, 8/10 chars, lowercase field)';
ALTER TABLE pskr.bronze COMMENT COLUMN band 'Lab band code (102..111 = 160m..10m) from bands.GetBand(); NOT an ADIF value: ADIF Band is a string such as 20m';
