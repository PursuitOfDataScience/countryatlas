# Global Moran's I (spatial autocorrelation)

Do neighbouring countries have similar values? Global Moran's I on the
country spine, using the
[`country_borders()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_borders.md)
land-border adjacency as the spatial weights (row-standardised), with a
permutation pseudo-p-value. No `spdep` required: at ~200 countries the
dense arithmetic is trivial, and reusing the package's own adjacency
keeps the weights consistent with the maps. Countries with no land
border in the data (islands) carry no weight and are excluded.

## Usage

``` r
morans_i(data, value, scale = "small", n_perm = 999)
```

## Arguments

- data:

  A country-level data frame with `iso3c` (map-ready frames are reduced
  to one row per country first).

- value:

  The value column (unquoted).

- scale:

  Natural Earth resolution for the adjacency (see
  [`country_borders()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_borders.md)).
  `"large"` needs the non-CRAN `rnaturalearthhires` package; see
  [`world_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_geometry.md).

- n_perm:

  Number of permutations for the pseudo-p-value (default `999`; use `0`
  to skip the test).

## Value

A one-row tibble: `i` (observed Moran's I), `expected` (\\-1/(n-1)\\
under no autocorrelation), `n` (countries used), `n_links` (border pairs
among them) and `p_value` (one-sided, \\P(I\_{perm} \ge I\_{obs})\\;
positive autocorrelation is the standard alternative). Set a seed
beforehand for a reproducible `p_value`.

## Examples

``` r
# \donttest{
if (requireNamespace("sf", quietly = TRUE) &&
    requireNamespace("rnaturalearth", quietly = TRUE)) {
  snap <- countryatlas::world_snapshot$countries
  set.seed(42)
  morans_i(snap, gdp_per_capita, n_perm = 99)  # GDP clusters in space
}
#> # A tibble: 1 × 5
#>       i expected     n n_links p_value
#>   <dbl>    <dbl> <int>   <int>   <dbl>
#> 1 0.607 -0.00709   142     275    0.01
# }
```
