-- Section 1: ETL audit tables
CREATE TABLE IF NOT EXISTS project_staging.etl_batch (
    batch_id INT GENERATED ALWAYS AS IDENTITY,
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    finished_at TIMESTAMPTZ,
    status VARCHAR(10) NOT NULL DEFAULT 'RUNNING',
    notes TEXT,
    CONSTRAINT pk_etl_batch PRIMARY KEY (batch_id),
    CONSTRAINT ck_etl_batch_status CHECK (status IN ('RUNNING', 'SUCCESS', 'FAILED'))
);

CREATE TABLE IF NOT EXISTS project_staging.etl_run_log (
    run_id BIGINT GENERATED ALWAYS AS IDENTITY,
    batch_id INT NOT NULL,
    step_name VARCHAR(60) NOT NULL,
    source_table VARCHAR(80),
    target_table VARCHAR(80),
    rows_read INT,
    rows_inserted INT,
    rows_updated INT,
    rows_rejected INT,
    status VARCHAR(10) NOT NULL DEFAULT 'RUNNING',
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    finished_at TIMESTAMPTZ,
    message TEXT,
    CONSTRAINT pk_etl_run_log PRIMARY KEY (run_id),
    CONSTRAINT fk_etl_run_log_batch FOREIGN KEY (batch_id) REFERENCES project_staging.etl_batch (batch_id),
    CONSTRAINT ck_etl_run_log_status CHECK (status IN ('RUNNING', 'SUCCESS', 'FAILED'))
);

CREATE TABLE IF NOT EXISTS project_staging.stg_rejected_rows (
    reject_id BIGINT GENERATED ALWAYS AS IDENTITY,
    batch_id INT NOT NULL,
    source_table VARCHAR(80) NOT NULL,
    source_row_id BIGINT,
    reject_reason VARCHAR(120) NOT NULL,
    row_data JSONB,
    rejected_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT pk_stg_rejected_rows PRIMARY KEY (reject_id)
);

-- Section 2: Raw staging tables (text, as received)
DROP TABLE IF EXISTS project_staging.stg_flight_raw;
CREATE TABLE project_staging.stg_flight_raw (
    raw_id BIGINT GENERATED ALWAYS AS IDENTITY,
    batch_id INT NOT NULL,
    source_file VARCHAR(120),
    flight_date TEXT,
    reporting_airline TEXT,
    tail_number TEXT,
    flight_number TEXT,
    origin TEXT,
    dest TEXT,
    crs_dep_time TEXT,
    dep_delay TEXT,
    taxi_out TEXT,
    taxi_in TEXT,
    arr_delay TEXT,
    cancelled TEXT,
    cancellation_code TEXT,
    diverted TEXT,
    air_time TEXT,
    distance TEXT,
    carrier_delay TEXT,
    weather_delay TEXT,
    nas_delay TEXT,
    security_delay TEXT,
    late_aircraft_delay TEXT,
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT pk_stg_flight_raw PRIMARY KEY (raw_id)
);

DROP TABLE IF EXISTS project_staging.stg_route_demand_raw;
CREATE TABLE project_staging.stg_route_demand_raw (
    raw_id BIGINT GENERATED ALWAYS AS IDENTITY,
    batch_id INT NOT NULL,
    source_file VARCHAR(120),
    year TEXT,
    month TEXT,
    unique_carrier TEXT,
    origin TEXT,
    dest TEXT,
    passengers TEXT,
    seats TEXT,
    departures_performed TEXT,
    service_class TEXT,
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT pk_stg_route_demand_raw PRIMARY KEY (raw_id)
);

DROP TABLE IF EXISTS project_staging.stg_weather_raw;
CREATE TABLE project_staging.stg_weather_raw (
    raw_id BIGINT GENERATED ALWAYS AS IDENTITY,
    batch_id INT NOT NULL,
    source_file VARCHAR(120),
    icao_code TEXT,
    observation_ts TEXT,
    tmp TEXT,
    vis TEXT,
    wnd TEXT,
    aa1 TEXT,
    mw1 TEXT,
    aw1 TEXT,
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT pk_stg_weather_raw PRIMARY KEY (raw_id)
);

DROP TABLE IF EXISTS project_staging.stg_faa_master_raw;
CREATE TABLE project_staging.stg_faa_master_raw (
    raw_id BIGINT GENERATED ALWAYS AS IDENTITY,
    batch_id INT NOT NULL,
    source_file VARCHAR(120),
    n_number TEXT,
    mfr_mdl_code TEXT,
    year_mfr TEXT,
    type_engine TEXT,
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT pk_stg_faa_master_raw PRIMARY KEY (raw_id)
);

DROP TABLE IF EXISTS project_staging.stg_faa_acftref_raw;
CREATE TABLE project_staging.stg_faa_acftref_raw (
    raw_id BIGINT GENERATED ALWAYS AS IDENTITY,
    batch_id INT NOT NULL,
    source_file VARCHAR(120),
    code TEXT,
    mfr TEXT,
    model TEXT,
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT pk_stg_faa_acftref_raw PRIMARY KEY (raw_id)
);

DROP TABLE IF EXISTS project_staging.stg_airport_raw;
CREATE TABLE project_staging.stg_airport_raw (
    raw_id BIGINT GENERATED ALWAYS AS IDENTITY,
    batch_id INT NOT NULL,
    source_file VARCHAR(120),
    iata_code TEXT,
    icao_code TEXT,
    airport_name TEXT,
    city TEXT,
    state TEXT,
    region TEXT,
    latitude TEXT,
    longitude TEXT,
    elevation_ft TEXT,
    airport_type TEXT,
    time_zone TEXT,
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT pk_stg_airport_raw PRIMARY KEY (raw_id)
);

DROP TABLE IF EXISTS project_staging.stg_airline_raw;
CREATE TABLE project_staging.stg_airline_raw (
    raw_id BIGINT GENERATED ALWAYS AS IDENTITY,
    batch_id INT NOT NULL,
    source_file VARCHAR(120),
    carrier_code TEXT,
    airline_name TEXT,
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT pk_stg_airline_raw PRIMARY KEY (raw_id)
);

DROP TABLE IF EXISTS project_staging.stg_holiday_raw;
CREATE TABLE project_staging.stg_holiday_raw (
    raw_id BIGINT GENERATED ALWAYS AS IDENTITY,
    batch_id INT NOT NULL,
    source_file VARCHAR(120),
    holiday_date TEXT,
    holiday_name TEXT,
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT pk_stg_holiday_raw PRIMARY KEY (raw_id)
);

-- Section 3: Clean staging tables (typed, standardized)
DROP TABLE IF EXISTS project_staging.stg_flight_clean;
CREATE TABLE project_staging.stg_flight_clean (
    raw_id BIGINT NOT NULL,
    batch_id INT NOT NULL,
    flight_date DATE NOT NULL,
    carrier_code VARCHAR(3) NOT NULL,
    tail_number VARCHAR(10),
    flight_number VARCHAR(6),
    origin_code CHAR(3) NOT NULL,
    dest_code CHAR(3) NOT NULL,
    sched_dep_hour SMALLINT,
    dep_delay_min SMALLINT,
    arr_delay_min SMALLINT,
    carrier_delay_min SMALLINT,
    weather_delay_min SMALLINT,
    nas_delay_min SMALLINT,
    security_delay_min SMALLINT,
    late_aircraft_delay_min SMALLINT,
    taxi_out_min SMALLINT,
    taxi_in_min SMALLINT,
    air_time_min SMALLINT,
    distance_miles INT,
    is_cancelled BOOLEAN NOT NULL,
    is_diverted BOOLEAN NOT NULL,
    cancellation_code CHAR(1),
    CONSTRAINT pk_stg_flight_clean PRIMARY KEY (raw_id)
);

DROP TABLE IF EXISTS project_staging.stg_route_demand_clean;
CREATE TABLE project_staging.stg_route_demand_clean (
    raw_id BIGINT NOT NULL,
    batch_id INT NOT NULL,
    month_start_date DATE NOT NULL,
    carrier_code VARCHAR(3) NOT NULL,
    origin_code CHAR(3) NOT NULL,
    dest_code CHAR(3) NOT NULL,
    passengers INT,
    seats INT,
    departures_performed INT,
    CONSTRAINT pk_stg_route_demand_clean PRIMARY KEY (raw_id)
);

DROP TABLE IF EXISTS project_staging.stg_weather_clean;
CREATE TABLE project_staging.stg_weather_clean (
    raw_id BIGINT NOT NULL,
    batch_id INT NOT NULL,
    icao_code VARCHAR(4) NOT NULL,
    observation_utc TIMESTAMP NOT NULL,
    temperature_c NUMERIC(4,1),
    visibility_m INT,
    wind_speed_ms NUMERIC(4,1),
    precipitation_mm NUMERIC(5,1),
    condition_code VARCHAR(10) NOT NULL,
    CONSTRAINT pk_stg_weather_clean PRIMARY KEY (raw_id)
);

DROP TABLE IF EXISTS project_staging.stg_aircraft_clean;
CREATE TABLE project_staging.stg_aircraft_clean (
    raw_id BIGINT NOT NULL,
    batch_id INT NOT NULL,
    tail_number VARCHAR(10) NOT NULL,
    manufacturer VARCHAR(60),
    model VARCHAR(60),
    engine_type VARCHAR(30),
    year_built SMALLINT,
    CONSTRAINT pk_stg_aircraft_clean PRIMARY KEY (raw_id)
);

DROP TABLE IF EXISTS project_staging.stg_airport_clean;
CREATE TABLE project_staging.stg_airport_clean (
    raw_id BIGINT NOT NULL,
    batch_id INT NOT NULL,
    iata_code CHAR(3) NOT NULL,
    icao_code VARCHAR(4),
    airport_name VARCHAR(120) NOT NULL,
    city VARCHAR(80),
    state CHAR(2) NOT NULL,
    region VARCHAR(10) NOT NULL,
    latitude NUMERIC(9,6),
    longitude NUMERIC(9,6),
    elevation_ft INT,
    airport_type VARCHAR(20),
    time_zone VARCHAR(40) NOT NULL,
    CONSTRAINT pk_stg_airport_clean PRIMARY KEY (raw_id)
);

DROP TABLE IF EXISTS project_staging.stg_airline_clean;
CREATE TABLE project_staging.stg_airline_clean (
    raw_id BIGINT NOT NULL,
    batch_id INT NOT NULL,
    carrier_code VARCHAR(3) NOT NULL,
    airline_name VARCHAR(80),
    CONSTRAINT pk_stg_airline_clean PRIMARY KEY (raw_id)
);

DROP TABLE IF EXISTS project_staging.stg_holiday_clean;
CREATE TABLE project_staging.stg_holiday_clean (
    raw_id BIGINT NOT NULL,
    batch_id INT NOT NULL,
    holiday_date DATE NOT NULL,
    holiday_name VARCHAR(40) NOT NULL,
    CONSTRAINT pk_stg_holiday_clean PRIMARY KEY (raw_id)
);
