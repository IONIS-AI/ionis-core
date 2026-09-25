-- 49-solar_goes_xrs_bronze.sql — GOES X-ray (XRS) 1-minute averages, NOAA NCEI archive
--
-- ONE SOURCE, ONE DOWNLOAD, ONE INGEST (Judge, 2026-09-25). Replaces solar.xray_bronze,
-- which polled SWPC's 7-day window and so never held more than a week of history.
--
-- SOURCE. NCEI product xrsf-l2-avg1m_science, one netCDF-4 file per satellite per day:
--   data.ngdc.noaa.gov/platforms/solar-space-observing-satellites/goes/<sat>/l2/data/
--       xrsf-l2-avg1m_science/YYYY/MM/sci_xrsf-l2-avg1m_gNN_dYYYYMMDD_v2-2-1.nc
--   GOES-16 2017-02-07..2025-04-06 · GOES-17 2018-06-01..2023-01-10 · GOES-18 2022-06-17..
--   · GOES-19 2024-09-20.. (enumerated 2026-09-25: 6,809 files)
-- goes-xrs-download mirrors them unchanged to $IONIS_SOLAR_DATA_DIR/goes-xrs/<sat>/YYYY/MM/
-- (the archive source of truth); goes-xrs-ingest loads them, reading each with Unidata's
-- ncdump (EPEL netcdf) -- nothing is linked.
--
-- DECLARED GAPS. NOAA publishes no file for GOES-17 on 2018-08-06..2018-09-13 (39 days)
-- or 2019-08-28..2019-12-17 (112 days). An audit that compares mirror to bronze passes
-- with those gaps; verify_goes_xrs_ingest.sh therefore reports, per satellite, every day
-- inside its span that has no file, so a gap is always stated and never hidden.
--
-- BRONZE GETS EVERYTHING (DATA-DICTIONARY §0). Every record of every file of every
-- satellite, every variable, named as the file names it. Satellites overlap in time and
-- are all kept, tagged by `satellite`; choosing between them is silver's job. Flags are
-- carried as sent, nothing filtered on quality. A value equal to the variable's
-- _FillValue (ncdump prints it as "_") is NULL -- never -9999, never 0.
--
-- TIME. `time` is kept as the file stores it: seconds since 2000-01-01 12:00:00 UTC,
-- leap seconds neglected (the file's own time:comments says so). observed_at is derived
-- from it the same way, so it is off true UTC by the leap seconds since 2000 (5 s).

CREATE DATABASE IF NOT EXISTS solar;

CREATE TABLE IF NOT EXISTS solar.goes_xrs_1m_bronze (
    satellite                     LowCardinality(String)    COMMENT 'g16, g17, g18, g19 -- from the file name',
    observed_at                   Nullable(DateTime64(3, 'UTC')) COMMENT 'Record start, derived from time (leap seconds neglected, as the file states)',
    xrsa_flux                     Nullable(Float32)         COMMENT 'XRS-A primary average flux. [W/m2]; NULL where the file holds _FillValue -9999.f',
    xrsa_flux_observed            Nullable(Float32)         COMMENT 'XRS-A primary average flux, without electron contamination correction. [W/m2]; NULL where the file holds _FillValue -9999.f',
    xrsa_flux_electrons           Nullable(Float32)         COMMENT 'XRS-A primary electron contamination. [W/m2]; NULL where the file holds _FillValue -9999.f',
    xrsb_flux                     Nullable(Float32)         COMMENT 'XRS-B primary average flux. [W/m2]; NULL where the file holds _FillValue -9999.f',
    xrsb_flux_observed            Nullable(Float32)         COMMENT 'XRS-B primary average flux, without electron contamination correction. [W/m2]; NULL where the file holds _FillValue -9999.f',
    xrsb_flux_electrons           Nullable(Float32)         COMMENT 'XRS-B primary electron contamination. [W/m2]; NULL where the file holds _FillValue -9999.f',
    xrsa_flag                     Nullable(UInt8)           COMMENT 'Flags for xrsa_flux.; NULL where the file holds _FillValue 255UB',
    xrsb_flag                     Nullable(UInt8)           COMMENT 'Flags for xrsb_flux.; NULL where the file holds _FillValue 255UB',
    xrsa_num                      Nullable(UInt8)           COMMENT 'Number of averaged measurements in xrsa_flux.; NULL where the file holds _FillValue 255UB',
    xrsb_num                      Nullable(UInt8)           COMMENT 'Number of averaged measurements in xrsb_flux.; NULL where the file holds _FillValue 255UB',
    time                          Nullable(Float64)         COMMENT 'Record start time. Neglects leap seconds since 2000-01-01. [seconds since 2000-01-01 12:00:00 UTC]; NULL where the file holds _FillValue -9999.',
    xrsa_flag_excluded            Nullable(UInt16)          COMMENT 'Flags on data excluded from xrsa_flux average.; NULL where the file holds _FillValue 65535US',
    xrsb_flag_excluded            Nullable(UInt16)          COMMENT 'Flags on data excluded from xrsb_flux average.; NULL where the file holds _FillValue 65535US',
    au_factor                     Nullable(Float32)         COMMENT '1-AU factor.; NULL where the file holds _FillValue -9999.f',
    corrected_current_xrsb2       Array(Nullable(Float32))  COMMENT 'Corrected currents for XRS-B2 quad diodes. [A]; NULL where the file holds _FillValue -9999.f',
    roll_angle                    Nullable(Float32)         COMMENT 'Angular offset of SPP relative to the celestial north rotational pole measured counterclockwise. [degrees]; NULL where the file holds _FillValue -9999.f',
    xrsa1_flux                    Nullable(Float32)         COMMENT 'XRS-A1 average flux. [W/m2]; NULL where the file holds _FillValue -9999.f',
    xrsa1_flux_observed           Nullable(Float32)         COMMENT 'XRS-A1 average flux, without electron contamination correction. [W/m2]; NULL where the file holds _FillValue -9999.f',
    xrsa1_flux_electrons          Nullable(Float32)         COMMENT 'XRS-A1 electron contamination. [W/m2]; NULL where the file holds _FillValue -9999.f',
    xrsa2_flux                    Nullable(Float32)         COMMENT 'XRS-A2 average flux. [W/m2]; NULL where the file holds _FillValue -9999.f',
    xrsa2_flux_observed           Nullable(Float32)         COMMENT 'XRS-A2 average flux, without electron contamination correction. [W/m2]; NULL where the file holds _FillValue -9999.f',
    xrsa2_flux_electrons          Nullable(Float32)         COMMENT 'XRS-A2 electron contamination. [W/m2]; NULL where the file holds _FillValue -9999.f',
    xrsb1_flux                    Nullable(Float32)         COMMENT 'XRS-B1 average flux. [W/m2]; NULL where the file holds _FillValue -9999.f',
    xrsb1_flux_observed           Nullable(Float32)         COMMENT 'XRS-B1 average flux, without electron contamination correction. [W/m2]; NULL where the file holds _FillValue -9999.f',
    xrsb1_flux_electrons          Nullable(Float32)         COMMENT 'XRS-B1 electron contamination. [W/m2]; NULL where the file holds _FillValue -9999.f',
    xrsb2_flux                    Nullable(Float32)         COMMENT 'XRS-B2 average flux. [W/m2]; NULL where the file holds _FillValue -9999.f',
    xrsb2_flux_observed           Nullable(Float32)         COMMENT 'XRS-B2 average flux, without electron contamination correction. [W/m2]; NULL where the file holds _FillValue -9999.f',
    xrsb2_flux_electrons          Nullable(Float32)         COMMENT 'XRS-B2 electron contamination. [W/m2]; NULL where the file holds _FillValue -9999.f',
    xrs_primary_chan              Nullable(UInt8)           COMMENT 'Primary XRS channel.; NULL where the file holds _FillValue 0UB',
    xrsa1_flag                    Nullable(UInt16)          COMMENT 'Flags for xrsa1_flux.; NULL where the file holds _FillValue 65535US',
    xrsa2_flag                    Nullable(UInt16)          COMMENT 'Flags for xrsa2_flux.; NULL where the file holds _FillValue 65535US',
    xrsb1_flag                    Nullable(UInt16)          COMMENT 'Flags for xrsb1_flux.; NULL where the file holds _FillValue 65535US',
    xrsb2_flag                    Nullable(UInt16)          COMMENT 'Flags for xrsb2_flux.; NULL where the file holds _FillValue 65535US',
    xrsa1_num                     Nullable(UInt8)           COMMENT 'Number of averaged measurements in xrsa1_flux.; NULL where the file holds _FillValue 255UB',
    xrsa2_num                     Nullable(UInt8)           COMMENT 'Number of averaged measurements in xrsa2_flux.; NULL where the file holds _FillValue 255UB',
    xrsb1_num                     Nullable(UInt8)           COMMENT 'Number of averaged measurements in xrsb1_flux.; NULL where the file holds _FillValue 255UB',
    xrsb2_num                     Nullable(UInt8)           COMMENT 'Number of averaged measurements in xrsb2_flux.; NULL where the file holds _FillValue 255UB',
    xrsa1_flag_excluded           Nullable(UInt16)          COMMENT 'Flags on data excluded from xrsa1_flux average.; NULL where the file holds _FillValue 65535US',
    xrsa2_flag_excluded           Nullable(UInt16)          COMMENT 'Flags on data excluded from xrsa2_flux average.; NULL where the file holds _FillValue 65535US',
    xrsb1_flag_excluded           Nullable(UInt16)          COMMENT 'Flags on data excluded from xrsb1_flux average.; NULL where the file holds _FillValue 65535US',
    xrsb2_flag_excluded           Nullable(UInt16)          COMMENT 'Flags on data excluded from xrsb2_flux average.; NULL where the file holds _FillValue 65535US',
    yaw_flip_flag                 Nullable(UInt8)           COMMENT 'Yaw flip flag, indicating if spacecraft is inverted; NULL where the file holds _FillValue 255UB',
    electron_correction_flag      Nullable(UInt16)          COMMENT 'Flags for electron contamination correction; NULL where the file holds _FillValue 65535US',
    file_path                     String                    COMMENT 'Relative to the solar data dir: goes-xrs/<sat>/YYYY/MM/<file>.nc',
    record_no                     UInt32                    COMMENT 'Record index within the file, 0-based',
    ingested_at                   DateTime DEFAULT now()
) ENGINE = MergeTree()
PARTITION BY toYear(ifNull(observed_at, toDateTime64(0, 3, 'UTC')))
ORDER BY (file_path, record_no)
COMMENT 'GOES XRS 1-minute averages, NOAA NCEI archive, all satellites. Every record of every file; missing as NULL; flags as sent.';
