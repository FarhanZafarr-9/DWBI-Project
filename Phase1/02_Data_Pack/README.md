# Null Pointers - DL3004 Data Pack

Aviation Reliability & Performance Data Warehouse (one year of US domestic flights, assumed 2025).

## Contents
- `data/reference/` - ready to use: `dim_airport_seed.csv` (2,036 US airports), `dim_date_2025.csv` and `dim_date_2026.csv` (with holidays), `weather_airports_top30.csv`, plus the raw OurAirports and OpenFlights files
- `data/raw_data/` - filled by the download scripts; **gitignored** because of size
- `data/cleaned_data/` - empty, for Phase 2 output; also gitignored
- `scripts/` - `00_build_reference.py`, `01_download_data.py`, `02_verify_data.py`, `03_download_all_years.py`
- `VERIFICATION_REPORT.md` - what was checked and what differs from our design
- `BONUS_TECH_FEASIBILITY.md` - technologies from the sample architecture

## How to run
```
pip install -r requirements.txt
python scripts/03_download_all_years.py all
python scripts/02_verify_data.py
```
Use `01_download_data.py` for the original 2025-only design; `03_download_all_years.py` is the verified 2025 + 2026 version (resumable, records `DOWNLOAD_MANIFEST.json`).

## Availability confirmed 2026-11-17
- **BTS On-Time**: 2025 M1-M12 and 2026 M1-M8 (2026 data lags ~3 months) - use M1-M8 of both years for YoY.
- **BTS DB1B Market**: 2025 Q1-Q2 only; no later quarters or 2026 files published.
- **NOAA Global Hourly**: 2025 only - the S3 bucket has no `2026/` prefix.
- **FAA**: `ReleasableAircraft.zip` (~73 MB) works; MASTER/ACFTREF/DEREG are extracted automatically.
- **T-100 is manual**: run `python scripts/01_download_data.py t100` for the steps, then place files in `data/raw_data/bts_t100/`.
- Raw source files are intentionally not committed; re-run the downloader on a fresh clone.
