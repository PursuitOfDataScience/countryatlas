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

# Users pipe out of group_by(), so a grouped frame arrives routinely. Functions
# here impose their own grouping (usually by iso3c) and so are unaffected --
# except rank_countries(), whose mutate() honoured the caller's groups. That
# silently converted the documented global ranking into a within-group one: the
# same data ranked 4,1,3,2 ungrouped and 2,1,2,1 grouped, with `within = NULL`
# in both cases.

test_that("rank_countries ranks globally unless `within` says otherwise", {
  d <- tibble::tibble(iso3c = c("AAA", "BBB", "CCC", "DDD"),
                      region = c("X", "X", "Y", "Y"), g = c(1, 4, 2, 3))
  global <- rank_countries(d, g)$rank
  expect_equal(global, rank_countries(dplyr::group_by(d, region), g)$rank)
  expect_equal(rank_countries(d, g)$percentile,
               rank_countries(dplyr::group_by(d, region), g)$percentile)
  expect_equal(rank_countries(d, g)$z_score,
               rank_countries(dplyr::group_by(d, region), g)$z_score)
  # `within` still works, from either input.
  wi <- rank_countries(d, g, within = region)$rank
  expect_equal(rank_countries(dplyr::group_by(d, region), g, within = region)$rank,
               wi)
  expect_false(identical(global, wi))          # the two really do differ
  # And the global ranking is the right one: rank 1 is the largest value.
  expect_equal(d$g[which(global == 1L)], max(d$g))
})

test_that("an incidental group_by() never changes an answer", {
  panel <- tibble::tibble(
    iso3c = rep(c("USA", "FRA", "CHN"), each = 4),
    year = rep(2000:2003, 3), region = rep(c("A", "B", "A"), each = 4),
    g = c(1, 2, 3, 4, 10, 11, 12, 13, 100, 110, 120, 130), population = 1e6)
  grp <- dplyr::group_by(panel, region)
  flat <- function(x) dplyr::ungroup(tibble::as_tibble(x))
  expect_equal(flat(growth_rate(grp, g)), flat(growth_rate(panel, g)))
  expect_equal(flat(index_to(grp, g, base_year = 2000)),
               flat(index_to(panel, g, base_year = 2000)))
  expect_equal(flat(lag_by_country(grp, g)), flat(lag_by_country(panel, g)))
  expect_equal(flat(diff_by_country(grp, g)), flat(diff_by_country(panel, g)))
  expect_equal(flat(share_of_world(grp, g)), flat(share_of_world(panel, g)))
  expect_equal(flat(per_capita(grp, g, pop = population)),
               flat(per_capita(panel, g, pop = population)))
  expect_equal(flat(complete_years(grp, value = "g")),
               flat(complete_years(panel, value = "g")))
  expect_equal(flat(aggregate_regions(grp, g, by = "region")),
               flat(aggregate_regions(panel, g, by = "region")))
  expect_equal(flat(rank_countries(grp, g)), flat(rank_countries(panel, g)))
  # The 3.0.0 verbs postdate this test, and rank_countries()'s comment claims
  # "every other function here likewise imposes its own grouping" -- so check
  # them rather than take the claim.
  expect_equal(flat(interpolate_missing(grp, "g")),
               flat(interpolate_missing(panel, "g")))
  expect_equal(flat(smooth_rates(grp, g, population)),
               flat(smooth_rates(panel, g, population)))
  expect_equal(flat(deflate(grp, g, 2000, deflator = population)),
               flat(deflate(panel, g, 2000, deflator = population)))
  expect_equal(flat(to_ppp(grp, g, factor = population)),
               flat(to_ppp(panel, g, factor = population)))
  expect_equal(flat(sigma_convergence(grp, g)), flat(sigma_convergence(panel, g)))
  # These reduce to one row per country, so a 4-year panel earns the
  # countryatlas_panel warning. That is correct and has its own test; here the
  # question is only whether grouping changed the answer.
  suppressWarnings({
    expect_equal(flat(rate_check(grp, g, population)),
                 flat(rate_check(panel, g, population)))
    expect_equal(flat(correlate_indicators(grp)),
                 flat(correlate_indicators(panel)))
    expect_equal(audit_coverage(grp)$na_rates, audit_coverage(panel)$na_rates)
  })

  # The panel branch was safe by accident: share_of_world() regroups by `year`,
  # which replaces the caller's groups. Without a `year` column nothing replaced
  # them, so sum() ran per group and the "share of the world" became a share of
  # the group -- grouped by region the column summed to 2, not 1. Cover that
  # branch explicitly.
  flat_panel <- dplyr::select(dplyr::ungroup(panel), -"year")
  flat_panel <- dplyr::summarise(dplyr::group_by(flat_panel, .data$iso3c),
                                 region = dplyr::first(.data$region),
                                 g = sum(.data$g), .groups = "drop")
  fg <- dplyr::group_by(flat_panel, region)
  expect_warning(shares <- share_of_world(fg, g), "grouping is ignored")
  expect_equal(flat(shares), flat(share_of_world(flat_panel, g)))
  expect_equal(sum(shares$g_share), 1)
})

test_that("no function leaks grouping into its return value", {
  panel <- tibble::tibble(iso3c = rep(c("USA", "FRA"), each = 3),
                          year = rep(2000:2002, 2), g = c(1, 2, 3, 4, 5, 6),
                          population = 1e6)
  grp <- dplyr::group_by(panel, iso3c)
  for (out in list(growth_rate(grp, g), lag_by_country(grp, g),
                   diff_by_country(grp, g), share_of_world(grp, g),
                   index_to(grp, g, base_year = 2000), rank_countries(grp, g),
                   per_capita(grp, g, pop = population),
                   complete_years(grp, value = "g"))) {
    expect_false(dplyr::is_grouped_df(out))
  }
})

# A group with no non-missing value has nothing to aggregate, and every base
# function got that wrong differently: sum() returned 0, mean() NaN,
# min()/max() -Inf/Inf with a warning, weighted.mean() NaN. "This region's
# total is 0" is a claim, not an absence -- and this package exists to handle
# missing country data honestly. .safe_min/.safe_max already returned NA; now
# every `fun` does.

test_that("a group with no data aggregates to NA, not 0", {
  mix <- tibble::tibble(iso3c = c("A", "B", "C", "D"),
                        region = c("X", "X", "Y", "Y"),
                        g = c(1, 3, NA, NA), w = c(1, 1, 1, 1))
  for (fn in c("sum", "mean", "median", "min", "max")) {
    out <- aggregate_regions(mix, g, by = "region", fun = fn)
    expect_identical(out$g[out$region == "Y"], NA_real_, info = fn)
    expect_false(is.na(out$g[out$region == "X"]))          # X still aggregates
  }
  wm <- aggregate_regions(mix, g, by = "region", fun = "weighted_mean",
                          weight = w)
  expect_identical(wm$g[wm$region == "Y"], NA_real_)
  # No warning either: min()/max() used to emit one on an empty group.
  expect_no_warning(aggregate_regions(mix, g, by = "region", fun = "min"))
  expect_no_warning(aggregate_regions(mix, g, by = "region", fun = "max"))
})

test_that("aggregating groups that do have data is unchanged", {
  full <- tibble::tibble(iso3c = c("A", "B", "C", "D"),
                         region = c("X", "X", "Y", "Y"),
                         g = c(1, 3, 10, 20), w = c(1, 3, 1, 1))
  val <- function(fn, ...) {
    o <- aggregate_regions(full, g, by = "region", fun = fn, ...)
    o$g[o$region == "X"]
  }
  expect_equal(val("sum"), 4)
  expect_equal(val("mean"), 2)
  expect_equal(val("median"), 2)
  expect_equal(val("min"), 1)
  expect_equal(val("max"), 3)
  expect_equal(val("weighted_mean", weight = w), 2.5)   # (1*1 + 3*3) / 4
  # A partially-missing group still aggregates the values it has.
  part <- tibble::tibble(iso3c = c("A", "B", "C"), region = "X",
                         g = c(2, NA, 4), w = c(1, 1, 1))
  expect_equal(aggregate_regions(part, g, by = "region", fun = "sum")$g, 6)
  expect_equal(aggregate_regions(part, g, by = "region", fun = "mean")$g, 3)
  expect_equal(aggregate_regions(part, g, by = "region",
                                 fun = "weighted_mean", weight = w)$g, 3)
})

test_that("aggregate_regions warns when handed map geometry", {
  # The polygon backend expands each country into ~400 vertex rows, so a
  # row-wise sum counts it that many times: for the bundled snapshot a regional
  # total of 497,265 became 280,951,373, silently. It cannot de-duplicate on
  # iso3c, because `by = c("region", "year")` roll-ups legitimately repeat a
  # country, so it says what looks wrong instead. Reachable straight off the
  # package's headline call, world_data(geometry = "polygon").
  skip_if_not_installed("maps")
  snap <- countryatlas::world_snapshot$countries
  poly <- suppressWarnings(attach_geometry(snap, geometry = "polygon"))
  expect_warning(aggregate_regions(poly, gdp_per_capita, by = "region"),
                 "map geometry")
  expect_warning(aggregate_regions(poly, gdp_per_capita, by = "region"),
                 class = "countryatlas_warning")
  # Country-level input is silent, and is the answer to trust.
  expect_no_warning(aggregate_regions(snap, gdp_per_capita, by = "region"))
  # A panel with many rows per country is legitimate and must stay silent.
  panel <- tibble::tibble(iso3c = rep(c("USA", "FRA"), each = 2),
                          year = rep(2000:2001, 2), region = rep("X", 4),
                          g = c(1, 2, 3, 4))
  expect_no_warning(aggregate_regions(panel, g, by = c("region", "year")))
  expect_no_warning(aggregate_regions(panel, g, by = "region"))
  expect_equal(aggregate_regions(panel, g, by = "region")$g, 10)
})

test_that("complete_years(value=) does not fill the columns it was not given", {
  # `static <- setdiff(names(data), c("year", value))` counted an unlisted
  # numeric column as a static attribute, so it got carry-filled -- naming
  # *fewer* columns in `value` fabricated *more* data, and even method = "none"
  # ("just complete the grid") invented a figure for the missing year.
  pan <- tibble::tibble(iso3c = "USA", year = c(2000, 2001, 2003),
                        v = c(1, 2, 4), w = c(10, 20, 40),
                        name = "United States")
  for (m in c("none", "locf", "linear")) {
    out <- complete_years(pan, value = "v", method = m)
    expect_identical(out$w, c(10, 20, NA, 40), info = m)
    # The genuinely static attribute is still carried into the invented row.
    expect_identical(unique(out$name), "United States", info = m)
  }
  # The requested column is still filled as asked.
  expect_identical(complete_years(pan, value = "v", method = "none")$v,
                   c(1, 2, NA, 4))
  expect_identical(complete_years(pan, value = "v", method = "locf")$v,
                   c(1, 2, 2, 4))
  expect_identical(complete_years(pan, value = "v", method = "linear")$v,
                   c(1, 2, 3, 4))
  # value = NULL treats every measure as a value, and is unchanged by the fix.
  both <- complete_years(pan, method = "locf")
  expect_identical(both$v, c(1, 2, 2, 4))
  expect_identical(both$w, c(10, 20, 20, 40))
})

test_that("aggregate_regions refuses a weight it would ignore", {
  # `weight` is read only by fun = "weighted_mean". Any other fun silently
  # returned the *unweighted* figure -- on European GDP per capita that is
  # 38,323 against a population-weighted 29,896, a 22% error with nothing to
  # say so. The mirror-image mistake (weighted_mean with no weight) already
  # aborted; this makes the pair symmetric.
  df <- tibble::tibble(iso3c = c("USA", "CAN", "BRA"),
                       region = c("NA", "NA", "LatAm"),
                       gdp = c(21, 1.7, 1.4), pop = c(330, 38, 213))
  for (f in c("sum", "mean", "median", "min", "max")) {
    expect_error(aggregate_regions(df, gdp, by = "region", fun = f, weight = pop),
                 "only used when", info = f)
    expect_error(aggregate_regions(df, gdp, by = "region", fun = f, weight = pop),
                 class = "countryatlas_error", info = f)
  }
  # Without a weight every fun still works, and weighting really does differ.
  expect_s3_class(aggregate_regions(df, gdp, by = "region", fun = "mean"), "tbl_df")
  unw <- aggregate_regions(df, gdp, by = "region", fun = "mean")
  wtd <- aggregate_regions(df, gdp, by = "region", fun = "weighted_mean", weight = pop)
  expect_false(isTRUE(all.equal(unw$gdp, wtd$gdp)))
})
