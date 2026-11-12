"""Downloads the raw sources into data/raw_data. Usage: python 01_download_data.py [all|ontime|db1b|faa|noaa|t100]
NOTE: URL patterns for BTS/NOAA/FAA could not be tested from the authoring sandbox (blocked network).
If a download fails, open the URL in a browser to confirm the pattern, then adjust the constant below."""
import sys, time, zipfile, pathlib, requests, pandas as pd
YEAR = 2025
ROOT = pathlib.Path(__file__).resolve().parents[1]
RAW = ROOT / "data" / "raw_data"; REF = ROOT / "data" / "reference"
UA = {"User-Agent": "Mozilla/5.0 (DWBI student project)"}
BTS = "https://transtats.bts.gov/PREZIP/"
ONTIME = BTS + "On_Time_Reporting_Carrier_On_Time_Performance_1987_present_{y}_{m}.zip"
DB1B = BTS + "Origin_and_Destination_Survey_DB1BMarket_{y}_{q}.zip"
FAA = "https://registry.faa.gov/database/ReleasableAircraft.zip"
ISD_HISTORY = "https://www.ncei.noaa.gov/pub/data/noaa/isd-history.csv"
ISD_FILE = "https://www.ncei.noaa.gov/data/global-hourly/access/{y}/{usaf}{wban}.csv"

def get(url, dest, tries=3):
    dest = pathlib.Path(dest); dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists() and dest.stat().st_size > 0:
        print("skip (exists)", dest.name); return True
    for i in range(tries):
        try:
            with requests.get(url, headers=UA, stream=True, timeout=120) as r:
                r.raise_for_status()
                with open(dest, "wb") as f:
                    for chunk in r.iter_content(1 << 20): f.write(chunk)
            print("ok", dest.name, f"{dest.stat().st_size/1e6:.1f} MB"); return True
        except Exception as e:
            print(f"retry {i+1}/{tries} {dest.name}: {e}"); time.sleep(3)
    print("FAILED", url); return False

def ontime():
    for m in range(1, 13): get(ONTIME.format(y=YEAR, m=m), RAW / "bts_ontime" / f"ontime_{YEAR}_{m:02d}.zip")
def db1b():
    for q in range(1, 5): get(DB1B.format(y=YEAR, q=q), RAW / "bts_db1b" / f"db1b_market_{YEAR}_q{q}.zip")
def faa():
    z = RAW / "faa" / "ReleasableAircraft.zip"
    if get(FAA, z):
        with zipfile.ZipFile(z) as f:
            for n in ("MASTER.txt", "ACFTREF.txt", "DEREG.txt"): f.extract(n, RAW / "faa")
def noaa():
    hist = RAW / "noaa" / "isd-history.csv"
    if not get(ISD_HISTORY, hist): return
    h = pd.read_csv(hist, dtype=str)
    h = h[(h.CTRY == "US") & h.ICAO.notna() & (h.BEGIN <= f"{YEAR}0101") & (h.END >= f"{YEAR}1231")]
    for icao in pd.read_csv(REF / "weather_airports_top30.csv").icao_code:
        s = h[h.ICAO == icao].sort_values("END", ascending=False)
        if s.empty: print("no ISD station for", icao); continue
        s = s.iloc[0]; get(ISD_FILE.format(y=YEAR, usaf=s.USAF, wban=s.WBAN), RAW / "noaa" / f"{icao}_{YEAR}.csv")
def t100():
    print("""T-100 Domestic Segment (U.S. Carriers Only) has no bulk file - download manually:
 1. TranStats > Air Carrier Statistics (Form 41 Traffic) > T-100 Domestic Segment (U.S. Carriers Only) > Download
 2. Filter Year = %d, Period = All Months (or one month at a time if the site limits it)
 3. Select fields: Year, Month, UniqueCarrier, Origin, Dest, DepScheduled, DepPerformed, Seats, Passengers, Distance, Class
 4. Save the zip(s) in data/raw_data/bts_t100/""" % YEAR)

if __name__ == "__main__":
    what = sys.argv[1] if len(sys.argv) > 1 else "all"
    steps = {"ontime": ontime, "db1b": db1b, "faa": faa, "noaa": noaa, "t100": t100}
    for k, fn in steps.items():
        if what in ("all", k): print(f"== {k}"); fn()
