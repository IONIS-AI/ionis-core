#!/usr/bin/env python3
# ==============================================================================
# populate_iri_lookup.py — Pre-Compute IRI-2020 Ionospheric Parameters
# ==============================================================================
#
# Populates solar.iri_lookup with foF2, hmF2, and foE for every unique 4-char
# Maidenhead grid in the training pool, across 24 UTC hours, 12 months, and
# 18 SFI buckets (70-240, step 10).
#
# This is a one-time pre-compute step for V23 feature engineering. The lookup
# table lets training scripts inject path-specific ionospheric geometry (foF2,
# hmF2, foE) without calling PyIRI in the training loop.
#
# Prerequisites:
#   - Python 3.10+ with PyIRI, numpy, clickhouse-connect
#   - ClickHouse accessible at CH_HOST (default: localhost)
#   - DDL 34-solar_iri_lookup.sql applied
#   - Signature tables populated (wspr, rbn, contest)
#
# Estimated runtime: ~2 hours on 32 cores (31K grids)
#
# Usage:
#   python3 populate_iri_lookup.py
#   python3 populate_iri_lookup.py --workers 16
#   CH_HOST=10.60.1.1 python3 populate_iri_lookup.py
#
# ==============================================================================

import os
import sys
import time
import argparse
import multiprocessing as mp
from functools import partial

import numpy as np

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

SFI_BUCKETS = list(range(70, 241, 10))   # 70, 80, ..., 240 (18 buckets, default)
HOURS = list(range(24))                  # 0-23
MONTHS = list(range(1, 13))              # 1-12

# Day-of-year for the 15th of each month (representative day for IRI monthly
# coefficients). Non-leap year; IRI's monthly resolution makes this exact.
MONTH_TO_DOY = {
    1: 15, 2: 46, 3: 74, 4: 105, 5: 135, 6: 166,
    7: 196, 8: 227, 9: 258, 10: 288, 11: 319, 12: 349,
}

# Representative year for IRI coefficients (recent, non-leap)
IRI_YEAR = 2025

# Batch size for ClickHouse inserts
INSERT_BATCH_SIZE = 50_000


def grid4_to_latlon(grid: str) -> tuple[float, float]:
    """Convert a 4-char Maidenhead grid to (lat, lon) at grid centroid."""
    grid = grid.upper().strip('\x00')
    if len(grid) < 4:
        return (0.0, 0.0)

    lon = (ord(grid[0]) - ord('A')) * 20 - 180 + int(grid[2]) * 2 + 1.0
    lat = (ord(grid[1]) - ord('A')) * 10 - 90 + int(grid[3]) * 1 + 0.5
    return (lat, lon)


def compute_grid_iri(grid: str) -> list[tuple]:
    """Compute IRI parameters for one grid across all hours, months, SFI buckets.

    Returns a list of (grid_4, hour, month, sfi_bucket, foF2, hmF2, foE) tuples.
    """
    # Import inside worker to avoid pickling issues with multiprocessing
    import PyIRI
    from PyIRI import main_library as gml

    lat, lon = grid4_to_latlon(grid)

    # PyIRI expects longitude in 0-360 (degrees East)
    lon_iri = lon % 360.0

    results = []
    coeff_dir = PyIRI.coeff_dir

    for month in MONTHS:
        doy = MONTH_TO_DOY[month]
        # Day of month for PyIRI (use 15th)
        day = 15

        for sfi in SFI_BUCKETS:
            try:
                # Vectorize over 24 hours in one call
                F2, F1, E, Es, sun, mag, EDP = gml.IRI_density_1day(
                    year=IRI_YEAR,
                    mth=month,
                    day=day,
                    aUT=np.arange(24, dtype=float),
                    alon=np.array([lon_iri]),
                    alat=np.array([lat]),
                    aalt=np.array([300.0]),
                    F107=float(sfi),
                    coeff_dir=coeff_dir,
                )

                for hour in HOURS:
                    foF2 = float(F2['fo'][hour, 0])
                    hmF2 = float(F2['hm'][hour, 0])
                    foE = float(E['fo'][hour, 0])

                    # Sanity clamp: foF2 and foE should be non-negative
                    foF2 = max(foF2, 0.0)
                    hmF2 = max(hmF2, 100.0)  # hmF2 always > 100 km
                    foE = max(foE, 0.0)

                    results.append((grid, hour, month, sfi, foF2, hmF2, foE))

            except Exception as e:
                # On failure, write defaults (foF2=5, hmF2=300, foE=3)
                for hour in HOURS:
                    results.append((grid, hour, month, sfi, 5.0, 300.0, 3.0))
                print(f"  WARN: IRI failed for {grid} month={month} sfi={sfi}: {e}",
                      file=sys.stderr)

    return results


def worker_init():
    """Worker initializer — import PyIRI once per process."""
    import PyIRI  # noqa: F401


def get_unique_grids(client) -> list[str]:
    """Query ClickHouse for all unique 4-char grids across signature tables."""
    query = """
    SELECT DISTINCT grid FROM (
        SELECT tx_grid_4 AS grid FROM wspr.signatures_v2_terrestrial
        UNION ALL
        SELECT rx_grid_4 AS grid FROM wspr.signatures_v2_terrestrial
        UNION ALL
        SELECT tx_grid_4 AS grid FROM rbn.signatures
        UNION ALL
        SELECT rx_grid_4 AS grid FROM rbn.signatures
        UNION ALL
        SELECT tx_grid_4 AS grid FROM contest.signatures
        UNION ALL
        SELECT rx_grid_4 AS grid FROM contest.signatures
    ) ORDER BY grid
    """
    result = client.query(query)
    grids = []
    for row in result.result_rows:
        g = row[0].strip('\x00') if isinstance(row[0], str) else row[0].decode().strip('\x00')
        # Validate: must be 2 letters + 2 digits
        if len(g) == 4 and g[0].isalpha() and g[1].isalpha() and g[2].isdigit() and g[3].isdigit():
            grids.append(g)
    return grids


def insert_batch(client, rows: list[tuple]):
    """Insert a batch of rows into solar.iri_lookup."""
    if not rows:
        return
    client.insert(
        'solar.iri_lookup',
        rows,
        column_names=['grid_4', 'hour', 'month', 'sfi_bucket', 'foF2', 'hmF2', 'foE'],
    )


def main():
    parser = argparse.ArgumentParser(
        description='Pre-compute IRI-2020 ionospheric parameters for training lookup')
    parser.add_argument('--workers', type=int, default=32,
                        help='Number of parallel workers (default: 32)')
    parser.add_argument('--host', type=str,
                        default=os.environ.get('CH_HOST', 'localhost'),
                        help='ClickHouse host (default: $CH_HOST or localhost)')
    parser.add_argument('--port', type=int,
                        default=int(os.environ.get('CH_PORT', '8123')),
                        help='ClickHouse HTTP port (default: $CH_PORT or 8123)')
    parser.add_argument('--sfi-step', type=int, default=10,
                        help='SFI bucket step size (default: 10, use 5 for 35-bucket atlas)')
    parser.add_argument('--sfi-values', type=str, default=None,
                        help='Explicit comma-separated SFI bucket values (overrides --sfi-step)')
    parser.add_argument('--truncate', action='store_true',
                        help='TRUNCATE table before populating')
    args = parser.parse_args()

    # Override global SFI_BUCKETS before forking workers
    global SFI_BUCKETS
    if args.sfi_values:
        SFI_BUCKETS = [int(x) for x in args.sfi_values.split(',')]
    else:
        SFI_BUCKETS = list(range(70, 241, args.sfi_step))

    import clickhouse_connect
    client = clickhouse_connect.get_client(host=args.host, port=args.port)

    # Verify table exists
    try:
        count = client.query("SELECT count() FROM solar.iri_lookup").result_rows[0][0]
        print(f"solar.iri_lookup exists, current rows: {count:,}")
    except Exception as e:
        print(f"ERROR: solar.iri_lookup not found. Apply DDL first: {e}", file=sys.stderr)
        sys.exit(1)

    if args.truncate:
        print("TRUNCATE TABLE solar.iri_lookup")
        client.command("TRUNCATE TABLE solar.iri_lookup")

    # Get unique grids
    print("Querying unique grids from signature tables...")
    grids = get_unique_grids(client)
    print(f"Found {len(grids):,} unique 4-char grids")

    if not grids:
        print("ERROR: No grids found. Are signature tables populated?", file=sys.stderr)
        sys.exit(1)

    # Compute expected row count
    expected = len(grids) * 24 * 12 * len(SFI_BUCKETS)
    print(f"Expected rows: {expected:,} ({len(grids)} grids x 24h x 12mo x {len(SFI_BUCKETS)} SFI)")
    print(f"Workers: {args.workers}")
    print()

    # Process grids in parallel
    t_start = time.time()
    completed = 0
    total_rows = 0
    insert_buffer = []

    with mp.Pool(processes=args.workers, initializer=worker_init) as pool:
        for result in pool.imap_unordered(compute_grid_iri, grids, chunksize=4):
            insert_buffer.extend(result)
            completed += 1
            total_rows += len(result)

            # Batch insert when buffer is large enough
            if len(insert_buffer) >= INSERT_BATCH_SIZE:
                insert_batch(client, insert_buffer)
                insert_buffer = []

            # Progress report every 500 grids
            if completed % 500 == 0:
                elapsed = time.time() - t_start
                rate = completed / elapsed
                eta = (len(grids) - completed) / rate if rate > 0 else 0
                print(f"  [{completed:,}/{len(grids):,}] "
                      f"{total_rows:,} rows, "
                      f"{rate:.1f} grids/s, "
                      f"ETA {eta/60:.1f} min")

    # Flush remaining buffer
    if insert_buffer:
        insert_batch(client, insert_buffer)

    elapsed = time.time() - t_start

    # Final count
    final_count = client.query("SELECT count() FROM solar.iri_lookup").result_rows[0][0]

    print()
    print(f"Done in {elapsed/60:.1f} minutes")
    print(f"Rows inserted: {total_rows:,}")
    print(f"Table count:   {final_count:,}")
    print()

    # Spot-check: JN48 (central Europe), noon July, SFI=150
    check = client.query(
        "SELECT foF2, hmF2, foE FROM solar.iri_lookup "
        "WHERE grid_4 = 'JN48' AND hour = 12 AND month = 7 AND sfi_bucket = 150"
    ).result_rows
    if check:
        print(f"Spot-check JN48 Jul noon SFI=150: "
              f"foF2={check[0][0]:.2f} MHz, hmF2={check[0][1]:.0f} km, foE={check[0][2]:.2f} MHz")
    else:
        print("WARN: JN48 not found in lookup (grid may not be in signature tables)")


if __name__ == '__main__':
    main()
