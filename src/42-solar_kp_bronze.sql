-- =============================================================================
-- File.........: 42-solar_kp_bronze.sql
-- Description..: Planetary Kp / ap index, from GFZ Potsdam — one source, one table
-- Engine.......: ReplacingMergeTree (re-fetching the archive must be idempotent)
-- Population...: solar-kp-download + solar-kp-ingest
--
-- ONE TABLE PER SOURCE. solar.bronze merged three NOAA streams into one row per
-- (date, time) with max() across whatever had staged. When a stream failed to
-- download, its column silently became 0 and the INSERT still succeeded -- and
-- because kp_index is a non-nullable Float32, a missing Kp and a genuinely quiet
-- Kp=0 are the same value. Five months of 2026 were lost that way: April through
-- August carry SFI on every row and Kp on none, and every run reported success.
--
-- Per-source tables remove that failure by construction. There is no merge, so
-- there is nothing to zero-fill; a download that fails writes no rows, and a gap
-- is visibly a gap.
--
-- WHY GFZ AND NOT NOAA. NOAA's products/noaa-planetary-k-index.json is a SEVEN DAY
-- rolling window. It was our only Kp source, which is why a missed day was
-- unrecoverable -- by the next run the window had moved past it. GFZ publishes
-- Kp_ap_since_1932.txt: the definitive series, 1932 to yesterday, 276,784 rows,
-- 16 MB, re-fetchable in full at any time. The whole class of "we missed a day"
-- stops existing.
--
-- NOAA remains useful for the last few hours GFZ has not published yet. That is a
-- nowcast overlay, not the source of record, and it belongs in its own table.
--
-- ENDPOINT NOTE: GFZ moved from kp.gfz-potsdam.de to kp.gfz.de. The old host
-- 301-redirects today; it will not forever. Third endpoint migration this year
-- after the DSCOVR RTSW move and NOAA's Kp format change, and all three failed
-- silently. The downloader follows redirects and asserts on content, not status.
--
-- SOURCE FORMAT (whitespace-separated, # comments):
--   YYY MM DD hh.h hh._m  days  days_m  Kp  ap  D
--   2026 06 15 00.0 01.50 34499.00000 34499.06250 1.333 5 1
--
-- Kp is the real value (0.000, 0.333, 0.667, 1.000 ...), NOT the 0-9 integer.
-- ap is the linear equivalent. D is the definitive flag: 1 = definitive,
-- 0 = provisional and may be revised, which is precisely why this is a
-- ReplacingMergeTree keyed on the observation time.
-- =============================================================================

CREATE DATABASE IF NOT EXISTS solar;

CREATE TABLE IF NOT EXISTS solar.kp_bronze
(
    -- DateTime64, NOT DateTime. ClickHouse DateTime spans 1970-2106, and this
    -- archive starts in 1932: the first load silently wrapped 1932-1969 into
    -- 2068-2106, producing plausible-looking rows for years that have not happened.
    -- DateTime64(0) covers 1900-2299 at the same one-second resolution.
    observed_at  DateTime64(0) COMMENT 'Start of the 3-hour interval, UTC',
    kp           Float32   COMMENT 'Planetary K index, real-valued (0.000, 0.333, 0.667, ...)',
    ap           UInt16    COMMENT 'Linear equivalent of Kp',
    definitive   UInt8     COMMENT '1 = definitive, 0 = provisional and subject to revision',
    source_file  LowCardinality(String) COMMENT 'File the row was parsed from',
    ingested_at  DateTime DEFAULT now() COMMENT 'When this row was loaded'
)
    -- PARTITION BY DECADE, not year. These are small tables -- Kp is 277k rows and
    -- 2.8 MiB, SSN 76k -- and a partition per year produces ~100-200 tiny parts for
    -- no benefit. ClickHouse's own guidance: partitioning is for data manipulation,
    -- not query speed; the ORDER BY key already makes range queries fast. A 209-year
    -- series also exceeds max_partitions_per_insert_block at yearly grain, which is
    -- how this was found.
ENGINE = ReplacingMergeTree(ingested_at)
PARTITION BY (toYear(observed_at) - toYear(observed_at) % 10)
ORDER BY observed_at
SETTINGS index_granularity = 8192;
