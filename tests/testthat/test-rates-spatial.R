# Rates in space, inequality, and the funnel (S2, S3, S5, S6, S8).

rate_fixture <- function(seed = 3) {
  set.seed(seed)
  d <- snap[!is.na(snap$population) & snap$population > 0, c("iso3c", "population",
                                                             "gdp_per_capita",
                                                             "life_expectancy",
                                                             "income")]
  d$deaths <- stats::rpois(nrow(d), d$population * 0.008 *
                             exp(stats::rnorm(nrow(d), 0, 0.3)))
  d
}

test_that("eb_morans_i() agrees with spdep::EBImoran.mc()", {
  skip_slow_on_cran()
  skip_if_not_installed("spdep")
  d <- rate_fixture()
  W <- country_weights("knn", k = 5)
  e <- eb_morans_i(d, deaths, population, weights = W, n_perm = 0)
  al <- countryatlas:::align_weights(transform(d, r = deaths / population), "r", W)
  lw <- suppressWarnings(spdep::mat2listw(al$m, style = "M"))
  dd <- d[match(al$iso3c, d$iso3c), ]
  sp <- suppressMessages(spdep::EBImoran.mc(dd$deaths, dd$population, lw, nsim = 9))
  expect_equal(e$i, unname(sp$statistic), tolerance = 1e-12)
  expect_identical(e$n, length(al$iso3c))
  # And with a permutation test, a p-value in range.
  p <- eb_morans_i(d, deaths, population, n_perm = 99)$p_value
  expect_true(p > 0 && p <= 1)
})

test_that("smooth_rates(method = 'local_eb') agrees with spdep::EBlocal()", {
  skip_if_not_installed("spdep")
  d <- rate_fixture()
  W <- country_weights("knn", k = 5)
  expect_warning(sm <- smooth_rates(d, deaths, population, method = "local_eb",
                                    weights = W),
                 class = "countryatlas_no_neighbours")    # Gibraltar
  al <- countryatlas:::align_weights(transform(d, r = deaths / population), "r", W)
  nb <- suppressWarnings(spdep::mat2listw(al$m > 0, style = "B"))$neighbours
  dd <- d[match(al$iso3c, d$iso3c), ]
  eb <- spdep::EBlocal(dd$deaths, dd$population, nb, geoda = TRUE)
  ours <- sm$deaths_smoothed[match(al$iso3c, sm$iso3c)]
  expect_equal(ours, eb$est, tolerance = 1e-12)
  expect_true(all(sm$deaths_shrinkage >= 0 & sm$deaths_shrinkage <= 1, na.rm = TRUE))
  # The global method is unchanged by the new argument.
  g <- smooth_rates(d, deaths, population)
  expect_false(anyNA(g$deaths_smoothed))
})

test_that("theil(type = 'L') is the mean log deviation, and decomposes", {
  x <- c(1, 2, 4, 8)
  expect_equal(theil(x, type = "L"), mean(log(mean(x) / x)))
  w <- c(1, 3, 1, 2)
  mu <- sum(w * x) / sum(w)
  expect_equal(theil(x, w, type = "L"), sum(w / sum(w) * log(mu / x)))
  d <- theil(x, w, groups = c("a", "a", "b", "b"), type = "L")
  expect_equal(sum(d$value[d$component %in% c("between", "within")]),
               d$value[d$component == "total"])
})

test_that("inequality() reports every measure, each checked by hand", {
  x <- c(1, 2, 3, 4, 10)
  out <- inequality(x)
  expect_identical(out$measure, c("gini", "theil_t", "theil_l", "atkinson",
                                  "cv", "palma", "p90_p10"))
  v <- stats::setNames(out$value, out$measure)
  expect_equal(v[["gini"]], gini(x))
  expect_equal(v[["theil_t"]], theil(x))
  expect_equal(v[["atkinson"]], 1 - exp(mean(log(x))) / mean(x))
  expect_equal(v[["cv"]], sqrt(mean((x - mean(x))^2)) / mean(x))
  # Atkinson with epsilon = 2: one minus the harmonic mean over the mean.
  a2 <- inequality(x, measures = "atkinson", epsilon = 2)$value
  expect_equal(a2, 1 - (1 / mean(1 / x)) / mean(x))
  # Equal incomes: no inequality by any measure.
  flat <- inequality(rep(5, 10))
  expect_true(all(abs(flat$value[flat$measure != "palma" & flat$measure != "p90_p10"]) < 1e-12))
  expect_equal(flat$value[flat$measure == "p90_p10"], 1)
  # Every measure is computed on the same values: a non-positive one is
  # dropped from all of them, with a warning, not from some in silence.
  expect_warning(neg <- inequality(c(-1, 0, 2, 3, 7)),
                 class = "countryatlas_nonpositive_dropped")
  expect_identical(neg, inequality(c(2, 3, 7)))
  # Population weights change the answer (concept 2 against concept 1).
  s <- snap[!is.na(snap$gdp_per_capita) & !is.na(snap$population), ]
  expect_false(isTRUE(all.equal(inequality(s$gdp_per_capita)$value,
                                inequality(s$gdp_per_capita, s$population)$value)))
})

test_that("rate_funnel() draws exact Poisson limits", {
  skip_slow_on_cran()
  d <- rate_fixture()
  f <- rate_funnel(d, deaths, population)
  tab <- attr(f, "countryatlas_funnel")
  expect_named(tab, c("iso3c", "deaths", "population", "rate", "z", "flag"))
  # The limit for a denominator of 10,000 at 0.8% (E = 80), worked by hand:
  # qpois(0.975, 80) = 98, F(98) = 0.97797, F(97) = 0.97187, so the count
  # limit is 98 - (0.97797 - 0.975) / (0.97797 - 0.97187) = 97.513.
  lim <- countryatlas:::funnel_limit(1e4, 0.975, 0.008)
  expect_equal(lim * 1e4, 98 - (stats::ppois(98, 80) - 0.975) /
                 (stats::ppois(98, 80) - stats::ppois(97, 80)))
  expect_equal(lim * 1e4, 97.513, tolerance = 1e-4)
  # Interpolated, the limit is continuous and grows less than the mean.
  big <- countryatlas:::funnel_limit(c(1e4, 1e6), 0.975, 0.008)
  expect_lt(diff(big), 0)
  expect_true(all(tab$flag %in% c("within", "above 95%", "above 99.8%",
                                  "below 95%", "below 99.8%")))
  expect_gt(sum(tab$flag != "within"), 0)
  # Overdispersion widens the limits, so fewer countries are flagged.
  g <- rate_funnel(d, deaths, population, overdispersion = TRUE)
  expect_lt(sum(attr(g, "countryatlas_funnel")$flag != "within"),
            sum(tab$flag != "within"))
  expect_error(rate_funnel(d, deaths, population, limits = c(0.99, 0.95)),
               "increasing")
})

test_that("bivariate_lisa() and join_counts() describe what they claim", {
  skip_slow_on_cran()
  d <- rate_fixture()
  b <- bivariate_lisa(d, gdp_per_capita, life_expectancy, n_perm = 199)
  expect_named(b, c("iso3c", "x", "lag_y", "ii", "p_value", "p_adjusted", "cluster"))
  # ii is the standardised x times the neighbours' average standardised y.
  expect_true(all(sign(b$ii[b$cluster == "High-High"]) > 0))
  expect_true(all(sign(b$ii[b$cluster == "Low-High"]) < 0))
  j <- join_counts(d, income, n_perm = 199)
  expect_named(j, c("category", "n", "joins", "expected", "sd", "z", "p_value"))
  # Income groups cluster: more within-group joins than chance.
  expect_gt(j$joins[j$category == "High income"], j$expected[j$category == "High income"])
  expect_gt(attr(j, "n_joins"), 0L)
  expect_error(join_counts(d, gdp_per_capita), "categorical")
})
