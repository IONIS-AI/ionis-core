-- =============================================================================
-- File.........: 44-solar_ssn_bronze.sql
-- Description..: Daily total sunspot number, from SIDC/SILSO (Royal Obs. Belgium)
-- Engine.......: MergeTree (every line a row; loaded via staging + EXCHANGE TABLES)
-- Population...: solar-ssn-download + solar-ssn-ingest
--
-- ONE TABLE PER SOURCE -- see 42-solar_kp_bronze.sql.
--
-- SIDC is the world authority on sunspot number and publishes the full daily
-- series from 1818, 76,214 rows, 2.8 MB. We take the whole file: restricting it
-- to our era would save 2 MB and throw away the only cheap thing about it.
--
-- SSN is revised. SILSO reprocesses the series, and a value published today can
-- change. A revision arrives as the next copy of the file, which replaces the table
-- whole (staging + EXCHANGE TABLES); `definitive` is carried from the source.
--
-- A value of -1 in the source means NO OBSERVATION for that day (cloud, war,
-- instrument). It is NOT a sunspot count of -1 and must never be averaged. The
-- ingester stores it as NULL rather than -1, because -1 is exactly the kind of
-- sentinel that ends up in a mean.
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
CREATE TABLE IF NOT EXISTS solar.ssn_bronze
(
    -- Date32, NOT Date: this series starts in 1818 and Date wraps before 1970.
    observed_on  Nullable(Date32)   COMMENT 'Year;Month;Day, UTC',
    decimal_year Nullable(Float64)  COMMENT 'DecimalDate: fractional year of the day midpoint',
    ssn          Nullable(Int16)    COMMENT 'SNvalue: daily total sunspot number; NULL = no observation (source -1)',
    ssn_stddev   Nullable(Float32)  COMMENT 'SNerror: std dev across stations; NULL where the source gives -1',
    observations Nullable(UInt16)   COMMENT 'Nobs: stations contributing; 0 is a real count, NULL only if negative',
    definitive   Nullable(UInt8)    COMMENT 'Definitive: 1 definitive, 0 provisional',
    line_no      UInt32             COMMENT 'Line number in the source file, 1-based',
    raw_line     String             COMMENT 'The line exactly as the file holds it',
    parse_error  String             COMMENT 'Why the line could not be read; empty when it was',
    source_file  LowCardinality(String),
    ingested_at  DateTime DEFAULT now()
)
ENGINE = MergeTree
ORDER BY (source_file, line_no)
SETTINGS index_granularity = 8192;
