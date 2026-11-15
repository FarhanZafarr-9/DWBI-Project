-- Section 1: Unknown members (surrogate key -1) for unmatched or late-arriving data.
-- Re-runnable: each insert is safe to repeat.

INSERT INTO project_dw.dim_date (
    date_key, full_date, day_of_week, week_of_year, month, month_name,
    quarter, year, season, is_weekend, is_holiday, holiday_name
) VALUES (
    -1, DATE '1900-01-01', 'Unknown', 0, 0, 'Unknown',
    0, 1900, 'None', FALSE, FALSE, NULL
)
ON CONFLICT (date_key) DO NOTHING;

INSERT INTO project_dw.dim_time (time_key, hour_of_day, time_band, is_peak)
VALUES (-1, -1, 'Unknown', FALSE)
ON CONFLICT (time_key) DO NOTHING;

INSERT INTO project_dw.dim_airline (airline_key, carrier_code, airline_name)
VALUES (-1, 'UNK', 'Unknown')
ON CONFLICT (airline_key) DO NOTHING;

INSERT INTO project_dw.dim_airport (
    airport_key, iata_code, icao_code, airport_name, city, state, region,
    latitude, longitude, elevation_ft, airport_type, time_zone
) VALUES (
    -1, 'UNK', NULL, 'Unknown', 'Unknown', 'XX', 'Unknown',
    NULL, NULL, NULL, 'Unknown', 'Unknown'
)
ON CONFLICT (airport_key) DO NOTHING;

INSERT INTO project_dw.dim_route (
    route_key, origin_code, dest_code, route_name, distance_miles, distance_band
) VALUES (
    -1, 'UNK', 'UNK', 'UNK-UNK', NULL, 'Unknown'
)
ON CONFLICT (route_key) DO NOTHING;

INSERT INTO project_dw.dim_aircraft (
    aircraft_key, tail_number, manufacturer, model, engine_type, year_built,
    age_band, row_effective_date, row_expiry_date, is_current
) VALUES (
    -1, 'UNKNOWN', 'Unknown', 'Unknown', 'Unknown', NULL,
    'Unknown', DATE '1900-01-01', NULL, TRUE
)
ON CONFLICT (tail_number) WHERE is_current DO NOTHING;

INSERT INTO project_dw.dim_flight_status (
    status_key, status_code, flight_status, cancellation_reason, delay_category
) VALUES (
    -1, 'UNK', 'Unknown', NULL, 'Unknown'
)
ON CONFLICT (status_key) DO NOTHING;

INSERT INTO project_dw.dim_weather_condition (
    weather_condition_key, condition_code, condition, visibility_band
) VALUES (
    -1, 'UNK', 'Unknown', 'Unknown'
)
ON CONFLICT (weather_condition_key) DO NOTHING;
