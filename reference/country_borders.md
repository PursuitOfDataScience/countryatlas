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

  Natural Earth resolution to compute adjacency from. This is not a
  cosmetic choice – see *Which countries the default leaves out* below.
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

## Which countries the default leaves out

Adjacency is computed from Natural Earth polygons, and the default
`scale = "small"` (110m) has no polygon at all for the European
microstates. **Andorra, Liechtenstein, Monaco, San Marino and the
Vatican are therefore absent from the table entirely** – not merely
missing a short border, but contributing no rows, despite a land border
being the whole of their geography. The default reports 310 pairs over
153 countries; France comes back with 8 neighbours rather than 10.

`scale = "medium"` (50m) has all five, giving 322 pairs over 162
countries and France its full list. Use it whenever the microstates
matter:

    country_borders(scale = "medium")

The same 110m gap is why
[`morans_i()`](https://pursuitofdatascience.github.io/countryatlas/reference/morans_i.md)'s
contiguity weights exclude them – see its `n_excluded` – and it is the
land-border twin of the island problem described in
[`vignette("honest-maps")`](https://pursuitofdatascience.github.io/countryatlas/articles/honest-maps.md).
Note the two Guiana borders are real, not artefacts: French Guiana makes
Brazil and Suriname neighbours of France.

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
