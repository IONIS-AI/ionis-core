-- =============================================================================
-- File.........: 42-solar_kp_bronze.sql
-- Description..: Planetary Kp / ap index, from GFZ Potsdam — one source, one table
-- Engine.......: MergeTree (every line a row; loaded via staging + EXCHANGE TABLES, so re-fetching is idempotent)
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
-- 0 = provisional and may be revised. A revision arrives as the next copy of the file,
-- which replaces the table whole (staging + EXCHANGE TABLES) -- no merge decides it.
-- =============================================================================

CREATE DATABASE IF NOT EXISTS solar;

-- EVERY LINE IS A ROW, EVERY COLUMN KEPT (2026-09-25, the #46 pattern). Was a
-- ReplacingMergeTree keyed on the date that stored only some of the source columns.
-- Now a plain MergeTree, one row per data line with line number and raw text; source
-- sentinels (-1) are NULL; an unreadable line is kept with parse_error set. The source
-- republishes its whole series each time, so the ingester loads a staging table,
-- checks its count against the file, and swaps it in with EXCHANGE TABLES.
-- MIGRATION on an existing host (schema changed): DROP TABLE, apply this file, run the
-- refresh service.
CREATE TABLE IF NOT EXISTS solar.kp_bronze
(
    -- DateTime64, NOT DateTime. ClickHouse DateTime spans 1970-2106, and this
    -- archive starts in 1932: the first load silently wrapped 1932-1969 into
    -- 2068-2106. DateTime64(0) covers 1900-2299 at one-second resolution.
    observed_at  Nullable(DateTime64(0, 'UTC')) COMMENT 'YYY MM DD hh.h: start of the 3-hour interval, UTC',
    hour_mid     Nullable(Float32)  COMMENT 'hh._m: hour of the interval midpoint',
    days         Nullable(Float64)  COMMENT 'days: days since 1932-01-01 00:00 UT, interval start',
    days_mid     Nullable(Float64)  COMMENT 'days_m: same, interval midpoint',
    kp           Nullable(Float32)  COMMENT 'Kp, real-valued (0.000, 0.333, ...); NULL where GFZ publishes -1',
    ap           Nullable(UInt16)   COMMENT 'ap, linear equivalent of Kp; NULL where GFZ publishes -1',
    definitive   Nullable(UInt8)    COMMENT 'D: 1 definitive, 0 provisional (revised in a later copy of the file)',
    line_no      UInt32             COMMENT 'Line number in the source file, 1-based, comments counted',
    raw_line     String             COMMENT 'The line exactly as the file holds it',
    parse_error  String             COMMENT 'Why the line could not be read; empty when it was',
    source_file  LowCardinality(String),
    ingested_at  DateTime DEFAULT now()
)
ENGINE = MergeTree
ORDER BY (source_file, line_no)
SETTINGS index_granularity = 8192;
