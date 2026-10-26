# 01_extract.R 
#
# Download half-hourly regional carbon intensity forecast for London from the 
# Carbon Intensity API (https://carbon-intensity.github.io/api-definitions/)
# and save every response to data/raw/ exactly as it came back. 
#
# The API returns at most 60 days per request, so we ask for one calendar month 
# at a time.
# No API key is needed.

# Load packages 
library(httr2)
library(lubridate)

# ---- Settings ---------------------------------------------------------------
region_id <- 13   
# 13 = London. Change to pull another DNO region

first_month <- as.Date("2025-01-01") 
last_month <- as.Date("2025-12-01") # First day of the last month
# 12 complete months, so all four seasons are covered.  
# Fixed dates for reproducibility.  

month_starts <- seq(first_month, last_month, by = 'month')

stopifnot(length(month_starts)== 12) # Check if 12 months are covered 

dir.create("data/raw", recursive = TRUE, showWarnings = FALSE)

# ---- Download one month at a time --------------------------------------------
# Loop over positions (seq_along) rather than the dates themselves: 
# a for loop over a Date vector turns the date into a plain number. 

for (i in seq_along(month_starts)) {
  month_start <- month_starts[i]
  month_end <- month_start + months(1) 

  file_path <- file.path(
    "data/raw",
    paste0("London_", format(month_start, "%Y-%m"),
  ".json")                              # This is the name of the JSON file
  )                                     

  # Raw files are never overwritten: once a month is saved, skip it.
  if (file.exists(file_path)) {
    message("Already have ", file_path, ", skipping")
    next
  }              

  resp <- request("https://api.carbonintensity.org.uk") |>
    req_url_path_append("regional","intensity",
    paste0(month_start, "T00:00Z"),
    paste0(month_end, "T00:00Z"),
    "regionid", region_id
    ) |> 
    req_retry(max_tries = 5) |>         # try again on temporary errors (e.g. 429, 503)
    req_perform()                       # stop with an error if the API returns 4xx or 5xx
  
  
  # Save the bytes exactly as received: no parsing, no reformatting.
  writeBin(resp_body_raw(resp), file_path)
  message("Saved: ", file_path)

  Sys.sleep(1) # Pause 1 second between requests to avoid the API's rate limit.
}