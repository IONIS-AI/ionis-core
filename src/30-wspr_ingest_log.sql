-- ============================================================================
-- ionis-core: WSPR Ingest Watermark Table
-- ============================================================================
-- Tracks which archive files have been loaded into wspr.bronze by wspr-turbo.
-- Each row represents one monthly archive (wsprspots-YYYY-MM.csv.gz or .tar.gz).
--
-- Design notes:
--   - ReplacingMergeTree(loaded_at) allows re-loads to update rather than
--     duplicate — only the latest row per file_path survives FINAL
--   - ORDER BY (file_path) gives O(1) lookup for "has this been loaded?"
--   - Tiny table: ~12 rows/year (one archive per month) + historical
--   - WSPR monthly archives are cumulative — file_size tracks growth.
--     When file_size increases, the month has new data and needs re-ingest
--     (partition-drop + full reload of that month)
--   - row_count=0 distinguishes primed entries (bootstrap) from real loads
--   - hostname tracks which host performed the ingest (multi-host safety)
-- ============================================================================

CREATE TABLE IF NOT EXISTS wspr.ingest_log (
    file_path    String                  COMMENT 'Relative path: wsprspots-2026-02.csv.gz',
    file_size    UInt64                  COMMENT 'File size in bytes at load time',
    row_count    UInt64                  COMMENT 'Rows loaded (0 for primed entries)',
    loaded_at    DateTime DEFAULT now()  COMMENT 'When loaded (UTC)',
    elapsed_ms   UInt32                  COMMENT 'Processing time ms',
    hostname     LowCardinality(String)  COMMENT 'Host that performed the load'
) ENGINE = ReplacingMergeTree(loaded_at)
ORDER BY (file_path)
SETTINGS index_granularity = 256
COMMENT 'WSPR incremental ingest watermark — tracks loaded archive files';
