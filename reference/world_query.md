# Emit a ggsql spatial query for a country map

Build a [ggsql](https://ggsql.org) query string that draws a choropleth
from a registered countryatlas source – the same idea as
[`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md),
but the map is rendered **in the database** (DuckDB) and returned as a
web-ready Vega-Lite widget, so the geometry never has to come back into
R. Pure string builder with no dependencies; pair it with
[`as_ggsql_source()`](https://pursuitofdatascience.github.io/countryatlas/reference/as_ggsql_source.md) +
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
  n_bins = NULL
)
```

## Arguments

- fill:

  The fill column (unquoted or a string).

- source:

  The table/source name registered with ggsql (default
  `"countryatlas_world"`).

- projection:

  A projection ggsql's `PROJECT TO` understands (e.g. `"equal_earth"`,
  `"orthographic"`), or `NULL` to omit the clause.

- palette:

  A scale ggsql's `SCALE ... TO` understands (default `"viridis"`), or
  `NULL` to omit.

- transform:

  Optional scale transform for `SCALE ... VIA` (e.g. `"log10"`).

- title:

  Optional plot title (`LABEL title => ...`).

- draw:

  The spatial layer (default `"spatial"`).

- layer:

  `"choropleth"` (default), `"bubble"` (proportional symbols – needs
  `size`) or `"binned"` (classed fill – see `n_bins`).

- facet:

  Optional column to facet the query by, e.g. `"year"` for a
  small-multiple panel rendered in the database.

- size:

  Column driving symbol size for `layer = "bubble"`.

- n_bins:

  Number of classes for `layer = "binned"` (default `5`).

## Value

A `ggsql_query` string (prints as the formatted query).

## Executing the query

Building the string needs nothing installed. *Running* it needs `ggsql`
\>= 0.4.1, the version that added the `DRAW spatial` clause; older
`ggsql` releases parse the query and reject that clause. As of August
2026 that clause has shipped in the ggsql *engine* but not yet in the
ggsql R package (still 0.3.3), so
[`interactive_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/interactive_map.md)`(engine = "ggsql")`
will refuse until the bindings catch up. `PROJECT TO` additionally needs
a spatial backend – for DuckDB, its `spatial` extension.

## Examples

``` r
world_query(gdp_per_capita, projection = "equal_earth",
            palette = "magma", transform = "log10",
            title = "GDP per capita")
#> VISUALISE gdp_per_capita AS fill
#> FROM countryatlas_world
#> DRAW spatial
#> PROJECT TO equal_earth
#> SCALE fill TO magma VIA log10
#> LABEL title => 'GDP per capita'
```
