test_that("per_capita divides by a supplied population column", {
  df <- data.frame(iso3c = c("USA", "CHN"), year = 2020L,
                   co2 = c(5e6, 1e7), pop = c(331e6, 1402e6))
  out <- per_capita(df, co2, pop)
  expect_true("co2_per_capita" %in% names(out))
  expect_equal(out$co2_per_capita, df$co2 / df$pop)
})

test_that("per_capita reports a failed population fetch clearly", {
  # Regression: fetch_wdi() degrades to a keys-only tibble when the World Bank
  # fetch fails (a timeout, say), and per_capita() then died on an opaque
  # vctrs error -- "Can't subset columns that don't exist: `.wdj_pop`".
  local_mocked_bindings(
    fetch_wdi = function(...) {
      tibble::tibble(iso3c = character(), iso2c = character(),
                     country = character(), year = integer())
    }
  )
  df <- data.frame(iso3c = c("USA", "CHN"), year = 2020L, co2 = c(5e6, 1e7))
  expect_error(per_capita(df, co2), class = "countryatlas_error")
  expect_error(per_capita(df, co2), "Could not fetch population")
  # A panel-free frame takes the other join branch; same clean error.
  expect_error(per_capita(df[, c("iso3c", "co2")], co2),
               "Could not fetch population")
  # An explicit pop column never touches the network.
  expect_no_error(per_capita(cbind(df, pop = c(331e6, 1402e6)), co2, pop))
})

test_that("aggregate_regions rolls up with sum and weighted mean", {
  df <- data.frame(
    iso3c = c("USA", "CAN", "BRA"),
    region = c("NA", "NA", "LAC"),
    gdp = c(21, 1.7, 1.4),
    pop = c(331, 38, 213)
  )
  s <- aggregate_regions(df, gdp, by = "region", fun = "sum")
  expect_equal(s$gdp[s$region == "NA"], 22.7)

  w <- aggregate_regions(df, gdp, by = "region", fun = "weighted_mean", weight = pop)
  expect_equal(
    w$gdp[w$region == "NA"],
    stats::weighted.mean(c(21, 1.7), c(331, 38))
  )
  expect_error(aggregate_regions(df, gdp, fun = "weighted_mean"),
               class = "countryatlas_error")
})

test_that("rank_countries adds rank, percentile, z-score", {
  df <- data.frame(iso3c = c("A", "B", "C"), v = c(3, 1, 2))
  out <- rank_countries(df, v)
  expect_equal(out$rank, c(1, 3, 2))
  expect_true(all(c("percentile", "z_score") %in% names(out)))
})

test_that("complete_years fills a panel by interpolation", {
  df <- data.frame(iso3c = "USA", year = c(2000L, 2002L), gdp = c(1, 3))
  out <- complete_years(df, 2000:2002, method = "linear")
  expect_equal(nrow(out), 3)
  expect_equal(out$gdp[out$year == 2001], 2)
})

test_that("complete_years locf carries forward", {
  df <- data.frame(iso3c = "USA", year = c(2000L, 2002L), gdp = c(1, NA))
  out <- complete_years(df, 2000:2002, method = "locf")
  expect_equal(out$gdp, c(1, 1, 1))
})

test_that("growth_rate computes year-on-year growth", {
  df <- data.frame(iso3c = "USA", year = 2000:2002, gdp = c(100, 110, 121))
  out <- growth_rate(df, gdp)
  expect_true("gdp_growth" %in% names(out))
  expect_true(is.na(out$gdp_growth[1]))                # first year has no lag
  expect_equal(out$gdp_growth[2], 110 / 100 - 1)       # 0.10
  expect_equal(out$gdp_growth[3], 121 / 110 - 1)       # 0.10
})

test_that("growth_rate computes CAGR from the first non-NA year", {
  df <- data.frame(iso3c = "USA", year = c(2000L, 2002L, 2004L),
                   gdp = c(100, 121, 144))
  out <- growth_rate(df, gdp, type = "cagr")
  expect_true("gdp_growth" %in% names(out))
  # CAGR: (V_t / V_0)^(1/n) - 1
  expect_equal(out$gdp_growth[2], (121 / 100)^(1 / 2) - 1)
  expect_equal(out$gdp_growth[3], (144 / 100)^(1 / 4) - 1)
})

test_that("growth_rate is per-country (groups are isolated)", {
  df <- data.frame(
    iso3c = rep(c("A", "B"), each = 3),
    year  = rep(2000:2002, 2),
    gdp   = c(100, 110, 121, 50, 55, 60)
  )
  out <- growth_rate(df, gdp)
  # Both countries see the same 10 % yoy growth, independent starting points
  expect_equal(out$gdp_growth[out$iso3c == "A"], c(NA, 0.1, 0.1))
  expect_equal(out$gdp_growth[out$iso3c == "B"], c(NA, 0.1, 0.0909090909090909))
})

test_that("growth_rate errors on missing columns", {
  expect_error(growth_rate(data.frame(x = 1), gdp),
               class = "countryatlas_error")
  df <- data.frame(iso3c = "A", year = 2000L)
  expect_error(growth_rate(df, gdp), class = "countryatlas_error")
})

test_that("index_to rebases a series to base year = 100", {
  df <- data.frame(iso3c = "USA", year = 2000:2002, gdp = c(50, 55, 60))
  out <- index_to(df, gdp, base_year = 2000)
  expect_true("gdp_index" %in% names(out))
  expect_equal(out$gdp_index, c(100, 110, 120))
})

test_that("index_to respects the `to` parameter", {
  df <- data.frame(iso3c = "USA", year = 2000:2002, gdp = c(50, 55, 60))
  out <- index_to(df, gdp, base_year = 2000, to = 1)
  expect_equal(out$gdp_index, c(1, 1.1, 1.2))
})

test_that("index_to returns NA when base year is missing", {
  df <- data.frame(iso3c = "USA", year = 2000:2002, gdp = c(50, 55, 60))
  out <- index_to(df, gdp, base_year = 1999)
  expect_true(all(is.na(out$gdp_index)))
})

test_that("index_to is per-country", {
  df <- data.frame(
    iso3c = rep(c("A", "B"), each = 3),
    year  = rep(2000:2002, 2),
    gdp   = c(100, 150, 200, 10, 12, 14)
  )
  out <- index_to(df, gdp, base_year = 2000)
  expect_equal(out$gdp_index[out$iso3c == "A"], c(100, 150, 200))
  expect_equal(out$gdp_index[out$iso3c == "B"], c(100, 120, 140))
})

test_that("index_to returns NA for zero-valued base", {
  df <- data.frame(iso3c = "A", year = 2000:2002, gdp = c(0, 1, 2))
  out <- index_to(df, gdp, base_year = 2000)
  expect_true(all(is.na(out$gdp_index)))
})

test_that("share_of_world adds a share column (single year)", {
  df <- data.frame(iso3c = c("USA", "CHN", "IND"), co2 = c(5, 10, 5))
  out <- share_of_world(df, co2)
  expect_true("co2_share" %in% names(out))
  expect_equal(out$co2_share, c(0.25, 0.5, 0.25))
})

test_that("share_of_world operates within year for panels", {
  df <- data.frame(
    iso3c = rep(c("USA", "CHN"), 2),
    year  = rep(c(2000L, 2001L), each = 2),
    co2   = c(5, 15, 10, 30)
  )
  out <- share_of_world(df, co2)
  # Within 2000: 5/(5+15)=0.25, 15/20=0.75
  expect_equal(out$co2_share[out$year == 2000], c(0.25, 0.75))
  # Within 2001: 10/(10+30)=0.25, 30/40=0.75
  expect_equal(out$co2_share[out$year == 2001], c(0.25, 0.75))
})

test_that("share_of_world handles NA values", {
  df <- data.frame(iso3c = c("A", "B", "C"), v = c(1, NA, 2))
  out <- share_of_world(df, v)
  expect_equal(out$v_share, c(1/3, NA, 2/3))
})

test_that("share_of_world errors on missing column", {
  expect_error(share_of_world(data.frame(x = 1), y),
               class = "countryatlas_error")
})
