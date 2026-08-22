# Pairwise correlation of indicators on the spine

Which indicators move together across countries? Computes pairwise
correlations between indicator columns (pairwise-complete, so patchy
coverage doesn't shrink every pair to the common subset), with the
per-pair `n` reported so a headline `r` computed on 12 countries can't
masquerade as a world fact.

## Usage

``` r
correlate_indicators(data, ..., method = c("pearson", "spearman"), min_n = 3)
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

## Value

A tibble with one row per indicator pair: `var_x`, `var_y`, `r`, `n`
(complete pairs), sorted by `|r|` descending.

## Examples

``` r
correlate_indicators(countryatlas::world_snapshot$countries)
#> # A tibble: 6 × 4
#>   var_x           var_y                  r     n
#>   <chr>           <chr>              <dbl> <int>
#> 1 gdp_per_capita  life_expectancy  0.607     191
#> 2 gdp_per_capita  co2_per_capita   0.435     184
#> 3 life_expectancy co2_per_capita   0.307     203
#> 4 gdp_per_capita  population      -0.0579    191
#> 5 population      life_expectancy -0.0188    215
#> 6 population      co2_per_capita   0.00660   203
```
