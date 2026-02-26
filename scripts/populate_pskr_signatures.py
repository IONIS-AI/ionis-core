#!/usr/bin/env python3
"""
populate_pskr_signatures.py — PSKR Aggregated Signatures

Aggregates 548M+ PSK Reporter spots into signatures matching the
WSPR/RBN/Contest schema for engineer_features() compatibility.

Steps:
1. Query pskr.bronze grouped by (tx_grid_4, rx_grid_4, band, hour, month)
2. Join solar.bronze at 3-hour resolution for SFI/Kp
3. Compute haversine distance and azimuth from grid centroids in numpy
4. Filter: distance > 500 km (ground-wave exclusion)
5. INSERT into pskr.signatures in batches

Expected output: ~9M signatures from 35M usable spots.

Prerequisites:
    - pskr.signatures table exists (36-pskr_signatures.sql)
    - pskr.bronze populated (548M+ spots)
    - solar.bronze populated (2000-2026)

Usage:
    python populate_pskr_signatures.py
    CH_HOST=10.60.1.1 python populate_pskr_signatures.py
"""

import os
import sys
import time

import numpy as np

try:
    import clickhouse_connect
except ImportError:
    print("ERROR: clickhouse-connect not installed. Run: uv pip install clickhouse-connect")
    sys.exit(1)


# ── Configuration ─────────────────────────────────────────────────────────────

CH_HOST = os.environ.get('CH_HOST', 'localhost')
CH_PORT = int(os.environ.get('CH_PORT', '8123'))

INSERT_BATCH = 500_000
MIN_SPOTS = 3
SNR_MIN = -30
SNR_MAX = 30
MIN_DISTANCE_KM = 500

HF_BANDS = [102, 103, 104, 105, 106, 107, 108, 109, 110, 111]
BAND_NAMES = {
    102: '160m', 103: '80m', 104: '60m', 105: '40m', 106: '30m',
    107: '20m', 108: '17m', 109: '15m', 110: '12m', 111: '10m',
}


# ── Grid / Geo Utilities ─────────────────────────────────────────────────────

def grid4_to_latlon(grid):
    """Convert 4-char Maidenhead grid to (lat, lon) centroid."""
    g = str(grid).upper().strip('\x00').strip()
    if len(g) < 4:
        return 0.0, 0.0
    try:
        lon = (ord(g[0]) - ord('A')) * 20 + int(g[2]) * 2 - 180 + 1.0
        lat = (ord(g[1]) - ord('A')) * 10 + int(g[3]) - 90 + 0.5
    except (ValueError, IndexError):
        return 0.0, 0.0
    return lat, lon


def grid4_to_latlon_arrays(grids):
    """Convert array of 4-char grids to (lat, lon) arrays."""
    n = len(grids)
    lats = np.zeros(n, dtype=np.float64)
    lons = np.zeros(n, dtype=np.float64)
    for i, g in enumerate(grids):
        lats[i], lons[i] = grid4_to_latlon(g)
    return lats, lons


def haversine_km(lat1, lon1, lat2, lon2):
    """Vectorized great-circle distance in km."""
    phi1, phi2 = np.radians(lat1), np.radians(lat2)
    dphi = np.radians(lat2 - lat1)
    dlam = np.radians(lon2 - lon1)
    a = np.sin(dphi / 2) ** 2 + np.cos(phi1) * np.cos(phi2) * np.sin(dlam / 2) ** 2
    return 2 * 6371 * np.arcsin(np.sqrt(np.clip(a, 0, 1)))


def compute_azimuth(lat1, lon1, lat2, lon2):
    """Vectorized initial bearing in degrees [0, 360)."""
    phi1, phi2 = np.radians(lat1), np.radians(lat2)
    dlam = np.radians(lon2 - lon1)
    x = np.sin(dlam) * np.cos(phi2)
    y = np.cos(phi1) * np.sin(phi2) - np.sin(phi1) * np.cos(phi2) * np.cos(dlam)
    return (np.degrees(np.arctan2(x, y)) + 360) % 360


# ── Main ─────────────────────────────────────────────────────────────────────

def main():
    wall_t0 = time.perf_counter()

    print("=" * 70)
    print("  Populating pskr.signatures")
    print("=" * 70)

    client = clickhouse_connect.get_client(host=CH_HOST, port=int(CH_PORT))

    # ── Pre-flight checks ────────────────────────────────────────────────

    pskr_count = client.query("SELECT count() FROM pskr.bronze").result_rows[0][0]
    if pskr_count == 0:
        print("ERROR: pskr.bronze is empty")
        sys.exit(1)

    solar_min = client.query(
        "SELECT min(date) FROM solar.bronze WHERE observed_flux > 0"
    ).result_rows[0][0]

    solar_count = client.query(
        "SELECT count() FROM solar.bronze WHERE observed_flux > 0"
    ).result_rows[0][0]

    print(f"  Host:            {CH_HOST}:{CH_PORT}")
    print(f"  PSKR spots:      {pskr_count:,}")
    print(f"  Solar from:      {solar_min}")
    print(f"  Solar rows:      {solar_count:,}")
    print(f"  SNR filter:      {SNR_MIN} to {SNR_MAX} dB")
    print(f"  Min bucket:      {MIN_SPOTS} spots")
    print(f"  Min distance:    {MIN_DISTANCE_KM} km")
    print("=" * 70)
    print()

    # ── Create table (DDL) ───────────────────────────────────────────────

    script_dir = os.path.dirname(os.path.abspath(__file__))
    ddl_paths = [
        os.path.join(script_dir, '..', 'ddl', '36-pskr_signatures.sql'),
        os.path.join(script_dir, '..', 'src', '36-pskr_signatures.sql'),
    ]
    for ddl_path in ddl_paths:
        if os.path.exists(ddl_path):
            with open(ddl_path) as f:
                for stmt in f.read().split(';'):
                    stmt = stmt.strip()
                    if stmt and not stmt.startswith('--'):
                        try:
                            client.command(stmt)
                        except Exception:
                            pass
            print(f"  DDL applied: {ddl_path}")
            break
    else:
        print("  WARNING: DDL file not found, assuming table exists")

    # Truncate for idempotent re-run
    print("  Truncating pskr.signatures...")
    client.command("TRUNCATE TABLE IF EXISTS pskr.signatures")
    print()

    # ── Population: per-band sequential ──────────────────────────────────

    total_inserted = 0
    total_filtered = 0
    total_groups = 0

    for band in HF_BANDS:
        bname = BAND_NAMES[band]
        band_idx = band - 101
        print(f"  [{band_idx:2d}/10] Band {band} ({bname})...")
        t0 = time.perf_counter()

        # Aggregate in ClickHouse — everything except distance/azimuth
        query = f"""
        SELECT
            substring(p.sender_grid, 1, 4)   AS tx_grid_4,
            substring(p.receiver_grid, 1, 4) AS rx_grid_4,
            {band}                           AS band,
            toHour(p.timestamp)              AS hour,
            toMonth(p.timestamp)             AS month,
            quantile(0.5)(p.snr)             AS median_snr,
            count()                          AS spot_count,
            stddevPop(p.snr)                 AS snr_std,
            countIf(p.snr > -20) / count()   AS reliability,
            avg(sol.observed_flux)           AS avg_sfi,
            avg(sol.kp_index)                AS avg_kp
        FROM pskr.bronze p
        LEFT JOIN solar.bronze sol
            ON toDate(p.timestamp) = sol.date
            AND intDiv(toHour(p.timestamp), 3) = intDiv(toHour(sol.time), 3)
        WHERE p.sender_grid != ''
          AND p.receiver_grid != ''
          AND length(p.sender_grid) >= 4
          AND length(p.receiver_grid) >= 4
          AND p.band = {band}
          AND p.snr BETWEEN {SNR_MIN} AND {SNR_MAX}
        GROUP BY tx_grid_4, rx_grid_4, hour, month
        HAVING count() >= {MIN_SPOTS}
        SETTINGS
            max_threads = 64,
            max_memory_usage = 80000000000,
            max_bytes_before_external_group_by = 20000000000
        """

        result = client.query(query)
        rows = result.result_rows

        if not rows:
            elapsed = time.perf_counter() - t0
            print(f"    No data ({elapsed:.1f}s)")
            continue

        n_groups = len(rows)
        total_groups += n_groups

        # Extract columns into numpy arrays
        tx_grids   = np.array([r[0] for r in rows], dtype='U4')
        rx_grids   = np.array([r[1] for r in rows], dtype='U4')
        bands      = np.full(n_groups, band, dtype=np.int32)
        hours      = np.array([r[3] for r in rows], dtype=np.uint8)
        months     = np.array([r[4] for r in rows], dtype=np.uint8)
        median_snr = np.array([float(r[5]) for r in rows], dtype=np.float32)
        spot_count = np.array([int(r[6]) for r in rows], dtype=np.uint32)
        snr_std    = np.array([float(r[7]) for r in rows], dtype=np.float32)
        reliability = np.array([float(r[8]) for r in rows], dtype=np.float32)
        avg_sfi    = np.array([float(r[9]) if r[9] is not None else 0.0
                               for r in rows], dtype=np.float32)
        avg_kp     = np.array([float(r[10]) if r[10] is not None else 0.0
                               for r in rows], dtype=np.float32)

        query_elapsed = time.perf_counter() - t0
        print(f"    Aggregated: {n_groups:,} groups ({query_elapsed:.1f}s)")

        # Compute lat/lon from grid centroids
        t1 = time.perf_counter()
        tx_lats, tx_lons = grid4_to_latlon_arrays(tx_grids)
        rx_lats, rx_lons = grid4_to_latlon_arrays(rx_grids)

        # Compute distance and azimuth (vectorized numpy)
        distances = haversine_km(tx_lats, tx_lons, rx_lats, rx_lons)
        azimuths = compute_azimuth(tx_lats, tx_lons, rx_lats, rx_lons)
        geo_elapsed = time.perf_counter() - t1

        # Ground-wave filter
        mask = distances > MIN_DISTANCE_KM
        n_filtered = int((~mask).sum())
        n_keep = int(mask.sum())
        total_filtered += n_filtered

        if n_keep == 0:
            elapsed = time.perf_counter() - t0
            print(f"    All filtered (ground-wave < {MIN_DISTANCE_KM} km) ({elapsed:.1f}s)")
            continue

        print(f"    Geo compute: {geo_elapsed:.1f}s | "
              f"Keep: {n_keep:,} | Filtered: {n_filtered:,}")

        # Apply ground-wave filter to all arrays
        tx_grids    = tx_grids[mask]
        rx_grids    = rx_grids[mask]
        bands       = bands[mask]
        hours       = hours[mask]
        months      = months[mask]
        median_snr  = median_snr[mask]
        spot_count  = spot_count[mask]
        snr_std     = snr_std[mask]
        reliability = reliability[mask]
        avg_sfi     = avg_sfi[mask]
        avg_kp      = avg_kp[mask]
        distances   = distances[mask]
        azimuths    = azimuths[mask]

        # INSERT in batches (column-oriented)
        t2 = time.perf_counter()
        band_inserted = 0
        for start in range(0, n_keep, INSERT_BATCH):
            end = min(start + INSERT_BATCH, n_keep)
            s = slice(start, end)

            data = [
                tx_grids[s].tolist(),
                rx_grids[s].tolist(),
                bands[s].tolist(),
                hours[s].tolist(),
                months[s].tolist(),
                median_snr[s].tolist(),
                spot_count[s].tolist(),
                snr_std[s].tolist(),
                reliability[s].tolist(),
                avg_sfi[s].tolist(),
                avg_kp[s].tolist(),
                distances[s].astype(np.uint32).tolist(),
                azimuths[s].astype(np.uint16).tolist(),
            ]

            client.insert(
                'pskr.signatures', data,
                column_names=[
                    'tx_grid_4', 'rx_grid_4', 'band', 'hour', 'month',
                    'median_snr', 'spot_count', 'snr_std', 'reliability',
                    'avg_sfi', 'avg_kp', 'avg_distance', 'avg_azimuth',
                ],
                column_oriented=True,
            )
            band_inserted += end - start

        insert_elapsed = time.perf_counter() - t2
        total_inserted += n_keep
        elapsed = time.perf_counter() - t0
        print(f"    Inserted: {n_keep:,} ({insert_elapsed:.1f}s) | "
              f"Total: {elapsed:.1f}s | Cumulative: {total_inserted:,}")

    # ── Summary ──────────────────────────────────────────────────────────

    wall_elapsed = time.perf_counter() - wall_t0
    total_sigs = client.query("SELECT count() FROM pskr.signatures").result_rows[0][0]

    print()
    print("=" * 70)
    print("  Population Complete — PSKR Signatures")
    print("=" * 70)
    print(f"  Total signatures:     {total_sigs:,}")
    print(f"  Total groups queried: {total_groups:,}")
    print(f"  Ground-wave filtered: {total_filtered:,}")
    print(f"  Wall time:            {wall_elapsed:.0f}s")
    print("=" * 70)
    print()

    # SNR distribution
    print("  SNR distribution (p10 / p50 / p90):")
    snr_dist = client.query("""
        SELECT
            round(quantile(0.1)(median_snr), 1) AS p10,
            round(quantile(0.5)(median_snr), 1) AS p50,
            round(quantile(0.9)(median_snr), 1) AS p90
        FROM pskr.signatures
    """).result_rows[0]
    print(f"    p10={snr_dist[0]}  p50={snr_dist[1]}  p90={snr_dist[2]}")
    print()

    # Per-band summary
    print("  Per-band breakdown:")
    print(f"    {'Band':>6s}  {'Sigs':>10s}  {'Avg SNR':>8s}  {'Avg Spots':>10s}  {'Avg Dist':>9s}")
    print(f"    {'-' * 50}")
    band_rows = client.query("""
        SELECT
            band,
            count()                   AS signatures,
            round(avg(median_snr), 1) AS avg_snr,
            round(avg(spot_count), 0) AS avg_spots,
            round(avg(avg_distance), 0) AS avg_dist_km
        FROM pskr.signatures
        GROUP BY band
        ORDER BY band
    """).result_rows
    for r in band_rows:
        bname = BAND_NAMES.get(r[0], str(r[0]))
        print(f"    {bname:>6s}  {r[1]:>10,}  {r[2]:>+7.1f}  {r[3]:>10.0f}  {r[4]:>8.0f} km")
    print()

    # Same-grid check
    self_count = client.query(
        "SELECT count() FROM pskr.signatures WHERE tx_grid_4 = rx_grid_4"
    ).result_rows[0][0]
    print(f"  Same-grid signatures: {self_count:,}")

    # Solar coverage
    solar_pct = client.query(
        "SELECT round(countIf(avg_sfi > 0) * 100.0 / count(), 1) FROM pskr.signatures"
    ).result_rows[0][0]
    print(f"  Solar coverage:       {solar_pct}%")
    print()

    print("=" * 70)
    print("  Ready for scoring:")
    print("    python tools/score_model.py --config versions/v22/config_v22.json \\")
    print("        --source pskr_sig --profile wspr")
    print("=" * 70)

    client.close()


if __name__ == '__main__':
    main()
