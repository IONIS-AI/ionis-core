-- =============================================================================
-- File.........: 45-solar_xray_bronze.sql
-- Description..: GOES X-ray flux, 3-hour aggregates aligned to the Kp grid
-- Engine.......: ReplacingMergeTree
-- Population...: solar-xray-download + solar-xray-ingest
--
-- ONE TABLE PER SOURCE -- see 42-solar_kp_bronze.sql.
--
-- STORED AT 3-HOUR GRAIN, NOT 1-MINUTE, AND THAT IS A DECISION.
--
-- NOAA publishes X-ray at 1-minute. Over our era that is ~11.6 million rows, and
-- every consumer we have joins solar at 3-hour buckets to match the Kp cadence --
-- all eight signature builds do intDiv(toHour(timestamp), 3). Storing 11.6M
-- samples to serve ~64K joins is 180x more rows than anything asks for.
--
-- What is kept per bucket is what flare work actually needs: the MAXIMUM (an X-class
-- flare is defined by its peak, and a mean over three hours erases it), the mean,
-- and the count of samples the bucket was built from, so a partial bucket is
-- visible rather than silently equal to a full one.
--
-- THE RAW FILES ARE RETAINED ON DISK. This is an aggregate of a source we keep in
-- full under /mnt/solar-data/raw, so the 1-minute series is recoverable if the
-- grain ever turns out to be wrong. That is the bronze rule holding: the archive
-- is the archive-side SOT, and this table is a faithful ingest OF THE CHOSEN GRAIN,
-- stated here so nobody mistakes it for everything the source had.
--
-- If a consumer ever needs sub-3-hour X-ray, it gets its own table from the same
-- raw files rather than this one growing a second grain.
-- =============================================================================

CREATE DATABASE IF NOT EXISTS solar;

CREATE TABLE IF NOT EXISTS solar.xray_bronze
(
    observed_at   DateTime  COMMENT 'Start of the 3-hour bucket, UTC, aligned to the Kp grid',
    short_max     Float64   COMMENT '0.05-0.4nm peak in the bucket, W/m2',
    short_mean    Float64   COMMENT '0.05-0.4nm mean, W/m2',
    long_max      Float64   COMMENT '0.1-0.8nm peak in the bucket, W/m2 (the flare-class band)',
    long_mean     Float64   COMMENT '0.1-0.8nm mean, W/m2',
    sample_count  UInt16    COMMENT 'Samples the bucket was built from; 180 is a full 1-minute bucket',
    satellite     LowCardinality(String) COMMENT 'GOES spacecraft, e.g. G16, G18',
    source_file   LowCardinality(String),
    ingested_at   DateTime DEFAULT now()
)
    -- PARTITION BY DECADE, not year. These are small tables -- Kp is 277k rows and
    -- 2.8 MiB, SSN 76k -- and a partition per year produces ~100-200 tiny parts for
    -- no benefit. ClickHouse's own guidance: partitioning is for data manipulation,
    -- not query speed; the ORDER BY key already makes range queries fast. A 209-year
    -- series also exceeds max_partitions_per_insert_block at yearly grain, which is
    -- how this was found.
ENGINE = ReplacingMergeTree(ingested_at)
PARTITION BY (toYear(observed_at) - toYear(observed_at) % 10)
ORDER BY (observed_at, satellite)
SETTINGS index_granularity = 8192;
