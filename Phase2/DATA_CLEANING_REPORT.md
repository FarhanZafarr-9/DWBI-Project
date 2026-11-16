# Phase 2 — Data Cleaning Report

**Project:** Null Pointers — Aviation Reliability & Performance Data Warehouse (DL3004)
**Scope:** Phase 1 raw sources → `project_staging` raw → `project_staging` clean
**Scripts:** `Phase1/02_Data_Pack/scripts/05_prepare_staging.py`, `Phase2/08_staging_loads.sql`
**Status:** See the results table at the end of this document.

---

## 1. Purpose

The raw sources are delivered in incompatible formats (BTS zipped CSVs, NOAA packed
meteorology strings, fixed FAA registry extracts, generated calendar CSVs). This
stage normalises them into typed, consistent staging tables before any dimension or
fact is loaded. No cleaning is applied inside the warehouse layer.

---

## 2. Source inventory (verified before load)

| Raw source | Files | Rows read | Format / notes |
|---|---:|---:|---|
| BTS On-Time Performance 2025 | 12 zips | 7,001,619 | 110 columns;Reporting_Airline, FlightDate, delay fields |
| BTS On-Time Performance 2026 | 8 zips | 4,728,732 | Jan–Aug only (latest published) |
| BTS T-100 Domestic Segment 2025 | 1 zip | 458,768 | `T_T100D_SEGMENT_ALL_CARRIER.csv`; 4 service classes |
| BTS T-100 Domestic Segment 2026 | 1 zip | 307,438 | Jan–Aug only |
| NOAA Global Hourly (ISD) | 30 CSVs | 264,364 | Packed `TMP`, `VIS`, `WND`, `AA1`, `AW1`, `MW1` fields |
| FAA MASTER | 1 txt | 319,417 | N-NUMBER omits the `N` prefix |
| FAA ACFTREF | 1 txt | 94,216 | Aircraft manufacturer/model reference |
| Airport seed | 1 CSV | 2,036 | Generated from OurAirports + OpenFlights |
| Holiday calendar | 2 CSVs | 22 | 11 federal holidays per year, 2025–2026 |

**Total flight rows read: 11,730,351. Total T-100 rows read: 766,206.**

---

## 3. Cleaning rules applied

### 3.1 Flight staging (`stg_flight_raw` → `stg_flight_clean`)

| Rule | Implementation | Reason |
|---|---|---|
| Date validation | `flight_date` must match `YYYY-MM-DD` | Reject malformed dates before `::date` cast |
| Key completeness | `reporting_airline`, `origin`, `dest` must be non-empty | These are mandatory fact foreign keys |
| Text trimming | `btrim()` on every field | BTS exports pad some columns |
| Delay measures | Numeric strings → `SMALLINT` via `NULLIF`; blanks → `NULL` | Preserve "not reported" as NULL, not zero |
| Departure hour | `lpad(crs_dep_time,4,'0')::int / 100` | BTS times are `830`, `45`, `0` etc. |
| Flags | `cancelled='1'`, `diverted='1'` → boolean | Standardise 0/1 to true/false |
| Tail numbers | `NULLIF(...,'')`; `N` prefix added later to FAA | Match BTS `N12345` to FAA `12345` |
| Cancellation code | Blank → `NULL`, else `CHAR(1)` | Optional attribute |

Rejected flight rows are written to `project_staging.stg_rejected_rows` with the
reason `missing key field or malformed flight date` and the complete source row as
JSON, so nothing is silently discarded.

### 3.2 Route demand (`stg_route_demand_raw` → `stg_route_demand_clean`)

| Rule | Implementation | Reason |
|---|---|---|
| ZIP member selection | Skip `Documentation.csv`, read only `T_T100D_SEGMENT_ALL_CARRIER.csv` | The zip includes a 45-row field-description file |
| Header mapping | `CLASS` → `service_class`; all other names matched case/underscore-insensitively | T-100 uses different header casing |
| Service class filter | **Keep `CLASS = 'F'` only** | `F`, `L`, `P`, `G` all exist; only `F` carries the passenger/seat totals. The other classes would overwrite the route fact with near-zero values because of `ON CONFLICT DO UPDATE` |
| Monthly grain | `make_date(year, month, 1)` | Fact grain is one row per carrier–route–month |
| Numeric parsing | Decimal strings such as `150000.00` accepted, cast via `::numeric::int` | T-100 exports integers with two decimal places |
| Key completeness | carrier, origin, dest must be non-empty | Mandatory fact foreign keys |

### 3.3 Weather (`stg_weather_raw` → `stg_weather_clean`)

| Rule | Implementation | Reason |
|---|---|---|
| Timestamp validation | Must match `YYYY-MM-DDTHH:MM:SS` | NOAA occasionally emits malformed observations |
| Station code | First 3 characters of filename, e.g. `KATL_2025.csv` → `KATL` | ICAO code used for the airport join |
| Packed fields | `TMP` split on comma → `numeric/10` (°C) | NOAA stores `+0050,1` = 5.0 °C |
| Visibility | `VIS` first token → integer metres | `016000,1` = 16,000 m |
| Wind speed | `WND` 4th token → `numeric/10` m/s | `310,1,N,0093,1` → 9.3 m/s |
| Precipitation | `AA1` 3rd token → `numeric/10` mm | One-hour precipitation amount |
| Condition | `PRECIP` if `AW1`/`MW1` present, else `CLEAR` | Simple derived weather condition |
| Time zone note | Timestamps remain UTC at this stage; local-time conversion is a documented downstream requirement | Flights are local time |

### 3.4 Aircraft, airport, airline, holiday

- **Aircraft:** FAA `N-NUMBER` prefixed with `N`; joined to `ACFTREF` on `MFR MDL CODE`
  = `CODE`; manufacturer, model, engine type and year built trimmed; malformed years
  become `NULL`.
- **Airport:** IATA code must be exactly 3 characters and the name non-empty;
  `state`/`region`/`time_zone` default to `XX`/`Unknown`; latitude, longitude and
  elevation validated by regex before numeric cast.
- **Airline:** Carrier code length 2–3; derived from the distinct
  `Reporting_Airline` codes in the On-Time files (14 carriers).
- **Holiday:** Only rows with `is_holiday=TRUE` and a non-empty name are kept.

---

## 4. Findings and limitations

1. **T-100 service classes matter.** Raw 2025 rows by class were `F` 359,198,
   `L` 54,969, `G` 34,909, `P` 9,692. Class `F` accounted for ~845 M passengers and
   ~1.07 B seats; the other classes together contributed under 0.5 %. Filtering is
   therefore both correct and materially important.
2. **Decimal-formatted integers.** T-100 numeric columns are exported as `0.00` /
   `150000.00`. An integer-only regex would have rejected every row; the clean SQL
   was corrected to accept decimals before casting.
3. **Documentation file in the ZIP.** The T-100 archive contains a field-description
   CSV that would otherwise create 45 junk route rows.
4. **Coverage mismatch.** On-Time 2026 and T-100 2026 stop at August; NOAA weather
   stops 2025-08-27; DB1B stops 2025 Q2. Year-over-year comparisons must use M1–M8.
5. **Weather time zone.** Weather observations are UTC and irregularly spaced; the
   warehouse fact rounds to the hour. A local-time conversion remains a known
   modelling simplification.
6. **No destructive filtering of flights.** Only rows missing mandatory keys or with
   malformed dates are rejected; all other source rows are retained.
7. **BTS flag format.** The `Cancelled` / `Diverted` CSV columns are exported as
   `0.00` / `1.00`, not `0` / `1`. The initial string comparison `= '1'` therefore
   classified every row as not cancelled. `08_staging_loads.sql` was corrected to
   cast the value to numeric before comparison. The validation run recovered the
   206,801 cancelled flights from the populated `CancellationCode` column, and the
   corrected SQL is what future full reloads will use.

---

## 5. Load results

Figures from the validation run on the isolated PostgreSQL 18 cluster (`aviation_dw`,
port 5433). The `stg_rejected_rows` table is empty — no source row failed the
mandatory-key or date-format rules.

| Staging table | Raw rows | Rows after cleaning | Rejected |
|---|---:|---:|---:|
| `stg_flight_clean` | 11,730,351 | 11,730,351 | 0 |
| `stg_route_demand_clean` | 766,206 | 601,435 | 0 |
| `stg_weather_clean` | 264,364 | 264,364 | 0 |
| `stg_aircraft_clean` | 319,417 (+ 94,216 ACFTREF) | 319,417 | 0 |
| `stg_airport_clean` | 2,036 | 2,036 | 0 |
| `stg_airline_clean` | 14 | 14 | 0 |
| `stg_holiday_clean` | 22 | 22 | 0 |

The route-demand reduction from 766,206 to 601,435 is the intended `CLASS = 'F'`
filter (2025: 359,198 rows; 2026: 242,237 rows), not a rejection.

The following corrections were applied during validation and are reflected in the
committed scripts:

- `08_staging_loads.sql`: numeric cast for `Cancelled` / `Diverted` flags.
- `08_staging_loads.sql`: decimal-string support for T-100 numeric columns.
- `05_prepare_staging.py`: skip `Documentation.csv` inside T-100 zips.
