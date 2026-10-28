# 03_staging.R
#
# Build two clean staging tables from raw_intensity:
#   stg_intensity:      one row per half-hour (UTC and London time, forecast, index)
#   stg_generation_mix: one row per half-hour per fuel
# Then run data checks. Each check prints rows only if something is wrong,
# except where the expected result is noted.

library(DBI)

# Connect R to the DuckDB database file
con <- dbConnect(duckdb::duckdb(), "london_carbon.duckdb")

# icu extension handles time zones
dbExecute(con, "INSTALL icu")
dbExecute(con, "LOAD icu")

# Build the staging table: one clean row per half-hour
dbExecute(con, "
  CREATE OR REPLACE TABLE stg_intensity AS
  -- Step 1: one row per half-hour 
  WITH halfhours AS (
    SELECT
      filename,
      data.regionid  AS region_id,
      data.shortname AS region_name,
      unnest(data.data) AS h -- split the list of half-hours into rows
    FROM raw_intensity
  ),
  -- Step 2: for each half-hour extract time,forecast and index
  parsed AS (
    SELECT
      filename,
      region_id,
      region_name,
      strptime(h.from, '%Y-%m-%dT%H:%MZ') AS from_utc, -- parse the text into a UTC timestamp
      strptime(h.to,       '%Y-%m-%dT%H:%MZ') AS to_utc,
      h.intensity.forecast AS forecast_gco2_kwh,
      h.intensity.index    AS intensity_index
    FROM halfhours
  ),
  -- Step 3: Keep 2025 only (drops the 2024-12-31 23:30 row at the start of January)
  in_2025 AS (
    SELECT *
    FROM parsed
    WHERE from_utc >= '2025-01-01' 
      AND from_utc <  '2026-01-01'
  )
  -- Step 4: Month-boundary half-hours appear in two files; keep the one from the earlier file
   SELECT DISTINCT ON (from_utc) -- Only select one row per timestamp
    filename AS source_file,
    region_id,
    region_name,
    from_utc,
    -- transform UTC to London time 
    (from_utc AT TIME ZONE 'UTC') AT TIME ZONE 'Europe/London' AS from_london_time,
    to_utc,
    forecast_gco2_kwh,
    intensity_index
  FROM in_2025
  ORDER BY from_utc, filename 
")

# Checks:
# No half-hour should appear twice: expect 0 rows
print(
  dbGetQuery(con, "
  SELECT from_utc, COUNT(*) AS n
  FROM stg_intensity
  GROUP BY from_utc
  HAVING COUNT(*) > 1
")
)

# Expect 26 missing half-hours out of 17,520 in 2025
print(
  dbGetQuery(con, "
SELECT
CAST(from_utc AS DATE) AS utc_date,
48 - COUNT(from_utc) AS rows_missing
FROM stg_intensity
GROUP BY CAST(from_utc AS DATE)
HAVING COUNT(from_utc) < 48
ORDER BY utc_date
")
)

# Each row should cover exactly 30 minutes: expect 0 rows
print(
  dbGetQuery(con, "
SELECT 
from_utc,
to_utc - from_utc AS duration
FROM stg_intensity
WHERE to_utc - from_utc != INTERVAL 30 MINUTE
"))

# expect 5 rows; London time equals UTC until 00:30, then runs 1 hour ahead
print(
  dbGetQuery(con, "
  SELECT from_utc, from_london_time
  FROM stg_intensity
  WHERE from_utc BETWEEN TIMESTAMP '2025-03-30 00:00' AND TIMESTAMP '2025-03-30 02:00'
")
)


# Build second staging table: one row per half-hour per fuel
dbExecute(con, "
CREATE OR REPLACE TABLE stg_generation_mix AS 
-- Step 1: one row per half-hour
WITH halfhour AS (
SELECT 
filename,
data.regionid  AS region_id,
data.shortname AS region_name,
unnest(data.data) AS h
FROM raw_intensity
),
-- Step 2: split each half-hour into one row per fuel
fuel_per_halfhour AS(
SELECT 
filename,
region_id,
region_name, 
strptime(h.from, '%Y-%m-%dT%H:%MZ') AS from_utc,
unnest(h.generationmix) AS f
FROM halfhour
),
-- Step 3: Keep 2025 only
in_2025 AS (
SELECT *
FROM fuel_per_halfhour
WHERE from_utc >= '2025-01-01' 
AND   from_utc < '2026-01-01')
-- Step 4: keep one row per half-hour and fuel 
SELECT DISTINCT ON (from_utc,fuel_type) 
filename AS source_file,
region_id,
from_utc,
region_name AS region,
f.fuel AS fuel_type,
f.perc AS generation_pct
FROM in_2025
ORDER BY from_utc, fuel_type, filename
")

# Checks:
# Each half-hour should have exactly 9 fuels - expect 0 rows
print(
  dbGetQuery(con, "
  SELECT from_utc, COUNT(*) AS n
  FROM stg_generation_mix
  GROUP BY from_utc
  HAVING COUNT(*) != 9
")
)

# Check if 9 fuel percentages add up to 100 +- 0.5 - expect 0 rows
print(
  dbGetQuery(con, "
WITH add_perc AS (  
SELECT 
  from_utc, 
  SUM(generation_pct) AS tot_perc
  FROM stg_generation_mix
  GROUP BY from_utc
  )
SELECT 
from_utc,
tot_perc
  FROM add_perc
  WHERE ABS(tot_perc - 100) > 0.5
")
)


dbDisconnect(con, shutdown = TRUE)