"""Checks downloaded data against the warehouse design. Usage: python 02_verify_data.py
Prints PASS/WARN lines for each source; skips sources that are not downloaded yet."""
import glob, pathlib, zipfile, pandas as pd
ROOT = pathlib.Path(__file__).resolve().parents[1]; RAW = ROOT / "data" / "raw_data"; REF = ROOT / "data" / "reference"
def say(ok, msg): print(("PASS  " if ok else "WARN  ") + msg)
def read_zip(path, **kw):
    with zipfile.ZipFile(path) as z:
        name = [n for n in z.namelist() if n.lower().endswith(".csv")][0]
        return pd.read_csv(z.open(name), low_memory=False, **kw)
def has(df, cols, label):
    miss = [c for c in cols if c not in df.columns]; say(not miss, f"{label}: required columns present" + (f" (missing {miss})" if miss else ""))

airports = pd.read_csv(REF / "dim_airport_seed.csv"); iata = set(airports.iata_code)
faa_n = None
f = RAW / "faa" / "MASTER.txt"
if f.exists():
    m = pd.read_csv(f, dtype=str, skipinitialspace=True, index_col=False); m.columns = [c.strip() for c in m.columns]
    r = pd.read_csv(RAW / "faa" / "ACFTREF.txt", dtype=str, skipinitialspace=True, index_col=False); r.columns = [c.strip() for c in r.columns]
    has(m, ["N-NUMBER", "MFR MDL CODE", "YEAR MFR", "TYPE ENGINE"], "FAA MASTER"); has(r, ["CODE", "MFR", "MODEL"], "FAA ACFTREF")
    faa_n = set("N" + m["N-NUMBER"].str.strip()); say(True, f"FAA registered aircraft: {len(m):,}")
else: print("SKIP  FAA (not downloaded)")

files = sorted(glob.glob(str(RAW / "bts_ontime" / "*.zip")))
if files:
    need = ["FlightDate","Reporting_Airline","Tail_Number","Flight_Number_Reporting_Airline","Origin","Dest","CRSDepTime","DepDelay","ArrDelay",
            "TaxiOut","TaxiIn","AirTime","Distance","Cancelled","CancellationCode","Diverted","CarrierDelay","WeatherDelay","NASDelay","SecurityDelay","LateAircraftDelay"]
    df = pd.concat([read_zip(p, usecols=lambda c: c in need) for p in files]); has(df, need, "BTS On-Time")
    say(len(files) == 12, f"months loaded: {len(files)}/12"); say(True, f"flight rows: {len(df):,}; reporting airlines: {df.Reporting_Airline.nunique()}")
    say(True, f"cancelled {df.Cancelled.mean():.1%}, diverted {df.Diverted.mean():.1%}")
    nc = df[(df.Cancelled == 0) & (df.Diverted == 0)]; say(nc.ArrDelay.notna().mean() > 0.97, f"arrival delay populated for completed flights: {nc.ArrDelay.notna().mean():.1%}")
    late = df[df.ArrDelay >= 15]; say(late.CarrierDelay.notna().mean() > 0.95, f"delay-cause minutes populated when arrival delay >= 15: {late.CarrierDelay.notna().mean():.1%}")
    bad = set(df.Origin) | set(df.Dest); say(not (bad - iata), f"airports missing from Dim_Airport seed: {sorted(bad - iata)[:10]}")
    if faa_n: t = df.Tail_Number.dropna().str.strip().unique(); say(True, f"tail numbers matching FAA MASTER: {sum(x in faa_n for x in t)/len(t):.1%} of {len(t):,}")
else: print("SKIP  BTS On-Time (not downloaded)")

f = sorted(glob.glob(str(RAW / "bts_db1b" / "*.zip")))
if f:
    d = read_zip(f[0], nrows=200000); has(d, ["Origin", "Dest", "RPCarrier", "Passengers", "MktFare", "MktCoupons"], "DB1B Market")
    say(True, f"non-stop share of sampled markets (MktCoupons = 1): {(d.MktCoupons == 1).mean():.1%}")
else: print("SKIP  DB1B (not downloaded)")

f = sorted(glob.glob(str(RAW / "bts_t100" / "*.zip")) + glob.glob(str(RAW / "bts_t100" / "*.csv")))
if f:
    t = read_zip(f[0]) if f[0].endswith(".zip") else pd.read_csv(f[0]); t.columns = [c.upper() for c in t.columns]
    has(t, ["UNIQUE_CARRIER", "ORIGIN", "DEST", "PASSENGERS", "SEATS", "DEPARTURES_PERFORMED"], "T-100 Segment")
    if "CLASS" in t: say(True, "service classes present: " + ", ".join(sorted(t.CLASS.astype(str).unique())) + " (use F = scheduled passenger)")
else: print("SKIP  T-100 (not downloaded)")

f = sorted(glob.glob(str(RAW / "noaa" / "K*_*.csv")))
if f:
    for p in f[:30]:
        w = pd.read_csv(p, usecols=["DATE", "TMP", "VIS", "WND"], low_memory=False)
        say(len(w) > 4000, f"{pathlib.Path(p).name}: {len(w):,} observations, {w.TMP.notna().mean():.0%} with temperature")
else: print("SKIP  NOAA (not downloaded)")
