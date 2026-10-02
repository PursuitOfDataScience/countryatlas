# --- Bug: a categorical fill died at print time on a hardcoded viridis_c -------

test_that("cartogram_map and dorling_map accept a categorical fill", {
  skip_slow_on_cran()
  skip_if_not_installed("cartogram")
  d <- sf_df()
  # Each of these used to reach ggplot2's bare "Discrete value supplied to a
  # continuous scale" at *print* time, long after the call that caused it.
  renders(cartogram_map(d, population, fill = continent))
  renders(dorling_map(d, population, fill = continent))
  renders(cartogram_map(d, population, type = "noncontiguous", fill = continent))
  # ...and the numeric path still gets a continuous scale.
  renders(cartogram_map(d, population, fill = gdp_per_capita))
})

test_that("tile_map accepts a categorical fill", {
  skip_slow_on_cran()
  # The grid cannot place a few snapshot countries; that has its own test.
  renders(suppressWarnings(tile_map(snap, continent)))
  renders(suppressWarnings(tile_map(snap, gdp_per_capita)))
  renders(suppressWarnings(tile_map(snap, income)))
})

# --- cartogramR ------------------------------------------------------------------

test_that("cartogram_map(type = 'flow') uses cartogramR", {
  skip_slow_on_cran()
  skip_if_no_sf_geometry()
  skip_if_not_installed("cartogramR")
  d <- sf_df()
  renders(suppressWarnings(cartogram_map(d, population, type = "flow")))
})

test_that("each cartogram type gates on the package it actually needs", {
  # "flow" must not demand `cartogram`, nor the others `cartogramR`.
  src <- paste(deparse(cartogram_map), collapse = " ")
  expect_match(src, "cartogramR")
  expect_match(src, 'identical\\(type, "flow"\\)')
})

# --- cartograms and projections ---------------------------------------------------

test_that("gridded_cartogram allocates exactly the cells requested", {
  skip_slow_on_cran()
  # The centroid warning is expected and correct here -- a handful of
  # territories have no bundled centroid; it is asserted separately below.
  p <- suppressWarnings(gridded_cartogram(snap, population, cells = 400))
  renders(p)
  expect_warning(gridded_cartogram(snap, population, cells = 400),
                 "no bundled centroid")
  cells <- attr(p, "countryatlas_cells")
  expect_equal(sum(cells$cells), 400L)
  expect_true(all(cells$cells >= 0))
  # Every placeable country is reported, including the ones that rounded to
  # zero -- which is what makes the rounding inspectable and `share` sum to 1.
  expect_equal(sum(cells$share), 1, tolerance = 1e-9)
  expect_true(any(cells$cells == 0L))
  # Largest-remainder: a bigger country never gets fewer cells than a smaller.
  ord <- order(cells$value, decreasing = TRUE)
  expect_false(is.unsorted(rev(cells$cells[ord])))
  # An awkward total still allocates exactly, with no cells lost to a country
  # that has no centroid to be placed at.
  odd <- attr(suppressWarnings(gridded_cartogram(snap, population, cells = 997)),
              "countryatlas_cells")
  expect_equal(sum(odd$cells), 997L)
  expect_error(gridded_cartogram(snap, population, cells = 0), "cells")
})

test_that("cartogram_diagnostics measures the residual area error", {
  skip_slow_on_cran()
  skip_if_not_installed("sf")
  skip_if_not_installed("cartogram")
  skip_if_not_installed("rnaturalearth")
  d <- sf_df()
  cg <- cartogram_map(d, population)
  diag <- cartogram_diagnostics(cg)
  expect_true(all(c("target_share", "actual_share", "area_error") %in% names(diag)))
  s <- attr(diag, "countryatlas_cartogram")
  expect_true(is.finite(s$mean_abs_error))
  # Sorted worst-first.
  expect_false(is.unsorted(rev(abs(diag$area_error))))
  expect_error(cartogram_diagnostics(d), "weight.* is required")
  expect_error(cartogram_diagnostics(42), "must be a cartogram plot")
})

test_that("a cartogram reports the world it started from, not the one it kept", {
  skip_slow_on_cran()
  # A cartogram can only size a country it has a positive weight for, so the
  # rest are dropped -- silently, and provenance was computed on the survivors,
  # so n_total shrank to match. A map of 69 countries out of 175 reported
  # "69 of 73", i.e. near-complete coverage of a world it had quietly cut down.
  skip_if_not_installed("sf")
  skip_if_not_installed("cartogram")
  skip_if_not_installed("rnaturalearth")
  snap <- world_snapshot$countries
  snap$w2 <- snap$population
  snap$w2[1:120] <- NA_real_
  m <- attach_geometry(snap, geometry = "sf")
  full_total <- length(unique(stats::na.omit(sf::st_drop_geometry(m)$iso3c)))

  expect_warning(p <- dorling_map(m, w2, fill = gdp_per_capita), "cannot be sized")
  cov <- attr(p, "countryatlas_provenance")$coverage
  expect_gte(cov$n_total, full_total)      # the whole world, not the survivors
  expect_lt(cov$n_shown, cov$n_total)
  # Distinct countries, as na_coverage() counts them: the sf frame carries more
  # than one row for a few, so a row count is off by a couple.
  d <- sf::st_drop_geometry(m)
  expect_equal(cov$n_shown, length(unique(stats::na.omit(
    d$iso3c[!is.na(d$w2) & !is.na(d$gdp_per_capita)]))))

  # A fully-weighted frame keeps the old numbers and stays quiet.
  m2 <- attach_geometry(world_snapshot$countries, geometry = "sf")
  expect_no_warning(p2 <- dorling_map(m2, population, fill = gdp_per_capita))
  cov2 <- attr(p2, "countryatlas_provenance")$coverage
  expect_equal(cov2$n_total, cov$n_total)
})

test_that("gridded_cartogram reports the whole input as its denominator", {
  skip_slow_on_cran()
  # Two filters drop countries the grid cannot represent -- no positive value,
  # no bundled centroid -- and provenance was computed on whatever survived
  # them, so n_total shrank to match. A grid covering 94 of 215 countries
  # reported "94 of 94", i.e. perfect coverage of a world it had cut down. Only
  # the centroid drop was ever mentioned.
  snap <- world_snapshot$countries
  snap$w2 <- snap$population
  snap$w2[1:120] <- NA_real_
  # Gibraltar has no bundled centroid; give it a weight so it is dropped there.
  snap$w2[snap$iso3c == "GIB"] <- 33000
  n_in <- length(unique(stats::na.omit(snap$iso3c)))

  # Two warnings here: the missing weights, and the one country with no bundled
  # centroid. Nest so neither escapes into the suite summary.
  expect_warning(
    expect_warning(p <- gridded_cartogram(snap, w2, cells = 300),
                   "no finite, positive"),
    "no bundled centroid")
  cov <- attr(suppressWarnings(gridded_cartogram(snap, w2, cells = 300)),
              "countryatlas_provenance")$coverage
  expect_equal(cov$n_total, n_in)
  expect_lt(cov$n_shown, cov$n_total)
  # `shown` is exactly what got cells.
  expect_equal(cov$n_shown, nrow(attr(p, "countryatlas_cells")))
})

test_that("tile_map and add_indicator say when the key matches nothing", {
  skip_slow_on_cran()
  # Same failure as attach_geometry(): a lowercase or padded iso3c matches
  # nothing, so every tile drew grey and the fetched indicator arrived as a
  # column of pure NA -- which reads as "the provider has no data" rather than
  # "the join failed".
  lo <- tibble::tibble(iso3c = c("fra", "deu"), v = c(1, 2))
  up <- tibble::tibble(iso3c = c("FRA", "DEU"), v = c(1, 2))

  # Nothing joins, so the grid also reports both countries as unplaceable;
  # muffle that so the assertion stays on the key-matching warning.
  expect_warning(
    withCallingHandlers(
      tile_map(lo, v),
      countryatlas_no_centroid = function(c) invokeRestart("muffleWarning")),
    "matches the geometry")
  expect_no_warning(tile_map(up, v))
  # Placeable countries only: the grid omits Hong Kong and Macao, which
  # tile_map() reports separately, and this test is about key matching.
  placeable <- world_snapshot$countries[
    world_snapshot$countries$iso3c %in% world_tiles$iso3c, ]
  expect_no_warning(tile_map(placeable, gdp_per_capita))

  register_country_source("test_probe", function(indicator, countries = NULL,
                                                 years = NULL, ...) {
    tibble::tibble(iso3c = c("FRA", "DEU"), val = c(9, 8))
  })
  withr::defer(suppressWarnings(
    rm(list = "test_probe", envir = countryatlas:::the_sources)))

  expect_warning(out <- add_indicator(lo, "test_probe", "x"),
                 "none of which joined")
  expect_true(all(is.na(out$val)))
  expect_no_warning(ok <- add_indicator(up, "test_probe", "x"))
  expect_equal(ok$val, c(9, 8))
})

test_that("tile_map draws one cell per country, panel or not", {
  skip_slow_on_cran()
  # The grid has exactly one cell per country, so joining a panel to it fanned
  # the cells out -- 239 became 659 overlapping tiles, each country's drawn once
  # per year with the last row winning, silently. The other one-cell-per-country
  # verbs go through distinct_countries(); this one joined the grid directly and
  # was missed when they were converted.
  snap <- world_snapshot$countries[, c("iso3c", "gdp_per_capita")]
  panel <- do.call(rbind, lapply(2018:2020, function(y) {
    s <- snap; s$year <- y; s
  }))
  cells <- function(p) nrow(ggplot2::ggplot_build(p)$data[[1]])
  grid_n <- nrow(countryatlas::world_tiles)

  cs <- suppressWarnings(tile_map(snap, gdp_per_capita))
  expect_equal(cells(cs), grid_n)
  # tile_map() also reports the countries the grid cannot place; muffle just
  # that so the assertion stays on the panel warning under test.
  expect_warning(
    pn <- withCallingHandlers(
      tile_map(panel, gdp_per_capita),
      countryatlas_no_centroid = function(c) invokeRestart("muffleWarning")),
    "spans 3 years")
  expect_equal(cells(pn), grid_n)
})

test_that("tile_map counts only the countries the grid can place", {
  skip_slow_on_cran()
  # The same overstatement bubble_map() and spike_map() had: the bundled grid
  # does not cover every code -- Gibraltar has snapshot data and no tile (Hong
  # Kong and Macao, on the 3.0.0 grid) -- so counting the input's coded
  # countries as "shown" claimed more than the map could draw.
  snap <- world_snapshot$countries
  placeable <- sum(!is.na(snap$population) &
                     snap$iso3c %in% world_tiles$iso3c)
  have <- sum(!is.na(snap$population))
  expect_lt(placeable, have)                       # the premise holds

  expect_warning(p <- tile_map(snap, population),
                 class = "countryatlas_no_centroid")
  cov <- attr(p, "countryatlas_provenance")$coverage
  expect_equal(cov$n_shown, placeable)
  expect_equal(cov$n_shown + cov$n_missing, cov$n_total)
  expect_true("GIB" %in% cov$missing_iso3c)
  # The message names the grid, not a centroid.
  expect_warning(tile_map(snap, population), "tile in the bundled grid")
  # The grid itself is still drawn whole.
  expect_equal(nrow(ggplot2::ggplot_build(p)$data[[1]]), nrow(world_tiles))

  # And the shared helper's default wording is still right for the point verbs.
  expect_warning(bubble_map(snap, population), "bundled centroid")
})

test_that("cartogram_diagnostics names invalid geometry, not s2's loop", {
  skip_slow_on_cran()
  skip_if_not_installed("sf")
  bow <- sf::st_polygon(list(rbind(c(0, 0), c(2, 2), c(2, 0), c(0, 2), c(0, 0))))
  sq <- function(x0) sf::st_polygon(list(rbind(
    c(x0, 0), c(x0 + 1, 0), c(x0 + 1, 1), c(x0, 1), c(x0, 0))))
  bad <- sf::st_sf(iso3c = c("USA", "FRA"), gdp = c(1, 2),
                   geometry = sf::st_sfc(bow, sq(3), crs = 4326))
  expect_error(cartogram_diagnostics(bad, "gdp"),
               class = "countryatlas_invalid_geometry")
  # It names the country rather than "Loop 0", and agrees at n = 1...
  err <- tryCatch(cartogram_diagnostics(bad, "gdp"), error = function(e) e)
  msg <- cli::ansi_strip(paste(conditionMessage(err), collapse = " "))
  expect_match(msg, "USA", fixed = TRUE)
  expect_match(msg, "1 geometry is invalid", fixed = TRUE)
  expect_match(msg, "st_make_valid", fixed = TRUE)
  # ...and at n = 2, where cli's agreement markers key to the wrong number if
  # anything numeric is interpolated between the count and the marker.
  bow2 <- sf::st_polygon(list(rbind(c(5, 0), c(7, 2), c(7, 0), c(5, 2), c(5, 0))))
  bad2 <- sf::st_sf(iso3c = c("USA", "FRA"), gdp = c(1, 2),
                    geometry = sf::st_sfc(bow, bow2, crs = 4326))
  err2 <- tryCatch(cartogram_diagnostics(bad2, "gdp"), error = function(e) e)
  expect_match(cli::ansi_strip(paste(conditionMessage(err2), collapse = " ")),
               "2 geometries are invalid", fixed = TRUE)
  # Valid geometry is untouched.
  good <- sf::st_sf(iso3c = c("USA", "FRA"), gdp = c(1, 2),
                    geometry = sf::st_sfc(sq(0), sq(3), crs = 4326))
  expect_s3_class(cartogram_diagnostics(good, "gdp"), "tbl_df")
})

test_that("a caller column named row or col does not break tile_map", {
  skip_slow_on_cran()
  # The tile grid supplies `row` and `col`, common enough names that a caller's
  # frame may carry its own. dplyr then suffixed both sides of the join to
  # `.x`/`.y` and aes(.data$col, -.data$row) failed with ggplot2's "Problem
  # while computing aesthetics".
  snap <- world_snapshot$countries
  for (nm in c("row", "col")) {
    d <- snap
    d[[nm]] <- 1
    expect_s3_class(suppressWarnings(tile_map(d, population)), "ggplot")
  }
  # Dropping the caller's copy must not change what is drawn.
  a <- suppressWarnings(ggplot2::ggplot_build(tile_map(snap, population)))
  d2 <- snap
  d2$row <- 1
  b <- suppressWarnings(ggplot2::ggplot_build(tile_map(d2, population)))
  expect_equal(a$data, b$data)

  # A fill column of that name cannot be both the value and a coordinate, so
  # it is refused rather than silently dropped.
  d3 <- snap
  d3$row <- snap$population
  expect_error(tile_map(d3, row), class = "countryatlas_error")
  expect_match(cli::ansi_strip(conditionMessage(tryCatch(tile_map(d3, row),
    error = identity))), "cannot be", fixed = TRUE)
})

test_that("gridded_cartogram() words the unusable-value warning for its count", {
  skip_slow_on_cran()
  g <- countryatlas::world_snapshot$countries
  g$population[g$iso3c == "CHN"] <- Inf
  msgs <- character(0)
  withCallingHandlers(gridded_cartogram(g, population, cells = 50),
                      warning = function(w) {
                        msgs <<- c(msgs, conditionMessage(w))
                        invokeRestart("muffleWarning")
                      })
  msgs <- gsub("\\s+", " ", msgs)
  expect_true(any(grepl("1 country has no finite, positive population and gets",
                        msgs)))
})

test_that("cartograms draw in the orthographic and Winkel Tripel projections", {
  skip_if_not_installed("cartogram")
  skip_if_no_sf_geometry()
  skip_on_cran()
  sfd <- suppressWarnings(attach_geometry(countryatlas::world_snapshot$countries,
                                          geometry = "sf"))
  draw <- function(p) {
    f <- tempfile(fileext = ".png")
    grDevices::png(f, width = 120, height = 120)
    on.exit({ grDevices::dev.off(); unlink(f) })
    print(p)
    TRUE
  }
  # The far side reached cartogram as empty geometry: "all sizes are missing
  # and/or non-positive". It is out of view, not missing, so coverage is
  # unchanged.
  flat <- suppressWarnings(dorling_map(sfd, population, itermax = 10))
  ortho <- suppressWarnings(dorling_map(sfd, population, itermax = 10,
                                        projection = "orthographic"))
  expect_true(draw(ortho))
  expect_equal(map_provenance(ortho)$n_missing, map_provenance(flat)$n_missing)
  # Printing computed a graticule over the cartogram's box and died on GEOS's
  # "point array must contain 0 or >1 elements".
  expect_true(draw(suppressWarnings(
    cartogram_map(sfd, population, itermax = 2, projection = "winkel_tripel"))))
})

test_that("cartogram_map builds every type and names a missing column", {
  skip_slow_on_cran()
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

test_that("dorling_map errors cleanly without sf/cartogram", {
  skip_if(requireNamespace("sf", quietly = TRUE) &&
            requireNamespace("cartogram", quietly = TRUE))
  # cartogram_map()'s need_pkg() runs ahead of its is_sf() check, so the gate
  # is what fires here -- pinned, so a shape or argument error cannot pass for
  # it.
  expect_error(dorling_map(snap, gdp_per_capita), class = "rlib_error_package_not_found")
})

test_that("a Dorling cartogram is area-proportional and does not overlap", {
  skip_slow_on_cran()
  # Sixteen tests cover this family's validation, package gating, cell counts
  # and denominators -- none of them the two properties that make the output a
  # Dorling cartogram at all. Passing the wrong column, or skipping the
  # equal-area projection, would leave every one of them passing.
  skip_if_no_sf_geometry()
  skip_if_not_installed("cartogram")
  sfd <- suppressWarnings(
    attach_geometry(countryatlas::world_snapshot$countries, geometry = "sf"))
  d <- suppressWarnings(dorling_map(sfd, population))$data

  # Areas are only honest in a projected CRS.
  expect_false(sf::st_is_longlat(d))

  # Circle area is proportional to the value -- so the ratio is one constant,
  # not merely correlated.
  a <- as.numeric(suppressWarnings(sf::st_area(d)))
  v <- d$population
  ok <- is.finite(a) & is.finite(v) & v > 0 & a > 0
  expect_gt(sum(ok), 100L)
  ratio <- a[ok] / v[ok]
  expect_equal(max(ratio) / min(ratio), 1, tolerance = 1e-6)

  # ...and the whole point of Dorling: the circles do not overlap.
  old <- sf::sf_use_s2()
  on.exit(suppressMessages(sf::sf_use_s2(old)), add = TRUE)
  suppressMessages(sf::sf_use_s2(FALSE))
  touching <- suppressWarnings(sf::st_intersects(d))
  expect_equal((sum(lengths(touching)) - nrow(d)) / 2, 0)
})

test_that("a gridded cartogram keeps countries near where they really are", {
  skip_slow_on_cran()
  # The grid is only a map if a country's cell tracks its real position; a
  # mis-assignment would draw a plausible-looking grid of the wrong countries.
  skip_if_no_sf_geometry()
  snap <- countryatlas::world_snapshot$countries
  d <- suppressWarnings(gridded_cartogram(snap, population, cells = 900))$data
  cm <- countryatlas::country_meta
  lon <- cm$centroid_lon[match(d$iso3c, cm$iso3c)]
  lat <- cm$centroid_lat[match(d$iso3c, cm$iso3c)]
  ok <- is.finite(lon) & is.finite(lat) & is.finite(d$x) & is.finite(d$y)
  expect_gt(sum(ok), 500L)
  expect_gt(cor(d$x[ok], lon[ok]), 0.9)
  expect_gt(cor(d$y[ok], lat[ok]), 0.9)
  # One country per cell (a country may hold several cells -- that is the
  # value-proportional part).
  expect_false(any(duplicated(paste(d$x, d$y))))
})

test_that("dorling_map builds a ggplot (needs sf + cartogram)", {
  skip_slow_on_cran()
  skip_if_not_installed("sf")
  skip_if_not_installed("cartogram")
  skip_if_not_installed("rnaturalearth")
  sfdata <- world_geometry("countries", geometry = "sf")
  sfdata <- dplyr::inner_join(sfdata, snap[, c("iso3c", "population")], by = "iso3c")
  p <- dorling_map(sfdata, population)
  expect_s3_class(p, "ggplot")
})

test_that("tile_trend_map() draws one sparkline per country with two years", {
  skip_slow_on_cran()
  set.seed(1)
  pan <- expand.grid(iso3c = c("FRA", "DEU", "BRA", "GIB"), year = 2000:2005,
                     stringsAsFactors = FALSE)
  pan$v <- seq_len(nrow(pan))
  pan$v[pan$iso3c == "BRA" & pan$year > 2000] <- NA   # one value: no line
  expect_warning(p <- tile_trend_map(pan, v), class = "countryatlas_no_centroid")
  lines <- ggplot2::layer_data(p, 2)
  expect_setequal(unique(p$layers[[2]]$data$iso3c), c("FRA", "DEU"))
  expect_equal(nrow(lines), 12L)
  prov <- map_provenance(p)
  expect_identical(prov$n_countries, 2L)
  expect_identical(prov$n_total, 4L)
  # Each line stays inside its own tile.
  d <- p$layers[[2]]$data
  expect_true(all(abs(d$.x - d$col) < 0.5 & abs(d$.y + d$row) < 0.5))
  # The subtitle says which scale.
  sub <- function(x) {
    if ("get_labs" %in% getNamespaceExports("ggplot2")) ggplot2::get_labs(x)$subtitle
    else x$labels$subtitle
  }
  expect_match(sub(p), "each country on its own scale", fixed = TRUE)
  q <- suppressWarnings(tile_trend_map(pan, v, scales = "fixed", years = c(2001, 2003)))
  expect_match(sub(q), "2001-2003; one scale", fixed = TRUE)
  expect_error(tile_trend_map(rbind(pan, pan), v), "more than one row")
  expect_match(ggplot2::get_alt_text(p), "line charts", fixed = TRUE)
})
