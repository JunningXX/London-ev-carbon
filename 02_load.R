# 02_load.R
#
# Loading the raw JSON files in data/raw/ into DuckDB as the table - raw_intensity.
# One row per file, nothing cleaned or changed.
# Safe to re-run: CREATE OR REPLACE rebuilds the table every time.


library(DBI)

# Connecting R to the DuckDB database file (created if it dose not exist yet)
con <- dbConnect(duckdb::duckdb(), "london_carbon.duckdb")
dbExecute(con, "INSTALL json")
dbExecute(con, "LOAD json")

# Raw layer: stack all 12 JSON files into one table, one row per file,
# kept exactly as the API returned it. filename records which file each row came from.
# dbExecute returns the number of rows written: 12 = one per file.
dbExecute(con, "
  CREATE OR REPLACE TABLE raw_intensity AS  
  SELECT filename, 
  data
  FROM read_json_auto('data/raw/*.json', filename = true)
  ") 

# Quick checks: the table exists and each month has the expected number of half-hours
dbListTables(con)   
dbGetQuery(con, 
  "SELECT filename, 
  len(data.data) AS n_halfhours 
  FROM raw_intensity")

# Close the connection and release the lock on the database file
dbDisconnect(con, shutdown = TRUE)