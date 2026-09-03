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
  expect_error(as_ggsql_source(df, format = "duckdb"))
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
