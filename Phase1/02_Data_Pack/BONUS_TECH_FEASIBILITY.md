# Bonus Technologies from the Sample Architecture - Feasibility

All options below run on free tools (PostgreSQL, Python/Pandas, Power BI Desktop). The handout does not state the bonus marking scheme, so confirm with your instructor which items count.

| # | Technology (from sample) | Our plan | Feasibility | Effort |
|---|---|---|---|---|
| 1 | Medallion layers (Bronze / Silver / Gold) | PostgreSQL schemas `bronze`, `silver`, `dw`, `gold`. Bronze = raw staging. | High | Low |
| 2 | Data quality checks (NULL, type, duplicate, business rule, referential) | SQL checks and Python validation per load | High | Low |
| 3 | Reject / quarantine table (reason, source + batch ID, timestamp) | `silver.rejected_rows` | High | Low |
| 4 | Audit, monitoring, reconciliation (ETL run log, rows read / inserted / rejected, source vs DW) | `audit.etl_run_log` plus a reconciliation query per load | High | Low |
| 5 | Pipeline orchestration (ingest, validate, transform, load dims, load facts, build marts, test, log) | One Python runner with a function per step | High | Medium |
| 6 | Partitioning, indexes, EXPLAIN ANALYZE, performance comparison | Partition Fact_Flight by month (about 7M rows), index FKs and date, before/after timing | High | Medium |
| 7 | OLAP: ROLLUP / CUBE, window functions | PostgreSQL `ROLLUP`, `CUBE`, `RANK()`, moving averages on the 10 questions | High | Low |
| 8 | Data marts and materialized views (Gold) | Flight reliability mart, route performance mart, airport mart | High | Low |
| 9 | Late-arriving data / Unknown member | Key -1 "Unknown" for unmatched aircraft and missing weather | High | Low |
| 10 | Incremental load with watermark | Load BTS month by month using batch ID and last loaded FlightDate | High | Medium |
| 11 | Metadata and data lineage (Source to Bronze to Silver to DW to Gold to Power BI) | `metadata.lineage` table plus a lineage diagram | Medium | Medium |
| 12 | SCD Type 1 and 2 | Type 1: airport and airline attributes. Type 2: Dim_Aircraft (registrant/status). Needs two FAA snapshots or a simulated change to show history. | Medium | Medium |
| 13 | Multiple source types (API, CSV, DB, JSON) | Already CSV, TXT and ZIP from six sources. A JSON/API source is optional. | High | Low |
| 14 | Optional tools: dbt Core, Snowflake, BigQuery, Databricks | dbt Core (free, Postgres adapter) would add tests and lineage docs. Others add setup time without new concepts. | Low to Medium | High |

## Suggested order
- **Do first (cheap, high value):** 1, 2, 3, 4, 7, 8, 9
- **Then:** 6, 10, 5
- **If time allows:** 11, 12
- **Skip unless required:** 14

## Phase mapping
- **Phase 2 (Implementation):** 1-6, 9, 10, 12
- **Phase 3 (Analytics and BI):** 7, 8, 11 and the Power BI dashboards
