# 05_export.R
#
# Purpose: export the two tables to CSV for Tableau and for reviewers to read on GitHub.
# Input:   mart_charging_profile, mart_charging_saving (built by 04_mart.R)
# Output:  output/mart_charging_profile.csv, output/mart_charging_saving.csv

dir.create("output", showWarnings = FALSE)   # create 'output' folder

library(DBI)

# Connect R to the DuckDB database file
con <- dbConnect(duckdb::duckdb(), "london_carbon.duckdb")

# Display existing datasets we created so far
print(dbListTables(con))  

# Extract two tables into the new output folder
dbExecute(con, "
COPY 
  mart_charging_profile 
TO 
  'output/mart_charging_profile.csv' (HEADER)
")

dbExecute(con, "
COPY 
  mart_charging_saving 
TO 
  'output/mart_charging_saving.csv' (HEADER)
")

dbDisconnect(con, shutdown = TRUE)