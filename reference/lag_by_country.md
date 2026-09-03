# Panel lag / difference by country

The two panel primitives everyone hand-rolls (and gets subtly wrong when
the frame isn't sorted): the value `n` years back, and the change since
then – grouped by `iso3c`, ordered by `year`, so country A's 1960 never
leaks into country B's first row.

## Usage

``` r
lag_by_country(data, value, n = 1, suffix = NULL)

diff_by_country(data, value, n = 1, suffix = NULL)
```

## Arguments

- data:

  A panel with `iso3c` and `year`.

- value:

  The value column (unquoted).

- n:

  Number of periods to lag / difference over (default `1`).

- suffix:

  Suffix for the new column. Defaults to `"_lag"` / `"_diff"` (with `n`
  appended when `n > 1`, e.g. `"_lag5"`).

## Value

`data` with the lagged / differenced column added. Rows come back sorted
by `iso3c` then `year`: the calculation reads each country's series in
time order, so a row-aligned vector held alongside `data` will no longer
line up.

## Examples

``` r
df <- data.frame(iso3c = "USA", year = 2000:2003, gdp = c(100, 110, 121, 133))
lag_by_country(df, gdp)
#> # A tibble: 4 × 4
#>   iso3c  year   gdp gdp_lag
#>   <chr> <int> <dbl>   <dbl>
#> 1 USA    2000   100      NA
#> 2 USA    2001   110     100
#> 3 USA    2002   121     110
#> 4 USA    2003   133     121
diff_by_country(df, gdp)
#> # A tibble: 4 × 4
#>   iso3c  year   gdp gdp_diff
#>   <chr> <int> <dbl>    <dbl>
#> 1 USA    2000   100       NA
#> 2 USA    2001   110       10
#> 3 USA    2002   121       11
#> 4 USA    2003   133       12
```
