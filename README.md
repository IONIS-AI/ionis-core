# ionis-core

**Core ClickHouse schemas and environment setup for the IONIS propagation analysis system**

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![COPR](https://img.shields.io/badge/COPR-ki7mt%2Fionis--ai-blue)](https://copr.fedorainfracloud.org/coprs/ki7mt/ionis-ai/)
[![Platform: EL9](https://img.shields.io/badge/Platform-EL9-green.svg)](https://rockylinux.org/)

## Package Contents

This package installs:

```text
File                Path                            Description
ionis-db-init      /usr/bin/                        Database initialization script
ionis-env          /usr/bin/                        Environment variables setup
*.sql (32 files)   /usr/share/ionis-core/ddl/       ClickHouse DDL schemas
*.sh (12 files)    /usr/share/ionis-core/scripts/   Population scripts
```

### Database Schemas

```text
DDL                               Creates
-----------------------------------------
01-wspr_schema_v2.sql             wspr: bronze, v_schema_contract, v_data_integrity; (function): fn_wspr_validate_schema_v2, fn_wspr_expected_struct_size
02-solar_indices.sql              solar: bronze
03-solar_silver.sql               solar: v_daily_indices
04-data_mgmt.sql                  data_mgmt: config
05-geo_functions.sql              geo: v_grid_validation_example
06-lab_versions.sql               data_mgmt: lab_versions, v_lab_versions_latest
07-callsign_grid.sql              wspr: callsign_grid
10-rbn_schema_v1.sql              rbn: bronze
11-contest_schema_v1.sql          contest: bronze
12-signatures_v1.sql              wspr: signatures_v1
13-training_stratified.sql        wspr: gold_stratified
14-training_continuous.sql        wspr: gold_continuous
15-training_v6_clean.sql          wspr: gold_v6
16-validation_step_i.sql          validation: step_i_paths, step_i_voacap
17-rbn_ingest_log.sql             rbn: ingest_log
18-validation_quality_test.sql    validation: quality_test_paths, quality_test_voacap
19-dxpedition_synthesis.sql       dxpedition: catalog; rbn: dxpedition_paths
20-signatures_v2_terrestrial.sql  wspr: signatures_v2_terrestrial
21-balloon_callsigns_v2.sql       wspr: balloon_callsigns_v2
22-pskr_schema_v1.sql             pskr: bronze
23-contest_signatures.sql         contest: signatures
24-rbn_signatures.sql             rbn: signatures
25-live_conditions.sql            wspr: live_conditions
26-validation_model_results.sql   validation: model_results
27-mode_thresholds.sql            validation: mode_thresholds
28-pskr_ingest_log.sql            pskr: ingest_log
29-rbn_dxpedition_signatures.sql  rbn: dxpedition_signatures
30-wspr_ingest_log.sql            wspr: ingest_log
31-contest_ingest_log.sql         contest: ingest_log
32-training_runs.sql              training: runs, epochs
33-solar_dscovr.sql               solar: dscovr
34-solar_iri_lookup.sql           solar: iri_lookup
35-dxpedition_contest_paths.sql   validation: dxpedition_contest_paths
36-pskr_signatures.sql            pskr: signatures
37-contest_quarantine.sql         contest: quarantine
38-wspr_bronze_uniform.sql        wspr: bronze_uniform
39-validation_sfi_audit.sql       validation: sfi_audit_runs, tst900_results
40-contest_log_metadata.sql       contest: log_metadata
```

**Every table, what writes it, what reads it, and how it is derived:
[docs/DATA-DICTIONARY.md](docs/DATA-DICTIONARY.md).** That file is authoritative; if another
document disagrees with it, that document is wrong.

The table above is generated from `src/*.sql`, and `scripts/verify_schema_complete.sh` checks it
against the live database in both directions — a table with no DDL here, or DDL here with no
table. Run it after any schema change. **Everything in `src/` is applied**: the `Makefile` and
`ionis-core.spec` both glob `src/*.sql`, so deleting a table without deleting its DDL means the
next apply brings it straight back.

## Installation

### From COPR (Recommended)

```bash
# Enable the repository
sudo dnf copr enable ki7mt/ionis-ai

# Install
sudo dnf install ionis-core
```

### From Source

```bash
git clone https://github.com/IONIS-AI/ionis-core.git
cd ionis-core
make build
sudo make install
```

## Usage

### 1. Start ClickHouse

```bash
sudo dnf install -y clickhouse-server clickhouse-client
sudo systemctl enable --now clickhouse-server
clickhouse-client --query="SELECT version()"
```

### 2. Initialize the Database

```bash
ionis-db-init
```

**Options:**
```
--dry-run        Show what would be done without executing
--force          Drop and recreate tables (DESTROYS DATA)
--auto-confirm   Skip confirmation prompts (for automation)
--stamp-version  Record installed version in data_mgmt.lab_versions
```

### 3. Load Environment Variables

```bash
source /usr/bin/ionis-env
```

**Variables exported:**
```
CLICKHOUSE_HOST=localhost
CLICKHOUSE_PORT=9000
CLICKHOUSE_DB=wspr
DDL_PATH=/usr/share/ionis-core/ddl
```

## Upgrading from ki7mt-ai-lab-core

The `ionis-core` package includes `Obsoletes: ki7mt-ai-lab-core < 3.0.0`, so a standard `dnf upgrade` will seamlessly replace the old package. Scripts are renamed:

- `ki7mt-lab-db-init` -> `ionis-db-init`
- `ki7mt-lab-env` -> `ionis-env`

## Testing

```bash
make build    # Process templates
make test     # Run 7 verification tests
```

---

## License

GPL-3.0-or-later - See [COPYING](COPYING)

## Author

Greg Beam, KI7MT

## Links

- **GitHub:** https://github.com/IONIS-AI/ionis-core
- **COPR:** https://copr.fedorainfracloud.org/coprs/ki7mt/ionis-ai/
- **Issues:** https://github.com/IONIS-AI/ionis-core/issues
