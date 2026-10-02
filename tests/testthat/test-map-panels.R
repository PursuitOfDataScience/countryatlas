test_that("animate_world keeps a title the caller asked for", {
  skip_slow_on_cran()
  skip_if_not_installed("gganimate")
  mapdf <- suppressWarnings(
    attach_geometry(world_snapshot$countries, geometry = "polygon"))
  pan <- do.call(rbind, lapply(2018:2020, function(y) {
    z <- mapdf; z$year <- y; z
  }))
  a <- animate_world(pan, gdp_per_capita, year, title = "MY TITLE")
  expect_equal(format(a$labels$title), "MY TITLE")
  expect_equal(format(a$labels$subtitle), "{current_frame}")
  # With no title the frame marker still goes where it always did.
  b <- animate_world(pan, gdp_per_capita, year)
  expect_equal(format(b$labels$title), "{current_frame}")
})

test_that("countries with no data are drawn in every period, not in an NA one", {
  skip_slow_on_cran()
  vals <- c(FRA = 1, DEU = 2, ITA = 3)
  d <- toy_polygons(vals)
  d$year <- NA_integer_
  panel <- rbind(transform(d[d$iso3c != "ITA", ], year = 2000L),
                 transform(d[d$iso3c != "ITA", ], year = 2010L),
                 d[d$iso3c == "ITA", ])
  panel$v[panel$iso3c == "ITA"] <- NA
  p <- facet_map(panel, v, year)
  b <- ggplot2::ggplot_build(p)
  expect_equal(as.character(b$layout$layout$year), c("2000", "2010"))
  # ITA, which has no data, is in both panels.
  per_panel <- tapply(b$plot$data$iso3c, b$plot$data$year,
                      function(z) "ITA" %in% z)
  expect_true(all(per_panel))
  expect_equal(map_provenance(p)$n_total, 3L)
  expect_equal(map_provenance(p)$n_missing, 1L)
  # The same frame animated: no NA frame for gganimate to coerce.
  skip_if_not_installed("gganimate")
  a <- animate_world(panel, v)
  dd <- tempfile("anim")
  dir.create(dd)
  on.exit(unlink(dd, recursive = TRUE), add = TRUE)
  expect_no_warning(gganimate::animate(
    a, nframes = 2, fps = 1, width = 80, height = 60,
    renderer = gganimate::file_renderer(dir = dd, overwrite = TRUE)))
})

test_that("animate_world animates or falls back to facets", {
  skip_slow_on_cran()
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

test_that("animate_world validates before handing off to gganimate", {
  skip_slow_on_cran()
  # A three-country panel is enough, and keeps the geometry join small: joining
  # the whole snapshot for three years is ~250k rows and trips dplyr's
  # many-to-many heuristic, which is noise for what this test checks.
  snap <- countryatlas::world_snapshot$countries
  small <- snap[snap$iso3c %in% c("FRA", "BRA", "USA"), ]
  panel <- do.call(rbind, lapply(2018:2020, function(y) transform(small, yr = y)))
  mapdf <- attach_geometry(panel, geometry = "polygon")
  expect_error(animate_world(panel, gdp_per_capita, yr), "no map geometry")
  expect_error(animate_world(mapdf, gdp_per_capita, nope), "not found")
  chr <- mapdf; chr$g <- "a"
  expect_error(animate_world(chr, g, yr, style = "quantile"), "needs a numeric")
  # The documented fallback when gganimate is absent is a faceted plot.
  local_mocked_bindings(has_pkg = function(pkg) {
    if (identical(pkg, "gganimate")) FALSE
    else isTRUE(requireNamespace(pkg, quietly = TRUE))
  })
  expect_message(animate_world(mapdf, gdp_per_capita, yr), "faceting")
  out <- suppressMessages(animate_world(mapdf, gdp_per_capita, yr))
  expect_s3_class(out, "ggplot")
  expect_no_error(ggplot2::ggplot_build(out))
})
