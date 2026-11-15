-- Section 1: Schemas
CREATE SCHEMA IF NOT EXISTS project_staging;
CREATE SCHEMA IF NOT EXISTS project_dw;
CREATE SCHEMA IF NOT EXISTS project_reporting;

COMMENT ON SCHEMA project_staging IS 'Raw and cleaned source data, ETL audit and rejected rows';
COMMENT ON SCHEMA project_dw IS 'Dimensional warehouse: dimensions and facts';
COMMENT ON SCHEMA project_reporting IS 'Views and marts for OLAP and Power BI';
