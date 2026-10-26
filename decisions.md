# Decisions log

Things I noticed about the data, and what I decided to do about them.

| # | What I found | Decision | Why |
|---|---|---|---|
| 1 | The response includes the half-hour that ends at the `from` time, so consecutive requests overlap by one row | Deduplicate on region + start time | Avoid double-counting at chunk boundaries |
| 2 | Region IDs 15-18 are England, Scotland, Wales and GB totals, not real DNO regions | Only keep London (region 13) | ... |
| 3 | ... | ... | ... |