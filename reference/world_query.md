# Emit a ggsql spatial query for a country map

Build a [ggsql](https://ggsql.org) query string that draws a choropleth
from a registered countryatlas source: the same idea as
[`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md),
but the map is rendered **in the database** (DuckDB) by ggsql, which
returns a plot specification it can draw as SVG or as an interactive
widget, so the geometry never has to come back into R. Pure string
builder with no dependencies; pair it with
[`as_ggsql_source()`](https://pursuitofdatascience.github.io/countryatlas/reference/as_ggsql_source.md)
and
[`ggsql::ggsql_execute()`](https://r.ggsql.org/reference/ggsql_execute.html),
or drop the string into a `{ggsql}` chunk.

## Usage

``` r
world_query(
  fill,
  source = "countryatlas_world",
  projection = "equal_earth",
  palette = "viridis",
  transform = NULL,
  title = NULL,
  draw = "spatial",
  layer = c("choropleth", "bubble", "binned"),
  facet = NULL,
  size = NULL,
  n_bins = NULL,
  geometry = "geometry"
)
```

## Arguments

- fill:

  The fill column (unquoted or a string).

- source:

  The table/source name registered with ggsql (default
  `"countryatlas_world"`).

- projection:

  A projection: one of the package's own names (see
  [`projection_info()`](https://pursuitofdatascience.github.io/countryatlas/reference/projection_info.md)),
  all thirteen translated to ggsql's (`"plate_carree"` becomes
  `equirectangular`, `"natural_earth"` becomes `natural`,
  `"azimuthal_equal_area"` becomes `lambert`, the polar views become
  `lambert` centred on a pole, and `"gall_peters"` a cylindrical
  equal-area CRS), or any other name ggsql's `PROJECT TO` understands,
  passed through. `NULL` omits the clause.

- palette:

  A scale ggsql's `SCALE ... TO` understands (default `"viridis"`), or
  `NULL` to omit.

- transform:

  Optional scale transform for `SCALE ... VIA` (e.g. `"log10"`).

- title:

  Optional plot title (`LABEL title => ...`).

- draw:

  The layer that draws the countries (default `"spatial"`).

- layer:

  `"choropleth"` (default), `"bubble"` (proportional symbols at each
  country's centroid over the countries, which needs `size`) or
  `"binned"` (a classed fill, see `n_bins`).

- facet:

  Optional column to facet the query by, e.g. `"year"` for a
  small-multiple panel rendered in the database.

- size:

  Column driving symbol size for `layer = "bubble"`.

- n_bins:

  Number of classes for `layer = "binned"` (default `5`); ggsql places
  the breaks, as close to this many as round numbers allow.

- geometry:

  The source's geometry column (default `"geometry"`, the name
  [`as_ggsql_source()`](https://pursuitofdatascience.github.io/countryatlas/reference/as_ggsql_source.md)
  writes).

## Value

A `ggsql_query` string (prints as the formatted query).

## Executing the query

Building the string needs nothing installed. *Running* it needs `ggsql`
\>= 0.5.0; the grammar was checked against 0.5.2, the first release on
CRAN with the `DRAW spatial` layer (2026-10-08). The query records that
version as its `"countryatlas_ggsql_version"` attribute, and
[`interactive_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/interactive_map.md)`(engine = "ggsql")`
refuses an older `ggsql`. The spatial layer also needs DuckDB's
`spatial` extension, which
[`as_ggsql_source()`](https://pursuitofdatascience.github.io/countryatlas/reference/as_ggsql_source.md)`(format = "reader")`
loads; ggsql's DuckDB downloads it once per session, into the session's
temporary directory. For `layer = "bubble"` the source needs
`centroid_lon` and `centroid_lat` columns, which
[`as_ggsql_source()`](https://pursuitofdatascience.github.io/countryatlas/reference/as_ggsql_source.md)
adds for a frame keyed on `iso3c`.

## Examples

``` r
world_query(gdp_per_capita, projection = "equal_earth",
            palette = "magma", transform = "log10",
            title = "GDP per capita")
#> VISUALISE gdp_per_capita AS fill, geometry FROM countryatlas_world
#> DRAW spatial
#> PROJECT TO equal_earth
#> SCALE fill TO magma VIA log10
#> LABEL title => 'GDP per capita'
world_query(gdp_per_capita, layer = "bubble", size = "population")
#> VISUALISE FROM countryatlas_world
#> DRAW spatial
#>   MAPPING geometry
#> DRAW point
#>   MAPPING centroid_lon AS lon, centroid_lat AS lat, population AS size, gdp_per_capita AS fill
#> PROJECT TO equal_earth
#> SCALE fill TO viridis
```
