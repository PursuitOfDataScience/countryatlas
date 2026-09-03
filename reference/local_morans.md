# Local Moran's I (LISA)

Local Indicators of Spatial Association (Anselin 1995): one Moran
statistic per country, plus the cluster type it belongs to. Where
[`morans_i()`](https://pursuitofdatascience.github.io/countryatlas/reference/morans_i.md)
answers "is there clustering anywhere", this answers "where, and of what
kind".

## Usage

``` r
local_morans(data, value, weights = NULL, n_perm = 999, alpha = 0.05)
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

- alpha:

  Significance threshold for the `cluster` label (default `0.05`).

## Value

A tibble, one row per country: `iso3c`, `value`, `lag` (the neighbour
average), `ii` (the local statistic), `p_value` and `cluster`
(`"High-High"`, `"Low-Low"`, `"High-Low"`, `"Low-High"` or
`"Not significant"`).

## References

Anselin, L. (1995). Local Indicators of Spatial Association – LISA.
*Geographical Analysis* 27(2), 93-115.
[doi:10.1111/j.1538-4632.1995.tb00338.x](https://doi.org/10.1111/j.1538-4632.1995.tb00338.x)

## See also

[`lisa_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/lisa_map.md),
[`morans_i()`](https://pursuitofdatascience.github.io/countryatlas/reference/morans_i.md),
[`country_weights()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_weights.md)

## Examples

``` r
# \donttest{
snap <- countryatlas::world_snapshot$countries
set.seed(1)
local_morans(snap, gdp_per_capita, weights = country_weights("knn", k = 5),
             n_perm = 99)
#> # A tibble: 189 × 6
#>    iso3c  value     lag      ii p_value cluster        
#>    <chr>  <dbl>   <dbl>   <dbl>   <dbl> <fct>          
#>  1 ABW   33374.  -2415. -0.0529    0.86 Not significant
#>  2 AGO    2845. -14426.  0.286     0.13 Not significant
#>  3 ALB    6549.  -6941.  0.102     0.54 Not significant
#>  4 AND   41035.  84205.  2.73      0.01 High-High      
#>  5 ARE   41605.  13493.  0.448     0.18 Not significant
#>  6 ARG   12774.  -6530.  0.0407    0.53 Not significant
#>  7 ARM    5378.  -9273.  0.152     0.41 Not significant
#>  8 ATG   18350.  10930.  0.0151    0.64 Not significant
#>  9 AUS   61481. -15496. -0.935     0.14 Not significant
#> 10 AUT   45959.  21289.  0.833     0.05 High-High      
#> # ℹ 179 more rows
# }
```
