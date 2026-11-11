# Null Pointers - DL3004 Data Pack

Aviation Reliability & Performance Data Warehouse (one year of US domestic flights, assumed 2025).

## Contents
- `data/reference/` - ready to use: `dim_airport_seed.csv` (2,036 US airports), `dim_date_2025.csv` (with holidays), `weather_airports_top30.csv`, plus the raw OurAirports and OpenFlights files
- `data/raw_data/` - empty, filled by the download script (matches the repo structure in the project handout)
- `data/cleaned_data/` - empty, for Phase 2 output
- `scripts/` - `00_build_reference.py`, `01_download_data.py`, `02_verify_data.py`
- `VERIFICATION_REPORT.md` - what was checked and what differs from our design
- `BONUS_TECH_FEASIBILITY.md` - technologies from the sample architecture

## How to run
```
pip install -r requirements.txt
python scripts/01_download_data.py all
python scripts/02_verify_data.py
```
- BTS On-Time, DB1B, FAA and NOAA download automatically (about 2-4 GB total).
- **T-100 is manual**: run `python scripts/01_download_data.py t100` for the steps.
- The downloads need a normal internet connection. The authoring sandbox could not reach BTS, NOAA or FAA, so those files are not in this zip.
