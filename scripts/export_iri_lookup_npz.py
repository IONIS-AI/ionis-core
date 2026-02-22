#!/usr/bin/env python3
# ==============================================================================
# export_iri_lookup_npz.py — Export IRI Lookup Table as NumPy .npz
# ==============================================================================
#
# Reads solar.iri_lookup from ClickHouse and exports as a compressed NumPy
# archive (.npz) for loading on M3 during V23 training.
#
# WHY NOT A PYTHON DICT:
#   PyTorch dataloaders use multiprocessing (num_workers > 0). On macOS, Python
#   dicts trigger Copy-on-Write duplication — each worker copies the full dict.
#   A 164M-entry dict = ~15 GB × 8 workers = 120 GB → OOM on 96 GB M3 Ultra.
#   NumPy arrays are raw memory buffers that share across fork() without copying.
#
# OUTPUT FORMAT:
#   iri_lookup.npz contains:
#     - grid_index: dict mapping grid_4 string → integer index
#     - data: float32 array of shape (N_grids, 24, 12, 18, 3)
#       axes: [grid_idx, hour, month_idx(0-11), sfi_idx(0-17), (foF2,hmF2,foE)]
#     - sfi_buckets: int array [70, 80, 90, ..., 240] for reference
#     - grids: string array of all grid_4 values (for reverse lookup)
#
# LOADING ON M3:
#   npz = np.load("iri_lookup.npz", allow_pickle=True)
#   data = npz["data"]          # (N, 24, 12, 18, 3) float32
#   grid_index = npz["grid_index"].item()  # dict: grid_4 -> int
#   # lookup: data[grid_index["JN48"], 12, 6, sfi_idx, :]
#
# Usage:
#   python3 export_iri_lookup_npz.py
#   python3 export_iri_lookup_npz.py --output /path/to/iri_lookup.npz
#   CH_HOST=10.60.1.1 python3 export_iri_lookup_npz.py
#
# ==============================================================================

import os
import sys
import time
import argparse

import numpy as np


# SFI buckets — must match populate_iri_lookup.py exactly
SFI_BUCKETS = list(range(70, 250, 10))  # 70, 80, ..., 240 (18 buckets)
SFI_TO_IDX = {sfi: i for i, sfi in enumerate(SFI_BUCKETS)}


def sfi_bucket(raw_sfi):
    """Quantize raw SFI to nearest bucket center.

    THIS IS THE SHARED FUNCTION. Both 9975WX (population) and M3 (training)
    must use identical logic. Canonical home: versions/common/model.py
    """
    return int(np.clip(np.round(raw_sfi / 10) * 10, 70, 240))


def main():
    parser = argparse.ArgumentParser(
        description='Export solar.iri_lookup as NumPy .npz for M3 training')
    parser.add_argument('--output', type=str,
                        default='/mnt/ai-stack/ionis-ai/iri_lookup.npz',
                        help='Output .npz path (default: /mnt/ai-stack/ionis-ai/iri_lookup.npz)')
    parser.add_argument('--host', type=str,
                        default=os.environ.get('CH_HOST', 'localhost'),
                        help='ClickHouse host')
    parser.add_argument('--port', type=int,
                        default=int(os.environ.get('CH_PORT', '8123')),
                        help='ClickHouse HTTP port')
    args = parser.parse_args()

    import clickhouse_connect
    client = clickhouse_connect.get_client(host=args.host, port=args.port)

    # Get total count
    total = client.query("SELECT count() FROM solar.iri_lookup").result_rows[0][0]
    print(f"solar.iri_lookup: {total:,} rows")

    # Get unique grids (sorted for deterministic indexing)
    print("Querying unique grids...")
    grid_rows = client.query(
        "SELECT DISTINCT grid_4 FROM solar.iri_lookup ORDER BY grid_4"
    ).result_rows
    grids = []
    for row in grid_rows:
        g = row[0].strip('\x00') if isinstance(row[0], str) else row[0].decode().strip('\x00')
        grids.append(g)

    n_grids = len(grids)
    grid_index = {g: i for i, g in enumerate(grids)}
    print(f"Unique grids: {n_grids:,}")

    # Allocate output array: (N_grids, 24_hours, 12_months, 18_sfi, 3_params)
    # Fill with defaults: foF2=5.0, hmF2=300.0, foE=3.0
    data = np.full((n_grids, 24, 12, len(SFI_BUCKETS), 3), [5.0, 300.0, 3.0],
                   dtype=np.float32)
    print(f"Array shape: {data.shape}, size: {data.nbytes / 1e6:.1f} MB")

    # Stream all rows from ClickHouse
    print("Loading data from ClickHouse...")
    t0 = time.time()
    result = client.query(
        "SELECT grid_4, hour, month, sfi_bucket, foF2, hmF2, foE "
        "FROM solar.iri_lookup"
    )

    filled = 0
    skipped = 0
    for row in result.result_rows:
        grid_raw = row[0].strip('\x00') if isinstance(row[0], str) else row[0].decode().strip('\x00')
        hour = int(row[1])
        month = int(row[2])
        sfi = int(row[3])
        foF2 = float(row[4])
        hmF2 = float(row[5])
        foE = float(row[6])

        gidx = grid_index.get(grid_raw)
        sidx = SFI_TO_IDX.get(sfi)
        if gidx is None or sidx is None:
            skipped += 1
            continue

        month_idx = month - 1  # 0-indexed

        # Replace NaN with defaults
        if np.isnan(foF2):
            foF2 = 5.0
        if np.isnan(hmF2):
            hmF2 = 300.0
        if np.isnan(foE):
            foE = 3.0

        data[gidx, hour, month_idx, sidx, :] = [foF2, hmF2, foE]
        filled += 1

    elapsed = time.time() - t0
    print(f"Loaded {filled:,} entries in {elapsed:.1f}s (skipped {skipped:,})")

    # Verify no NaN in output
    nan_count = np.isnan(data).sum()
    print(f"NaN values in array: {nan_count}")
    assert nan_count == 0, f"FATAL: {nan_count} NaN values remain in array!"

    # Save as compressed .npz
    print(f"Saving to {args.output}...")
    np.savez_compressed(
        args.output,
        data=data,
        grid_index=grid_index,       # dict: grid_4 -> int
        grids=np.array(grids),       # string array for reverse lookup
        sfi_buckets=np.array(SFI_BUCKETS, dtype=np.int32),
    )

    file_size = os.path.getsize(args.output)
    print(f"Done. File size: {file_size / 1e6:.1f} MB")

    # Spot check
    jn48_idx = grid_index.get('JN48')
    if jn48_idx is not None:
        # July noon SFI=150
        sfi_idx = SFI_TO_IDX[150]
        vals = data[jn48_idx, 12, 6, sfi_idx, :]
        print(f"\nSpot check — JN48, Jul noon, SFI=150:")
        print(f"  foF2={vals[0]:.2f} MHz, hmF2={vals[1]:.0f} km, foE={vals[2]:.2f} MHz")

    # Usage hint
    print(f"""
--- M3 Usage ---
npz = np.load("{os.path.basename(args.output)}", allow_pickle=True)
data = npz["data"]                     # shape {data.shape}, {data.nbytes / 1e6:.0f} MB
grid_index = npz["grid_index"].item()  # dict: grid_4 -> int idx
sfi_buckets = npz["sfi_buckets"]       # [70, 80, ..., 240]

# Lookup: foF2 at JN48, 12 UTC, July, SFI=150
sfi_idx = np.searchsorted(sfi_buckets, sfi_bucket(150))
foF2, hmF2, foE = data[grid_index["JN48"], 12, 6, sfi_idx, :]
""")


if __name__ == '__main__':
    main()
