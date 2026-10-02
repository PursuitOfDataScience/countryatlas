# Getis-Ord G statistics (hot spots)

Global \\G\\ and local \\G_i^\*\\: unlike Moran's I, these distinguish
clusters of **high** values from clusters of **low** ones, which is what
"hot spot" analysis usually wants.

## Usage

``` r
getis_ord(
  data,
  value,
  weights = NULL,
  local = TRUE,
  p_adjust = c("fdr", "bonferroni", "holm", "none")
)
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

- local:

  If `TRUE` (default) return the per-country \\G_i^\*\\ with z-scores;
  if `FALSE` return the single global \\G\\.

  The global \\G\\ needs a variable with a natural origin and no
  negative values: it compares cross-products, so negating the variable
  leaves it unchanged. Given a negative value it warns and returns `NA`
  rather than a number computed outside its domain. \\G_i^\*\\
  standardises and is defined for signed data.

- p_adjust:

  For `local = TRUE`, how to adjust the per-country p-values for
  multiple testing: `"fdr"` (default), `"bonferroni"`, `"holm"` or
  `"none"`, as in
  [`local_morans()`](https://pursuitofdatascience.github.io/countryatlas/reference/local_morans.md).
  The global form makes one test and takes no adjustment.

## Value

With `local = TRUE`, a tibble of `iso3c`, `gi_star`, `z_score`,
`p_value` (two-sided, from the normal approximation) and `p_adjusted`,
one row per country used. With `local = FALSE`, a one-row tibble of `g`,
`expected`, `n` (countries used – the same count, so the local form
returns `n` rows) and `n_links` (non-zero weights).

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
#> # A tibble: 199 × 5
#>    iso3c gi_star z_score  p_value p_adjusted
#>    <chr>   <dbl>   <dbl>    <dbl>      <dbl>
#>  1 ABW   0.0139    0.449 0.654        0.850 
#>  2 AFG   0.00109  -1.07  0.287        0.794 
#>  3 AGO   0.00162  -1.00  0.316        0.794 
#>  4 ALB   0.00476  -0.629 0.529        0.831 
#>  5 AND   0.0408    3.58  0.000337     0.0134
#>  6 ARE   0.0207    1.26  0.207        0.794 
#>  7 ARG   0.00672  -0.388 0.698        0.850 
#>  8 ARM   0.00381  -0.727 0.467        0.802 
#>  9 ATG   0.0133    0.340 0.734        0.850 
#> 10 AUS   0.0180    0.898 0.369        0.794 
#> # ℹ 189 more rows
# }
```
