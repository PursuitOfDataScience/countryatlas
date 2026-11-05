# Export a countryatlas table as a ggsql source

Hand countryatlas's curated, ISO-reconciled, WDI-joined spatial table to
[ggsql](https://ggsql.org) so it can be charted with `DRAW spatial`: the
bridge that lets ggsql draw maps of *your* override-corrected data
instead of its static bundled world. `sf` geometry is WKB-encoded in
longitude and latitude, which is what ggsql reads, and a frame keyed on
`iso3c` gains `centroid_lon` and `centroid_lat` for
[`world_query()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_query.md)`(layer = "bubble")`.

## Usage

``` r
as_ggsql_source(
  data,
  name = "countryatlas_world",
  format = c("reader", "frame", "duckdb", "parquet", "arrow"),
  con = NULL,
  path = NULL,
  geometry_col = "geometry"
)
```

## Arguments

- data:

  A map-ready frame (ideally `sf`, so `DRAW spatial` has geometry).

- name:

  The table name to register/write (default `"countryatlas_world"`).

- format:

  `"reader"` (the default: a ggsql reader with the table registered,
  which is what
  [`ggsql::ggsql_execute()`](https://r.ggsql.org/reference/ggsql_execute.html)
  takes), `"frame"` (the prepared data frame itself, which a `{ggsql}`
  chunk reads as `FROM r:<object>`), `"duckdb"` (write to a DuckDB
  connection and return it), `"parquet"` (write a Parquet file and
  return its path) or `"arrow"` (return a nanoarrow array stream).
  Passing `con` without `format` means `"duckdb"`.

- con:

  An existing DuckDB `DBIConnection` to write into
  (`format = "duckdb"`); a fresh in-memory one is created if `NULL`.

- path:

  Output path for `format = "parquet"`. Defaults to a file named after
  `name` in the session's temporary directory, whose path is returned;
  pass one explicitly to write somewhere you choose. A package must not
  write to the working directory uninvited, which is what the bare
  `"<name>.parquet"` this used to default to did.

- geometry_col:

  Name for the WKB geometry column (default `"geometry"`).

## Value

Depending on `format`: a ggsql reader, a data frame, a DuckDB connection
(with the table written), a Parquet file path, or a nanoarrow array
stream.

`format = "reader"` with an `sf` frame also loads DuckDB's `spatial`
extension into the reader, which `DRAW spatial` needs. ggsql's DuckDB
downloads it once per session, into the session's temporary directory,
so the first call needs a network connection; without one, the reader is
returned with a warning (class `countryatlas_ggsql_spatial`) and only
non-spatial queries run.

**You own the connection** that `format = "duckdb"` returns, and duckdb
keeps its in-memory database alive until the handle is released, so
close it when you are done:

    src <- as_ggsql_source(d, format = "duckdb")
    on.exit(DBI::dbDisconnect(src, shutdown = TRUE))

`format = "parquet"` needs no such care: it closes the connection it
opened before returning the path. Passing your own `con` leaves it open
in every case, since it was never ours to close.

## Examples

``` r
if (FALSE) { # \dontrun{
# Curate in R, render in the database:
reader <- world_data(2020, geometry = "sf") |> as_ggsql_source()
spec <- ggsql::ggsql_execute(reader, world_query(gdp_per_capita))
ggsql::ggsql_widget(spec)
} # }
```
