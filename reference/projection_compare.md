# The same map under several projections

Small multiples of one choropleth, drawn once per projection, so the
cost of a projection choice is visible rather than asserted. The data
and the classification are held fixed; only the CRS varies.

## Usage

``` r
projection_compare(
  data,
  fill,
  projections = c("equal_earth", "robinson", "winkel_tripel", "mercator"),
  ncol = NULL,
  labeller = c("name", "property"),
  ...
)
```

## Arguments

- data:

  An `sf` map-ready frame (projections are an `sf`-backend feature; the
  polygon backend draws in
  [`coord_quickmap()`](https://ggplot2.tidyverse.org/reference/coord_map.html)
  and cannot reproject).

- fill:

  The fill column (unquoted).

- projections:

  Projections to compare (default: Equal Earth, Robinson, Winkel tripel
  and Mercator – an equal-area, two compromises and a conformal). See
  [`projection_info()`](https://pursuitofdatascience.github.io/countryatlas/reference/projection_info.md).

- ncol:

  Number of facet columns.

- labeller:

  `"name"` (default) labels each panel with the projection name;
  `"property"` appends what it preserves, which is the point of the
  comparison.

- ...:

  Passed to
  [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md)
  (e.g. `style`, `palette`, `n_bins`).

## Value

A faceted `ggplot` object.

## See also

[`projection_info()`](https://pursuitofdatascience.github.io/countryatlas/reference/projection_info.md),
[`tissot_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/tissot_map.md)

## Examples

``` r
# \donttest{
if (requireNamespace("sf", quietly = TRUE) &&
    requireNamespace("rnaturalearth", quietly = TRUE)) {
  attach_geometry(countryatlas::world_snapshot$countries, geometry = "sf") |>
    projection_compare(gdp_per_capita, style = "quantile")
}

# }
```
