"""Prepare flat CSVs for the Phase 2 staging load.

Reads the gitignored raw_data/ tree and writes one CSV per staging raw table
into data/cleaned_data/. Column order matches project_staging.stg_*_raw exactly,
so Phase2/08_staging_loads.sql can load them with psql \\copy.

This script never connects to a database.

Usage:
    python scripts/05_prepare_staging.py --batch-id 1
"""

import argparse
import csv
import io
import pathlib
import re
import zipfile

BASE = pathlib.Path(__file__).resolve().parents[1]
RAW = BASE / "data" / "raw_data"
REF = BASE / "data" / "reference"
OUT = BASE / "data" / "cleaned_data"

AIRLINE_NAMES = {
    "AA": "American Airlines",
    "DL": "Delta Air Lines",
    "UA": "United Airlines",
    "WN": "Southwest Airlines",
    "AS": "Alaska Airlines",
    "B6": "JetBlue Airways",
    "NK": "Spirit Airlines",
    "F9": "Frontier Airlines",
    "G4": "Allegiant Air",
    "HA": "Hawaiian Airlines",
    "OH": "PSA Airlines",
    "OO": "SkyWest Airlines",
    "MQ": "Envoy Air",
    "YV": "Mesa Airlines",
    "9E": "Endeavor Air",
    "EV": "ExpressJet Airlines",
}

FLIGHT_KEYS = [
    "FlightDate", "Reporting_Airline", "Tail_Number",
    "Flight_Number_Reporting_Airline", "Origin", "Dest", "CRSDepTime",
    "DepDelay", "TaxiOut", "TaxiIn", "ArrDelay", "Cancelled",
    "CancellationCode", "Diverted", "AirTime", "Distance", "CarrierDelay",
    "WeatherDelay", "NASDelay", "SecurityDelay", "LateAircraftDelay",
]

FLIGHT_COLS = [
    "batch_id", "source_file", "flight_date", "reporting_airline",
    "tail_number", "flight_number", "origin", "dest", "crs_dep_time",
    "dep_delay", "taxi_out", "taxi_in", "arr_delay", "cancelled",
    "cancellation_code", "diverted", "air_time", "distance",
    "carrier_delay", "weather_delay", "nas_delay", "security_delay",
    "late_aircraft_delay",
]


def open_csv(name, columns):
    fh = (OUT / name).open("w", newline="", encoding="utf-8")
    writer = csv.writer(fh)
    writer.writerow(columns)
    return fh, writer


def cell(row, key):
    return (row.get(key) or "").strip()


def prepare_flights(batch_id):
    """BTS On-Time zips -> stg_flight_raw.csv; also returns the carrier codes seen."""
    codes = set()
    total = 0
    fh, w = open_csv("stg_flight_raw.csv", FLIGHT_COLS)
    with fh:
        for path in sorted((RAW / "bts_ontime").glob("ontime_*.zip")):
            with zipfile.ZipFile(path) as z:
                inner = next(n for n in z.namelist() if n.lower().endswith(".csv"))
                with z.open(inner) as raw:
                    text = io.TextIOWrapper(raw, encoding="latin-1", newline="")
                    for row in csv.DictReader(text):
                        if not cell(row, "FlightDate"):
                            continue
                        code = cell(row, "Reporting_Airline")
                        if code:
                            codes.add(code)
                        w.writerow([batch_id, path.name] + [cell(row, k) for k in FLIGHT_KEYS])
                        total += 1
    return codes, total


def prepare_airlines(batch_id, codes):
    cols = ["batch_id", "source_file", "carrier_code", "airline_name"]
    fh, w = open_csv("stg_airline_raw.csv", cols)
    with fh:
        for code in sorted(codes):
            w.writerow([batch_id, "bts_ontime", code, AIRLINE_NAMES.get(code, code)])
    return len(codes)


def prepare_route_demand(batch_id):
    """T-100 files -> stg_route_demand_raw.csv. Header-only until T-100 is downloaded."""
    cols = [
        "batch_id", "source_file", "year", "month", "unique_carrier",
        "origin", "dest", "passengers", "seats", "departures_performed",
        "service_class",
    ]
    fh, w = open_csv("stg_route_demand_raw.csv", cols)
    total = 0
    norm = lambda s: re.sub(r"[^a-z0-9]", "", s.lower())
    folder = RAW / "bts_t100"
    sources = []
    if folder.exists():
        sources.extend((p, None) for p in sorted(folder.glob("*.csv")))
        sources.extend((p, "zip") for p in sorted(folder.glob("*.zip")))

    with fh:
        for path, kind in sources:
            if kind == "zip":
                with zipfile.ZipFile(path) as z:
                    members = [
                        n for n in z.namelist()
                        if n.lower().endswith(".csv") and "documentation" not in n.lower()
                    ]
                    for member in members:
                        with z.open(member) as raw:
                            text = io.TextIOWrapper(raw, encoding="latin-1", newline="")
                            total += _write_t100_rows(w, text, batch_id, path.name, cols, norm)
            else:
                with path.open("r", encoding="latin-1", newline="") as src:
                    total += _write_t100_rows(w, src, batch_id, path.name, cols, norm)
    return total


def _write_t100_rows(writer, src, batch_id, source_file, cols, norm):
    """Write one T-100 CSV stream into the route-demand raw CSV. Returns row count."""
    reader = csv.DictReader(src)
    index = {norm(k): k for k in (reader.fieldnames or [])}
    aliases = {"serviceclass": "class"}
    count = 0
    for row in reader:
        values = []
        for col in cols[2:]:
            key = norm(col)
            src_key = index.get(aliases.get(key, key))
            values.append(cell(row, src_key) if src_key else "")
        writer.writerow([batch_id, source_file] + values)
        count += 1
    return count


def prepare_weather(batch_id):
    cols = [
        "batch_id", "source_file", "icao_code", "observation_ts",
        "tmp", "vis", "wnd", "aa1", "mw1", "aw1",
    ]
    keys = ["DATE", "TMP", "VIS", "WND", "AA1", "MW1", "AW1"]
    fh, w = open_csv("stg_weather_raw.csv", cols)
    total = 0
    with fh:
        for path in sorted((RAW / "noaa").glob("*_2025.csv")):
            icao = path.name.split("_")[0]
            with path.open("r", encoding="latin-1", newline="") as src:
                for row in csv.DictReader(src):
                    if not cell(row, "DATE"):
                        continue
                    w.writerow(
                        [batch_id, path.name, icao]
                        + [cell(row, k) for k in keys]
                    )
                    total += 1
    return total


def prepare_faa(batch_id):
    master_cols = [
        "batch_id", "source_file", "n_number", "mfr_mdl_code",
        "year_mfr", "type_engine",
    ]
    acftref_cols = ["batch_id", "source_file", "code", "mfr", "model"]
    folder = RAW / "faa"
    counts = {}

    fh, w = open_csv("stg_faa_master_raw.csv", master_cols)
    n = 0
    with fh:
        with (folder / "MASTER.txt").open("r", encoding="utf-8-sig", newline="") as src:
            for row in csv.DictReader(src):
                w.writerow([
                    batch_id, "MASTER.txt",
                    cell(row, "N-NUMBER"), cell(row, "MFR MDL CODE"),
                    cell(row, "YEAR MFR"), cell(row, "TYPE ENGINE"),
                ])
                n += 1
    counts["master"] = n

    fh, w = open_csv("stg_faa_acftref_raw.csv", acftref_cols)
    n = 0
    with fh:
        with (folder / "ACFTREF.txt").open("r", encoding="utf-8-sig", newline="") as src:
            for row in csv.DictReader(src):
                w.writerow([
                    batch_id, "ACFTREF.txt",
                    cell(row, "CODE"), cell(row, "MFR"), cell(row, "MODEL"),
                ])
                n += 1
    counts["acftref"] = n
    return counts


def prepare_airports(batch_id):
    cols = [
        "batch_id", "source_file", "iata_code", "icao_code", "airport_name",
        "city", "state", "region", "latitude", "longitude", "elevation_ft",
        "airport_type", "time_zone",
    ]
    fh, w = open_csv("stg_airport_raw.csv", cols)
    n = 0
    with fh:
        with (REF / "dim_airport_seed.csv").open("r", encoding="utf-8", newline="") as src:
            for row in csv.DictReader(src):
                w.writerow([batch_id, "dim_airport_seed.csv"] + [cell(row, c) for c in cols[2:]])
                n += 1
    return n


def prepare_holidays(batch_id):
    cols = ["batch_id", "source_file", "holiday_date", "holiday_name"]
    fh, w = open_csv("stg_holiday_raw.csv", cols)
    n = 0
    with fh:
        for name in ("dim_date_2025.csv", "dim_date_2026.csv"):
            with (REF / name).open("r", encoding="utf-8", newline="") as src:
                for row in csv.DictReader(src):
                    if cell(row, "is_holiday").lower() == "true" and cell(row, "holiday_name"):
                        w.writerow([
                            batch_id, name, cell(row, "full_date"), cell(row, "holiday_name"),
                        ])
                        n += 1
    return n


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--batch-id", type=int, default=1)
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)

    codes, flights = prepare_flights(args.batch_id)
    report = {
        "batch_id": args.batch_id,
        "stg_flight_raw": flights,
        "stg_airline_raw": prepare_airlines(args.batch_id, codes),
        "stg_route_demand_raw": prepare_route_demand(args.batch_id),
        "stg_weather_raw": prepare_weather(args.batch_id),
        "stg_airport_raw": prepare_airports(args.batch_id),
        "stg_holiday_raw": prepare_holidays(args.batch_id),
    }
    report.update({"stg_faa_" + k + "_raw": v for k, v in prepare_faa(args.batch_id).items()})
    for name, count in report.items():
        print(f"{name}: {count:,}")
    print(f"CSVs written to {OUT}")


if __name__ == "__main__":
    main()
