Name:           ionis-core
Version:        3.2.0
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
Includes 32 ClickHouse DDL schemas optimized for 10+ billion rows of
propagation data across WSPR, RBN, contest, PSK Reporter, solar, and
validation databases.

%prep
%autosetup -n %{name}-%{version}

%build
# Nothing to build - noarch package

%install
# Create directories
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

# Install static data files
install -m 644 data/*.tsv %{buildroot}%{_datadir}/%{name}/data/

%post
echo "------------------------------------------------------------"
echo " IONIS Core v%{version} installed successfully."
echo " To finalize the database schema and version stamp, run:"
echo "   ionis-db-init --stamp-version"
echo "------------------------------------------------------------"

%files
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
%{_datadir}/%{name}/data/*.tsv

%changelog
* Thu Feb 19 2026 Greg Beam <ki7mt@yahoo.com> - 3.0.6-1
- Add 3 ingest_log watermark DDL files (rbn, wspr, contest)
- Standardize incremental ingest tracking across all data sources
- DDL schemas: 29 → 32

* Mon Feb 17 2026 Greg Beam <ki7mt@yahoo.com> - 3.0.5-1
- Add Debian packaging for Launchpad PPA (debian/ directory)
- Fix day-of-week in debian/changelog

* Mon Feb 17 2026 Greg Beam <ki7mt@yahoo.com> - 3.0.4-1
- Fix README: DDL count (29), script count (12), add DDL #29

* Sat Feb 14 2026 Greg Beam <ki7mt@yahoo.com> - 3.0.3-1
- Add dxpedition population scripts (catalog + paths/signatures)
- Add static data file: data/dxpedition-catalog.tsv (332 GDXF entries)
- Install data/ directory to /usr/share/ionis-core/data/
- Population scripts: 10 → 12

* Thu Feb 13 2026 Greg Beam <ki7mt@yahoo.com> - 3.0.2-1
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
