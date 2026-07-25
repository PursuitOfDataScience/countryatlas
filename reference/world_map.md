# One-line choropleth, several honest styles

Encapsulates the choropleth boilerplate and goes beyond a single style.
Auto-detects the polygon vs `sf` backend, applies
[`theme_world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/theme_world_map.md),
and – for `sf` – a real projection via
[`ggplot2::coord_sf()`](https://ggplot2.tidyverse.org/reference/ggsf.html).
Binned / quantile / jenks styles are offered because a continuous fill
on a skewed indicator hides almost all the variation; binning is the
honest default for choropleths.

## Usage

``` r
world_map(
  data,
  fill,
  style = c("continuous", "binned", "quantile", "jenks", "categorical"),
  projection = "equal_earth",
  palette = NULL,
  n_bins = 5,
  borders = TRUE,
  title = NULL,
  legend = NULL,
  na_label = "No data",
  recenter = NULL
)
```

## Arguments

- data:

  A map-ready frame from
  [`world_data()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_data.md)
  /
  [`join_world()`](https://pursuitofdatascience.github.io/countryatlas/reference/join_world.md)
  (polygon tibble or `sf`).

- fill:

  The fill column (unquoted).

- style:

  `"continuous"` (default), `"binned"`, `"quantile"`, `"jenks"` or
  `"categorical"`.

- projection:

  For the `sf` backend, any of the projections in
  [`world_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_geometry.md):
  `"equal_earth"` (default), `"robinson"`, `"mollweide"`,
  `"natural_earth"`, `"plate_carree"`, `"mercator"`, `"winkel_tripel"`,
  `"eckert4"`, `"gall_peters"`, `"orthographic"`,
  `"azimuthal_equal_area"`, `"north_polar"` or `"south_polar"`.

- palette:

  Optional palette name passed to the relevant `ggplot2` scale.

- n_bins:

  Number of bins for binned/quantile/jenks styles.

- borders:

  Draw country borders (default `TRUE`).

- title, legend:

  Optional plot title and legend title.

- na_label:

  Legend key label for missing data, used by the styles with a discrete
  legend (`"quantile"`, `"jenks"`, `"categorical"`); the continuous and
  binned colourbars have no `NA` key to name.

- recenter:

  Optional central meridian for the `sf` backend.

## Value

A `ggplot` object.

## Examples

``` r
# \donttest{
snap <- countryatlas::world_snapshot$countries
if (requireNamespace("maps", quietly = TRUE)) {
  mapdf <- attach_geometry(snap, geometry = "polygon")
  world_map(mapdf, gdp_per_capita, style = "quantile")
}

# }
```
