# Add rank, percentile and z-score

Adds `rank`, `percentile` and `z_score` for a value column, optionally
within a group (region, year, ...), for "top 10" tables and labelling.

## Usage

``` r
rank_countries(data, value, within = NULL, desc = TRUE)
```

## Arguments

- data:

  A data frame.

- value:

  The value column to rank (unquoted).

- within:

  Optional grouping column(s) (unquoted or character) to rank within.

- desc:

  Rank descending (largest = rank 1); default `TRUE`. This affects
  `rank` only: `percentile` is always the percentile of the *value* (0
  is the lowest value), so under `desc = FALSE` rank 1 has percentile 0.

## Value

`data` with `rank`, `percentile` and `z_score` columns added.

## Panels

With no `within`, every row is ranked against every other. On a panel
that pools the years: a country's 2020 and its 2000 compete for the same
ranks, and `z_score` carries the time trend. So a frame whose `year`
holds more than one value warns (class `countryatlas_panel`);
`within = year` ranks countries within each year, which is nearly always
what is meant.

## Examples

``` r
df <- data.frame(iso3c = c("USA", "CHN", "IND"), gdp = c(21, 17, 3))
rank_countries(df, gdp)
#> # A tibble: 3 × 5
#>   iso3c   gdp  rank percentile z_score
#>   <chr> <dbl> <int>      <dbl>   <dbl>
#> 1 USA      21     1        1     0.776
#> 2 CHN      17     2        0.5   0.353
#> 3 IND       3     3        0    -1.13 
```
