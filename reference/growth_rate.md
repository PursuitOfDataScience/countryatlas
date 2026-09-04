# Year-on-year (or compound) growth rate

Adds a growth-rate column to a panel: either the period-over-period
change (`"yoy"`) or the compound annual growth rate from the first
observed year (`"cagr"`), computed per country.

## Usage

``` r
growth_rate(data, value, type = c("yoy", "cagr"), suffix = "_growth")
```

## Arguments

- data:

  A panel with `iso3c` and `year`.

- value:

  The value column (unquoted).

- type:

  `"yoy"` (default, period-over-period) or `"cagr"` (compound annual
  growth rate vs. the first non-`NA` year). `"cagr"` needs a positive
  ratio at both ends, so a negative value gives `NA` for that row (with
  a warning) and a non-positive base year gives `NA` for that country; a
  value of exactly `0` is a legitimate annualised -100%. `"yoy"` is a
  plain ratio change and is defined for negative values.

- suffix:

  Suffix for the new column (default `"_growth"`).

## Value

`data` with a growth-rate column added (a proportion, so 0.03 = 3%).
Rows come back sorted by `iso3c` then `year`: the calculation reads each
country's series in time order, so a row-aligned vector held alongside
`data` will no longer line up.

## Examples

``` r
df <- data.frame(iso3c = "USA", year = 2000:2002, gdp = c(100, 110, 121))
growth_rate(df, gdp)
#> # A tibble: 3 × 4
#>   iso3c  year   gdp gdp_growth
#>   <chr> <int> <dbl>      <dbl>
#> 1 USA    2000   100     NA    
#> 2 USA    2001   110      0.100
#> 3 USA    2002   121      0.100
```
