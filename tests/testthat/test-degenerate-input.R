# Degenerate-but-valid input: zero variance, a single observation, duplicate
# panel keys, poles, antimeridian, all-NA columns. These are ordinary messy-data
# situations, and the question for each is whether the package returns an honest
# answer, an actionable error, or something confusing.

snap <- countryatlas::world_snapshot$countries

test_that("beta_convergence reports why it cannot estimate a flat panel", {
  # Zero spread in the initial levels makes the predictor constant, so lm()
  # returns an NA coefficient and summary() drops the row -- which used to
  # surface as a bare "subscript out of bounds".
  flat <- data.frame(iso3c = rep(c("A", "B", "C", "D"), each = 2),
                     year  = rep(c(2000L, 2010L), 4),
                     g     = rep(c(100, 110), 4))
  expect_error(suppressWarnings(beta_convergence(flat, g)),
               class = "countryatlas_error")
  expect_error(suppressWarnings(beta_convergence(flat, g)), "no spread")
  # Too few countries is a different, already-clear message.
  expect_error(beta_convergence(data.frame(iso3c = "A", year = c(2000L, 2010L),
                                           g = c(1, 2)), g),
               "at least 3")
})

test_that("inequality measures return 0, not NaN, for perfect equality", {
  expect_equal(gini(5), 0)
  expect_equal(gini(c(3, 3)), 0)
  expect_equal(gini(rep(2, 100)), 0)
  expect_equal(theil(5), 0)
  expect_equal(theil(rep(4, 10)), 0)
  # With groups at perfect equality the components are 0 and the shares
  # undefined rather than NaN.
  d <- theil(rep(4, 6), groups = rep(c("a", "b"), 3))
  expect_equal(d$value, c(0, 0, 0))
  # Undefined, not NaN -- and is.na() alone cannot tell those apart.
  expect_identical(d$share, rep(NA_real_, 3L))
})

test_that("zero-variance columns give NA/NaN rather than an error", {
  # A z-score needs a spread; NaN is the honest answer, not a failure.
  r <- rank_countries(data.frame(iso3c = c("A", "B", "C"), v = c(5, 5, 5)), v)
  expect_true(all(is.nan(r$z_score)))
  expect_true(all(r$rank == 1L))
  # cor() of a constant column is undefined.
  ci <- suppressWarnings(correlate_indicators(
    data.frame(a = c(1, 2, 3, 4), b = c(7, 7, 7, 7))))
  expect_equal(nrow(ci), 1L)
  expect_true(is.na(ci$r))
  # One country in a year has no dispersion -- and now says so rather than
  # handing back a blank sigma column in silence.
  expect_warning(
    sc <- sigma_convergence(data.frame(iso3c = c("A", "B"),
                                       year = c(2000L, 2001L), g = c(1, 2)), g),
    class = "countryatlas_thin_year")
  expect_true(all(is.na(sc$sigma)))
  expect_equal(sc$n, c(1L, 1L))
})

test_that("panel helpers survive duplicate (iso3c, year) rows", {
  # Malformed but common; nothing should error. And since every one of these
  # reads neighbouring rows, each now says so rather than quietly lagging
  # against the duplicate -- surviving the input was never the same as being
  # right about it.
  dup <- data.frame(iso3c = c("A", "A", "A"), year = c(2000L, 2000L, 2001L),
                    g = c(1, 2, 3))
  w <- "repeated country-year"
  expect_warning(expect_no_error(complete_years(dup)), w)
  expect_warning(expect_no_error(complete_years(dup, method = "locf")), w)
  expect_warning(expect_no_error(growth_rate(dup, g)), w)
  expect_warning(expect_no_error(lag_by_country(dup, g)), w)
  expect_warning(expect_no_error(index_to(dup, g, base_year = 2000)), w)
  # Also reports the thin years it found; muffle just that so the assertion
  # stays on the repeated-country-year warning this test is about.
  expect_warning(expect_no_error(withCallingHandlers(
    sigma_convergence(dup, g),
    countryatlas_thin_year = function(c) invokeRestart("muffleWarning"))), w)
})

test_that("the geometric kernels handle poles, antipodes and collinearity", {
  gc <- countryatlas:::great_circle
  hv <- countryatlas:::haversine_km
  ra <- countryatlas:::ring_area_km2
  # Pole to pole, and a degenerate same-point arc.
  expect_equal(nrow(gc(0, 90, 0, -90, n = 5)), 5L)
  expect_false(anyNA(gc(0, 90, 0, -90, n = 5)$lat))
  expect_equal(nrow(gc(0, 90, 180, 90, n = 5)), 5L)
  # A ring with no area.
  expect_equal(ra(c(0, 1, 2, 3), c(0, 0, 0, 0)), 0)
  # NA in, NA out -- not an error.
  expect_true(is.na(hv(NA, 0, 10, 10)))
  expect_equal(distance_between("France", "France"), 0)
})

test_that("plotting verbs cope with all-NA and all-zero columns", {
  skip_if_not_installed("maps")
  d <- snap
  d$all_na <- NA_real_
  d$all_zero <- 0
  expect_no_error(ggplot2::ggplot_build(tile_map(d, all_na)))
  expect_no_error(suppressWarnings(ggplot2::ggplot_build(spike_map(d, all_zero))))
  expect_no_error(suppressWarnings(ggplot2::ggplot_build(bubble_map(d, all_na))))
  # An origin-destination pair that is the same country is a zero-length arc.
  od <- data.frame(f = "France", t = "France", v = 1)
  expect_no_error(ggplot2::ggplot_build(flow_map(od, f, t, v)))
})

test_that("a single-country frame still bins and draws", {
  skip_if_no_sf_geometry()
  one <- attach_geometry(snap[1, ], geometry = "sf")
  # compute_breaks() widens a single distinct value into a usable interval.
  expect_no_error(ggplot2::ggplot_build(
    world_map(one, gdp_per_capita, style = "quantile")))
  expect_equal(countryatlas:::compute_breaks(rep(5, 10), "quantile", 5),
               c(4.5, 5.5))
  expect_equal(countryatlas:::compute_breaks(numeric(0), "quantile", 5), c(0, 1))
})

test_that("share_of_world and per_capita pass through odd but valid values", {
  # Negative values are the caller's business; the arithmetic stays honest.
  sw <- share_of_world(data.frame(iso3c = c("A", "B"), v = c(-1, 3)), v)
  expect_equal(sum(sw$v_share), 1)
  expect_equal(per_capita(data.frame(iso3c = "A", v = 1, p = -2), v, p)$v_per_capita,
               -0.5)
  # A zero world total has no meaningful share.
  z <- share_of_world(data.frame(iso3c = c("A", "B"), v = c(-2, 2)), v)
  expect_true(all(is.na(z$v_share)))
})

# Every other panel helper returns 0 rows for a 0-row frame. complete_years()
# instead reached seq(min(numeric(0)), max(numeric(0))) and died on base R's
# "'from' must be a finite number" (with a "no non-missing arguments to min"
# warning alongside), or -- when `years` was supplied -- on tidyr's "Can't
# recycle `year` (size 3) to size 0". Neither names anything the caller did.

test_that("complete_years returns 0 rows for a 0-row panel", {
  z <- tibble::tibble(iso3c = character(), year = integer(), g = numeric())
  for (m in c("none", "locf", "linear")) {
    out <- complete_years(z, value = "g", method = m)
    expect_equal(nrow(out), 0L)
    expect_named(out, c("iso3c", "year", "g"))
    expect_no_warning(complete_years(z, value = "g", method = m))
  }
  # Explicit years cannot conjure countries that are not there.
  expect_equal(nrow(complete_years(z, years = 2000:2002, value = "g")), 0L)
  # And with no `value` at all (columns inferred).
  expect_equal(nrow(complete_years(z)), 0L)
})

test_that("a 0-row panel still reports a bad argument", {
  # The early return must not swallow validation.
  z <- tibble::tibble(iso3c = character(), year = integer(), g = numeric())
  expect_error(complete_years(z, years = "a"), "`years`")
  expect_error(complete_years(z, years = numeric(0)), "Got 0 values")
  expect_error(complete_years(z, years = c(2000, NA)), "`years`")
  expect_error(complete_years(z, value = "nope"), "not found")
  expect_error(complete_years(tibble::tibble(a = 1)), "iso3c")
})

test_that("completing a panel that does have rows is unchanged", {
  d <- tibble::tibble(iso3c = "USA", year = c(2000L, 2002L), g = c(1, 3))
  expect_equal(nrow(complete_years(d, value = "g")), 3L)
  expect_equal(complete_years(d, 2000:2002, value = "g",
                              method = "linear")$g, c(1, 2, 3))
  expect_equal(complete_years(d, 2000:2002, value = "g", method = "locf")$g,
               c(1, 1, 3))
})

test_that("the other summarising verbs are honest about no data", {
  # Recorded so these are not mistaken for bugs later: a rate or correlation
  # over zero observations is 0/0, and NA/NaN is the right answer for it.
  z <- tibble::tibble(iso3c = character(), year = integer(),
                      g = numeric(), h = numeric())
  expect_true(is.na(audit_coverage(z, "g")$na_rates$na_rate))
  expect_equal(audit_coverage(z, "g")$na_rates$n, 0L)
  cr <- correlate_indicators(z, c("g", "h"))
  expect_true(is.na(cr$r))
  expect_equal(cr$n, 0L)
  # n = 1 cannot support a correlation either.
  one <- tibble::tibble(iso3c = "USA", year = 2000L, g = 1, h = 2)
  expect_true(is.na(correlate_indicators(one, c("g", "h"))$r))
  # And these all return 0 rows rather than erroring.
  # sigma_convergence() now says why its result is empty, which is the point of
  # this block; assert that separately from the shape check.
  expect_warning(sc_empty <- sigma_convergence(z, g),
                 class = "countryatlas_no_positive")
  for (out in list(growth_rate(z, g), share_of_world(z, g), rank_countries(z, g),
                   lag_by_country(z, g), sc_empty,
                   aggregate_regions(z, g, by = "iso3c"))) {
    expect_equal(nrow(out), 0L)
  }
})

# An empty input does not stay empty: attach_geometry() joins geometry-on-the-
# left, so it arrives at the plotting verbs as full-length columns of NA. Two
# verbs then failed inside their optional dependency -- biscale indexes
# sVar[1:(length(sVar) - 1)], which becomes 1:-1 ("only 0's may be mixed with
# negative subscripts"), and cartogram compares NA in
# `if (meanSizeError < maxSizeError)` ("missing value where TRUE/FALSE needed").
# Neither mentions the data. spike_map() already reported this properly.

test_that("bivariate_map says so when no row has both variables", {
  skip_if_no_sf_geometry()
  skip_if_not_installed("biscale")
  snap <- countryatlas::world_snapshot$countries
  empty <- suppressWarnings(attach_geometry(snap[0, ], geometry = "sf"))
  expect_gt(nrow(empty), 0L)                 # the join kept every geometry row
  expect_error(bivariate_map(empty, gdp_per_capita, population),
               "No country has both")
  expect_error(bivariate_map(empty, gdp_per_capita, population),
               class = "countryatlas_error")
  # A non-numeric column is named too, rather than failing inside biscale.
  fx <- suppressWarnings(attach_geometry(snap, geometry = "sf"))
  fx$gdp_per_capita <- factor(round(fx$gdp_per_capita))
  expect_error(bivariate_map(fx, gdp_per_capita, population), "must be numeric")
})

test_that("cartogram_map says so when nothing has a positive weight", {
  skip_if_no_sf_geometry()
  skip_if_not_installed("cartogram")
  snap <- countryatlas::world_snapshot$countries
  empty <- suppressWarnings(attach_geometry(snap[0, ], geometry = "sf"))
  expect_error(cartogram_map(empty, population), "No country has a positive")
  expect_error(dorling_map(empty, population), "No country has a positive")
  # All weights zero is the same situation: a cartogram needs positive sizes.
  z <- suppressWarnings(attach_geometry(snap, geometry = "sf"))
  z$population <- 0
  expect_error(cartogram_map(z, population), "No country has a positive")
  z$population <- factor(1)
  expect_error(cartogram_map(z, population), "must be numeric")
})

test_that("the bivariate and cartogram verbs still draw real data", {
  skip_if_no_sf_geometry()
  skip_if_not_installed("biscale")
  skip_if_not_installed("cartogram")
  snap <- countryatlas::world_snapshot$countries
  sfd <- suppressWarnings(attach_geometry(snap, geometry = "sf"))
  expect_s3_class(bivariate_map(sfd, gdp_per_capita, population), "ggplot")
  expect_s3_class(dorling_map(sfd, population), "ggplot")
  # Partly-missing columns must still draw from what is there -- and say which
  # countries dropped out, since a bivariate class needs both variables.
  part <- sfd
  part$population[seq_len(100)] <- NA
  expect_warning(
    expect_s3_class(bivariate_map(part, gdp_per_capita, population), "ggplot"),
    "no class to give")
  expect_s3_class(dorling_map(part, population), "ggplot")
})

test_that("gini/theil refuse an infinity instead of returning a silent NaN", {
  # Inf is not NA, so it survived na.rm and the non-positive filter, then made
  # the mean Inf and every share Inf/Inf -- the answer came back NaN with no
  # word. is.na(NaN) is TRUE, so an is.na() assertion could not have caught a
  # regression either (see the theil zero-weight fix). Assert NA_real_ exactly.
  expect_warning(g <- gini(c(1, 2, Inf, 4, 5)), "infinite")
  expect_identical(g, NA_real_)
  expect_warning(t <- theil(c(1, 2, Inf, 4, 5)), "infinite")
  expect_identical(t, NA_real_)
  # -Inf too, and infinite *weights*.
  expect_warning(expect_identical(gini(c(1, 2, -Inf)), NA_real_), "infinite")
  expect_warning(expect_identical(gini(c(1, 2, 3), weights = c(1, Inf, 1)),
                                  NA_real_), "infinite")
  expect_warning(expect_identical(theil(c(1, 2, 3), weights = c(1, Inf, 1)),
                                  NA_real_), "infinite")
  # With groups the degenerate answer is a bare NA, not a tibble -- documented.
  expect_warning(gt <- theil(c(1, 2, Inf, 4), groups = c("a", "a", "b", "b")),
                 "infinite")
  expect_identical(gt, NA_real_)
  expect_false(is.data.frame(gt))

  # NaN is NA in R, so it is still dropped by na.rm rather than refused.
  expect_silent(expect_equal(gini(c(1, 2, NaN, 4, 5)), gini(c(1, 2, 4, 5))))
  expect_silent(expect_equal(theil(c(1, 2, NaN, 4, 5)), theil(c(1, 2, 4, 5))))
  # And finite input is untouched.
  expect_silent(expect_equal(round(gini(c(1, 2, 3, 4, 5)), 6), 0.266667))
  expect_silent(expect_equal(round(theil(c(1, 2, 3, 4, 5)), 6), 0.119688))

  # The guard is is.infinite(), not !is.finite(): with na.rm = FALSE an NA must
  # still return a quiet NA rather than being reported as an infinity. In theil
  # the guard sits ahead of the anyNA() line, so the distinction is reachable.
  expect_silent(expect_identical(theil(c(1, 2, NA), na.rm = FALSE), NA_real_))
  expect_silent(expect_identical(theil(c(1, 2, NaN), na.rm = FALSE), NA_real_))
  expect_silent(expect_identical(gini(c(1, 2, NA), na.rm = FALSE), NA_real_))
})

test_that("the other verbs propagate an infinity visibly", {
  # gini/theil are the exception because an inequality index has no infinite
  # value to report. Everywhere else Inf in / Inf out is the honest answer, and
  # share_of_world already guards its total -- so this pins the contrast rather
  # than proposing more guards.
  d <- tibble::tibble(iso3c = c("A", "B", "C"), continent = "X",
                      v = c(1, Inf, 3), pop = c(10, 20, 30))
  expect_equal(aggregate_regions(d, v, by = "continent", fun = "sum")$v, Inf)
  expect_equal(aggregate_regions(d, v, by = "continent", fun = "mean")$v, Inf)
  expect_equal(per_capita(d, v, pop = pop)$v_per_capita, c(0.1, Inf, 0.1))
  # share_of_world's non-finite total guard returns NA rather than all-zero.
  expect_true(all(is.na(share_of_world(d, v)$v_share)))
  # The largest value still ranks first.
  expect_identical(rank_countries(d, v)$rank[2], 1L)
})

test_that("the plotting verbs handle an empty frame without leaking", {
  # Iteration-11's degenerate sweep covered the analysis kernels; the plotting
  # verbs were never fed a zero-row frame. Most draw an empty panel, which is
  # the right answer. The two that could not were both leaking someone else's
  # message: facet_map got ggplot2's "Faceting variables must have at least one
  # value", and geom_country_labels ran polygon_centroids() over nothing, where
  # range() warns twice and dplyr adds a deprecation note.
  skip_if_no_sf_geometry()
  skip_if_not_installed("maps")
  snap <- countryatlas::world_snapshot$countries
  sfd <- attach_geometry(snap, geometry = "sf")
  poly <- attach_geometry(snap, geometry = "polygon")

  # These draw an empty plot rather than erroring.
  for (p in list(world_map(sfd[0, ], gdp_per_capita),
                 world_map(poly[0, ], gdp_per_capita),
                 world_map(sfd[0, ], gdp_per_capita, style = "quantile"),
                 bubble_map(sfd[0, ], population, backend = "sf"),
                 tile_map(snap[0, ], gdp_per_capita))) {
    expect_no_error(ggplot2::ggplot_build(p))
  }

  # geom_country_labels must be silent on an empty frame, as it is on a full one.
  expect_silent(ggplot2::ggplot_build(
    ggplot2::ggplot(poly[0, ]) + geom_country_labels()))

  # facet_map cannot draw nothing, but the message must be ours.
  expect_error(facet_map(sfd[0, ], gdp_per_capita, continent),
               "no rows to facet", class = "countryatlas_error")
  expect_error(facet_map(sfd[0, ], gdp_per_capita, continent), "facet")

  # And the verbs that refuse an empty frame already name the reason themselves.
  expect_error(spike_map(poly[0, ], population), class = "countryatlas_error")
  expect_error(bivariate_map(sfd[0, ], gdp_per_capita, life_expectancy),
               class = "countryatlas_error")

  # A single row is legal everywhere it is meaningful.
  expect_no_error(ggplot2::ggplot_build(world_map(sfd[1, ], gdp_per_capita)))
  expect_no_error(ggplot2::ggplot_build(
    world_map(sfd[1, ], gdp_per_capita, style = "quantile")))
  expect_error(morans_i(sfd[1, ], gdp_per_capita, n_perm = 0),
               class = "countryatlas_error")   # needs >= 3 bordering countries
})
