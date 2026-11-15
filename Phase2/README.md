# Phase 2 - Database implementation

All SQL is PostgreSQL. Nothing in this folder executes itself; run the scripts in the order below.

## Run order

| # | File | Purpose |
|---|---|---|
| 1 | `00_create_database.sql` | Create the database |
| 2 | `01_create_schemas.sql` | `project_staging`, `project_dw`, `project_reporting` |
| 3 | `02_staging_tables.sql` | ETL audit, raw staging and clean staging tables |
| 4 | `03_dw_tables.sql` | Dimensions, facts, partitions and indexes |
| 5 | `04_seed_dimensions.sql` | `-1` Unknown members in every dimension |
| 6 | `08_staging_loads.sql` | Load raw sources into staging, then clean them |
| 7 | `06_dimension_loads.sql` | Clean staging -> dimensions |
| 8 | `07_fact_loads.sql` | Clean staging -> facts |
| 9 | `05_data_quality_checks.sql` | Write results to `project_staging.dq_check_result` |
| - | `99_reset_database.sql` | Optional: drop everything and start again |

`05` is numbered earlier than `06`/`07` but must run **after** them, because
it checks the loaded data. `08` is numbered last but must run **before** `06`.
Every script is re-runnable.

## Before step 6

The raw source files are gitignored and large. Generate the flat CSVs first:

```
python Phase1/02_Data_Pack/scripts/05_prepare_staging.py --batch-id 1
```

That writes eight `stg_*_raw.csv` files into `Phase1/02_Data_Pack/data/cleaned_data/`.
`08_staging_loads.sql` loads them with psql `\copy`, so run that file with psql:

```
psql -d <database> -f Phase2/08_staging_loads.sql
```

If your checkout is not at `C:\Projects\DWBI-Project`, edit the CSV paths in that file.

## Known data gaps

- T-100 is present for 2025 (all 12 months) and 2026 (Jan-Aug). The prep script
  reads the zips from `Phase1/02_Data_Pack/data/raw_data/bts_t100/`; only
  `CLASS = 'F'` rows are loaded, because the other service classes would
  overwrite the route fact with smaller values.
- NOAA weather ends 2025-08-27; there is no 2026 weather in the bulk bucket.
- BTS On-Time 2026 ends August. Compare like-for-like months (M1-M8) year over year.
