-- =============================================================================
-- File.........: 44-solar_ssn_bronze.sql
-- Description..: Daily total sunspot number, from SIDC/SILSO (Royal Obs. Belgium)
-- Engine.......: ReplacingMergeTree
-- Population...: solar-ssn-download + solar-ssn-ingest
--
-- ONE TABLE PER SOURCE -- see 42-solar_kp_bronze.sql.
--
-- SIDC is the world authority on sunspot number and publishes the full daily
-- series from 1818, 76,214 rows, 2.8 MB. We take the whole file: restricting it
-- to our era would save 2 MB and throw away the only cheap thing about it.
--
-- SSN is revised. SILSO reprocesses the series, and a value published today can
-- change -- hence ReplacingMergeTree keyed on the observation date, and hence
-- `definitive` carried from the source rather than assumed.
--
-- A value of -1 in the source means NO OBSERVATION for that day (cloud, war,
-- instrument). It is NOT a sunspot count of -1 and must never be averaged. The
-- ingester stores it as NULL rather than -1, because -1 is exactly the kind of
-- sentinel that ends up in a mean.
-- =============================================================================

CREATE DATABASE IF NOT EXISTS solar;

CREATE TABLE IF NOT EXISTS solar.ssn_bronze
(
    -- Date32, NOT Date. ClickHouse Date spans 1970-2149, and this series starts in
    -- 1818: a first load silently wrapped 1818-1969 into 2078-2149 and produced
    -- 65,540 rows from a 76,214-row file, losing 10,674 without an error. Date32
    -- covers 1900-2299. The same trap caught kp_bronze one table earlier with
    -- DateTime (1970-2106) -- worth checking the range of any date type against the
    -- range of the archive before loading it, not after.
    observed_on  Date32    COMMENT 'Observation date UTC',
    ssn          Nullable(Int16)   COMMENT 'Daily total sunspot number; NULL = no observation (source -1)',
    ssn_stddev   Nullable(Float32) COMMENT 'Standard deviation across contributing stations',
    observations Nullable(UInt16)  COMMENT 'Number of stations contributing',
    definitive   UInt8     COMMENT '1 = definitive, 0 = provisional and subject to revision',
    source_file  LowCardinality(String),
    ingested_at  DateTime DEFAULT now()
)
    -- PARTITION BY DECADE, not year. These are small tables -- Kp is 277k rows and
    -- 2.8 MiB, SSN 76k -- and a partition per year produces ~100-200 tiny parts for
    -- no benefit. ClickHouse's own guidance: partitioning is for data manipulation,
    -- not query speed; the ORDER BY key already makes range queries fast. A 209-year
    -- series also exceeds max_partitions_per_insert_block at yearly grain, which is
    -- how this was found.
ENGINE = ReplacingMergeTree(ingested_at)
PARTITION BY (toYear(observed_on) - toYear(observed_on) % 10)
ORDER BY observed_on
SETTINGS index_granularity = 8192;
