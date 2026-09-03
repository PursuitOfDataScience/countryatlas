# Web-ready interactive choropleth

An interactive choropleth with hover and zoom, for dashboards and R
Markdown / Quarto. Engines are all optional `Suggests`.

## Usage

``` r
interactive_map(
  data,
  fill,
  tooltip = NULL,
  engine = c("plotly", "ggiraph", "leaflet", "ggsql", "mapgl"),
  ...
)
```

## Arguments

- data:

  A map-ready frame (polygon or sf). The `"leaflet"` engine will attach
  geometry itself if given a country-level table; the others require it
  already attached.

- fill:

  The fill column (unquoted).

- tooltip:

  Optional tooltip column (unquoted).

- engine:

  `"plotly"` (default), `"ggiraph"`, `"leaflet"`, `"mapgl"` or
  `"ggsql"`. `"mapgl"` renders through MapLibre GL – vector tiles,
  smooth zoom and a genuine interactive globe, which is what turns
  [`globe_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/globe_map.md)
  from a static novelty into something you can turn. It needs an `sf`
  frame (database-side rendering to a Vega-Lite widget; needs an `sf`
  frame and `ggsql` \>= 0.4.1, the version that added the `DRAW spatial`
  clause). `tooltip` is honoured by the `"ggiraph"` and `"leaflet"`
  engines (defaults to `fill` when omitted); `"plotly"`'s hover is
  controlled by
  [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md)
  aesthetics instead, and `"ggsql"` has no hover concept.

- ...:

  Passed to
  [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md)
  for the `"plotly"` engine, to
  [`world_query()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_query.md)
  for `"ggsql"`, and to
  [`mapgl::maplibre()`](https://walker-data.com/mapgl/reference/maplibre.html)
  for `"mapgl"`. The `"ggiraph"` and `"leaflet"` engines assemble their
  own map and take no further arguments; they warn rather than ignore
  what they are given.

## Value

An interactive widget.

## Examples

``` r
if (FALSE) { # \dontrun{
world_data(2020) |> interactive_map(gdp_per_capita)
world_data(2020, geometry = "sf") |>
  interactive_map(gdp_per_capita, engine = "ggsql", transform = "log10")
} # }
```
