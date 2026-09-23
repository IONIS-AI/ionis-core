Name:           ionis-core
Version:        4.0.7
Release:        1%{?dist}
Summary:        Core database schemas for the IONIS propagation analysis system

License:        GPL-3.0-or-later
URL:            https://github.com/IONIS-AI/ionis-core
# Hardcoded Source avoids rpkg naming conflicts
Source0:        https://github.com/IONIS-AI/ionis-core/archive/v%{version}.tar.gz

BuildArch:      noarch

Obsoletes:      ki7mt-ai-lab-core < 3.0.0
Provides:       ki7mt-ai-lab-core = %{version}-%{release}

Requires:       clickhouse-server >= 23.0
Requires:       clickhouse-client >= 23.0

%description
Core database schemas and initialization scripts for the IONIS
(Ionospheric Neural Inference System) propagation analysis project.
Includes 36 ClickHouse DDL schemas optimized for 10+ billion rows of
propagation data across WSPR, RBN, contest, PSK Reporter, solar,
training, and validation databases.

%prep
%autosetup -n %{name}-%{version}

%build
# Nothing to build - noarch package

%install
# Create directories
# Site configuration, sourced by ionis-env. %config(noreplace) and shipped with no
# assignments: absent or untouched, the built-in defaults apply.
install -d -m 0755 %{buildroot}%{_sysconfdir}/%{name}
install -p -m 0644 config/ionis-core.conf %{buildroot}%{_sysconfdir}/%{name}/ionis-core.conf

install -d %{buildroot}%{_bindir}
install -d %{buildroot}%{_datadir}/%{name}/ddl
install -d %{buildroot}%{_datadir}/%{name}/scripts
install -d %{buildroot}%{_datadir}/%{name}/data

# Install and process scripts (substitute @PROGRAM@ and @VERSION@)
for script in ionis-db-init ionis-env; do
    sed -e 's|@PROGRAM@|%{name}|g' \
        -e 's|@VERSION@|%{version}|g' \
        src/${script} > %{buildroot}%{_bindir}/${script}
    chmod 755 %{buildroot}%{_bindir}/${script}
done

# Install and process DDL files
for sql in src/*.sql; do
    basename=$(basename "$sql")
    sed -e 's|@PROGRAM@|%{name}|g' \
        -e 's|@VERSION@|%{version}|g' \
        -e 's|@COPYRIGHT@|GPL-3.0-or-later|g' \
        "$sql" > %{buildroot}%{_datadir}/%{name}/ddl/${basename}
done

# Install population scripts
for sh in scripts/populate_*.sh; do
    install -m 755 "$sh" %{buildroot}%{_datadir}/%{name}/scripts/
done
for py in scripts/populate_*.py; do
    install -m 755 "$py" %{buildroot}%{_datadir}/%{name}/scripts/
done

# Install the audits. These were repo-only, which made them unrunnable on any host
# that installs the package rather than checking out the repo -- and an audit that
# gates a tag or a release has to exist where the gate runs, not where it was written.
for sh in scripts/verify_*.sh; do
    install -m 755 "$sh" %{buildroot}%{_datadir}/%{name}/scripts/
done

# Install static data files
install -m 644 data/*.tsv %{buildroot}%{_datadir}/%{name}/data/

%post
echo "------------------------------------------------------------"
echo " IONIS Core v%{version} installed successfully."
echo " To finalize the database schema and version stamp, run:"
echo "   ionis-db-init --stamp-version"
echo "------------------------------------------------------------"

%files
%dir %{_sysconfdir}/%{name}
%config(noreplace) %{_sysconfdir}/%{name}/ionis-core.conf
%license COPYING
%doc README.md
%{_bindir}/ionis-db-init
%{_bindir}/ionis-env
%dir %{_datadir}/%{name}
%dir %{_datadir}/%{name}/ddl
%dir %{_datadir}/%{name}/scripts
%dir %{_datadir}/%{name}/data
%{_datadir}/%{name}/ddl/*.sql
%{_datadir}/%{name}/scripts/*.sh
%{_datadir}/%{name}/scripts/*.py
%{_datadir}/%{name}/data/*.tsv

%changelog
* Wed Sep 23 2026 Bob <bob@ipa.home.arpa> - 4.0.7-1
- Fix the 4.0.6 changelog: it wrote %%install unescaped at the start of a line, so
  rpm read it as a second %%install section and the spec stopped parsing --
  "error: line 105: second %%install". v4.0.6 was tagged and could not be built.
  A changelog is prose to a human and spec syntax to rpm; a leading %% is the latter.

* Wed Sep 23 2026 Bob <bob@ipa.home.arpa> - 4.0.6-1
- Package the audits. verify_schema_complete.sh, verify_contest_ingest.sh and
  verify_dictionary_complete.sh were installed by nothing -- the %%install loops
  matched only populate_*, so the scripts existed in a git checkout and nowhere
  else. An audit that gates a tag has to be on the host where the gate runs.
- contest.parse_rejects + ingest_log.skipped_rows (from 4.0.5) and the two new
  audits are the controls for the contest rebuild.
- verify_contest_ingest.sh counted archive records with ^QSO:, which misses logs that
  indent them -- 239,685 lines corpus-wide, 237,226 of them in cq-wpx. A reconciliation
  that undercounts the archive reports a series as balanced when it is not, which is the
  one failure mode a gate must not have. Archive total was 387,652,077; it is 387,891,762.

* Tue Sep 22 2026 Bob <bob@ipa.home.arpa> - 4.0.5-1
- contest.parse_rejects: new table holding every QSO line the parser could not
  read -- file, line number, category, full parser error and the raw line. A skip
  was previously a counter printed to stdout and nothing else, which is how three
  parser defects stayed hidden. reason is a bounded category and detail carries
  the offending value, so the LowCardinality column stays low-cardinality.
- contest.v_parse_rejects_by_reason: the review query. A reason spread thinly is
  bad source data; one concentrated in a contest is a parser assumption that does
  not hold there.
- contest.ingest_log gains skipped_rows: the DURABLE per-file count, never capped,
  where parse_rejects samples at 100 lines per file.

* Tue Sep 22 2026 Bob <bob@ipa.home.arpa> - 4.0.4-1
- REQUIRED alongside ionis-apps 4.2.0. solar.bronze is superseded by four
  per-source tables; the 4.0.3 populate scripts still reference it and will FAIL
  against the live schema until this lands.
- NEW solar.{kp,sfi,ssn,xray}_bronze (DDL 42-45): one table per source, no merge.
  The old table combined three NOAA streams with max() over whatever had staged, so
  a stream that failed to download became 0 and the INSERT still succeeded -- with
  kp_index a non-nullable Float32, a missing Kp and a quiet Kp=0 were the same
  value, and four months of 2026 hold SFI on every row and Kp on none.
- NEW solar.silver (DDL 46): the conformed 3-hour grid. Every signature build
  carried its own copy of the same two-line bucket join against solar.bronze --
  eight scripts, one expression, eight places to change it. Three more carried an
  aggregating subquery that existed only because solar.bronze was not on a 3-hour
  grid. The rule now lives in populate_solar_silver.sh alone.
- Nine build scripts repointed onto solar.silver; the subqueries are gone rather
  than rewritten. Verified live: CQ-WW-CW 2024, 5,408,056 rows, 100% joined to Kp.
- Every solar.silver column is Nullable on purpose. join_use_nulls=1 in the
  populate is load-bearing, not tuning: without it ClickHouse LEFT JOIN fills
  unmatched rows with the column DEFAULT, and the first build reported SFI present
  on all 276,784 rows when Penticton starts in 2004.
- DateTime64 and Date32 where the archives predate 1970. DateTime stops at 2106 and
  wrapped GFZ's 1932-1969 into the future; Date stops at 2149 and wrapped SIDC's
  1818-1969, losing 10,674 rows silently.
- All new tables partition by DECADE. Yearly makes ~100-200 tiny parts on tables of
  a few hundred thousand rows, and a 209-year series exceeds
  max_partitions_per_insert_block at yearly grain.

* Mon Sep 22 2026 Bob <bob@ipa.home.arpa> - 4.0.3-1
- Host-neutrality, the fleet-zfs-backup pattern (KI7MT/fleet-ops#183) applied here.
  Sixteen populate scripts each carried CH_HOST="${CH_HOST:-192.168.1.90}" and
  populate_stratified.sh carried CH_HOST="192.168.1.90" with no override at all --
  one host's address shipped seventeen times in a package published on COPR, and
  seventeen files to edit to change it
- Scripts now source /usr/bin/ionis-env, which was already shipped for this and
  which nothing used. It exported CLICKHOUSE_HOST while every script read CH_HOST,
  so the two mechanisms never met; ionis-env now sets both
- NEW %config(noreplace) /etc/ionis-core/ionis-core.conf, shipped with no
  assignments: absent or untouched, behaviour is what it was
- Precedence is explicit environment, then conf, then default. zfs-backup lets its
  conf win outright, which is right there and wrong here: every script's header
  documents `CH_HOST=10.60.1.1 bash populate_*.sh`, and a plain assignment in the
  conf would silently beat it
- Defaults leave /mnt/ai-stack (Judge: that dataset is AI stack ops): WSPR_DATA_DIR
  /mnt/wspr-data, SOLAR_DATA_DIR /mnt/solar-data, CLICKHOUSE_DATA_DIR
  /var/lib/clickhouse -- which is where ClickHouse actually is on this host
- populate_training_runs.sh's fallback named /mnt/ai-stack/ionis-ai/... , a
  workspace root that stopped existing when the repos moved. Dead for months while
  looking like a working alternative; now $IONIS_TRAINING_DIR
- derive_dxpedition_windows.py had http://192.168.1.90:8123/ hardcoded with no
  override; export_iri_lookup_npz.py defaulted its output to the same dead path

* Wed Sep 09 2026 Greg Beam <ki7mt@yahoo.com> - 4.0.2-1
- 25-live_conditions.sql: wspr.live_conditions changes from ENGINE = Memory to a durable
  append-only MergeTree (ORDER BY updated_at, TTL 2 years). Memory meant the table was lost
  on every ClickHouse restart, and it did not come back stale -- it came back EMPTY, which
  ionis-hamstats turned into an invented SFI 100 / Kp 3 for the IONIS model and published as
  current conditions. Durability is what closes that window.
- 25-live_conditions.sql: adds sfi_observed_at, kp_observed_at and updated_at. The writer has
  emitted these since ionis-apps 4.0.6; the DDL had drifted behind it.
- NOTE: this DDL alone does NOT convert an existing host. Every statement here is
  CREATE TABLE IF NOT EXISTS, which cannot change the engine of a table that already exists,
  so ionis-db-init is a no-op against a live Memory table. The conversion is performed by
  solar-live-update (ionis-apps >= 4.0.7), which probes system.tables and recreates the table
  when it finds any engine other than MergeTree. This file is the schema of record and what a
  fresh install gets.
- Readers must now ORDER BY updated_at DESC LIMIT 1; a bare LIMIT 1 was unambiguous against a
  single-row Memory table and returns an arbitrary row against history. ionis-hamstats and
  ionis-docs are updated.
* Wed Feb 25 2026 Greg Beam <ki7mt@yahoo.com> - 4.0.1-1
- Documentation update only (no schema changes)

* Wed Feb 25 2026 Greg Beam <ki7mt@yahoo.com> - 4.0.0-2
- Remove Debian packaging (Launchpad cannot build the full stack)

* Wed Feb 25 2026 Greg Beam <ki7mt@yahoo.com> - 4.0.0-1
- Align version across all IONIS packages at 4.0.0 (Phase 4.0 release)

* Tue Feb 24 2026 Greg Beam <ki7mt@yahoo.com> - 3.0.10-1
- Add validation.dxpedition_contest_paths DDL: DXpedition-contest path observations
- Add populate_dxpedition_contest_paths.sh: 81.5K observations to 49 DXCC entities
- DDL schemas: 35 → 36, population scripts: 14 → 15

* Sun Feb 22 2026 Greg Beam <ki7mt@yahoo.com> - 3.0.9-1
- Add solar.iri_lookup DDL: IRI-2020 ionospheric parameter lookup table
- Add populate_iri_lookup.py: pre-compute foF2, hmF2, foE for V23 features
- DDL schemas: 34 → 35, population scripts: 13 → 14

* Sat Feb 21 2026 Greg Beam <ki7mt@yahoo.com> - 3.0.8-1
- Add solar.dscovr DDL: DSCOVR L1 solar wind data (Bz, Bt, speed, density, temp)
- DDL schemas: 33 → 34

* Sat Feb 21 2026 Greg Beam <ki7mt@yahoo.com> - 3.0.7-1
- Add training.runs and training.epochs DDL (training run audit trail)
- Add populate_training_runs.sh backfill script (V20, V21-alpha, V21-beta)
- DDL schemas: 32 → 33, population scripts: 12 → 13

* Thu Feb 19 2026 Greg Beam <ki7mt@yahoo.com> - 3.0.6-1
- Add 3 ingest_log watermark DDL files (rbn, wspr, contest)
- Standardize incremental ingest tracking across all data sources
- DDL schemas: 29 → 32

* Tue Feb 17 2026 Greg Beam <ki7mt@yahoo.com> - 3.0.5-1
- Add Debian packaging for Launchpad PPA (debian/ directory)
- Fix day-of-week in debian/changelog

* Tue Feb 17 2026 Greg Beam <ki7mt@yahoo.com> - 3.0.4-1
- Fix README: DDL count (29), script count (12), add DDL #29

* Sat Feb 14 2026 Greg Beam <ki7mt@yahoo.com> - 3.0.3-1
- Add dxpedition population scripts (catalog + paths/signatures)
- Add static data file: data/dxpedition-catalog.tsv (332 GDXF entries)
- Install data/ directory to /usr/share/ionis-core/data/
- Population scripts: 10 → 12

* Fri Feb 13 2026 Greg Beam <ki7mt@yahoo.com> - 3.0.2-1
- Fix populate_callsign_grid.sh: add PSKR sender/receiver enrichment
- Fix populate_balloon_callsigns.sh: add join_use_nulls=1 for type2 detection
- Fix populate_quality_test_paths.sh: toUInt8 → reinterpretAsUInt8
- Fix DDL path resolution in rbn/contest scripts (../ddl/ for RPM, ../src/ for git)
- Strip stale V16/V17/Step version labels from all population scripts
- Fix ionis-db-init: solar.bronze expected columns 10 → 11

* Fri Feb 13 2026 Greg Beam <ki7mt@yahoo.com> - 3.0.1-1
- Add DDL for rbn.dxpedition_signatures (29th schema, closes audit gap)
- Update description: 29 DDL schemas (was 28)

* Fri Feb 13 2026 Greg Beam <ki7mt@yahoo.com> - 3.0.0-1
- Migrate to IONIS-AI organization (ionis-core)
- Rename package: ki7mt-ai-lab-core → ionis-core
- Rename scripts: ki7mt-lab-db-init → ionis-db-init, ki7mt-lab-env → ionis-env
- Add Obsoletes/Provides for seamless upgrade from ki7mt-ai-lab-core

* Wed Feb 11 2026 Greg Beam <ki7mt@yahoo.com> - 2.4.0-1
- V20 production release
- Add DDL files 16-28: validation, balloon, dxpedition, signatures v2,
  pskr schema, contest/rbn signatures, live conditions, model results,
  mode thresholds, pskr ingest log
- Update description: 28 DDL schemas (was 15)

* Sun Feb 08 2026 Greg Beam <ki7mt@yahoo.com> - 2.3.1-1
- Medallion architecture: rename spots_raw->bronze, model_features->silver, training->gold
- Update README with 15 DDL schemas, convert tables to code blocks for COPR

* Sat Feb 07 2026 Greg Beam <ki7mt@yahoo.com> - 2.3.0-1
- DDL audit: renumber all DDL files to sequential 01-15 (resolve 04/05 conflicts)
- Add DDL for wspr.silver (08) and v_quality_distribution MV (09)
- Add populate_signatures.sh and populate_v6_clean.sh population scripts
- Drop wspr.training_set_v1 (empty, obsolete V1 dev iteration)
- Every ClickHouse table now has a corresponding DDL file
- Align version across all lab packages at 2.3.0

* Wed Feb 04 2026 Greg Beam <ki7mt@yahoo.com> - 2.2.0-1
- Align version across all lab packages at 2.2.0 for Phase 4.1

* Tue Feb 03 2026 Greg Beam <ki7mt@yahoo.com> - 2.1.0-1
- Align version across all lab packages at 2.1.0

* Mon Jan 20 2025 Greg Beam <ki7mt@yahoo.com> - 2.0.3-1
- Sync version across all lab packages
- Fix maintainer email in changelog

* Sat Jan 18 2025 Greg Beam <ki7mt@yahoo.com> - 2.0.0-1
- Major version bump to align with ki7mt-ai-lab-apps v2.0.0

* Fri Jan 17 2025 Greg Beam <ki7mt@yahoo.com> - 1.1.7-1
- Add 01-wspr_schema_v2.sql: 17-column schema synchronized with CUDA wspr_structs.h
- Use FixedString(N) for direct GPU memory mapping
- Add mode and column_count columns
- Change band to Int32 to match live database
- Add migration ALTER statements for v1 to v2 upgrade
- Add schema validation function wspr.fn_validate_schema_v2()

* Fri Jan 17 2025 Greg Beam <ki7mt@yahoo.com> - 1.1.6-1
- Add spec changelog for v1.1.5 and v1.1.6

* Fri Jan 17 2025 Greg Beam <ki7mt@yahoo.com> - 1.1.5-1
- Version sync with ki7mt-ai-lab-cuda

* Thu Jan 16 2025 Greg Beam <ki7mt@yahoo.com> - 1.1.4-1
- Hardcode Source0 URL to avoid rpkg naming conflicts

* Thu Jan 16 2025 Greg Beam <ki7mt@yahoo.com> - 1.1.3-1
- Switch to GitHub archive Source0 for COPR builds
- Add --push flag to bump-version script
