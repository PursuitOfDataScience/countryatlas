test_that("per_capita divides by a supplied population column", {
  df <- data.frame(iso3c = c("USA", "CHN"), year = 2020L,
                   co2 = c(5e6, 1e7), pop = c(331e6, 1402e6))
  out <- per_capita(df, co2, pop)
  expect_true("co2_per_capita" %in% names(out))
  expect_equal(out$co2_per_capita, df$co2 / df$pop)
})

test_that("per_capita reports a failed population fetch clearly", {
  skip_slow_on_cran()
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
  # NA is the documented answer; the verb now also names the countries it
  # could not index, which is what makes an all-NA column readable.
  expect_warning(out <- index_to(df, gdp, base_year = 1999),
                 class = "countryatlas_no_base_year")
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
  # A zero base is unusable, so this country is reported like any other the
  # verb cannot index.
  expect_warning(out <- index_to(df, gdp, base_year = 2000),
                 class = "countryatlas_no_base_year")
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
  skip_slow_on_cran()
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
  # Pooling the years is warned about (class countryatlas_panel); that is
  # not what this test is about, so the warning is muffled by class.
  pooled <- function(x) {
    withCallingHandlers(rank_countries(x, g), countryatlas_panel = function(w)
      invokeRestart("muffleWarning"))
  }
  expect_equal(flat(pooled(grp)), flat(pooled(panel)))
  # The 3.0.0 verbs postdate this test, and rank_countries()'s comment claims
  # "every other function here likewise imposes its own grouping" -- so check
  # them rather than take the claim.
  expect_equal(flat(interpolate_missing(grp, "g")),
               flat(interpolate_missing(panel, "g")))
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
    # smooth_rates() joined these once its pooled prior started reading one row
    # per country rather than every row of the panel.
    expect_equal(flat(smooth_rates(grp, g, population)),
                 flat(smooth_rates(panel, g, population)))
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
                   index_to(grp, g, base_year = 2000),
                   rank_countries(grp, g, within = "year"),
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
  # min_coverage = 0 isolates the empty-group contract from the coverage
  # rule, which would withhold Y anyway and say so.
  for (fn in c("sum", "mean", "median", "min", "max")) {
    out <- aggregate_regions(mix, g, by = "region", fun = fn, min_coverage = 0)
    expect_identical(out$g[out$region == "Y"], NA_real_, info = fn)
    expect_false(is.na(out$g[out$region == "X"]))          # X still aggregates
  }
  wm <- aggregate_regions(mix, g, by = "region", fun = "weighted_mean",
                          weight = w, min_coverage = 0)
  expect_identical(wm$g[wm$region == "Y"], NA_real_)
  # No base-R warning either: min()/max() used to emit one on an empty group.
  expect_no_warning(aggregate_regions(mix, g, by = "region", fun = "min",
                                      min_coverage = 0))
  expect_no_warning(aggregate_regions(mix, g, by = "region", fun = "max",
                                      min_coverage = 0))
  # Under the default rule the empty group is named, by class.
  expect_warning(aggregate_regions(mix, g, by = "region", fun = "min"),
                 class = "countryatlas_low_coverage")
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
  skip_slow_on_cran()
  # The polygon backend expands each country into ~400 vertex rows, so a
  # row-wise sum counts it that many times: for the bundled snapshot a regional
  # total of 497,265 became 280,951,373, silently. It cannot de-duplicate on
  # iso3c, because `by = c("region", "year")` roll-ups legitimately repeat a
  # country, so it says what looks wrong instead. Reachable straight off the
  # package's headline call, world_data(geometry = "polygon").
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
  skip_slow_on_cran()
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
  skip_slow_on_cran()
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

test_that("growth_rate computes yoy and cagr per country", {
  df <- data.frame(iso3c = "USA", year = 2000:2002, gdp = c(100, 110, 121))
  g <- growth_rate(df, gdp)
  expect_equal(g$gdp_growth, c(NA, 0.1, 0.1))
  cg <- growth_rate(df, gdp, type = "cagr")
  expect_equal(round(cg$gdp_growth[3], 4), 0.1)
})

test_that("index_to rebases each country to the base year", {
  df <- data.frame(iso3c = "USA", year = 2000:2002, gdp = c(50, 55, 60))
  out <- index_to(df, gdp, base_year = 2000)
  expect_equal(out$gdp_index, c(100, 110, 120))
})

test_that("share_of_world sums to one within a year", {
  df <- data.frame(iso3c = c("USA", "CHN"), co2 = c(5, 15))
  out <- share_of_world(df, co2)
  expect_equal(out$co2_share, c(0.25, 0.75))
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

test_that("weighted_mean returns NA, not NaN, when the weights sum to zero", {
  # The unweighted branch goes to some length to turn an empty group into NA --
  # sum() would say 0, mean() NaN, min()/max() -Inf/Inf, each of which reads as
  # a real figure for a region we have no data for. weighted_mean() had the
  # same hole: weighted.mean() divides by the total weight, so all-zero (or
  # cancelling) weights came back NaN.
  g <- function(v, w) {
    d <- tibble::tibble(iso3c = c("A", "B"), region = "R",
                        v = as.numeric(v), w = as.numeric(w))
    aggregate_regions(d, v, "region", fun = "weighted_mean", weight = w,
                      min_coverage = 0)$v[1]
  }
  expect_true(is.na(g(c(10, 20), c(0, 0))))
  expect_false(is.nan(g(c(10, 20), c(0, 0))))
  expect_true(is.na(g(c(10, 20), c(5, -5))))   # cancel to zero
  expect_true(is.na(g(c(NA, NA), c(1, 3))))
  # Unchanged where there is weight to go on.
  expect_equal(g(c(10, 20), c(1, 3)), 17.5)
  expect_equal(g(c(10, NA), c(1, 3)), 10)
})

test_that("a repeated country-year is reported before it corrupts a lag", {
  skip_slow_on_cran()
  # Every panel verb here reads neighbouring rows. With France's 2019 present
  # twice (20 and 999), lag_by_country() lagged 2020 against the duplicate
  # rather than the real 2019, and diff_by_country() and growth_rate() turned
  # that into confident nonsense -- a difference of 979 and 4895% growth --
  # with nothing to say the input was malformed.
  dup <- tibble::tibble(iso3c = rep("FRA", 4),
                        year = c(2018L, 2019L, 2019L, 2020L),
                        v = c(10, 20, 999, 30))
  clean <- tibble::tibble(iso3c = rep("FRA", 3), year = 2018:2020,
                          v = c(10, 20, 30))

  expect_warning(growth_rate(dup, v), "repeated country-year")
  expect_warning(index_to(dup, v, base_year = 2018), "repeated country-year")
  expect_warning(lag_by_country(dup, v), "repeated country-year")
  expect_warning(diff_by_country(dup, v), "repeated country-year")
  expect_warning(complete_years(dup, value = "v"), "repeated country-year")
  # It names the offending key.
  expect_warning(lag_by_country(dup, v), "FRA 2019")

  for (f in list(growth_rate, lag_by_country, diff_by_country)) {
    expect_no_warning(f(clean, v))
  }
  expect_no_warning(index_to(clean, v, base_year = 2018))
  expect_no_warning(complete_years(clean, value = "v"))
  # NA keys are not duplicates of one another.
  nas <- tibble::tibble(iso3c = c(NA, NA), year = c(NA_integer_, NA_integer_),
                        v = c(1, 2))
  expect_no_warning(countryatlas:::check_panel_unique(nas))
})

test_that("complete_years names a non-numeric year column", {
  # The `years` argument is checked carefully; the `year` column was not. A
  # character one reached dplyr's "Can't join `x$year` with `y$year` due to
  # incompatible types" -- naming dplyr's internals, not the column -- and a
  # factor got base R's bare "'min' not meaningful for factors". Both come
  # straight out of a CSV read.
  mk <- function(y) tibble::tibble(iso3c = rep("FRA", 3), year = y,
                                   v = c(10, 20, 30))
  expect_error(complete_years(mk(c("2018", "2019", "2020")), value = "v"),
               '"year" must be numeric')
  expect_error(complete_years(mk(factor(c("2018", "2019", "2020"))),
                              value = "v"), '"year" must be numeric')
  # Both numeric flavours still work.
  expect_equal(nrow(complete_years(mk(2018:2020), value = "v")), 3L)
  expect_equal(nrow(complete_years(mk(c(2018, 2019, 2020)), value = "v")), 3L)
})

# --- independent validation of the inequality measures -------------------
#
# Same reasoning as the spdep section above: gini() and theil() are formulas
# that can be subtly wrong and still look plausible, and the existing tests
# check small hand-computed cases plus "weighted differs from unweighted" --
# neither of which would catch a weighting or decomposition error. There is no
# reference package worth a dependency here, so the references are written out
# from the definitions.

test_that("gini and theil match their definitions", {
  set.seed(7)
  # Gini as the mean absolute difference over twice the mean.
  gini_ref <- function(x) {
    x <- sort(x[is.finite(x) & x > 0]); n <- length(x)
    sum(outer(x, x, function(a, b) abs(a - b))) / (2 * n^2 * mean(x))
  }
  # Theil T as the mean of (x/xbar) log(x/xbar).
  theil_ref <- function(x) {
    x <- x[is.finite(x) & x > 0]; r <- x / mean(x); mean(r * log(r))
  }
  snap_gdp <- stats::na.omit(world_snapshot$countries$gdp_per_capita)
  cases <- list(
    uniform   = rep(5, 20),               # degenerate: both must be 0
    lognormal = exp(stats::rnorm(200)),
    pareto    = (1 - stats::runif(200))^(-1 / 1.5),
    two_point = c(rep(1, 90), rep(100, 10)),
    snapshot  = snap_gdp)
  for (nm in names(cases)) {
    x <- cases[[nm]]
    expect_equal(gini(x), gini_ref(x), tolerance = 1e-12, info = nm)
    expect_equal(theil(x), theil_ref(x), tolerance = 1e-12, info = nm)
  }
  expect_equal(gini(cases$uniform), 0)
  expect_equal(theil(cases$uniform), 0)
})

test_that("the weighted and decomposed paths match their definitions too", {
  set.seed(11)
  gini_w <- function(x, w) {
    mu <- sum(w * x) / sum(w)
    sum(outer(w, w) * outer(x, x, function(a, b) abs(a - b))) /
      (2 * sum(w)^2 * mu)
  }
  theil_w <- function(x, w) {
    mu <- sum(w * x) / sum(w); r <- x / mu
    sum(w * r * log(r)) / sum(w)
  }
  x <- exp(stats::rnorm(80)); w <- stats::runif(80, 1, 100)
  expect_equal(gini(x, weights = w), gini_w(x, w), tolerance = 1e-12)
  expect_equal(theil(x, weights = w), theil_w(x, w), tolerance = 1e-12)
  # Unit weights must reproduce the unweighted answer exactly.
  expect_equal(gini(x, weights = rep(1, length(x))), gini(x))
  expect_equal(theil(x, weights = rep(1, length(x))), theil(x))

  # Theil's decomposition, on real population-weighted GDP by continent.
  s <- world_snapshot$countries
  ok <- !is.na(s$gdp_per_capita) & !is.na(s$population) & !is.na(s$continent)
  xv <- s$gdp_per_capita[ok]; wv <- s$population[ok]; gv <- s$continent[ok]
  mu <- sum(wv * xv) / sum(wv)
  gs <- split(seq_along(xv), gv)
  share <- function(i) sum(wv[i]) / sum(wv)
  mug <- function(i) sum(wv[i] * xv[i]) / sum(wv[i])
  between <- sum(vapply(gs, function(i) share(i) * (mug(i) / mu) *
                          log(mug(i) / mu), numeric(1)))
  within <- sum(vapply(gs, function(i) {
    tg <- sum(wv[i] * (xv[i] / mug(i)) * log(xv[i] / mug(i))) / sum(wv[i])
    share(i) * (mug(i) / mu) * tg
  }, numeric(1)))

  out <- theil(xv, weights = wv, groups = gv)
  expect_equal(out$value[out$component == "between"], between, tolerance = 1e-12)
  expect_equal(out$value[out$component == "within"], within, tolerance = 1e-12)
  # The identity the decomposition exists for.
  expect_equal(out$value[out$component == "total"], between + within,
               tolerance = 1e-12)
  expect_equal(sum(out$share[out$component != "total"]), 1, tolerance = 1e-12)
})

test_that("complete_years rejects a missing year", {
  # The span is inferred with seq(min(year), max(year)), so a single NA gave
  # base R's "'from' must be a finite number" -- naming neither the column nor
  # the package. The `years` argument has been checked for NA all along; the
  # column it defaults from had not, and one blank cell in a CSV is enough.
  mk <- function(y) tibble::tibble(iso3c = rep("FRA", length(y)), year = y,
                                   v = seq_along(y))
  expect_error(complete_years(mk(c(2000L, NA)), value = "v"),
               "must not contain missing values")
  expect_error(complete_years(mk(c(NA_integer_, NA_integer_)), value = "v"),
               "must not contain missing values")
  # The working paths are untouched, including the two that never reach seq().
  expect_equal(nrow(complete_years(mk(c(2000L, 2002L)), value = "v")), 3L)
  expect_equal(nrow(complete_years(mk(integer(0)), value = "v")), 0L)
  expect_equal(nrow(complete_years(mk(c(2000L, 2002L)), years = 2000:2002,
                                   value = "v")), 3L)
})

test_that("gini and theil say why they return NA", {
  # Both carried a comment stating the convention -- "NA plus a word about why
  # (as for zero weights)" -- while the line beneath returned NA in silence for
  # exactly those cases, so an all-zero column and zero weights came back
  # indistinguishable from a missing input.
  expect_warning(g0 <- gini(rep(0, 6)), class = "countryatlas_undefined_index")
  expect_true(is.na(g0))
  expect_warning(gini(rep(0, 6)), "Every value is zero")
  expect_warning(gw <- gini(c(1, 2, 3), weights = c(0, 0, 0)),
                 class = "countryatlas_undefined_index")
  expect_true(is.na(gw))
  expect_warning(gini(c(1, 2, 3), weights = c(0, 0, 0)), "sum to zero")
  expect_warning(tw <- theil(c(1, 2, 3), weights = c(0, 0, 0)),
                 class = "countryatlas_undefined_index")
  expect_true(is.na(tw))

  # Perfect equality is 0, not undefined, and stays silent.
  expect_silent(g <- gini(rep(5, 6)))
  expect_equal(g, 0)
  expect_silent(t <- theil(rep(5, 6)))
  expect_equal(t, 0)
  # Ordinary values are unaffected.
  expect_silent(expect_equal(gini(c(1, 2, 3, 4)), 0.25))
  expect_silent(expect_gt(theil(c(1, 2, 3, 4)), 0))
})

test_that("sigma_convergence explains an empty or blank series", {
  skip_slow_on_cran()
  # The positive-value filter is documented (`n` counts what survived), but two
  # of its outcomes were not: an all-non-positive column came back as a 0-row
  # tibble, and a year with one country got sigma = NA from sd() -- both in
  # silence, so an empty or blank convergence series looked like a result.
  mk <- function(n_c, n_y, val) do.call(rbind, lapply(seq_len(n_y), function(i)
    data.frame(iso3c = paste0("C", seq_len(n_c)), year = 1999L + i, v = val)))

  expect_warning(z <- sigma_convergence(mk(6, 5, 0), v),
                 class = "countryatlas_no_positive")
  expect_equal(nrow(z), 0L)
  expect_named(z, c("year", "n", "sigma"))         # shape is still the contract

  expect_warning(one <- sigma_convergence(mk(1, 3, 1), v),
                 class = "countryatlas_thin_year")
  expect_equal(nrow(one), 3L)
  expect_true(all(is.na(one$sigma)))
  # Both agreements sit on the count, in the singular as well as the plural.
  expect_warning(sigma_convergence(mk(1, 3, 1), v),
                 "3 years have fewer than two countries")
  thin1 <- rbind(data.frame(iso3c = "C1", year = 2000L, v = 5),
                 data.frame(iso3c = paste0("C", 1:4), year = 2001L, v = 1:4))
  expect_warning(sigma_convergence(thin1, v),
                 "1 year has fewer than two countries")

  # An ordinary panel is silent on both measures.
  ok <- mk(6, 5, c(1, 2, 3, 4, 5, 6))
  expect_silent(s <- sigma_convergence(ok, v))
  expect_equal(nrow(s), 5L)
  expect_true(all(is.finite(s$sigma)))
  expect_silent(sigma_convergence(ok, v, measure = "cv"))
})

test_that("per_capita gives NA, not Inf, for an unusable population", {
  skip_slow_on_cran()
  # deflate() and to_ppp() were fixed for this under a test literally called
  # "an unusable deflator or PPP factor gives NA, not Inf", whose comment notes
  # that Inf "propagated silently into every scale and summary downstream".
  # per_capita() is the most used of the family and never got the fix: a zero
  # population produced Inf, in silence.
  d <- function(pop) data.frame(iso3c = paste0("C", seq_along(pop)),
                                year = 2000L, v = seq_along(pop), pop = pop)

  expect_warning(one <- per_capita(d(c(0, 1e4, 1e5)), v, pop),
                 class = "countryatlas_unusable_rows")
  expect_false(any(is.infinite(one$v_per_capita)))
  expect_true(is.na(one$v_per_capita[1]))
  expect_equal(one$v_per_capita[2:3], c(2, 3) / c(1e4, 1e5))
  expect_warning(per_capita(d(c(0, 1e4, 1e5)), v, pop), "1 row has")
  # Zero and missing count as unusable; negative does not.
  expect_warning(per_capita(d(c(0, NA, 1e5)), v, pop), "2 rows have")

  # A *negative* population passes straight through, and silently: that is
  # pinned deliberately by "share_of_world and per_capita pass through odd but
  # valid values" -- negative values are the caller's business and the
  # arithmetic stays honest. Only division by zero is unreportable.
  expect_silent(neg <- per_capita(d(c(-1e3, 1e4, 1e5)), v, pop))
  expect_equal(neg$v_per_capita[1], 1 / -1e3)
  # A missing population has nothing to divide by, so it is NA and says so.
  expect_warning(nap <- per_capita(d(c(NA, 1e4, 1e5)), v, pop),
                 class = "countryatlas_unusable_rows")
  expect_true(is.na(nap$v_per_capita[1]))

  # Nothing usable at all is reported as such.
  expect_warning(none <- per_capita(d(c(0, 0, 0)), v, pop),
                 class = "countryatlas_no_rates")
  expect_true(all(is.na(none$v_per_capita)))

  # Ordinary input is untouched and silent.
  expect_silent(ok <- per_capita(d(c(1e3, 1e4, 1e5)), v, pop))
  expect_equal(ok$v_per_capita, c(1, 2, 3) / c(1e3, 1e4, 1e5))
})

test_that("rank_countries and share_of_world report a repeated country-year", {
  skip_slow_on_cran()
  # interpolate_missing() and complete_years() already report this shape, but
  # the two verbs that *aggregate across* rows did not -- and their output is
  # the harder to reconcile. On a frame with USA-2020 duplicated,
  # rank_countries() gave the same country ranks 1 and 3, and share_of_world()
  # gave it shares 0.1 and 0.7 against a total that counted it twice.
  dup <- rbind(data.frame(iso3c = c("USA", "FRA"), year = 2020L, v = c(10, 20)),
               data.frame(iso3c = "USA", year = 2020L, v = 70))
  ok <- data.frame(iso3c = c("USA", "FRA"), year = 2020L, v = c(10, 20))

  expect_warning(rank_countries(dup, v), "repeated country-year")
  expect_warning(rank_countries(dup, v), "ranked twice")
  expect_warning(share_of_world(dup, v), "repeated country-year")
  expect_warning(share_of_world(dup, v), "counted twice in the total")
  # The reason is verb-specific: the lag family reads neighbouring rows, these
  # two aggregate across them, and naming the wrong consequence would mislead.
  # Each country here has one year, so the year-keyed lag is also empty, and
  # says so.
  expect_warning(expect_warning(lag_by_country(dup, v), "read neighbouring rows"),
                 "came out NA")

  # Both verbs also accept a *cross-section*, where `year` is absent. Reaching
  # for data$year there warned "Unknown or uninitialised column" and, worse,
  # paste(iso3c, NULL) collapses to iso3c alone -- so two years of one country
  # would have been reported as a repeat, and the bundled snapshot (no year
  # column at all) would have warned on every call.
  xs <- data.frame(iso3c = c("USA", "FRA"), v = c(10, 20))
  expect_silent(rank_countries(xs, v))
  expect_silent(share_of_world(xs, v))
  expect_silent(rank_countries(world_snapshot$countries, gdp_per_capita))
  expect_silent(share_of_world(world_snapshot$countries, population))
  two_years <- data.frame(iso3c = c("USA", "USA"), year = c(2020L, 2021L),
                          v = c(1, 2))
  # Not a repeat. Pooled, the ranks carry the panel warning and nothing else;
  # within each year, nothing at all.
  expect_s3_class(tryCatch(rank_countries(two_years, v), warning = identity),
                  "countryatlas_panel")
  expect_silent(rank_countries(two_years, v, within = year))

  # But a cross-section is keyed on the country alone, so iso3c twice there is
  # a real repeat -- skipping year-less frames outright would have let
  # rank_countries() hand one country two ranks in silence. The noun follows
  # the key.
  xs_dup <- data.frame(iso3c = c("USA", "USA", "FRA"), v = c(1, 999, 5))
  expect_warning(rank_countries(xs_dup, v), "repeated country\\b")
  expect_warning(share_of_world(xs_dup, v), "repeated country\\b")
  xs_dup2 <- data.frame(iso3c = c("USA", "USA", "FRA", "FRA"), v = 1:4)
  expect_warning(rank_countries(xs_dup2, v), "2 repeated countries")

  # A well-formed panel stays silent, and the numbers are unchanged.
  expect_silent(r <- rank_countries(ok, v))
  expect_equal(r$rank, c(2L, 1L))
  expect_silent(s <- share_of_world(ok, v))
  expect_equal(sum(s$v_share), 1)
})

test_that("index_to says base_year is required, as deflate does", {
  skip_slow_on_cran()
  d <- data.frame(iso3c = c("FRA", "FRA"), year = c(2000L, 2001L),
                  gdp = c(100, 110), defl = c(90, 100))
  # It reached check_number() and gave base R's 'argument "base_year" is
  # missing, with no default'.
  expect_error(index_to(d, gdp), "`base_year` is required",
               class = "countryatlas_error")
  expect_error(deflate(d, gdp, deflator = defl), "`base_year` is required")
  # `value` is still reported first when both are missing.
  expect_error(index_to(d), "`value` is required")
  # The numeric-only contract is deliberate and unchanged: index_to() is
  # per-country, so a base year no country has is NA rather than an error, and
  # the message names the value the caller actually supplied.
  expect_error(index_to(d, gdp, base_year = NA), "single finite number")
  err <- tryCatch(index_to(d, gdp, base_year = as.Date("2000-01-01")),
                  error = function(e) e)
  expect_match(cli::ansi_strip(conditionMessage(err)), "2000-01-01",
               fixed = TRUE)
  expect_true(all(is.na(suppressWarnings(
    index_to(d, gdp, base_year = 1999))$gdp_index)))
})

test_that("a panel verb that computes nothing says so", {
  skip_slow_on_cran()
  cs <- data.frame(iso3c = c("FRA", "DEU", "ESP"), year = 2000L,
                   gdp = c(1, 2, 3))
  # One year per country: there is no earlier value, so the derived column is
  # NA throughout and the verb accomplished nothing. It used to say nothing.
  for (call in list(
    function() growth_rate(cs, "gdp"),
    function() growth_rate(cs, "gdp", type = "cagr"),
    function() lag_by_country(cs, "gdp"),
    function() diff_by_country(cs, "gdp"))) {
    expect_warning(call(), class = "countryatlas_all_na_result")
  }
  # The message states what the verb needs, with the count agreeing.
  msg <- function(w) {
    gsub("[[:space:]]+", " ",
         cli::ansi_strip(paste(conditionMessage(w), collapse = " ")))
  }
  expect_match(msg(tryCatch(lag_by_country(cs, "gdp", n = 3),
                            warning = function(w) w)),
               "A lag of 3 needs 4 years", fixed = TRUE)
  expect_match(msg(tryCatch(diff_by_country(cs, "gdp", n = 1),
                            warning = function(w) w)),
               "over 1 year needs", fixed = TRUE)
  expect_match(msg(tryCatch(diff_by_country(cs, "gdp", n = 2),
                            warning = function(w) w)),
               "over 2 years needs", fixed = TRUE)

  # An ordinary panel is silent: only the first year per country is NA.
  pan <- rbind(cs, transform(cs, year = 2001L, gdp = c(2, 3, 4)))
  expect_no_warning(growth_rate(pan, "gdp"))
  expect_no_warning(lag_by_country(pan, "gdp"))
  expect_no_warning(diff_by_country(pan, "gdp"))
  # ...and so is a mixed frame where any country has enough years.
  expect_no_warning(
    lag_by_country(rbind(cs, data.frame(iso3c = "FRA", year = 2001L, gdp = 9)),
                   "gdp"))
  # index_to() keeps its own documented behaviour: NA per country, no notice.
  expect_no_warning(index_to(cs, "gdp", base_year = 2000))
})

test_that("share_of_world reports a total it cannot use", {
  skip_slow_on_cran()
  mk <- function(v, y = 2000L) {
    data.frame(iso3c = c("FRA", "DEU", "ESP"), year = y, gdp = v)
  }
  # per_capita() and to_ppp() report an unusable denominator; this returned a
  # column of NA in silence, which reads as "no share" rather than "no total".
  expect_warning(share_of_world(mk(c(0, 0, 0)), "gdp"),
                 class = "countryatlas_no_rates")
  expect_warning(share_of_world(mk(c(-5, 0, 5)), "gdp"),
                 class = "countryatlas_no_rates")
  expect_warning(share_of_world(mk(c(1, Inf, 3)), "gdp"),
                 class = "countryatlas_no_rates")
  # A usable total stays silent, and the arithmetic is untouched.
  expect_no_warning(out <- share_of_world(mk(c(1, 2, 3)), "gdp"))
  expect_equal(out$gdp_share, c(1, 2, 3) / 6)

  # On a panel only the unusable years go NA, and the message names them.
  pan <- rbind(mk(c(1, 2, 3), 2000L), mk(c(0, 0, 0), 2001L))
  w <- tryCatch(share_of_world(pan, "gdp"), warning = function(x) x)
  expect_s3_class(w, "countryatlas_unusable_rows")
  msg <- gsub("[[:space:]]+", " ",
              cli::ansi_strip(paste(conditionMessage(w), collapse = " ")))
  expect_match(msg, "1 year", fixed = TRUE)     # agrees at n = 1
  expect_match(msg, "2001", fixed = TRUE)
  expect_match(msg, "3 rows", fixed = TRUE)
  got <- suppressWarnings(share_of_world(pan, "gdp"))
  expect_equal(got$gdp_share[got$year == 2000L], c(1, 2, 3) / 6)
  expect_true(all(is.na(got$gdp_share[got$year == 2001L])))

  # ...and agrees at n = 2 as well.
  pan2 <- rbind(pan, mk(c(0, 0, 0), 2002L))
  w2 <- tryCatch(share_of_world(pan2, "gdp"), warning = function(x) x)
  expect_match(gsub("[[:space:]]+", " ",
                    cli::ansi_strip(paste(conditionMessage(w2), collapse = " "))),
               "2 years", fixed = TRUE)
})

test_that("a duplicated column name is named, not left to tibble", {
  skip_slow_on_cran()
  # read.csv(check.names = FALSE) on a sheet with two `gdp` headers. Ten verbs
  # leaked tibble's ".name_repair" message; per_capita() and to_ppp() silently
  # computed from the first and dropped the second.
  mk <- function() {
    d <- data.frame(iso3c = c("FRA", "DEU", "ESP", "ITA"), year = 2000L,
                    gdp = c(1, 2, 3, 4), pop = c(10, 20, 30, 40))
    d$gdp2 <- c(9, 9, 9, 9)
    names(d)[names(d) == "gdp2"] <- "gdp"
    d
  }
  expect_equal(sum(duplicated(names(mk()))), 1L)
  verbs <- list(
    per_capita          = function(x) per_capita(x, "gdp", "pop"),
    share_of_world      = function(x) share_of_world(x, "gdp"),
    index_to            = function(x) index_to(x, "gdp", 2000),
    growth_rate         = function(x) growth_rate(x, "gdp"),
    rank_countries      = function(x) rank_countries(x, "gdp"),
    lag_by_country      = function(x) lag_by_country(x, "gdp"),
    diff_by_country     = function(x) diff_by_country(x, "gdp"),
    to_ppp              = function(x) to_ppp(x, "gdp", "pop"),
    deflate             = function(x) deflate(x, "gdp", 2000, "pop"),
    complete_years      = function(x) complete_years(x, 2000:2001, "gdp"),
    aggregate_regions   = function(x) aggregate_regions(x, "gdp", by = "iso3c"),
    world_table         = function(x) world_table(x, "gdp"),
    audit_coverage      = function(x) audit_coverage(x, "gdp")
  )
  for (nm in names(verbs)) {
    err <- tryCatch(suppressWarnings(suppressMessages(verbs[[nm]](mk()))),
                    error = function(e) e)
    expect_s3_class(err, "countryatlas_error")
    msg <- cli::ansi_strip(paste(conditionMessage(err), collapse = " "))
    expect_match(msg, "gdp", fixed = TRUE, label = paste(nm, "names the column"))
    expect_false(grepl(".name_repair", msg, fixed = TRUE),
                 label = paste(nm, "leaks tibble internals"))
  }
  # interpolate_missing() keeps its own tailored wording.
  expect_error(interpolate_missing(mk(), "gdp"), "duplicated column name")
  # A frame with unique names is untouched.
  ok <- mk()
  names(ok)[5] <- "gdp_alt"
  expect_no_error(per_capita(ok, "gdp", "pop"))
  expect_no_error(rank_countries(ok, "gdp"))
})

test_that("complete_years keeps sf and gives invented years real geometry", {
  skip_slow_on_cran()
  skip_if_no_sf_geometry()
  iso <- c("USA", "FRA", "DEU", "BRA")
  d <- expand.grid(iso3c = iso, year = 2000:2002, stringsAsFactors = FALSE)
  d$gdp <- as.numeric(seq_len(nrow(d)))
  g <- world_geometry(geometry = "sf")
  g <- g[g$iso3c %in% iso, c("iso3c", "geometry")]
  sfp <- sf::st_as_sf(merge(d, g, by = "iso3c"))

  out <- suppressWarnings(complete_years(sfp, 2000:2004, "gdp"))
  # tidyr::complete() drops the class while leaving a live sfc column behind,
  # so the frame looked fine and st_bbox() refused it.
  expect_s3_class(out, "sf")
  expect_silent(sf::st_bbox(out))
  expect_equal(nrow(out), length(iso) * 5L)

  # complete() gives an invented row an *empty* geometry, not NA, so fill()
  # skipped it and the completed years rendered blank.
  expect_equal(sum(sf::st_is_empty(out)), 0L)
  # Each country keeps its own shape rather than borrowing a neighbour's.
  expect_equal(length(unique(sf::st_as_text(sf::st_geometry(out)))), length(iso))
  fr <- out[out$iso3c == "FRA", ]
  expect_equal(length(unique(sf::st_as_text(sf::st_geometry(fr)))), 1L)

  # The values that were already there are untouched.
  m <- merge(sf::st_drop_geometry(out), sf::st_drop_geometry(sfp),
             by = c("iso3c", "year"), suffixes = c("", ".in"))
  expect_equal(m$gdp, m$gdp.in)
  # A non-sf panel still comes back as a plain tibble.
  expect_false(inherits(complete_years(d, 2000:2004, "gdp"), "sf"))
})

test_that("a missing year does not decide an answer by row order", {
  # `year == base_year` is NA for a missing year, and x[c(NA, TRUE)] returns an
  # NA element *before* the real match, so [1] picked up the NA and indexed
  # the whole country to NA. Which happened depended on row order: the same
  # three rows gave 100/150/50 with the missing year last and NA/NA/NA with it
  # first.
  first <- data.frame(iso3c = "USA", year = c(NA, 2000L, 2001L),
                      v = c(10, 20, 30))
  last <- data.frame(iso3c = "USA", year = c(2000L, 2001L, NA),
                     v = c(20, 30, 10))
  expect_equal(index_to(first, v, 2000)$v_index, c(50, 100, 150))
  expect_equal(index_to(last, v, 2000)$v_index, c(100, 150, 50))
  # Both are the same three observations, so both must index off the same base.
  expect_setequal(index_to(first, v, 2000)$v_index,
                  index_to(last, v, 2000)$v_index)
  # A base year that is genuinely absent is still NA, as documented.
  absent <- data.frame(iso3c = "USA", year = c(2001L, 2002L), v = c(20, 30))
  expect_true(all(is.na(suppressWarnings(
    index_to(absent, v, 2000))$v_index)))
})

test_that("an optional column argument is validated like a required one", {
  skip_slow_on_cran()
  # quo_arg_name() says it covers "every unquoted column argument in the
  # package", and for the *required* ones it did. Thirteen optional ones --
  # per_capita(pop), aggregate_regions(weight), rank_countries(within),
  # flow_matrix(weight), flow_map(weight), bubble_map(color),
  # cartogram_map(fill), gridded_cartogram(fill), cartogram_diagnostics(weight),
  # interactive_map(tooltip), animate_world(time), join_world(country_col) --
  # called rlang::as_name() directly, so an expression reached the user as
  # rlang's own "Can't convert a call to a string". In several functions the
  # required argument was checked and the optional one beside it was not:
  # bubble_map() validated `size` but not `color`, flow_map() validated
  # `from`/`to` but not `weight`.
  snap <- world_snapshot$countries
  snap$w <- 1
  d <- data.frame(iso3c = rep(c("USA", "FRA"), each = 3),
                  year = rep(2018:2020, 2), v = c(1, 2, 3, 4, 5, 6),
                  p = c(10, 10, 10, 20, 20, 20), q = c(2, 2, 2, 3, 3, 3),
                  region = "Europe")
  fl <- data.frame(from = "USA", to = "FRA", q = 1)

  expect_error(per_capita(d, v, pop = p * 2), "must name a column")
  expect_error(aggregate_regions(d, v, fun = "weighted_mean", weight = p * 2),
               "must name a column")
  expect_error(rank_countries(d, v, within = q * 2), "must name a column")
  expect_error(flow_matrix(fl, from, to, q * 2), "must name a column")
  expect_error(flow_map(fl, from, to, q * 2), "must name a column")
  expect_error(bubble_map(snap, population, color = w * 2), "must name a column")
  expect_error(gridded_cartogram(snap, population, fill = w * 2),
               "must name a column")
  expect_error(animate_world(d, v, time = year * 2), "must name a column")
  expect_error(join_world(data.frame(nm = "France"), country_col = nm * 2,
                          geometry = "none"), "must name a column")
  # Each names its own argument, not rlang's.
  expect_match(cli::ansi_strip(conditionMessage(tryCatch(
    bubble_map(snap, population, color = w * 2), error = identity))),
    "`color`", fixed = TRUE)

  # An optional column that does not exist was equally unchecked in three of
  # them: per_capita() left pop_vec NULL and failed with base R's "replacement
  # has 0 rows, data has 4".
  expect_error(per_capita(d, v, pop = nosuch), class = "countryatlas_error")
  expect_error(aggregate_regions(d, v, fun = "weighted_mean", weight = nosuch),
               class = "countryatlas_error")
  expect_error(rank_countries(d, v, within = nosuch),
               class = "countryatlas_error")

  # The legitimate forms all still work, including `within`'s deliberate
  # character-vector path -- c("region", "year") is a call, so as_name() cannot
  # read it and the names must be evaluated.
  expect_s3_class(per_capita(d, v, pop = p), "data.frame")
  expect_s3_class(aggregate_regions(d, v, fun = "weighted_mean", weight = p),
                  "data.frame")
  expect_s3_class(rank_countries(d, v, within = region), "data.frame")
  expect_s3_class(rank_countries(d, v, within = c("region")), "data.frame")
  expect_s3_class(rank_countries(d, v, within = c("region", "year")),
                  "data.frame")
  # The bundled snapshot has five microstates with no centroid, which
  # bubble_map() reports by design and another test pins.
  expect_s3_class(suppressWarnings(bubble_map(snap, population, color = w)),
                  "ggplot")
  expect_s3_class(join_world(data.frame(nm = "France"), country_col = "nm",
                             geometry = "none"), "data.frame")
})

test_that("aggregate_regions handles an sf frame instead of crashing", {
  skip_slow_on_cran()
  # An sf frame carries one row per country, so the totals are right -- but
  # dplyr's sf-aware summarise() unions the geometries per group, and two of
  # the bundled Natural Earth polygons (SDN, MOZ) are invalid, so this died
  # with the raw GEOS error "TopologyException: side location conflict". It also drew
  # the "counts each country once per geometry row" warning, which is true of a
  # polygon frame and false of an sf one.
  skip_if_no_sf_geometry()
  snap <- world_snapshot$countries
  gsf <- suppressWarnings(join_world(snap, geometry = "sf"))

  expect_silent(out <- aggregate_regions(gsf, population, by = "region"))
  expect_s3_class(out, "tbl_df")
  expect_false(inherits(out, "sf"))
  # Identical to dropping the geometry by hand, which is what it now does.
  expect_equal(out,
               suppressWarnings(aggregate_regions(sf::st_drop_geometry(gsf),
                                                  population, by = "region")))
  # A polygon frame still warns: there the vertex hazard is real.
  poly <- suppressWarnings(join_world(snap))
  expect_warning(aggregate_regions(poly, population, by = "region"),
                 "geometry")
  # And a frame that is sf *and* carries long/lat/group must still warn:
  # dropping the geometry leaves the vertex rows behind, so guarding the check
  # as the `else` of the sf branch skipped exactly the frame whose totals are
  # inflated.
  hybrid <- gsf
  hybrid$long <- 0
  hybrid$lat <- 0
  hybrid$group <- seq_len(nrow(gsf))
  expect_warning(aggregate_regions(hybrid, population, by = "region"),
                 "geometry")
})

test_that("per_capita survives an all-NA year column", {
  # min()/max() of an empty vector gave start = Inf and a bogus WDI request.
  df <- data.frame(iso3c = c("USA", "CHN"), year = NA_integer_,
                   co2 = c(5e6, 1e7), pop = c(331e6, 1402e6))
  out <- per_capita(df, co2, pop)
  expect_true("co2_per_capita" %in% names(out))
  # Without an explicit pop the fetch is mocked, so no network is touched; the
  # point is that `start`/`end` are finite years, not Inf.
  seen <- NULL
  testthat::local_mocked_bindings(
    fetch_wdi = function(indicator, start, end, ...) {
      seen <<- c(start = start, end = end)
      tibble::tibble(iso3c = c("USA", "CHN"), year = NA_integer_,
                     .wdj_pop = c(331e6, 1402e6))
    }
  )
  # The stub returns NA years, so nothing joins and the population is unusable
  # -- which per_capita() now reports rather than handing back a blank column.
  expect_warning(out2 <- per_capita(df[, c("iso3c", "year", "co2")], co2),
                 class = "countryatlas_no_rates")
  expect_true(all(is.finite(seen)))
  expect_true("co2_per_capita" %in% names(out2))
})

test_that("per_capita aborts cleanly on a partial population fetch", {
  # A fetch missing a join column used to die on a raw vctrs subscript error.
  df <- data.frame(iso3c = c("USA", "CHN"), year = 2020L, co2 = c(5e6, 1e7))
  testthat::local_mocked_bindings(
    fetch_wdi = function(...) {
      tibble::tibble(iso3c = c("USA", "CHN"), .wdj_pop = c(331e6, 1402e6))
    }
  )
  expect_error(per_capita(df, co2), class = "countryatlas_error")
  expect_error(per_capita(df, co2), "Could not fetch population")
})

test_that("theil returns NA rather than NaN when all weights are zero", {
  # is.na() is TRUE for NaN as well, so it cannot tell the fixed NA from the
  # NaN the bug produced -- assert the exact value.
  # And both now say which degenerate case it was, rather than returning a
  # bare NA indistinguishable from a missing input.
  expect_warning(t0 <- theil(c(1, 2, 3), weights = c(0, 0, 0)),
                 class = "countryatlas_undefined_index")
  expect_identical(t0, NA_real_)
  expect_warning(g0 <- gini(c(1, 2, 3), weights = c(0, 0, 0)),
                 class = "countryatlas_undefined_index")
  expect_identical(g0, NA_real_)
})

test_that("no runnable example calls per_capita without an explicit pop", {
  skip_slow_on_cran()
  # That path deliberately errors when the World Bank is unreachable, so it must
  # not appear in an example that R CMD check executes.
  skip_if_not(dir.exists("../../man"), "man/ not present (installed package)")
  offenders <- character()
  for (f in Sys.glob("../../man/*.Rd")) {
    out <- tempfile(fileext = ".R")
    tools::Rd2ex(f, out = out, commentDontrun = TRUE, commentDonttest = FALSE)
    if (!file.exists(out)) next
    src <- paste(readLines(out, warn = FALSE), collapse = "\n")
    calls <- regmatches(src, gregexpr("per_capita\\([^)]*\\)", src))[[1]]
    for (cl in calls) {
      if (length(strsplit(cl, ",")[[1]]) < 3L) offenders <- c(offenders, basename(f))
    }
  }
  expect_length(offenders, 0L)
})

test_that("growth_rate(type = 'yoy') gives NA, not Inf, after a zero", {
  d <- data.frame(iso3c = "USA", year = 2000:2003, v = c(0, 5, 0, 0))
  expect_warning(g <- growth_rate(d, v), class = "countryatlas_zero_base")
  # 5 after 0 was Inf and 0 after 0 NaN; 0 after 5 is a real -100%.
  expect_equal(g$v_growth, c(NA, NA, -1, NA))
  expect_false(any(is.infinite(g$v_growth) | is.nan(g$v_growth)))
  # An ordinary series is untouched and silent.
  ok <- data.frame(iso3c = "USA", year = 2000:2002, v = c(100, 110, 121))
  expect_silent(g2 <- growth_rate(ok, v))
  expect_equal(g2$v_growth, c(NA, 0.1, 0.1))
})

test_that("a row with no year gets no lag, difference or growth", {
  d <- data.frame(iso3c = "A", year = c(2000, NA, 2001), v = c(1, 5, 2))
  for (f in list(growth_rate, lag_by_country, diff_by_country)) {
    out <- suppressWarnings(f(d, v))
    new <- setdiff(names(out), names(d))
    expect_true(is.na(out[[new]][is.na(out$year)]))
    # The dated rows are exactly what they are without the stray row.
    clean <- suppressWarnings(f(d[!is.na(d$year), ], v))
    expect_equal(out[[new]][!is.na(out$year)], clean[[new]])
  }
})

test_that("complete_years() carries forward in time order", {
  # 1999 is in the data but not in `years`. complete() appended it after the
  # grid, so locf carried nothing into 2000 and the rows came back unsorted.
  d <- data.frame(iso3c = "USA", year = c(1999, 2001), gdp = c(1, 3))
  out <- complete_years(d, years = 2000:2002, method = "locf")
  expect_equal(out$year, 1999:2002)
  expect_equal(out$gdp, c(1, 1, 3, 3))
})

test_that("base-year warnings count unidentified countries separately", {
  d <- data.frame(iso3c = c(NA, NA, "USA", "USA"),
                  country = c("Freedonia", "Sylvania", "USA", "USA"),
                  year = c(2000, 2000, 2000, 2001), v = c(1, 2, 3, 6),
                  defl = c(1, 1, 1, 1))
  # Two unidentified rows are two countries, named by what identifies them,
  # not "1 country: NA".
  w <- tryCatch(index_to(d, v, base_year = 2001),
                countryatlas_no_base_year = function(w) conditionMessage(w))
  w <- gsub("\\s+", " ", w)
  expect_match(w, "2 countries")
  expect_match(w, "Freedonia")
  expect_match(w, "Sylvania")
  w2 <- tryCatch(deflate(d, v, base_year = 2001, deflator = defl),
                 warning = function(w) conditionMessage(w))
  expect_match(w2, "2 countries")
  expect_match(w2, "Freedonia")
})

test_that("a stray undated row does not drop a country from beta convergence", {
  set.seed(3)
  iso <- sprintf("C%02d", 1:12)
  d <- expand.grid(iso3c = iso, year = c(2000L, 2020L), stringsAsFactors = FALSE)
  d$v <- exp(stats::runif(nrow(d), 6, 11))
  n0 <- suppressWarnings(beta_convergence(d, v))$n
  d2 <- rbind(d, data.frame(iso3c = "C01", year = NA_integer_, v = 500))
  expect_equal(suppressWarnings(beta_convergence(d2, v))$n, n0)
})

test_that("sigma_convergence() reports no phantom NA year", {
  d <- data.frame(iso3c = c("A", "B", "C", "A", "B"),
                  year = c(2000, 2000, 2000, NA, NA), v = c(1, 2, 3, 4, 5))
  s <- sigma_convergence(d, v)
  expect_equal(s$year, 2000)
  expect_false(anyNA(s$year))
})

test_that("per_capita() names an infinite population as one", {
  d <- data.frame(iso3c = c("USA", "CHN"), v = c(1, 2), p = c(Inf, 10))
  expect_warning(per_capita(d, v, p), "infinite",
                 class = "countryatlas_unusable_rows")
})

test_that("share_of_world() gives an undated row no share", {
  s <- data.frame(iso3c = c("A", "B", "C", "D"), year = c(2000, 2000, NA, NA),
                  v = c(1, 3, 5, 5))
  expect_silent(out <- share_of_world(s, v))
  expect_equal(out$v_share, c(0.25, 0.75, NA, NA))
})

test_that("theil(na.rm = FALSE) does not break its decomposition on a missing group", {
  # The row stayed in `total` and fell out of both components.
  x <- c(1, 2, 3, 4)
  g <- c("a", "a", NA, "b")
  expect_true(is.na(theil(x, groups = g, na.rm = FALSE)))
  # na.rm = TRUE drops the row from all three, so the identity holds.
  d <- theil(x, groups = g)
  expect_equal(d$value[1], d$value[2] + d$value[3])
  expect_equal(d$share[2] + d$share[3], 1)
})

test_that("growth_rate() does not read the row after an infinity as -100%", {
  d <- data.frame(iso3c = "USA", year = 2000:2002, gdp = c(100, Inf, 121))
  expect_warning(g <- growth_rate(d, gdp), class = "countryatlas_infinite_base")
  expect_equal(g$gdp_growth, c(NA, Inf, NA))
  base <- data.frame(iso3c = rep(c("USA", "FRA"), each = 3),
                     year = rep(2000:2002, 2),
                     gdp = c(Inf, 110, 121, 100, 110, 121))
  expect_warning(cg <- growth_rate(base, gdp, type = "cagr"), "USA")
  expect_true(all(is.na(cg$gdp_growth[cg$iso3c == "USA"])))
  expect_equal(cg$gdp_growth[cg$iso3c == "FRA"], c(NA, 0.1, 0.1))
})

test_that("growth_rate(type = 'cagr') names a country with a zero base", {
  d <- tibble::tibble(iso3c = rep(c("FRA", "ITA"), each = 3),
                      year = rep(2015:2017, 2), v = c(0, 2, 3, 1, 2, 4))
  # FRA came back NA throughout with nothing said: a negative base is reported
  # with the negative rows, an infinite one on its own, a zero one not at all.
  expect_warning(out <- growth_rate(d, v, type = "cagr"),
                 class = "countryatlas_zero_base")
  expect_true(all(is.na(out$v_growth[out$iso3c == "FRA"])))
  expect_equal(out$v_growth[out$iso3c == "ITA" & out$year == 2017], 1)
  # With every base zero it was blamed on the series being too short.
  w <- testthat::capture_warnings(
    growth_rate(d[d$iso3c == "FRA", ], v, type = "cagr"))
  expect_length(w, 1L)
  expect_match(w, "zero")
})

test_that("index_to validates its column and its scalars", {
  skip_slow_on_cran()
  df <- data.frame(iso3c = "USA", year = 2000:2002, gdp = c(50, 55, 60))
  # Used to fail with a dplyr error from inside mutate().
  expect_error(index_to(df, not_a_column, base_year = 2000), "not found in")
  expect_error(index_to(df, gdp, base_year = NA), "single finite number")
  expect_error(index_to(df, gdp, base_year = 2000, to = NA),
               "single finite number")
  expect_error(index_to(data.frame(x = 1), gdp, base_year = 2000),
               class = "countryatlas_error")
  out <- index_to(df, gdp, base_year = 2000)
  expect_equal(out$gdp_index, c(100, 110, 120))
  # A base year with no observation gives NA rather than a wrong index -- and
  # now names the country it could not index, so the all-NA column is readable.
  expect_warning(none <- index_to(df, gdp, base_year = 1999),
                 class = "countryatlas_no_base_year")
  expect_true(all(is.na(none$gdp_index)))
})

test_that("aggregate_regions() says how much of each group stands behind it", {
  skip_slow_on_cran()
  # A Sub-Saharan Africa sum without Nigeria came back as 575 with no warning
  # and no coverage column, which reads as the region's total.
  d <- tibble::tibble(iso3c = c("NGA", "ZAF", "KEN", "GHA"),
                      region = "Sub-Saharan Africa",
                      gdp = c(NA, 400, 100, 75), pop = c(223, 60, 55, 34))
  expect_silent(out <- aggregate_regions(d, gdp))
  expect_identical(names(out),
                   c("region", "gdp", "n_countries", "n_reporting", "coverage"))
  expect_equal(out$gdp, 575)
  expect_identical(out$n_countries, 4L)
  expect_identical(out$n_reporting, 3L)
  expect_equal(out$coverage, 0.75)
  # Weighted by population, Nigeria is most of the region: below two-thirds,
  # so the figure is withheld and the group is named.
  expect_warning(w <- aggregate_regions(d, gdp, coverage_weight = pop),
                 class = "countryatlas_low_coverage")
  expect_true(is.na(w$gdp))
  expect_equal(w$coverage_weighted, (60 + 55 + 34) / (223 + 60 + 55 + 34))
  expect_match(conditionMessage(tryCatch(
    aggregate_regions(d, gdp, coverage_weight = pop), warning = identity)),
    "Sub-Saharan Africa", fixed = TRUE)
  # The way back: min_coverage = 0 gives the 3.0.0 number, coverage reported.
  expect_silent(old <- aggregate_regions(d, gdp, coverage_weight = pop,
                                         min_coverage = 0))
  expect_equal(old$gdp, 575)
  # A weighted mean follows the World Bank's weight rule by default.
  expect_warning(wm <- aggregate_regions(d, gdp, fun = "weighted_mean",
                                         weight = pop),
                 class = "countryatlas_low_coverage")
  expect_true(is.na(wm$gdp))
  expect_true("coverage_weighted" %in% names(wm))
})

test_that("aggregate_regions() applies the rule per group and per year", {
  pan <- tibble::tibble(
    iso3c = rep(c("A", "B", "C"), 2), region = "R", year = rep(2000:2001, each = 3),
    v = c(1, 2, 3, 1, NA, NA))
  expect_warning(out <- aggregate_regions(pan, v, by = c("region", "year")),
                 "R / 2001")
  expect_equal(out$v, c(6, NA))
  expect_equal(out$coverage, c(1, 1 / 3))
  # A country listed twice in a group counts once as a member.
  rep2 <- tibble::tibble(iso3c = c("A", "A", "B"), region = "R", v = c(1, 1, NA))
  expect_identical(aggregate_regions(rep2, v, min_coverage = 0)$n_countries, 2L)
  # Rows with no grouping value are reported, never withheld.
  nk <- tibble::tibble(iso3c = c("A", "B", "C"), region = c("R", NA, NA),
                       v = c(1, 2, NA))
  expect_silent(o <- aggregate_regions(nk, v))
  expect_equal(o$v[is.na(o$region)], 2)
})

test_that("aggregate_regions() validates min_coverage and keeps zero rows typed", {
  skip_slow_on_cran()
  d <- tibble::tibble(iso3c = "A", region = "R", v = 1, w = 1)
  for (bad in list(-0.1, 1.5, NA, "half", c(0.5, 0.6))) {
    expect_error(aggregate_regions(d, v, min_coverage = bad), "min_coverage")
  }
  expect_error(aggregate_regions(d, v, coverage_weight = nope), "nope")
  z <- aggregate_regions(d[0, ], v)
  expect_identical(nrow(z), 0L)
  expect_type(z$coverage, "double")
  expect_type(z$n_countries, "integer")
})

test_that("aggregate_groups() uses the members of each row's year", {
  pan <- data.frame(iso3c = rep(c("GBR", "FRA", "DEU", "HRV"), each = 2),
                    year = rep(c(2012, 2021), 4), gdp = 1:8)
  expect_silent(out <- aggregate_groups(pan, gdp, "EU", min_coverage = 0))
  # 2012: GBR + FRA + DEU (Croatia joined in 2013); 2021: FRA + DEU + HRV.
  expect_equal(out$gdp, c(1 + 3 + 5, 4 + 6 + 8))
  # Coverage is measured against the whole membership on that date, so the
  # members with no row count as missing: 3 of 27 in both years.
  expect_identical(out$n_countries, c(27L, 27L))
  expect_identical(out$n_reporting, c(3L, 3L))
  expect_warning(low <- aggregate_groups(pan, gdp, "EU"),
                 class = "countryatlas_low_coverage")
  expect_true(all(is.na(low$gdp)))
  # A single as_of applies one membership to every row: the 2012 values of
  # the 2021 members, FRA + DEU + HRV.
  expect_equal(aggregate_groups(pan[pan$year == 2012, ], gdp, "EU",
                                as_of = 2021, min_coverage = 0)$gdp,
               3 + 5 + 7)
})

test_that("aggregate_groups() on a full cross-section is complete", {
  snap <- countryatlas::world_snapshot$countries
  out <- aggregate_groups(snap, population, c("EU", "G7"))
  expect_identical(out$group, c("EU", "G7"))
  expect_identical(out$n_countries, c(27L, 7L))
  expect_equal(out$coverage, c(1, 1))
  expect_equal(out$population[out$group == "G7"],
               sum(snap$population[snap$iso3c %in% country_groups("G7")$iso3c]))
  wm <- aggregate_groups(snap, gdp_per_capita, "EU", fun = "weighted_mean",
                         weight = population)
  eu <- snap[snap$iso3c %in% country_groups("EU")$iso3c, ]
  expect_equal(wm$gdp_per_capita,
               stats::weighted.mean(eu$gdp_per_capita, eu$population))
})

test_that("aggregate_groups() validates and handles the edges", {
  skip_slow_on_cran()
  snap <- countryatlas::world_snapshot$countries
  expect_error(aggregate_groups(snap, population, "Atlantis"), "Atlantis")
  expect_error(aggregate_groups(snap, population, character()), "groups")
  expect_error(aggregate_groups(snap, population, "EU", fun = "weighted_mean"),
               "weight")
  expect_error(aggregate_groups(snap[, "population"], population, "EU"),
               "iso3c")
  expect_silent(z <- aggregate_groups(snap[0, ], population, "EU"))
  expect_identical(nrow(z), 0L)
  # An undated group warns and uses today's membership.
  pan <- data.frame(iso3c = c("GBR", "IND"), year = 2000, v = 1:2)
  expect_warning(aggregate_groups(pan, v, "Commonwealth", min_coverage = 0),
                 "No dated membership")
})

test_that("per_capita() says when it divides across years", {
  d <- tibble::tibble(iso3c = c("FRA", "DEU"), gdp = c(3, 20),
                      gdp_year = c(2023L, 2022L), pop = c(5, 9),
                      pop_year = c(2021L, 2022L))
  expect_warning(out <- per_capita(d, gdp, pop),
                 class = "countryatlas_mixed_years")
  expect_match(conditionMessage(tryCatch(per_capita(d, gdp, pop),
                                         warning = identity)),
               "FRA: gdp 2023, pop 2021", fixed = TRUE)
  expect_equal(out$gdp_per_capita, c(3 / 5, 20 / 9))
  # Agreeing years, or no year columns, are silent.
  d$pop_year <- d$gdp_year
  expect_silent(per_capita(d, gdp, pop))
  expect_silent(per_capita(d[, c("iso3c", "gdp", "pop")], gdp, pop))
})

test_that("per_capita() fetches population for the year the value is from", {
  d <- tibble::tibble(iso3c = c("FRA", "DEU"), gdp = c(3, 20),
                      gdp_year = c(2023L, 2022L))
  popf <- tibble::tibble(iso3c = rep(c("FRA", "DEU"), each = 3),
                         year = rep(2021:2023, 2),
                         .wdj_pop = c(100, 200, 300, 1000, 2000, 3000))
  seen <- NULL
  out <- testthat::with_mocked_bindings(
    per_capita(d, gdp),
    fetch_wdi = function(indicator, start, end, ...) {
      seen <<- c(start, end)
      popf
    })
  expect_equal(seen, c(2022, 2023))
  expect_equal(out$gdp_per_capita, c(3 / 300, 20 / 2000))
})

test_that("rank_countries() warns when it pools the years of a panel", {
  # Three countries by two years: France 2020 ranked 1 and France 2000 ranked
  # 6, with z_score computed across all six country-years, and no warning.
  pan <- data.frame(iso3c = rep(c("FRA", "DEU", "ITA"), each = 2),
                    year = rep(c(2000, 2020), 3),
                    gdp = c(10, 40, 20, 30, 15, 16))
  expect_warning(pooled <- rank_countries(pan, gdp),
                 class = "countryatlas_panel")
  expect_identical(sort(pooled$rank), 1:6)
  expect_silent(by_year <- rank_countries(pan, gdp, within = year))
  expect_identical(by_year$rank[by_year$year == 2020], c(1L, 2L, 3L))
  # One year, or no year column, is a cross-section and stays silent.
  expect_silent(rank_countries(pan[pan$year == 2000, ], gdp))
  expect_silent(rank_countries(pan[pan$year == 2000, c("iso3c", "gdp")], gdp))
})

test_that("correlate_indicators(by_year = TRUE) gives one table per year", {
  snap <- countryatlas::world_snapshot$countries
  pan <- rbind(transform(snap, year = 2020),
               transform(snap, year = 2021, gdp_per_capita = -gdp_per_capita))
  expect_silent(out <- correlate_indicators(pan, gdp_per_capita,
                                            life_expectancy, by_year = TRUE))
  expect_identical(names(out), c("year", "var_x", "var_y", "r", "n"))
  expect_equal(out$year, c(2020, 2021))
  # Each year is its own cross-section: the flipped year flips the sign,
  # which pooling to the earliest year would have hidden.
  expect_equal(out$r[1], -out$r[2])
  expect_error(correlate_indicators(snap, by_year = TRUE), "year")
  expect_error(correlate_indicators(pan, by_year = NA), "by_year")
})

test_that("correlate_indicators(weight =) matches a weighted covariance", {
  snap <- countryatlas::world_snapshot$countries
  out <- correlate_indicators(snap, gdp_per_capita, life_expectancy,
                              weight = population)
  ok <- is.finite(snap$gdp_per_capita) & is.finite(snap$life_expectancy) &
    is.finite(snap$population) & snap$population > 0
  ref <- stats::cov.wt(cbind(snap$gdp_per_capita[ok], snap$life_expectancy[ok]),
                       wt = snap$population[ok], cor = TRUE)$cor[1, 2]
  expect_equal(out$r, ref, tolerance = 1e-12)
  expect_identical(out$n, sum(ok))
  # Equal weights give the unweighted answer.
  snap$one <- 1
  expect_equal(correlate_indicators(snap, gdp_per_capita, life_expectancy,
                                    weight = one)$r,
               correlate_indicators(snap, gdp_per_capita, life_expectancy)$r,
               tolerance = 1e-12)
  expect_equal(correlate_indicators(snap, gdp_per_capita, life_expectancy,
                                    weight = one, method = "spearman")$r,
               correlate_indicators(snap, gdp_per_capita, life_expectancy,
                                    method = "spearman")$r,
               tolerance = 1e-12)
  expect_error(correlate_indicators(snap, weight = nope), "nope")
})

test_that("lags, differences and yoy growth are keyed on the year", {
  skip_slow_on_cran()
  # 3.0.0 compared each row with the previous one and warned about gaps; a
  # gapped panel's "one-year" change silently spanned two years. Year-keyed,
  # the change that has no year one earlier is NA.
  d <- data.frame(iso3c = "FRA", year = c(2000, 2002, 2003, 2005),
                  v = c(100, 110, 121, 133))
  expect_no_warning(l <- lag_by_country(d, v))
  expect_equal(l$v_lag, c(NA, NA, 110, NA))
  expect_equal(diff_by_country(d, v, n = 2)$v_diff2, c(NA, 10, NA, 12))
  expect_equal(growth_rate(d, v)$v_growth, c(NA, NA, 0.1, NA))
  # The 3.0.0 behaviour, by name, still warns about the gaps.
  expect_warning(r <- lag_by_country(d, v, by = "row"),
                 class = "countryatlas_irregular_years")
  expect_equal(r$v_lag, c(NA, 100, 110, 121))
  expect_warning(growth_rate(d, v, by = "row"),
                 class = "countryatlas_irregular_years")
  # Never across countries.
  two <- data.frame(iso3c = c("FRA", "DEU"), year = c(2000, 2001), v = 1:2)
  expect_warning(l2 <- lag_by_country(two, v), "came out NA")
  expect_true(all(is.na(l2$v_lag)))
  # A factor or Date year is read as a year; labels that are not years need
  # by = "row".
  f <- transform(d, year = factor(year))
  expect_equal(lag_by_country(f, v)$v_lag, c(NA, NA, 110, NA))
  dt <- transform(d, year = as.Date(paste0(year, "-01-01")))
  expect_equal(lag_by_country(dt, v)$v_lag, c(NA, NA, 110, NA))
  e <- data.frame(iso3c = "FRA", year = c("pre-war", "post-war"), v = 1:2)
  expect_error(lag_by_country(e, v), class = "countryatlas_year_not_numeric")
  expect_no_error(lag_by_country(e, v, by = "row"))
})
