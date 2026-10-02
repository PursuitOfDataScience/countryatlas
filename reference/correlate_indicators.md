# Pairwise correlation of indicators on the spine

Which indicators move together across countries? Computes pairwise
correlations between indicator columns (pairwise-complete, so patchy
coverage doesn't shrink every pair to the common subset), with the
per-pair `n` reported so a headline `r` computed on 12 countries can't
masquerade as a world fact.

## Usage

``` r
correlate_indicators(
  data,
  ...,
  method = c("pearson", "spearman"),
  min_n = 3,
  by_year = FALSE,
  weight = NULL
)
```

## Arguments

- data:

  A country-level (or map-ready) data frame; map-ready frames are
  reduced to one row per country first, so the reported `n` counts
  countries rather than geometry rows.

- ...:

  \<[`tidy-select`](https://dplyr.tidyverse.org/reference/dplyr_tidy_select.html)\>
  Indicator columns to correlate. If empty, all numeric columns except
  coordinates, `year` and other structural columns are used.

- method:

  `"pearson"` (default) or `"spearman"`.

- min_n:

  Minimum number of complete pairs for a correlation to be reported
  (default `3`).

- by_year:

  If `TRUE`, correlate within each year of a panel and return one table
  per year, stacked with a leading `year` column. `FALSE` (default)
  wants one row per country and, handed a panel, keeps each country's
  earliest year with a warning.

- weight:

  Optional column (unquoted), typically population, to weight each
  country by. Unweighted, every country counts once (Milanovic's
  "concept 1"); weighted by population, a correlation describes the
  average person rather than the average country ("concept 2"). A
  Spearman correlation is weighted on the ranks.

## Value

A tibble with one row per indicator pair: `var_x`, `var_y`, `r`, `n`
(complete pairs), sorted by `|r|` descending; with `by_year = TRUE`, the
same per year, led by `year`.

## Examples

``` r
correlate_indicators(countryatlas::world_snapshot$countries)
#> # A tibble: 6 × 4
#>   var_x           var_y                  r     n
#>   <chr>           <chr>              <dbl> <int>
#> 1 gdp_per_capita  life_expectancy  0.607     199
#> 2 life_expectancy co2_per_capita   0.307     203
#> 3 gdp_per_capita  co2_per_capita   0.295     191
#> 4 gdp_per_capita  population      -0.0567    199
#> 5 population      life_expectancy -0.0194    216
#> 6 population      co2_per_capita   0.00663   203
# weighted by population: the correlation for the average person
correlate_indicators(countryatlas::world_snapshot$countries,
                     gdp_per_capita, life_expectancy, weight = population)
#> # A tibble: 1 × 4
#>   var_x          var_y               r     n
#>   <chr>          <chr>           <dbl> <int>
#> 1 gdp_per_capita life_expectancy 0.600   199
```
