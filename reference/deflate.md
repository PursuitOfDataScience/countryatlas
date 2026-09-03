# Convert a money series to constant prices

A nominal series is not comparable across years. `deflate()` divides by
a price index rebased to `base_year`, turning current-price values into
constant `base_year` prices.

## Usage

``` r
deflate(data, value, base_year, deflator = NULL, suffix = "_real")
```

## Arguments

- data:

  A panel with `iso3c`, `year` and the value column.

- value:

  The nominal value column (unquoted).

- base_year:

  The year whose prices to express everything in.

- deflator:

  Either a column in `data` holding the price index (unquoted), or
  `NULL` to fetch the World Bank GDP deflator (`NY.GDP.DEFL.ZS`) for the
  countries and years present. Fetching needs the network.

- suffix:

  Suffix for the new column (default `"_real"`).

## Value

`data` with the constant-price column added.

## Which deflator

The GDP deflator is the right default for aggregate output. For
household spending the CPI (`FP.CPI.TOTL`) is usually preferred, and for
cross-country *level* comparisons a deflator is not enough at all – you
want
[`to_ppp()`](https://pursuitofdatascience.github.io/countryatlas/reference/to_ppp.md)
as well, because exchange rates do not equalise purchasing power.
Deflating and converting to PPP are different corrections for different
problems, and a cross-country panel over time generally needs both.

## See also

[`to_ppp()`](https://pursuitofdatascience.github.io/countryatlas/reference/to_ppp.md),
[`per_capita()`](https://pursuitofdatascience.github.io/countryatlas/reference/per_capita.md),
[`index_to()`](https://pursuitofdatascience.github.io/countryatlas/reference/index_to.md)

## Examples

``` r
d <- data.frame(iso3c = "USA", year = 2000:2002,
                gdp = c(100, 110, 120), defl = c(90, 100, 105))
deflate(d, gdp, base_year = 2001, deflator = defl)
#> # A tibble: 3 × 5
#>   iso3c  year   gdp  defl gdp_real
#>   <chr> <int> <dbl> <dbl>    <dbl>
#> 1 USA    2000   100    90     111.
#> 2 USA    2001   110   100     110 
#> 3 USA    2002   120   105     114.
```
