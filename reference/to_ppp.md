# Convert to purchasing-power-parity terms

Market exchange rates do not equalise what money buys. `to_ppp()`
divides a local-currency series by the PPP conversion factor, putting
every country on comparable international dollars – the correction that
makes a cross-country *level* comparison meaningful.

## Usage

``` r
to_ppp(data, value, factor = NULL, suffix = "_ppp")
```

## Arguments

- data:

  A panel with `iso3c`, `year` and the value column.

- value:

  The local-currency value column (unquoted).

- factor:

  Either a column holding the PPP conversion factor (unquoted), or
  `NULL` to fetch the World Bank's (`PA.NUS.PPP`). Fetching needs the
  network.

- suffix:

  Suffix for the new column (default `"_ppp"`).

## Value

`data` with the PPP-converted column added.

## See also

[`deflate()`](https://pursuitofdatascience.github.io/countryatlas/reference/deflate.md),
[`per_capita()`](https://pursuitofdatascience.github.io/countryatlas/reference/per_capita.md)

## Examples

``` r
d <- data.frame(iso3c = c("IND", "USA"), year = 2020L,
                gdp_lcu = c(1e5, 1e4), ppp = c(21.9, 1))
to_ppp(d, gdp_lcu, factor = ppp)
#> # A tibble: 2 × 5
#>   iso3c  year gdp_lcu   ppp gdp_lcu_ppp
#>   <chr> <int>   <dbl> <dbl>       <dbl>
#> 1 IND    2020  100000  21.9       4566.
#> 2 USA    2020   10000   1        10000 
```
