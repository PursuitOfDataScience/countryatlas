# Orthographic globe choropleth

The world as a globe (orthographic projection) centred on `lon`/`lat` –
the honest answer to "the whole world on a rectangle exaggerates the
poles". Takes the same `fill` / `style` options as
[`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md).
The default `"sf"` backend gives the cleanest limb; the `"polygon"`
backend draws the globe with
[`ggplot2::coord_map()`](https://ggplot2.tidyverse.org/reference/coord_map.html)
and needs only `maps` + `mapproj` (no `sf`).

## Usage

``` r
globe_map(
  data,
  fill,
  lon = 0,
  lat = 20,
  backend = c("sf", "polygon"),
  style = c("continuous", "binned", "quantile", "jenks", "categorical"),
  palette = NULL,
  n_bins = 5,
  borders = TRUE,
  title = NULL,
  legend = NULL,
  na_label = "No data"
)
```

## Arguments

- data:

  A map-ready frame: an `sf` frame for `backend = "sf"`, or a
  country-level frame with `iso3c` (or a polygon frame) for
  `backend = "polygon"`.

- fill:

  The fill column (unquoted).

- lon, lat:

  The longitude / latitude the globe is centred on (the face pointing at
  the viewer).

- backend:

  `"sf"` (default, via
  [`ggplot2::coord_sf()`](https://ggplot2.tidyverse.org/reference/ggsf.html))
  or `"polygon"` (via
  [`ggplot2::coord_map()`](https://ggplot2.tidyverse.org/reference/coord_map.html),
  no `sf` required).

- style, palette, n_bins, borders, title, legend, na_label:

  As in
  [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md).

## Value

A `ggplot` object.

## Examples

``` r
# \donttest{
# No sf required -- the polygon backend needs only maps + mapproj:
if (requireNamespace("maps", quietly = TRUE) &&
    requireNamespace("mapproj", quietly = TRUE)) {
  globe_map(countryatlas::world_snapshot$countries, continent,
            backend = "polygon", style = "categorical")
}

# }
if (FALSE) { # \dontrun{
# The sf backend gives the cleanest limb (needs a World Bank fetch):
world_data(2020, geometry = "sf") |>
  globe_map(gdp_per_capita, lon = 10, lat = 30)
} # }
```
