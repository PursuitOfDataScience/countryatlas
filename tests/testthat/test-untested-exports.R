# Coverage for the exports that had no test call site at all, plus the tidy-eval
# column arguments that were missed when the rest of the package gained
# existence checks. Untested paths are where every bug in this package has hidden.

snap <- countryatlas::world_snapshot$countries

test_that("wdi_search returns a tidy indicator/name tibble", {
  # Runs offline against WDI's bundled cache -- no network needed.
  out <- wdi_search("CO2 emissions")
  expect_s3_class(out, "tbl_df")
  expect_named(out, c("indicator", "name"))
  expect_gt(nrow(out), 0L)
  expect_true(all(grepl("CO2", out$name, ignore.case = TRUE)))
  # No match is an empty tibble with the same shape, not an error.
  none <- wdi_search("zzzz_no_such_indicator_zzzz")
  expect_s3_class(none, "tbl_df")
  expect_equal(nrow(none), 0L)
  expect_named(none, c("indicator", "name"))
  # Exactly one match still comes back as a one-row tibble (the branch that
  # reshapes a dimension-less result).
  one <- wdi_search("^Official Moderate Poverty Rate-National$")
  expect_equal(nrow(one), 1L)
  expect_named(one, c("indicator", "name"))
  # Searching the code field works too.
  codes <- wdi_search("SP.POP", field = "indicator")
  expect_gt(nrow(codes), 0L)
  expect_true(all(grepl("SP.POP", codes$indicator, fixed = TRUE)))
})

test_that("clear_wdi_cache forgets the memo and can remove the disk cache", {
  expect_true(clear_wdi_cache())
  dir <- file.path(tempdir(), "countryatlas-clear-test")
  dir.create(dir, showWarnings = FALSE)
  old <- options(countryatlas.cache_dir = dir)
  on.exit(options(old), add = TRUE)
  expect_true(dir.exists(dir))
  expect_true(clear_wdi_cache(disk = TRUE))
  expect_false(dir.exists(dir))
  # Removing a cache that was never created is a no-op, not an error.
  expect_true(clear_wdi_cache(disk = TRUE))
})

test_that("animate_world animates or falls back to facets", {
  skip_if_not_installed("maps")
  mapdf <- attach_geometry(snap, geometry = "polygon")
  panel <- dplyr::bind_rows(dplyr::mutate(mapdf, year = 2023L),
                            dplyr::mutate(mapdf, year = 2024L))
  p <- animate_world(panel, gdp_per_capita)
  # gganimate present -> a gganim object; absent -> a faceted ggplot.
  if (requireNamespace("gganimate", quietly = TRUE)) {
    expect_s3_class(p, "gganim")
  } else {
    expect_s3_class(p, "ggplot")
  }
  # A non-default time column is honoured, and `...` reaches world_map().
  expect_no_error(animate_world(dplyr::rename(panel, yr = year),
                                gdp_per_capita, time = yr))
  expect_no_error(animate_world(panel, gdp_per_capita, style = "quantile"))
  expect_error(animate_world(panel, gdp_per_capita, time = not_a_column),
               class = "countryatlas_error")
  # The fill column is validated through world_map().
  expect_error(animate_world(panel, not_a_column), class = "countryatlas_error")
})

test_that("cartogram_map builds every type and names a missing column", {
  skip_if_not_installed("sf")
  skip_if_not_installed("cartogram")
  skip_if_not_installed("rnaturalearth")
  sfd <- attach_geometry(snap, geometry = "sf")
  sub <- sfd[!is.na(sfd$population) & !is.na(sfd$continent) &
               sfd$continent == "Europe", ]
  expect_gt(nrow(sub), 10L)
  # "contiguous" is the default type and had never been exercised.
  expect_no_error(ggplot2::ggplot_build(
    cartogram_map(sub, population, itermax = 2)))
  expect_no_error(ggplot2::ggplot_build(
    cartogram_map(sub, population, type = "noncontiguous")))
  # A separate fill column is honoured.
  expect_no_error(ggplot2::ggplot_build(
    cartogram_map(sub, population, fill = gdp_per_capita, itermax = 2)))
  # A bad weight used to reach cartogram as "missing value where TRUE/FALSE
  # needed"; a bad fill was not caught at all.
  expect_error(cartogram_map(sub, not_a_column), "not found in")
  expect_error(cartogram_map(sub, population, fill = not_a_column),
               "not found in")
  expect_error(dorling_map(sub, not_a_column), "not found in")
  expect_error(cartogram_map(snap, population), class = "countryatlas_error")
})

test_that("index_to validates its column and its scalars", {
  df <- data.frame(iso3c = "USA", year = 2000:2002, gdp = c(50, 55, 60))
  # Used to fail with a dplyr error from inside mutate().
  expect_error(index_to(df, not_a_column, base_year = 2000), "not found in")
  expect_error(index_to(df, gdp, base_year = NA), "single finite number")
  expect_error(index_to(df, gdp, base_year = 2000, to = NA),
               "single finite number")
  expect_error(index_to(data.frame(x = 1), gdp, base_year = 2000),
               class = "countryatlas_error")
  out <- index_to(df, gdp, base_year = 2000)
  expect_equal(out$gdp_index, c(100, 110, 120))
  # A base year with no observation gives NA rather than a wrong index.
  expect_true(all(is.na(index_to(df, gdp, base_year = 1999)$gdp_index)))
})

test_that("spin_globe renders one frame per central longitude", {
  # gifski/magick assemble the GIF and are often unavailable, but the frame
  # loop is the part worth testing: it calls globe_map() once per longitude in
  # a full 0-360 sweep, which is why wdj_crs() must accept a `recenter` beyond
  # +/-180. Intercept ggsave() so the loop runs for real without writing PNGs.
  skip_if_not_installed("maps")
  skip_if_not_installed("mapproj")
  snap <- countryatlas::world_snapshot$countries
  rendered <- list()
  testthat::local_mocked_bindings(
    ggsave = function(filename, plot, ...) {
      rendered[[length(rendered) + 1L]] <<- basename(filename)
      expect_s3_class(plot, "ggplot")
      invisible(filename)
    },
    .package = "ggplot2"
  )
  # Claim an assembler exists so the loop is reached; the assembly call itself
  # then fails, which is fine -- the frames are what we are checking.
  testthat::local_mocked_bindings(
    has_pkg = function(pkg) {
      if (identical(pkg, "gifski")) TRUE else isTRUE(requireNamespace(pkg, quietly = TRUE))
    }
  )
  invisible(tryCatch(
    spin_globe(snap, continent, backend = "polygon", style = "categorical",
               n_frames = 6, width = 120, height = 120),
    error = function(e) NULL
  ))
  expect_length(rendered, 6L)
  expect_equal(rendered[[1]], "frame_0001.png")
  expect_equal(rendered[[6]], "frame_0006.png")
})

test_that("spin_globe validates its scalars before rendering anything", {
  # Deliberately NOT guarded on gifski/magick: a bad argument must be reported
  # regardless of which optional packages are installed, so these checks have
  # to run before the animation-package gate.
  snap <- countryatlas::world_snapshot$countries
  expect_error(spin_globe(snap, continent, backend = "polygon", n_frames = 1),
               "`n_frames`")
  expect_error(spin_globe(snap, continent, backend = "polygon", n_frames = NA),
               "single finite number")
  expect_error(spin_globe(snap, continent, backend = "polygon", fps = 0), "`fps`")
  expect_error(spin_globe(snap, continent, backend = "polygon", width = 0), "`width`")
  expect_error(spin_globe(snap, continent, backend = "polygon", lat = 200), "`lat`")
  # The fill column is validated by globe_map() inside the frame loop, which is
  # covered by globe_map()'s own tests -- reaching it here would need an
  # animation package installed.
})

test_that("join_world auto-detects a code column, and reads it as codes", {
  # The fallback comment said "the first column that mostly matches ISO codes",
  # but it tested with origin = "country.name", which does not match most
  # alpha-3 codes ("FRA" and "JPN" fail; "USA" happens to). And a column named
  # `iso3c` was found by the name list, which set no scheme, so
  # join_world(tibble(iso3c = c("FRA", "JPN"))) warned and returned all NA.
  expect_silent(a <- join_world(tibble::tibble(iso3c = c("FRA", "JPN"), v = 1:2),
                                geometry = "none"))
  expect_identical(a$iso3c, c("FRA", "JPN"))
  expect_silent(b <- join_world(tibble::tibble(code = c("FRA", "JPN"), v = 1:2),
                                geometry = "none"))
  expect_identical(b$iso3c, c("FRA", "JPN"))
  expect_silent(cc <- join_world(tibble::tibble(iso2c = c("FR", "JP"), v = 1:2),
                                 geometry = "none"))
  expect_identical(cc$iso3c, c("FRA", "JPN"))
  # Names still work, including in a column *named* iso3c -- the implied scheme
  # is verified before it is used, so a misnamed column falls back.
  expect_silent(d <- join_world(tibble::tibble(iso3c = c("France", "Japan")),
                                geometry = "none"))
  expect_identical(d$iso3c, c("FRA", "JPN"))
  # An explicit origin is an instruction, not a hint.
  expect_warning(e <- join_world(tibble::tibble(iso3c = c("FRA", "JPN")),
                                 origin = "country.name", geometry = "none"),
                 "could not be matched")
  expect_true(all(is.na(e$iso3c)))
  # And a column that resolves to nothing is still reported, not guessed at.
  expect_error(join_world(tibble::tibble(junk = c("zz", "qq"))),
               "auto-detect")
})

test_that("a bounding-box region warns on the polygon backend", {
  # The polygon backend drops vertices instead of clipping, so a country across
  # the edge keeps a truncated ring that geom_polygon() closes with a chord --
  # France loses 202 of 605 vertices and the ends sit 15 degrees apart. The
  # returned tibble gives no sign of it, so the call has to say so.
  skip_if_not_installed("maps")
  med <- c(-10, 30, 40, 48)
  expect_warning(pb <- world_geometry("countries", geometry = "polygon",
                                      region = med), "filters vertices")
  expect_true(all(pb$long >= med[1] & pb$long <= med[3]))
  expect_true(all(pb$lat >= med[2] & pb$lat <= med[4]))
  # Only for a box: naming countries or a continent selects whole shapes.
  expect_silent(world_geometry("countries", geometry = "polygon",
                               region = "Europe"))
  expect_silent(world_geometry("countries", geometry = "polygon"))
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
  # The sf backend does a real clip, and says nothing.
  expect_silent(world_geometry("countries", geometry = "sf", region = med))
})

test_that("globe_map(backend = 'sf') builds on every style", {
  # This whole branch had no coverage: the only sf-related test in the file ran
  # *when sf was absent*, which is how nine bugs hid in an earlier pass.
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
  sfd <- attach_geometry(countryatlas::world_snapshot$countries, geometry = "sf")
  for (st in c("continuous", "binned", "quantile", "jenks")) {
    if (st == "jenks") skip_if_not_installed("classInt")
    p <- globe_map(sfd, gdp_per_capita, backend = "sf", style = st, n_bins = 4)
    expect_s3_class(p, "ggplot")
    expect_no_error(ggplot2::ggplot_build(p))
  }
  p <- globe_map(sfd, continent, backend = "sf", style = "categorical",
                 title = "TT")
  expect_identical(p$labels$title, "TT")
  # lon/lat really do move the orthographic centre.
  crs_at <- function(lon) {
    b <- ggplot2::ggplot_build(globe_map(sfd, gdp_per_capita, backend = "sf",
                                         lon = lon))
    sf::st_crs(b$plot$coordinates$crs)$proj4string
  }
  expect_false(identical(crs_at(0), crs_at(90)))
  expect_match(crs_at(0), "ortho", fixed = TRUE)
})

test_that("print.countryatlas_coverage prints every section", {
  # The method had zero test coverage; each branch depends on a different part
  # of the report being non-empty.
  snap <- countryatlas::world_snapshot$countries
  # The cli headings go to the message stream and the tibbles to stdout; capture
  # both, or the report prints through the middle of the test run.
  msgs <- function(x) {
    out <- NULL
    m <- capture.output(out <- capture.output(print(x)), type = "message")
    c(m, out)
  }
  full <- msgs(audit_coverage(snap, by = "continent"))
  expect_true(any(grepl("Coverage audit", full)))
  expect_true(any(grepl("Missingness by indicator", full)))
  expect_true(any(grepl("Coverage by group", full)))
  # With nothing unmatched it reports success rather than a warning.
  expect_true(any(grepl("matched", full)))
  # An unmatched country takes the other branch.
  bad <- snap[1:3, ]
  bad$country[1] <- "Zzz"
  bad$iso3c[1] <- NA
  un <- msgs(audit_coverage(bad))
  expect_true(any(grepl("unmatched", un)))
  # And the object is returned invisibly, so it can be piped on.
  cv <- audit_coverage(snap)
  ret <- NULL
  invisible(capture.output(invisible(capture.output(ret <- print(cv))),
                           type = "message"))
  expect_identical(ret, cv)
})
