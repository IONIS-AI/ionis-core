-- =============================================================================
-- File.........: 43-solar_sfi_bronze.sql
-- Description..: 10.7cm solar radio flux, from Penticton (NRC Canada)
-- Engine.......: ReplacingMergeTree
-- Population...: solar-sfi-download + solar-sfi-ingest
--
-- ONE TABLE PER SOURCE -- see 42-solar_kp_bronze.sql for why solar.bronze's
-- three-stream merge lost five months of 2026.
--
-- PENTICTON IS THE SOURCE OF RECORD, not NOAA. NOAA's 10cm-flux-30-day.json is a
-- 30-day window; Penticton publishes fluxtable.txt, the observatory's own series,
-- 2004-10-28 to today, 23,963 rows, 2.1 MB, re-fetchable in full.
--
-- 2004-10-28 is where the published table starts, and it is 11 months before our
-- earliest contest QSO (2005-10-09) and 3 years before WSPR. So this covers
-- everything we hold. There is no deeper SFI available at this cadence from any
-- source -- monthly means go back to 1947 via NOAA solar-cycle, but that is a
-- different grain and a different table if it is ever wanted.
--
-- THREE OBSERVATIONS A DAY, not one. Penticton measures at 17, 20 and 23 UTC.
-- NOAA's feed publishes a single daily value; keeping all three preserves
-- intra-day variation that the daily rollup discards.
--
-- observed vs adjusted: observed is what the antenna measured; adjusted is
-- normalised to 1 AU, removing the annual variation from Earth's orbit. Models
-- generally want adjusted. Both are kept because the choice belongs to the
-- consumer, not the ingester.
-- =============================================================================

CREATE DATABASE IF NOT EXISTS solar;

CREATE TABLE IF NOT EXISTS solar.sfi_bronze
(
    observed_at   DateTime  COMMENT 'Observation time UTC (Penticton measures at 17, 20, 23)',
    observed_flux Float32   COMMENT 'Measured 10.7cm flux, sfu',
    adjusted_flux Float32   COMMENT 'Normalised to 1 AU, sfu',
    ursi_flux     Float32   COMMENT 'URSI series D adjusted value, sfu',
    carrington    Float32   COMMENT 'Carrington rotation number',
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
ORDER BY observed_at
SETTINGS index_granularity = 8192;
