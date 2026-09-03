# Global Moran's I (spatial autocorrelation)

Do neighbouring countries have similar values? Global Moran's I on the
country spine, with a permutation pseudo-p-value. No `spdep` required:
at ~200 countries the dense arithmetic is trivial.

## Usage

``` r
morans_i(data, value, scale = "small", n_perm = 999, weights = NULL)
```

## Arguments

- data:

  A country-level data frame with `iso3c` (map-ready frames are reduced
  to one row per country first).

- value:

  The value column (unquoted).

- scale:

  Natural Earth resolution for the default contiguity adjacency (see
  [`country_borders()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_borders.md)).
  Ignored when `weights` is supplied.

- n_perm:

  Number of permutations for the pseudo-p-value (default `999`; use `0`
  to skip the test, which leaves `p_value` as `NA`).

- weights:

  A
  [`country_weights()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_weights.md)
  object. Defaults to land-border contiguity, row-standardised – which
  excludes every island. See below.

## Value

A one-row tibble: `i` (observed Moran's I), `expected` (\\-1/(n-1)\\
under no autocorrelation), `n` (countries used), `n_excluded` (countries
with data that the weights could not reach), `n_links`, `p_value`
(one-sided, \\P(I\_{perm} \ge I\_{obs})\\) and an `excluded` list-column
of the excluded `iso3c` codes. Set a seed beforehand for a reproducible
`p_value`.

## Which countries are left out

The default weights are land-border contiguity, and an island has no
land border – so any country with no land neighbour *present in `data`*
drops out entirely. On the bundled
[world_snapshot](https://pursuitofdatascience.github.io/countryatlas/reference/world_snapshot.md)
that is around a quarter of the countries with data: Japan, the United
Kingdom, Australia, Indonesia, Madagascar, New Zealand, the Philippines,
Iceland, Cuba, Sri Lanka and every small island state. The omission is
systematic rather than random.

`n_excluded` and `excluded` report it, and
[`country_weights()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_weights.md)
fixes it – `"knn"` and `"distance"` give every country neighbours:

    morans_i(snap, gdp_per_capita, weights = country_weights("knn", k = 5))

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
#> 1 0.472 -0.00532   189          2     785    0.01 <chr [2]>
# }
```
