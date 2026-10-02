# --- coverage_map / classify_compare / value_by_alpha_map ---------------------

test_that("coverage_map maps availability", {
  skip_slow_on_cran()
  mapdf <- poly_df()
  p <- coverage_map(mapdf, gdp_per_capita)
  renders(p)
  expect_match(p$labels$caption, "report a value")
  expect_match(p$labels$title, "Coverage of gdp_per_capita")
  renders(coverage_map(mapdf, co2_per_capita, title = "Custom"))
  expect_error(coverage_map(mapdf, not_a_column), "not found")
})

test_that("classify_compare reports how unbalanced each method is", {
  skip_slow_on_cran()
  mapdf <- poly_df()
  # "jenks" falls back to quantile breaks, with a warning, when classInt is
  # absent -- which is the documented degraded path and is exercised under
  # _R_CHECK_DEPENDS_ONLY_. The assertions below hold either way.
  p <- suppressWarnings(classify_compare(mapdf, gdp_per_capita))
  renders(p)
  rep <- attr(p, "countryatlas_classification")
  expect_setequal(unique(rep$method), c("quantile", "jenks", "fisher",
                                        "headtails", "equal", "pretty"))
  # The point of the feature: equal-interval piles most countries into one
  # class on a skewed indicator, quantile does not.
  worst <- function(m) max(rep$n[rep$method == m]) / sum(rep$n[rep$method == m])
  expect_lt(worst("quantile"), 0.3)
  expect_gt(worst("equal"), 0.7)
  expect_error(classify_compare(mapdf, gdp_per_capita, methods = "nope"),
               "Unknown classification method")
  expect_error(classify_compare(mapdf, country), "numeric")
})

test_that("classify_breaks produces n+1 finite, increasing breaks", {
  x <- snap$gdp_per_capita[!is.na(snap$gdp_per_capita)]
  for (m in c("quantile", "jenks", "equal", "pretty", "sd")) {
    # Without classInt, "jenks" warns and returns quantile breaks; these are
    # structural properties that must hold on either path.
    br <- suppressWarnings(countryatlas:::classify_breaks(x, m, 5))
    expect_true(all(is.finite(br)), info = m)
    expect_false(is.unsorted(br), info = m)
    expect_gt(length(br), 2L)
  }
})

test_that("jenks really is jenks when classInt is available", {
  # The structural assertions above are satisfied by quantile breaks too, so
  # without this the jenks case passes vacuously wherever classInt is missing
  # -- which is exactly where the fallback silently substitutes quantile.
  skip_if_not_installed("classInt")
  x <- snap$gdp_per_capita[!is.na(snap$gdp_per_capita)]
  jen <- countryatlas:::classify_breaks(x, "jenks", 5)
  quant <- countryatlas:::classify_breaks(x, "quantile", 5)
  expect_false(isTRUE(all.equal(jen, quant)))
  expect_silent(countryatlas:::classify_breaks(x, "jenks", 5))
})

test_that("value_by_alpha_map maps the equalising variable to opacity", {
  skip_slow_on_cran()
  mapdf <- poly_df()
  renders(value_by_alpha_map(mapdf, gdp_per_capita, population))
  renders(value_by_alpha_map(mapdf, gdp_per_capita, population, transform = "log10"))
  renders(value_by_alpha_map(mapdf, gdp_per_capita, population, transform = "identity"))
  expect_error(value_by_alpha_map(mapdf, gdp_per_capita, population,
                                  alpha_range = c(2, 3)), "alpha_range")
  expect_error(value_by_alpha_map(mapdf, gdp_per_capita, population,
                                  alpha_range = c(0.9, 0.1)), "increasing")
  expect_error(value_by_alpha_map(mapdf, gdp_per_capita, country), "numeric")
})

test_that("rescale01 survives a constant vector", {
  expect_equal(countryatlas:::rescale01(c(1, 3, 5)), c(0, 0.5, 1))
  expect_equal(countryatlas:::rescale01(rep(2, 4)), rep(1, 4))
  expect_equal(countryatlas:::rescale01(c(NA, NA)), c(1, 1))
})

test_that("the VSUP suppresses the value range as uncertainty rises", {
  v <- c(1, 2, 3, 4, 5); u_low <- rep(0, 5); u_high <- rep(1, 5)
  lo <- countryatlas:::vsup_fill(v, u_low, n_bins = 5, n_uncertainty = 3)
  # With uniform uncertainty everything lands in one uncertainty bin, so the
  # value range is unsuppressed and all five colours differ.
  expect_equal(length(unique(lo$fill)), 5L)
  # Rank-based binning: the bins are populated rather than piled into one.
  big <- countryatlas:::vsup_fill(c(1, 2, 3, 1000), c(1, 2, 3, 4),
                                  n_bins = 4, n_uncertainty = 2)
  expect_equal(length(unique(stats::na.omit(big$v_bin))), 4L)
})

# --- numerical invariants of the new estimators -------------------------------------

test_that("the VSUP actually suppresses: colour spread narrows with uncertainty", {
  v <- rep(1:5, 3); u <- rep(1:3, each = 5)
  f <- countryatlas:::vsup_fill(v, u, n_bins = 5, n_uncertainty = 3)
  # Counting distinct colours is the wrong measure -- they stay distinct, they
  # just crowd together. Measure the span of the colour range instead.
  spread <- vapply(split(seq_along(v), f$u_bin), function(i) {
    m <- grDevices::col2rgb(f$fill[i])
    sum(apply(m, 1, function(r) diff(range(r))))
  }, numeric(1))
  expect_true(all(diff(spread) < 0))
  # The top uncertainty level should be dramatically narrower, not marginally.
  expect_lt(spread[[3]] / spread[[1]], 0.2)
})

test_that("value_by_alpha_map keeps opacity absolute", {
  skip_slow_on_cran()
  # `a` is normalised to [0, 1] by every transform, so the alpha scale is
  # pinned there. Without limits it rescaled to whatever spread the frame
  # happened to have: an equalize column with nothing usable collapsed to a
  # single value and ggplot2 put it at the *midpoint* of alpha_range -- a
  # uniformly half-lit map reading as "equally weighted", which is the one
  # impression this verb exists to prevent.
  skip_if_no_sf_geometry()
  snap <- world_snapshot$countries
  snap$allna <- NA_real_
  m <- attach_geometry(snap, geometry = "sf")
  alpha_of <- function(p) {
    b <- ggplot2::ggplot_build(p)
    a <- b$data[[which.max(vapply(b$data, nrow, 1L))]]$alpha
    range(a[!is.na(a)])
  }
  expect_warning(p <- value_by_alpha_map(m, gdp_per_capita, allna),
                 "carries no information")
  expect_equal(alpha_of(p), c(0.15, 0.15))    # the floor, not the midpoint
  expect_no_warning(p2 <- value_by_alpha_map(m, gdp_per_capita, population))
  expect_equal(alpha_of(p2), c(0.15, 1))
})

test_that("value_by_alpha_map() refuses a non-numeric value", {
  d <- toy_polygons(c(FRA = 1, DEU = 2, ITA = 3))
  d$pop <- c(10, 20, 30)[d$group]
  d$label <- d$iso3c
  expect_error(value_by_alpha_map(d, label, pop), "needs a numeric",
               class = "countryatlas_error")
})

test_that("classify_compare() tolerates a repeated method", {
  skip_slow_on_cran()
  d <- toy_polygons(c(FRA = 1, DEU = 2, ITA = 3, ESP = 4, PRT = 5, BEL = 6))
  p <- classify_compare(d, v, methods = c("quantile", "quantile", "equal"),
                        n_bins = 2)
  expect_equal(levels(countryatlas:::gg_plot_data(p)$.wdj_method),
               c("quantile", "equal"))
})

# --- ranking once per country ------------------------------------------------

test_that("value_by_alpha_map() ranks opacity once per country, not per vertex", {
  skip_slow_on_cran()
  # FRA has far more vertex rows than the others and the lowest population,
  # so a rank over the raw rows pushed everyone above it up the scale.
  d <- toy_polygons(c(FRA = 1, DEU = 2, ITA = 3, ESP = 4),
                    n_vertices = c(60, 4, 4, 4))
  d$pop <- c(10, 20, 30, 40)[d$group]
  p <- value_by_alpha_map(d, v, pop)
  drawn <- unique(ggplot2::ggplot_build(p)$plot$data[, c("iso3c", ".wdj_alpha")])
  expect_equal(drawn$.wdj_alpha[match(c("FRA", "DEU", "ITA", "ESP"), drawn$iso3c)],
               c(0, 1, 2, 3) / 3)
  # The same countries drawn with equal outlines get the same opacity.
  eq <- toy_polygons(c(FRA = 1, DEU = 2, ITA = 3, ESP = 4))
  eq$pop <- c(10, 20, 30, 40)[eq$group]
  eq_drawn <- unique(ggplot2::ggplot_build(value_by_alpha_map(eq, v, pop))$plot$data[
    , c("iso3c", ".wdj_alpha")])
  expect_equal(eq_drawn$.wdj_alpha, drawn$.wdj_alpha)
})
