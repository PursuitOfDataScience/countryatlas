# ggsql bridge -----------------------------------------------------------------
# Make countryatlas the curated, ISO-reconciled, WDI-joined data layer for
# ggsql's database-side spatial rendering (DRAW spatial, 0.4.1+). ggsql, duckdb,
# DBI, nanoarrow and sf are all optional Suggests, gated by check_installed().

# WKB-encode an sf frame's geometry into a BLOB column so ggsql's DRAW spatial
# can read it; pass non-sf frames through unchanged.
ggsql_wkb_frame <- function(data, geometry_col = "geometry") {
  if (!is_sf(data)) return(tibble::as_tibble(data))
  need_pkg("sf", "to WKB-encode geometry for ggsql")
  geom <- sf::st_geometry(data)
  df <- sf::st_drop_geometry(data)
  df[[geometry_col]] <- sf::st_as_binary(geom, EWKB = FALSE)
  tibble::as_tibble(df)
}

#' Emit a ggsql spatial query for a country map
#'
#' Build a [ggsql](https://ggsql.org) query string that draws a choropleth from
#' a registered countryatlas source -- the same idea as [world_map()], but the
#' map is rendered **in the database** (DuckDB) and returned as a web-ready
#' Vega-Lite widget, so the geometry never has to come back into R. Pure string
#' builder with no dependencies; pair it with [as_ggsql_source()] +
#' `ggsql::ggsql_execute()`, or drop the string into a ````{ggsql}```` chunk.
#'
#' @param fill The fill column (unquoted or a string).
#' @param source The table/source name registered with ggsql (default
#'   `"countryatlas_world"`).
#' @param projection A projection ggsql's `PROJECT TO` understands (e.g.
#'   `"equal_earth"`, `"orthographic"`), or `NULL` to omit the clause.
#' @param palette A scale ggsql's `SCALE ... TO` understands (default
#'   `"viridis"`), or `NULL` to omit.
#' @param transform Optional scale transform for `SCALE ... VIA` (e.g.
#'   `"log10"`).
#' @param title Optional plot title (`LABEL title => ...`).
#' @param draw The spatial layer (default `"spatial"`).
#'
#' @return A `ggsql_query` string (prints as the formatted query).
#' @export
#' @examples
#' world_query(gdp_per_capita, projection = "equal_earth",
#'             palette = "magma", transform = "log10",
#'             title = "GDP per capita")
world_query <- function(fill, source = "countryatlas_world",
                        projection = "equal_earth", palette = "viridis",
                        transform = NULL, title = NULL, draw = "spatial") {
  fill_name <- rlang::as_name(rlang::enquo(fill))
  lines <- c(
    sprintf("VISUALISE %s AS fill", fill_name),
    sprintf("FROM %s", source),
    sprintf("DRAW %s", draw)
  )
  if (!is.null(projection)) {
    lines <- c(lines, sprintf("PROJECT TO %s", projection))
  }
  if (!is.null(palette) || !is.null(transform)) {
    scale_line <- if (!is.null(palette)) sprintf("SCALE fill TO %s", palette) else "SCALE fill"
    if (!is.null(transform)) scale_line <- paste0(scale_line, " VIA ", transform)
    lines <- c(lines, scale_line)
  }
  if (!is.null(title)) {
    lines <- c(lines, sprintf("LABEL title => '%s'", gsub("'", "''", title)))
  }
  structure(paste(lines, collapse = "\n"), class = c("ggsql_query", "character"))
}

#' @export
print.ggsql_query <- function(x, ...) {
  cat(unclass(x), "\n", sep = "")
  invisible(x)
}

#' Export a countryatlas table as a ggsql source
#'
#' Hand countryatlas's curated, ISO-reconciled, WDI-joined spatial table to
#' [ggsql](https://ggsql.org) so it can be charted with `DRAW spatial` -- the
#' bridge that lets ggsql draw maps of *your* override-corrected data instead of
#' its static bundled world. `sf` geometry is WKB-encoded so ggsql can decode it.
#'
#' @param data A map-ready frame (ideally `sf`, so `DRAW spatial` has geometry).
#' @param name The table name to register/write (default `"countryatlas_world"`).
#' @param format `"duckdb"` (write to a DuckDB connection and return it),
#'   `"parquet"` (write a Parquet file and return its path) or `"arrow"` (return
#'   a nanoarrow array stream ggsql can read directly).
#' @param con An existing DuckDB `DBIConnection` to write into (`format =
#'   "duckdb"`); a fresh in-memory one is created if `NULL`.
#' @param path Output path for `format = "parquet"` (default `"<name>.parquet"`).
#' @param geometry_col Name for the WKB geometry column (default `"geometry"`).
#'
#' @return Depending on `format`: a DuckDB connection (with the table written),
#'   a Parquet file path, or a nanoarrow array stream.
#' @export
#' @examples
#' \dontrun{
#' # Curate in R, render in the database:
#' src <- world_data(2020, geometry = "sf") |> as_ggsql_source(format = "duckdb")
#' ggsql::ggsql_execute(src, world_query(gdp_per_capita))
#' }
as_ggsql_source <- function(data, name = "countryatlas_world",
                            format = c("duckdb", "parquet", "arrow"),
                            con = NULL, path = NULL, geometry_col = "geometry") {
  format <- match.arg(format)
  df <- ggsql_wkb_frame(data, geometry_col)

  if (format == "arrow") {
    need_pkg("nanoarrow", "for as_ggsql_source(format = \"arrow\")")
    return(nanoarrow::as_nanoarrow_array_stream(df))
  }

  need_pkg(c("DBI", "duckdb"), sprintf("for as_ggsql_source(format = \"%s\")", format))
  own_con <- is.null(con)
  con <- con %||% DBI::dbConnect(duckdb::duckdb())
  DBI::dbWriteTable(con, name, as.data.frame(df), overwrite = TRUE)

  if (format == "parquet") {
    path <- path %||% paste0(name, ".parquet")
    DBI::dbExecute(con, sprintf(
      "COPY %s TO '%s' (FORMAT PARQUET)",
      DBI::dbQuoteIdentifier(con, name), path
    ))
    if (own_con) DBI::dbDisconnect(con, shutdown = TRUE)
    return(invisible(path))
  }
  invisible(con)
}
