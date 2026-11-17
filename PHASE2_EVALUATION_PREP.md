# Phase 2 Evaluation Prep

**Project:** Null Pointers, Aviation Reliability & Performance Data Warehouse (DL3004)
**Phase 2 weight:** 40 marks (Database 10, ETL 15, Surrogate Keys 5, Data Quality 10)

**Basis for this file.** Repo README, `PROJECT_CONTEXT.md`, `SUBMISSION_REPORT.md`, the two Phase 2 reports, `reference.md`, and all nine Phase 2 SQL files (`00`-`08`), read in full. **Not read:** the Phase 1 design documents other than the proposal. The Python step `05_prepare_staging.py` was read in full.

---

## 1. 60-second pitch

Airlines lose money and trust to delays, but the evidence sits in separate systems. We built one PostgreSQL warehouse that joins BTS flight operations, BTS T-100 passenger demand, NOAA weather and the FAA aircraft registry, so a manager can see where delays happen, what drives them, and how reliability relates to demand.

Phase 2 is the implementation: three schemas (`project_staging`, `project_dw`, `project_reporting`), a raw and clean staging layer, 8 dimensions with surrogate keys, 4 fact tables, and 28 automated data quality checks. Result: 27 passed, 1 warning, 0 failures, and 0 orphan rows across all 19 foreign-key checks.

---

## 2. Marks map

| Component | Marks | Evidence to show | Core claim | Be ready for |
|---|---:|---|---|---|
| Database implementation | 10 | `00`-`03`, `99`; 3 schemas; PKs, FKs, UNIQUE constraints; 24 monthly partitions plus a default; 8 indexes on `fact_flight` | Full physical model with integrity enforced by the database, not only by ETL | Why partition by `date_key`; why a composite PK `(flight_key, date_key)` |
| ETL pipeline | 15 | `05_prepare_staging.py`, `08` (raw to clean), `06` (dimensions), `07` (facts); Data Cleaning Report; `etl_batch`, `etl_run_log`, `stg_rejected_rows` | Source files to raw to clean to dimensions to facts, no cleaning inside the warehouse, every reject kept with its reason | The flag bug, the T-100 class filter, the fact sample |
| Surrogate keys | 5 | Identity PKs on every dimension; `-1` Unknown member in each; fact tables hold only keys | Business keys stay as dimension attributes; facts join on integers only | Why `-1` and not NULL; how a tail number becomes `aircraft_key` |
| Data quality validation | 10 | `05_data_quality_checks.sql`; `project_staging.dq_check_result`; Data Quality Report | Completeness, accuracy and integrity are all checked and logged with severity | The 1 warning; the missing NULL-rate check (section 7) |

---

## 3. Numbers to know cold

| Item | Value |
|---|---|
| Coverage | 2025-01 to 2026-08 (**20 months**) |
| Raw flight rows read | 11,730,351 (7,001,619 in 2025, 4,728,732 in 2026) |
| Rejected rows | 0 |
| T-100 raw / clean (CLASS F) | 766,206 / 601,435 |
| NOAA weather rows read | 264,364 (30 stations, 2025 only, ends 2025-08-27) |
| FAA MASTER rows | 319,417 |
| Dimensions | date 731, time 25, airline 15, airport 2,036, route 7,345, aircraft 319,418, flight status 5, weather condition 3 |
| Facts | flight 469,214 (**sampled**), route demand 232,281, weather 171,225, aircraft-route 99,950 (**sampled**) |
| DQ result | 28 checks: 27 pass, 1 warning, 0 fail; 19/19 FK checks at 0 orphans |
| Unknown-member usage | 16,448 facts (INFO) |
| Cancelled flights | 8,229 in the sample (1.8%); 206,801 in the full source |
| Sample rule | `raw_id % 25 = 0`, no LIMIT (11,730,351 / 25 = 469,214) |

**Why the small dimensions look odd, and are correct:** each is real members plus the `-1` Unknown. 731 = 730 days (2025 and 2026) + 1. 25 = 24 hours + 1. 15 = 14 carriers + 1. 5 = 4 statuses + 1.

---

## 4. Suggested 10-minute walkthrough

1. **Architecture (1 min).** Source files, raw staging, clean staging, warehouse, reporting. Use Figure 2 from the Data Cleaning Report.
2. **Schema (2 min).** Star schema figure: `fact_flight` in the centre, 7 dimensions, `dim_airport` used for origin and destination. Mention the other 3 facts and their grains.
3. **ETL run order (2 min).** `00` to `04` setup, then `05_prepare_staging.py`, `08`, `06`, `07`, and `05` DQ last. State that `05` runs last despite its number.
4. **Cleaning (2 min).** Before and after table: `1.00` to true, `150000.00` to 150000, `+0050,1` to 5.0 C, unmatched tail number to `-1`.
5. **Surrogate keys (1 min).** Live query 7.3.
6. **Data quality (2 min).** Scorecard, then live query 7.2 and the warning explanation.

---

## 5. Concrete examples to quote

- **Business key to surrogate key.** BTS tail number `N12345` is matched to FAA `12345` after the `N` prefix is added; the fact stores `aircraft_key`, not the tail number. If no FAA match exists, the fact stores `-1`.
- **Flag bug.** BTS exports `Cancelled` as `0.00` / `1.00`. The first comparison `= '1'` marked every flight as not cancelled. Found because the source summary showed 0 cancellations; 206,801 were recovered from the populated `CancellationCode` column and the SQL now casts to numeric first.
- **T-100 class filter.** `CLASS` has F, L, P and G. Only F carries passenger and seat totals; the others add under 0.5%. Keeping them would have corrupted the route demand fact.
- **Documentation file in the ZIP.** The T-100 zip includes a 45-row field description CSV that would have become 45 junk route rows.
- **Cancelled flights.** Kept in `fact_flight` with status `CANCELLED`; their delay columns are NULL (the first DQ run found 5 cancelled flights with delay values, which led to the fix).

---

## 6. Likely questions and short answers

### Database

**Why a constellation (4 facts, shared dimensions)?** The four business processes have different grains (flight, route-month, airport-hour, aircraft-route-date). Each gets its own fact; they are compared only through shared dimensions (Date, Airport, Airline, Route).

**Why partition `fact_flight`?** By month on `date_key`: 24 monthly partitions plus a default. Queries with a date filter scan only the matching partition, and monthly loads stay isolated. Demo with query 7.7.

**Why is the PK `(flight_key, date_key)`?** PostgreSQL requires the partition column in a PK on a partitioned table.

**What indexes exist?** Eight on `fact_flight`, one per foreign key column, plus smaller indexes on the other facts. Indexing analysis is a Phase 3 deliverable.

### ETL

**Why raw and clean staging?** Raw keeps the source exactly as received (auditable); clean holds typed, validated rows. No transformation happens inside the warehouse layer.

**What happens to bad rows?** They go to `project_staging.stg_rejected_rows` with a reason and the full source row as JSON. In this run the table is empty because no row failed the mandatory-key or date rules.

**Why did the T-100 row count drop from 766,206 to 601,435?** The intended `CLASS = 'F'` filter (2025: 359,198; 2026: 242,237), not a rejection.

**Why did `fact_route_demand` end up with 232,281 rows?** Clean rows are aggregated to the grain of one airline, one route, one month. Duplicate carrier-route-month rows are summed with `GROUP BY` in `07`, so the unique grain is never violated.

**Is the ETL re-runnable?** `04`, `06`, `07` and `05` are: seeds and dimensions use `ON CONFLICT`, `07` deletes the batch's rows before reloading, and `05` truncates its results table. `08` is **not** safe to re-run on its own, because its `\copy` steps append to the raw tables without truncating them (see section 8). Re-run `02` first, or truncate the raw tables.

**What does the audit trail record?** `08` inserts batch 1 and closes it as SUCCESS, and writes 7 `etl_run_log` rows (one per clean staging table, with `rows_inserted` only). `06` and `07` do not write to `etl_run_log`.

**What does the Python step do?** `05_prepare_staging.py` streams the raw BTS, T-100, NOAA, FAA and reference files and writes one flat CSV per raw table, with columns in the same order as `stg_*_raw`. It never connects to a database, tags every row with `batch_id` and `source_file` (lineage), and trims every field. It uses only the standard library (`csv`, `zipfile`) so the 11.7 M flight rows stream without loading into memory.

**Where do airline names come from?** A hardcoded dictionary of 16 carriers in the script; carrier codes seen in the On-Time files are written out, and any code missing from the dictionary falls back to the code itself as the name.

**Why is weather 2025 only?** The script reads `*_2025.csv` station files only, and NOAA has no 2026 files in the bulk bucket.

### Surrogate keys

**Why surrogate keys at all?** Source codes differ across systems (BTS `N12345` versus FAA `12345`), can change, and are wide strings. Integers are smaller, faster to join, and allow slowly changing history.

**Why `-1` instead of NULL?** NOT NULL foreign keys stay valid, joins never drop rows, and unmatched records are visible and countable (16,448 facts) instead of silently missing.

**Is `dim_aircraft` slowly changing?** The table has `row_effective_date`, `row_expiry_date`, `is_current` and a unique partial index on current tail numbers, so the structure is ready for Type 2. As loaded (`06`, section 6) it behaves as **Type 1**: `ON CONFLICT ... DO UPDATE` overwrites attributes, one current row per tail number. The FAA file is a single snapshot, so there is no history to track.

### Data quality

**What do the checks cover?** Volume (6), referential integrity (19), business rules (3) = 28. Severity: FAIL is unacceptable, WARN is explainable but documented, INFO is an observation.

**Why is there one warning?** The reconciliation check compares `fact_flight` (469,214 sampled rows) with `stg_flight_clean` (11,730,351). The gap is the documented sample, not a dropped row.

**Why sample?** The full 11.7 M-row join and two full-table sorts exhausted local disk (about 3 GB free). The sample is deterministic (`raw_id % 25 = 0`), has no LIMIT, preserves the monthly shape and covers all 20 months. The committed `07_fact_loads.sql` is the full-load script and no longer performs either sort.

**Which two tables are sampled?** `fact_flight` and `fact_aircraft_route`. Route demand, weather, all dimensions and clean staging are full loads.

**Where is revenue reconciliation (from the handout)?** Revenue is out of scope (no fare data). The equivalent accuracy check is volume reconciliation plus the route demand totals (query 7.5).

### Design and scope

**Why 2026 data when the proposal said 2025 only?** To allow like-for-like year-over-year on months 1-8. Weather and DB1B do not extend into 2026, so weather and fare YoY are not possible.

**Why 30 weather stations when the proposal said 15?** The implementation used a 30-airport list for better coverage *(the proposal wording is out of date, see section 8)*.

**Why does `project_reporting` have nothing in it?** The schema is part of the architecture; views, marts and dashboards are Phase 3 deliverables.

---

## 7. Live demo queries

Column names are taken from the DDL (`03_dw_tables.sql`, `02_staging_tables.sql`). **Run each once before the evaluation.**

**7.1 Layers and row counts**
```sql
SELECT table_schema, count(*) AS tables
FROM information_schema.tables
WHERE table_schema LIKE 'project_%'
GROUP BY table_schema;
```

**7.2 DQ results (the headline)**
```sql
SELECT check_name, severity, observed, expected, passed
FROM project_staging.dq_check_result
ORDER BY passed, check_name;
```

**7.3 Surrogate key mapping (business key to surrogate key and back)**
```sql
SELECT a.carrier_code, o.iata_code AS origin, d.iata_code AS dest,
       f.airline_key, f.origin_airport_key, f.dest_airport_key, f.dep_delay_min
FROM project_dw.fact_flight f
JOIN project_dw.dim_airline a ON a.airline_key = f.airline_key
JOIN project_dw.dim_airport o ON o.airport_key = f.origin_airport_key
JOIN project_dw.dim_airport d ON d.airport_key = f.dest_airport_key
LIMIT 5;
```

**7.4 Unknown member and orphan check**
```sql
SELECT * FROM project_dw.dim_airline WHERE airline_key = -1;

SELECT count(*) AS orphans              -- expected 0
FROM project_dw.fact_flight f
LEFT JOIN project_dw.dim_airline a ON a.airline_key = f.airline_key
WHERE a.airline_key IS NULL;
```

**7.5 Accuracy: route demand totals reconcile (2025)**
```sql
SELECT
 (SELECT sum(passengers) FROM project_staging.stg_route_demand_clean
   WHERE month_start_date < DATE '2026-01-01') AS staging_2025,
 (SELECT sum(passengers) FROM project_dw.fact_route_demand
   WHERE date_key BETWEEN 20250101 AND 20251231) AS fact_2025;
-- reports show 845,242,741 for 2025
```

**7.6 Completeness: missing values in the flight fact**
```sql
SELECT count(*) AS total_rows,
       count(*) FILTER (WHERE dep_delay_min IS NULL AND NOT is_cancelled) AS null_dep_delay_non_cancelled,
       count(*) FILTER (WHERE arr_delay_min IS NULL AND NOT is_cancelled AND NOT is_diverted) AS null_arr_delay_non_cancelled,
       count(*) FILTER (WHERE is_cancelled AND (dep_delay_min IS NOT NULL OR arr_delay_min IS NOT NULL)) AS cancelled_with_delay  -- expected 0
FROM project_dw.fact_flight;
```

**7.7 Partition pruning**
```sql
EXPLAIN SELECT count(*) FROM project_dw.fact_flight
WHERE date_key BETWEEN 20250701 AND 20250731;
-- plan should touch only fact_flight_2025_07
```

**7.8 Audit trail** (populated by `08`: one batch, 7 staging steps)
```sql
SELECT batch_id, status, started_at, finished_at FROM project_staging.etl_batch;
SELECT step_name, target_table, rows_inserted, status
FROM project_staging.etl_run_log ORDER BY run_id;
SELECT source_table, reject_reason, count(*) FROM project_staging.stg_rejected_rows GROUP BY 1, 2;  -- empty in this run
```

Do **not** run `99_reset_database.sql` during the demo; it drops all three schemas.

---

## 8. Weak spots and what to do about them

| # | Weak spot | Why it matters | Suggested handling |
|---|---|---|---|
| 1 | Two facts are samples | The most obvious question | State it first, with the deterministic rule and the full-load script; the warning is documented, not hidden |
| 2 | No explicit NULL-rate check among the 28 | Handout lists "Completeness: missing values" | Show query 7.6 live, or add it to `05` before the evaluation (about 5 minutes) |
| 3 | "Remove duplicates" is not done on flights | Handout lists it as a staging transformation | Accurate answer: each flight row is its own event, so flights are not de-duplicated. Duplicates are handled where they matter: dimensions (`GROUP BY` natural key plus UNIQUE), route demand (summed), weather (averaged per hour), aircraft-route (`DISTINCT` plus `ON CONFLICT DO NOTHING`) |
| 4 | Stale wording in docs | A careful evaluator will spot contradictions | See list below |
| 5 | Weather condition dimension has only CLEAR / PRECIP (plus Unknown) | Design listed Clear, Rain, Snow, Fog, Storm and visibility bands | Explain it as a simplification from packed NOAA fields; weather also stays UTC, rounded to the hour |
| 6 | Empty `project_reporting` | Architecture in the handout ends at reporting | Say views are Phase 3; optionally add 2 simple views (monthly delay, route load factor) beforehand |
| 7 | Proposal says one year and 15 airports | Implementation is 2025-01 to 2026-08 and 30 stations | Update the proposal wording or be ready to explain it as a deliberate upgrade |
| 8 | Hardcoded CSV path in `08_staging_loads.sql` (`C:\Projects\DWBI-Project`) | Breaks if run on another machine | Edit the path before any live run |
| 9 | Text standardisation is `btrim()` and type casts only | Handout example is `" lahore "` / `"LAHORE"` to `Lahore` (case standardisation) | Say source codes are already upper case; or add `upper(btrim())` for codes and `initcap()` for city and airport names in `08` before the evaluation |
| 10 | `08` appends to raw tables on every run | A second run doubles raw rows, clean rows, rejects and audit rows | Do not re-run `08` live; if needed, re-run `02` first |
| 11 | Audit log covers staging only (7 rows, no `rows_read` or `rows_rejected`) | ETL is the biggest mark component | Show `etl_batch`, the 7 log rows and `stg_rejected_rows`; mention that dimension and fact steps are logged through `etl_batch_id` on each fact row |
| 12 | `dim_weather_condition` visibility band is computed from `max(visibility_m)` per condition code | A band per condition is not meaningful, and there are only 2 real conditions (CLEAR, PRECIP) | Describe it as a simplification; do not claim it classifies visibility per observation |
| 13 | Weather fact picks `min(weather_condition_key)` across an hour | An hour with mixed readings takes the lowest key, not the "worst" condition | Mention only if asked: it is a documented simplification |
| 14 | Python skips rows with a blank `FlightDate` (flights) or blank `DATE` (weather) before staging | Those rows never reach `stg_*_raw`, so they cannot appear in `stg_rejected_rows`; "0 rejected" is measured on staged rows | Say it plainly if asked: blank-key rows (typically empty lines) are dropped at file-read time; all staged rows are accounted for |

**Stale wording — status as of 2026-11-20 (first three items are now handled):**
- `SUBMISSION_REPORT.md` section 2 still shows `Cancelled = 0` in the raw source table, but a note has been added explaining that it predates the flag fix and pointing to the corrected warehouse counts (206,801 full source / 8,229 sample). Fine as-is.
- `PROJECT_CONTEXT.md` has been updated: full Phase 2 file list, correct run order, and Phase 2 marked complete and validated. Its `dw` versus `project_dw` naming note remains and is intentional.
- All "19 months" wording has been corrected to **20 months** across the README, both reports, `SUBMISSION_REPORT.md` and `reference.md`. The regenerated PDFs use 20 months too.
- Data Cleaning Report section 3.2 mentions `ON CONFLICT DO UPDATE`, but `SUBMISSION_REPORT.md` says fact loads now aggregate with `GROUP BY` instead. The generated PDF repeats the old wording. Only worth fixing if the PDF is regenerated; otherwise explain it as the original reason for the filter.
- Data Cleaning Report section 3.3 says "first 3 characters" of the file name, but the example `KATL` is 4 characters. The script takes the text before the first underscore (`path.name.split("_")[0]`); the report should say that. The generated Cleaning Report PDF repeats the markdown wording. Answer verbally if asked.
- The comment in `08_staging_loads.sql` (T-100 class filter) still says `ON CONFLICT DO UPDATE`; `07` now uses `GROUP BY` sums. Historical wording, safe to explain.
- The Cleaning Report flag rule shows `cancelled = '1'`; `08` now casts to numeric first (`coalesce(nullif(btrim(cancelled),'')::numeric,0) = 1`). Historical wording, safe to explain.
- The proposal lists "Python/Pandas" for ingestion and cleaning; the script uses only the standard library (`csv`, `zipfile`). Say it was a deliberate choice for streaming 11.7 M rows.

---

## 9. Pre-evaluation checklist

- [x] PostgreSQL running, `aviation_dw` reachable, all 7.x queries tested (2026-11-20: all eight ran successfully; partition pruning confirmed)
- [x] `dq_check_result` freshly populated (27 pass / 1 warn / 0 fail)
- [ ] Both PDFs and the repo open; GitHub link works
- [ ] Section 3 numbers memorised, especially 469,214 and 27 / 1 / 0
- [ ] Explanation of the sample ready in two sentences
- [x] Fixes from section 8 applied, or answers prepared; live audit state also restored (`etl_batch` = SUCCESS, 7 `etl_run_log` rows)
- [x] Do not re-run `08` or `99` during the demo
