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
  # A zero world total has no meaningful share -- and share_of_world() now
  # says so rather than returning a column of NA in silence.
  expect_warning(
    z <- share_of_world(data.frame(iso3c = c("A", "B"), v = c(-2, 2)), v),
    class = "countryatlas_no_rates")
  expect_true(all(is.na(z$v_share)))
  # A usable total, however odd its parts, stays silent.
  expect_no_warning(share_of_world(data.frame(iso3c = c("A", "B"),
                                              v = c(-1, 3)), v))
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
  # share_of_world's non-finite total guard returns NA rather than all-zero --
  # and now says so, as per_capita() and to_ppp() already did.
  expect_warning(sw <- share_of_world(d, v), class = "countryatlas_no_rates")
  expect_true(all(is.na(sw$v_share)))
  # The largest value still ranks first. rank_countries() now also says that
  # z_score is undefined here -- scale() turned the infinity into an all-NaN
  # column -- while rank and percentile, being rank-based, are unaffected.
  expect_warning(rk <- rank_countries(d, v), "infinite")
  expect_identical(rk$rank[2], 1L)
  expect_true(all(is.na(rk$z_score)))
  expect_false(any(is.nan(rk$z_score)))
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

test_that("cagr growth is NA-and-loud for a negative value, but keeps -100% for zero", {
  # `v0 > 0` guarded the base of the ratio and nothing guarded the current
  # value, so a fractional power of a negative ratio put a bare NaN in the
  # column with nothing said. Every neighbouring measure reports this case --
  # theil() drops non-positive values and says so, gini() warns, and
  # growth_rate() itself warns when *every* row is NA -- so the partial case
  # was the one silent spot, and it is the one a real series hits: a deficit
  # or a net flow dipping below zero for a single year.
  #
  # Rows are addressed by iso3c/year rather than by position: the frame comes
  # back sorted, so "row 1" is DEU, not the first country named.
  mk <- function(edit = identity) {
    d <- expand.grid(iso3c = c("FRA", "DEU"), year = 2000:2006,
                     stringsAsFactors = FALSE)
    d <- d[order(d$iso3c, d$year), ]
    rownames(d) <- NULL
    d$value <- seq_len(nrow(d)) * 1.5 + 10
    edit(d)
  }
  at <- function(d, iso, yr) which(d$iso3c == iso & d$year == yr)
  set <- function(iso, yr, v) function(d) { d$value[at(d, iso, yr)] <- v; d }

  # A clean positive panel says nothing and is all finite bar the base years.
  clean <- expect_silent(growth_rate(mk(), value, type = "cagr"))
  expect_equal(sum(is.na(clean$value_growth)), 2L)   # one base year per country
  expect_false(any(is.nan(clean$value_growth)))

  # One negative year mid-series: NA, not NaN, and it says how many rows.
  d_neg <- mk(set("FRA", 2004, -3))
  expect_warning(got <- growth_rate(d_neg, value, type = "cagr"),
                 class = "countryatlas_cagr_negative")
  expect_false(any(is.nan(got$value_growth)))
  expect_true(is.na(got$value_growth[at(got, "FRA", 2004)]))
  expect_equal(sum(is.na(got$value_growth)), 3L)     # 2 base years + the row
  expect_warning(growth_rate(d_neg, value, type = "cagr"), "1 row")
  # The other country is untouched.
  expect_false(any(is.na(got$value_growth[got$iso3c == "DEU"] [-1])))

  # A negative *base* takes that country out entirely, and says so rather than
  # returning a column of NA with no explanation.
  d_nb <- mk(set("FRA", 2000, -1))
  expect_warning(got <- growth_rate(d_nb, value, type = "cagr"),
                 class = "countryatlas_cagr_negative")
  expect_true(all(is.na(got$value_growth[got$iso3c == "FRA"])))
  expect_false(all(is.na(got$value_growth[got$iso3c == "DEU"])))

  # A value of exactly 0 is *not* excluded: (0/v0)^(1/n) - 1 is -1, an
  # annualised -100%, the correct and informative answer for a series that
  # went to nothing. The first version of this fix wrongly lumped it in with
  # negatives.
  d_z <- mk(set("FRA", 2004, 0))
  gz <- expect_silent(growth_rate(d_z, value, type = "cagr"))
  expect_equal(gz$value_growth[at(gz, "FRA", 2004)], -1)
  expect_equal(sum(is.na(gz$value_growth)), 2L)      # no extra NA vs clean

  # All negative: warn_all_na_result() already covers that and says something
  # more useful, so the per-row warning stands down rather than doubling up.
  d_all <- mk(function(d) { d$value <- -d$value; d })
  w <- testthat::capture_warnings(growth_rate(d_all, value, type = "cagr"))
  expect_length(grep("negative", w, ignore.case = TRUE), 0L)
  expect_true(any(grepl("every row", w)))

  # yoy is a plain ratio change, defined for negatives -- untouched.
  expect_silent(y <- growth_rate(d_neg, value, type = "yoy"))
  expect_false(any(is.nan(y$value_growth)))
})

test_that("the global G refuses a signed variable instead of ignoring the sign", {
  # The general G compares cross-products, so x_i * x_j is unchanged when the
  # whole variable is negated -- g(x) and g(-x) were bit-for-bit identical and
  # the statistic could not distinguish a coldspot pattern from a hotspot one.
  # gini(), the nearest analogue, already warns and returns NA for negatives.
  skip_if_no_sf_geometry()
  iso <- c("FRA", "DEU", "ITA", "ESP", "BEL", "NLD", "AUT", "CHE")
  w <- country_weights("knn", k = 3, countries = iso)
  mk <- function(v) data.frame(iso3c = iso, v = v, stringsAsFactors = FALSE)
  x <- c(45, 52, 38, 41, 60, 33, 47, 71) * 1000

  # Positive: silent, and a real number.
  pos <- expect_silent(getis_ord(mk(x), v, weights = w, local = FALSE))
  expect_true(is.finite(pos$g))
  # Zero is inside the domain x >= 0.
  expect_silent(getis_ord(mk(replace(x, 2, 0)), v, weights = w, local = FALSE))

  # One negative, and all negative: NA plus a warning that counts them.
  for (vals in list(replace(x, 3, -38000), -x)) {
    expect_warning(got <- getis_ord(mk(vals), v, weights = w, local = FALSE),
                   class = "countryatlas_global_g_negative")
    expect_true(is.na(got$g))
    # The parts that depend only on the weights are still reported.
    expect_true(is.finite(got$expected))
    expect_equal(got$n, length(iso))
  }
  expect_warning(getis_ord(mk(-x), v, weights = w, local = FALSE), "8 negative")

  # The local branch standardises, so signed data is fine there -- the guard
  # must not leak across.
  expect_silent(loc <- getis_ord(mk(-x), v, weights = w, local = TRUE))
  expect_true(all(is.finite(loc$z_score)))
})

test_that("rate_check's flagged column agrees with its own no-threshold warning", {
  # The warning says "`flagged` is `NA` throughout" when no small-denominator
  # threshold can be computed. It was not: `is.finite(den) & den < thr` gives
  # FALSE rather than NA for a non-finite denominator, because R
  # short-circuits `FALSE & NA` to FALSE. So an all-NA denominator produced
  # FALSE throughout and sum(out$flagged) returned 0 -- a confident "nothing
  # is flagged", which is the exact misreading the warning exists to prevent.
  # An all-zero denominator did give NA, so the two disagreed with each other
  # as well as with the message.
  d <- data.frame(iso3c = c("FRA", "DEU", "ITA"), num = c(3, 4, 5),
                  den = c(100, 200, 300), stringsAsFactors = FALSE)
  no_threshold <- list(
    "all NA"       = rep(NA_real_, 3),
    "all zero"     = c(0, 0, 0),
    "all negative" = c(-5, -9, -2)
  )
  for (nm in names(no_threshold)) {
    z <- d
    z$den <- no_threshold[[nm]]
    w <- capture_warnings(r <- rate_check(z, num, den))
    # The message fires and the column matches what it promises.
    expect_true(any(grepl("No usable", w)), info = nm)
    expect_true(all(is.na(r$flagged)), info = nm)
    expect_type(r$flagged, "logical")
    # sum() is NA, not a confident zero -- the point of the warning.
    expect_true(is.na(sum(r$flagged)), info = nm)
  }

  # The biconditional: the warning fires exactly when flagged is all NA.
  for (den in list(c(100, 200, 300), c(NA_real_, 200, 300), rep(NA_real_, 3))) {
    z <- d
    z$den <- den
    w <- capture_warnings(r <- rate_check(z, num, den))
    expect_equal(any(grepl("No usable", w)), all(is.na(r$flagged)))
  }

  # The normal path is unchanged: a finite threshold still flags the smallest
  # denominators, a missing denominator among usable ones still reads FALSE
  # (so sum() keeps working), and nothing is NA.
  big <- data.frame(iso3c = sprintf("C%02d", 1:20), num = 1:20,
                    den = (1:20) * 100, stringsAsFactors = FALSE)
  r <- expect_silent(rate_check(big, num, den))
  expect_equal(sum(r$flagged), 2L)          # bottom decile of 20
  expect_false(any(is.na(r$flagged)))
  expect_true(is.finite(attr(r, "min_denominator")))
  mixed <- d
  mixed$den <- c(NA_real_, 200, 300)
  rm2 <- expect_silent(rate_check(mixed, num, den))
  expect_false(any(is.na(rm2$flagged)))
  expect_false(is.na(sum(rm2$flagged)))
  # An explicit min_denominator is a finite threshold too.
  r3 <- expect_silent(rate_check(d, num, den, min_denominator = 250))
  expect_equal(sum(r3$flagged), 2L)
})

test_that("audit_time_coverage's three message paths read correctly", {
  # Coverage showed none of these lines ever running, so the pluralisation had
  # never been checked at both counts -- and `{?s}` keys to the most recently
  # interpolated value, which this package has got wrong before. "1 row falls"
  # and "2 rows fall" both have to come out right, and the no-findings path has
  # its own message.
  mk <- function(n) {
    data.frame(iso3c = rep("SUN", n), year = seq(1995, length.out = n),
               stringsAsFactors = FALSE)
  }
  expect_message(audit_time_coverage(mk(1)), "1 row falls outside")
  expect_message(audit_time_coverage(mk(2)), "2 rows fall outside")
  # A clean frame reports the opposite, rather than saying nothing.
  expect_message(audit_time_coverage(data.frame(iso3c = "FRA", year = 2020L)),
                 "No rows fall outside")

  # The empty-input early return still has the full column contract.
  r <- suppressMessages(
    audit_time_coverage(data.frame(iso3c = character(0), year = integer(0))))
  expect_equal(nrow(r), 0L)
  expect_named(r, c("iso3c", "country", "year", "issue", "existed"))
})

test_that("interpolate_missing rejects duplicate column names once", {
  # interpolate_missing() carried its own duplicate-name guard that became
  # unreachable when check_panel_unique() grew one; coverage flagged it as
  # never executed and it has been removed. The rejection itself must survive,
  # since the dplyr pipeline would otherwise repair the names quietly and hand
  # back a `v.1` column the caller never created.
  mk <- function(dups) {
    d <- data.frame(iso3c = c("FRA", "DEU"), year = c(2020L, 2021L),
                    stringsAsFactors = FALSE)
    for (nm in dups) d <- cbind(d, setNames(data.frame(c(1, 2)), nm),
                                setNames(data.frame(c(3, 4)), nm))
    names(d) <- c("iso3c", "year", rep(dups, each = 2))
    d
  }
  expect_error(interpolate_missing(mk("v"), "v"),
               class = "countryatlas_duplicate_columns")
  expect_error(interpolate_missing(mk("v"), "v"), "1 duplicated column name")
  expect_error(interpolate_missing(mk(c("v", "w")), "v"), "2 duplicated column names")
  # A clean panel is unaffected: an interior gap fills, and no column is added.
  ok <- data.frame(iso3c = rep("FRA", 3), year = 2020:2022, v = c(1, NA, 3),
                   stringsAsFactors = FALSE)
  r <- interpolate_missing(ok, "v")
  expect_equal(r$v, c(1, 2, 3))
  expect_false("v.1" %in% names(r))
})

test_that("a top_n past integer range means no limit, not a base R error", {
  # `Inf` is the documented "no limit" and both callers gate on
  # is.finite(top_n) to spot it. A *finite* value past integer range passed
  # that gate and then broke on the coercion behind it: as.integer(1e18) is
  # NA, so utils::head(df, NA) surfaced base R's "invalid 'n' - must contain
  # at least one non-missing element" -- a bare simpleError naming neither
  # top_n nor the package. Asking for at most 1e18 rows of a 191-row table is
  # the same request as Inf, so it is normalised rather than rejected.
  d <- countryatlas::world_snapshot$countries
  all_rows <- nrow(suppressWarnings(suppressMessages(
    world_table(d, gdp_per_capita, top_n = Inf, engine = "tibble"))))
  expect_gt(all_rows, 100L)
  for (v in list(1e18, 2147483648, 1e300, .Machine$double.xmax)) {
    r <- suppressWarnings(suppressMessages(
      world_table(d, gdp_per_capita, top_n = v, engine = "tibble")))
    expect_equal(nrow(r), all_rows)
  }
  # A representable limit still limits, and integer.max itself is fine.
  expect_equal(nrow(suppressWarnings(suppressMessages(
    world_table(d, gdp_per_capita, top_n = 5, engine = "tibble")))), 5L)
  expect_equal(nrow(suppressWarnings(suppressMessages(
    world_table(d, gdp_per_capita, top_n = .Machine$integer.max,
                engine = "tibble")))), all_rows)
  # Genuinely invalid values are still refused, with the package's own class.
  for (bad in list(0, -1, NA, "x", c(1, 2), NULL)) {
    expect_error(world_table(d, gdp_per_capita, top_n = bad),
                 class = "countryatlas_error")
  }
  # country_network() shares the helper and the same is.finite() gate.
  od <- data.frame(from = c("FRA", "DEU", "ITA", "ESP"),
                   to = c("DEU", "ITA", "ESP", "FRA"), w = c(4, 3, 2, 1),
                   stringsAsFactors = FALSE)
  net <- function(v) suppressWarnings(suppressMessages(
    country_network(od, from, to, w, origin = "iso3c", top_n = v)))
  expect_equal(net(1e18), net(Inf))
  expect_false(identical(net(2), net(Inf)))
  # And the helper itself normalises rather than erroring.
  expect_equal(countryatlas:::check_top_n(1e18), Inf)
  expect_equal(countryatlas:::check_top_n(5), 5)
})

test_that("an absurd dorling k is refused by us, not by GEOS", {
  # check_number() already refuses Inf, but `k` was bounded below only, so a
  # merely enormous finite value passed and overflowed the coordinate
  # arithmetic inside GEOS: "IllegalArgumentException:
  # CGAlgorithmsDD::orientationIndex encountered NaN/Inf numbers", a bare
  # simpleError from a C++ library naming neither k nor the function. Same
  # shape as the top_n bug above -- a guard with a floor and no ceiling.
  skip_if_no_sf_geometry()
  skip_if_not_installed("cartogram")
  g <- attach_geometry(countryatlas::world_snapshot$countries, geometry = "sf")
  draw <- function(v) suppressWarnings(suppressMessages(
    dorling_map(g, population, k = v)))
  # Sane values are untouched.
  expect_s3_class(draw(5), "ggplot")
  expect_s3_class(draw(0.5), "ggplot")
  expect_s3_class(draw(1e6), "ggplot")
  # The overflow case is ours now, with our class and our argument named.
  expect_error(draw(1e300), class = "countryatlas_error")
  expect_error(draw(1e300), "`k`")
  # Pre-existing rejections still read the same.
  expect_error(draw(Inf), class = "countryatlas_error")
  expect_error(draw(-1), class = "countryatlas_error")
  expect_error(draw(0), "greater than 0")
})

test_that("tissot_map closes its circles at every radius, not just the default", {
  # The circle vertices are generated by walking out along azimuths 0..2*pi,
  # then wrapping longitude into [-180, 180). az = 0 and az = 2*pi are the
  # same point, but the wrap could send the two ends to -180 and +180 -- the
  # same meridian, opposite signs -- leaving st_polygon() with an unclosed
  # ring and sf reporting "polygons not (all) closed", an unclassed error.
  #
  # Whether it happened depended on the radius, so the default hid it: at
  # 500 km no centre in the grid produced such a ring, at 1000 km six did.
  # The failures were not monotonic either -- 500 and 10000 worked while 1000,
  # 5000 and 20000 did not -- which is why a bound on radius_km would have
  # been the wrong fix.
  skip_if_no_sf_geometry()
  for (r in c(100, 500, 1000, 2000, 5000, 8000, 10000, 12000, 20000, 40000)) {
    p <- expect_silent(suppressMessages(tissot_map(radius_km = r)))
    expect_s3_class(p, "ggplot")
  }
  # The default still draws every centre in the grid, and a larger radius
  # drops more circles to the antimeridian guard rather than erroring.
  n_at <- function(r) nrow(suppressMessages(tissot_map(radius_km = r))$layers[[2]]$data)
  expect_equal(n_at(500), n_at(100))
  expect_lt(n_at(5000), n_at(500))
  # And the rings really are closed, which is the property that broke.
  ring_closed <- function(r) {
    p <- suppressMessages(tissot_map(radius_km = r))
    geo <- p$layers[[2]]$data$geometry
    if (length(geo) == 0L) return(TRUE)
    all(vapply(geo, function(g) {
      m <- sf::st_coordinates(g)[, c("X", "Y"), drop = FALSE]
      identical(m[1L, ], m[nrow(m), ])
    }, logical(1)))
  }
  expect_true(ring_closed(1000))
  expect_true(ring_closed(5000))
})

test_that("theil() keeps the decomposition identity when a group has no weight", {
  x <- c(1, 2, 3, 5, 8, 13, 21, 34)
  w <- c(0, 0, 1, 1, 1, 1, 1, 1)
  g <- c("A", "A", rep("B", 6))
  out <- suppressWarnings(theil(x, weights = w, groups = g))
  v <- stats::setNames(out$value, out$component)

  # The bug: mug <- 0/0 for group A, so both components came back NaN beside a
  # perfectly good total.
  expect_false(anyNA(v))
  expect_equal(v[["total"]], v[["between"]] + v[["within"]])
  # Only group B carries any weight, so all of the inequality is within it.
  expect_equal(v[["between"]], 0)
  expect_equal(v[["within"]], v[["total"]])
  # ... and it matches the same call with the zero-weight rows simply removed.
  keep <- w > 0
  expect_equal(v[["total"]], suppressWarnings(theil(x[keep], weights = w[keep])))
})

test_that("interpolate_missing() keeps a column's class whether or not it has a gap", {
  mk <- function(v) data.frame(iso3c = rep("FRA", 6), year = 2000:2005, value = v)
  dates <- as.Date("2020-01-01") + c(0, 1, NA, 3, 4, 5)
  whole <- as.Date("2020-01-01") + 0:5

  for (m in c("locf", "linear")) {
    # The bug: ifelse() dropped the class, so the gapped column came back as
    # bare numbers (18262) while the gapless one -- an early return -- stayed a
    # Date. Same column, different type, depending only on the data.
    gapped <- interpolate_missing(mk(dates), "value", method = m)
    intact <- interpolate_missing(mk(whole), "value", method = m)
    expect_s3_class(gapped$value, "Date")
    expect_s3_class(intact$value, "Date")
    expect_false(anyNA(gapped$value))
  }

  # An integer column stays integer under LOCF, and widens under linear only
  # because interpolated values are genuinely fractional.
  ints <- c(1L, 2L, NA, 4L, 5L, 6L)
  expect_type(interpolate_missing(mk(ints), "value", method = "locf")$value, "integer")
  expect_type(interpolate_missing(mk(ints), "value", method = "linear")$value, "double")
})

test_that("an unresolved value that is a code under another origin says so", {
  # ISO3 under the country.name default is the commonest way to misuse these
  # verbs, and the generic advice (check_country_match()) is useless for a code.
  expect_error(country_factsheet("FRA"), 'origin = "iso3c"')
  expect_warning(distance_between("FR", "DE"), 'origin = "iso2c"')
  # A genuinely unknown name must NOT get a hint, only the close-name advice.
  expect_error(country_factsheet("Freedonia"), "check_country_match")
  unknown <- tryCatch(country_factsheet("Freedonia"), error = conditionMessage)
  expect_no_match(unknown, "try that instead", fixed = TRUE)
  # Singular and plural both read correctly.
  expect_error(country_factsheet("FRA"), "It resolves under")
  expect_warning(distance_between(c("FR", "DE"), c("IT", "ES")),
                 "They all resolve under")
})

test_that("the origin hint reaches the geometry verbs too", {
  # neighbors() reads country_borders(), which needs sf -- without this guard
  # the expectation fails under _R_CHECK_DEPENDS_ONLY_ with sf's "not
  # installed" error instead of the warning under test.
  skip_if_not_installed("sf")
  expect_warning(neighbors(c("FRA", "DEU")), 'origin = "iso3c"')
  # The reverse direction is caught too.
  expect_warning(neighbors(c("France", "Germany"), origin = "iso3c"),
                 'origin = "country.name"')
})

test_that("a gap in year is reported by the verbs that read neighbouring rows", {
  gappy <- data.frame(iso3c = rep("FRA", 4), year = c(2000, 2002, 2005, 2006),
                      value = c(100, 110, 140, 150))
  annual <- data.frame(iso3c = rep("FRA", 4), year = 2000:2003,
                       value = c(100, 110, 140, 150))

  # The bug: 2005's "year-on-year" growth is the change since 2002, and nothing
  # said so. The number stays; the warning is what was missing.
  expect_warning(growth_rate(gappy, value), "spans more than one year")
  expect_warning(lag_by_country(gappy, value), "spans more than one year")
  expect_warning(diff_by_country(gappy, value), "spans more than one year")
  expect_equal(suppressWarnings(growth_rate(gappy, value))$value_growth,
               c(NA, 0.1, 30 / 110, 10 / 140))

  # cagr divides by the real year span, so a gap is already handled there.
  expect_no_warning(growth_rate(gappy, value, type = "cagr"))
  expect_no_warning(growth_rate(annual, value))
  expect_no_warning(lag_by_country(annual, value))

  # Names only the countries that actually have gaps.
  mixed <- data.frame(iso3c = c("FRA", "FRA", "DEU", "DEU", "ITA", "ITA"),
                      year = c(2000, 2002, 2000, 2001, 2000, 2004),
                      value = 1:6)
  w <- tryCatch(lag_by_country(mixed, value), warning = conditionMessage)
  expect_match(w, "FRA")
  expect_match(w, "ITA")
  expect_no_match(w, "DEU")

  # Row order must not matter -- the check sorts, like the verbs do.
  expect_warning(lag_by_country(gappy[c(3, 1, 4, 2), ], value),
                 "spans more than one year")
  # One row per country has no predecessor at all; the existing all-NA warning
  # covers that, and this check must stay quiet rather than double-report.
  single <- data.frame(iso3c = c("FRA", "DEU"), year = c(2000, 2005), value = 1:2)
  w2 <- tryCatch(lag_by_country(single, value), warning = conditionMessage)
  expect_no_match(w2, "spans more than one year")

  # A repeated country-year is a step of 0, not a gap. check_panel_unique()
  # reports it accurately; this check must not also claim a gap that is not
  # there, or every duplicate warns twice and one of the two is wrong.
  dup <- data.frame(iso3c = rep("FRA", 4), year = c(2000, 2001, 2001, 2002),
                    value = c(1, 2, 9, 3))
  msgs <- character(0)
  withCallingHandlers(invisible(lag_by_country(dup, value)),
    warning = function(w) { msgs <<- c(msgs, conditionMessage(w))
                            invokeRestart("muffleWarning") })
  expect_length(msgs, 1L)
  expect_match(msgs, "repeated country-year")
})

test_that("convergence_club() refuses a repeated country-year with a classed error", {
  d <- data.frame(iso3c = c("FRA", "FRA", "FRA"), year = c(2000, 2001, 2001),
                  value = c(10, 20, 99))
  # The bug: base R's "invalid 'type' (list) of argument", an unclassed
  # simpleError from as.matrix() on the list-column pivot_wider() produced.
  err <- tryCatch(suppressWarnings(convergence_club(d, value)), error = function(e) e)
  expect_s3_class(err, "countryatlas_error")
  expect_match(conditionMessage(err), "repeated country-year")
  expect_match(conditionMessage(err), "FRA 2001")
  expect_no_match(conditionMessage(err), "invalid 'type'", fixed = TRUE)
})

test_that("locate_country() handles NA and out-of-range coordinates", {
  skip_if_not_installed("sf")

  # The bug: sf::st_as_sf() refused the NA outright with an unclassed
  # "missing values in coordinates not allowed", losing the good points too.
  mixed <- locate_country(c(2.35, NA, 13.4), c(48.86, 48.86, 52.5))
  expect_equal(mixed$iso3c, c("FRA", NA, "DEU"))
  expect_equal(nrow(mixed), 3L)

  # All-NA input returns the same shape, not an error and not zero rows.
  alln <- locate_country(c(NA_real_, NA_real_), c(NA_real_, NA_real_))
  expect_equal(nrow(alln), 2L)
  expect_true(all(is.na(alln$iso3c)))

  # The column shape must not depend on which branch ran.
  for (a in list("country", character(0), c("country", "continent"))) {
    good <- locate_country(c(2.35, 13.4), c(48.86, 52.5), add = a)
    expect_named(locate_country(c(2.35, NA), c(48.86, 52.5), add = a), names(good))
    expect_named(locate_country(c(NA_real_, NA_real_), c(NA_real_, NA_real_),
                                add = a), names(good))
  }

  # Out of range was a silent NA -- the same answer as open ocean.
  expect_error(locate_country(362.35, 48.86), "outside the valid range")
  expect_error(locate_country(2.35, 91), "outside the valid range")
  expect_error(locate_country(362.35, 48.86), "-180")
  # In-range values are untouched.
  expect_equal(locate_country(2.35, 48.86)$iso3c, "FRA")
  expect_equal(locate_country(c(180, -180), c(-17.7, -17.7))$iso3c,
               locate_country(c(180, -180), c(-17.7, -17.7))$iso3c)
})

test_that("beta_convergence() drops an infinite value instead of crashing", {
  iso <- c("FRA", "DEU", "ITA", "ESP", "POL", "PRT")
  d <- expand.grid(iso3c = iso, year = 2000:2019, stringsAsFactors = FALSE)
  d$value <- rep(seq(1000, 6000, length.out = 6), 20) * (1.02^(d$year - 2000))

  clean <- beta_convergence(d, value)
  inf <- d; inf$value[3] <- Inf
  # The bug: Inf passes both !is.na() and > 0, so it reached log() and lm()
  # died with base R's unclassed "NA/NaN/Inf in 'x'".
  got <- beta_convergence(inf, value)
  expect_s3_class(got, "data.frame")
  expect_true(is.finite(got$beta))
  # -Inf and NaN take the same route.
  for (v in c(-Inf, NaN)) {
    z <- d; z$value[3] <- v
    expect_true(is.finite(beta_convergence(z, value)$beta))
  }
  # An untouched panel is unchanged by the new filter.
  expect_equal(beta_convergence(d, value)$beta, clean$beta)
})

test_that("a character year is refused only where a year is arithmetic", {
  iso <- c("FRA", "DEU", "ITA", "ESP", "POL", "PRT")
  d <- expand.grid(iso3c = iso, year = 2000:2019, stringsAsFactors = FALSE)
  d$value <- rep(seq(1000, 6000, length.out = 6), 20) * (1.02^(d$year - 2000))
  dc <- d; dc$year <- as.character(dc$year)

  # These compute with the year. Each used to fail differently -- a base error,
  # a dplyr mutate error, an exposed join -- and now share one classed message.
  expect_error(beta_convergence(dc, value), 'Column "year" must be numeric')
  expect_error(growth_rate(dc, value, type = "cagr"), 'Column "year" must be numeric')
  expect_error(deflate(dc, value, base_year = 2000), 'Column "year" must be numeric')
  expect_error(complete_years(dc, years = 2000:2019, value = "value"),
               'Column "year" must be numeric')

  # These only sort or group on it, so a character year is fine and must stay
  # fine -- guarding them too would reject input that works today.
  expect_no_error(growth_rate(dc, value, type = "yoy"))
  expect_no_error(lag_by_country(dc, value))
  expect_no_error(diff_by_country(dc, value))
  expect_no_error(index_to(dc, value, base_year = 2000))
  expect_no_error(sigma_convergence(dc, value))
  expect_no_error(suppressWarnings(convergence_club(dc, value)))
  expect_no_error(interpolate_missing(dc, "value"))
  expect_no_error(share_of_world(dc, value))
  expect_no_error(rank_countries(dc, value))
  # ... and give the same answer as the numeric-year panel.
  expect_equal(growth_rate(dc, value)$value_growth, growth_rate(d, value)$value_growth)
})

test_that("an infinite value never silently produces NaN", {
  iso <- c("FRA", "DEU", "ITA", "ESP", "POL", "PRT")
  d <- expand.grid(iso3c = iso, year = 2000:2019, stringsAsFactors = FALSE)
  d$value <- rep(seq(1000, 6000, length.out = 6), 20) * (1.02^(d$year - 2000))

  for (spike in c(Inf, -Inf)) {
    bad <- d; bad$value[3] <- spike

    # rank_countries: scale() turned ONE infinity into an all-NaN column while
    # rank and percentile still looked right.
    rk <- suppressWarnings(rank_countries(bad, value))
    expect_false(any(is.nan(rk$z_score)))
    expect_true(all(is.na(rk$z_score)))
    expect_false(anyNA(rk$rank))
    expect_false(anyNA(rk$percentile))
    expect_warning(rank_countries(bad, value), "infinite")

    # sigma_convergence: Inf passed the !is.na() filter into sd(log(x)).
    sg <- suppressWarnings(sigma_convergence(bad, value))
    expect_false(any(is.nan(sg$sigma)))
  }

  # index_to: an infinite base made every other year finite/Inf, a plausible 0.
  ix <- data.frame(iso3c = rep(c("FRA", "DEU"), each = 4),
                   year = rep(2000:2003, 2),
                   value = c(Inf, 110, 120, 130, 50, 55, 60, 65))
  out <- suppressWarnings(index_to(ix, value, base_year = 2000))
  expect_true(all(is.na(out$value_index[out$iso3c == "FRA"])))
  expect_equal(out$value_index[out$iso3c == "DEU"], c(100, 110, 120, 130))

  # None of this may move a clean panel.
  expect_equal(suppressWarnings(rank_countries(d, value))$z_score,
               as.numeric(scale(d$value)))
  expect_false(anyNA(suppressWarnings(sigma_convergence(d, value))$sigma))
})

test_that("interpolate_missing() cannot turn its own imputation flag off", {
  d <- data.frame(iso3c = rep(c("FRA", "DEU"), each = 4), year = rep(2000:2003, 2),
                  value = c(1, NA, 3, 4, 5, 6, NA, 8))
  once <- interpolate_missing(d, "value")
  expect_equal(sum(once$value_imputed), 2L)

  # The bug: the flag was recomputed as "was NA, is not now", and after the
  # first call nothing is NA -- so every TRUE became FALSE and world_map()
  # would draw imputed values as observed, with no caption. The documented
  # hard rule is that the flag cannot be turned off.
  twice <- interpolate_missing(once, "value")
  expect_equal(twice$value_imputed, once$value_imputed)
  expect_equal(as.data.frame(twice), as.data.frame(once), ignore_attr = TRUE)
  # Still true a third time.
  expect_equal(interpolate_missing(twice, "value")$value_imputed, once$value_imputed)

  # The flags must land on the right rows even when the input is unsorted --
  # the pipeline arranges by (iso3c, year), so a positionally-held vector would
  # misalign them.
  u <- d[c(6, 2, 8, 1, 4, 7, 3, 5), ]
  ua <- interpolate_missing(u, "value")
  ub <- interpolate_missing(ua, "value")
  imputed <- ub[ub$value_imputed, c("iso3c", "year")]
  expect_equal(imputed$iso3c, c("DEU", "FRA"))
  expect_equal(imputed$year, c(2002, 2001))

  # No internal bookkeeping column escapes.
  expect_false(any(grepl("^\\.countryatlas_prior", names(once))))
  expect_false(any(grepl("^\\.countryatlas_prior", names(twice))))

  # Carrying the flag forward means the second call has nothing to clobber, so
  # it must not warn -- but a flag column that is not ours still does.
  expect_no_warning(interpolate_missing(once, "value"))
  mine <- d; mine$value_imputed <- "mine"
  expect_warning(interpolate_missing(mine, "value"), "Overwriting")
})

test_that("map_provenance() counts imputed values in a data frame", {
  b <- data.frame(iso3c = c("FRA", "DEU", "ITA", "ESP"), gdp = c(10, 20, 30, 40),
                  stringsAsFactors = FALSE)
  d <- rbind(transform(b, year = 2020), transform(b, year = 2021),
             transform(b, year = 2022))
  d <- d[order(d$iso3c, d$year), ]
  # Middle year, so both methods can actually fill it: neither extrapolates.
  d$gdp[d$year == 2021 & d$iso3c %in% c("DEU", "ESP")] <- NA
  f <- interpolate_missing(d, "gdp")
  slice <- f[f$year == 2021, ]
  expect_equal(sum(slice$gdp_imputed), 2L)

  # The bug: the data-frame branch never set n_imputed, and the fallback is
  # `%||% 0L` -- so it asserted "nothing imputed" rather than reporting.
  expect_equal(map_provenance(slice, gdp)$n_imputed, 2L)
  # A panel counts once per country, not from an arbitrary first row.
  expect_equal(map_provenance(f, gdp)$n_imputed, 2L)
  # No flags at all is still an honest zero.
  expect_equal(map_provenance(b, gdp)$n_imputed, 0L)
  # And it survives a second interpolate_missing(), which used to clear the flags.
  again <- interpolate_missing(f, "gdp")
  expect_equal(map_provenance(again[again$year == 2021, ], gdp)$n_imputed, 2L)
})

test_that("imputed_count() counts a country once, from any of its rows", {
  # Cross-section: one row per country, so this must be exactly as before.
  cs <- data.frame(iso3c = c("FRA", "DEU", "ITA", "ESP"), gdp = c(1, NA, 3, NA),
                   gdp_imputed = c(FALSE, TRUE, FALSE, TRUE))
  expect_equal(countryatlas:::imputed_count(cs), 2L)
  cs$gdp_imputed <- c(FALSE, NA, FALSE, TRUE)
  expect_equal(countryatlas:::imputed_count(cs), 1L)
  expect_equal(countryatlas:::imputed_count(cs["iso3c"]), 0L)

  # Panel: the flag sits on a row that distinct() would not have picked.
  pn <- data.frame(iso3c = rep(c("FRA", "DEU"), each = 3),
                   year = rep(2000:2002, 2), gdp = 1:6,
                   gdp_imputed = c(FALSE, FALSE, TRUE, FALSE, TRUE, FALSE))
  expect_equal(countryatlas:::imputed_count(pn), 2L)
  # A country flagged in several years still counts once -- a map draws it once.
  pn$gdp_imputed <- c(TRUE, TRUE, TRUE, FALSE, FALSE, FALSE)
  expect_equal(countryatlas:::imputed_count(pn), 1L)
})

test_that("map colour breaks do not depend on the caller's row order", {
  skip_if_not_installed("sf")
  iso <- c("FRA", "DEU", "ITA", "ESP", "POL", "PRT", "GRC", "IRL", "NLD", "BEL")
  lo <- data.frame(iso3c = iso, year = 2000, v = seq(10, 100, length.out = 10),
                   stringsAsFactors = FALSE)
  hi <- data.frame(iso3c = iso, year = 2020, v = seq(1000, 10000, length.out = 10),
                   stringsAsFactors = FALSE)
  brk <- function(d, style) {
    g <- suppressWarnings(suppressMessages(attach_geometry(d, geometry = "sf")))
    p <- suppressWarnings(suppressMessages(world_map(g, v, style = style)))
    attr(p, "countryatlas_provenance")$breaks
  }
  for (style in c("quantile", "jenks")) {
    # The bug: one arbitrary row per country, so 2000-first gave breaks over
    # 10-100 and 2020-first gave 1000-10000 -- the same data, a different map.
    expect_equal(brk(rbind(lo, hi), style), brk(rbind(hi, lo), style))
    # The panel's breaks span the panel, which is what a shared facet scale needs.
    b <- brk(rbind(lo, hi), style)
    expect_equal(min(b), 10)
    expect_equal(max(b), 10000)
    # A cross-section is untouched.
    expect_equal(brk(lo, style), brk(lo[rev(seq_len(nrow(lo))), ], style))
  }
})

test_that("na_coverage() counts a country once, from any of its rows", {
  iso <- c("FRA", "DEU", "ITA", "ESP")
  y20 <- data.frame(iso3c = iso, year = 2020, v = c(NA, NA, 3, 4), stringsAsFactors = FALSE)
  y21 <- data.frame(iso3c = iso, year = 2021, v = c(1, 2, 3, 4), stringsAsFactors = FALSE)
  cov <- function(d) countryatlas:::na_coverage(d, "v")

  # Cross-sections are exactly as before.
  expect_equal(cov(y20)[c("n_total", "n_shown", "n_missing")],
               list(n_total = 4L, n_shown = 2L, n_missing = 2L))
  expect_equal(cov(y20)$missing_iso3c, c("DEU", "FRA"))
  expect_equal(cov(y21)$n_missing, 0L)

  # The bug: the same panel reordered reported 2 of 4 missing or 0 of 4.
  expect_equal(cov(rbind(y20, y21)), cov(rbind(y21, y20)))
  expect_equal(cov(rbind(y20, y21))$n_missing, 0L)
  shuffled <- rbind(y20, y21)[c(3, 7, 1, 5, 2, 8, 4, 6), ]
  expect_equal(cov(shuffled), cov(rbind(y20, y21)))

  # missing_iso3c must always name exactly n_missing countries.
  for (d in list(y20, y21, rbind(y20, y21), shuffled,
                 data.frame(iso3c = iso, v = rep(NA_real_, 4)))) {
    cv <- cov(d)
    expect_length(cv$missing_iso3c, cv$n_missing)
    expect_equal(cv$n_shown + cv$n_missing, cv$n_total)
  }
})

test_that("earliest_per_unit() picks the earliest year, not the first row", {
  p <- rbind(data.frame(iso3c = "FRA", year = 2002, v = 3),
             data.frame(iso3c = "FRA", year = 2000, v = 1),
             data.frame(iso3c = "FRA", year = 2001, v = 2))
  expect_equal(countryatlas:::earliest_per_unit(p, "iso3c")$year, 2000)
  # order() on a factor sorts by level index, so a factored year with reversed
  # levels used to hand back the latest.
  pf <- p; pf$year <- factor(pf$year, levels = c("2002", "2001", "2000"))
  expect_equal(as.character(countryatlas:::earliest_per_unit(pf, "iso3c")$year), "2000")
  pc <- p; pc$year <- as.character(pc$year)
  expect_equal(countryatlas:::earliest_per_unit(pc, "iso3c")$year, "2000")
  # No year column, and no rows, both still work.
  expect_equal(nrow(countryatlas:::earliest_per_unit(
    data.frame(iso3c = c("FRA", "FRA", "DEU"), v = 1:3), "iso3c")), 2L)
  expect_equal(nrow(countryatlas:::earliest_per_unit(p[0, ], "iso3c")), 0L)
  # Survivors keep their original relative order.
  q <- rbind(data.frame(iso3c = "ZWE", year = 2000, v = 1),
             data.frame(iso3c = "AFG", year = 2000, v = 2))
  expect_equal(countryatlas:::earliest_per_unit(q, "iso3c")$iso3c, c("ZWE", "AFG"))
})

test_that("classify_compare() classes do not depend on row order", {
  skip_if_not_installed("sf")
  iso <- c("FRA", "DEU", "ITA", "ESP", "POL", "PRT", "GRC", "IRL", "NLD", "BEL")
  lo <- data.frame(iso3c = iso, year = 2000, v = seq(10, 100, length.out = 10),
                   stringsAsFactors = FALSE)
  hi <- data.frame(iso3c = iso, year = 2020, v = seq(1000, 10000, length.out = 10),
                   stringsAsFactors = FALSE)
  sig <- function(d) {
    g <- suppressWarnings(suppressMessages(attach_geometry(d, geometry = "sf")))
    p <- suppressWarnings(suppressMessages(
      classify_compare(g, v, methods = c("quantile", "equal"))))
    x <- sf::st_drop_geometry(suppressWarnings(suppressMessages(p$data)))
    x <- x[x$iso3c %in% iso & x$.wdj_method == "quantile",
           c("iso3c", "year", ".wdj_class")]
    x[order(x$iso3c, x$year), ".wdj_class", drop = TRUE]
  }
  a <- sig(rbind(lo, hi)); b <- sig(rbind(hi, lo))
  # The bug: breaks came from one arbitrary year, so the other year's values
  # fell outside them and every one of its rows classified as NA -- half the
  # panel drawn as na.value, and swapping row order swapped which half.
  expect_equal(a, b)
  expect_false(anyNA(a))
  expect_length(a, 20L)
  # A cross-section is untouched.
  expect_equal(sig(lo), sig(lo[rev(seq_len(nrow(lo))), ]))
  expect_false(anyNA(sig(lo)))
})

test_that("distinct_countries() uses the earliest year for uncoded rows too", {
  d <- data.frame(iso3c = c(NA, NA, "FRA", "FRA"),
                  country = c("Freedonia", "Freedonia", "France", "France"),
                  year = c(2002, 2000, 2002, 2000), v = c(9, 1, 90, 10),
                  stringsAsFactors = FALSE)
  f <- function(x) {
    r <- suppressWarnings(suppressMessages(countryatlas:::distinct_countries(x)))
    r <- r[order(r$country), ]
    stats::setNames(r$v, r$country)
  }
  # The bug: the coded branch picked the earliest year, the uncoded branch --
  # three lines below it -- took whichever row came first.
  expect_equal(f(d), f(d[c(2, 1, 4, 3), ]))
  expect_equal(f(d), f(d[c(4, 3, 2, 1), ]))
  expect_equal(unname(f(d)), c(10, 1))   # both are the year-2000 values
})

test_that("a categorical fill's level order does not depend on the locale", {
  skip_if_not_installed("sf")
  # Built with escapes: every file in R/ and tests/ here is pure ASCII.
  ring <- intToUtf8(0xC5)
  labs <- c("aland", paste0(ring, "land"), "Chad", "chile", "Zambia", "Belgium")
  snap <- countryatlas::world_snapshot$countries
  d <- snap[1:12, "iso3c", drop = FALSE]
  d$cat <- rep(labs, 2)
  g <- suppressWarnings(suppressMessages(attach_geometry(d, geometry = "sf")))

  old <- Sys.getlocale("LC_COLLATE")
  on.exit(suppressWarnings(Sys.setlocale("LC_COLLATE", old)), add = TRUE)

  limits <- function(lc) {
    if (identical(suppressWarnings(Sys.setlocale("LC_COLLATE", lc)), "")) {
      return(NULL)                                   # locale unavailable here
    }
    p <- suppressWarnings(suppressMessages(world_map(g, cat, style = "categorical")))
    b <- suppressWarnings(suppressMessages(ggplot2::ggplot_build(p)))
    b$plot$scales$get_scales("fill")$get_limits()
  }
  a <- limits("C"); z <- limits("en_US.UTF-8")
  skip_if(is.null(a) || is.null(z), "needs both C and en_US.UTF-8 collation")

  # The bug: ggplot2 sorted the character column with LC_COLLATE, so the same
  # data gave a different legend order -- and a different colour per category
  # -- on machines with different locales.
  expect_equal(a, z)
  # Pinned byte order: uppercase before lowercase, accents last.
  expect_equal(setdiff(a, NA), c("Belgium", "Chad", "Zambia", "aland",
                                 paste0(ring, "land")))

  # An incoming factor keeps the caller's own order.
  d2 <- d; d2$cat <- factor(d2$cat, levels = rev(labs))
  g2 <- suppressWarnings(suppressMessages(attach_geometry(d2, geometry = "sf")))
  p2 <- suppressWarnings(suppressMessages(world_map(g2, cat, style = "categorical")))
  b2 <- suppressWarnings(suppressMessages(ggplot2::ggplot_build(p2)))
  # Not every label survives the geometry join, so compare against the ones
  # that are actually drawn -- the point is the relative order, not the set.
  got <- setdiff(b2$plot$scales$get_scales("fill")$get_limits(), NA)
  expect_equal(got, rev(labs)[rev(labs) %in% got])
  expect_false(identical(got, got[order(got, method = "radix")]))
})

test_that("classification_report rows are in a locale-independent order", {
  ring <- intToUtf8(0xC5)
  d <- data.frame(iso3c = c("FRA", "DEU", "ITA", "ESP", "POL"),
                  cat = c("aland", paste0(ring, "land"), "Chad", "chile", "Zambia"),
                  stringsAsFactors = FALSE)
  old <- Sys.getlocale("LC_COLLATE")
  on.exit(suppressWarnings(Sys.setlocale("LC_COLLATE", old)), add = TRUE)
  got <- function(lc) {
    if (identical(suppressWarnings(Sys.setlocale("LC_COLLATE", lc)), "")) return(NULL)
    ct <- suppressWarnings(suppressMessages(
      countryatlas:::classification_table(d, "cat", "categorical", 5, NULL)))
    if (is.null(ct)) NULL else ct$class
  }
  a <- got("C"); z <- got("en_US.UTF-8")
  skip_if(is.null(a) || is.null(z), "needs both C and en_US.UTF-8 collation")
  expect_equal(a, z)
})

test_that("the global G is NA with a reason, never a silent NaN", {
  snap <- countryatlas::world_snapshot$countries
  W <- suppressWarnings(country_weights("knn", k = 4))
  d <- snap[match(rownames(as.matrix(W)), snap$iso3c), c("iso3c", "gdp_per_capita")]
  d <- d[!is.na(d$gdp_per_capita), ]
  M <- as.matrix(W)[d$iso3c, d$iso3c]
  rs <- rowSums(M); M <- M / ifelse(rs == 0, 1, rs)
  wc <- suppressWarnings(country_weights("custom", w = M))
  g <- function(x) {
    z <- d; z$gdp_per_capita <- x
    suppressWarnings(getis_ord(z, gdp_per_capita, weights = wc, local = FALSE))$g
  }

  # A well-behaved column is unaffected.
  ok <- g(d$gdp_per_capita)
  expect_true(is.finite(ok))

  # The bug: 0/0 for an all-zero column, and Inf - Inf (or an underflow to 0)
  # at extreme magnitudes -- all three came back as a bare NaN in `g`.
  for (x in list(rep(0, nrow(d)),
                 d$gdp_per_capita * 1e290,
                 d$gdp_per_capita * 1e-290)) {
    got <- g(x)
    expect_true(is.na(got))
    expect_false(is.nan(got))
  }
  # g() suppresses warnings so it can report the value; assert on the warning
  # through an unsuppressed call.
  raw <- function(x) {
    z <- d; z$gdp_per_capita <- x
    getis_ord(z, gdp_per_capita, weights = wc, local = FALSE)
  }
  expect_warning(raw(rep(0, nrow(d))), "Every value is zero")
  expect_warning(raw(d$gdp_per_capita * 1e290), "not finite at this magnitude")

  # The remedy the overflow message gives has to be true: the statistic is
  # unchanged by a positive scale factor.
  expect_equal(g(d$gdp_per_capita * 1e6), ok)
  expect_equal(g(d$gdp_per_capita / 1000), ok)
})

test_that("permutation p-values are bounded and reproducible", {
  snap <- countryatlas::world_snapshot$countries
  W <- suppressWarnings(country_weights("knn", k = 4))
  d <- snap[match(rownames(as.matrix(W)), snap$iso3c), c("iso3c", "gdp_per_capita")]
  d <- d[!is.na(d$gdp_per_capita), ]
  M <- as.matrix(W)[d$iso3c, d$iso3c]
  rs <- rowSums(M); M <- M / ifelse(rs == 0, 1, rs)
  wc <- suppressWarnings(country_weights("custom", w = M))
  np <- 49
  lo <- 1 / (np + 1)

  set.seed(1); a <- suppressWarnings(morans_i(d, gdp_per_capita, weights = wc, n_perm = np))
  set.seed(1); b <- suppressWarnings(morans_i(d, gdp_per_capita, weights = wc, n_perm = np))
  expect_identical(a$p_value, b$p_value)

  # The documented floor: (1 + r)/(n + 1) can never be 0, and never exceed 1.
  gc_ <- suppressWarnings(gearys_c(d, gdp_per_capita, weights = wc, n_perm = np))
  lm_ <- suppressWarnings(local_morans(d, gdp_per_capita, weights = wc, n_perm = np))
  for (p in list(a$p_value, gc_$p_value, lm_$p_value)) {
    expect_true(all(p >= lo))
    expect_true(all(p <= 1))
  }

  # The documented tails: this column is positively autocorrelated, so Moran's
  # I sits above its expectation and Geary's C below 1 -- opposite directions,
  # both significant.
  expect_gt(a$i, a$expected)
  expect_lt(gc_$c, 1)
  expect_lt(a$p_value, 0.05)
  expect_lt(gc_$p_value, 0.05)

  # n_perm = 0 leaves p NA, and then nothing may be called significant.
  z <- suppressWarnings(local_morans(d, gdp_per_capita, weights = wc, n_perm = 0))
  expect_true(all(is.na(z$p_value)))
  expect_true(all(z$cluster == "Not significant"))
})

test_that("repair_country_names() reports exactly what it changed", {
  # The documented guarantees, as opposed to the one that was withdrawn: a name
  # that already matches is untouched, and every substitution is reported both
  # in the message and in the "repairs" attribute.
  good <- c("France", "Germany", "Italy", "Chad")
  # as.character(): the result carries its documented "repairs" attribute, so
  # comparing against a bare vector would fail on attributes alone.
  expect_equal(as.character(suppressMessages(repair_country_names(good))), good)
  expect_equal(nrow(attr(suppressMessages(repair_country_names(good)), "repairs")), 0L)

  # "Germny" is one edit, so both the Jaro-Winkler and the fallback metric
  # repair it. "Frnace" is a transposition -- two edits, 0.33 of six characters
  # -- which the fallback deliberately rejects at the default threshold, so a
  # test built on it passes here and fails under _R_CHECK_DEPENDS_ONLY_.
  mixed <- c("Germny", "Germany", "Chad")
  out <- suppressMessages(repair_country_names(mixed))
  rep <- attr(out, "repairs")
  expect_equal(length(out), length(mixed))
  # Only the misspelling moved, and the report accounts for every change.
  changed <- which(out != mixed)
  expect_equal(sort(mixed[changed]), sort(rep$from))
  expect_equal(sort(out[changed]), sort(rep$to))
  expect_equal(out[mixed == "Germany"], "Germany")
  expect_equal(out[mixed == "Chad"], "Chad")

  # verbose controls the message but not the result.
  expect_message(repair_country_names(mixed), "Repaired")
  expect_silent(repair_country_names(mixed, verbose = FALSE))
  expect_equal(repair_country_names(mixed, verbose = FALSE), out)

  # The transposition case, both ways round: it depends on the metric, so it is
  # asserted only where stringdist decides the answer.
  if (requireNamespace("stringdist", quietly = TRUE)) {
    expect_equal(as.character(suppressMessages(repair_country_names("Frnace"))), "France")
  } else {
    expect_equal(as.character(suppressMessages(repair_country_names("Frnace"))), "Frnace")
  }

  # A name it cannot place is left alone rather than forced onto something.
  odd <- suppressMessages(repair_country_names("Qwertyuiop"))
  expect_equal(as.character(odd), "Qwertyuiop")
})

test_that("a misbehaving custom source is reported as the source's fault", {
  env <- countryatlas:::the_sources
  on.exit(suppressWarnings(rm(list = intersect("zz_probe", ls(env)), envir = env)),
          add = TRUE)
  reg <- function(f) suppressWarnings(suppressMessages(
    register_country_source("zz_probe", f, cache = FALSE)))
  go <- function() fetch_indicator("zz_probe", "gdp", countries = "FRA")

  # A well-behaved adapter is unaffected.
  reg(function(indicator, countries, years) data.frame(iso3c = "FRA", gdp = 1))
  expect_equal(suppressWarnings(suppressMessages(go()))$gdp, 1)

  # The bug: the adapter's own error came back bare, naming no source. The
  # provider's message is preserved verbatim, braces and all -- a cli template
  # would have tried to interpolate them.
  reg(function(indicator, countries, years) stop("provider is down {oops}"))
  err <- tryCatch(go(), error = function(e) e)
  expect_s3_class(err, "countryatlas_error")
  expect_match(conditionMessage(err), "zz_probe")
  expect_match(conditionMessage(err), "provider is down {oops}", fixed = TRUE)

  # The bug: a wrong signature surfaced R's "unused arguments".
  reg(function(indicator) data.frame(iso3c = "FRA", gdp = 1))
  err2 <- tryCatch(go(), error = function(e) e)
  expect_s3_class(err2, "countryatlas_error")
  expect_match(conditionMessage(err2), "does not take the arguments")
  expect_match(conditionMessage(err2), "indicator")

  # The return-value checks that already worked must keep working.
  for (bad in list(NULL, c(1, 2, 3), matrix(1:4, 2), list(a = 1))) {
    reg(function(indicator, countries, years) bad)
    e <- tryCatch(go(), error = function(x) x)
    expect_s3_class(e, "countryatlas_error")
    expect_match(conditionMessage(e), "not a data frame")
  }
  reg(function(indicator, countries, years) data.frame(country = "FRA", gdp = 1))
  expect_error(go(), "no iso3c column", class = "countryatlas_error")

  # A duplicate key is reported by add_indicator(), as the contract promises.
  reg(function(indicator, countries, years)
    data.frame(iso3c = c("FRA", "FRA", "DEU"), gdp = c(1, 2, 3)))
  expect_warning(
    add_indicator(data.frame(iso3c = c("FRA", "DEU"), v = 1:2), "zz_probe", "gdp"),
    "duplicate key")
})

test_that("max_gap is measured in years, not rows", {
  fill <- function(yr, v, max_gap = 3, method = "linear") {
    d <- data.frame(iso3c = rep("FRA", length(yr)), year = yr, value = v,
                    stringsAsFactors = FALSE)
    r <- suppressWarnings(suppressMessages(
      interpolate_missing(d, "value", max_gap = max_gap, method = method)))
    sum(is.na(d$value) & !is.na(r$value))
  }
  # Annual panels are unchanged: the span between the bracketing observations
  # equals the number of missing rows exactly.
  expect_equal(fill(2000:2004, c(1, 2, NA, 4, 5)), 1L)
  expect_equal(fill(2000:2005, c(1, NA, NA, NA, 5, 6)), 3L)   # exactly max_gap
  expect_equal(fill(2000:2006, c(1, NA, NA, NA, NA, 6, 7)), 0L)

  # The bug: one missing *row* spanning a decade passed a max_gap of 3, so the
  # default invented a value ten years from either anchor.
  expect_equal(fill(c(2000, 2010, 2020), c(1, NA, 3)), 0L)
  expect_equal(fill(c(2000, 2005, 2010, 2015, 2020), c(1, NA, NA, 4, 5)), 0L)
  # But a filled point close to an anchor is fine even when the *other* anchor
  # is distant: 2001 sits one year from 2000, so it fills. Measuring the
  # bracketing span instead would wrongly refuse this.
  expect_equal(fill(c(2000, 2001, 2020), c(1, NA, 3)), 1L)
  expect_equal(fill(c(2000, 2019, 2020), c(1, NA, 3)), 1L)
  # Raising max_gap to cover the span makes it explicit and allowed again.
  expect_equal(fill(c(2000, 2010, 2020), c(1, NA, 3), max_gap = 20), 1L)
  # An irregular gap genuinely within max_gap still fills.
  expect_equal(fill(c(2000, 2002, 2003), c(1, NA, 3)), 1L)
  # Same for locf, and character years get the year measure too.
  expect_equal(fill(c(2000, 2010, 2020), c(1, NA, 3), method = "locf"), 0L)
  expect_equal(fill(as.character(c(2000, 2010, 2020)), c(1, NA, 3)), 0L)
  expect_equal(fill(as.character(2000:2004), c(1, 2, NA, 4, 5)), 1L)
})

test_that("linear interpolation refuses a year it cannot read", {
  lab <- data.frame(iso3c = rep("FRA", 3), year = c("early", "mid", "late"),
                    value = c(1, NA, 3), stringsAsFactors = FALSE)
  # The bug: approx() got NA and its message surfaced through dplyr's across().
  expect_error(interpolate_missing(lab, "value", method = "linear"),
               "readable as a number", class = "countryatlas_error")
  expect_error(interpolate_missing(lab, "value", method = "linear"), "early")
  # locf needs no arithmetic, so it must keep working.
  expect_equal(sum(!is.na(suppressWarnings(suppressMessages(
    interpolate_missing(lab, "value", method = "locf"))$value)), na.rm = TRUE), 3L)

  # Coercibility, not is.numeric(): a character year still works, which is what
  # approx() has always accepted.
  chr <- data.frame(iso3c = rep("FRA", 5), year = as.character(2000:2004),
                    value = c(1, 2, NA, 4, 5), stringsAsFactors = FALSE)
  expect_no_error(interpolate_missing(chr, "value", method = "linear"))
  expect_no_error(interpolate_missing(chr, "value", method = "locf"))
})

# dplyr::arrange() and order() on a factor sort by LEVEL INDEX, not the label,
# and approx() coerces a factor x to level indices too. A year column arrives
# as a factor more often than it looks (read.csv(stringsAsFactors = TRUE), some
# importers, any deliberate factor(year) for plotting), and every verb that
# reads a *neighbouring* row then read the wrong neighbour -- silently.
test_that("a factor or character year gives the same answers as a numeric one", {
  base <- data.frame(
    iso3c = rep(c("FRA", "DEU"), each = 4), year = rep(2000:2003, 2),
    value = c(10, 20, 40, 80, 5, 10, 20, 40), stringsAsFactors = FALSE)
  # Levels deliberately out of chronological order: sorting by level index
  # would give 2003, 2001, 2000, 2002.
  as_factor_year <- function(d) {
    d$year <- factor(as.character(d$year),
                     levels = c("2003", "2001", "2000", "2002"))
    d
  }
  as_chr_year <- function(d) { d$year <- as.character(d$year); d }
  gapped <- base
  gapped$value[3] <- NA

  for (mk in list(as_factor_year, as_chr_year)) {
    expect_equal(lag_by_country(mk(base), "value")$value_lag,
                 lag_by_country(base, "value")$value_lag)
    expect_equal(diff_by_country(mk(base), "value")$value_diff,
                 diff_by_country(base, "value")$value_diff)
    expect_equal(growth_rate(mk(base), "value")$value_growth,
                 growth_rate(base, "value")$value_growth)
    # The gap must actually be filled, not left NA by interpolating against
    # level indices and falling outside approx()'s anchors.
    got <- interpolate_missing(mk(gapped), "value")$value
    expect_equal(got, interpolate_missing(gapped, "value")$value)
    expect_false(anyNA(got))
  }
})

test_that("year_sort_key leaves a genuinely non-numeric period label alone", {
  expect_identical(countryatlas:::year_sort_key(1:3), 1:3)
  expect_identical(countryatlas:::year_sort_key(c("2000", "2001")), c(2000, 2001))
  expect_identical(countryatlas:::year_sort_key(factor(c("2001", "2000"))),
                   c(2001, 2000))
  # Not numbers at all: handed back untouched, so it still sorts by whatever
  # order its own type defines rather than collapsing to NA.
  lab <- factor(c("pre-war", "post-war"), levels = c("pre-war", "post-war"))
  expect_identical(countryatlas:::year_sort_key(lab), lab)
  d <- as.Date(c("2000-01-01", "2001-01-01"))
  expect_identical(countryatlas:::year_sort_key(d), d)
})

test_that("the irregular-year warning reads a factor year by label, not level", {
  mk <- function(years, fac) {
    d <- data.frame(iso3c = rep("FRA", length(years)), year = years,
                    value = seq_along(years), stringsAsFactors = FALSE)
    if (fac) {
      # Levels reversed, so level index and year disagree.
      d$year <- factor(as.character(d$year),
                       levels = rev(as.character(sort(unique(years)))))
    }
    d
  }
  irregular <- function(d) {
    hit <- FALSE
    withCallingHandlers(
      suppressMessages(lag_by_country(d, "value")),
      warning = function(w) {
        if (inherits(w, "countryatlas_irregular_years")) hit <<- TRUE
        invokeRestart("muffleWarning")
      })
    hit
  }
  # as.numeric() on a factor returns level indices, which made a regular annual
  # panel look irregular and vice versa.
  expect_false(irregular(mk(2000:2004, FALSE)))
  expect_false(irregular(mk(2000:2004, TRUE)))
  expect_true(irregular(mk(c(2000, 2001, 2010), FALSE)))
  expect_true(irregular(mk(c(2000, 2001, 2010), TRUE)))
})

# Indexing a NAMED vector with a factor selects by the factor's integer codes,
# not its labels. audit_time_coverage() looked up historical_codes that way, so
# a frame from read.csv(stringsAsFactors = TRUE) matched whichever rows happened
# to sit at those positions -- from the one verb whose job is catching exactly
# that kind of mistake. The year key had already been hardened (read_year());
# the iso3c key had not.
test_that("audit_time_coverage does not invent history for a factor iso3c", {
  iso <- c("FRA", "DEU", "ITA", "ESP")
  d <- data.frame(iso3c = rep(iso, each = 2), year = rep(2000:2001, 4),
                  value = 1:8, stringsAsFactors = FALSE)
  fac <- d
  # Levels reversed, so each code's integer position points at another country.
  fac$iso3c <- factor(fac$iso3c, levels = rev(iso))

  chr_out <- audit_time_coverage(d)
  fac_out <- audit_time_coverage(fac)
  # None of these four countries dissolved or post-dates its predecessor.
  expect_equal(nrow(chr_out), 0L)
  expect_equal(nrow(fac_out), 0L)

  # And where there IS something to report, both agree. SUN carries data after
  # it dissolved; RUS carries data before it existed.
  hist <- data.frame(
    iso3c = c("SUN", "RUS"), year = c(1995L, 1985L), value = 1:2,
    stringsAsFactors = FALSE)
  hist_fac <- hist
  hist_fac$iso3c <- factor(hist_fac$iso3c, levels = c("RUS", "SUN"))
  a <- audit_time_coverage(hist)
  b <- audit_time_coverage(hist_fac)
  expect_equal(as.data.frame(a), as.data.frame(b))
  expect_true(nrow(a) > 0)
  expect_setequal(a$issue, c("after_dissolution", "before_existence"))
})

test_that("a factor iso3c gives the same answers as a character one", {
  iso <- c("FRA", "DEU", "ITA", "ESP")
  d <- data.frame(iso3c = rep(iso, each = 3), year = rep(2000:2002, 4),
                  value = c(100, 104, 108, 10, 13, 17, 50, 56, 63, 200, 205, 210),
                  stringsAsFactors = FALSE)
  fac <- d
  fac$iso3c <- factor(fac$iso3c, levels = rev(iso))
  flat <- function(x) {
    x <- as.data.frame(x)
    x$iso3c <- as.character(x$iso3c)
    x[order(x$iso3c, x$year), setdiff(names(x), character(0))]
  }
  expect_equal(flat(lag_by_country(fac, "value")), flat(lag_by_country(d, "value")),
               ignore_attr = TRUE)
  expect_equal(flat(growth_rate(fac, "value")), flat(growth_rate(d, "value")),
               ignore_attr = TRUE)
  expect_equal(flat(index_to(fac, "value", base_year = 2000)),
               flat(index_to(d, "value", base_year = 2000)), ignore_attr = TRUE)
  expect_equal(sigma_convergence(fac, "value")$sigma,
               sigma_convergence(d, "value")$sigma)
})

# dplyr::group_by() puts every NA in ONE group, so a panel carrying two rows
# whose iso3c did not resolve was treated as one country -- and these verbs read
# a neighbouring row within the group.
test_that("verbs do not read across two unidentified countries", {
  d <- data.frame(iso3c = c("FRA", "FRA", NA, NA),
                  year = c(2000, 2001, 2000, 2001),
                  value = c(10, 20, 100, 999), stringsAsFactors = FALSE)
  na_of <- function(out, col) out[[col]][is.na(out$iso3c)]

  # 999 - 100 = 899 between two unrelated rows was reported as a real change.
  expect_true(all(is.na(na_of(lag_by_country(d, "value"), "value_lag"))))
  expect_true(all(is.na(na_of(diff_by_country(d, "value"), "value_diff"))))
  expect_true(all(is.na(na_of(growth_rate(d, "value"), "value_growth"))))
  # The identified rows are untouched.
  out <- lag_by_country(d, "value")
  expect_equal(out$value_lag[!is.na(out$iso3c) & out$year == 2001], 10)

  # interpolate_missing() must not fill a gap from another unknown country.
  gap <- data.frame(iso3c = c(NA, NA, NA), year = 2000:2002,
                    value = c(10, NA, 30), stringsAsFactors = FALSE)
  expect_true(is.na(interpolate_missing(gap, "value")$value[2]))
  # And no internal key leaks into the result.
  expect_false(".wdj_unit" %in% names(interpolate_missing(gap, "value")))
  expect_false(".wdj_unit" %in% names(lag_by_country(d, "value")))
})

test_that("a row identified by country instead of iso3c still groups as one series", {
  # An appended aggregate row -- no iso3c, but `country` names it -- is a
  # deliberate series and must keep behaving like one.
  d <- data.frame(
    iso3c = c("FRA", "FRA", NA, NA),
    country = c("France", "France", "World", "World"),
    year = c(2000, 2001, 2000, 2001),
    value = c(10, 20, 100, 999), stringsAsFactors = FALSE)
  out <- lag_by_country(d, "value")
  expect_equal(out$value_lag[out$country == "World" & out$year == 2001], 100)
  expect_true(is.na(out$value_lag[out$country == "World" & out$year == 2000]))

  # Two *different* unmatched names must stay apart.
  d2 <- d
  d2$country <- c("France", "France", "Atlantis", "Ruritania")
  out2 <- lag_by_country(d2, "value")
  expect_true(all(is.na(out2$value_lag[is.na(out2$iso3c)])))
})

test_that("complete_years does not copy one unidentified country's geometry to another", {
  skip_if_not_installed("sf")
  sq <- function(x) sf::st_polygon(list(cbind(c(x, x + 1, x + 1, x, x),
                                              c(0, 0, 1, 1, 0))))
  # Two rows nothing identifies, with different shapes. The geometry carry
  # matched on iso3c, and match() treats NA as equal to NA, so the invented
  # rows took whichever unresolved row happened to have a shape.
  d <- sf::st_sf(iso3c = c(NA_character_, NA_character_), year = c(2000, 2002),
                 value = c(1, 2), geometry = sf::st_sfc(sq(0), sq(10)))
  out <- complete_years(d, years = 2000:2002)
  # Each unresolved row is its own unit: its own grid, carrying its own shape.
  wkt <- sf::st_as_text(sf::st_geometry(out))
  expect_equal(length(unique(wkt)), 2L)
  expect_equal(sum(sf::st_is_empty(sf::st_geometry(out))), 0L)
  expect_equal(nrow(out), 6L)

  # A real panel is unaffected: each country keeps its own shape across the
  # years invented for it.
  d2 <- sf::st_sf(iso3c = c("FRA", "FRA", "DEU"), year = c(2000, 2002, 2000),
                  value = c(1, 2, 3), geometry = sf::st_sfc(sq(0), sq(0), sq(10)))
  o2 <- complete_years(d2, years = 2000:2002)
  expect_true(inherits(o2, "sf"))
  expect_equal(sum(sf::st_is_empty(sf::st_geometry(o2))), 0L)
  fr <- sf::st_as_text(sf::st_geometry(o2[o2$iso3c == "FRA", ]))
  de <- sf::st_as_text(sf::st_geometry(o2[o2$iso3c == "DEU", ]))
  expect_equal(length(unique(fr)), 1L)
  expect_equal(length(unique(de)), 1L)
  expect_false(identical(unique(fr), unique(de)))
  expect_false(".wdj_unit" %in% names(o2))
})

# `""` is not NA, so every is.na() guard missed it -- but read.csv() without
# na.strings = "" gives a blank for every empty cell, and standardize_country("")
# already resolves to iso3c = NA. A blank code identifies no country.
test_that("a blank iso3c is treated as unidentified, not as a country", {
  for (blank in c("", " ", "   ", "\t")) {
    d <- data.frame(iso3c = c("FRA", "FRA", blank, blank),
                    year = c(2000, 2001, 2000, 2001),
                    value = c(10, 20, 100, 999), stringsAsFactors = FALSE)
    out <- diff_by_country(d, "value")
    # 999 - 100 = 899 between two unrelated blank-coded rows.
    expect_true(all(is.na(out$value_diff[out$iso3c == blank])),
                info = paste0("blank = ", encodeString(blank)))
    # The identified rows are untouched.
    expect_equal(out$value_diff[out$iso3c == "FRA" & out$year == 2001], 10)
  }

  # A blank code that `country` does identify is still one series.
  d2 <- data.frame(iso3c = c("", "", ""), country = rep("World", 3),
                   year = 2000:2002, value = c(1, 2, 3), stringsAsFactors = FALSE)
  expect_equal(lag_by_country(d2, "value")$value_lag, c(NA, 1, 2))
})

test_that("blank_key treats missing, empty and whitespace-only alike", {
  bk <- countryatlas:::blank_key
  expect_equal(bk(c("FRA", NA, "", " ", "\t", "\n", "  x  ")),
               c(FALSE, TRUE, TRUE, TRUE, TRUE, TRUE, FALSE))
  # Unicode spaces too: trimws()'s default class is ASCII-only, which is why
  # standardize_country() uses [\h\v] as well.
  expect_true(bk(intToUtf8(0x00A0)))   # no-break space
  expect_true(bk(intToUtf8(0x2003)))   # em space
  expect_false(bk("0"))                # a real, if odd, code
})

test_that("the internal unit key never reaches the caller", {
  d <- data.frame(iso3c = rep(c("FRA", "DEU", "ITA", "ESP"), each = 3),
                  year = rep(2000:2002, 4),
                  value = c(100, 104, 108, 10, 13, 17, 50, 56, 63, 200, 205, 210),
                  defl = rep(c(100, 102, 104), 4), stringsAsFactors = FALSE)
  gapped <- d
  gapped$value[2] <- NA
  outs <- list(
    lag_by_country(d, "value"), diff_by_country(d, "value"),
    growth_rate(d, "value"), index_to(d, "value", base_year = 2000),
    interpolate_missing(gapped, "value"), complete_years(d[-2, ], years = 2000:2002),
    beta_convergence(d, "value"),
    deflate(d, "value", deflator = defl, base_year = 2000))
  for (o in outs) expect_false(".wdj_unit" %in% names(o))

  # And a caller who happens to have a column of that name does not lose it to
  # a verb that never grouped by unit.
  mine <- d[d$year == 2000, ]
  mine$.wdj_unit <- "mine"
  expect_true(".wdj_unit" %in% names(share_of_world(mine, "value")))
  expect_equal(share_of_world(mine, "value")$.wdj_unit, rep("mine", 4))
})

# The panel guards have to judge the panel on the same key the verb groups by.
# Keying them on iso3c while the verb grouped by unit meant blank-coded rows
# were reported as duplicates of each other, and as one country with gaps.
test_that("the panel guards key on the unit, not on iso3c alone", {
  warns <- function(d) {
    seen <- character(0)
    withCallingHandlers(
      suppressMessages(lag_by_country(d, "value")),
      warning = function(w) { seen <<- c(seen, class(w)[1]); invokeRestart("muffleWarning") })
    unique(seen)
  }
  mk <- function(iso, yr) data.frame(iso3c = iso, year = yr,
                                     value = seq_along(iso), stringsAsFactors = FALSE)

  # Four single-year unidentified rows are four units with no gaps at all.
  expect_length(warns(mk(c("FRA", "FRA", "", "", "", ""),
                         c(2000, 2001, 2000, 2005, 2010, 2015))), 0)
  # Two unidentified rows in one year are different countries, not a duplicate.
  expect_length(warns(mk(c("FRA", "FRA", "", ""), c(2000, 2001, 2000, 2000))), 0)

  # Both guards must still fire on the real thing.
  expect_true(length(warns(mk(c("FRA", "FRA", "FRA"), c(2000, 2001, 2001)))) > 0)
  expect_true("countryatlas_irregular_years" %in%
                warns(mk(c("FRA", "FRA", "FRA"), c(2000, 2001, 2010))))
})

# subnational_map()'s body past validation needs a GISCO download, so none of
# it ran in an offline check -- covr put R/subnational.R at 66% while every
# other file was above 90%. Mocked here so the join logic is actually exercised.
test_that("subnational_map joins on nuts_id whatever the caller's column is called", {
  skip_if_not_installed("sf")
  skip_if_not_installed("ggplot2")
  sq <- function(x) sf::st_polygon(list(cbind(c(x, x+1, x+1, x, x), c(0, 0, 1, 1, 0))))
  fake <- sf::st_sf(
    nuts_id = c("DE-BY", "FR-ARA", "IT-LOM"), iso3c = c("DEU", "FRA", "ITA"),
    name = c("Bayern", "Auvergne", "Lombardia"), level = c(2L, 2L, 2L),
    geometry = sf::st_sfc(sq(0), sq(2), sq(4)), crs = 4326)
  local_mocked_bindings(nuts_geometry = function(...) fake)
  fills <- function(p) ggplot2::ggplot_build(p)$data[[1]]$fill

  ref <- fills(subnational_map(
    data.frame(nuts_id = c("DE-BY","FR-ARA","IT-LOM"), value = c(10, 20, 30),
               stringsAsFactors = FALSE), value))
  # `by` is documented as "the code column in `data`". The guard used to be
  # `if (!by %in% names(geom))`, which is false exactly when the caller's
  # column collides with one of the geometry's own -- so `by = "name"` joined
  # NUTS codes against region names and matched nothing.
  got <- fills(subnational_map(
    data.frame(name = c("DE-BY","FR-ARA","IT-LOM"), value = c(10, 20, 30),
               stringsAsFactors = FALSE), value, by = "name"))
  expect_equal(got, ref)
  expect_equal(length(unique(ref)), 3L)

  # A code that does not exist is reported and dropped, not silently lost.
  expect_warning(subnational_map(
    data.frame(nuts_id = c("DE-BY","XX-ZZ"), value = c(1, 2),
               stringsAsFactors = FALSE), value), class = "countryatlas_warning")
  # Nothing matching at all is still an error.
  expect_error(suppressWarnings(subnational_map(
    data.frame(nuts_id = c("XX-ZZ","YY-QQ"), value = c(1, 2),
               stringsAsFactors = FALSE), value)), class = "countryatlas_error")
})

test_that("subnational_map draws an all-NA indicator instead of blaming the codes", {
  skip_if_not_installed("sf")
  skip_if_not_installed("ggplot2")
  sq <- function(x) sf::st_polygon(list(cbind(c(x, x+1, x+1, x, x), c(0, 0, 1, 1, 0))))
  fake <- sf::st_sf(nuts_id = c("DE-BY", "FR-ARA"), iso3c = c("DEU", "FRA"),
                    name = c("Bayern", "Auvergne"), level = c(2L, 2L),
                    geometry = sf::st_sfc(sq(0), sq(2)), crs = 4326)
  local_mocked_bindings(nuts_geometry = function(...) fake)
  # The match count was sum(!is.na(fill)), so a genuinely all-NA indicator --
  # which this package draws with an na.value and reports in the caption -- was
  # reported as "no rows matched the geometry", sending the reader to check
  # NUTS vintages for a mismatch that never happened.
  d <- data.frame(nuts_id = c("DE-BY", "FR-ARA"), value = c(NA_real_, NA_real_),
                  stringsAsFactors = FALSE)
  expect_no_error(p <- subnational_map(d, value))
  cols <- ggplot2::ggplot_build(p)$data[[1]]$fill
  expect_equal(length(unique(cols)), 1L)
})

# attach_geometry(year = ) had no coverage at all -- the whole historical branch
# was dark -- and its match warning was keyed on how much of the geometry the
# caller had asked for rather than on the geometry itself.
test_that("the historical join reports unreachable entities, not the caller's frame size", {
  skip_if_not_installed("cshapes")
  skip_if_not_installed("sf")
  d3 <- data.frame(iso3c = c("FRA", "DEU", "ITA"), value = c(1, 2, 3),
                   stringsAsFactors = FALSE)
  d1 <- data.frame(iso3c = "FRA", value = 1, stringsAsFactors = FALSE)

  count_of <- function(d, year) {
    msg <- NULL
    withCallingHandlers(
      suppressMessages(attach_geometry(d, year = year)),
      warning = function(w) {
        if (inherits(w, "countryatlas_unreachable_entities")) msg <<- conditionMessage(w)
        invokeRestart("muffleWarning")
      })
    msg
  }
  # The number reported must not depend on how many countries were supplied:
  # the old threshold (matched < nrow(geom) * 0.5) said "only 3 of 97 matched"
  # for a perfectly ordinary three-country frame.
  expect_identical(count_of(d3, 1960), count_of(d1, 1960))
  expect_match(count_of(d3, 1960), "no iso3c", fixed = TRUE)
  # And it is a property of the year's geometry, so different years differ.
  expect_false(identical(count_of(d3, 1960), count_of(d3, 2019)))

  # Nothing matching at all is reported separately, by the same helper every
  # other geometry verb uses.
  classes <- character(0)
  withCallingHandlers(
    suppressMessages(attach_geometry(
      data.frame(iso3c = c("ZZZ", "YYY"), value = c(1, 2), stringsAsFactors = FALSE),
      year = 1960)),
    warning = function(w) { classes <<- c(classes, class(w)[1]); invokeRestart("muffleWarning") })
  expect_true("countryatlas_unreachable_entities" %in% classes)
  expect_true(length(classes) > 1)

  # The branch's own guards.
  expect_error(attach_geometry(data.frame(x = 1, value = 1), year = 1960),
               class = "countryatlas_error")
  expect_error(attach_geometry(
    data.frame(iso2c = c("FR", "DE"), value = c(1, 2), stringsAsFactors = FALSE),
    year = 1960, by = "iso2c"), class = "countryatlas_error")
  expect_error(attach_geometry(d3, year = 2030), class = "countryatlas_error")
  # The modern path raises none of this.
  expect_silent(suppressMessages(attach_geometry(d3, geometry = "polygon")))
})
