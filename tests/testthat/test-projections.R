# --- projections ---------------------------------------------------------------

test_that("projection_info covers every projection wdj_crs can build", {
  info <- projection_info()
  expect_setequal(info$projection, countryatlas:::wdj_projections())
  expect_named(info, c("projection", "family", "property", "equal_area",
                       "conformal", "note", "proj4"))
  # The property flags have to agree with the PROJ string actually emitted.
  expect_true(info$equal_area[info$projection == "equal_earth"])
  expect_false(info$equal_area[info$projection == "mercator"])
  expect_true(info$conformal[info$projection == "mercator"])
  expect_match(info$proj4[info$projection == "equal_earth"], "+proj=eqearth",
               fixed = TRUE)
  expect_equal(nrow(projection_info("mercator")), 1L)
  expect_error(projection_info("nope"), "Unknown projection")
})

test_that("projection_compare draws one panel per projection", {
  skip_slow_on_cran()
  d <- sf_df()
  p <- projection_compare(d, gdp_per_capita, style = "quantile")
  renders(p)
  built <- ggplot2::ggplot_build(p)
  expect_equal(length(unique(built$data[[1]]$PANEL)), 4L)
  renders(projection_compare(d, gdp_per_capita, projections = "mollweide"))
  renders(projection_compare(d, gdp_per_capita, labeller = "property"))
  expect_error(projection_compare(d, gdp_per_capita, projections = "nope"),
               "Unknown projection")
  expect_error(projection_compare(d, gdp_per_capita, projections = character(0)),
               "at least one")
})

test_that("projection_compare rejects the polygon backend rather than ignoring it", {
  # Without sf the need_pkg() guard fires first and says so instead; that is a
  # different (and correct) refusal, not the one under test here.
  skip_if_not_installed("sf")
  expect_error(projection_compare(poly_df(), gdp_per_capita), "needs an sf frame")
})

test_that("projection_compare leaves the s2 setting as it found it", {
  skip_slow_on_cran()
  d <- sf_df()
  before <- sf::sf_use_s2()
  invisible(ggplot2::ggplotGrob(projection_compare(d, gdp_per_capita)))
  expect_equal(sf::sf_use_s2(), before)
})

test_that("tissot_map draws equal-area circles on an equal-area projection", {
  skip_slow_on_cran()
  skip_if_no_sf_geometry()
  renders(tissot_map("equal_earth"))
  renders(tissot_map("mercator", spacing = 45))
  expect_error(tissot_map("equal_earth", spacing = 0), "spacing")
  expect_error(tissot_map("equal_earth", radius_km = 0), "radius_km")
  expect_error(tissot_map("equal_earth", max_lat = 95), "max_lat")
})

test_that("projection_distortion agrees with what each projection claims", {
  skip_slow_on_cran()
  skip_if_not_installed("sf")
  areal <- function(p) attr(projection_distortion(p, "areal", spacing = 20),
                            "countryatlas_distortion")
  angular <- function(p) attr(projection_distortion(p, "angular", spacing = 20),
                              "countryatlas_distortion")
  # Equal-area projections have areal distortion of exactly 1...
  for (p in c("equal_earth", "mollweide", "gall_peters")) {
    expect_equal(areal(p)$mean, 1, tolerance = 0.01, label = p)
  }
  # ...and Mercator, which is not equal-area, does not.
  expect_gt(areal("mercator")$mean, 2)
  # Mercator is conformal, so angular distortion is ~0; equal-area ones are not.
  expect_lt(angular("mercator")$mean, 1)
  expect_gt(angular("equal_earth")$mean, 10)
  expect_error(projection_distortion("nope"), "`projection` must be one of")
})

test_that("projection_info's properties agree with measured distortion", {
  skip_slow_on_cran()
  # The table is a set of factual claims about thirteen projections, and
  # projection_distortion() can check every one of them from the Jacobian. The
  # separation is two orders of magnitude, so this is a real assertion rather
  # than a tuned threshold: equal-area projections hold areal scale to a spread
  # of <= 0.014, every other projection spreads by >= 0.99; Mercator's maximum
  # angular deformation is 0.4 degrees, every non-conformal projection exceeds
  # 100. It also guards the sign convention -- the angular measure was once
  # written upside down, which put Mercator at 170 degrees instead of nearly 0.
  skip_if_not_installed("sf")
  info <- projection_info()

  for (p in info$projection[info$equal_area]) {
    d <- projection_distortion(p, measure = "areal", spacing = 20)$distortion
    expect_lt(diff(range(d, na.rm = TRUE)), 0.1)
  }
  for (p in info$projection[!info$equal_area]) {
    d <- projection_distortion(p, measure = "areal", spacing = 20)$distortion
    expect_gt(diff(range(d, na.rm = TRUE)), 0.1)
  }
  for (p in info$projection[info$conformal]) {
    d <- projection_distortion(p, measure = "angular", spacing = 20)$distortion
    expect_lt(max(d, na.rm = TRUE), 5)
  }
  for (p in info$projection[!info$conformal]) {
    d <- projection_distortion(p, measure = "angular", spacing = 20)$distortion
    expect_gt(max(d, na.rm = TRUE), 5)
  }
})

test_that("projection_distortion() measures against the datum it projects", {
  skip_if_not_installed("sf")
  ee <- projection_distortion("equal_earth", "areal", spacing = 15)
  expect_equal(range(ee$distortion), c(1, 1), tolerance = 1e-5)
  laea <- projection_distortion("north_polar", "areal", spacing = 15)
  expect_equal(range(laea$distortion), c(1, 1), tolerance = 1e-5)
  merc <- projection_distortion("mercator", "angular", spacing = 15)
  expect_lt(max(merc$distortion), 1e-3)
})
