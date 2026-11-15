-- Section 0: how to run
-- Run order: 00 -> 01 -> 02 -> 03 -> 04 -> 08 -> 06 -> 07 -> 05 -> (99 to reset)
-- Prerequisite: python Phase1/02_Data_Pack/scripts/05_prepare_staging.py --batch-id 1
-- This file uses psql \copy (client-side), so run it with psql, not pgAdmin:
--   psql -d <database> -f Phase2/08_staging_loads.sql
-- The CSV path below is the default checkout location; edit it if yours differs.
-- Batch 1 is the full 2025 + 2026 load; use another id for a later run.

-- Section 1: ETL batch
INSERT INTO project_staging.etl_batch (batch_id, notes)
OVERRIDING SYSTEM VALUE
VALUES (1, 'Full load of 2025 and 2026 sources')
ON CONFLICT (batch_id) DO NOTHING;

-- Section 2: raw files -> raw staging (flat CSVs from 05_prepare_staging.py)
\copy project_staging.stg_flight_raw (batch_id, source_file, flight_date, reporting_airline, tail_number, flight_number, origin, dest, crs_dep_time, dep_delay, taxi_out, taxi_in, arr_delay, cancelled, cancellation_code, diverted, air_time, distance, carrier_delay, weather_delay, nas_delay, security_delay, late_aircraft_delay) FROM 'C:/Projects/DWBI-Project/Phase1/02_Data_Pack/data/cleaned_data/stg_flight_raw.csv' WITH (FORMAT csv, HEADER true)

\copy project_staging.stg_route_demand_raw (batch_id, source_file, year, month, unique_carrier, origin, dest, passengers, seats, departures_performed, service_class) FROM 'C:/Projects/DWBI-Project/Phase1/02_Data_Pack/data/cleaned_data/stg_route_demand_raw.csv' WITH (FORMAT csv, HEADER true)

\copy project_staging.stg_weather_raw (batch_id, source_file, icao_code, observation_ts, tmp, vis, wnd, aa1, mw1, aw1) FROM 'C:/Projects/DWBI-Project/Phase1/02_Data_Pack/data/cleaned_data/stg_weather_raw.csv' WITH (FORMAT csv, HEADER true)

\copy project_staging.stg_faa_master_raw (batch_id, source_file, n_number, mfr_mdl_code, year_mfr, type_engine) FROM 'C:/Projects/DWBI-Project/Phase1/02_Data_Pack/data/cleaned_data/stg_faa_master_raw.csv' WITH (FORMAT csv, HEADER true)

\copy project_staging.stg_faa_acftref_raw (batch_id, source_file, code, mfr, model) FROM 'C:/Projects/DWBI-Project/Phase1/02_Data_Pack/data/cleaned_data/stg_faa_acftref_raw.csv' WITH (FORMAT csv, HEADER true)

\copy project_staging.stg_airport_raw (batch_id, source_file, iata_code, icao_code, airport_name, city, state, region, latitude, longitude, elevation_ft, airport_type, time_zone) FROM 'C:/Projects/DWBI-Project/Phase1/02_Data_Pack/data/cleaned_data/stg_airport_raw.csv' WITH (FORMAT csv, HEADER true)

\copy project_staging.stg_airline_raw (batch_id, source_file, carrier_code, airline_name) FROM 'C:/Projects/DWBI-Project/Phase1/02_Data_Pack/data/cleaned_data/stg_airline_raw.csv' WITH (FORMAT csv, HEADER true)

\copy project_staging.stg_holiday_raw (batch_id, source_file, holiday_date, holiday_name) FROM 'C:/Projects/DWBI-Project/Phase1/02_Data_Pack/data/cleaned_data/stg_holiday_raw.csv' WITH (FORMAT csv, HEADER true)

-- Section 3: rejected flight rows (missing key fields or malformed date)
INSERT INTO project_staging.stg_rejected_rows
    (batch_id, source_table, source_row_id, reject_reason, row_data)
SELECT r.batch_id, 'stg_flight_raw', r.raw_id,
       'missing key field or malformed flight date', to_jsonb(r)
FROM project_staging.stg_flight_raw r
WHERE btrim(r.flight_date) !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
   OR nullif(btrim(r.reporting_airline), '') IS NULL
   OR nullif(btrim(r.origin), '') IS NULL
   OR nullif(btrim(r.dest), '') IS NULL;

-- Section 4: raw -> clean staging (typed, standardized)
TRUNCATE TABLE project_staging.stg_flight_clean;

INSERT INTO project_staging.stg_flight_clean (
    raw_id, batch_id, flight_date, carrier_code, tail_number, flight_number,
    origin_code, dest_code, sched_dep_hour, dep_delay_min, arr_delay_min,
    carrier_delay_min, weather_delay_min, nas_delay_min, security_delay_min,
    late_aircraft_delay_min, taxi_out_min, taxi_in_min, air_time_min,
    distance_miles, is_cancelled, is_diverted, cancellation_code
)
SELECT
    r.raw_id, r.batch_id,
    btrim(r.flight_date)::date,
    btrim(r.reporting_airline)::varchar(3),
    nullif(btrim(r.tail_number), '')::varchar(10),
    nullif(btrim(r.flight_number), '')::varchar(6),
    btrim(r.origin)::char(3),
    btrim(r.dest)::char(3),
    CASE WHEN btrim(r.crs_dep_time) ~ '^[0-9]{1,4}$'
         THEN (lpad(btrim(r.crs_dep_time), 4, '0')::int / 100)::smallint END,
    CASE WHEN btrim(r.dep_delay) ~ '^-?[0-9]+$' THEN btrim(r.dep_delay)::smallint END,
    CASE WHEN btrim(r.arr_delay) ~ '^-?[0-9]+$' THEN btrim(r.arr_delay)::smallint END,
    CASE WHEN btrim(r.carrier_delay) ~ '^-?[0-9]+$' THEN btrim(r.carrier_delay)::smallint END,
    CASE WHEN btrim(r.weather_delay) ~ '^-?[0-9]+$' THEN btrim(r.weather_delay)::smallint END,
    CASE WHEN btrim(r.nas_delay) ~ '^-?[0-9]+$' THEN btrim(r.nas_delay)::smallint END,
    CASE WHEN btrim(r.security_delay) ~ '^-?[0-9]+$' THEN btrim(r.security_delay)::smallint END,
    CASE WHEN btrim(r.late_aircraft_delay) ~ '^-?[0-9]+$' THEN btrim(r.late_aircraft_delay)::smallint END,
    CASE WHEN btrim(r.taxi_out) ~ '^[0-9]+$' THEN btrim(r.taxi_out)::smallint END,
    CASE WHEN btrim(r.taxi_in) ~ '^[0-9]+$' THEN btrim(r.taxi_in)::smallint END,
    CASE WHEN btrim(r.air_time) ~ '^[0-9]+$' THEN btrim(r.air_time)::smallint END,
    CASE WHEN btrim(r.distance) ~ '^[0-9]+$' THEN btrim(r.distance)::int END,
    btrim(r.cancelled) = '1',
    btrim(r.diverted) = '1',
    nullif(btrim(r.cancellation_code), '')::char(1)
FROM project_staging.stg_flight_raw r
WHERE btrim(r.flight_date) ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
  AND nullif(btrim(r.reporting_airline), '') IS NOT NULL
  AND nullif(btrim(r.origin), '') IS NOT NULL
  AND nullif(btrim(r.dest), '') IS NOT NULL;

TRUNCATE TABLE project_staging.stg_route_demand_clean;

INSERT INTO project_staging.stg_route_demand_clean (
    raw_id, batch_id, month_start_date, carrier_code, origin_code,
    dest_code, passengers, seats, departures_performed
)
SELECT
    r.raw_id, r.batch_id,
    make_date(btrim(r.year)::int, btrim(r.month)::int, 1),
    btrim(r.unique_carrier)::varchar(3),
    btrim(r.origin)::char(3),
    btrim(r.dest)::char(3),
    CASE WHEN btrim(r.passengers) ~ '^[0-9]+(\.[0-9]+)?$' THEN btrim(r.passengers)::numeric::int END,
    CASE WHEN btrim(r.seats) ~ '^[0-9]+(\.[0-9]+)?$' THEN btrim(r.seats)::numeric::int END,
    CASE WHEN btrim(r.departures_performed) ~ '^[0-9]+(\.[0-9]+)?$' THEN btrim(r.departures_performed)::numeric::int END
FROM project_staging.stg_route_demand_raw r
WHERE btrim(r.year) ~ '^[0-9]{4}$'
  AND btrim(r.month) ~ '^[0-9]{1,2}$'
  AND btrim(r.month)::int BETWEEN 1 AND 12
  AND nullif(btrim(r.unique_carrier), '') IS NOT NULL
  AND nullif(btrim(r.origin), '') IS NOT NULL
  AND nullif(btrim(r.dest), '') IS NOT NULL
  -- T-100 reports the same route once per service class; F carries the
  -- passenger/seat totals. Loading all classes would overwrite the fact row
  -- with arbitrary smaller values because of ON CONFLICT DO UPDATE.
  AND btrim(r.service_class) = 'F';

TRUNCATE TABLE project_staging.stg_weather_clean;

INSERT INTO project_staging.stg_weather_clean (
    raw_id, batch_id, icao_code, observation_utc, temperature_c,
    visibility_m, wind_speed_ms, precipitation_mm, condition_code
)
SELECT
    r.raw_id, r.batch_id,
    btrim(r.icao_code)::varchar(4),
    btrim(r.observation_ts)::timestamp,
    CASE WHEN split_part(r.tmp, ',', 1) ~ '^[+-]?[0-9]+$'
         THEN split_part(r.tmp, ',', 1)::numeric / 10 END,
    CASE WHEN split_part(r.vis, ',', 1) ~ '^[0-9]+$'
         THEN split_part(r.vis, ',', 1)::int END,
    CASE WHEN split_part(r.wnd, ',', 4) ~ '^[0-9]+$'
         THEN split_part(r.wnd, ',', 4)::numeric / 10 END,
    CASE WHEN split_part(r.aa1, ',', 3) ~ '^[+-]?[0-9]+$'
         THEN split_part(r.aa1, ',', 3)::numeric / 10 END,
    CASE WHEN nullif(btrim(r.aw1), '') IS NOT NULL
           OR nullif(btrim(r.mw1), '') IS NOT NULL THEN 'PRECIP' ELSE 'CLEAR' END
FROM project_staging.stg_weather_raw r
WHERE nullif(btrim(r.icao_code), '') IS NOT NULL
  AND btrim(r.observation_ts) ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}';

TRUNCATE TABLE project_staging.stg_aircraft_clean;

-- FAA N-NUMBER omits the N prefix; add it so it matches On-Time tail numbers.
INSERT INTO project_staging.stg_aircraft_clean (
    raw_id, batch_id, tail_number, manufacturer, model, engine_type, year_built
)
SELECT
    m.raw_id, m.batch_id,
    ('N' || btrim(m.n_number))::varchar(10),
    nullif(btrim(a.mfr), '')::varchar(60),
    nullif(btrim(a.model), '')::varchar(60),
    nullif(btrim(m.type_engine), '')::varchar(30),
    CASE WHEN btrim(m.year_mfr) ~ '^[0-9]{4}$' THEN btrim(m.year_mfr)::smallint END
FROM project_staging.stg_faa_master_raw m
LEFT JOIN project_staging.stg_faa_acftref_raw a
       ON btrim(a.code) = btrim(m.mfr_mdl_code)
WHERE nullif(btrim(m.n_number), '') IS NOT NULL;

TRUNCATE TABLE project_staging.stg_airport_clean;

INSERT INTO project_staging.stg_airport_clean (
    raw_id, batch_id, iata_code, icao_code, airport_name, city, state, region,
    latitude, longitude, elevation_ft, airport_type, time_zone
)
SELECT
    r.raw_id, r.batch_id,
    btrim(r.iata_code)::char(3),
    nullif(btrim(r.icao_code), '')::varchar(4),
    btrim(r.airport_name)::varchar(120),
    nullif(btrim(r.city), '')::varchar(80),
    coalesce(nullif(btrim(r.state), '')::char(2), 'XX'),
    coalesce(nullif(btrim(r.region), '')::varchar(10), 'Unknown'),
    CASE WHEN btrim(r.latitude) ~ '^-?[0-9]+(\.[0-9]+)?$' THEN btrim(r.latitude)::numeric(9,6) END,
    CASE WHEN btrim(r.longitude) ~ '^-?[0-9]+(\.[0-9]+)?$' THEN btrim(r.longitude)::numeric(9,6) END,
    CASE WHEN btrim(r.elevation_ft) ~ '^-?[0-9]+(\.[0-9]+)?$' THEN round(btrim(r.elevation_ft)::numeric)::int END,
    nullif(btrim(r.airport_type), '')::varchar(20),
    coalesce(nullif(btrim(r.time_zone), '')::varchar(40), 'Unknown')
FROM project_staging.stg_airport_raw r
WHERE length(btrim(r.iata_code)) = 3
  AND nullif(btrim(r.airport_name), '') IS NOT NULL;

TRUNCATE TABLE project_staging.stg_airline_clean;

INSERT INTO project_staging.stg_airline_clean (raw_id, batch_id, carrier_code, airline_name)
SELECT r.raw_id, r.batch_id,
       btrim(r.carrier_code)::varchar(3),
       nullif(btrim(r.airline_name), '')::varchar(80)
FROM project_staging.stg_airline_raw r
WHERE length(btrim(r.carrier_code)) BETWEEN 2 AND 3;

TRUNCATE TABLE project_staging.stg_holiday_clean;

INSERT INTO project_staging.stg_holiday_clean (raw_id, batch_id, holiday_date, holiday_name)
SELECT r.raw_id, r.batch_id,
       btrim(r.holiday_date)::date,
       btrim(r.holiday_name)::varchar(40)
FROM project_staging.stg_holiday_raw r
WHERE btrim(r.holiday_date) ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
  AND nullif(btrim(r.holiday_name), '') IS NOT NULL;

-- Section 5: audit log and close the batch
INSERT INTO project_staging.etl_run_log
    (batch_id, step_name, target_table, rows_inserted, status, finished_at)
SELECT 1, 'load stg_flight_clean',      'project_staging.stg_flight_clean',      count(*), 'SUCCESS', now() FROM project_staging.stg_flight_clean
UNION ALL SELECT 1, 'load stg_route_demand_clean', 'project_staging.stg_route_demand_clean', count(*), 'SUCCESS', now() FROM project_staging.stg_route_demand_clean
UNION ALL SELECT 1, 'load stg_weather_clean',      'project_staging.stg_weather_clean',      count(*), 'SUCCESS', now() FROM project_staging.stg_weather_clean
UNION ALL SELECT 1, 'load stg_aircraft_clean',    'project_staging.stg_aircraft_clean',    count(*), 'SUCCESS', now() FROM project_staging.stg_aircraft_clean
UNION ALL SELECT 1, 'load stg_airport_clean',     'project_staging.stg_airport_clean',     count(*), 'SUCCESS', now() FROM project_staging.stg_airport_clean
UNION ALL SELECT 1, 'load stg_airline_clean',     'project_staging.stg_airline_clean',     count(*), 'SUCCESS', now() FROM project_staging.stg_airline_clean
UNION ALL SELECT 1, 'load stg_holiday_clean',     'project_staging.stg_holiday_clean',     count(*), 'SUCCESS', now() FROM project_staging.stg_holiday_clean;

UPDATE project_staging.etl_batch
SET finished_at = now(), status = 'SUCCESS'
WHERE batch_id = 1;
