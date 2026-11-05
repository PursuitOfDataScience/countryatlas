# ggsql bridge -----------------------------------------------------------------
# Make countryatlas the curated, ISO-reconciled, WDI-joined data layer for
# ggsql's database-side spatial rendering (DRAW spatial). ggsql, duckdb, DBI,
# nanoarrow and sf are all optional Suggests, gated by check_installed().

# The ggsql R package release whose grammar world_query() emits. 0.5.2, on CRAN
# since 2026-10-08, is the first release there with DRAW spatial, and every
# query this file emits was checked against it, by ggsql_validate() and by
# executing it (tests/testthat/test-ggsql.R). The 0.4.x releases never reached
# CRAN, and the queries 4.0.0 first wrote for them were rejected by 0.5.2 in
# every form: the spatial layer wanted its geometry mapped, facets are
# `FACET <col>`, binning is a scale, and there is no spatial_point layer.
GGSQL_VERSION <- "0.5.0"

# WKB-encode an sf frame's geometry into a BLOB column so ggsql's DRAW spatial
# can read it, with each country's centroid alongside for the bubble layer;
# pass non-sf frames through with the centroids added.
ggsql_wkb_frame <- function(data, geometry_col = "geometry") {
  if (!is_sf(data)) return(tibble::as_tibble(ggsql_add_centroids(data)))
  need_pkg("sf", "to WKB-encode geometry for ggsql")
  # WKB carries no CRS, and ggsql reads it as longitude/latitude unless told
  # otherwise. attach_geometry(geometry = "sf") returns Equal Earth metres,
  # which ggsql took for degrees, so every map drew as an empty panel: go back
  # to longitude/latitude, and let the query's PROJECT TO project.
  if (!is.na(sf::st_crs(data)) && !isTRUE(sf::st_is_longlat(data))) {
    data <- sf::st_transform(data, 4326)
  }
  geom <- sf::st_geometry(data)
  df <- sf::st_drop_geometry(data)
  # st_as_binary() returns a classed "WKB" object, which tibble rejects ("all
  # columns must be vectors"). Strip the class: the payload is already a list
  # of raw vectors, which is what nanoarrow encodes as binary and DBI writes
  # as a BLOB.
  # Say so before clobbering, as the eleven other column-adding verbs do: a
  # frame that already had a column of this name lost it in silence.
  warn_overwrite(df, geometry_col)
  df[[geometry_col]] <- unclass(sf::st_as_binary(geom, EWKB = FALSE))
  tibble::as_tibble(ggsql_add_centroids(df))
}

# A point per country for world_query(layer = "bubble"), in degrees: the
# country_meta centroids bubble_map() places its symbols at. Added only where
# the frame is keyed on iso3c and has no columns of these names already.
ggsql_add_centroids <- function(df) {
  if (!"iso3c" %in% names(df) ||
      any(c("centroid_lon", "centroid_lat") %in% names(df))) {
    return(df)
  }
  meta <- countryatlas::country_meta
  i <- match(df$iso3c, meta$iso3c)
  df$centroid_lon <- meta$centroid_lon[i]
  df$centroid_lat <- meta$centroid_lat[i]
  df
}

#' Emit a ggsql spatial query for a country map
#'
#' Build a [ggsql](https://ggsql.org) query string that draws a choropleth from
#' a registered countryatlas source: the same idea as [world_map()], but the
#' map is rendered **in the database** (DuckDB) by ggsql, which returns a plot
#' specification it can draw as SVG or as an interactive widget, so the
#' geometry never has to come back into R. Pure string builder with no
#' dependencies; pair it with [as_ggsql_source()] and `ggsql::ggsql_execute()`,
#' or drop the string into a ````{ggsql}```` chunk.
#'
#' @param fill The fill column (unquoted or a string).
#' @param source The table/source name registered with ggsql (default
#'   `"countryatlas_world"`).
#' @param projection A projection: one of the package's own names (see
#'   [projection_info()]), all thirteen translated to ggsql's (`"plate_carree"`
#'   becomes `equirectangular`, `"natural_earth"` becomes `natural`,
#'   `"azimuthal_equal_area"` becomes `lambert`, the polar views become
#'   `lambert` centred on a pole, and `"gall_peters"` a cylindrical equal-area
#'   CRS), or any other name ggsql's `PROJECT TO` understands, passed through.
#'   `NULL` omits the clause.
#' @param palette A scale ggsql's `SCALE ... TO` understands (default
#'   `"viridis"`), or `NULL` to omit.
#' @param transform Optional scale transform for `SCALE ... VIA` (e.g.
#'   `"log10"`).
#' @param title Optional plot title (`LABEL title => ...`).
#' @param draw The layer that draws the countries (default `"spatial"`).
#' @param layer `"choropleth"` (default), `"bubble"` (proportional symbols at
#'   each country's centroid over the countries, which needs `size`) or
#'   `"binned"` (a classed fill, see `n_bins`).
#' @param facet Optional column to facet the query by, e.g. `"year"` for a
#'   small-multiple panel rendered in the database.
#' @param size Column driving symbol size for `layer = "bubble"`.
#' @param n_bins Number of classes for `layer = "binned"` (default `5`); ggsql
#'   places the breaks, as close to this many as round numbers allow.
#' @param geometry The source's geometry column (default `"geometry"`, the
#'   name [as_ggsql_source()] writes).
#'
#' @return A `ggsql_query` string (prints as the formatted query).
#' @section Executing the query:
#' Building the string needs nothing installed. *Running* it needs `ggsql` >=
#' 0.5.0; the grammar was checked against 0.5.2, the first release on CRAN with
#' the `DRAW spatial` layer (2026-10-08). The query records that version as
#' its `"countryatlas_ggsql_version"` attribute, and
#' [interactive_map()]`(engine = "ggsql")` refuses an older `ggsql`. The
#' spatial layer also needs DuckDB's `spatial` extension, which
#' [as_ggsql_source()]`(format = "reader")` loads; ggsql's DuckDB downloads it
#' once per session, into the session's temporary directory. For
#' `layer = "bubble"` the source needs `centroid_lon` and `centroid_lat`
#' columns, which [as_ggsql_source()] adds for a frame keyed on `iso3c`.
#' @export
#' @examples
#' world_query(gdp_per_capita, projection = "equal_earth",
#'             palette = "magma", transform = "log10",
#'             title = "GDP per capita")
#' world_query(gdp_per_capita, layer = "bubble", size = "population")
world_query <- function(fill, source = "countryatlas_world",
                        projection = "equal_earth", palette = "viridis",
                        transform = NULL, title = NULL, draw = "spatial",
                        layer = c("choropleth", "bubble", "binned"),
                        facet = NULL, size = NULL, n_bins = NULL,
                        geometry = "geometry") {
  fill_name <- quo_arg_name(rlang::enquo(fill), "fill")
  layer <- rlang::arg_match(layer)
  check_string(source, "source")
  check_string(draw, "draw")
  # Guarded before the is.null() tests below, which force the promise.
  facet_expr <- substitute(facet)
  facet <- tryCatch(force(facet), error = function(e) {
    abort_bare_column(facet_expr, "facet", e)
  })
  size_expr <- substitute(size)
  size <- tryCatch(force(size), error = function(e) {
    abort_bare_column(size_expr, "size", e)
  })
  if (!is.null(facet)) check_string(facet, "facet")
  if (!is.null(size)) check_string(size, "size")
  if (!is.null(n_bins)) {
    # hi: the value is coerced with as.integer() below, which returns NA past
    # 2^31-1 with a bare "NAs introduced by coercion" -- the query then read
    # "BIN fill INTO NA". compute_breaks() has carried this bound all along.
    check_number(n_bins, "n_bins", lo = 2, hi = .Machine$integer.max)
  }
  # `size` belongs to "bubble" and `n_bins` to "binned", and the other layers
  # took them without a word: n_bins was simply dropped (only the binned layer
  # emits a BIN clause), while size still went into the VISUALISE list as
  # `pop AS size` on a choropleth, which has no size channel to put it on. The
  # emission is left alone -- it is what a pass-through query builder does, and
  # what ggsql makes of it is ggsql's business -- but the silence is not, since
  # the neighbouring abort already treats layer/argument mismatches as worth
  # naming.
  # `[[` on a named vector throws for a name that is not there, so "choropleth"
  # -- which uses neither argument -- has to be handled explicitly.
  layer_arg <- c(bubble = "size", binned = "n_bins")
  used <- if (layer %in% names(layer_arg)) layer_arg[[layer]] else character(0)
  inert <- setdiff(
    c(if (!is.null(size)) "size", if (!is.null(n_bins)) "n_bins"), used
  )
  if (length(inert)) {
    wdj_warn(c(
      "{.code layer = \"{layer}\"} does not use
       {cli::qty(length(inert))}{?this argument/these arguments}: {.arg {inert}}.",
      "i" = '{.arg size} applies to {.code layer = "bubble"} and {.arg n_bins}
             to {.code layer = "binned"}.'
    ), class = "countryatlas_layer_args_ignored")
  }
  if (identical(layer, "bubble") && is.null(size)) {
    wdj_abort(c(
      '{.code layer = "bubble"} needs a {.arg size} column.',
      "i" = "A proportional-symbol map has nothing to size the symbols by
             otherwise."
    ))
  }
  if (identical(layer, "binned") && is.null(n_bins)) n_bins <- 5
  if (!is.null(projection)) check_string(projection, "projection")
  if (!is.null(palette)) check_string(palette, "palette")
  if (!is.null(transform)) check_string(transform, "transform")
  if (!is.null(title)) check_string(title, "title", allow_empty = TRUE)
  # Only `title` was escaped, and it is the one value that lands inside quotes.
  # Everything else is interpolated as a bare SQL *identifier* or keyword, so a
  # column name with a space produced invalid SQL with no diagnostic
  # ("VISUALISE my col AS fill"), and a value derived from untrusted input --
  # a column picked from a web form, a source name out of a config file --
  # went into a string that is then handed to ggsql::ggsql_execute() to run.
  # Validate the shape here, where the mistake is: an unquoted SQL identifier
  # is a letter or underscore followed by letters, digits or underscores.
  check_sql_ident(fill_name, "fill")
  check_sql_ident(source, "source")
  check_sql_ident(draw, "draw")
  check_sql_ident(geometry, "geometry")
  if (!is.null(size)) check_sql_ident(size, "size")
  if (!is.null(facet)) check_sql_ident(facet, "facet")
  if (!is.null(projection)) check_sql_ident(projection, "projection")
  if (!is.null(palette)) check_sql_ident(palette, "palette")
  if (!is.null(transform)) check_sql_ident(transform, "transform")
  geom_map <- if (identical(geometry, "geometry")) "geometry" else
    paste(geometry, "AS geometry")
  lines <- if (identical(layer, "bubble")) {
    # The countries underneath, then a point per country at its centroid: the
    # map coordinate system's position aesthetics are lon and lat.
    c(sprintf("VISUALISE FROM %s", source),
      sprintf("DRAW %s", draw),
      sprintf("  MAPPING %s", geom_map),
      "DRAW point",
      sprintf("  MAPPING centroid_lon AS lon, centroid_lat AS lat, %s AS size, %s AS fill",
              size, fill_name))
  } else {
    # The geometry is mapped explicitly. ggsql finds a geometry column by
    # itself when the query runs, but ggsql_validate() has no data to look in
    # and rejects the query without it.
    c(sprintf("VISUALISE %s AS fill, %s FROM %s", fill_name, geom_map, source),
      sprintf("DRAW %s", draw))
  }
  if (!is.null(projection)) {
    lines <- c(lines, paste("PROJECT TO", ggsql_projection(projection)))
  }
  binned <- identical(layer, "binned")
  if (!is.null(palette) || !is.null(transform) || binned) {
    scale_line <- paste0("SCALE ", if (binned) "BINNED ", "fill")
    if (!is.null(palette)) scale_line <- paste(scale_line, "TO", palette)
    if (!is.null(transform)) scale_line <- paste(scale_line, "VIA", transform)
    if (binned) {
      scale_line <- paste(scale_line, "SETTING breaks =>", as.integer(n_bins))
    }
    lines <- c(lines, scale_line)
  }
  if (!is.null(facet)) {
    lines <- c(lines, sprintf("FACET %s", facet))
  }
  if (!is.null(title)) {
    lines <- c(lines, sprintf("LABEL title => '%s'", ggsql_string(title)))
  }
  structure(paste(lines, collapse = "\n"), class = c("ggsql_query", "character"),
            countryatlas_ggsql_version = GGSQL_VERSION)
}

# The package's thirteen projections in ggsql's PROJECT TO vocabulary, read
# from ggsql 0.5.2's map coordinate system documentation
# (https://ggsql.org/syntax/coord/crs.html) and drawn by it in
# tests/testthat/test-ggsql.R. ggsql spells three of them differently, the
# polar views are its Lambert azimuthal centred on a pole, the orthographic
# view is centred where the package's is (ORTHO_LAT0), and Gall-Peters, which
# has no name there, is given as a PROJ string.
ggsql_projection_table <- function() {
  tibble::tribble(
    ~projection,             ~ggsql,
    "equal_earth",           "equal_earth",
    "robinson",              "robinson",
    "mollweide",             "mollweide",
    "natural_earth",         "natural",
    "plate_carree",          "equirectangular",
    "mercator",              "mercator",
    "winkel_tripel",         "winkel_tripel",
    "eckert4",               "eckert4",
    "gall_peters",           "crs SETTING target => '+proj=cea +lat_ts=45'",
    "orthographic",          sprintf("orthographic SETTING origin => (0, %d)",
                                     as.integer(ORTHO_LAT0)),
    "azimuthal_equal_area",  "lambert",
    "north_polar",           "lambert SETTING origin => (0, 90)",
    "south_polar",           "lambert SETTING origin => (0, -90)"
  )
}

# One projection name, resolved to what follows PROJECT TO: the package's name
# translated, and any other name passed through unchanged, since ggsql may
# know it.
ggsql_projection <- function(projection) {
  tab <- ggsql_projection_table()
  i <- match(projection, tab$projection)
  if (is.na(i)) projection else tab$ggsql[i]
}

# The body of a single-quoted ggsql string. ggsql escapes with a backslash, not
# by doubling the quote as SQL does: the doubled form this used to write,
# 'World''s GDP', is a parse error in ggsql 0.5.2, so any title with an
# apostrophe broke the query. Backslashes first, so an escape is not doubled.
ggsql_string <- function(x) {
  gsub("'", "\\'", gsub("\\", "\\\\", x, fixed = TRUE), fixed = TRUE)
}

# Refuse anything that is not a bare SQL identifier. This builder emits a
# query as text, so every interpolated name is unquoted SQL: a space, a quote,
# a semicolon or a comment marker either breaks the query silently or changes
# what it does. Names that need quoting are legal in SQL but not supported
# here, and saying so is better than emitting something that fails inside
# ggsql or, worse, runs.
check_sql_ident <- function(x, arg, call = rlang::caller_env()) {
  check_string(x, arg, call = call)
  if (!grepl("^[A-Za-z_][A-Za-z0-9_]*$", x)) {
    wdj_abort(c(
      "{.arg {arg}} must be a plain SQL identifier.",
      "x" = "Got {.val {x}}.",
      "i" = "Letters, digits and underscores only, starting with a letter or
             underscore. This builder emits the name unquoted, so anything
             else would change the query rather than name a column.",
      "i" = "Rename the column first -- {.code dplyr::rename()} -- or build
             the query yourself."
    ), class = "countryatlas_bad_sql_ident", call = call)
  }
  invisible(x)
}

#' @export
print.ggsql_query <- function(x, ...) {
  cat(unclass(x), "\n", sep = "")
  invisible(x)
}

# Where a format = "parquet" export goes when the caller names no path. Never
# the working directory: CRAN policy is that a package writes nowhere but the
# session temp dir unless the caller says otherwise, and the bare
# paste0(name, ".parquet") this used to default to is a *relative* path, so it
# landed in getwd(). The path is returned to the caller, so a temp default is
# still usable. Separated out so it is testable without duckdb installed.
ggsql_parquet_path <- function(name, path = NULL) {
  path %||% file.path(tempdir(), paste0(name, ".parquet"))
}

# A throwaway in-memory DuckDB for handing one table to ggsql.
#
# duckdb keeps downloaded extensions and secrets in ~/.duckdb by default and
# announces it on every connection. Seeding a directory in the user's home just
# to hold a temporary table is exactly what CRAN policy asks packages not to do,
# and `R CMD check` reports a new ~/.duckdb under "new files in some other
# directories" (~ is snapshotted, so a directory directly inside it shows up).
# shared_home = FALSE puts that state in a temp directory instead. The argument
# arrived in duckdb 1.4 and DESCRIPTION pins no version, so only pass it when
# the installed duckdb actually has it.
wdj_duckdb <- function() {
  if ("shared_home" %in% names(formals(duckdb::duckdb))) {
    duckdb::duckdb(shared_home = FALSE)
  } else {
    duckdb::duckdb()
  }
}

#' Export a countryatlas table as a ggsql source
#'
#' Hand countryatlas's curated, ISO-reconciled, WDI-joined spatial table to
#' [ggsql](https://ggsql.org) so it can be charted with `DRAW spatial`: the
#' bridge that lets ggsql draw maps of *your* override-corrected data instead
#' of its static bundled world. `sf` geometry is WKB-encoded in longitude and
#' latitude, which is what ggsql reads, and a frame keyed on `iso3c` gains
#' `centroid_lon` and `centroid_lat` for [world_query()]`(layer = "bubble")`.
#'
#' @param data A map-ready frame (ideally `sf`, so `DRAW spatial` has geometry).
#' @param name The table name to register/write (default `"countryatlas_world"`).
#' @param format `"reader"` (the default: a ggsql reader with the table
#'   registered, which is what `ggsql::ggsql_execute()` takes), `"frame"` (the
#'   prepared data frame itself, which a ````{ggsql}```` chunk reads as
#'   `FROM r:<object>`), `"duckdb"` (write to a DuckDB connection and return
#'   it), `"parquet"` (write a Parquet file and return its path) or `"arrow"`
#'   (return a nanoarrow array stream). Passing `con` without `format` means
#'   `"duckdb"`.
#' @param con An existing DuckDB `DBIConnection` to write into (`format =
#'   "duckdb"`); a fresh in-memory one is created if `NULL`.
#' @param path Output path for `format = "parquet"`. Defaults to a file named
#'   after `name` in the session's temporary directory, whose path is returned;
#'   pass one explicitly to write somewhere you choose. A package must not write
#'   to the working directory uninvited, which is what the bare `"<name>.parquet"`
#'   this used to default to did.
#' @param geometry_col Name for the WKB geometry column (default `"geometry"`).
#'
#' @return Depending on `format`: a ggsql reader, a data frame, a DuckDB
#'   connection (with the table written), a Parquet file path, or a nanoarrow
#'   array stream.
#'
#'   `format = "reader"` with an `sf` frame also loads DuckDB's `spatial`
#'   extension into the reader, which `DRAW spatial` needs. ggsql's DuckDB
#'   downloads it once per session, into the session's temporary directory, so
#'   the first call needs a network connection; without one, the reader is
#'   returned with a warning (class `countryatlas_ggsql_spatial`) and only
#'   non-spatial queries run.
#'
#'   **You own the connection** that `format = "duckdb"` returns, and duckdb
#'   keeps its in-memory database alive until the handle is released, so close
#'   it when you are done:
#'   ```r
#'   src <- as_ggsql_source(d, format = "duckdb")
#'   on.exit(DBI::dbDisconnect(src, shutdown = TRUE))
#'   ```
#'   `format = "parquet"` needs no such care: it closes the connection it
#'   opened before returning the path. Passing your own `con` leaves it open
#'   in every case, since it was never ours to close.
#' @export
#' @examples
#' \dontrun{
#' # Curate in R, render in the database:
#' reader <- world_data(2020, geometry = "sf") |> as_ggsql_source()
#' spec <- ggsql::ggsql_execute(reader, world_query(gdp_per_capita))
#' ggsql::ggsql_widget(spec)
#' }
as_ggsql_source <- function(data, name = "countryatlas_world",
                            format = c("reader", "frame", "duckdb", "parquet",
                                       "arrow"),
                            con = NULL, path = NULL, geometry_col = "geometry") {
  # A connection handed in is a connection to write into.
  if (missing(format) && !is.null(con)) format <- "duckdb"
  format <- rlang::arg_match(format)
  check_string(name, "name")
  # Same bare-column guard as the verbs in analysis.R: this argument takes a
  # column name as a string, and writing it unquoted -- as the tidy-eval verbs
  # next door allow -- otherwise reached the user as base R's "object not
  # found", naming neither the argument nor the string it wanted.
  geometry_col_expr <- substitute(geometry_col)
  geometry_col <- tryCatch(force(geometry_col), error = function(e) {
    abort_bare_column(geometry_col_expr, "geometry_col", e)
  })
  check_string(geometry_col, "geometry_col")
  if (!is.null(path)) check_string(path, "path")
  # `data` is documented as a map-ready frame, and nothing checked it:
  # as_ggsql_source(1:5) wrote an integer vector out as a table and handed back
  # a connection, so a "world source" could contain no countries at all.
  if (!is.data.frame(data)) {
    wdj_abort(c(
      "{.arg data} must be a data frame.",
      "x" = "Got {.cls {class(data)[1]}}.",
      "i" = "Pass a map-ready frame -- ideally {.pkg sf}, so
             {.code DRAW spatial} has geometry to work with."
    ))
  }
  df <- ggsql_wkb_frame(data, geometry_col)

  if (format == "frame") return(df)

  if (format == "reader") {
    need_pkg("ggsql", 'for as_ggsql_source(format = "reader")',
             version = GGSQL_VERSION)
    reader <- ggsql::duckdb_reader()
    ggsql::ggsql_register(reader, as.data.frame(df), name)
    if (is_sf(data)) ggsql_load_spatial(reader)
    return(reader)
  }

  if (format == "arrow") {
    need_pkg("nanoarrow", "for as_ggsql_source(format = \"arrow\")")
    return(nanoarrow::as_nanoarrow_array_stream(df))
  }

  need_pkg(c("DBI", "duckdb"), sprintf("for as_ggsql_source(format = \"%s\")", format))
  # A connection the caller already closed reached dbWriteTable() as base R's
  # bare "Invalid connection", naming neither the argument nor the state it was
  # in. Checked here rather than left to the write, for the same reason the
  # own_con bookkeeping below exists: this is the one place that knows whose
  # connection it is.
  if (!is.null(con)) {
    if (!inherits(con, "DBIConnection")) {
      wdj_abort(c(
        "{.arg con} must be a {.cls DBIConnection}.",
        "x" = "Got {.cls {class(con)[1]}}.",
        "i" = "Leave it {.code NULL} for a fresh in-memory DuckDB."
      ))
    }
    if (!isTRUE(DBI::dbIsValid(con))) {
      wdj_abort(c(
        "{.arg con} is closed.",
        "i" = "Open a new connection, or leave it {.code NULL} for a fresh
               in-memory DuckDB."
      ))
    }
  }
  own_con <- is.null(con)
  con <- con %||% DBI::dbConnect(wdj_duckdb())
  if (own_con) {
    # If the write throws, the caller never receives the handle and so cannot
    # close it, while duckdb holds the in-memory database open. Release a
    # connection we opened ourselves; one passed in was never ours to close.
    written <- FALSE
    on.exit(
      if (!written) try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE),
      add = TRUE
    )
  }
  DBI::dbWriteTable(con, name, as.data.frame(df), overwrite = TRUE)

  if (format == "parquet") {
    path <- ggsql_parquet_path(name, path)
    # dbQuoteString(), not sprintf("'%s'"): a path may legally contain an
    # apostrophe, which would otherwise close the SQL literal early.
    DBI::dbExecute(con, sprintf(
      "COPY %s TO %s (FORMAT PARQUET)",
      DBI::dbQuoteIdentifier(con, name), DBI::dbQuoteString(con, path)
    ))
    # Not marked `written` on this branch, so the on.exit() above closes a
    # connection we opened whether the COPY succeeds or fails. It used to be
    # marked straight after the table write, which disarmed that handler, and
    # the disconnect below the COPY was then the only one, so a path that
    # could not be written left the in-memory database open with no handle
    # the caller could close.
    return(invisible(path))
  }
  if (own_con) written <- TRUE
  invisible(con)
}


# Load DuckDB's spatial extension into a ggsql reader: DRAW spatial needs it.
# ggsql's DuckDB keeps its home in the session's temporary directory but does
# not create it, so INSTALL failed with "Can't find the home directory"; point
# the extension directory at a folder made here instead. INSTALL downloads the
# extension the first time in a session; LOAD alone is enough after that.
ggsql_load_spatial <- function(reader) {
  dir <- file.path(tempdir(), "duckdb-extensions")
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  dir <- gsub("'", "''", normalizePath(dir, winslash = "/", mustWork = FALSE))
  sql <- sprintf("SET extension_directory = '%s'; INSTALL spatial; LOAD spatial;",
                 dir)
  res <- tryCatch(ggsql::ggsql_execute_sql(reader, sql), error = identity)
  if (inherits(res, "error")) {
    wdj_warn(c(
      "DuckDB's {.val spatial} extension could not be loaded, so
       {.code DRAW spatial} cannot run on this reader.",
      "i" = "ggsql's DuckDB downloads the extension once per session, into
             the session's temporary directory, which needs a network
             connection.",
      "x" = conditionMessage(res)
    ), class = "countryatlas_ggsql_spatial")
  }
  invisible(reader)
}
