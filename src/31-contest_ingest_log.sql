-- ============================================================================
-- ionis-core: Contest Ingest Watermark Table
-- ============================================================================
-- Tracks which Cabrillo log files have been loaded into contest.bronze
-- by contest-ingest. Each row represents one .log file.
--
-- Design notes:
--   - ReplacingMergeTree(loaded_at) allows re-loads to update rather than
--     duplicate — only the latest row per file_path survives FINAL
--   - ORDER BY (file_path) gives O(1) lookup for "has this been loaded?"
--   - ~407K rows (one entry per Cabrillo log file)
--   - Contest logs are static (historical archives) — no file_size growth
--   - row_count=0 distinguishes primed entries (bootstrap) from real loads
--   - hostname tracks which host performed the ingest (multi-host safety)
--   - skipped_rows is the DURABLE per-file count of unreadable QSO lines. It used
--     to exist only as a running total printed to stdout, so after a 99-minute run
--     over 823K files there was no way to ask which file had dropped anything. The
--     lines themselves go to contest.parse_rejects (capped per file); this count is
--     the true total and is never capped.
-- ============================================================================

CREATE TABLE IF NOT EXISTS contest.ingest_log (
    file_path    String                  COMMENT 'Relative path: cq-ww/2005cw/k1abc.log',
    file_size    UInt64                  COMMENT 'File size in bytes at load time',
    row_count    UInt64                  COMMENT 'Rows loaded (0 for primed entries)',
    loaded_at    DateTime DEFAULT now()  COMMENT 'When loaded (UTC)',
    elapsed_ms   UInt32                  COMMENT 'Processing time ms',
    hostname     LowCardinality(String)  COMMENT 'Host that performed the load'
) ENGINE = ReplacingMergeTree(loaded_at)
ORDER BY (file_path)
SETTINGS index_granularity = 256
COMMENT 'Contest incremental ingest watermark — tracks loaded Cabrillo log files';
