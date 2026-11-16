-- Section 1: Date dimension (2025-2026, from generated calendar + holiday staging)
INSERT INTO project_dw.dim_date (
    date_key, full_date, day_of_week, week_of_year, month, month_name,
    quarter, year, season, is_weekend, is_holiday, holiday_name
)
SELECT
    to_char(g.d, 'YYYYMMDD')::int,
    g.d::date,
    trim(to_char(g.d, 'Day')),
    extract(week FROM g.d)::smallint,
    extract(month FROM g.d)::smallint,
    trim(to_char(g.d, 'Month')),
    extract(quarter FROM g.d)::smallint,
    extract(year FROM g.d)::smallint,
    CASE WHEN extract(month FROM g.d) IN (12, 1, 2) THEN 'Winter'
         WHEN extract(month FROM g.d) IN (3, 4, 5) THEN 'Spring'
         WHEN extract(month FROM g.d) IN (6, 7, 8) THEN 'Summer'
         ELSE 'Fall' END,
    extract(isodow FROM g.d) >= 6,
    h.holiday_name IS NOT NULL,
    h.holiday_name
FROM generate_series(DATE '2025-01-01', DATE '2026-12-31', INTERVAL '1 day') AS g(d)
LEFT JOIN (
    SELECT DISTINCT holiday_date, holiday_name
    FROM project_staging.stg_holiday_clean
    WHERE holiday_name IS NOT NULL
) h ON h.holiday_date = g.d::date
ON CONFLICT (date_key) DO UPDATE SET
    full_date = EXCLUDED.full_date,
    day_of_week = EXCLUDED.day_of_week,
    week_of_year = EXCLUDED.week_of_year,
    month = EXCLUDED.month,
    month_name = EXCLUDED.month_name,
    quarter = EXCLUDED.quarter,
    year = EXCLUDED.year,
    season = EXCLUDED.season,
    is_weekend = EXCLUDED.is_weekend,
    is_holiday = EXCLUDED.is_holiday,
    holiday_name = EXCLUDED.holiday_name;

-- Section 2: Time dimension (24 hours)
INSERT INTO project_dw.dim_time (time_key, hour_of_day, time_band, is_peak)
SELECT h::smallint,
       h::smallint,
       CASE WHEN h < 6 THEN 'Night'
            WHEN h < 12 THEN 'Morning'
            WHEN h < 18 THEN 'Afternoon'
            ELSE 'Evening' END,
       (h BETWEEN 6 AND 9 OR h BETWEEN 16 AND 19)
FROM generate_series(0, 23) AS g(h)
ON CONFLICT (time_key) DO UPDATE SET
    hour_of_day = EXCLUDED.hour_of_day,
    time_band = EXCLUDED.time_band,
    is_peak = EXCLUDED.is_peak;

-- Section 3: Airline dimension (natural key = carrier_code)
INSERT INTO project_dw.dim_airline (carrier_code, airline_name)
SELECT carrier_code, coalesce(max(airline_name), 'Unknown')
FROM project_staging.stg_airline_clean
WHERE carrier_code IS NOT NULL
GROUP BY carrier_code
ON CONFLICT (carrier_code) DO UPDATE SET
    airline_name = EXCLUDED.airline_name;

-- Section 4: Airport dimension (natural key = iata_code)
INSERT INTO project_dw.dim_airport (
    iata_code, icao_code, airport_name, city, state, region,
    latitude, longitude, elevation_ft, airport_type, time_zone
)
SELECT iata_code,
       max(icao_code),
       coalesce(max(airport_name), 'Unknown'),
       max(city),
       coalesce(max(state), 'XX'),
       coalesce(max(region), 'Unknown'),
       max(latitude),
       max(longitude),
       max(elevation_ft),
       max(airport_type),
       coalesce(max(time_zone), 'Unknown')
FROM project_staging.stg_airport_clean
WHERE iata_code IS NOT NULL
GROUP BY iata_code
ON CONFLICT (iata_code) DO UPDATE SET
    icao_code = EXCLUDED.icao_code,
    airport_name = EXCLUDED.airport_name,
    city = EXCLUDED.city,
    state = EXCLUDED.state,
    region = EXCLUDED.region,
    latitude = EXCLUDED.latitude,
    longitude = EXCLUDED.longitude,
    elevation_ft = EXCLUDED.elevation_ft,
    airport_type = EXCLUDED.airport_type,
    time_zone = EXCLUDED.time_zone;

-- Section 5: Route dimension (derived from the flight staging data)
INSERT INTO project_dw.dim_route (
    origin_code, dest_code, route_name, distance_miles, distance_band
)
SELECT origin_code,
       dest_code,
       origin_code || '-' || dest_code,
       max(distance_miles),
       CASE WHEN max(distance_miles) < 500 THEN 'Short'
            WHEN max(distance_miles) < 1500 THEN 'Medium'
            ELSE 'Long' END
FROM project_staging.stg_flight_clean
WHERE origin_code IS NOT NULL AND dest_code IS NOT NULL
GROUP BY origin_code, dest_code
ON CONFLICT (origin_code, dest_code) DO UPDATE SET
    route_name = EXCLUDED.route_name,
    distance_miles = EXCLUDED.distance_miles,
    distance_band = EXCLUDED.distance_band;

-- Section 6: Aircraft dimension (Type 1; one current row per tail number)
INSERT INTO project_dw.dim_aircraft (
    tail_number, manufacturer, model, engine_type, year_built,
    age_band, row_effective_date, row_expiry_date, is_current
)
SELECT tail_number,
       max(manufacturer),
       max(model),
       max(engine_type),
       max(year_built),
       CASE WHEN 2026 - max(year_built) < 5 THEN '0-4'
            WHEN 2026 - max(year_built) < 10 THEN '5-9'
            WHEN 2026 - max(year_built) < 20 THEN '10-19'
            ELSE '20+' END,
       CURRENT_DATE,
       NULL,
       TRUE
FROM project_staging.stg_aircraft_clean
WHERE tail_number IS NOT NULL
GROUP BY tail_number
ON CONFLICT (tail_number) WHERE is_current DO UPDATE SET
    manufacturer = EXCLUDED.manufacturer,
    model = EXCLUDED.model,
    engine_type = EXCLUDED.engine_type,
    year_built = EXCLUDED.year_built,
    age_band = EXCLUDED.age_band;

-- Section 7: Flight status junk dimension
INSERT INTO project_dw.dim_flight_status (
    status_code, flight_status, cancellation_reason, delay_category
)
SELECT * FROM (VALUES
    ('ON_TIME',   'On-time',   NULL::varchar, 'None'),
    ('DELAYED',   'Delayed',   NULL::varchar, '15+ min'),
    ('CANCELLED', 'Cancelled', 'Unknown',     'None'),
    ('DIVERTED',  'Diverted',  NULL::varchar, 'None')
) AS v(status_code, flight_status, cancellation_reason, delay_category)
ON CONFLICT (status_code) DO NOTHING;

-- Section 8: Weather condition dimension
INSERT INTO project_dw.dim_weather_condition (
    condition_code, condition, visibility_band
)
SELECT condition_code,
       CASE condition_code
            WHEN 'CLEAR' THEN 'Clear'
            WHEN 'PRECIP' THEN 'Precipitation'
            ELSE 'Unknown' END,
       CASE WHEN max(visibility_m) < 1000 THEN 'Low'
            WHEN max(visibility_m) < 5000 THEN 'Medium'
            ELSE 'High' END
FROM project_staging.stg_weather_clean
WHERE condition_code IS NOT NULL
GROUP BY condition_code
ON CONFLICT (condition_code) DO UPDATE SET
    condition = EXCLUDED.condition,
    visibility_band = EXCLUDED.visibility_band;
