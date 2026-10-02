# Global Moran's I (spatial autocorrelation)

Do neighbouring countries have similar values? Global Moran's I on the
country spine, with a permutation pseudo-p-value. No `spdep` required:
at ~200 countries the dense arithmetic is trivial.

## Usage

``` r
morans_i(data, value, scale = deprecated(), n_perm = 999, weights = NULL)
```

## Arguments

- data:

  A country-level data frame with `iso3c` (map-ready frames are reduced
  to one row per country first).

- value:

  The value column (unquoted).

- scale:

  **\[deprecated\]** The Natural Earth resolution of the contiguity
  weights that were the default before 4.0.0. Supplying it still builds
  them, with a warning; write
  `weights = country_weights("contiguity", scale = )` instead.

- n_perm:

  Number of permutations for the pseudo-p-value (default `999`; use `0`
  to skip the test, which leaves `p_value` as `NA`).

- weights:

  A
  [`country_weights()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_weights.md)
  object. `NULL` (default) uses `country_weights("knn", k = 5)`,
  row-standardised, so every country with data and a centroid takes
  part. See below.

## Value

A one-row tibble: `i` (observed Moran's I), `expected` (\\-1/(n-1)\\
under no autocorrelation), `n` (countries used), `n_excluded` (countries
with data that the weights could not reach), `n_links`, `p_value`
(one-sided, \\P(I\_{perm} \ge I\_{obs})\\, computed as \\(1 + \\\\I^{\*}
\ge I\_{obs}\\) / (n\_{perm} + 1)\\, so never exactly zero – the floor
is \\1/(n\_{perm}+1)\\) and an `excluded` list-column of the excluded
`iso3c` codes. Set a seed beforehand for a reproducible `p_value`.

## Which countries are left out

The default weights are the five nearest neighbours, so every country
with data and a bundled centroid takes part. Land-border contiguity, the
default before 4.0.0, is still available and still systematic in what it
drops: an island has no land border, so any country with no land
neighbour *present in `data`* leaves the statistic – Japan, the United
Kingdom, Australia, Indonesia, Madagascar, New Zealand, the Philippines,
Iceland, Cuba, Sri Lanka and every small island state. On the bundled
[world_snapshot](https://pursuitofdatascience.github.io/countryatlas/reference/world_snapshot.md)'s
GDP per capita that changes the answer, not only the sample: see the
numbers in the example below. `n_excluded` and `excluded` report who is
left out under either scheme:

    morans_i(snap, gdp_per_capita, weights = country_weights("contiguity"))

## References

Moran, P. A. P. (1950). Notes on continuous stochastic phenomena.
*Biometrika* 37(1/2), 17-23.
[doi:10.2307/2332142](https://doi.org/10.2307/2332142)

## See also

[`country_weights()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_weights.md),
[`local_morans()`](https://pursuitofdatascience.github.io/countryatlas/reference/local_morans.md),
[`gearys_c()`](https://pursuitofdatascience.github.io/countryatlas/reference/gearys_c.md),
[`spatial_lag()`](https://pursuitofdatascience.github.io/countryatlas/reference/spatial_lag.md)

## Examples

``` r
# \donttest{
snap <- countryatlas::world_snapshot$countries
set.seed(42)
# every country included, no sf required
morans_i(snap, gdp_per_capita, n_perm = 99,
         weights = country_weights("knn", k = 5))
#> # A tibble: 1 × 7
#>       i expected     n n_excluded n_links p_value excluded 
#>   <dbl>    <dbl> <int>      <int>   <int>   <dbl> <list>   
#> 1 0.452 -0.00505   199          0     848    0.01 <chr [0]>
# }
```
