# Country adjacency (shared land borders)

Which countries share a land border with which, as a tidy edge list –
built from polygon topology
([`sf::st_touches()`](https://r-spatial.github.io/sf/reference/geos_binary_pred.html)),
so it reflects the same curated geometry as the rest of the package.
Powers
[`neighbors()`](https://pursuitofdatascience.github.io/countryatlas/reference/neighbors.md).

## Usage

``` r
country_borders(scale = "small", region = NULL)
```

## Arguments

- scale:

  Natural Earth resolution to compute adjacency from. Coarser scales
  simplify small slivers and may miss a handful of short borders.
  `"large"` needs the non-CRAN `rnaturalearthhires` package; see
  [`world_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_geometry.md).

- region:

  Optional region subset (see
  [`world_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_geometry.md));
  a pair is only reported when both countries remain in the subset.

## Value

A tibble, one row per bordering pair: `iso3c_a`, `country_a`, `iso3c_b`,
`country_b`. Each unordered pair appears once, with `iso3c_a <= iso3c_b`
alphabetically.

## Turning it into a graph

`igraph::graph_from_data_frame()` takes the *first two* columns as the
edge endpoints, so pass only the two code columns – handing it the whole
tibble would build edges from each country's code to its own name:

    igraph::graph_from_data_frame(
      country_borders()[, c("iso3c_a", "iso3c_b")], directed = FALSE)

Attaching `igraph` also masks
[`neighbors()`](https://pursuitofdatascience.github.io/countryatlas/reference/neighbors.md),
which it exports too, so call that one as
[`countryatlas::neighbors()`](https://pursuitofdatascience.github.io/countryatlas/reference/neighbors.md)
from then on.

## Examples

``` r
# \donttest{
if (requireNamespace("sf", quietly = TRUE) &&
    requireNamespace("rnaturalearth", quietly = TRUE)) {
  head(country_borders(region = "Europe"))
  # The whole world is only a little dearer: a fraction of a second.
  nrow(country_borders())
}
#> [1] 310
# }
```
