# Spatial weights on the country spine

Build a reusable neighbour-weights object for
[`morans_i()`](https://pursuitofdatascience.github.io/countryatlas/reference/morans_i.md),
[`local_morans()`](https://pursuitofdatascience.github.io/countryatlas/reference/local_morans.md),
[`gearys_c()`](https://pursuitofdatascience.github.io/countryatlas/reference/gearys_c.md),
[`getis_ord()`](https://pursuitofdatascience.github.io/countryatlas/reference/getis_ord.md)
and
[`spatial_lag()`](https://pursuitofdatascience.github.io/countryatlas/reference/spatial_lag.md).
Four schemes, three of which give every country at least one neighbour –
which land-border contiguity, the historical default, cannot do for an
island.

## Usage

``` r
country_weights(
  type = c("contiguity", "knn", "distance", "custom"),
  countries = NULL,
  k = 5,
  cutoff_km = NULL,
  w = NULL,
  style = c("W", "B"),
  scale = "small"
)
```

## Arguments

- type:

  - `"contiguity"` – shared land border, from
    [`country_borders()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_borders.md).
    Needs `sf`. Islands get no neighbours; see
    [`morans_i()`](https://pursuitofdatascience.github.io/countryatlas/reference/morans_i.md)'s
    note.

    - `"knn"` – the `k` nearest countries by great-circle centroid
      distance. Every country gets exactly `k` neighbours, islands
      included. Needs nothing but the bundled
      [country_meta](https://pursuitofdatascience.github.io/countryatlas/reference/country_meta.md).

    - `"distance"` – every country within `cutoff_km`. Needs nothing.

    - `"custom"` – your own adjacency (see `w`), which is how
      non-geographic neighbourhoods – trade volume, migration flows,
      colonial or language ties – go through the same API.

- countries:

  Optional `iso3c` vector to restrict the weights to. Defaults to every
  country the chosen backend knows about.

- k:

  Neighbours per country for `type = "knn"` (default `5`).

- cutoff_km:

  Distance band for `type = "distance"`, in kilometres.

- w:

  For `type = "custom"`: either a square named matrix, or a long data
  frame with columns `iso3c`, `neighbor` and optionally `weight`.

- style:

  `"W"` (default) row-standardises so each row sums to 1, the usual
  choice for Moran's I; `"B"` leaves the weights binary/raw.

- scale:

  Natural Earth resolution for `type = "contiguity"`.

## Value

A `countryatlas_weights` object: the weights matrix plus the scheme that
built it. Inspect it by printing;
[`as.matrix()`](https://rdrr.io/r/base/matrix.html) gives the matrix.

## Choosing a scheme

Contiguity encodes "shares a border", which is the right relation for
spillovers that cross borders by land. It is the wrong relation for a
global question, because it silently deletes the islands. `"knn"` is the
safe default for world-scale work: every country participates, and `k`
controls how local the neighbourhood is. `"distance"` is right when the
process has a real length scale. `"custom"` is right when geography is
not the relevant space at all.

## See also

[`morans_i()`](https://pursuitofdatascience.github.io/countryatlas/reference/morans_i.md),
[`local_morans()`](https://pursuitofdatascience.github.io/countryatlas/reference/local_morans.md),
[`lisa_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/lisa_map.md),
[`spatial_lag()`](https://pursuitofdatascience.github.io/countryatlas/reference/spatial_lag.md)

## Examples

``` r
# k-nearest neighbours: no sf needed, and islands are included
w <- country_weights("knn", k = 4)
w
#> 
#> ── countryatlas spatial weights 
#> scheme: knn -- 4 nearest centroids
#> style: row-standardised (W)
#> countries: 239
#> links: 956
#> isolated: 0

# \donttest{
snap <- countryatlas::world_snapshot$countries
morans_i(snap, gdp_per_capita, weights = country_weights("knn", k = 5),
         n_perm = 99)
#> # A tibble: 1 × 7
#>       i expected     n n_excluded n_links p_value excluded 
#>   <dbl>    <dbl> <int>      <int>   <int>   <dbl> <list>   
#> 1 0.472 -0.00532   189          2     785    0.01 <chr [2]>
# }
```
