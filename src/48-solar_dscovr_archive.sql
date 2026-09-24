-- 48-solar_dscovr_archive.sql — DSCOVR from NOAA's definitive archive, one bronze per product
--
-- SOURCE. NOAA NCEI publishes DSCOVR as one gzipped netCDF-3 file per day per product
-- in the bucket behind archive.data.noaa.gov/satellite-spaceweather:
--
--   DSCOVR/DSCOVR/FC/f1m/YYYY/MM/   Faraday cup plasma, 1-minute averages
--   DSCOVR/DSCOVR/MAG/m1m/YYYY/MM/  magnetometer, 1-minute averages
--
-- from 2016-07-26, about three months behind real time. dscovr-archive-download mirrors
-- the files unchanged to $IONIS_SOLAR_DATA_DIR/dscovr/{f1m,m1m}/ -- that mirror is the
-- archive source of truth -- and dscovr-archive-ingest loads them.
--
-- BRONZE GETS EVERYTHING (DATA-DICTIONARY §0). Every record of every file, every
-- variable. Nothing is filtered on quality: overall_quality and every flag are carried
-- as sent, and choosing what is good enough is silver's job.
--
--   missing  NOAA marks a missing measurement with the attribute missing_value =
--            -99999.0 (not _FillValue). It is stored as NULL. It is never 0: the old
--            solar.bronze turned missing into 0 and a gap became a measurement.
--   flags    the *_flag variables go into one Map by name. NOAA has added plasma flags
--            twice (large_flow_angle_flag by 2019; two unexpected_peak_location flags by
--            2022), so the set differs by year: an absent key means the file predates it.
--            Any NEW non-flag variable makes the ingester fail loudly instead.
--
-- NOT MERGED WITH THE LIVE FEED. solar.dscovr is the real-time RTSW feed, which carries
-- DSCOVR, ACE and IMAP together. These tables are DSCOVR only. Keeping them apart keeps
-- spacecraft from being collapsed into one minute; reconciling the two is silver's job.
--
-- A day NOAA reprocesses arrives as a new file (the _p<timestamp> part of the name
-- changes) and is ingested as well: bronze keeps both versions.

CREATE DATABASE IF NOT EXISTS solar;

CREATE TABLE IF NOT EXISTS solar.dscovr_f1m_bronze (
    observed_at         DateTime64(3, 'UTC') COMMENT 'Start of the 1-minute average (file variable time, ms since epoch)',
    sample_count        Int16              COMMENT 'Samples averaged into this minute, as the file gives it',
    proton_vx_gse       Nullable(Float32)  COMMENT 'km/s; NULL where the file holds missing_value -99999',
    proton_vy_gse       Nullable(Float32)  COMMENT 'km/s; NULL where the file holds missing_value -99999',
    proton_vz_gse       Nullable(Float32)  COMMENT 'km/s; NULL where the file holds missing_value -99999',
    proton_vx_gsm       Nullable(Float32)  COMMENT 'km/s; NULL where the file holds missing_value -99999',
    proton_vy_gsm       Nullable(Float32)  COMMENT 'km/s; NULL where the file holds missing_value -99999',
    proton_vz_gsm       Nullable(Float32)  COMMENT 'km/s; NULL where the file holds missing_value -99999',
    proton_speed        Nullable(Float32)  COMMENT 'km/s; NULL where the file holds missing_value -99999',
    proton_density      Nullable(Float32)  COMMENT 'cm^-3; NULL where the file holds missing_value -99999',
    proton_temperature  Nullable(Float32)  COMMENT 'K; NULL where the file holds missing_value -99999',
    alpha_vx_gse        Nullable(Float32)  COMMENT 'km/s; NULL where the file holds missing_value -99999',
    alpha_vy_gse        Nullable(Float32)  COMMENT 'km/s; NULL where the file holds missing_value -99999',
    alpha_vz_gse        Nullable(Float32)  COMMENT 'km/s; NULL where the file holds missing_value -99999',
    alpha_vx_gsm        Nullable(Float32)  COMMENT 'km/s; NULL where the file holds missing_value -99999',
    alpha_vy_gsm        Nullable(Float32)  COMMENT 'km/s; NULL where the file holds missing_value -99999',
    alpha_vz_gsm        Nullable(Float32)  COMMENT 'km/s; NULL where the file holds missing_value -99999',
    alpha_speed         Nullable(Float32)  COMMENT 'km/s; NULL where the file holds missing_value -99999',
    alpha_density       Nullable(Float32)  COMMENT 'cm^-3; NULL where the file holds missing_value -99999',
    alpha_temperature   Nullable(Float32)  COMMENT 'K; NULL where the file holds missing_value -99999',
    overall_quality     Int8               COMMENT 'NOAA overall sample quality: 0 normal, 1 suspect, 2 bad (as sent; not filtered)',
    flags               Map(LowCardinality(String), Int8) COMMENT 'Every *_flag variable in the file, by name. Absent key = the file predates that flag',
    file_path           String             COMMENT 'Relative to the archive mirror: dscovr/f1m/YYYY/MM/oe_f1m_dscovr_s..._pub.nc.gz',
    record_no           UInt32             COMMENT 'Record index within the file, 0-based',
    ingested_at         DateTime DEFAULT now()
) ENGINE = MergeTree()
PARTITION BY toYear(observed_at)
ORDER BY (file_path, record_no)
COMMENT 'DSCOVR Faraday cup plasma, 1-min averages, NOAA NCEI archive 2016-07-26-. Every record of every file; missing as NULL; flags as sent.';

CREATE TABLE IF NOT EXISTS solar.dscovr_m1m_bronze (
    observed_at         DateTime64(3, 'UTC') COMMENT 'Start of the 1-minute average (file variable time, ms since epoch)',
    sample_count        Int16              COMMENT 'Samples averaged into this minute, as the file gives it',
    measurement_mode    Int8               COMMENT 'Range selection mode: 0 auto, 1 manual',
    measurement_range   Int8               COMMENT 'Measurement range step (~4x sensitivity per step)',
    bt                  Nullable(Float32)  COMMENT 'nT; NULL where the file holds missing_value -99999',
    bx_gse              Nullable(Float32)  COMMENT 'nT; NULL where the file holds missing_value -99999',
    by_gse              Nullable(Float32)  COMMENT 'nT; NULL where the file holds missing_value -99999',
    bz_gse              Nullable(Float32)  COMMENT 'nT; NULL where the file holds missing_value -99999',
    theta_gse           Nullable(Float32)  COMMENT 'degrees; NULL where the file holds missing_value -99999',
    phi_gse             Nullable(Float32)  COMMENT 'degrees; NULL where the file holds missing_value -99999',
    bx_gsm              Nullable(Float32)  COMMENT 'nT; NULL where the file holds missing_value -99999',
    by_gsm              Nullable(Float32)  COMMENT 'nT; NULL where the file holds missing_value -99999',
    bz_gsm              Nullable(Float32)  COMMENT 'nT; NULL where the file holds missing_value -99999',
    theta_gsm           Nullable(Float32)  COMMENT 'degrees; NULL where the file holds missing_value -99999',
    phi_gsm             Nullable(Float32)  COMMENT 'degrees; NULL where the file holds missing_value -99999',
    overall_quality     Int8               COMMENT 'NOAA overall sample quality: 0 normal, 1 suspect, 2 bad (as sent; not filtered)',
    flags               Map(LowCardinality(String), Int8) COMMENT 'Every *_flag variable in the file, by name. Absent key = the file predates that flag',
    file_path           String             COMMENT 'Relative to the archive mirror: dscovr/m1m/YYYY/MM/oe_m1m_dscovr_s..._pub.nc.gz',
    record_no           UInt32             COMMENT 'Record index within the file, 0-based',
    ingested_at         DateTime DEFAULT now()
) ENGINE = MergeTree()
PARTITION BY toYear(observed_at)
ORDER BY (file_path, record_no)
COMMENT 'DSCOVR magnetometer, 1-min averages, NOAA NCEI archive 2016-07-26-. Every record of every file; missing as NULL; flags as sent.';

-- Watermark for the solar archive ingesters: one row per file loaded. Same shape as the
-- other *.ingest_log tables, including skipped_rows, so internal/watermark writes it.
CREATE TABLE IF NOT EXISTS solar.ingest_log (
    file_path    String                  COMMENT 'Relative to the solar data dir: dscovr/f1m/2016/07/...nc.gz',
    file_size    UInt64                  COMMENT 'File size in bytes at load time',
    row_count    UInt64                  COMMENT 'Rows loaded',
    skipped_rows UInt64 DEFAULT 0        COMMENT 'Records not loaded; 0 by design (bronze gets everything)',
    loaded_at    DateTime DEFAULT now()  COMMENT 'When loaded (UTC)',
    elapsed_ms   UInt32                  COMMENT 'Processing time ms',
    hostname     LowCardinality(String)  COMMENT 'Host that performed the load'
) ENGINE = ReplacingMergeTree(loaded_at)
ORDER BY (file_path)
SETTINGS index_granularity = 256
COMMENT 'Solar archive ingest watermark: tracks loaded archive files';
