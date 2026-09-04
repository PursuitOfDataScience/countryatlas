# Closed-form anchors for the hand-rolled numerical kernels. Structural tests
# ("is it a tibble", "is beta negative") pass even if a formula is wrong, so
# each of these pins a value against an analytic result or an independent
# implementation rather than against itself.

R_EARTH <- 6371.0088   # the constant haversine_km() / ring_area_km2() share

test_that("haversine_km matches known great-circle distances", {
  hv <- countryatlas:::haversine_km
  # Quarter of a great circle and a full half-circle are exact.
  expect_equal(hv(0, 0, 90, 0), R_EARTH * pi / 2)
  expect_equal(hv(0, -90, 0, 90), R_EARTH * pi)
  expect_equal(hv(10, 20, 10, 20), 0)
  # Published airport-to-airport great-circle distances, 0.5% tolerance.
  expect_equal(hv(-118.4085, 33.9425, -73.7789, 40.6397), 3974,
               tolerance = 0.005)                      # LAX -> JFK
  expect_equal(hv(-0.4543, 51.4700, 151.1772, -33.9399), 17016,
               tolerance = 0.005)                      # LHR -> SYD
})

test_that("ring_area_km2 matches the analytic spherical-rectangle area", {
  ra <- countryatlas:::ring_area_km2
  # A lon/lat rectangle has area R^2 * dlon * (sin lat2 - sin lat1).
  analytic <- function(lon1, lon2, lat1, lat2) {
    R_EARTH^2 * (lon2 - lon1) * pi / 180 *
      (sin(lat2 * pi / 180) - sin(lat1 * pi / 180))
  }
  ring <- function(lon1, lon2, lat1, lat2, k = 200) {
    lons <- seq(lon1, lon2, length.out = k)
    lats <- seq(lat1, lat2, length.out = k)
    list(lon = c(lons, rep(lon2, k), rev(lons), rep(lon1, k)),
         lat = c(rep(lat1, k), lats, rep(lat2, k), rev(lats)))
  }
  for (p in list(c(0, 10, 0, 10), c(-20, 20, 30, 60), c(100, 110, -40, -20))) {
    g <- ring(p[1], p[2], p[3], p[4])
    expect_equal(ra(g$lon, g$lat), analytic(p[1], p[2], p[3], p[4]),
                 tolerance = 1e-6)
  }
  # A degenerate ring has no area rather than erroring.
  expect_equal(ra(c(1, 2), c(1, 2)), 0)
  expect_equal(ra(numeric(0), numeric(0)), 0)
})

test_that("great_circle traces a true great circle, not a straight line", {
  gc <- countryatlas:::great_circle
  hv <- countryatlas:::haversine_km
  g <- gc(0, 0, 90, 0, n = 3)
  expect_equal(g$lon, c(0, 45, 90))       # equatorial arc is exact
  expect_equal(g$lat, c(0, 0, 0))
  # A northern-hemisphere arc bows poleward of both endpoints (the whole point
  # of drawing great circles rather than segments).
  g2 <- gc(-100, 40, 20, 50, n = 101)
  expect_gt(max(g2$lat), 50)
  # Summing the interpolated legs reproduces the direct great-circle distance.
  legs <- sum(hv(utils::head(g2$lon, -1), utils::head(g2$lat, -1),
                 utils::tail(g2$lon, -1), utils::tail(g2$lat, -1)))
  expect_equal(legs, hv(-100, 40, 20, 50), tolerance = 1e-6)
  # Coincident endpoints must not divide by sin(0).
  expect_equal(gc(5, 5, 5, 5, n = 4)$lon, rep(5, 4))
})

test_that("gini and theil match their closed forms", {
  # Gini of 1..n is exactly (n - 1) / (3n).
  expect_equal(gini(1:100), 99 / 300)
  expect_equal(gini(1:7), 6 / 21)
  expect_equal(gini(c(0, 1)), 0.5)
  x <- c(1, 2, 4, 8)
  expect_equal(theil(x), mean((x / mean(x)) * log(x / mean(x))))
  # Both indices are scale-invariant: a currency change must not move them.
  expect_equal(gini(x * 1e6), gini(x))
  expect_equal(theil(x * 1e6), theil(x))
})

test_that("sigma_convergence matches sd(log(x)) and the coefficient of variation", {
  v <- c(1, 10, 100)
  df <- data.frame(iso3c = c("A", "B", "C"), year = 2000L, g = v)
  expect_equal(sigma_convergence(df, g)$sigma, stats::sd(log(v)))
  expect_equal(sigma_convergence(df, g, measure = "cv")$sigma,
               stats::sd(v) / mean(v))
})

test_that("beta_convergence recovers a planted beta exactly when noiseless", {
  set.seed(11)
  start <- runif(60, 6, 11)
  true_beta <- -0.004
  span <- 20
  growth <- 0.05 + true_beta * start
  panel <- data.frame(
    iso3c = rep(sprintf("C%02d", 1:60), each = 2),
    year  = rep(c(2000L, 2000L + span), 60),
    gdp   = as.vector(rbind(exp(start), exp(start + growth * span)))
  )
  out <- beta_convergence(panel, gdp)
  expect_equal(out$beta, true_beta)
  expect_equal(out$r_squared, 1)
  # beta = -(1 - exp(-lambda * T)) / T  =>  lambda = -log(1 + beta * T) / T
  expect_equal(out$speed, -log(1 + true_beta * span) / span)
  expect_equal(out$half_life, log(2) / out$speed)
})

test_that("correlate_indicators reproduces stats::cor on complete pairs", {
  d <- data.frame(a = c(1, 2, 3, 4, NA), b = c(2, 4, 6, 9, 1),
                  cc = c(5, 3, 2, 1, 7))
  ci <- correlate_indicators(d)
  hit <- ci$var_x == "a" & ci$var_y == "b"
  expect_equal(ci$r[hit], stats::cor(c(1, 2, 3, 4), c(2, 4, 6, 9)))
  expect_equal(ci$n[hit], 4L)
})

test_that("deflate and to_ppp rescale by the right factor, not just at unity", {
  # The existing identity test uses a deflator equal to the base year and a
  # PPP factor of one. Both are degenerate: they hold whatever the rescaling
  # formula is, so they cannot catch an inverted ratio. (The same trap caught
  # a first draft of the Marshall anchor below, where modest counts sent every
  # case down the full-shrinkage branch.)
  d <- data.frame(iso3c = "FRA", year = 2000:2002,
                  v = c(100, 250, 160), defl = c(100, 125, 80))

  got <- deflate(d, v, base_year = 2000, deflator = defl)
  # real = nominal * deflator[base] / deflator
  expect_equal(got$v_real, d$v * d$defl[d$year == 2000] / d$defl)
  # Read economically: 250 at index 125 and 160 at index 80 are the same real
  # quantity, and an inverted ratio would give 312.5 and 128 instead.
  expect_equal(got$v_real, c(100, 200, 200))

  # Rebasing moves the level and leaves the ratios alone.
  reb <- deflate(d, v, base_year = 2001, deflator = defl)
  expect_equal(reb$v_real, c(125, 250, 250))
  expect_equal(reb$v_real / reb$v_real[1], got$v_real / got$v_real[1])

  # to_ppp divides by the factor; two countries on different factors that meet
  # at the same converted level is the case worth pinning.
  p <- data.frame(iso3c = c("FRA", "DEU"), year = 2000L,
                  v = c(100, 200), f = c(2, 4))
  expect_equal(to_ppp(p, v, factor = f)$v_ppp, c(50, 50))
})

test_that("interpolate_missing puts filled values on the right line", {
  # The existing tests pin the flags, the warnings and the validation -- not
  # the numbers. A wrong interpolation would keep every one of them passing.
  d <- data.frame(iso3c = "FRA", year = 2000:2004,
                  v = c(100, NA, NA, NA, 140))
  lin <- interpolate_missing(d, "v", method = "linear")
  expect_equal(lin$v, c(100, 110, 120, 130, 140))
  expect_equal(lin$v_imputed, c(FALSE, TRUE, TRUE, TRUE, FALSE))

  # Carry-forward holds the last observation, it does not average.
  expect_equal(interpolate_missing(d, "v", method = "locf")$v,
               c(100, 100, 100, 100, 140))
  # "none" leaves the column exactly as it arrived.
  expect_equal(interpolate_missing(d, "v", method = "none")$v, d$v)

  # The one that matters on real panels: the line follows the *year*, not the
  # row. With 2000, 2001, 2005 and 0 .. 100, the 2001 value is a fifth of the
  # way (20). Interpolating on row position -- which looks identical on an
  # evenly spaced panel, i.e. on most test fixtures -- would give 50.
  uneven <- data.frame(iso3c = "FRA", year = c(2000, 2001, 2005),
                       v = c(0, NA, 100))
  expect_equal(interpolate_missing(uneven, "v", method = "linear")$v,
               c(0, 20, 100))

  # It interpolates; it does not extrapolate. A gap outside the observed range
  # has no two points to sit between, so it stays NA.
  ends <- data.frame(iso3c = "FRA", year = 2000:2003, v = c(NA, 10, 20, NA))
  got <- interpolate_missing(ends, "v", method = "linear")
  expect_true(is.na(got$v[1]))
  expect_true(is.na(got$v[4]))
  expect_equal(got$v[2:3], c(10, 20))
})

test_that("empirical-Bayes shrinkage matches Marshall's published estimator", {
  # Anchored for the same reason as the log-t below: the existing tests check
  # that shrinkage *behaves* like shrinkage (small denominators move, large
  # ones do not), which a wrong constant would still satisfy.
  #
  # Marshall (1991) method of moments: with r_i = y_i / d_i,
  #   rbar = sum(y)/sum(d),  dbar = mean(d),
  #   s2   = sum(d (r - rbar)^2) / sum(d),   phi = s2 - rbar/dbar,
  #   w_i  = phi / (phi + rbar/d_i),
  #   rhat = w r + (1 - w) rbar
  # and phi <= 0 (no more spread than Poisson noise alone) means full
  # shrinkage to the global rate.
  marshall <- function(y, d) {
    r <- y / d
    rbar <- sum(y) / sum(d)
    s2 <- sum(d * (r - rbar)^2) / sum(d)
    phi <- s2 - rbar / mean(d)
    w <- if (is.finite(phi) && phi > 0) phi / (phi + rbar / d) else rep(0, length(r))
    list(rate = r, smoothed = w * r + (1 - w) * rbar, w = w, phi = phi,
         rbar = rbar)
  }

  # Genuine between-area variation with large denominators, so phi > 0 and the
  # branch that actually shrinks is the one under test. (Getting this wrong is
  # easy: modest counts give phi < 0 and every value collapses to the global
  # rate, which would "pass" without exercising the formula at all.)
  pop <- c(500, 800, 1200, 2000, 3000, 5000, 700, 1500, 2500, 4000, 6000, 9000)
  rate <- c(0.01, 0.02, 0.03, 0.04, 0.05, 0.06, 0.07, 0.08, 0.09, 0.10,
            0.02, 0.09)
  d <- data.frame(iso3c = paste0("C", seq_along(pop)), year = 2000L,
                  cases = round(pop * rate), pop = pop)
  ref <- marshall(d$cases, d$pop)
  expect_gt(ref$phi, 0)

  got <- smooth_rates(d, cases, pop)
  expect_equal(got$cases_rate, ref$rate)
  expect_equal(got$cases_smoothed, ref$smoothed, tolerance = 1e-12)
  expect_equal(got$cases_shrinkage, ref$w, tolerance = 1e-12)

  # The estimator's point: a small denominator is pulled toward the global
  # rate, a large one is left where it is.
  expect_gt(abs(got$cases_smoothed[1] - got$cases_rate[1]),
            abs(got$cases_smoothed[12] - got$cases_rate[12]))
  # ...and every smoothed value lies between its own rate and the global one.
  between <- (got$cases_smoothed - got$cases_rate) *
    (got$cases_smoothed - ref$rbar)
  expect_true(all(between <= 1e-12))

  # phi <= 0: no evidence of real variation, so shrink all the way.
  flat <- data.frame(iso3c = paste0("C", 1:6), year = 2000L,
                     cases = rep(10, 6), pop = rep(100, 6))
  fref <- marshall(flat$cases, flat$pop)
  expect_lte(fref$phi, 0)
  fgot <- smooth_rates(flat, cases, pop)
  expect_equal(fgot$cases_shrinkage, rep(0, 6))
  expect_equal(unique(fgot$cases_smoothed), fref$rbar)
})

test_that("the log-t statistic matches Phillips & Sul's published formula", {
  # Every other statistic here is anchored numerically -- gini and theil on
  # their closed forms, morans_i on an independently built W, beta_convergence
  # on a planted beta. The log-t is the most intricate of them and had only
  # behavioural tests ("separates what should separate"), so a refactor could
  # change the number without changing which clubs come out.
  #
  # Phillips & Sul (2007): with h_it = y_it / mean_i(y_it) and
  # H_t = mean_i (h_it - 1)^2, regress
  #   log(H_1 / H_t) - 2 log(log t)  on  log t,   t = [rT] .. T
  # and take the one-sided t statistic on log t. Written out here from the
  # formula rather than from the implementation.
  ps_logt <- function(y, r = 0.3) {
    tn <- ncol(y)
    h <- t(apply(y, 1, function(row) row / colMeans(y)))
    ht <- apply((h - 1)^2, 2, mean)
    idx <- max(2L, floor(r * tn)):tn
    lhs <- log(ht[1] / ht[idx]) - 2 * log(log(idx))
    summary(stats::lm(lhs ~ log(idx)))$coefficients[2, 3]
  }
  mk <- function(paths) {
    y <- do.call(rbind, paths)
    rownames(y) <- paste0("C", seq_len(nrow(y)))
    y
  }
  tn <- 24L
  tt <- seq_len(tn)
  # Spreads collapsing toward a common level, spreads compounding apart, and a
  # constant spread (which is *not* convergence).
  converging <- mk(lapply(1:8, function(i) 100 + (i - 4.5) * 20 * exp(-0.25 * tt)))
  diverging <- mk(lapply(1:8, function(i) 100 * (1 + (i - 4.5) * 0.02)^tt))
  flat <- mk(lapply(1:8, function(i) rep(100 + i, tn)))

  for (y in list(converging, diverging, flat)) {
    expect_equal(countryatlas:::log_t_stat(y), ps_logt(y), tolerance = 1e-9)
  }
  # And the sign is the decision the procedure actually makes, against the
  # -1.645 critical value the docs name.
  expect_gt(countryatlas:::log_t_stat(converging), -1.645)
  expect_lt(countryatlas:::log_t_stat(diverging), -1.645)
  expect_lt(countryatlas:::log_t_stat(flat), -1.645)

  # log(log(t)) is singular at t = 1, so the window must never start there.
  expect_gte(max(2L, floor(0.3 * tn)), 2L)
  expect_true(is.finite(countryatlas:::log_t_stat(converging)))
  # Too few periods is NA rather than a number from a 2-point regression.
  expect_true(is.na(countryatlas:::log_t_stat(converging[, 1:4, drop = FALSE])))
  expect_true(is.na(countryatlas:::log_t_stat(converging[1, , drop = FALSE])))
})

test_that("morans_i matches an independently built row-standardised statistic", {
  skip_if_no_sf_geometry()
  snap <- countryatlas::world_snapshot$countries
  got <- morans_i(snap, gdp_per_capita, n_perm = 0)

  # Rebuild the statistic from scratch: adjacency -> binary W -> row-standardise
  # -> I = (n / S0) * sum_ij w_ij z_i z_j / sum_i z_i^2.
  b <- country_borders()
  df <- dplyr::distinct(snap, iso3c, .keep_all = TRUE)
  df <- df[!is.na(df$iso3c) & is.finite(df$gdp_per_capita), ]
  b <- b[b$iso3c_a %in% df$iso3c & b$iso3c_b %in% df$iso3c, ]
  iso <- sort(unique(c(b$iso3c_a, b$iso3c_b)))
  n <- length(iso)
  W <- matrix(0, n, n, dimnames = list(iso, iso))
  for (k in seq_len(nrow(b))) {
    W[b$iso3c_a[k], b$iso3c_b[k]] <- 1
    W[b$iso3c_b[k], b$iso3c_a[k]] <- 1
  }
  W <- W / rowSums(W)
  z <- df$gdp_per_capita[match(iso, df$iso3c)]
  z <- z - mean(z)
  ref <- (n / sum(W)) *
    sum(vapply(seq_len(n), function(i) sum(W[i, ] * z[i] * z), numeric(1))) /
    sum(z^2)

  expect_equal(got$i, ref)
  expect_equal(got$n, n)
  expect_equal(got$n_links, nrow(b))
  expect_equal(got$expected, -1 / (n - 1))
})

test_that("quantile breaks are computed per country, not per polygon vertex", {
  # This is the 2.0.0 fix that forced the major version bump: the polygon
  # backend repeats a country's value once per boundary point, so breaking on
  # the raw column weights each country by its geometric complexity and a
  # "quantile" map stops holding roughly equal countries per colour.
  skip_if_not_installed("maps")
  snap <- countryatlas::world_snapshot$countries
  mapdf <- attach_geometry(snap, geometry = "polygon")
  vals <- mapdf$gdp_per_capita
  per_country <- dplyr::distinct(tibble::as_tibble(mapdf), .data$iso3c,
                                 .keep_all = TRUE)$gdp_per_capita

  right <- countryatlas:::compute_breaks(per_country, "quantile", 5)
  naive <- countryatlas:::compute_breaks(vals, "quantile", 5)
  # The two genuinely differ, so the test can tell them apart.
  expect_false(isTRUE(all.equal(right, naive)))

  # The helper must de-duplicate on the key, never break on the raw column.
  got <- countryatlas:::apply_binned_fill(
    mapdf, rlang::quo(gdp_per_capita), "gdp_per_capita", "quantile", 5)
  expect_equal(levels(got$data$.wdj_bin),
               levels(cut(vals, breaks = right, include.lowest = TRUE,
                          dig.lab = 4)))
  expect_false(identical(levels(got$data$.wdj_bin),
                         levels(cut(vals, breaks = naive, include.lowest = TRUE,
                                    dig.lab = 4))))

  # The property that matters: roughly equal COUNTRIES per colour.
  one_per <- dplyr::distinct(tibble::as_tibble(got$data), .data$iso3c,
                             .keep_all = TRUE)
  counts <- table(one_per$.wdj_bin[!is.na(one_per$.wdj_bin)])
  expect_length(counts, 5L)
  expect_lt(max(counts) / min(counts), 1.5)
})

test_that("world_map wires the de-duplication flag to the right backend", {
  # Catches the flag being flipped at the call site, not just inside the helper.
  skip_if_not_installed("maps")
  snap <- countryatlas::world_snapshot$countries
  mapdf <- attach_geometry(snap, geometry = "polygon")
  per_country <- dplyr::distinct(tibble::as_tibble(mapdf), .data$iso3c,
                                 .keep_all = TRUE)$gdp_per_capita
  right <- countryatlas:::compute_breaks(per_country, "quantile", 5)

  built <- ggplot2::ggplot_build(
    world_map(mapdf, gdp_per_capita, style = "quantile", n_bins = 5))
  # The legend keys are the bin levels the plot actually used.
  used <- levels(droplevels(factor(built$plot$data$.wdj_bin)))
  expected <- levels(cut(mapdf$gdp_per_capita, breaks = right,
                         include.lowest = TRUE, dig.lab = 4))
  expect_true(all(used %in% expected))
  expect_gt(length(used), 1L)
})

test_that("the sf backend de-duplicates divided countries before breaking", {
  # An sf frame is NOT exactly one row per country: Cyprus occupies two rows
  # sharing one iso3c at 110m (Cyprus and India at 50m). Breaking on the raw
  # column double-counted them, which moved real countries into the wrong bin.
  skip_if_no_sf_geometry()
  snap <- countryatlas::world_snapshot$countries
  sfd <- attach_geometry(snap, geometry = "sf")
  expect_gt(nrow(sfd), dplyr::n_distinct(sfd$iso3c))   # duplicates really exist
  vals <- sfd$gdp_per_capita
  per_country <- dplyr::distinct(tibble::as_tibble(sfd), .data$iso3c,
                                 .keep_all = TRUE)$gdp_per_capita
  right <- countryatlas:::compute_breaks(per_country, "quantile", 5)
  naive <- countryatlas:::compute_breaks(vals, "quantile", 5)
  expect_false(isTRUE(all.equal(right, naive)))        # and they matter
  got <- countryatlas:::apply_binned_fill(
    sfd, rlang::quo(gdp_per_capita), "gdp_per_capita", "quantile", 5)
  expect_equal(levels(got$data$.wdj_bin),
               levels(cut(vals, breaks = right, include.lowest = TRUE,
                          dig.lab = 4)))
})

test_that("globe_map's polygon backend also de-duplicates before breaking", {
  # globe_map attaches polygon geometry internally, so it needs the same
  # per-country de-duplication world_map does -- and it passes the flag
  # separately, so it needs its own check.
  skip_if_not_installed("maps")
  skip_if_not_installed("mapproj")
  snap <- countryatlas::world_snapshot$countries
  # Reproduce the frame globe_map builds internally.
  poly <- attach_geometry(
    dplyr::distinct(tibble::as_tibble(snap), .data$iso3c, .keep_all = TRUE),
    geometry = "polygon")
  per_country <- dplyr::distinct(tibble::as_tibble(poly), .data$iso3c,
                                 .keep_all = TRUE)$gdp_per_capita
  right <- countryatlas:::compute_breaks(per_country, "quantile", 5)
  naive <- countryatlas:::compute_breaks(poly$gdp_per_capita, "quantile", 5)
  expect_false(isTRUE(all.equal(right, naive)))

  built <- ggplot2::ggplot_build(
    globe_map(snap, gdp_per_capita, backend = "polygon", style = "quantile",
              n_bins = 5))
  used <- levels(built$plot$data$.wdj_bin)
  expect_equal(used, levels(cut(poly$gdp_per_capita, breaks = right,
                                include.lowest = TRUE, dig.lab = 4)))
  expect_false(identical(used, levels(cut(poly$gdp_per_capita, breaks = naive,
                                          include.lowest = TRUE, dig.lab = 4))))
})

# gini() computed the weighted mean absolute difference with outer(), i.e. an
# n-by-n matrix. That is fine for the ~200 countries it is written for, but the
# function is exported and takes any numeric vector: a geometry-joined column is
# 99,338 rows, needing ~79 GB, and the R process was killed outright -- no error,
# no message. It now uses the sorted cumulative form, O(n log n) time and O(n)
# memory, which agrees with the pairwise version to floating-point noise.

# Provenance for the figures below: cross-checked against independent
# implementations, not just derived by hand. gini() agrees with
# DescTools::Gini(unbiased = FALSE) to 1.7e-16 over 200 random trials, weighted
# and unweighted -- which matters because the weighted kernel was rewritten from
# the O(n^2) pairwise form. haversine_km() agrees with
# geosphere::distHaversine(r = 6371.0088) to 1.5e-15 relative over 500 random
# pairs. Neither package is a dependency, so those comparisons are not run here.

test_that("gini still matches its analytic references exactly", {
  expect_identical(gini(c(1, 1, 1, 1)), 0)
  expect_equal(gini(c(0, 0, 0, 1)), 0.75)
  expect_equal(gini(as.numeric(1:4)), 0.25)          # population Gini of 1..4
  expect_equal(gini(c(1, 2)), 1 / 6)
  expect_equal(gini(c(1, 9), weights = c(9, 1)), 0.4)
  # Weighting must still change the answer, and in the documented direction.
  snap <- countryatlas::world_snapshot$countries
  between_countries <- gini(snap$gdp_per_capita)
  between_people <- gini(snap$gdp_per_capita, weights = snap$population)
  expect_false(isTRUE(all.equal(between_countries, between_people)))
})

test_that("gini agrees with the pairwise definition it replaced", {
  pairwise <- function(x, w = rep(1, length(x))) {
    sw <- sum(w)
    mu <- sum(w * x) / sw
    sum(outer(w, w) * abs(outer(x, x, "-"))) / (2 * sw^2 * mu)
  }
  set.seed(7)
  for (i in 1:40) {
    n <- sample(2:60, 1)
    x <- runif(n, 0, 10^sample(0:5, 1))
    w <- if (i %% 2 == 0) rep(1, n) else runif(n, 0.01, 10)
    expect_equal(gini(x, weights = w), pairwise(x, w), tolerance = 1e-12)
  }
  # Ties, and a single repeated value, are where a sorted form could go wrong.
  expect_equal(gini(c(5, 5, 5, 9)), pairwise(c(5, 5, 5, 9)), tolerance = 1e-12)
  expect_equal(gini(rep(3, 10)), pairwise(rep(3, 10)), tolerance = 1e-12)
})

test_that("gini handles a vector far larger than the country scale", {
  # The size that used to kill the session. Keep it well under a second.
  set.seed(11)
  x <- runif(2e5, 1, 1000)
  t <- system.time(g <- gini(x))[["elapsed"]]
  expect_true(is.finite(g))
  expect_gt(g, 0)
  expect_lt(g, 1)
  expect_lt(t, 5)
  # And weighted, at the same size.
  expect_true(is.finite(gini(x, weights = runif(2e5, 0.1, 5))))
})

# RNG discipline. morans_i() is the only function here that draws random
# numbers, and ?morans_i tells the caller to set a seed for a reproducible
# p_value. A package that called set.seed() itself would silently destroy the
# caller's stream, so assert that too -- nothing else guards it.

test_that("the package never reseeds the caller's RNG", {
  ns <- asNamespace("countryatlas")
  fns <- Filter(is.function, mget(ls(ns, all.names = TRUE), envir = ns,
                                  ifnotfound = list(NULL)))
  src <- vapply(fns, function(f) paste(deparse(f), collapse = " "), character(1))
  expect_equal(unname(grep("set\\.seed", src, value = TRUE)), character(0))
  expect_equal(unname(grep("RNGkind", src, value = TRUE)), character(0))
})

test_that("morans_i is reproducible under a seed and leaves i deterministic", {
  skip_if_no_sf_geometry()
  snap <- countryatlas::world_snapshot$countries
  set.seed(42); a <- morans_i(snap, gdp_per_capita, n_perm = 99)
  set.seed(42); b <- morans_i(snap, gdp_per_capita, n_perm = 99)
  expect_identical(a, b)
  # The statistic itself does not depend on the seed; only the p-value does.
  set.seed(7); d <- morans_i(snap, gdp_per_capita, n_perm = 99)
  expect_equal(a$i, d$i)
  expect_equal(a$expected, d$expected)
  # On a column with no spatial structure the seed genuinely moves the p-value.
  set.seed(99); snap$noise <- runif(nrow(snap))
  ps <- vapply(1:5, function(s) {
    set.seed(s); morans_i(snap, noise, n_perm = 99)$p_value
  }, numeric(1))
  expect_gt(length(unique(ps)), 1L)
  expect_true(all(ps > 0 & ps <= 1))
})

test_that("n_perm = 0 does not consume the caller's random stream", {
  skip_if_no_sf_geometry()
  snap <- countryatlas::world_snapshot$countries
  set.seed(1)
  before <- .Random.seed
  invisible(morans_i(snap, gdp_per_capita, n_perm = 0))
  expect_identical(.Random.seed, before)
  # A clean draw afterwards must match one taken without calling us at all.
  set.seed(7); x1 <- runif(1)
  set.seed(7); invisible(morans_i(snap, gdp_per_capita, n_perm = 0))
  expect_identical(runif(1), x1)
  # Whereas a real permutation run does advance it.
  set.seed(1)
  invisible(morans_i(snap, gdp_per_capita, n_perm = 9))
  expect_false(identical(.Random.seed, before))
})

test_that("the permutation p-value respects its own floor", {
  skip_if_no_sf_geometry()
  snap <- countryatlas::world_snapshot$countries
  # p = (exceedances + 1) / (n_perm + 1), so it can never be 0 and never below
  # 1/(n_perm + 1).
  for (np in c(9, 99, 199)) {
    set.seed(1)
    p <- morans_i(snap, gdp_per_capita, n_perm = np)$p_value
    expect_gte(p, 1 / (np + 1))
    expect_lte(p, 1)
  }
  # GDP per capita is strongly autocorrelated, so it should sit at the floor --
  # which is why a different seed does not move it, and why a seed-sensitivity
  # test must not use this column.
  set.seed(5)
  expect_equal(morans_i(snap, gdp_per_capita, n_perm = 199)$p_value, 1 / 200)
})

# theil had no numeric anchor on the bundled data, where gini did. Both values
# were verified bit-identical across R 4.4.1/4.6.0 and dplyr 1.1.4/1.2.1, so
# they are safe to pin: a change here means the kernel moved, not the platform.

test_that("theil is anchored on the bundled snapshot", {
  snap <- countryatlas::world_snapshot$countries
  x <- snap$gdp_per_capita
  expect_equal(theil(x), 0.740384576223, tolerance = 1e-9)
  expect_equal(theil(x, weights = snap$population), 0.677915582736,
               tolerance = 1e-9)
  # Weighting between people rather than between countries lowers it here.
  expect_lt(theil(x, weights = snap$population), theil(x))
})

test_that("the theil decomposition adds up, over the grouped subset", {
  snap <- countryatlas::world_snapshot$countries
  x <- snap$gdp_per_capita
  g <- snap$region
  d <- theil(x, groups = g)
  expect_named(d, c("component", "value", "share"))
  between <- d$value[d$component == "between"]
  within <- d$value[d$component == "within"]
  total <- d$value[d$component == "total"]
  # The defining property: the two parts sum exactly to the whole.
  expect_equal(between + within, total)
  expect_equal(sum(d$share[d$component %in% c("between", "within")]), 1)
  # And the documented subtlety: a row with no group is dropped, so `total` is
  # theil over the grouped subset -- not over everything. Puerto Rico has no
  # region in the snapshot, which is the entire difference.
  expect_equal(total, theil(x[!is.na(g)]))
  expect_false(isTRUE(all.equal(total, theil(x))))
  expect_equal(sum(is.na(g)), 1L)
})

test_that("Moran's I matches the standard statistic's properties", {
  # ?morans_i says no spdep is needed because "at ~200 countries the dense
  # arithmetic is trivial". These are the properties that make that claim
  # checkable without spdep, which is not a dependency.
  skip_if_no_sf_geometry()
  snap <- countryatlas::world_snapshot$countries
  r <- morans_i(snap, gdp_per_capita, n_perm = 0)

  # For row-standardised weights the expectation under no autocorrelation is
  # exactly -1/(n-1). A bug in building or normalising the weight matrix shows
  # up here.
  expect_equal(r$expected, -1 / (r$n - 1))
  expect_gt(r$n, 100L)
  expect_gt(r$n_links, r$n)                  # more links than countries
  # I is bounded in practice well inside [-1, 1] for row-standardised weights.
  expect_gt(r$i, -1)
  expect_lt(r$i, 1)
  # GDP per capita is strongly, positively autocorrelated across land borders.
  expect_gt(r$i, 0.3)

  # The permutation distribution must centre on that same expectation.
  set.seed(11)
  p <- morans_i(snap, gdp_per_capita, n_perm = 199)
  expect_equal(p$i, r$i)                     # the statistic is unchanged by it
  expect_equal(p$expected, r$expected)
  expect_gte(p$p_value, 1 / 200)
})

test_that("every reversible convert_country destination round-trips", {
  # The package is a code-translation tool, so this is its core invariant: for
  # each destination that countrycode can also read *back*, iso3c -> dest ->
  # iso3c must be the identity wherever both steps resolve.
  iso <- countryatlas::country_meta$iso3c
  reversible <- c("iso2c", "iso3n", "country.name", "cown", "cowc", "p4n",
                  "p5n", "gwn", "vdem", "imf", "fao", "fips", "gaul", "wb", "un")
  for (d in reversible) {
    fwd <- suppressWarnings(convert_country(iso, to = d, from = "iso3c",
                                           warn = FALSE))
    back <- suppressWarnings(convert_country(fwd, to = "iso3c", from = d,
                                            warn = FALSE))
    keep <- !is.na(fwd) & !is.na(back)
    expect_gt(sum(keep), 150L)                       # the scheme really resolved
    expect_identical(back[keep], iso[keep], info = d)
  }
})

test_that("the verbs do not depend on input row order", {
  # Anything that sorts, ranks, groups or builds a weight matrix internally can
  # pick up an order dependency without any test noticing.
  snap <- countryatlas::world_snapshot$countries
  set.seed(7)
  sh <- snap[sample(nrow(snap)), ]
  by_iso <- function(d) as.data.frame(d)[order(as.data.frame(d)$iso3c), ]

  expect_equal(as.data.frame(aggregate_regions(snap, population, by = "continent")),
               as.data.frame(aggregate_regions(sh, population, by = "continent")))
  expect_equal(by_iso(rank_countries(snap, gdp_per_capita))$rank,
               by_iso(rank_countries(sh, gdp_per_capita))$rank)
  expect_equal(as.data.frame(correlate_indicators(snap)),
               as.data.frame(correlate_indicators(sh)))
  expect_equal(gini(snap$gdp_per_capita), gini(sh$gdp_per_capita))
  expect_equal(as.data.frame(theil(snap$gdp_per_capita, groups = snap$continent)),
               as.data.frame(theil(sh$gdp_per_capita, groups = sh$continent)))
  expect_equal(by_iso(share_of_world(snap, population))$population_share,
               by_iso(share_of_world(sh, population))$population_share)

  pan <- tibble::tibble(iso3c = rep(c("USA", "FRA", "CHN", "IND"), each = 4),
                        year = rep(2000:2003, 4),
                        v = c(1, 2, 3, 4, 10, 20, 30, 40,
                              100, 150, 200, 260, 5, 6, 7, 9))
  set.seed(3)
  span <- pan[sample(nrow(pan)), ]
  expect_equal(beta_convergence(pan, v)$beta, beta_convergence(span, v)$beta)
  expect_equal(as.data.frame(sigma_convergence(pan, v)),
               as.data.frame(sigma_convergence(span, v)))
  ord <- function(d) as.data.frame(d)[order(d$iso3c, d$year), ]
  expect_equal(ord(growth_rate(pan, v)), ord(growth_rate(span, v)),
               ignore_attr = TRUE)
  expect_equal(ord(complete_years(pan)), ord(complete_years(span)),
               ignore_attr = TRUE)

  skip_if_no_sf_geometry()
  sfd <- attach_geometry(snap, geometry = "sf")
  set.seed(9)
  shs <- sfd[sample(nrow(sfd)), ]
  # Moran's I builds a neighbour matrix from row positions -- the one place an
  # order dependency would be genuinely easy to introduce.
  expect_equal(morans_i(sfd, gdp_per_capita, n_perm = 0)$i,
               morans_i(shs, gdp_per_capita, n_perm = 0)$i)
  fills <- function(d) {
    table(ggplot2::ggplot_build(
      world_map(d, gdp_per_capita, style = "quantile"))$data[[1]]$fill)
  }
  expect_equal(sort(fills(sfd)), sort(fills(shs)))
})

test_that("attach_geometry refuses a frame that already has geometry", {
  # Re-attaching joins a one-row-per-vertex frame back onto the vertex table by
  # country, which is N-squared: the bundled snapshot went from 99,338 rows to
  # 310,977,360. The join sets relationship = "many-to-many" -- correct, one
  # country has many vertices -- so dplyr's guard against this is switched off.
  skip_if_not_installed("maps")
  snap <- countryatlas::world_snapshot$countries
  poly <- attach_geometry(snap, geometry = "polygon")
  expect_error(attach_geometry(poly, geometry = "polygon"),
               "already has map geometry", class = "countryatlas_error")
  expect_error(attach_geometry(poly, geometry = "sf"), "already has map geometry")
  # Reducing to country level and dropping the positional columns is the way out,
  # and is what the internal call sites do.
  reduced <- countryatlas:::drop_map_geometry(
    dplyr::distinct(poly, .data$iso3c, .keep_all = TRUE))
  expect_false(any(c("long", "lat", "group", "order") %in% names(reduced)))
  # globe_map(backend = "polygon") needs mapproj as well as maps.
  if (requireNamespace("mapproj", quietly = TRUE)) {
    expect_silent(globe_map(poly, gdp_per_capita, backend = "polygon"))
  }

  skip_if_no_sf_geometry()
  sfd <- attach_geometry(snap, geometry = "sf")
  expect_error(attach_geometry(sfd, geometry = "sf"), "already has map geometry")
  expect_s3_class(attach_geometry(reduced, geometry = "sf"), "sf")
})

# --- algebraic invariants -----------------------------------------------------
#
# The anchors above pin single values. These pin *relationships*, which is what
# catches a normalisation or off-by-one slip: a wrong divisor can still match a
# hand-computed anchor for one input while breaking the identity for every
# other one. None of these properties was pinned before.

test_that("share_of_world shares are a proper distribution", {
  d <- data.frame(iso3c = rep(c("USA", "FRA", "JPN", "BRA"), each = 2),
                  year = rep(2019:2020, 4), v = c(10, 20, 30, 40, 50, 60, 70, 80))
  s <- share_of_world(d, v)
  # Shares are of the world total *within* each year, so each year sums to one.
  per_year <- tapply(s$v_share, s$year, sum)
  expect_equal(as.numeric(per_year), rep(1, length(per_year)))
  expect_true(all(s$v_share >= 0 & s$v_share <= 1))
})

test_that("per_capita and the rate helpers satisfy their identities", {
  d <- data.frame(iso3c = c("USA", "FRA"), year = 2020L, v = c(250, 400),
                  pop = c(1e6, 5e5), defl = c(100, 100), f = c(1, 1))
  pc <- per_capita(d, v, pop = pop)
  # Dividing then multiplying back must land on the original value.
  expect_equal(pc$v_per_capita * pc$pop, pc$v)
  # A deflator equal to the base year, and a PPP factor of one, are identities.
  expect_equal(deflate(d, v, base_year = 2020, deflator = defl)$v_real, d$v)
  expect_equal(to_ppp(d, v, factor = f)$v_ppp, d$v)
})

test_that("rank_countries returns a genuine ranking", {
  d <- data.frame(iso3c = c("USA", "FRA", "JPN", "BRA"), v = c(30, 10, 40, 20))
  r <- rank_countries(d, v)
  expect_identical(sort(r$rank), seq_len(nrow(r)))
  expect_equal(r$v[which.min(r$rank)], max(d$v))   # rank 1 is the largest
  expect_true(all(r$percentile >= 0 & r$percentile <= 1))
  expect_equal(mean(r$z_score), 0)
})

test_that("index_to is exactly `to` at the base year", {
  d <- data.frame(iso3c = rep(c("USA", "FRA"), each = 3),
                  year = rep(2018:2020, 2), v = c(50, 60, 70, 80, 90, 100))
  it <- index_to(d, v, 2018, to = 100)
  expect_equal(it$v_index[it$year == 2018], c(100, 100))
  it7 <- index_to(d, v, 2019, to = 7)
  expect_equal(it7$v_index[it7$year == 2019], c(7, 7))
})

test_that("compounding growth_rate reconstructs the series", {
  d <- data.frame(iso3c = "USA", year = 2017:2020, v = c(100, 110, 121, 133.1))
  g <- growth_rate(d, v)
  g <- g[order(g$year), ]
  # Each rate is the step from the previous year, so the cumulative product of
  # (1 + rate) must walk the original series back out.
  expect_equal(g$v[1] * cumprod(c(1, 1 + g$v_growth[-1])), g$v)
})

test_that("gini and theil hit their analytic bounds and are scale free", {
  expect_equal(gini(rep(5, 10)), 0)
  expect_equal(theil(rep(5, 10)), 0)
  # One holder of everything is the maximum for a population of n.
  expect_equal(gini(c(rep(0, 9), 1)), 9 / 10)
  # Both indices are relative, so multiplying every value leaves them alone.
  x <- c(3, 7, 11, 29, 101)
  expect_equal(gini(x), gini(x * 1000))
  expect_equal(theil(x), theil(x * 1000))
})

test_that("the spatial statistics satisfy their algebraic identities", {
  skip_if_no_sf_geometry()
  snap <- countryatlas::world_snapshot$countries
  d <- snap[!is.na(snap$gdp_per_capita), c("iso3c", "gdp_per_capita")]
  w <- suppressWarnings(country_weights("knn", countries = d$iso3c, k = 5))

  mi <- suppressWarnings(morans_i(d, gdp_per_capita, weights = w, n_perm = 0))
  gc <- suppressWarnings(gearys_c(d, gdp_per_capita, weights = w, n_perm = 0))
  lm <- suppressWarnings(local_morans(d, gdp_per_capita, weights = w,
                                      n_perm = 0))

  # Expectations under the null of no spatial association.
  expect_equal(mi$expected, -1 / (mi$n - 1))
  expect_equal(gc$expected, 1)

  # Anselin (1995): with row-standardised weights the local statistics average
  # to the global one. This is the check that keeps the two implementations
  # from drifting apart -- each could match a reference on its own and still
  # disagree with the other.
  expect_equal(mean(lm$ii, na.rm = TRUE), mi$i, tolerance = 1e-8)

  # Moran's I is built from standardised deviations, so an affine rescaling of
  # the values must leave it alone.
  d2 <- d
  d2$gdp_per_capita <- d$gdp_per_capita * 1000 + 7
  expect_equal(suppressWarnings(morans_i(d2, gdp_per_capita, weights = w,
                                         n_perm = 0))$i, mi$i)

  # A constant field has no variance to explain: the statistic is undefined and
  # the spatial lag is the constant itself.
  dc <- d
  dc$gdp_per_capita <- 5
  expect_true(is.na(suppressWarnings(morans_i(dc, gdp_per_capita, weights = w,
                                              n_perm = 0))$i))
  # The lag of a constant is that constant wherever a neighbour exists. It is
  # NA where the weights cannot place a country -- no centroid under knn, no
  # land border under the contiguity default, which by documentation excludes
  # every island -- and that is a coverage fact, not an arithmetic failure. The
  # comparison needs a tolerance too: row-standardised weights sum to one only
  # to floating point, so the lag is 5 but not bit-exactly 5.
  for (wts in list(w, NULL)) {
    sl <- suppressWarnings(spatial_lag(dc, gdp_per_capita, weights = wts))
    got <- sl$gdp_per_capita_lag[!is.na(sl$gdp_per_capita_lag)]
    expect_gt(length(got), 0L)
    expect_equal(got, rep(5, length(got)))
  }
})

test_that("getis_ord z-scores are shift invariant, and stay finite for a tight column", {
  # Gi* standardises by the spread, so adding a constant to every value cannot
  # change a z-score. The old code computed the spread as
  # sqrt(sum(x^2)/n - mean(x)^2), which subtracts two nearly equal large
  # numbers, so this invariant broke exactly when the shift was large: 1e9 + 1:5
  # drove the spread to 0 and every z_score to Inf with p_value 0 -- "every
  # country is a significant hotspot" -- while 1e12 + (10:50) went negative
  # under the sqrt and returned NaN. Centring first is stable, so this pins the
  # property rather than any particular number.
  skip_if_no_sf_geometry()
  iso <- c("FRA", "DEU", "ITA", "ESP", "BEL", "NLD", "AUT", "CHE")
  w <- country_weights("knn", k = 3, countries = iso)
  base <- c(45000, 52000, 38000, 41000, 60000, 33000, 47000, 71000)
  mk <- function(v) data.frame(iso3c = iso, v = v, stringsAsFactors = FALSE)
  ref <- getis_ord(mk(base), v, weights = w)

  # The invariant, over shifts spanning the range where the old form failed.
  for (shift in c(0, 1e3, 1e6, 1e9, 1e12)) {
    got <- getis_ord(mk(base + shift), v, weights = w)
    expect_equal(got$z_score, ref$z_score, tolerance = 1e-6)
  }
  # Scaling is likewise absorbed by the standardisation.
  expect_equal(getis_ord(mk(base * 1000), v, weights = w)$z_score,
               ref$z_score, tolerance = 1e-6)

  # A column clustered tightly around a large value: finite, and not the
  # degenerate answer. These are the three shapes that used to fail.
  for (v0 in list(1e9 + seq_along(iso), 1e10 + seq_along(iso),
                  1e12 + 10 * seq_along(iso))) {
    got <- getis_ord(mk(v0), v, weights = w)
    expect_false(any(is.nan(got$z_score)))
    expect_false(any(is.infinite(got$z_score)))
    expect_true(all(is.finite(got$z_score)))
    # An evenly spaced column is not all-hotspot: p-values must not collapse.
    expect_false(all(got$p_value < 0.05))
  }
  # An evenly spaced ramp has the same shape whatever the offset, so the
  # z-scores agree with each other too.
  z9 <- getis_ord(mk(1e9 + seq_along(iso)), v, weights = w)$z_score
  z12 <- getis_ord(mk(1e12 + 1e3 * seq_along(iso)), v, weights = w)$z_score
  expect_equal(z9, z12, tolerance = 1e-6)

  # A genuinely constant column still takes the documented NA path, with the
  # warning -- that guard is about zero variance, not about conditioning.
  expect_warning(flat <- getis_ord(mk(rep(5, length(iso))), v, weights = w),
                 class = "countryatlas_zero_variance")
  expect_true(all(is.na(flat$z_score)))
})
