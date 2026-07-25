# countryatlas and ggsql

[ggsql](https://ggsql.org) is a grammar of graphics for SQL: you
describe a plot *inside a SQL query* and it renders in the database
(DuckDB), returning a web-ready Vega-Lite widget — no ggplot2 or `sf`
runtime required. Version 0.4.1 added a spatial layer (`DRAW spatial`)
that reads WKB geometry.

countryatlas and ggsql fit together cleanly:

- **countryatlas** does the part ggsql’s static bundled world can’t —
  reconcile messy country names to the ISO spine, repair the entities
  map backends get wrong
  ([`country_overrides()`](https://pursuitofdatascience.github.io/countryatlas/reference/wdj_overrides.md)),
  and join World Bank indicators onto geometry.
- **ggsql** does the part countryatlas doesn’t — push the rendering down
  into the database and emit Vega-Lite, so the geometry never has to
  come back into R.

So countryatlas becomes the *data layer* and ggsql the *renderer*.

## Emit a query (no dependencies)

[`world_query()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_query.md)
is a pure string builder — it needs nothing installed — so you can see
exactly what will be sent to ggsql:

``` r

world_query(
  gdp_per_capita,
  projection = "equal_earth",
  palette    = "magma",
  transform  = "log10",
  title      = "GDP per capita"
)
#> VISUALISE gdp_per_capita AS fill
#> FROM countryatlas_world
#> DRAW spatial
#> PROJECT TO equal_earth
#> SCALE fill TO magma VIA log10
#> LABEL title => 'GDP per capita'
```

## Render in the database

[`as_ggsql_source()`](https://pursuitofdatascience.github.io/countryatlas/reference/as_ggsql_source.md)
exports a curated countryatlas table (with `sf` geometry WKB-encoded) to
a DuckDB connection, a Parquet file, or a nanoarrow stream that ggsql
can read. The one-call path is `interactive_map(engine = "ggsql")`:

``` r

# needs: ggsql, duckdb, DBI, sf
world_data(2020, geometry = "sf") |>
  interactive_map(gdp_per_capita, engine = "ggsql", transform = "log10")
```

Under the hood that is just the two building blocks, which you can also
drive yourself for full control over the query:

``` r

src <- world_data(2020, geometry = "sf") |>
  as_ggsql_source(format = "duckdb")          # a DuckDB connection

q <- world_query(gdp_per_capita, projection = "orthographic", palette = "viridis")

ggsql::ggsql_execute(src, q)                  # -> Vega-Lite widget
```

## In a Quarto / R Markdown document

Loading `ggsql` registers a chunk engine. Export the source once, then
chart it in a ```` ```{ggsql} ```` block, referencing the registered
table by name:

```` default
```{r}
library(countryatlas)
library(ggsql)

src <- world_data(2020, geometry = "sf") |>
  as_ggsql_source(format = "duckdb")          # registers countryatlas_world
```

```{ggsql connection=src}
VISUALISE gdp_per_capita AS fill
FROM countryatlas_world
DRAW spatial
PROJECT TO equal_earth
SCALE fill TO magma VIA log10
LABEL title => 'GDP per capita, 2020'
```
````

## Why bother?

The win is the same as ggsql’s everywhere else: only the rendered result
leaves the database. For a single world map that is minor, but the
moment your country panel lives in a warehouse — millions of rows, many
years — pushing the aggregation and rendering down to where the data
already is, rather than pulling it into R, is the whole point.
countryatlas makes sure what you push down is keyed on an honest,
reconciled ISO spine.
