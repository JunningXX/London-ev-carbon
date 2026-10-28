# 04_mart.R
#
# Purpose: build the user-facing mart tables from the clean staging table.
# Input: stg_intensity
# Output: mart_charging_profile - avg forecast gCO2/kWh by season x weekday x half-hour (London time)
#         mart_charging_saving  - per season, CO2 per charge for habit A (plug in 18:30)
#                                 vs habit B (plug in 22:30), weekdays only

library(DBI)

# Connect R to the DuckDB database file
con <- dbConnect(duckdb::duckdb(), "london_carbon.duckdb")

# icu extension handles time zones
dbExecute(con, "INSTALL icu")
dbExecute(con, "LOAD icu")


# ---- Table 1: mart_charging_profile ----------------------------------------
# One row per season x day of week x half-hour (4 x 7 x 48 = 1,344 rows)
# For heatmap: when in the week is London's electricity cleanest?
dbExecute(con, "
CREATE OR REPLACE TABLE mart_charging_profile AS
WITH labelled AS (
-- Add the labels we group by, all taken from London local time
  SELECT 
  from_london_time,
  forecast_gco2_kwh,
  CASE 
    WHEN month(from_london_time) IN (12, 1, 2) THEN  'Winter'
    WHEN month(from_london_time) IN (3, 4, 5)  THEN  'Spring'
    WHEN month(from_london_time) IN (6, 7, 8)  THEN  'Summer'
  ELSE 'Autumn' 
  END                                 AS season, -- create column 'season'
  isodow(from_london_time)            AS day_num, --  1 = Monday ... 7 = Sunday
  dayname(from_london_time)           AS day_of_week, --'Monday' etc., for labels
  strftime(from_london_time, '%H:%M') AS time_of_day -- '18:30' etc
FROM stg_intensity
  )
SELECT 
  season,
  day_of_week,
  day_num,
  time_of_day,
  COUNT(*) AS n_halfhours, -- how many half-hours the average is based on
  ROUND(AVG(forecast_gco2_kwh), 1) AS avg_forecast_gco2_kwh 
FROM labelled
GROUP BY season, day_num, day_of_week, time_of_day
ORDER BY season, day_num, time_of_day
")

# ---- Table 2: mart_charging_saving -----------------------------------------
# One row per season (4 rows)
# Question: on a weekday, how much CO2 does one charge save if I plug in at
# 22:30 before bed (habit B) instead of 18:30 when I get home (habit A)?

# Assumptions: Tesla Model Y RWD (UK), 7.4 kW single-phase home charger
charger_kw     <- 7.4
charge_hours   <- 4
kwh_per_charge <- charger_kw * charge_hours   # = 29.6 kWh, about half the 57.5 kWh battery

# paste0() attaches the R variable kwh_per_charge into the SQL text
sql <- paste0("
CREATE OR REPLACE TABLE mart_charging_saving AS
WITH work_day_evening AS (
  -- Weekday half-hours between 18:00 and 08:00 only, labelled by season
  -- (Simplification: slots after midnight are also taken from Mon-Fri dates)
  SELECT
    CASE
      WHEN month(from_london_time) IN (12, 1, 2) THEN 'Winter'
      WHEN month(from_london_time) IN (3, 4, 5)  THEN 'Spring'
      WHEN month(from_london_time) IN (6, 7, 8)  THEN 'Summer'
      ELSE 'Autumn'
    END                                 AS season,
    strftime(from_london_time, '%H:%M') AS time_of_day,
    forecast_gco2_kwh
  FROM stg_intensity
  WHERE isodow(from_london_time) < 6                    -- Monday to Friday
    AND (strftime(from_london_time, '%H:%M') >= '18:00'
      OR strftime(from_london_time, '%H:%M') <  '08:00') -- window crosses midnight, so OR
),
season_avg AS (
  -- Average intensity over each 4-hour charge (8 half-hours), not rounded yet
  SELECT
    season,
    AVG(forecast_gco2_kwh) FILTER (WHERE time_of_day BETWEEN '18:30' AND '22:00')          AS habit_a, -- 18:30 to 22:30
    AVG(forecast_gco2_kwh) FILTER (WHERE time_of_day >= '22:30' OR time_of_day <= '02:00') AS habit_b  -- 22:30 to 02:30
  FROM work_day_evening
  GROUP BY season
)
-- Turn intensity (g per kWh) into CO2 per charge (kg): g/kWh x kWh / 1000
-- Round only here, so the subtraction uses the unrounded averages
SELECT
  season,
  ROUND(habit_a, 1)                                           AS habit_a_gco2_kwh,
  ROUND(habit_b, 1)                                           AS habit_b_gco2_kwh,
  ROUND(habit_a * ", kwh_per_charge, " / 1000, 2)             AS kg_co2_habit_a,
  ROUND(habit_b * ", kwh_per_charge, " / 1000, 2)             AS kg_co2_habit_b,
  ROUND((habit_a - habit_b) * ", kwh_per_charge, " / 1000, 2) AS kg_saved_per_charge,
  ROUND((habit_a - habit_b) / habit_a * 100, 1)               AS pct_saved -- kWh cancels out
FROM season_avg
")
 
dbExecute(con, sql)


# ---- Checks -----------------------------------------------------------------
 
# Profile has one row per season x weekday x half-hour: expect 1,344
print(dbGetQuery(con, "SELECT COUNT(*) AS n_rows FROM mart_charging_profile"))
 
# How many half-hours each cell averages over: expect min 11, max 14
# (11 = Winter Sunday 23:00/23:30, hit by the January gap;
#  14 = Autumn Sunday 01:00/01:30, repeated when the clocks went back on 26 Oct)
print(dbGetQuery(con, "
SELECT
  MIN(n_halfhours) AS min_n,
  MAX(n_halfhours) AS max_n
FROM mart_charging_profile
"))
 
# Saving has one row per season: expect 4
# Expect Autumn: 157.6 vs 113.3 g/kWh, 1.31 kg saved per charge, 28.1%
print(dbGetQuery(con, "SELECT * FROM mart_charging_saving"))
 
dbDisconnect(con, shutdown = TRUE)