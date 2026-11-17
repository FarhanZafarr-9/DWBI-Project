# Project Context — Aviation Reliability & Performance Data Warehouse

> Working context for AI agents and new contributors. Read this before changing anything in the repo.
> Source material: Phase 1 design pack (`files (6).zip`) and Phase 2 DDL pack (`files (5).zip`), extracted on 2026-11-17.

## 1. Identity

| Field | Value |
|---|---|
| Course | DL3004 — Data Warehousing & Business Intelligence |
| Team | **Null Pointers** |
| Members | Farhan (23L-2589), Haris Hassaan (23L-2642), Muhammad Zuraiz Anjum (23L-2547), Zoraiz Rizwan (23L-6008) |
| Project | Aviation Reliability & Performance Data Warehouse |
| Data year | **2025 full year + 2026 Jan–Aug** (flight data, for YoY). Weather is 2025 only — see §5. |
| Git remote | `https://github.com/FarhanZafarr-9/DWBI-Project.git` (branch `main`) |

## 2. Business problem and objective

Delays and cancellations cost airlines and airports money and customer trust, but the evidence is scattered across separate source systems (flights, passenger demand, weather, aircraft). The goal is one integrated warehouse that lets operations and commercial managers see **where delays happen, what drives them, and how reliability relates to passenger demand**.

In scope: US domestic flights for one year, four business processes, drill-down by date, time, airline, airport, route and aircraft.
Out of scope: passenger-level or revenue data, fare/ticket-price analysis, real-time or predictive modelling, international flights, multi-year trends.

### Stakeholders
- Airline Operations Manager — on-time performance, delay causes, aircraft reliability.
- Airport Operations Manager — congestion, delays, cancellations, weather impact.
- Commercial / Revenue Analyst — demand and load factor versus reliability.

### Requirements (BR1–BR7)
BR1 delays/on-time by airline, route, airport, time · BR2 delay causes (carrier, weather, NAS, security, late aircraft) · BR3 delays/cancellations vs origin weather · BR4 reliability vs demand/load factor · BR5 delays by aircraft model and age · BR6 date (year→day) and location (region→airport) drill-down · BR7 dashboards for operations, airport and commercial users.

Non-functional: free tools only, everything reproducible from GitHub, sized for a standard laptop, all tables/columns in the data dictionary.

## 3. Repository layout

```
DWBI-Project/
├── README.md                           # project overview, Mermaid diagrams, quick start
├── PROJECT_CONTEXT.md                  # this file
├── SUBMISSION_REPORT.md                # Phase 2 load + validation summary
├── reference.md                        # Phase 1 intent vs Phase 2 results vs Phase 3 handover
├── Phase1/
│   ├── 01_Project_Documentation/       # proposal, requirements, 10 business questions,
│   │                                   # fact/dimension identification, grain, schema (PDF),
│   │                                   # schema.dbml, Data_Dictionary.xlsx
│   └── 02_Data_Pack/                   # reference CSVs + Python download/build/verify scripts
│       ├── README.md
│       ├── VERIFICATION_REPORT.md
│       ├── BONUS_TECH_FEASIBILITY.md
│       ├── requirements.txt
│       ├── scripts/                    # 00-04 download/build/verify, 05_prepare_staging.py
│       └── data/                       # reference/ (seeded), raw_data/ (gitignored), cleaned_data/
└── Phase2/
    ├── 00_create_database.sql          # CREATE DATABASE aviation_dw
    ├── 01_create_schemas.sql           # project_staging, project_dw, project_reporting
    ├── 02_staging_tables.sql           # etl_batch, etl_run_log, stg_rejected_rows + staging tables
    ├── 03_dw_tables.sql                # 8 dimensions, 4 facts, FKs, indexes, partitioning
    ├── 04_seed_dimensions.sql          # -1 Unknown member in every dimension
    ├── 05_data_quality_checks.sql      # 28 checks -> project_staging.dq_check_result
    ├── 06_dimension_loads.sql          # clean staging -> dimensions
    ├── 07_fact_loads.sql               # clean staging -> facts (full-load script)
    ├── 08_staging_loads.sql            # raw CSVs -> raw staging -> clean staging
    ├── 99_reset_database.sql           # drops the three schemas (destructive)
    └── DATA_*_REPORT.md / Data_*_Report.pdf   # cleaning and DQ reports
```

Run order: Python `05_prepare_staging.py` first, then SQL `00` → `01` → `02` → `03` →
`04` → `08` → `06` → `07` → `05`. `05` runs last despite its number because it checks
the loaded data; `99` is a teardown script only. See `Phase2/README.md`.
Python data pack: `pip install -r Phase1/02_Data_Pack/requirements.txt`, then `python scripts/01_download_data.py all`, then `python scripts/02_verify_data.py`. T-100 is manual (`... t100` prints the steps).

## 4. Dimensional model (Phase 1 design)

Constellation / galaxy schema: **4 fact tables + 8 conformed dimensions**. Each dimension gets an `Unknown` member with key `-1` at load time. All fact–dimension joins use integer surrogate keys; natural keys stay as attributes.

| Dimension | Hierarchy / natural key | Notes |
|---|---|---|
| `dim_date` | Day > Month > Quarter > Year; `full_date` | weekend/holiday flags, season |
| `dim_time` | Hour > Time band; `hour_of_day` | Night/Morning/Afternoon/Evening, peak flag |
| `dim_airline` | Flat; `carrier_code` | ~14 carriers expected (see caveats) |
| `dim_airport` | Airport > City > State > Region; `iata_code` | role-playing: origin **and** destination |
| `dim_route` | Route > Distance band; `origin_code + dest_code` | `route_name` like `ATL-LAX` |
| `dim_aircraft` | Manufacturer > Model > Aircraft; `tail_number` | optional SCD Type 2 (`is_current`, effective/expiry dates) |
| `dim_flight_status` | Junk dimension; `status_code` | On-time, Delayed, Cancelled, Diverted + reason |
| `dim_weather_condition` | Flat; `condition_code` | Clear, Rain, Snow, Fog, Storm + visibility band |

| Fact | Grain | Measures |
|---|---|---|
| `fact_flight` (transaction) | One scheduled flight leg, origin→destination, on one date | Departure/arrival delay, 5 delay causes, taxi-out/in, air time, distance, cancelled/diverted flags; `flight_number` is a degenerate dimension; partitioned by month on `date_key` |
| `fact_route_demand` (monthly snapshot) | One airline on one route in one month | passengers, seats, departures; load factor = passengers/seats, calculated in a view; `date_key` = first day of month |
| `fact_airport_weather` (hourly snapshot) | One hourly weather observation at one airport | temperature, visibility, wind speed, precipitation; hour converted to airport local time |
| `fact_aircraft_route` (factless) | One aircraft operated by one airline on one route on one date | none — rows are counted |

Grain rules: one grain per fact; measures only describe that grain; different grains are compared **only** through shared dimensions; cancelled/diverted flights stay in `fact_flight` with delay measures empty.

### The 10 business questions
1. Monthly trends in average arrival delay — `fact_flight` × date.
2. Best/worst on-time airlines — `fact_flight` × airline, date.
3. Routes with worst average delays — `fact_flight` × route, airport.
4. Share of delay minutes by cause and season — `fact_flight` × date.
5. Hours/days with most delays — `fact_flight` × date, time.
6. Airport/state congestion, delays, cancellation rates — `fact_flight` × airport, date, status.
7. Origin visibility/wind/precipitation vs delays — `fact_flight` + `fact_airport_weather` × airport, date, time, weather.
8. Passenger volume and load factor by route/month — `fact_route_demand` × route, airline, date.
9. High-demand + low-reliability routes — `fact_route_demand` + `fact_flight`.
10. Aircraft age/model vs delays, distinct aircraft per route — `fact_flight` + `fact_aircraft_route`.

## 5. Data sources

| Source | Feeds | Status in pack |
|---|---|---|
| BTS On-Time Performance | `fact_flight`, aircraft-route | **bulk available** — 2025 months 1–12 and 2026 months 1–8 (data lags ~3 months) |
| BTS T-100 Domestic Segment | `fact_route_demand` | **downloaded** — 2025 months 1–12 and 2026 months 1–8 via the TranStats form |
| BTS DB1B Market | fare/demand context | bulk available for 2025 Q1–Q2 only (later quarters not published) |
| NOAA Global Hourly (ISD) | `fact_airport_weather` | **2025 only** — station-year CSVs on `noaa-global-hourly-pds` S3; no 2026 prefix exists |
| FAA Aircraft Registry | `dim_aircraft` | **downloadable** — `ReleasableAircraft.zip` (~73 MB) with MASTER/ACFTREF/DEREG |
| OurAirports + OpenFlights | `dim_airport` | **downloaded** — reference CSVs included |
| US holiday calendar | `dim_date` | **generated** — `dim_date_2025.csv` and `dim_date_2026.csv` (11 federal holidays each) |

Verified against the live BTS PREZIP directory listing and the NOAA S3 bucket on 2026-11-17. The exact files and byte counts are recorded in `Phase1/02_Data_Pack/data/raw_data/DOWNLOAD_MANIFEST.json` after a download run.

Raw source files live under `Phase1/02_Data_Pack/data/raw_data/` (subfolders `bts_ontime`, `bts_db1b`, `bts_t100`, `faa`, `noaa`) and are **gitignored** because of their size. Keep only the small reference CSVs in version control. `cleaned_data/` is for Phase 2 ETL output and is also gitignored.

### Known source caveats (from `VERIFICATION_REPORT.md`)
- BTS On-Time covers only carriers above 0.5% of domestic revenue (~14 for 2025).
- Keep only `MktCoupons = 1` in DB1B so markets are non-stop and join to `dim_route`.
- Filter T-100 to `CLASS = F` (scheduled passenger) — it also contains cargo/charter.
- FAA is a single current snapshot; deregistered aircraft appear only in `DEREG.txt`.
- Tail-number join needs an `N` prefix: BTS `N12345` vs FAA MASTER `12345`.
- Time zone and region are derived (OpenFlights/coordinates and Census regions).
- Top-30 weather airport list is assumed; validate against BTS flight counts after load.
- Weather is UTC and irregularly timed while flights are local — parse packed `VIS/WND/TMP` strings and round to the hour in ETL.
- If T-100 or DB1B 2025 is unavailable, fall back to 2024 for **all** sources.

### YoY comparison notes (2025 vs 2026)
- 2026 On-Time data currently covers **January–August only**. Compare like-for-like months (2025 M1–M8 vs 2026 M1–M8); never compare 2025 full-year totals with 2026 partial-year totals.
- 2026 T-100 is published for **January–August** (307,438 rows), so demand YoY is possible for M1–M8. There is still **no 2026 DB1B or NOAA weather data**, so fare and weather YoY are not possible from these sources yet.
- `dim_date_2026.csv` supplies date keys for 2026 facts, and `03_dw_tables.sql` already creates monthly `fact_flight` partitions for both 2025 and 2026.
- T-100 has no bulk URL; the two zips in `data/raw_data/bts_t100/` came from the TranStats `DL_SelectFields.aspx` form (year, all months, `CLASS = F` kept in ETL).

## 6. Technology and architecture

PostgreSQL + pgAdmin (warehouse/OLAP), Python/Pandas (ingestion/cleaning), Power BI Desktop (dashboards), Draw.io + dbdiagram.io (diagrams), GitHub (version control), optional BigQuery sandbox for gold marts (60-day table expiry — loads must be scripted/re-runnable).

Planned layers: `staging` (raw, audit, rejects) → `dw` (dimensions/facts) → `reporting` (views/marts), with bronze/silver/gold as a naming concept.

Bonus priorities from `BONUS_TECH_FEASIBILITY.md`:
- Phase 2: medallion layers, data-quality checks, reject/quarantine tables, audit/reconciliation, partitioning + EXPLAIN ANALYZE, unknown members, incremental loads with watermark, SCD Type 1/2.
- Phase 3: ROLLUP/CUBE/window functions, data marts and materialized views, metadata/lineage, Power BI dashboards.
- Skip unless required: dbt Core / Snowflake / BigQuery / Databricks.

## 7. Important discrepancy to resolve

The Phase 1 physical model (`schema.dbml`, `Schema.pdf`) uses schema **`dw`**, while the Phase 2 DDL uses **`project_staging`**, **`project_dw`**, **`project_reporting`**. Treat the Phase 2 DDL as the implementation naming and update the design docs (or align the DDL) before Phase 3 so marts and documentation do not drift. Also confirm whether the bonus layer names (bronze/silver/gold) should be schemas or prefixes.

## 8. Current status and next steps

- Phase 1 (design, 30%): **complete** — documents and data pack present.
- Phase 2 (implementation, 40%): **complete and validated** — all schemas, staging, dimensions, facts, ETL, DQ checks and reports are in the repo. Results: 27 DQ checks pass, 1 documented warning, 0 failures; all 19 FK orphan checks return 0. `fact_flight` and `fact_aircraft_route` use a deterministic 20-month sample; all other loads are full. See `SUBMISSION_REPORT.md`.
- Phase 3 (analytics & BI, 30%): not started — OLAP queries, reporting views, indexing report, dashboards and business insights.

Suggested next work: build `project_reporting` views for the 10 business questions (especially the high-demand / low-reliability cross-fact join), then the analytical and OLAP SQL, indexing report and Power BI dashboards. `reference.md` maps each Phase 3 deliverable to the Phase 2 input it builds on.
