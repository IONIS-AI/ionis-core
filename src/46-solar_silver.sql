-- =============================================================================
-- File.........: 46-solar_silver.sql
-- Description..: All solar parameters on one 3-hour grid — the conformed dimension
-- Engine.......: ReplacingMergeTree
-- Population...: scripts/populate_solar_silver.sh, after the four bronze loads
--
-- THIS EXISTS TO DELETE EIGHT COPIES OF ONE RULE.
--
-- Every signature build did its own solar join against solar.bronze:
--
--   LEFT JOIN solar.bronze sol
--     ON toDate(c.timestamp) = sol.date
--     AND intDiv(toHour(c.timestamp), 3) = intDiv(toHour(sol.time), 3)
--
-- Eight scripts, the same expression written out eight times. Change the bucketing
-- and there are eight places to fix, with no reason to believe they stay consistent.
-- This is the same defect the Atlas hit at a different layer, where one statement
-- was written twice per backend until it moved into one place.
--
-- SILVER EXTRACTS, IT DOES NOT REPAIR. Bronze is taken as-is: four tables, four
-- sources, four cadences. This selects them onto the single grid the consumers
-- actually use and asks nothing of bronze.
--
-- THE GRID IS 3-HOURLY BECAUSE Kp IS. Kp is defined on 3-hour intervals; it is not
-- a sample that can be interpolated. Everything else is aligned onto that grid:
--
--   kp, ap        exact. One bronze row per bucket, by construction.
--   sfi           Penticton observes ~3x/day (17, 20, 23 UTC). The day's mean is
--                 carried across that day's eight buckets. F10.7 varies slowly --
--                 solar rotation, 27 days -- so a daily value on a 3-hour grid is
--                 a faithful representation, not a smear.
--   ssn           daily by definition. Same treatment.
--   xray          exact where we have it. NULL before 2026-09-15, because that feed
--                 is a 7-day window with no deep archive and we only began keeping
--                 dated copies then. NULL is the honest answer; 0 would read as
--                 "no flare activity" for twenty years.
--
-- NULLABLE ON PURPOSE. The table this replaces used non-nullable Float32 with 0 for
-- missing, which made a quiet Kp=0 and an absent Kp the same value and hid five
-- months of 2026. Every parameter here is Nullable so a gap is a gap.
--
-- READ BY: all eight signature builds plus populate_dxpedition_contest_paths.
-- That is stated because a silver with no named reader should be retired rather
-- than explained -- the lesson wspr.silver cost us.
-- =============================================================================

CREATE DATABASE IF NOT EXISTS solar;

CREATE TABLE IF NOT EXISTS solar.silver
(
    observed_at   DateTime64(0)     COMMENT 'Start of the 3-hour interval, UTC — the Kp grid',
    kp            Nullable(Float32) COMMENT 'Planetary K, real-valued; NULL = no observation',
    ap            Nullable(UInt16)  COMMENT 'Linear equivalent of Kp',
    sfi_observed  Nullable(Float32) COMMENT '10.7cm flux as measured, sfu (daily mean across that day)',
    sfi_adjusted  Nullable(Float32) COMMENT '10.7cm flux normalised to 1 AU, sfu',
    ssn           Nullable(Int16)   COMMENT 'Daily total sunspot number; NULL = unobserved',
    xray_short_max Nullable(Float64) COMMENT '0.05-0.4nm peak in the bucket, W/m2',
    xray_long_max  Nullable(Float64) COMMENT '0.1-0.8nm peak, W/m2 — the flare-class band',
    built_at      DateTime DEFAULT now()
)
    -- Decade partitions: ~64k rows over our era. Yearly would make tiny parts for
    -- no benefit, and ClickHouse's own guidance is that partitioning is for data
    -- manipulation, not query speed.
ENGINE = ReplacingMergeTree(built_at)
PARTITION BY (toYear(observed_at) - toYear(observed_at) % 10)
ORDER BY observed_at
SETTINGS index_granularity = 8192;
