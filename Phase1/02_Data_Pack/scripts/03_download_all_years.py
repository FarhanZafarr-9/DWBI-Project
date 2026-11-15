"""Download every bulk-available raw source for the DWBI project.

Verified 2026-11-17:
  BTS On-Time Reporting  2025 M1-M12 and 2026 M1-M8
  BTS DB1B Market        2025 Q1-Q2 only (later quarters not published)
  FAA ReleasableAircraft current snapshot (MASTER, ACFTREF, DEREG)
  NOAA Global Hourly     2025 station-year CSVs (no 2026 prefix exists yet)
  T-100 has no bulk file - download manually from TranStats into data/raw_data/bts_t100/

Resumable: skips non-empty targets, writes to .part then renames on success.
Usage: python scripts/03_download_all_years.py [all|ontime|db1b|faa|noaa]
"""
import urllib.request, urllib.error, ssl, csv, io, json, pathlib, time, zipfile, sys

UA = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"}
CTX = ssl.create_default_context()
ROOT = pathlib.Path(__file__).resolve().parents[1]
RAW = ROOT / "data" / "raw_data"
REF = ROOT / "data" / "reference"
MANIFEST = RAW / "DOWNLOAD_MANIFEST.json"
BTS = "https://transtats.bts.gov/PREZIP/"
ONTIME = BTS + "On_Time_Reporting_Carrier_On_Time_Performance_1987_present_{y}_{m}.zip"
DB1B = BTS + "Origin_and_Destination_Survey_DB1BMarket_{y}_{q}.zip"
FAA = "https://registry.faa.gov/database/ReleasableAircraft.zip"
NOAA = "https://noaa-global-hourly-pds.s3.amazonaws.com/{y}/{usaf}{wban}.csv"

results = []

def log(msg):
    print(msg, flush=True)

def fetch(url, dest, tries=4):
    dest = pathlib.Path(dest)
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists() and dest.stat().st_size > 0:
        log(f"SKIP  {dest.name} ({dest.stat().st_size/1e6:.1f} MB already present)")
        results.append({"file": str(dest.relative_to(RAW)), "url": url, "bytes": dest.stat().st_size, "status": "already-present"})
        return True
    part = dest.with_name(dest.name + ".part")
    for attempt in range(1, tries + 1):
        try:
            req = urllib.request.Request(url, headers=UA)
            with urllib.request.urlopen(req, timeout=180, context=CTX) as r:
                ctype = r.headers.get("Content-Type", "")
                if "text/html" in ctype:
                    raise RuntimeError(f"got HTML instead of data ({r.geturl()})")
                expected = int(r.headers.get("Content-Length") or 0)
                with open(part, "wb") as f:
                    while True:
                        chunk = r.read(1 << 20)
                        if not chunk:
                            break
                        f.write(chunk)
            size = part.stat().st_size
            if expected and abs(size - expected) > 1024:
                raise RuntimeError(f"size mismatch {size} vs {expected}")
            part.replace(dest)
            log(f"OK    {dest.name} ({size/1e6:.1f} MB)")
            results.append({"file": str(dest.relative_to(RAW)), "url": url, "bytes": size, "status": "downloaded"})
            return True
        except Exception as e:
            log(f"RETRY {attempt}/{tries} {dest.name}: {type(e).__name__}: {str(e)[:120]}")
            if part.exists():
                part.unlink()
            time.sleep(4 * attempt)
    log(f"FAILED {url}")
    results.append({"file": str(dest.relative_to(RAW)), "url": url, "bytes": 0, "status": "FAILED"})
    return False

def ontime():
    for year, months in ((2025, range(1, 13)), (2026, range(1, 9))):
        for m in months:
            fetch(ONTIME.format(y=year, m=m), RAW / "bts_ontime" / f"ontime_{year}_{m:02d}.zip")

def db1b():
    for q in (1, 2):
        fetch(DB1B.format(y=2025, q=q), RAW / "bts_db1b" / f"db1b_market_2025_q{q}.zip")

def faa():
    z = RAW / "faa" / "ReleasableAircraft.zip"
    if not fetch(FAA, z):
        return
    try:
        with zipfile.ZipFile(z) as f:
            names = f.namelist()
            log("FAA zip contents: " + ", ".join(f"{n} ({f.getinfo(n).file_size/1e6:.0f} MB)" for n in names[:15]))
            want = [n for n in names if n.split("/")[-1].upper() in ("MASTER.TXT", "ACFTREF.TXT", "DEREG.TXT")]
            for n in want:
                out = RAW / "faa" / n.split("/")[-1]
                if out.exists() and out.stat().st_size > 0:
                    log(f"SKIP  extract {out.name}")
                    continue
                with f.open(n) as src, open(out, "wb") as dst:
                    while True:
                        chunk = src.read(1 << 20)
                        if not chunk:
                            break
                        dst.write(chunk)
                log(f"EXTRACT {out.name} ({out.stat().st_size/1e6:.1f} MB)")
    except Exception as e:
        log(f"FAA extract error: {e}")

def noaa():
    hist = RAW / "noaa" / "isd-history.csv"
    if not hist.exists() or hist.stat().st_size < 1000:
        if not fetch("https://www.ncei.noaa.gov/pub/data/noaa/isd-history.csv", hist):
            return
    top = [l.strip().split(",") for l in (REF / "weather_airports_top30.csv").read_text().splitlines()[1:]]
    icaos = [r[1] for r in top if len(r) > 1]
    rows = list(csv.DictReader(io.StringIO(hist.read_text(encoding="utf-8", errors="replace"))))
    for icao in icaos:
        cand = [r for r in rows if r.get("ICAO") == icao and r.get("CTRY") == "US"]
        cand.sort(key=lambda r: (r.get("END") or ""), reverse=True)
        if not cand:
            log(f"NOAA no station for {icao}")
            continue
        s = cand[0]
        url = NOAA.format(y=2025, usaf=s["USAF"], wban=s["WBAN"])
        fetch(url, RAW / "noaa" / f"{icao}_2025.csv")

if __name__ == "__main__":
    which = sys.argv[1] if len(sys.argv) > 1 else "all"
    steps = {"ontime": ontime, "db1b": db1b, "faa": faa, "noaa": noaa}
    for name, fn in steps.items():
        if which in ("all", name):
            log(f"===== {name} =====")
            fn()
    MANIFEST.write_text(json.dumps(results, indent=2), encoding="utf-8")
    log(f"DONE. {sum(r['status']=='downloaded' for r in results)} downloaded, "
        f"{sum(r['status']=='already-present' for r in results)} skipped, "
        f"{sum(r['status']=='FAILED' for r in results)} failed. Manifest: {MANIFEST}")
