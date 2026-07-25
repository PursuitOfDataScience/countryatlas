# Tests for the 2.0.0 second wave: historical crosswalk, analysis helpers,
# spatial statistics, spike_map, multilingual names, formatted binned legends.

# --- historical crosswalk -------------------------------------------------------

test_that("historical_codes has the expected shape", {
  expect_s3_class(historical_codes, "tbl_df")
  expect_named(historical_codes,
               c("historical", "iso3c_hist", "dissolved", "iso3c", "country"))
  expect_equal(nrow(historical_codes), 41L)
  expect_false(anyNA(historical_codes$iso3c))
  expect_false(anyNA(historical_codes$country))
  # The headline entities resolve to the right number of successors.
  expect_equal(sum(historical_codes$historical == "Soviet Union"), 15L)
  expect_equal(sum(historical_codes$historical == "Yugoslavia"), 7L)
  expect_equal(sum(historical_codes$historical == "Czechoslovakia"), 2L)
})

test_that("dissolve_country expands historical entities to successors", {
  out <- dissolve_country("USSR")
  expect_equal(nrow(out), 15L)
  expect_true(all(c("RUS", "UKR", "EST") %in% out$iso3c))
  expect_true(all(out$historical == "Soviet Union"))
  expect_true(all(out$dissolved == 1991L))

  yug <- dissolve_country("Yugoslavia")
  expect_equal(nrow(yug), 7L)
  expect_true("XKX" %in% yug$iso3c)   # territory-based; documented
})

test_that("dissolve_country passes modern names through as single rows", {
  out <- dissolve_country(c("USSR", "France"))
  expect_equal(nrow(out), 16L)
  fra <- out[out$input == "France", ]
  expect_equal(fra$iso3c, "FRA")
  expect_true(is.na(fra$historical))
  expect_true(is.na(fra$dissolved))
})

test_that("dissolve_country matches aliases case-insensitively and warns on misses", {
  out <- dissolve_country(c("czechoslovakia", "German Democratic Republic"),
                          warn = FALSE)
  expect_equal(sum(out$historical == "Czechoslovakia", na.rm = TRUE), 2L)
  expect_true("DEU" %in% out$iso3c)

  expect_warning(res <- dissolve_country("Wakanda"),
                 class = "countryatlas_warning")
  expect_true(is.na(res$iso3c))
  expect_silent(dissolve_country("Wakanda", warn = FALSE))
})

test_that("'Sudan' alone is NOT treated as historical (current country)", {
  out <- dissolve_country("Sudan", warn = FALSE)
  expect_equal(nrow(out), 1L)
  expect_equal(out$iso3c, "SDN")
  expect_true(is.na(out$historical))
  # The explicitly historical spelling expands.
  expect_equal(nrow(dissolve_country("Sudan (former)")), 2L)
})

test_that("repair_country_names does not record identity 'repairs'", {
  # "Yugoslavia" exists in the codelist by name (no ISO code), so its own name
  # is its closest suggestion; that must not count as a repair.
  out <- repair_country_names(c("Yugoslavia", "Brzil"), verbose = FALSE)
  reps <- attr(out, "repairs")
  expect_false("Yugoslavia" %in% reps$from)
  expect_true("Brzil" %in% reps$from)
  expect_equal(as.character(out)[1], "Yugoslavia")
})

test_that("check_country_match flags historical entities, even matched ones", {
  rep <- check_country_match(c("USSR", "Yugoslavia", "France", "Wakanda"))
  expect_true(all(c("historical", "matched") %in% names(rep)))
  # USSR silently matches RUS in countrycode -- the flag is the safety net.
  expect_true(rep$historical[rep$input == "USSR"])
  expect_true(rep$matched[rep$input == "USSR"])
  expect_true(rep$historical[rep$input == "Yugoslavia"])
  expect_false(rep$matched[rep$input == "Yugoslavia"])
  expect_false(rep$historical[rep$input == "France"])
  expect_false(rep$historical[rep$input == "Wakanda"])
})

# --- correlate_indicators -------------------------------------------------------

test_that("correlate_indicators computes pairwise correlations with n", {
  df <- data.frame(iso3c = c("A", "B", "C", "D"),
                   x = c(1, 2, 3, 4), y = c(2, 4, 6, 8), z = c(4, 3, 2, 1))
  out <- correlate_indicators(df, x, y, z)
  expect_named(out, c("var_x", "var_y", "r", "n"))
  expect_equal(nrow(out), 3L)          # 3 pairs
  xy <- out[out$var_x == "x" & out$var_y == "y", ]
  expect_equal(xy$r, 1)
  expect_equal(xy$n, 4L)
  xz <- out[out$var_x == "x" & out$var_y == "z", ]
  expect_equal(xz$r, -1)
})

test_that("correlate_indicators auto-selects numeric columns and respects min_n", {
  out <- correlate_indicators(world_snapshot$countries)
  expect_true(all(c("var_x", "var_y", "r", "n") %in% names(out)))
  expect_gt(nrow(out), 2L)
  expect_true(all(out$n <= nrow(world_snapshot$countries)))
  # Pairwise-complete: NA-heavy pairs below min_n come back NA.
  df <- data.frame(iso3c = c("A", "B", "C"), x = c(1, 2, NA), y = c(1, NA, 3))
  out2 <- correlate_indicators(df, x, y, min_n = 3)
  expect_true(is.na(out2$r))
  expect_equal(out2$n, 1L)
})

test_that("correlate_indicators validates its inputs", {
  df <- data.frame(iso3c = "A", x = 1)
  expect_error(correlate_indicators(df), class = "countryatlas_error")
  df2 <- data.frame(iso3c = c("A", "B"), x = c(1, 2), y = c("a", "b"))
  expect_error(correlate_indicators(df2, x, y), class = "countryatlas_error")
})

# --- panel lag / diff -----------------------------------------------------------

test_that("lag_by_country and diff_by_country stay within countries", {
  df <- data.frame(
    iso3c = rep(c("A", "B"), each = 3),
    year = rep(2000:2002, 2),
    gdp = c(1, 2, 4, 10, 20, 40)
  )
  lg <- lag_by_country(df, gdp)
  expect_equal(lg$gdp_lag[lg$iso3c == "A"], c(NA, 1, 2))
  expect_equal(lg$gdp_lag[lg$iso3c == "B"], c(NA, 10, 20))  # no cross-country leak

  dd <- diff_by_country(df, gdp)
  expect_equal(dd$gdp_diff[dd$iso3c == "A"], c(NA, 1, 2))

  # n > 1 appends n to the default suffix.
  lg2 <- lag_by_country(df, gdp, n = 2)
  expect_true("gdp_lag2" %in% names(lg2))
  expect_equal(lg2$gdp_lag2[lg2$iso3c == "A"], c(NA, NA, 1))
})

test_that("lag_by_country sorts by year before lagging", {
  df <- data.frame(iso3c = "A", year = c(2002L, 2000L, 2001L), gdp = c(4, 1, 2))
  lg <- lag_by_country(df, gdp)
  expect_equal(lg$gdp_lag[order(lg$year)], c(NA, 1, 2))
  expect_error(lag_by_country(data.frame(x = 1), gdp),
               class = "countryatlas_error")
})

# --- convergence ----------------------------------------------------------------

test_that("beta_convergence detects convergence in a synthetic panel", {
  set.seed(1)
  start <- runif(30, 6, 11)
  growth <- 0.05 - 0.004 * start + rnorm(30, 0, 0.001)
  panel <- data.frame(
    iso3c = rep(sprintf("C%02d", 1:30), each = 2),
    year = rep(c(2000L, 2020L), 30),
    gdp = as.vector(rbind(exp(start), exp(start + growth * 20)))
  )
  out <- beta_convergence(panel, gdp)
  expect_equal(nrow(out), 1L)
  expect_lt(out$beta, 0)
  expect_lt(out$p_value, 0.01)
  expect_gt(out$speed, 0)
  expect_gt(out$half_life, 0)
  expect_equal(out$n, 30L)
  expect_s3_class(attr(out, "model"), "lm")
})

test_that("beta_convergence errors with too few countries", {
  panel <- data.frame(iso3c = rep(c("A", "B"), each = 2),
                      year = rep(c(2000L, 2020L), 2), gdp = c(1, 2, 3, 4))
  expect_error(beta_convergence(panel, gdp), class = "countryatlas_error")
})

test_that("sigma_convergence reports per-year dispersion", {
  df <- data.frame(
    iso3c = rep(c("A", "B", "C"), 2),
    year = rep(c(2000L, 2010L), each = 3),
    gdp = c(1, 10, 100, 2, 11, 60)
  )
  out <- sigma_convergence(df, gdp)
  expect_named(out, c("year", "n", "sigma"))
  expect_equal(out$year, c(2000L, 2010L))
  expect_lt(out$sigma[2], out$sigma[1])   # dispersion falls
  cv <- sigma_convergence(df, gdp, measure = "cv")
  expect_true(all(cv$sigma > 0))
})

# --- inequality -----------------------------------------------------------------

test_that("gini matches known values", {
  expect_equal(gini(c(5, 5, 5)), 0)
  expect_equal(gini(c(0, 0, 1)), 2 / 3)
  # Integer weights replicate values.
  expect_equal(gini(c(1, 5), weights = c(3, 1)), gini(c(1, 1, 1, 5)))
  expect_true(is.na(gini(numeric(0))))
  expect_equal(gini(c(1, NA, 1)), 0)
  expect_error(gini(c(1, 2), weights = c(-1, 1)), class = "countryatlas_error")
})

test_that("theil is zero at equality and decomposes exactly", {
  expect_equal(theil(c(4, 4, 4)), 0)
  x <- c(1, 2, 8, 9, 30, 40)
  g <- c("a", "a", "b", "b", "c", "c")
  w <- c(1, 2, 1, 2, 1, 2)
  dec <- theil(x, weights = w, groups = g)
  expect_named(dec, c("component", "value", "share"))
  total <- dec$value[dec$component == "total"]
  expect_equal(total,
               dec$value[dec$component == "between"] +
                 dec$value[dec$component == "within"])
  expect_equal(total, theil(x, weights = w))
  expect_gt(total, 0)
  expect_warning(theil(c(0, 1, 2)), class = "countryatlas_warning")
})

test_that("theil shares are NA (not NaN) at perfect equality", {
  dec <- theil(c(5, 5, 5, 5), groups = c("a", "a", "b", "b"))
  expect_equal(dec$value, c(0, 0, 0))
  expect_true(all(is.na(dec$share)))
  expect_false(any(is.nan(dec$share)))
})

# --- Moran's I ------------------------------------------------------------------

test_that("morans_i finds spatial autocorrelation in GDP (needs sf)", {
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
  set.seed(42)
  out <- morans_i(world_snapshot$countries, gdp_per_capita, n_perm = 199)
  expect_named(out, c("i", "expected", "n", "n_links", "p_value"))
  expect_gt(out$i, 0.3)          # GDP clusters strongly in space
  expect_lt(out$p_value, 0.05)
  expect_gt(out$n, 100)
  expect_equal(out$expected, -1 / (out$n - 1))
  # n_perm = 0 skips the permutation test.
  out0 <- morans_i(world_snapshot$countries, gdp_per_capita, n_perm = 0)
  expect_true(is.na(out0$p_value))
})

test_that("morans_i validates input", {
  skip_if_not_installed("sf")
  expect_error(morans_i(data.frame(x = 1), x), class = "countryatlas_error")
})

# --- spike_map ------------------------------------------------------------------

test_that("spike_map builds a ggplot with one triangle per country", {
  skip_if_not_installed("maps")
  p <- spike_map(world_snapshot$countries, population)
  expect_s3_class(p, "ggplot")
  expect_silent(ggplot2::ggplot_build(p))
  spikes <- p$layers[[2]]$data
  expect_equal(nrow(spikes) %% 3L, 0L)
  expect_equal(anyDuplicated(unique(spikes$iso3c)), 0L)
})

test_that("spike_map validates input", {
  expect_error(spike_map(data.frame(x = 1), x), class = "countryatlas_error")
})

# --- multilingual names ---------------------------------------------------------

test_that("convert_country(to = 'name_<lang>') returns localized names", {
  expect_equal(convert_country("Germany", to = "name_fr"), "Allemagne")
  expect_equal(convert_country("Germany", to = "name_es"), "Alemania")
  expect_equal(convert_country(c("Japan", "Brazil"), to = "name_de"),
               c("Japan", "Brasilien"))
  # Override-only entities work too (resolved via iso3c first).
  expect_equal(convert_country("Canary Islands", to = "name_fr"), "Espagne")
})

# --- formatted binned legends ---------------------------------------------------

test_that("binned style builds with SI-formatted labels", {
  skip_if_not_installed("scales")
  # The shared formatter renders 4e+06 as "4M".
  fmt <- countryatlas:::scales_format()
  expect_equal(unname(fmt(c(4e6, 2e9))), c("4M", "2B"))

  skip_if_not_installed("maps")
  mapdf <- attach_geometry(world_snapshot$countries, geometry = "polygon")
  p <- world_map(mapdf, population, style = "binned")
  expect_s3_class(p, "ggplot")
  expect_silent(ggplot2::ggplot_build(p))
})
