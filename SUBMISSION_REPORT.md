# DWBI Project - Phase 2 Load & Data Quality Report

Generated: 2026-11-17 23:51:50

## 1. Source files loaded into raw staging

| Raw staging table | Rows |
|---|---:|
| stg_flight_raw | 11,730,351 |
| stg_route_demand_raw | 766,206 |
| stg_weather_raw | 264,364 |
| stg_faa_master_raw | 319,417 |
| stg_faa_acftref_raw | 94,216 |
| stg_airport_raw | 2,036 |
| stg_airline_raw | 14 |
| stg_holiday_raw | 22 |

## 2. Flights by year and month (source data)

| Year | Month | Flights | Cancelled | Diverted | Avg dep delay (min) |
|---:|---:|---:|---:|---:|---:|
| 2025 | 01 | 539747 | 0 | 0 | 10.3 |
| 2025 | 02 | 504884 | 0 | 0 | 11.7 |
| 2025 | 03 | 600872 | 0 | 0 | 11.2 |
| 2025 | 04 | 583950 | 0 | 0 | 10.4 |
| 2025 | 05 | 605648 | 0 | 0 | 14.2 |
| 2025 | 06 | 611575 | 0 | 0 | 19.3 |
| 2025 | 07 | 631428 | 0 | 0 | 21.5 |
| 2025 | 08 | 602378 | 0 | 0 | 14.3 |
| 2025 | 09 | 562439 | 0 | 0 | 8.1 |
| 2025 | 10 | 605844 | 0 | 0 | 10.3 |
| 2025 | 11 | 570550 | 0 | 0 | 11.7 |
| 2025 | 12 | 582304 | 0 | 0 | 18.3 |
| 2026 | 01 | 544003 | 0 | 0 | 13.1 |
| 2026 | 02 | 515037 | 0 | 0 | 11.4 |
| 2026 | 03 | 612102 | 0 | 0 | 17.0 |
| 2026 | 04 | 597919 | 0 | 0 | 10.7 |
| 2026 | 05 | 611735 | 0 | 0 | 12.6 |
| 2026 | 06 | 607577 | 0 | 0 | 17.6 |
| 2026 | 07 | 631970 | 0 | 0 | 21.4 |
| 2026 | 08 | 608389 | 0 | 0 | 18.7 |

## 3. Route demand by year (T-100, CLASS = F)

| Year | Route-month rows | Passengers | Seats | Departures |
|---:|---:|---:|---:|---:|
| 2025 | 359198 | 845242741 | 1066506009 | 8335263 |
| 2026 | 242237 | 563656180 | 712331175 | 5589460 |

## 4. Top 10 routes by passengers (T-100, 2025, CLASS = F)

| Origin | Dest | Passengers | Seats | Load factor % |
|---|---|---:|---:|---:|
| LAX | JFK | 1463719 | 1685835 | 86.8 |
| JFK | LAX | 1448659 | 1693981 | 85.5 |
| ORD | LGA | 1387132 | 1620612 | 85.6 |
| LGA | ORD | 1382413 | 1622975 | 85.2 |
| LAX | SFO | 1365324 | 1651121 | 82.7 |
| ATL | MCO | 1357669 | 1602267 | 84.7 |
| SFO | LAX | 1342956 | 1653358 | 81.2 |
| MCO | ATL | 1339829 | 1603352 | 83.6 |
| LAS | LAX | 1231064 | 1626104 | 75.7 |
| DEN | PHX | 1198989 | 1544934 | 77.6 |

## 5. Weather observations

| Station | Observations |
|---|---:|
| KDTW | 9943 |
| KPHL | 9720 |
| KDCA | 9658 |
| KSAN | 9636 |
| KDEN | 9224 |
| KBOS | 9156 |
| KSEA | 9100 |
| KLAX | 9082 |
| KORD | 9049 |
| KTPA | 9032 |

## 6. Notes

- Raw data is gitignored; only reference CSVs and SQL are version-controlled.
- Like-for-like YoY: compare 2025 M1-M8 with 2026 M1-M8 (2026 data ends August).
- T-100 keeps only CLASS = 'F'; other service classes do not carry passenger totals.
- Load status: all 8 raw staging tables, all clean staging tables, all 8 dimensions and all 4 fact tables were loaded on the isolated validation cluster. Raw and clean staging plus dimensions and two facts are full; `fact_flight` and `fact_aircraft_route` use deterministic systematic samples (`raw_id % 25 = 0`, ~469k/~100k rows, no `LIMIT`) that cover all 19 published months, 2025-01 to 2026-08. The full 11.7M-row join exhausted local disk. See §7 and `Phase2/DATA_QUALITY_REPORT.md` for the DQ results and the sampling limitation.
- BTS `Cancelled` / `Diverted` flags are exported as `0.00` / `1.00`; `08_staging_loads.sql` was corrected to cast to numeric before comparison. The 206,801 cancelled flights were recovered from `CancellationCode` during validation.
- Fact loads aggregate duplicate route/weather keys with `GROUP BY` instead of `ON CONFLICT DO UPDATE`, and clear delay measures on cancelled flights. The unnecessary `row_number()` sort over 11.7M rows was removed.

## 7. Phase 2 warehouse validation results

| Layer | Table | Rows |
|---|---|---:|
| Clean | stg_flight_clean | 11,730,351 |
| Clean | stg_route_demand_clean | 601,435 |
| Clean | stg_weather_clean | 264,364 |
| Clean | stg_aircraft_clean | 319,417 |
| Clean | stg_airport_clean | 2,036 |
| Clean | stg_airline_clean | 14 |
| Clean | stg_holiday_clean | 22 |
| DW | dim_date / dim_time / dim_airline / dim_airport | 731 / 25 / 15 / 2,036 |
| DW | dim_route / dim_aircraft / dim_flight_status / dim_weather_condition | 7,345 / 319,418 / 5 / 3 |
| DW | fact_flight (sampled, 19 months) | 469,214 |
| DW | fact_route_demand | 232,281 |
| DW | fact_airport_weather | 171,225 |
| DW | fact_aircraft_route (sampled) | 99,950 |

**Data quality:** 28 automated checks ran; 27 passed and 1 warning (flight
reconciliation reflects the deliberate fact sample). The cancelled-flight delay
anomaly found in the first run was resolved by nulling delay measures for
cancelled flights in the fact load. All 19 referential integrity checks returned
0 orphan rows; 16,448 facts use the `-1` Unknown member (INFO). The sampled flight
fact covers all 19 published months, so the monthly trend no longer stops at June.

Detailed reports: `Phase2/DATA_CLEANING_REPORT.md` and
`Phase2/DATA_QUALITY_REPORT.md`.


