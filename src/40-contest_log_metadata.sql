-- =============================================================================
-- File.........: 40-contest_log_metadata.sql
-- Description..: Per-Cabrillo-log station metadata -- logger software, category, score
-- Engine.......: MergeTree
-- Population...: ionis-devel/contests/ingest_log_metadata.py, over /mnt/contest-logs/
--
-- MOVED HERE FROM ionis-devel/contests/contest_log_metadata.sql on 2026-09-22.
-- The table is real and carries 496K rows, but its DDL lived in a repository that
-- nothing applies, so a clean schema rebuild produced a database without it -- and
-- every ionis-hamstats logger query (logger_by_contest, logger_by_mode,
-- logger_categories, logger_market_share, logger_participation) then failed
-- against a schema that was, by its own account, complete.
--
-- One row per Cabrillo log file: what software wrote it, what category the station
-- entered, and what it claimed. This is the source for the logger market-share and
-- category-distribution reporting in ionis-hamstats.
--
-- PRIVACY: deliberately carries NO operator identifiers -- no callsign, no
-- operators list, no club, no name. Aggregate statistics only. Do not add them.
-- =============================================================================

CREATE DATABASE IF NOT EXISTS contest;

CREATE TABLE IF NOT EXISTS contest.log_metadata
(
    -- Contest identity
    contest              LowCardinality(String),  -- e.g. CQ-WW-CW, ARRL-DX-CW
    year                 UInt16,
    mode                 LowCardinality(String),  -- CW, SSB, RTTY, DIGI, MIXED

    -- Logger software
    created_by_raw       String,                  -- raw CREATED-BY value
    logger               LowCardinality(String),  -- normalized family (N1MM, Win-Test, ...)

    -- Category fields
    category_operator    LowCardinality(String),  -- SINGLE-OP, MULTI-ONE, MULTI-TWO, ...
    category_assisted    LowCardinality(String),  -- ASSISTED, NON-ASSISTED
    category_power       LowCardinality(String),  -- HIGH, LOW, QRP
    category_band        LowCardinality(String),  -- ALL, 20M, 40M, ...
    category_transmitter LowCardinality(String),  -- ONE, TWO, UNLIMITED, SWL
    category_station     LowCardinality(String),  -- FIXED, MOBILE, PORTABLE, ROVER, ...
    category_overlay     LowCardinality(String),  -- ROOKIE, TB-WIRES, CLASSIC, ...

    -- Metadata (non-identifying)
    location             LowCardinality(String),  -- ARRL section or DX
    claimed_score        UInt32 DEFAULT 0,
    qso_count            UInt32 DEFAULT 0         -- counted from QSO: lines
)
ENGINE = MergeTree()
ORDER BY (contest, year, logger, mode)
SETTINGS index_granularity = 8192;
