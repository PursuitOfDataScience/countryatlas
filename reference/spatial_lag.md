# The neighbour average, as a column

The spatially lagged value: for each country, the (weighted) mean of its
neighbours. The building block behind every statistic here, and useful
on its own – "what is happening around this country" as a regressor, a
map layer or a scatter-plot axis against the country's own value (the
Moran scatterplot).

## Usage

``` r
spatial_lag(data, value, weights = NULL, suffix = "_lag")
```

## Arguments

- data:

  A country-level frame with `iso3c` and the value column.

- value:

  The value column (unquoted).

- weights:

  A
  [`country_weights()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_weights.md)
  object. `NULL` (default) uses `country_weights("knn", k = 5)`: every
  country's five nearest neighbours, islands included.
  `country_weights("contiguity")` gives the land-border default of
  earlier versions, which leaves every island out.

- suffix:

  Suffix for the new column (default `"_lag"`).

## Value

`data` with the lagged column added. Countries the weights cannot reach
get `NA` – and since that `NA` is indistinguishable from one caused by a
missing input value, the codes themselves are attached as the
`"countryatlas_excluded"` attribute, the frame-shaped counterpart to the
`excluded` column
[`morans_i()`](https://pursuitofdatascience.github.io/countryatlas/reference/morans_i.md)
returns.

## See also

[`country_weights()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_weights.md),
[`local_morans()`](https://pursuitofdatascience.github.io/countryatlas/reference/local_morans.md)

## Examples

``` r
# \donttest{
snap <- countryatlas::world_snapshot$countries
spatial_lag(snap, gdp_per_capita, weights = country_weights("knn", k = 5))
#> # A tibble: 216 × 11
#>    iso3c iso2c country         continent region income gdp_per_capita population
#>    <chr> <chr> <chr>           <chr>     <chr>  <fct>           <dbl>      <dbl>
#>  1 AFG   AF    Afghanistan     Asia      South… Low i…           374.   42647492
#>  2 ALB   AL    Albania         Europe    Europ… Upper…          6549.    2377128
#>  3 DZA   DZ    Algeria         Africa    Middl… Lower…          4766.   46814308
#>  4 ASM   AS    American Samoa  Oceania   East … High …            NA       46765
#>  5 AND   AD    Andorra         Europe    Europ… High …         41224.      81938
#>  6 AGO   AO    Angola          Africa    Sub-S… Lower…          2799.   37885849
#>  7 ATG   AG    Antigua and Ba… Americas  Latin… High …         18305.      93772
#>  8 ARG   AR    Argentina       Americas  Latin… Upper…         12774.   45696159
#>  9 ARM   AM    Armenia         Asia      Europ… Upper…          5378.    3033500
#> 10 ABW   AW    Aruba           Americas  Latin… High …         33939.     107995
#> # ℹ 206 more rows
#> # ℹ 3 more variables: life_expectancy <dbl>, co2_per_capita <dbl>,
#> #   gdp_per_capita_lag <dbl>
# }
```
