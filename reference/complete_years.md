# Fill or interpolate panel gaps

Completes a panel so every country has every year, optionally filling
missing values by carry-forward (`"locf"`) or linear interpolation
(`"linear"`) so animations do not flicker on missing years.

## Usage

``` r
complete_years(
  data,
  years = NULL,
  value = NULL,
  method = c("none", "locf", "linear")
)
```

## Arguments

- data:

  A panel with `iso3c` and `year`.

- years:

  The full set of years to complete to. Defaults to the observed
  min:max.

- value:

  Optional value column(s) (character) to fill. If `NULL`, all numeric
  columns except `year` are filled.

- method:

  `"none"` (default; just complete the grid), `"locf"` or `"linear"`.

## Value

A completed (and optionally filled) panel tibble – or an `sf` frame, if
`data` was one; each invented row carries its country's geometry.

## Examples

``` r
df <- data.frame(iso3c = "USA", year = c(2000L, 2002L), gdp = c(1, 3))
complete_years(df, 2000:2002, method = "linear")
#> # A tibble: 3 × 3
#>   iso3c  year   gdp
#>   <chr> <int> <dbl>
#> 1 USA    2000     1
#> 2 USA    2001     2
#> 3 USA    2002     3
```
