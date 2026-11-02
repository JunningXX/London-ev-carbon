# London EV Charging Carbon

**When should a London EV owner plug in to charge on the cleanest electricity?**

[![Dashboard preview](https://public.tableau.com/static/images/Lo/LondonEVChargingCarbon/Dashboard1/1.png)](https://public.tableau.com/views/LondonEVChargingCarbon/Dashboard1)

**Interactive dashboard:** https://public.tableau.com/views/LondonEVChargingCarbon/Dashboard1

---

## What I built and who for

A small R + DuckDB pipeline that turns a year of half-hourly carbon intensity forecasts for London into a Tableau dashboard for organisations that advise London EV drivers (council sustainability teams, energy suppliers, EV campaigns). They need a simple, evidence-based message they can share: when to plug in makes a measurable difference to CO2 emissions.

**The problem.** Most EV owners plug in as soon as they get home, usually early evening. That is also when the grid is most carbon-intensive: demand peaks and solar has gone for the day. The same charge can produce noticeably more CO2 depending only on *when* it starts, but drivers have no simple way to see this.

**The approach.** I compare two realistic plug-in times: **18:30**, a typical time to get home from work, and **22:30**, a typical time to plug in before bed. I chose these instead of the mathematically "cleanest" 4 hours of the night, because most people don't set a charging timer. Both are things a driver could actually do tonight.

**The answer.** For 2025, plugging in at 22:30 instead of 18:30 makes a 4-hour weekday charge **19–28% less carbon-intensive on average**, depending on the season. For an example car (Tesla Model Y, 29.6 kWh per charge) that is about **0.9–1.3 kg of CO2 saved per charge**.

The dashboard shows:
- a heatmap of average carbon intensity by **day of week × half-hour**, for each season;
- four headline numbers comparing the two plug-in times;
- a weekday comparison of the two habits.

## The data

- **Source:** [Carbon Intensity API](https://carbonintensity.org.uk/) from the National Energy System Operator (NESO). No API key needed. Licence: CC BY 4.0.
- **Endpoint:** `/regional/intensity/{from}/{to}/regionid/13` (region 13 = London).
- **Scope:** 1 January to 31 December 2025, half-hourly. 12 monthly JSON files in `data/raw/`, committed exactly as the API returned them.
- **What one row means:** the *forecast* carbon intensity (gCO2 per kWh) of electricity used in London for one half-hour, plus the generation mix (9 fuel types, % share). Regional data has forecasts only; actual values are only published nationally.
- **Quirks I found** (full list in [`decisions.md`](decisions.md)):
  - each monthly file repeats the last half-hour of the previous month (11 duplicates, identical values);
  - 26 of 17,520 half-hours are missing from the API (0.15%), and I left them as gaps;
  - all times are UTC, so I convert to London time to handle BST;
  - fuel percentages sum to 99.8–100.2 because of rounding.

## How it works

| Script | Layer | What it does |
|---|---|---|
| `01_extract.R` | extract | Calls the API month by month and saves each raw response to `data/raw/` unchanged. |
| `02_load.R` | raw | Loads all 12 JSON files into `raw_intensity` (one row per file, nothing changed). |
| `03_staging.R` | staging | Unnests the JSON into `stg_intensity` (one row per half-hour, 17,494 rows) and `stg_generation_mix` (one row per half-hour × fuel, 157,446 rows). Removes boundary duplicates, filters to 2025, adds London local time. Runs data checks (duplicates, gaps, 30-minute intervals, clock change, mix sums). |
| `04_mart.R` | marts | `mart_charging_profile`: average intensity by season × weekday × half-hour (1,344 rows, feeds the heatmap). `mart_charging_saving`: CO2 per charge for the two plug-in habits, by season (4 rows, feeds the headline numbers). `mart_charging_saving_weekday`: CO2 per charge for the two plug-in habits, by weekday and season (20 rows, feeds the headline numbers)|
| `05_export.R` | output | Exports the marts to `output/*.csv` for Tableau. |

Every script prints its checks with the expected result written next to it in a comment, so a run can be checked by eye.

**Key assumptions** (kept as variables at the top of `04_mart.R`): Tesla Model Y RWD on a 7.4 kW home charger, 4-hour charge = 29.6 kWh. The % saving does not depend on these; only the kg figures do.

## How to run it

Requirements: R (4.5+) with `httr2`, `DBI` and `duckdb`.

```r
install.packages(c("httr2", "DBI", "duckdb"))
```

From the repo root:

```r
# The raw API responses are already committed, so you can start at step 2.
source("02_load.R")
source("03_staging.R")
source("04_mart.R")
source("05_export.R")

```

This creates `london_carbon.duckdb` locally and rewrites `output/*.csv`. No credentials are used anywhere.


## Where AI helped

- **Learning and code help:** This was my first time using an API, JSON or DuckDB. I used Claude (Anthropic) as a tutor throughout. For the extract and load steps, Claude walked me through the code (calling the API with httr2, saving raw responses, reading JSON into DuckDB) and explained each line, and I typed and ran it myself. Along the way it explained the concepts behind the pipeline (ELT and layers, unnesting JSON, time zones, grain, CTEs) and suggested the overall structure.
- **Debugging SQL:** From the staging step on, **I wrote the SQL myself**; I used Claude to review and point out bugs.
- **Proofread:** I used Claude to proofread this file and [`decisions.md`](decisions.md).