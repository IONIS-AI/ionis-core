#!/usr/bin/env python3
"""test-adif-tier-upgrade.py -- prove the generated ADIF DDL upgrades an EXISTING database.

A new ADIF version is data, not code (Atlas SPEC R17; IONIS-AI/ionis-ai-atlas#41). When one changes
structure, a database already holding older versions must take the new DDL and the new rows, not
only a fresh install. 3.1.6 -> 3.1.7 changed rows only, so the real data never exercises this; the
test builds a synthetic next version from ADIF's real 3.1.7 all.json with the three structural
changes a release can make:

  1. a NEW COLUMN                    Band gains a header
  2. a natural key that STOPS BEING UNIQUE   Ant_Path reuses an abbreviation under a new record key
  3. a column that must WIDEN to text        a Primary_Administrative_Subdivision DXCC Entity Code
                                             becomes a list ('1,291'), as ARRL_Section's already is

Then, in a throwaway PostgreSQL (Red Hat sclorg, CentOS Stream 9, pinned by digest):

  UPGRADE   DDL for 3.1.6+3.1.7, load both; DDL for 3.1.6+3.1.7+next on the SAME database, load
            next. Every version audits clean; applying the DDL again changes nothing.
  FRESH     DDL for all three on an empty database, load all three. Must end with the same
            columns, types, indexes and foreign keys as UPGRADE.
  CONTROL   the generator as it is on `main` runs the same UPGRADE and must FAIL, so this test is
            known to catch the gap it exists for. Skipped with --no-control.

ADIF's zips come from adif.org, verified against data/adif_upstream_sha256.json, cached in
$ATLAS_ADIF_CACHE (default ~/.cache/ionis-ai-atlas/adif, shared with Atlas's tests). Needs podman.

    make test-adif-upgrade          (or: python3 scripts/test-adif-tier-upgrade.py)
"""
import argparse
import copy
import hashlib
import importlib.util
import io
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PINS = json.loads((ROOT / "data/adif_upstream_sha256.json").read_text())
CACHE = Path(os.environ.get("ATLAS_ADIF_CACHE", Path.home() / ".cache/ionis-ai-atlas/adif"))
PG_IMAGE = "quay.io/sclorg/postgresql-16-c9s@sha256:f6bd736450b263a8259497092e0bf36e9716d4657a2ce10c12c8617d48e26c91"
NEXT = "3199"                                  # the synthetic version's directory; its Version is 3.1.99


def module(source: str, name: str):
    spec = importlib.util.spec_from_loader(name, loader=None)
    mod = importlib.util.module_from_spec(spec)
    exec(compile(source, name, "exec"), mod.__dict__)
    return mod


# --- ADIF's files ---------------------------------------------------------------------------------
def spec_dir(tmp: Path) -> Path:
    spec = tmp / "spec"
    for vdir, pin in PINS["versions"].items():
        path = CACHE / f"{vdir}.zip"
        if not path.exists() or hashlib.sha256(path.read_bytes()).hexdigest() != pin["zip_sha256"]:
            raw = urllib.request.urlopen(pin["source"], timeout=60).read()
            got = hashlib.sha256(raw).hexdigest()
            if got != pin["zip_sha256"]:
                sys.exit(f"{pin['source']}: SHA-256 {got} is not the pinned {pin['zip_sha256']}")
            CACHE.mkdir(parents=True, exist_ok=True)
            path.write_bytes(raw)
        z = zipfile.ZipFile(io.BytesIO(path.read_bytes()))
        (spec / vdir).mkdir(parents=True)
        (spec / vdir / "all.json").write_bytes(z.read(next(n for n in z.namelist() if n.endswith("exports/json/all.json"))))
    return spec


def synthetic_next(spec: Path) -> dict:
    """ADIF's real 3.1.7, as a version 3.1.99 with three structural changes. Returns its pins."""
    data = json.loads((spec / "317" / "all.json").read_text(encoding="utf-8-sig"))
    adif = data["Adif"]
    adif["Version"] = "3.1.99"
    e = adif["Enumerations"]

    band = e["Band"]                                       # 1. a new column
    band["Header"].append("Test New Column")
    for r in band["Records"].values():
        r["Test New Column"] = "x"

    ant = e["Ant_Path"]                                    # 2. a natural key stops being unique
    key, rec = next(iter(ant["Records"].items()))
    ant["Records"][f"{key}.Reused.0"] = dict(rec)

    pas = e["Primary_Administrative_Subdivision"]          # 3. an integer column becomes a list
    first = next(iter(pas["Records"].values()))
    first["DXCC Entity Code"] = f"{first['DXCC Entity Code']},291"

    raw = json.dumps(data, ensure_ascii=False).encode("utf-8")
    (spec / NEXT).mkdir()
    (spec / NEXT / "all.json").write_bytes(raw)
    pins = copy.deepcopy(PINS)
    pins["versions"][NEXT] = {"source": "synthetic: ADIF 3.1.7 with three structural changes",
                              "zip_sha256": "-", "files": {"all.json": hashlib.sha256(raw).hexdigest()}}
    return pins


def only(pins: dict, *vdirs) -> dict:
    p = copy.deepcopy(pins)
    p["versions"] = {v: p["versions"][v] for v in vdirs}
    return p


# --- PostgreSQL -----------------------------------------------------------------------------------
class PG:
    def __init__(self, name: str):
        self.name = name
        subprocess.run(["podman", "rm", "-f", name], capture_output=True)
        subprocess.run(["podman", "run", "-d", "--name", name, "-e", "POSTGRESQL_ADMIN_PASSWORD=test-only",
                        PG_IMAGE], check=True, capture_output=True)
        for _ in range(60):
            if subprocess.run(["podman", "exec", name, "pg_isready", "-q"], capture_output=True).returncode == 0:
                break
            time.sleep(1)
        else:
            sys.exit(f"{name}: PostgreSQL did not start")
        time.sleep(2)
        self.psql("CREATE DATABASE ionis", db="postgres")

    def psql(self, sql: str, db: str = "ionis", single: bool = False) -> str:
        args = ["podman", "exec", "-i", self.name, "psql", "-X", "-q", "-A", "-t", "-v", "ON_ERROR_STOP=1", "-d", db]
        r = subprocess.run(args + (["-1"] if single else []), input=sql, capture_output=True, text=True)
        if r.returncode:
            raise RuntimeError(r.stderr.strip().splitlines()[-1] if r.stderr.strip() else "psql failed")
        return r.stdout

    def shape(self) -> dict:
        q = {
            "columns": "SELECT table_name||'.'||column_name||' '||data_type FROM information_schema.columns "
                       "WHERE table_schema='adif' ORDER BY 1",
            "indexes": "SELECT indexname FROM pg_indexes WHERE schemaname='adif' ORDER BY 1",
            "fkeys": "SELECT conname FROM pg_constraint WHERE contype='f' AND connamespace='adif'::regnamespace ORDER BY 1",
        }
        return {k: self.psql(v).splitlines() for k, v in q.items()}

    def audit(self, tier, versions: dict) -> list:
        return [f"{v}: {self.psql(tier.audit_sql(a)).strip()}" for v, a in versions.items() if self.psql(tier.audit_sql(a)).strip()]

    def close(self):
        subprocess.run(["podman", "rm", "-f", self.name], capture_output=True)


def upgrade(tier, spec: Path, pins: dict, pg: PG):
    """DDL for 3.1.6+3.1.7, load them; then DDL for all three on the same database, load next."""
    tier._TYPES.clear()
    before = tier.all_versions(str(spec), only(pins, "316", "317"))
    pg.psql(tier.ddl(before))
    for a in before.values():
        pg.psql(tier.load_sql(a), single=True)
    tier._TYPES.clear()
    after = tier.all_versions(str(spec), pins)
    pg.psql(tier.ddl(after))
    pg.psql(tier.load_sql(after[NEXT]), single=True)
    return after


# --- the test -------------------------------------------------------------------------------------
def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--no-control", action="store_true", help="skip running the generator from main")
    args = ap.parse_args()
    import adif_tier as tier  # noqa: E402 (scripts/ is on sys.path when run from there)

    fails, passes = [], []
    check = lambda ok, what: (passes if ok else fails).append(what)
    with tempfile.TemporaryDirectory() as t:
        tmp = Path(t)
        spec = spec_dir(tmp)
        pins = synthetic_next(spec)

        up, fresh = PG("adif-upgrade-test"), PG("adif-fresh-test")
        try:
            versions = upgrade(tier, spec, pins, up)
            check(True, "UPGRADE: 3.1.99 loaded into a database built for 3.1.6+3.1.7")
            check(not up.audit(tier, versions), f"UPGRADE: every version audits clean {up.audit(tier, versions)}")
            s = up.shape()
            check("band.test_new_column text" in s["columns"], "UPGRADE: Band gained its new column")
            check("ant_path_natural" not in s["indexes"], "UPGRADE: Ant_Path's natural-key index was dropped")
            check("primary_administrative_subdivision.dxcc_entity_code text" in s["columns"],
                  "UPGRADE: PAS dxcc_entity_code widened to text")
            check("primary_administrative_subdivision_dxcc_entity_code_fk" not in s["fkeys"]
                  and "primary_administrative_subdivision_adif_version_fkey" in s["fkeys"],
                  "UPGRADE: PAS's DXCC foreign key dropped (it holds a list now); its release key kept")
            up.psql(tier.ddl(versions))
            check(up.shape() == s and not up.audit(tier, versions), "UPGRADE: applying the DDL again changes nothing")

            fresh.psql(tier.ddl(versions))
            for a in versions.values():
                fresh.psql(tier.load_sql(a), single=True)
            check(not fresh.audit(tier, versions), "FRESH: every version audits clean")
            diff = {k: sorted(set(fresh.shape()[k]) ^ set(s[k])) for k in s}
            check(not any(diff.values()), f"FRESH and UPGRADE end with the same shape {diff}")
        finally:
            up.close()
            fresh.close()

        if not args.no_control:
            src = subprocess.run(["git", "-C", str(ROOT), "show", "main:scripts/adif_tier.py"],
                                 capture_output=True, text=True).stdout
            if not src:
                check(False, "CONTROL: could not read scripts/adif_tier.py from main")
            else:
                old, ctl = module(src, "adif_tier_main"), PG("adif-control-test")
                try:
                    upgrade(old, spec, pins, ctl)
                    check(False, "CONTROL: the generator on main upgraded cleanly, so this test would not catch the gap")
                except RuntimeError as e:
                    check(True, f"CONTROL: the generator on main fails the same upgrade ({e})")
                finally:
                    ctl.close()

    print("\n".join([f"PASS  {p}" for p in passes] + [f"FAIL  {f}" for f in fails]))
    print(f"\n{len(passes)} passed, {len(fails)} failed")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    sys.exit(main())
