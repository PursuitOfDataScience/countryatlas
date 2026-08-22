# Roll countries up to region / income / continent

Aggregate a country-level value to a coarser grouping, optionally with
population-weighted means.

## Usage

``` r
aggregate_regions(data, value, by = "region", fun = "sum", weight = NULL)
```

## Arguments

- data:

  A country-level data frame.

- value:

  The value column to aggregate (unquoted).

- by:

  Grouping column(s) (character), default `"region"`. Combine with
  `"year"` for panel roll-ups.

- fun:

  Aggregation: `"sum"` (default), `"mean"`, `"median"`, `"min"`, `"max"`
  or `"weighted_mean"`.

- weight:

  Optional weight column (unquoted) for `"weighted_mean"`.

## Value

A tibble of `by` plus the aggregated value.

## Groups with no data

Missing values are dropped before aggregating, so a group is summarised
from whatever it does have. A group with *no* non-missing value returns
`NA` rather than a figure: [`sum()`](https://rdrr.io/r/base/sum.html)
would otherwise report `0`, [`mean()`](https://rdrr.io/r/base/mean.html)
`NaN` and
[`min()`](https://rdrr.io/r/base/Extremes.html)/[`max()`](https://rdrr.io/r/base/Extremes.html)
`-Inf`/`Inf`, each of which reads as a real total for a region we simply
have no data for. Use
[`audit_coverage()`](https://pursuitofdatascience.github.io/countryatlas/reference/audit_coverage.md)
to see where those gaps are.

## Examples

``` r
df <- data.frame(iso3c = c("USA", "CAN", "BRA"),
                 region = c("North America", "North America", "Latin America"),
                 gdp = c(21, 1.7, 1.4))
aggregate_regions(df, gdp, fun = "sum")
#> # A tibble: 2 × 2
#>   region          gdp
#>   <chr>         <dbl>
#> 1 Latin America   1.4
#> 2 North America  22.7
```
