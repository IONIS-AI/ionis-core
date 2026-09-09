-- =============================================================================
-- File.........: 25-live_conditions.sql
-- Description..: Live solar conditions from NOAA SWPC for nowcasting / PSKR validation
-- Engine.......: MergeTree (durable, append-only history)
-- Population...: solar-live-update.sh (systemd timer, every 15 minutes)
--
-- Holds NOAA SWPC solar conditions at 15-minute resolution:
--   - SFI (10.7cm flux, published a few times daily from Penticton)
--   - Kp / Ap (planetary indices, 3-hourly)
--   - X-ray flux (GOES, ~5 minutes)
--
-- Unlike solar.bronze (GFZ Potsdam, ~1 day lag), this is near-real-time.
-- Use it for live PSK Reporter validation, nowcasting, and storm-aware responses.
--
-- WAS `ENGINE = Memory`, which is why this file changed.
-- ---------------------------------------------------------------------------
-- The header used to say: "Memory engine means this table is LOST on ClickHouse
-- restart. The solar-live-update.sh cron will repopulate within 15 minutes." That
-- was accepted as harmless. It is not, because the table does not come back as
-- STALE -- it comes back EMPTY, and an empty result is not the same as an old one:
--
--   * ionis-hamstats renders the solar indices as em-dashes, and then runs the
--     IONIS V22-gamma model on `solar_row.get("solar_flux", 100)` and
--     `solar_row.get("kp_index", 3)` -- inventing SFI 100 / Kp 3 and publishing
--     the resulting predictions as current conditions.
--   * ionis-docs' landing page reads the same table for its live figures.
--
-- So every ClickHouse restart opened a 15-minute window in which the public site
-- published model output derived from numbers nobody measured. Durability here is
-- not tidiness; it is what closes that window.
--
-- APPEND-ONLY. The writer INSERTs one row per run instead of replacing a single
-- row, so this is now a 15-minute-resolution record of live conditions rather than
-- a single volatile snapshot -- which is what the "live PSKR validation" use case
-- named above actually wants, and it was being discarded. ~35k rows/year.
--
-- READERS MUST ASK FOR THE LATEST ROW EXPLICITLY:
--     SELECT ... FROM wspr.live_conditions ORDER BY updated_at DESC LIMIT 1
-- A bare `LIMIT 1` returned the only row when this was Memory; against history it
-- returns an arbitrary one.
-- =============================================================================

CREATE TABLE IF NOT EXISTS wspr.live_conditions
(
    kp_index        Float32,    -- Planetary K-index (0-9, 3-hourly)
    ap_index        Float32,    -- Planetary Ap index (linear equivalent)
    solar_flux      Float32,    -- 10.7cm SFI (sfu, from Penticton)
    xray_short      Float64,    -- GOES 0.05-0.4nm X-ray flux (W/m²)
    xray_long       Float64,    -- GOES 0.1-0.8nm X-ray flux (W/m²)
    conditions      String,     -- Quiet/Unsettled/Storm/Severe Storm [+ Radio Blackout]

    -- Observation times are NOAA's own time_tags for the samples used, NOT when we
    -- fetched them. Without these the table could not answer "how old is this?" --
    -- which is how a hardcoded fallback SFI of 145 went unnoticed for months while
    -- being served as a measurement.
    sfi_observed_at DateTime,   -- NOAA time_tag of the 10cm-flux sample
    kp_observed_at  DateTime,   -- NOAA time_tag of the planetary-K sample
    updated_at      DateTime    -- when solar-live-update wrote this row
)
ENGINE = MergeTree
ORDER BY updated_at
TTL updated_at + INTERVAL 2 YEAR;
