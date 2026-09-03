# Geary's C (spatial autocorrelation)

The other classical global autocorrelation statistic. Where Moran's I is
a correlation-like measure centred on \\-1/(n-1)\\, Geary's C is a
distance-like one centred on 1: **below 1** means positive
autocorrelation (neighbours are similar), above 1 means negative. It is
more sensitive than Moran's I to local differences.

## Usage

``` r
gearys_c(data, value, weights = NULL, n_perm = 999)
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

- n_perm:

  Permutations for the pseudo-p-value (default `999`; use `0` to skip
  the test, which leaves `p_value` as `NA`).

## Value

A one-row tibble: `c` (observed), `expected` (always 1), `n`,
`n_excluded`, `n_links`, `p_value` and an `excluded` list-column.

## References

Geary, R. C. (1954). The contiguity ratio and statistical mapping. *The
Incorporated Statistician* 5(3), 115-146.
[doi:10.2307/2986645](https://doi.org/10.2307/2986645)

## See also

[`morans_i()`](https://pursuitofdatascience.github.io/countryatlas/reference/morans_i.md),
[`country_weights()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_weights.md)

## Examples

``` r
# \donttest{
snap <- countryatlas::world_snapshot$countries
gearys_c(snap, gdp_per_capita, weights = country_weights("knn", k = 5),
         n_perm = 99)
#> # A tibble: 1 × 7
#>       c expected     n n_excluded n_links p_value excluded 
#>   <dbl>    <dbl> <int>      <int>   <int>   <dbl> <list>   
#> 1 0.535        1   189          2     785    0.01 <chr [2]>
# }
```
