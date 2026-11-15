-- Section 1: results table (re-runnable; each run replaces the previous results)
CREATE TABLE IF NOT EXISTS project_staging.dq_check_result (
    check_id BIGINT GENERATED ALWAYS AS IDENTITY,
    run_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    check_name VARCHAR(80) NOT NULL,
    severity VARCHAR(10) NOT NULL DEFAULT 'FAIL'
        CHECK (severity IN ('INFO', 'WARN', 'FAIL')),
    observed BIGINT NOT NULL,
    expected BIGINT,
    passed BOOLEAN NOT NULL,
    notes TEXT,
    CONSTRAINT pk_dq_check_result PRIMARY KEY (check_id)
);

TRUNCATE TABLE project_staging.dq_check_result;

-- Section 2: minimum volume checks (lab requires 100+ dimension rows, 10,000+ fact rows)
INSERT INTO project_staging.dq_check_result
    (check_name, severity, observed, expected, passed, notes)
SELECT 'dim_date volume', 'FAIL', count(*), 100,
       count(*) >= 100, 'Date dimension must cover 2025 and 2026'
FROM project_dw.dim_date
UNION ALL
SELECT 'dim_airport volume', 'FAIL', count(*), 100,
       count(*) >= 100, 'Airport seed has 2,036 rows'
FROM project_dw.dim_airport
UNION ALL
SELECT 'fact_flight volume', 'FAIL', count(*), 10000,
       count(*) >= 10000, '2025 alone has 7 million rows'
FROM project_dw.fact_flight
UNION ALL
SELECT 'fact_route_demand volume', 'FAIL', count(*), 10000,
       count(*) >= 10000, 'Requires T-100 data'
FROM project_dw.fact_route_demand
UNION ALL
SELECT 'fact_airport_weather volume', 'FAIL', count(*), 10000,
       count(*) >= 10000, '30 stations x 2025 observations'
FROM project_dw.fact_airport_weather
UNION ALL
SELECT 'fact_aircraft_route volume', 'FAIL', count(*), 10000,
       count(*) >= 10000, 'Factless fact is counted rows'
FROM project_dw.fact_aircraft_route;

-- Section 3: referential integrity - orphan facts must be zero
DO $$
DECLARE
    r RECORD;
    q TEXT;
    n BIGINT;
BEGIN
    FOR r IN
        SELECT * FROM (VALUES
            ('fact_flight.date_key',         'project_dw.fact_flight',          'date_key',              'project_dw.dim_date',             'date_key'),
            ('fact_flight.time_key',         'project_dw.fact_flight',          'sched_dep_time_key',    'project_dw.dim_time',             'time_key'),
            ('fact_flight.airline_key',      'project_dw.fact_flight',          'airline_key',           'project_dw.dim_airline',          'airline_key'),
            ('fact_flight.origin_key',       'project_dw.fact_flight',          'origin_airport_key',    'project_dw.dim_airport',          'airport_key'),
            ('fact_flight.dest_key',         'project_dw.fact_flight',          'dest_airport_key',      'project_dw.dim_airport',          'airport_key'),
            ('fact_flight.route_key',        'project_dw.fact_flight',          'route_key',             'project_dw.dim_route',            'route_key'),
            ('fact_flight.aircraft_key',     'project_dw.fact_flight',          'aircraft_key',          'project_dw.dim_aircraft',         'aircraft_key'),
            ('fact_flight.status_key',       'project_dw.fact_flight',          'status_key',            'project_dw.dim_flight_status',    'status_key'),
            ('route_demand.date_key',        'project_dw.fact_route_demand',    'date_key',              'project_dw.dim_date',             'date_key'),
            ('route_demand.airline_key',     'project_dw.fact_route_demand',    'airline_key',           'project_dw.dim_airline',          'airline_key'),
            ('route_demand.route_key',       'project_dw.fact_route_demand',    'route_key',             'project_dw.dim_route',            'route_key'),
            ('weather.date_key',             'project_dw.fact_airport_weather', 'date_key',              'project_dw.dim_date',             'date_key'),
            ('weather.time_key',             'project_dw.fact_airport_weather', 'time_key',              'project_dw.dim_time',             'time_key'),
            ('weather.airport_key',          'project_dw.fact_airport_weather', 'airport_key',           'project_dw.dim_airport',          'airport_key'),
            ('weather.condition_key',        'project_dw.fact_airport_weather', 'weather_condition_key', 'project_dw.dim_weather_condition','weather_condition_key'),
            ('aircraft_route.date_key',      'project_dw.fact_aircraft_route',  'date_key',              'project_dw.dim_date',             'date_key'),
            ('aircraft_route.aircraft_key',  'project_dw.fact_aircraft_route',  'aircraft_key',          'project_dw.dim_aircraft',         'aircraft_key'),
            ('aircraft_route.route_key',     'project_dw.fact_aircraft_route',  'route_key',             'project_dw.dim_route',            'route_key'),
            ('aircraft_route.airline_key',   'project_dw.fact_aircraft_route',  'airline_key',           'project_dw.dim_airline',          'airline_key')
        ) AS v(check_name, fact_table, fact_col, dim_table, dim_col)
    LOOP
        q := format(
            'SELECT count(*) FROM %s f LEFT JOIN %s d ON d.%I = f.%I WHERE d.%I IS NULL',
            r.fact_table, r.dim_table, r.dim_col, r.fact_col, r.dim_col
        );
        EXECUTE q INTO n;
        INSERT INTO project_staging.dq_check_result
            (check_name, severity, observed, expected, passed, notes)
        VALUES (
            'orphan ' || r.check_name, 'FAIL', n, 0, n = 0,
            'Fact rows without a matching dimension row'
        );
    END LOOP;
END $$;

-- Section 4: business rules
INSERT INTO project_staging.dq_check_result
    (check_name, severity, observed, expected, passed, notes)
SELECT 'cancelled flights with delay minutes', 'FAIL', count(*), 0,
       count(*) = 0, 'Cancelled flights must not carry delay measures'
FROM project_dw.fact_flight
WHERE is_cancelled
  AND (dep_delay_min IS NOT NULL OR arr_delay_min IS NOT NULL);

INSERT INTO project_staging.dq_check_result
    (check_name, severity, observed, expected, passed, notes)
SELECT 'unknown member usage', 'INFO', count(*), NULL, TRUE,
       'Rows mapped to surrogate key -1; inspect if high'
FROM project_dw.fact_flight
WHERE airline_key = -1 OR origin_airport_key = -1
   OR dest_airport_key = -1 OR route_key = -1 OR aircraft_key = -1;

-- Section 5: reconciliation against the latest batch
DO $$
DECLARE
    b INT;
    n_staging BIGINT;
    n_fact BIGINT;
BEGIN
    SELECT max(batch_id) INTO b FROM project_staging.etl_batch;
    IF b IS NOT NULL THEN
        SELECT count(*) INTO n_staging
        FROM project_staging.stg_flight_clean WHERE batch_id = b;
        SELECT count(*) INTO n_fact
        FROM project_dw.fact_flight WHERE etl_batch_id = b;

        INSERT INTO project_staging.dq_check_result
            (check_name, severity, observed, expected, passed, notes)
        VALUES (
            'flight reconciliation batch ' || b, 'WARN', n_fact, n_staging,
            n_fact = n_staging,
            'Fact rows versus clean staging rows for the latest batch'
        );
    END IF;
END $$;

-- Inspect results with:
-- SELECT check_name, severity, observed, expected, passed, notes
-- FROM project_staging.dq_check_result ORDER BY passed, check_name;
