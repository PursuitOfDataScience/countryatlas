# Export a countryatlas table as a ggsql source

Hand countryatlas's curated, ISO-reconciled, WDI-joined spatial table to
[ggsql](https://ggsql.org) so it can be charted with `DRAW spatial` –
the bridge that lets ggsql draw maps of *your* override-corrected data
instead of its static bundled world. `sf` geometry is WKB-encoded so
ggsql can decode it.

## Usage

``` r
as_ggsql_source(
  data,
  name = "countryatlas_world",
  format = c("duckdb", "parquet", "arrow"),
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

  `"duckdb"` (write to a DuckDB connection and return it), `"parquet"`
  (write a Parquet file and return its path) or `"arrow"` (return a
  nanoarrow array stream ggsql can read directly).

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

Depending on `format`: a DuckDB connection (with the table written), a
Parquet file path, or a nanoarrow array stream.

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
src <- world_data(2020, geometry = "sf") |> as_ggsql_source(format = "duckdb")
ggsql::ggsql_execute(src, world_query(gdp_per_capita))
} # }
```
