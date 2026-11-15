-- Section 1: fact loads from clean staging using business-key -> surrogate-key lookups.
-- Re-runnable: rows belonging to the latest ETL batch are deleted before reload.

DO $$
DECLARE
    b INT;
BEGIN
    SELECT max(batch_id) INTO b
    FROM project_staging.etl_batch
    WHERE status IN ('RUNNING', 'SUCCESS');

    IF b IS NULL THEN
        RAISE EXCEPTION 'No ETL batch found - insert one into project_staging.etl_batch first';
    END IF;

    -- ------------------------------------------------------------------ fact_flight
    DELETE FROM project_dw.fact_flight WHERE etl_batch_id = b;

    WITH src AS (
        SELECT f.*,
               row_number() OVER (
                   PARTITION BY f.flight_date, f.carrier_code, f.flight_number,
                                f.origin_code, f.dest_code, f.sched_dep_hour
                   ORDER BY f.raw_id
               ) AS rn
        FROM project_staging.stg_flight_clean f
        WHERE f.batch_id = b
    )
    INSERT INTO project_dw.fact_flight (
        date_key, sched_dep_time_key, airline_key, origin_airport_key,
        dest_airport_key, route_key, aircraft_key, status_key, flight_number,
        dep_delay_min, arr_delay_min, carrier_delay_min, weather_delay_min,
        nas_delay_min, security_delay_min, late_aircraft_delay_min,
        taxi_out_min, taxi_in_min, air_time_min, distance_miles,
        is_cancelled, is_diverted, flight_count, etl_batch_id
    )
    SELECT to_char(s.flight_date, 'YYYYMMDD')::int,
           coalesce(tm.time_key, -1),
           coalesce(al.airline_key, -1),
           coalesce(oa.airport_key, -1),
           coalesce(da.airport_key, -1),
           coalesce(rt.route_key, -1),
           coalesce(ac.aircraft_key, acn.aircraft_key, -1),
           coalesce(st.status_key, -1),
           s.flight_number,
           s.dep_delay_min, s.arr_delay_min, s.carrier_delay_min,
           s.weather_delay_min, s.nas_delay_min, s.security_delay_min,
           s.late_aircraft_delay_min, s.taxi_out_min, s.taxi_in_min,
           s.air_time_min, s.distance_miles,
           s.is_cancelled, s.is_diverted, 1, b
    FROM src s
    LEFT JOIN project_dw.dim_time tm
           ON tm.hour_of_day = s.sched_dep_hour
    LEFT JOIN project_dw.dim_airline al
           ON al.carrier_code = s.carrier_code
    LEFT JOIN project_dw.dim_airport oa
           ON oa.iata_code = s.origin_code
    LEFT JOIN project_dw.dim_airport da
           ON da.iata_code = s.dest_code
    LEFT JOIN project_dw.dim_route rt
           ON rt.origin_code = s.origin_code AND rt.dest_code = s.dest_code
    LEFT JOIN project_dw.dim_aircraft ac
           ON ac.tail_number = s.tail_number AND ac.is_current
    LEFT JOIN project_dw.dim_aircraft acn
           ON acn.tail_number = 'N' || s.tail_number AND acn.is_current
    LEFT JOIN project_dw.dim_flight_status st
           ON st.status_code = CASE WHEN s.is_cancelled THEN 'CANCELLED'
                                    WHEN s.is_diverted THEN 'DIVERTED'
                                    WHEN s.arr_delay_min >= 15 THEN 'DELAYED'
                                    ELSE 'ON_TIME' END
    WHERE s.rn = 1;

    -- ------------------------------------------------------------ fact_route_demand
    DELETE FROM project_dw.fact_route_demand WHERE etl_batch_id = b;

    INSERT INTO project_dw.fact_route_demand (
        date_key, airline_key, route_key,
        passengers, seats, departures_performed, etl_batch_id
    )
    SELECT to_char(s.month_start_date, 'YYYYMMDD')::int,
           coalesce(al.airline_key, -1),
           coalesce(rt.route_key, -1),
           s.passengers, s.seats, s.departures_performed, b
    FROM project_staging.stg_route_demand_clean s
    LEFT JOIN project_dw.dim_airline al ON al.carrier_code = s.carrier_code
    LEFT JOIN project_dw.dim_route rt
           ON rt.origin_code = s.origin_code AND rt.dest_code = s.dest_code
    WHERE s.batch_id = b
    ON CONFLICT (date_key, airline_key, route_key) DO UPDATE SET
        passengers = EXCLUDED.passengers,
        seats = EXCLUDED.seats,
        departures_performed = EXCLUDED.departures_performed,
        etl_batch_id = EXCLUDED.etl_batch_id;

    -- ---------------------------------------------------------- fact_airport_weather
    DELETE FROM project_dw.fact_airport_weather WHERE etl_batch_id = b;

    -- NOTE: staging must already have converted the UTC observation to airport local time.
    INSERT INTO project_dw.fact_airport_weather (
        date_key, time_key, airport_key, weather_condition_key,
        temperature_c, visibility_m, wind_speed_ms, precipitation_mm, etl_batch_id
    )
    SELECT to_char(s.observation_utc::date, 'YYYYMMDD')::int,
           extract(hour FROM s.observation_utc)::smallint,
           coalesce(ap.airport_key, -1),
           coalesce(wc.weather_condition_key, -1),
           s.temperature_c, s.visibility_m, s.wind_speed_ms,
           s.precipitation_mm, b
    FROM project_staging.stg_weather_clean s
    LEFT JOIN project_dw.dim_airport ap ON ap.icao_code = s.icao_code
    LEFT JOIN project_dw.dim_weather_condition wc
           ON wc.condition_code = s.condition_code
    WHERE s.batch_id = b
    ON CONFLICT (date_key, time_key, airport_key) DO UPDATE SET
        weather_condition_key = EXCLUDED.weather_condition_key,
        temperature_c = EXCLUDED.temperature_c,
        visibility_m = EXCLUDED.visibility_m,
        wind_speed_ms = EXCLUDED.wind_speed_ms,
        precipitation_mm = EXCLUDED.precipitation_mm,
        etl_batch_id = EXCLUDED.etl_batch_id;

    -- ------------------------------------------------------------ fact_aircraft_route
    DELETE FROM project_dw.fact_aircraft_route WHERE etl_batch_id = b;

    INSERT INTO project_dw.fact_aircraft_route (
        date_key, aircraft_key, route_key, airline_key, etl_batch_id
    )
    SELECT DISTINCT
           to_char(s.flight_date, 'YYYYMMDD')::int,
           coalesce(ac.aircraft_key, acn.aircraft_key, -1),
           coalesce(rt.route_key, -1),
           coalesce(al.airline_key, -1),
           b
    FROM project_staging.stg_flight_clean s
    LEFT JOIN project_dw.dim_aircraft ac
           ON ac.tail_number = s.tail_number AND ac.is_current
    LEFT JOIN project_dw.dim_aircraft acn
           ON acn.tail_number = 'N' || s.tail_number AND acn.is_current
    LEFT JOIN project_dw.dim_route rt
           ON rt.origin_code = s.origin_code AND rt.dest_code = s.dest_code
    LEFT JOIN project_dw.dim_airline al ON al.carrier_code = s.carrier_code
    WHERE s.batch_id = b
    ON CONFLICT (date_key, aircraft_key, route_key, airline_key) DO NOTHING;
END $$;
