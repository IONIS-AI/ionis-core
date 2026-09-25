-- =============================================================================
-- File.........: 43-solar_sfi_bronze.sql
-- Description..: 10.7cm solar radio flux, from Penticton (NRC Canada)
-- Engine.......: MergeTree (every line a row; loaded via staging + EXCHANGE TABLES)
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

-- EVERY LINE IS A ROW (IONIS-AI/ionis-apps#46, 2026-09-25). This was a
-- ReplacingMergeTree keyed on observed_at. Penticton's fluxtime is ROUNDED, and 49 pairs
-- of lines share one while being separate observations -- different fluxjulian,
-- different fluxes, adjacent in the file. The merge kept one of each, picked by merge
-- order, and fluxjulian, the column that separates them, was not stored. Now a plain
-- MergeTree: one row per data line, every column, the line number and raw text;
-- an unreadable line is kept with parse_error set and NULL values.
--
-- Penticton republishes its whole history in one file, so solar-sfi-ingest loads each
-- copy into solar.sfi_bronze_staging and swaps it in with EXCHANGE TABLES only once the
-- staged row count equals the file's data lines: the table is always an exact copy of
-- one version of the file, and a failed run leaves the previous one in place.
--
-- MIGRATION on an existing host (schema changed): DROP TABLE solar.sfi_bronze, apply
-- this file, then run solar-sfi-refresh.service.
CREATE TABLE IF NOT EXISTS solar.sfi_bronze
(
    observed_at   Nullable(DateTime) COMMENT 'fluxdate + fluxtime, UTC as the file gives it (fluxtime is rounded; julian is exact)',
    julian        Nullable(Float64)  COMMENT 'fluxjulian: Julian date of the observation -- distinguishes observations sharing a rounded fluxtime',
    carrington    Nullable(Float64)  COMMENT 'fluxcarrington: Carrington rotation',
    observed_flux Nullable(Float32)  COMMENT 'fluxobsflux: measured 10.7 cm flux, sfu',
    adjusted_flux Nullable(Float32)  COMMENT 'fluxadjflux: normalised to 1 AU, sfu',
    ursi_flux     Nullable(Float32)  COMMENT 'fluxursi: URSI series D adjusted value, sfu',
    line_no       UInt32             COMMENT 'Line number in the source file, 1-based, headers counted',
    raw_line      String             COMMENT 'The line exactly as the file holds it',
    parse_error   String             COMMENT 'Why the line could not be read; empty when it was',
    source_file   LowCardinality(String),
    ingested_at   DateTime DEFAULT now()
)
ENGINE = MergeTree
ORDER BY (source_file, line_no)
SETTINGS index_granularity = 8192;
