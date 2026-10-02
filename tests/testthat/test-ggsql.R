test_that("world_query builds a valid ggsql spatial query string", {
  q <- world_query(gdp_per_capita, projection = "equal_earth",
                   palette = "magma", transform = "log10",
                   title = "GDP per capita")
  expect_s3_class(q, "ggsql_query")
  qs <- unclass(q)
  expect_match(qs, "VISUALISE gdp_per_capita AS fill", fixed = TRUE)
  expect_match(qs, "FROM countryatlas_world", fixed = TRUE)
  expect_match(qs, "DRAW spatial", fixed = TRUE)
  expect_match(qs, "PROJECT TO equal_earth", fixed = TRUE)
  expect_match(qs, "SCALE fill TO magma VIA log10", fixed = TRUE)
  expect_match(qs, "LABEL title => 'GDP per capita'", fixed = TRUE)
})

test_that("world_query omits optional clauses when NULL", {
  q <- world_query(gdp_per_capita, projection = NULL, palette = NULL)
  qs <- unclass(q)
  expect_match(qs, "VISUALISE gdp_per_capita AS fill", fixed = TRUE)
  expect_false(grepl("PROJECT TO", qs, fixed = TRUE))
  expect_false(grepl("SCALE", qs, fixed = TRUE))
  expect_false(grepl("LABEL title", qs, fixed = TRUE))
})

test_that("world_query accepts a custom source name", {
  q <- world_query(gdp_per_capita, source = "my_custom_table")
  expect_match(unclass(q), "FROM my_custom_table", fixed = TRUE)
})

test_that("world_query handles apostrophes in titles", {
  q <- world_query(gdp_per_capita, title = "World's GDP")
  expect_match(unclass(q), "title => 'World''s GDP'", fixed = TRUE)
})

test_that("print.ggsql_query prints the query", {
  q <- world_query(gdp_per_capita)
  out <- capture.output(print(q))
  expect_match(paste(out, collapse = "\n"), "VISUALISE", fixed = TRUE)
})

test_that("as_ggsql_source writes a DuckDB table", {
  skip_slow_on_cran()
  skip_if_not_installed("duckdb")
  skip_if_not_installed("DBI")
  df <- data.frame(iso3c = c("USA", "CAN"), value = c(1, 2))
  con <- as_ggsql_source(df, format = "duckdb")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  expect_s4_class(con, "DBIConnection")
  tbls <- DBI::dbListTables(con)
  expect_true("countryatlas_world" %in% tbls)
})

test_that("as_ggsql_source writes a Parquet file", {
  skip_slow_on_cran()
  skip_if_not_installed("duckdb")
  skip_if_not_installed("DBI")
  df <- data.frame(iso3c = c("USA", "CAN"), value = c(1, 2))
  tmp <- tempfile(fileext = ".parquet")
  path <- as_ggsql_source(df, format = "parquet", path = tmp)
  expect_equal(path, tmp)
  expect_true(file.exists(tmp))
  unlink(tmp)
})

test_that("ggsql_wkb_frame passes a plain data frame through unchanged", {
  df <- data.frame(iso3c = c("USA", "CAN"), value = c(1, 2))
  out <- countryatlas:::ggsql_wkb_frame(df)
  expect_s3_class(out, "tbl_df")
  expect_equal(nrow(out), 2)
  expect_true(all(c("iso3c", "value") %in% names(out)))
})

test_that("ggsql_wkb_frame WKB-encodes real sf geometry", {
  # Regression: st_as_binary() returns a classed "WKB" object that tibble
  # rejects ("all columns must be vectors"), so every sf input to
  # as_ggsql_source() / interactive_map(engine = "ggsql") used to error.
  skip_if_no_sf_geometry()
  sfd <- world_geometry("countries", geometry = "sf", region = "Europe")
  out <- countryatlas:::ggsql_wkb_frame(sfd)
  expect_s3_class(out, "tbl_df")
  expect_equal(nrow(out), nrow(sfd))
  expect_true("geometry" %in% names(out))
  expect_type(out$geometry, "list")
  expect_true(is.raw(out$geometry[[1]]))
  # The WKB round-trips back to the geometry it came from.
  expect_s3_class(sf::st_as_sfc(structure(out$geometry, class = "WKB"),
                                EWKB = FALSE), "sfc")
})

test_that("as_ggsql_source(format = 'arrow') streams an sf frame", {
  skip_if_not_installed("nanoarrow")
  skip_if_no_sf_geometry()
  sfd <- world_geometry("countries", geometry = "sf", region = "Europe")
  stream <- as_ggsql_source(sfd, format = "arrow")
  expect_s3_class(stream, "nanoarrow_array_stream")
  # Geometry lands as an Arrow binary column ("z"), which is what ggsql reads.
  schema <- nanoarrow::infer_nanoarrow_schema(countryatlas:::ggsql_wkb_frame(sfd))
  expect_equal(schema$children$geometry$format, "z")
})

test_that("as_ggsql_source errors cleanly without duckdb/DBI", {
  skip_if(requireNamespace("duckdb", quietly = TRUE) &&
          requireNamespace("DBI", quietly = TRUE))
  df <- data.frame(iso3c = "USA", value = 1)
  # Pinned to the gate, matching the block below that already does so.
  expect_error(as_ggsql_source(df, format = "duckdb"), class = "rlib_error_package_not_found")
})

test_that("world_query omits all optional clauses and escapes quotes", {
  q <- world_query(gdp_per_capita, projection = NULL, palette = NULL,
                   title = "it's a map")
  expect_false(grepl("PROJECT", q))
  expect_false(grepl("SCALE", q))
  expect_match(q, "LABEL title => 'it''s a map'")
})

test_that("ggsql helpers error cleanly without the optional stack", {
  skip_if(requireNamespace("ggsql", quietly = TRUE))
  # With no pattern this accepted any condition at all -- a typo in the
  # fixture, or an argument error thrown before engine dispatch was reached.
  expect_error(
    interactive_map(world_snapshot$countries, gdp_per_capita, engine = "ggsql"),
    "ggsql"
  )
})

test_that("a parquet export defaults into the session temp dir, not getwd()", {
  # CRAN policy: a package writes nowhere but the session temp directory unless
  # the caller says otherwise. The default was the bare relative path
  # "<name>.parquet", which lands in the working directory. Tested through the
  # helper because the surrounding code needs duckdb, which is not installed
  # everywhere this runs.
  d <- countryatlas:::ggsql_parquet_path("countryatlas_world")
  # Compare normalised paths: on Windows tempdir() comes back with backslashes
  # while dirname() hands back forward slashes, so the raw strings differ even
  # when they name the same directory.
  norm <- function(x) normalizePath(x, winslash = "/", mustWork = FALSE)
  expect_identical(norm(dirname(d)), norm(tempdir()))
  expect_identical(basename(d), "countryatlas_world.parquet")
  expect_false(basename(d) == d)                 # i.e. not a bare relative path
  expect_true(startsWith(d, tempdir()))

  # The table name is honoured, and an explicit path always wins.
  expect_identical(basename(countryatlas:::ggsql_parquet_path("mine")),
                   "mine.parquet")
  expect_identical(countryatlas:::ggsql_parquet_path("x", "/somewhere/else.parquet"),
                   "/somewhere/else.parquet")

  # No other export writes outside the temp dir by default: spin_globe() and
  # its frames both go through tempfile().
  body_txt <- paste(deparse(body(spin_globe)), collapse = " ")
  expect_true(grepl("tempfile", body_txt, fixed = TRUE))
  expect_false(grepl("getwd", body_txt, fixed = TRUE))
})

test_that("world_query gained layers, faceting and binning", {
  q <- world_query(gdp, layer = "binned", n_bins = 4, facet = "year")
  expect_match(q, "BIN fill INTO 4")
  expect_match(q, "FACET BY year")
  b <- world_query(gdp, layer = "bubble", size = "population")
  expect_match(b, "population AS size")
  expect_match(b, "DRAW spatial_point")
  expect_error(world_query(gdp, layer = "bubble"), "needs a .*size. column")
  # The default is unchanged.
  expect_match(world_query(gdp), "DRAW spatial")
})

test_that("counts coerced with as.integer() carry an upper bound", {
  # check_number() with only `lo` lets a value past 2^31-1 through, and the
  # as.integer() below each of these turns it into NA with R's bare "NAs
  # introduced by coercion to integer range": world_query() then emitted
  # "BIN fill INTO NA", od_map()'s min(NA, nrow) reached seq_len(NA), and
  # convergence_club()'s size comparisons all became NA. compute_breaks() has
  # carried this bound since 2.0.0; these three had not.
  od <- data.frame(from = c("France", "Germany"),
                   to = c("Germany", "Italy"), w = c(1, 2))
  panel <- tibble::tibble(iso3c = rep(c("A", "B", "C"), each = 6),
                          year = rep(2000:2005, 3), v = as.numeric(1:18))
  expect_error(world_query(gdp, layer = "binned", n_bins = 3e9), "n_bins")
  expect_error(od_map(od, from, to, w, origins = 3e9), "origins")
  expect_error(convergence_club(panel, v, min_size = 3e9), "min_size")
  # Ordinary values are unaffected.
  expect_match(world_query(gdp, layer = "binned", n_bins = 5), "BIN fill INTO 5")
})

test_that("as_ggsql_source is explicit about who owns the connection", {
  skip_slow_on_cran()
  # format = "duckdb" hands back a live connection and duckdb keeps its
  # in-memory database alive until the handle is released, but neither @return
  # nor @param said the caller owns it -- while the parquet branch quietly
  # closed its own. Pin all three lifecycles so they cannot drift apart.
  skip_if_not_installed("DBI")
  skip_if_not_installed("duckdb")
  d <- data.frame(iso3c = c("USA", "FRA"), v = 1:2)

  # Ours to close, and usable when we get it.
  con <- as_ggsql_source(d, format = "duckdb")
  expect_true(DBI::dbIsValid(con))
  expect_equal(nrow(DBI::dbReadTable(con, "countryatlas_world")), 2L)
  DBI::dbDisconnect(con, shutdown = TRUE)

  # Parquet closes the connection it opened and returns only the path.
  path <- as_ggsql_source(d, format = "parquet")
  expect_true(file.exists(path))
  expect_type(path, "character")

  # A connection we were handed is never ours to close, in either format.
  own <- DBI::dbConnect(duckdb::duckdb())
  on.exit(try(DBI::dbDisconnect(own, shutdown = TRUE), silent = TRUE), add = TRUE)
  back <- as_ggsql_source(d, con = own)
  expect_identical(back, own)
  expect_true(DBI::dbIsValid(own))
  invisible(as_ggsql_source(d, format = "parquet", con = own))
  expect_true(DBI::dbIsValid(own))

  # The instruction must be in the help, not only in a code comment. Read the
  # source .Rd: an installed package has no man/ directory (the help is
  # compiled), so system.file() returns "" there and readLines("") errors --
  # the same source-tree assumption the helper below exists to avoid.
  skip_if_no_source_tree()
  rd <- "../../man/as_ggsql_source.Rd"
  skip_if_not(file.exists(rd), "Rd source not present")
  expect_match(paste(readLines(rd, warn = FALSE), collapse = " "),
               "dbDisconnect", fixed = TRUE)
})

test_that("world_query stays a dependency-free string builder", {
  # It must not gate on ggsql at all -- only executing the query does.
  q <- world_query(gdp_per_capita, projection = "equal_earth",
                   palette = "magma", transform = "log10", title = "It's a test")
  expect_s3_class(q, "ggsql_query")
  expect_match(as.character(q), "DRAW spatial", fixed = TRUE)
  expect_match(as.character(q), "PROJECT TO equal_earth", fixed = TRUE)
  expect_match(as.character(q), "SCALE fill TO magma VIA log10", fixed = TRUE)
  # A quote in the title is SQL-escaped, not injected.
  expect_match(as.character(q), "'It''s a test'", fixed = TRUE)
  # Omitting the optional clauses omits the lines.
  bare <- world_query(x, projection = NULL, palette = NULL)
  expect_false(grepl("PROJECT TO", bare, fixed = TRUE))
  expect_false(grepl("SCALE", bare, fixed = TRUE))
})

test_that("world_query() records the ggsql engine version its projection needs", {
  # PROJECT TO equal_earth was emitted by default and execution was gated on
  # 0.4.1, the DRAW spatial version -- but the engine added Equal Earth in
  # 0.5.0, so the gate would have let an unknown projection through.
  ver <- function(...) attr(world_query(gdp, ...), "countryatlas_ggsql_version")
  expect_identical(ver(), "0.5.0")
  expect_identical(ver(projection = "mercator"), "0.4.1")
  expect_identical(ver(projection = NULL), "0.4.1")
  # The package's names are translated where ggsql spells them differently.
  q <- function(p) unclass(world_query(gdp, projection = p))
  expect_match(q("plate_carree"), "PROJECT TO equirectangular", fixed = TRUE)
  expect_match(q("natural_earth"), "PROJECT TO natural", fixed = TRUE)
  expect_match(q("azimuthal_equal_area"), "PROJECT TO lambert", fixed = TRUE)
  # ggsql's own names pass through, and a name neither side lists makes no
  # version claim beyond DRAW spatial's.
  expect_match(q("sinusoidal"), "PROJECT TO sinusoidal", fixed = TRUE)
  expect_identical(ver(projection = "equirectangular"), "0.4.1")
  expect_identical(ver(projection = "sinusoidal"), "0.4.1")
  # Every name the table translates is one the package itself knows.
  tab <- countryatlas:::ggsql_projection_table()
  expect_true(all(tab$projection %in% projection_info()$projection))
})
