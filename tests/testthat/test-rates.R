# --- rates, deflation, convergence -----------------------------------------------

test_that("rate_check ranks by how little stands behind the rate", {
  d <- data.frame(iso3c = c("CHN", "IND", "TUV", "NRU"),
                  cases = c(50000, 42000, 3, 1),
                  pop = c(1.41e9, 1.39e9, 11000, 12000))
  out <- rate_check(d, cases, pop)
  expect_named(out, c("iso3c", "numerator", "denominator", "rate",
                      "expected_se", "flagged"))
  # The tiny denominators come first.
  expect_true(out$iso3c[1] %in% c("TUV", "NRU"))
  expect_gt(out$expected_se[1], out$expected_se[nrow(out)])
  expect_equal(out$rate[out$iso3c == "CHN"], 50000 / 1.41e9)
})

test_that("smooth_rates shrinks small denominators and leaves large ones", {
  d <- data.frame(iso3c = c("CHN", "IND", "TUV", "NRU", "USA"),
                  cases = c(50000, 42000, 3, 1, 30000),
                  pop = c(1.41e9, 1.39e9, 11000, 12000, 3.3e8))
  out <- smooth_rates(d, cases, pop)
  expect_true(all(c("cases_rate", "cases_smoothed", "cases_shrinkage") %in%
                    names(out)))
  big <- out$cases_shrinkage[out$iso3c == "CHN"]
  small <- out$cases_shrinkage[out$iso3c == "TUV"]
  expect_gt(big, 0.99)      # believed
  expect_lt(small, 0.2)     # shrunk hard
  # Shrinkage moves the small rate toward the pooled rate.
  pooled <- sum(d$cases) / sum(d$pop)
  expect_lt(abs(out$cases_smoothed[out$iso3c == "TUV"] - pooled),
            abs(out$cases_rate[out$iso3c == "TUV"] - pooled))
  expect_equal(smooth_rates(d, cases, pop, method = "none")$cases_smoothed,
               out$cases_rate)
})

test_that("an unusable deflator or PPP factor gives NA, not Inf", {
  # Dividing by a zero index produced Inf, which then propagated silently into
  # every scale and summary downstream. The NA it gives instead is reported,
  # as to_ppp()'s is below.
  expect_warning(
    d0 <- deflate(data.frame(iso3c = "A", year = 2000:2001, g = c(1, 2),
                             d = c(0, 1)), g, base_year = 2001, deflator = d),
    class = "countryatlas_unusable_rows")
  expect_false(any(is.infinite(d0$g_real)))
  expect_true(is.na(d0$g_real[1]))
  # And an unusable factor now says so, rather than handing back a blank
  # column -- the silence this test's own comment above objects to.
  expect_warning(
    p0 <- to_ppp(data.frame(iso3c = "A", year = 2000L, g = 1, f = 0), g,
                 factor = f),
    class = "countryatlas_no_rates")
  expect_true(is.na(p0$g_ppp))
})

test_that("deflate rebases per country", {
  d <- data.frame(iso3c = "USA", year = 2000:2002, gdp = c(100, 110, 120),
                  defl = c(90, 100, 105))
  out <- deflate(d, gdp, base_year = 2001, deflator = defl)
  # The base year is unchanged by construction.
  expect_equal(out$gdp_real[out$year == 2001], 110)
  expect_equal(out$gdp_real[out$year == 2000], 100 / (90 / 100))
  expect_error(deflate(d, gdp, base_year = 1999, deflator = defl),
               "not in .*year")
  expect_error(deflate(d, gdp, deflator = defl), "base_year")
})

test_that("to_ppp divides by the conversion factor", {
  d <- data.frame(iso3c = c("IND", "USA"), year = 2020L,
                  gdp_lcu = c(1e5, 1e4), ppp = c(20, 1))
  out <- to_ppp(d, gdp_lcu, factor = ppp)
  expect_equal(out$gdp_lcu_ppp, c(5000, 10000))
})

test_that("convergence_club separates groups converging to different levels", {
  set.seed(1)
  panel <- expand.grid(iso3c = c(paste0("A", 1:5), paste0("B", 1:5)),
                       year = 2000:2029, stringsAsFactors = FALSE)
  panel$y <- ifelse(startsWith(panel$iso3c, "A"), 100, 30) +
    stats::rnorm(nrow(panel), 0, 1)
  cc <- convergence_club(panel, y)
  expect_named(cc, c("iso3c", "club", "log_t"))
  expect_true(any(!is.na(cc$club)))
  expect_s3_class(attr(cc, "countryatlas_clubs"), "tbl_df")
  # An unbalanced panel with nothing complete cannot be tested.
  expect_error(convergence_club(data.frame(iso3c = "A", year = 2000, y = 1), y),
               "Not enough countries")
})

test_that("log_t_stat is finite on a converging group", {
  set.seed(2)
  y <- matrix(rep(seq(10, 20, length.out = 30), each = 6), nrow = 6) +
    stats::rnorm(180, 0, 0.1)
  expect_true(is.finite(countryatlas:::log_t_stat(y)))
  expect_true(is.na(countryatlas:::log_t_stat(matrix(1, 1, 30))))
})

test_that("empirical-Bayes shrinkage behaves like shrinkage", {
  d <- data.frame(iso3c = LETTERS[1:6], cases = c(5, 10, 20, 40, 80, 160),
                  pop = c(1e3, 1e4, 1e5, 1e6, 1e7, 1e8))
  sr <- smooth_rates(d, cases, pop)
  # Believe a country in proportion to its denominator...
  expect_false(is.unsorted(sr$cases_shrinkage))
  expect_true(all(sr$cases_shrinkage >= 0 & sr$cases_shrinkage <= 1))
  # ...and never push a rate past the pooled rate, or away from it.
  pooled <- sum(d$cases) / sum(d$pop)
  expect_true(all((sr$cases_smoothed - pooled) * (sr$cases_rate - pooled) >= 0))
  expect_true(all(abs(sr$cases_smoothed - pooled) <=
                    abs(sr$cases_rate - pooled) + 1e-12))
})

test_that("convergence_club separates what should separate and joins what should join", {
  set.seed(3)
  one <- expand.grid(iso3c = paste0("C", 1:8), year = 2000:2039,
                     stringsAsFactors = FALSE)
  one$y <- 100 + stats::rnorm(nrow(one), 0, 0.5)
  expect_equal(length(unique(stats::na.omit(convergence_club(one, y)$club))), 1L)

  set.seed(4)
  two <- expand.grid(iso3c = c(paste0("A", 1:5), paste0("B", 1:5)),
                     year = 2000:2039, stringsAsFactors = FALSE)
  two$y <- ifelse(startsWith(two$iso3c, "A"), 1000, 10) +
    stats::rnorm(nrow(two), 0, 0.2)
  expect_gt(length(unique(stats::na.omit(convergence_club(two, y)$club))), 1L)
})

test_that("deflate says which countries have no base-year deflator", {
  # Without a base-year row there is nothing to rebase against, so every value
  # for that country becomes NA -- which in the output looks exactly like a
  # country the source had no data for. The arithmetic was right; the silence
  # was not.
  d <- tibble::tibble(
    iso3c = c("FRA", "FRA", "DEU", "DEU"),
    year  = c(2015L, 2020L, 2019L, 2020L),
    gdp   = c(100, 120, 200, 220),
    defl  = c(100, 110, 105, 112))
  expect_warning(out <- deflate(d, gdp, base_year = 2015, deflator = defl),
                 "DEU")
  expect_true(all(is.na(out$gdp_real[out$iso3c == "DEU"])))
  # The countries that do have the base year are untouched.
  expect_equal(out$gdp_real[out$iso3c == "FRA"], c(100, 120 / 1.1))

  # A panel where every country covers the base year stays quiet.
  full <- tibble::tibble(
    iso3c = c("FRA", "FRA", "DEU", "DEU"),
    year  = c(2015L, 2020L, 2015L, 2020L),
    gdp   = c(100, 120, 200, 220),
    defl  = c(100, 110, 105, 112))
  expect_no_warning(deflate(full, gdp, base_year = 2015, deflator = defl))
})

test_that("one-row-per-country never folds the uncoded countries together", {
  # Three verbs de-duplicated on iso3c to stop a polygon frame counting a
  # country once per vertex, but distinct() treats NA as a value -- so every
  # uncoded country collapsed into one row and rate_check()/world_table()
  # silently returned three rows for a five-row input.
  d <- tibble::tibble(
    iso3c   = c("FRA", "DEU", NA, NA, NA),
    country = c("France", "Germany", "Freedonia", "Ruritania", "Elbonia"),
    cases   = c(10, 20, 30, 40, 50),
    pop     = c(1e6, 2e6, 3e5, 4e5, 5e5),
    v       = c(1, 2, 3, 4, 5))
  expect_equal(nrow(suppressWarnings(rate_check(d, cases, pop))), 5L)
  expect_equal(nrow(world_table(d, v, engine = "tibble")), 5L)
  expect_equal(audit_coverage(d)$na_rates$n[1], 5L)

  # Coded duplicates are still collapsed, which is what the de-duplication is
  # for in the first place.
  dup <- tibble::tibble(iso3c = c("FRA", "FRA", "DEU"),
                        country = c("France", "France", "Germany"),
                        v = c(1, 1, 2))
  expect_equal(nrow(world_table(dup, v, engine = "tibble")), 2L)
  expect_equal(nrow(countryatlas:::distinct_countries(dup)), 2L)
  # An uncoded frame with nothing else to key on is left alone.
  bare <- tibble::tibble(iso3c = c(NA, NA), v = c(1, 2))
  expect_equal(nrow(countryatlas:::distinct_countries(bare)), 2L)
})

test_that("the money verbs all announce a column they are about to clobber", {
  # deflate(), to_ppp() and smooth_rates() are the same shape -- take a panel,
  # write one derived column back into it -- but only two of them warned.
  # deflate() overwrote an existing gdp_real in silence.
  d <- tibble::tibble(iso3c = c("FRA", "FRA"), year = c(2015L, 2020L),
                      gdp = c(100, 120), defl = c(100, 110), f = c(2, 2),
                      gdp_real = c(-1, -1), gdp_ppp = c(-1, -1))
  expect_warning(deflate(d, gdp, base_year = 2015, deflator = defl),
                 "Overwriting")
  expect_warning(to_ppp(d, gdp, factor = f), "Overwriting")
  s <- tibble::tibble(iso3c = c("A", "B"), cases = c(1, 2), pop = c(100, 200),
                      cases_smoothed = c(-1, -1))
  expect_warning(smooth_rates(s, cases, pop), "Overwriting")

  # None of them warns when there is nothing to clobber, and the arithmetic is
  # unchanged.
  ok <- tibble::tibble(iso3c = c("FRA", "FRA"), year = c(2015L, 2020L),
                       gdp = c(100, 120), defl = c(100, 110))
  expect_no_warning(out <- deflate(ok, gdp, base_year = 2015, deflator = defl))
  expect_equal(round(out$gdp_real, 2), c(100, 109.09))
  # A custom suffix is what gets checked, not the default.
  expect_no_warning(deflate(ok, gdp, base_year = 2015, deflator = defl,
                            suffix = "_c"))
  clash_c <- ok; clash_c$gdp_c <- -1
  expect_warning(deflate(clash_c, gdp, base_year = 2015, deflator = defl,
                         suffix = "_c"), "Overwriting")
})

test_that("the one-row-per-country rule really takes the earliest year", {
  skip_slow_on_cran()
  # distinct_countries() warns "only the earliest year of each country is
  # used", but the code was distinct(iso3c, .keep_all = TRUE), which keeps
  # whichever row is *first in the frame*. That is the earliest year only if
  # the caller happened to sort by year, so the same panel in a different row
  # order gave a different answer -- rate_check() reported a different
  # numerator for France, and the map verbs drew a different year -- with the
  # warning still promising "earliest" either way.
  set.seed(7)
  pan <- do.call(rbind, lapply(2000:2007, function(y)
    data.frame(iso3c = c("USA", "FRA", "BRA"), year = y,
               v = c(10, 20, 30) + (y - 2000), pop = c(3e8, 6e7, 2e8))))
  shuf <- pan[sample(nrow(pan)), ]
  dc <- countryatlas:::distinct_countries

  # The promise, on any input order.
  for (d in list(pan, shuf, pan[rev(seq_len(nrow(pan))), ])) {
    got <- suppressWarnings(dc(d))
    expect_equal(sort(got$year), rep(2000L, 3L))
    expect_equal(nrow(got), 3L)
  }
  # And the verbs built on it agree with each other whatever the row order.
  norm <- function(x) {
    x <- as.data.frame(dplyr::ungroup(x))
    x[order(x$iso3c), setdiff(names(x), "year"), drop = FALSE] |>
      `rownames<-`(NULL)
  }
  expect_equal(norm(suppressWarnings(rate_check(pan, v, pop))),
               norm(suppressWarnings(rate_check(shuf, v, pop))))
  # The numerator is the year 2000 value, not an arbitrary one.
  rc <- suppressWarnings(rate_check(shuf, v, pop))
  expect_equal(rc$numerator[match(c("USA", "FRA", "BRA"), rc$iso3c)],
               c(10, 20, 30))
  # A frame with no year column is untouched by any of this.
  flat <- data.frame(iso3c = c("USA", "FRA"), v = 1:2)
  expect_equal(nrow(dc(flat)), 2L)
  expect_silent(dc(flat))

  # "Earliest" has to mean earliest for every type `year` arrives as. order()
  # on a factor sorts by level index, not label, so a factored year with levels
  # 2002 < 2001 < 2000 handed back the *latest* year.
  mk <- function(y) data.frame(iso3c = rep(c("USA", "FRA"), each = 3),
                               year = y, v = 1:6)
  years <- list(
    integer   = rep(c(2002L, 2000L, 2001L), 2),
    double    = rep(c(2002, 2000, 2001), 2),
    character = rep(c("2002", "2000", "2001"), 2),
    factor_rev = factor(rep(c("2002", "2000", "2001"), 2),
                        levels = c("2002", "2001", "2000")),
    factor_alpha = factor(rep(c("2002", "2000", "2001"), 2)),
    with_na   = rep(c(NA, 2000L, 2001L), 2))
  for (nm in names(years)) {
    got <- suppressWarnings(dc(mk(years[[nm]])))
    expect_equal(as.character(got$year), c("2000", "2000"), info = nm)
    expect_equal(got$v, c(2L, 5L), info = nm)
  }
  # Labels that are not years at all fall back to sorting on the label.
  q <- suppressWarnings(dc(mk(rep(c("Q3", "Q1", "Q2"), 2))))
  expect_equal(q$year, c("Q1", "Q1"))
  # All-NA years leave the first row standing rather than erroring.
  expect_equal(nrow(suppressWarnings(dc(mk(rep(NA_integer_, 6))))), 2L)
})

test_that("smooth_rates and to_ppp say when they had nothing to work with", {
  skip_slow_on_cran()
  # rate_check() had exactly this bug fixed already -- "returned an all-NA
  # flagged column in silence" -- but its two siblings kept it. With no usable
  # denominator every rate is NA and the smoothed column with it; with no usable
  # conversion factor every converted value is NA. Correct arithmetic either
  # way, but the result looked like a computation that ran rather than one with
  # nothing to run on.
  # A cross-section: smooth_rates() estimates one prior per year, which a panel
  # exercises elsewhere. What this block is about is the no-usable-denominator
  # notices, so keep the fixture single-year.
  mk <- function(den) data.frame(iso3c = paste0("C", 1:6), year = 2000L,
                                 num = 1:6, den = den)

  expect_warning(s <- smooth_rates(mk(0), num, den),
                 class = "countryatlas_no_rates")
  expect_true(all(is.na(s$num_rate)))
  expect_true(all(is.na(s$num_smoothed)))
  # A partial loss is reported with a count, in the singular and the plural.
  one <- mk(1e6); one$den[1] <- 0
  expect_warning(smooth_rates(one, num, den), "1 row has")
  two <- mk(1e6); two$den[1:2] <- 0
  expect_warning(smooth_rates(two, num, den), "2 rows have")
  expect_silent(smooth_rates(mk(1e6), num, den))

  d <- function(f) data.frame(iso3c = paste0("C", seq_along(f)), year = 2000L,
                              v = seq_along(f), f = f)
  expect_warning(p <- to_ppp(d(c(0, -1, NA)), v, factor = f),
                 class = "countryatlas_no_rates")
  expect_true(all(is.na(p$v_ppp)))
  expect_warning(to_ppp(d(c(0, 2, 3)), v, factor = f), "1 row has")
  expect_warning(to_ppp(d(c(0, -1, 3)), v, factor = f), "2 rows have")
  # Zero, negative and NA are each unusable; a positive factor converts.
  expect_silent(ok <- to_ppp(d(c(1, 2, 4)), v, factor = f))
  expect_equal(ok$v_ppp, c(1, 1, 0.75))
})

test_that("the value and rate columns are checked for a number", {
  d <- data.frame(iso3c = "USA", year = 2000:2002, gdp = c("100", "110", "120"),
                  defl = c(90, 100, 105), ppp = 1)
  expect_error(deflate(d, gdp, base_year = 2001, deflator = defl),
               "must be numeric", class = "countryatlas_error")
  expect_error(to_ppp(d, gdp, factor = ppp), "must be numeric",
               class = "countryatlas_error")
  r <- data.frame(iso3c = c("CHN", "IND"), cases = c(5, 4), pop = c(10, 20),
                  r = c("a", "b"))
  expect_error(rate_check(r, cases, pop, rate = r), "must be numeric",
               class = "countryatlas_error")
})

test_that("convergence_club() does not depend on row order", {
  skip_slow_on_cran()
  set.seed(1)
  panel <- expand.grid(year = 2000:2024,
                       iso3c = c(paste0("A", 1:5), paste0("B", 1:5)),
                       stringsAsFactors = FALSE)[, c("iso3c", "year")]
  panel$y <- ifelse(startsWith(panel$iso3c, "A"), 100, 30) +
    stats::rnorm(nrow(panel), 0, 2)
  base <- convergence_club(panel, y)
  shuffled <- convergence_club(panel[sample(nrow(panel)), ], y)
  expect_equal(as.data.frame(shuffled), as.data.frame(base))
  # The first country lacking the first year used to put that year last. That
  # country has no complete series, so it comes back unclassified and says so.
  p2 <- panel[!(panel$iso3c == "A1" & panel$year == 2000), ]
  p3 <- rbind(p2[p2$iso3c != "A1", ], p2[p2$iso3c == "A1", ])
  expect_warning(o2 <- convergence_club(p2, y),
                 class = "countryatlas_incomplete_series")
  expect_warning(o3 <- convergence_club(p3, y),
                 class = "countryatlas_incomplete_series")
  expect_equal(as.data.frame(o2), as.data.frame(o3))
})

test_that("smooth_rates() estimates one prior per year of a panel", {
  set.seed(4)
  n <- 30
  one <- function(year, rate) {
    den <- round(10^stats::runif(n, 3, 7))
    data.frame(iso3c = sprintf("C%02d", seq_len(n)), year = year, den = den,
               num = stats::rpois(n, den * rate * exp(stats::rnorm(n, 0, 0.5))))
  }
  # Rates ten times higher in the second year: shrinking 2020 toward 2019's
  # global rate is the wrong answer, and it is what the old pooling did.
  panel <- rbind(one(2019L, 0.001), one(2020L, 0.01))
  expect_no_warning(sm <- smooth_rates(panel, num, den),
                    class = "countryatlas_panel")
  expect_equal(nrow(sm), nrow(panel))
  for (y in c(2019L, 2020L)) {
    alone <- smooth_rates(panel[panel$year == y, ], num, den)
    expect_equal(sm$num_smoothed[sm$year == y], alone$num_smoothed)
    expect_equal(sm$num_shrinkage[sm$year == y], alone$num_shrinkage)
  }
})

test_that("convergence_club() returns a country with a gap as unclassified", {
  skip_slow_on_cran()
  set.seed(1)
  panel <- expand.grid(iso3c = c(paste0("A", 1:5), paste0("B", 1:5)),
                       year = 2000:2024, stringsAsFactors = FALSE)
  panel$y <- ifelse(startsWith(panel$iso3c, "A"), 100, 30) +
    stats::rnorm(nrow(panel), 0, 2)
  full <- convergence_club(panel, y)
  gap <- panel
  gap$y[gap$iso3c == "A1" & gap$year == 2010] <- NA
  expect_warning(out <- convergence_club(gap, y),
                 class = "countryatlas_incomplete_series")
  expect_warning(convergence_club(gap, y), "A1")
  expect_setequal(out$iso3c, unique(panel$iso3c))
  expect_true(is.na(out$club[out$iso3c == "A1"]))
  expect_true(is.na(out$log_t[out$iso3c == "A1"]))
  # A complete panel is untouched and says nothing new.
  expect_equal(nrow(full), 10L)
  expect_false(anyNA(full$iso3c))
})

test_that("smooth_rates() keeps a negative count out of the model", {
  d <- data.frame(iso3c = c("A", "B", "C", "D"), cases = c(-50, 1, 4, 9),
                  pop = c(100, 100, 400, 900))
  expect_warning(out <- smooth_rates(d, cases, pop),
                 class = "countryatlas_negative_count")
  expect_true(all(is.na(unlist(out[1, c("cases_rate", "cases_smoothed",
                                        "cases_shrinkage")]))))
  # The rest is smoothed exactly as though the negative row were not there.
  alone <- smooth_rates(d[-1, ], cases, pop)
  expect_equal(out$cases_smoothed[-1], alone$cases_smoothed)
  expect_equal(out$cases_shrinkage[-1], alone$cases_shrinkage)
  expect_true(all(out$cases_shrinkage[-1] >= 0 & out$cases_shrinkage[-1] <= 1))
})

test_that("smooth_rates() blames the denominator only for denominator rows", {
  d <- data.frame(iso3c = c("A", "B", "C", "D"), cases = c(NA, 2, 3, 4),
                  pop = c(100, 0, 300, 400))
  w <- character(0)
  withCallingHandlers(smooth_rates(d, cases, pop),
    warning = function(x) { w <<- c(w, conditionMessage(x))
                            invokeRestart("muffleWarning") })
  # One row (B) has no usable pop; A's pop is fine, its count is missing.
  expect_true(any(grepl("1 row has no finite, positive", w)))
  expect_false(any(grepl("2 rows have", w)))
})

test_that("rate_check() gives no standard error for a negative rate", {
  skip_slow_on_cran()
  d <- data.frame(iso3c = c("A", "B", "C"), cases = c(-5, 10, 20),
                  pop = c(1000, 2000, 3000))
  expect_warning(out <- rate_check(d, cases, pop),
                 class = "countryatlas_negative_count")
  expect_true(is.na(out$expected_se[out$iso3c == "A"]))
  expect_false(anyNA(out$expected_se[out$iso3c != "A"]))
})

test_that("deflate() says which rows an unusable index left empty", {
  d <- tibble::tibble(iso3c = rep(c("FRA", "DEU"), each = 3),
                      year = rep(2015:2017, 2), v = 1:6,
                      defl = c(100, Inf, 110, 100, 0, 120))
  # Silent NA, where to_ppp() and per_capita() report the same thing.
  expect_warning(out <- deflate(d, v, base_year = 2015, deflator = defl),
                 class = "countryatlas_unusable_rows")
  expect_equal(sum(is.na(out$v_real)), 2L)
  expect_no_warning(deflate(d[c(1, 3, 4, 6), ], v, base_year = 2015,
                            deflator = defl))
})

test_that("deflate() and to_ppp() say when value and index years differ", {
  d <- tibble::tibble(iso3c = "FRA", year = c(2020L, 2021L), gdp = c(10, 11),
                      gdp_year = c(2020L, 2019L), defl = c(100, 110),
                      defl_year = c(2020L, 2021L))
  expect_warning(deflate(d, gdp, base_year = 2020, deflator = defl),
                 class = "countryatlas_mixed_years")
  expect_warning(to_ppp(d, gdp, factor = defl),
                 class = "countryatlas_mixed_years")
  d$gdp_year <- d$defl_year
  expect_silent(deflate(d, gdp, base_year = 2020, deflator = defl))
})
