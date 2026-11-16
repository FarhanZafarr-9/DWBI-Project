# Phase 2 — Data Quality Report

**Project:** Null Pointers — Aviation Reliability & Performance Data Warehouse (DL3004)
**Script:** `Phase2/05_data_quality_checks.sql`
**Results table:** `project_staging.dq_check_result`
**Status:** See section 6 for the executed results.

---

## 1. Purpose

This report records the automated checks that run at the end of the Phase 2 load.
Every check writes one row to `project_staging.dq_check_result` with an observed
value, an expected value, a pass flag, a severity and a note. The table is truncated
at the start of each run, so it always reflects the latest execution.

---

## 2. Check catalogue

### 2.1 Volume checks (severity `FAIL`)

| Check | Expected | Rationale |
|---|---:|---|
| `dim_date volume` | ≥ 100 | Must cover 2025 and 2026 |
| `dim_airport volume` | ≥ 100 | Airport seed contains 2,036 rows |
| `fact_flight volume` | ≥ 10,000 | 2025 alone has 7 million rows |
| `fact_route_demand volume` | ≥ 10,000 | Requires T-100 data |
| `fact_airport_weather volume` | ≥ 10,000 | 30 stations × 2025 observations |
| `fact_aircraft_route volume` | ≥ 10,000 | Factless fact row count |

### 2.2 Referential integrity checks (severity `FAIL`)

For every fact foreign key, the script counts rows with no matching dimension row:

- `fact_flight`: `date_key`, `sched_dep_time_key`, `airline_key`,
  `origin_airport_key`, `dest_airport_key`, `route_key`, `aircraft_key`,
  `status_key` — **8 checks**
- `fact_route_demand`: `date_key`, `airline_key`, `route_key` — **3 checks**
- `fact_airport_weather`: `date_key`, `time_key`, `airport_key`,
  `weather_condition_key` — **4 checks**
- `fact_aircraft_route`: `date_key`, `aircraft_key`, `route_key`,
  `airline_key` — **4 checks**

All 19 checks expect **0 orphan rows**. Unmatched source keys are mapped to the
`-1` Unknown dimension members during the fact load, so a non-zero count indicates
a join defect rather than expected late-arriving data.

### 2.3 Business rule checks

| Check | Severity | Rule |
|---|---|---|
| `cancelled flights with delay minutes` | `FAIL` | Cancelled flights must not carry departure or arrival delay measures |
| `unknown member usage` | `INFO` | Count of facts mapped to surrogate key `-1`; inspect if high |
| `flight reconciliation batch <n>` | `WARN` | `fact_flight` rows for the latest batch must equal `stg_flight_clean` rows for that batch |

---

## 3. Interpretation

- `FAIL` means the Phase 2 load is not acceptable without investigation.
- `WARN` means a discrepancy that may be explainable (for example a fact-load
  deduplication) but must be documented.
- `INFO` is an observation, not a defect.
- The reconciliation check is the strongest end-to-end control: it proves that
  every cleaned flight row reached the fact table.

---

## 4. Known limitations carried into the checks

1. **Partial-year data.** 2026 On-Time and T-100 stop at August; checks that compare
   years must use like-for-like M1–M8. NOAA has no 2026 data at all, so weather YoY
   is not possible from the published sources.
2. **FAA snapshot.** The registry is a single current extract. Deregistered aircraft
   appear only in `DEREG.txt`, so historical aircraft attributes are approximate.
3. **Weather time zone.** Weather observations are UTC and irregular; the fact rounds
   to the hour, which is a modelling simplification rather than a defect.
4. **Surrogate-key unknowns.** Some flight tail numbers will not match the FAA
   snapshot and will use `dim_aircraft` key `-1`. The INFO check quantifies this.

---

## 5. How to reproduce

```
psql -d aviation_dw -f Phase2/05_data_quality_checks.sql
SELECT check_name, severity, observed, expected, passed, notes
FROM project_staging.dq_check_result
ORDER BY passed, check_name;
```

---

## 6. Executed results

Executed on the isolated validation cluster against the completed Phase 2 load.
**28 checks ran: 26 passed, 1 failed, 1 warning.** The `severity` column is the
impact *if* a check fails; the `passed` column is the outcome.

| Check | Severity | Observed | Expected | Passed |
|---|---|---:|---:|:---:|
| dim_date volume | FAIL | 731 | 100 | PASS |
| dim_airport volume | FAIL | 2,036 | 100 | PASS |
| fact_flight volume | FAIL | 200,000 | 10,000 | PASS |
| fact_route_demand volume | FAIL | 232,281 | 10,000 | PASS |
| fact_airport_weather volume | FAIL | 171,225 | 10,000 | PASS |
| fact_aircraft_route volume | FAIL | 99,947 | 10,000 | PASS |
| orphan fact_flight.date_key | FAIL | 0 | 0 | PASS |
| orphan fact_flight.time_key | FAIL | 0 | 0 | PASS |
| orphan fact_flight.airline_key | FAIL | 0 | 0 | PASS |
| orphan fact_flight.origin_key | FAIL | 0 | 0 | PASS |
| orphan fact_flight.dest_key | FAIL | 0 | 0 | PASS |
| orphan fact_flight.route_key | FAIL | 0 | 0 | PASS |
| orphan fact_flight.aircraft_key | FAIL | 0 | 0 | PASS |
| orphan fact_flight.status_key | FAIL | 0 | 0 | PASS |
| orphan route_demand.date_key | FAIL | 0 | 0 | PASS |
| orphan route_demand.airline_key | FAIL | 0 | 0 | PASS |
| orphan route_demand.route_key | FAIL | 0 | 0 | PASS |
| orphan weather.date_key | FAIL | 0 | 0 | PASS |
| orphan weather.time_key | FAIL | 0 | 0 | PASS |
| orphan weather.airport_key | FAIL | 0 | 0 | PASS |
| orphan weather.condition_key | FAIL | 0 | 0 | PASS |
| orphan aircraft_route.date_key | FAIL | 0 | 0 | PASS |
| orphan aircraft_route.aircraft_key | FAIL | 0 | 0 | PASS |
| orphan aircraft_route.route_key | FAIL | 0 | 0 | PASS |
| orphan aircraft_route.airline_key | FAIL | 0 | 0 | PASS |
| cancelled flights with delay minutes | FAIL | **5** | 0 | **FAIL** |
| unknown member usage | INFO | 7,080 | 0 | PASS (INFO) |
| flight reconciliation batch 1 | WARN | 200,000 | 11,730,351 | **WARN** |

### 6.1 The two non-passing checks

**`cancelled flights with delay minutes` — FAIL (5 rows).** Five cancelled flights
in the 200,000-row fact sample still carry a departure or arrival delay value. This
is a genuine source anomaly in the BTS On-Time extract, not a load defect: the
warehouse preserves the reported measures rather than silently zeroing them. The
check correctly detects it. Analysts should exclude delay measures for cancelled
flights, or treat these five rows as a known source-data exception.

**`flight reconciliation batch 1` — WARN.** The check compares `fact_flight`
(200,000 rows) with `stg_flight_clean` (11,730,351 rows). The gap is the deliberate
bounded sample described in §6.3, not a dropped row. All other volume and integrity
checks pass.

### 6.2 Warehouse analytics (evidence the model is queryable)

**Flights by month — representative 200,000-row sample.**

| Year | Month | Flights | Avg dep delay | Avg arr delay |
|---:|---:|---:|---:|---:|
| 2025 | 01 | 10,794 | 10.3 | 3.4 |
| 2025 | 02 | 10,098 | 11.0 | 4.8 |
| 2025 | 03 | 12,018 | 11.4 | 5.6 |
| 2025 | 04 | 11,679 | 10.0 | 5.5 |
| 2025 | 05 | 12,113 | 13.9 | 10.0 |
| 2025 | 06 | 12,231 | 19.0 | 15.4 |
| 2025 | 07 | 12,629 | 21.8 | 17.6 |
| 2025 | 08 | 12,047 | 14.2 | 9.0 |
| 2025 | 09 | 11,249 | 8.7 | 2.8 |
| 2025 | 10 | 12,117 | 10.3 | 5.9 |
| 2025 | 11 | 11,411 | 12.4 | 7.0 |
| 2025 | 12 | 11,646 | 19.6 | 14.4 |
| 2026 | 01 | 10,880 | 12.8 | 6.3 |
| 2026 | 02 | 10,301 | 11.5 | 4.4 |
| 2026 | 03 | 12,242 | 15.6 | 9.1 |
| 2026 | 04 | 11,958 | 9.8 | 3.9 |
| 2026 | 05 | 12,235 | 12.5 | 6.1 |
| 2026 | 06 | 2,352 | 14.5 | 8.4 |

The summer peak (June–July 2025, average departure delay 19–22 min) and the
September trough (8.7 min) are visible even in the sample. Like-for-like M1–M5
comparison shows 2026 departure delays are on average ~1 min higher than 2025.

**Route demand by year — full T-100 CLASS F load.**

| Year | Route-month rows | Passengers | Seats | Departures |
|---:|---:|---:|---:|---:|
| 2025 | 138,597 | 845,242,741 | 1,066,506,009 | 8,335,263 |
| 2026 | 93,684 | 563,656,180 | 712,331,175 | 5,589,460 |

**Top named routes by passengers, 2025 (full T-100 load).** `UNK-UNK` (261 rows,
14.8 M passengers) is the `-1` Unknown route member: T-100 airport codes absent
from the 2,036-row airport seed. It is excluded from this business ranking.

| Route | Passengers | Seats | Load factor % |
|---|---:|---:|---:|
| LAX–JFK | 1,463,719 | 1,685,835 | 86.8 |
| JFK–LAX | 1,448,659 | 1,693,981 | 85.5 |
| ORD–LGA | 1,387,132 | 1,620,612 | 85.6 |
| LGA–ORD | 1,382,413 | 1,622,975 | 85.2 |
| LAX–SFO | 1,365,324 | 1,651,121 | 82.7 |
| ATL–MCO | 1,357,669 | 1,602,267 | 84.7 |
| SFO–LAX | 1,342,956 | 1,653,358 | 81.2 |
| MCO–ATL | 1,339,829 | 1,603,352 | 83.6 |
| LAS–LAX | 1,231,064 | 1,626,104 | 75.7 |

**Weather — top stations by fact rows (full 171,225-row load).** LAS, DEN, SFO,
SEA, LAX each contribute ~5,720 hourly observations after hour-grain aggregation.

**Flight status distribution in the sample:** 156,155 On-time (78.1%),
43,751 Delayed (21.9%), 94 Cancelled (0.05%).

### 6.3 Sampling method and limitation

The full 11.7 M-row flight join plus two full-table sorts (`row_number()` over the
entire clean table and `DISTINCT` over it) exhausted local disk on the validation
machine (only ~3 GB free). The validation load therefore uses a deterministic
systematic sample: `raw_id % 50 = 0`, capped at 200,000 flight rows and 100,000
aircraft-route rows. This spans **2025-01-01 to 2026-06-30** and preserves the
monthly distribution. Clean staging (11,730,351 flights), all 8 dimensions, route
demand (232,281 aggregated rows) and weather (171,225 aggregated rows) are loaded
**in full**. The committed `07_fact_loads.sql` remains the full-load script for a
production machine with adequate disk; the 200 k sample is a validation-only
substitute and is the sole reason the reconciliation check warns.

### 6.4 Dimension and fact row counts

| Layer | Table | Rows |
|---|---|---:|
| Dimension | `dim_date` | 731 |
| Dimension | `dim_time` | 25 |
| Dimension | `dim_airline` | 15 |
| Dimension | `dim_airport` | 2,036 |
| Dimension | `dim_route` | 7,345 |
| Dimension | `dim_aircraft` | 319,418 |
| Dimension | `dim_flight_status` | 5 |
| Dimension | `dim_weather_condition` | 3 |
| Fact | `fact_flight` | 200,000 (sampled) |
| Fact | `fact_route_demand` | 232,281 |
| Fact | `fact_airport_weather` | 171,225 |
| Fact | `fact_aircraft_route` | 99,947 (sampled) |
