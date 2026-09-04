# Getis-Ord G statistics (hot spots)

Global \\G\\ and local \\G_i^\*\\: unlike Moran's I, these distinguish
clusters of **high** values from clusters of **low** ones, which is what
"hot spot" analysis usually wants.

## Usage

``` r
getis_ord(data, value, weights = NULL, local = TRUE)
```

## Arguments

- data:

  A country-level frame with `iso3c` and the value column.

- value:

  The value column (unquoted).

- weights:

  A
  [`country_weights()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_weights.md)
  object. Defaults to land-border contiguity, which excludes islands –
  prefer `country_weights("knn")` for global work.

- local:

  If `TRUE` (default) return the per-country \\G_i^\*\\ with z-scores;
  if `FALSE` return the single global \\G\\.

  The global \\G\\ needs a variable with a natural origin and no
  negative values: it compares cross-products, so negating the variable
  leaves it unchanged. Given a negative value it warns and returns `NA`
  rather than a number computed outside its domain. \\G_i^\*\\
  standardises and is defined for signed data.

## Value

With `local = TRUE`, a tibble of `iso3c`, `gi_star`, `z_score` and
`p_value` (two-sided, from the normal approximation). With
`local = FALSE`, a one-row tibble of `g`, `expected`, `n` and `n_links`.

## References

Getis, A. & Ord, J. K. (1992). The analysis of spatial association by
use of distance statistics. *Geographical Analysis* 24(3), 189-206.
[doi:10.1111/j.1538-4632.1992.tb00261.x](https://doi.org/10.1111/j.1538-4632.1992.tb00261.x)

## See also

[`local_morans()`](https://pursuitofdatascience.github.io/countryatlas/reference/local_morans.md),
[`country_weights()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_weights.md)

## Examples

``` r
# \donttest{
snap <- countryatlas::world_snapshot$countries
getis_ord(snap, gdp_per_capita, weights = country_weights("knn", k = 5))
#> # A tibble: 189 × 4
#>    iso3c gi_star z_score  p_value
#>    <chr>   <dbl>   <dbl>    <dbl>
#>  1 ABW   0.0147    0.453 0.650   
#>  2 AGO   0.00176  -0.982 0.326   
#>  3 ALB   0.00517  -0.602 0.547   
#>  4 AND   0.0435    3.59  0.000332
#>  5 ARE   0.0221    1.28  0.200   
#>  6 ARG   0.00720  -0.369 0.712   
#>  7 ARM   0.00410  -0.706 0.480   
#>  8 ATG   0.0142    0.362 0.717   
#>  9 AUS   0.0193    0.922 0.356   
#> 10 AUT   0.0258    1.66  0.0969  
#> # ℹ 179 more rows
# }
```
