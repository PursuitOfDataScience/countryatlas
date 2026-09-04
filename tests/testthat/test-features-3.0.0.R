# 3.0.0: spatial weights, data sources, time, disputes, rates, networks,
# reporting, subnational and the alternative renderers.

snap <- countryatlas::world_snapshot$countries

poly_df <- function() {
  skip_if_not_installed("maps")
  attach_geometry(snap, geometry = "polygon")
}
sf_df <- function() {
  skip_if_no_sf_geometry()
  attach_geometry(snap, geometry = "sf")
}
renders <- function(p) {
  expect_s3_class(p, "ggplot")
  expect_s3_class(ggplot2::ggplotGrob(p), "gtable")
  invisible(p)
}

# --- spatial weights ------------------------------------------------------------

test_that("country_weights builds each scheme and reports isolation", {
  w <- country_weights("knn", k = 5)
  expect_s3_class(w, "countryatlas_weights")
  m <- as.matrix(w)
  expect_true(is.matrix(m))
  expect_identical(rownames(m), colnames(m))
  # The whole reason knn exists: every country gets neighbours, islands too.
  expect_length(w$isolated, 0L)
  expect_true(all(c("JPN", "AUS", "ISL") %in% w$iso3c))
  expect_equal(unname(rowSums(m)[1]), 1, tolerance = 1e-9)   # row-standardised

  wd <- country_weights("distance", cutoff_km = 2000)
  expect_s3_class(wd, "countryatlas_weights")
  expect_true(wd$n_links > 0)

  wb <- country_weights("knn", k = 3, style = "B")
  expect_true(all(as.matrix(wb) %in% c(0, 1)))
  expect_equal(unname(rowSums(as.matrix(wb))[1]), 3)
})

test_that("country_weights validates its arguments", {
  expect_error(country_weights("knn", k = 9999), "smaller than the number")
  expect_error(country_weights("distance"), "cutoff_km")
  expect_error(country_weights("custom"), "`w` is required")
  expect_error(country_weights("custom", w = 42), "named square matrix")
  expect_error(country_weights("custom", w = matrix(1, 2, 2)), "row and column names")
  expect_error(country_weights("nope"), "`type`")
})

test_that("custom weights accept a long frame -- non-geographic adjacency", {
  trade <- data.frame(iso3c = c("USA", "USA", "CHN"),
                      neighbor = c("CHN", "MEX", "JPN"),
                      weight = c(5, 3, 4))
  w <- country_weights("custom", w = trade)
  expect_setequal(w$iso3c, c("USA", "CHN", "MEX", "JPN"))
  expect_equal(w$type, "custom")
  # Row-standardised: USA's two links become 5/8 and 3/8.
  m <- as.matrix(w)
  expect_equal(unname(m["USA", "CHN"]), 5 / 8, tolerance = 1e-9)
})

test_that("morans_i accepts weights and the scheme changes the answer", {
  skip_if_no_sf_geometry()
  set.seed(1)
  contig <- morans_i(snap, gdp_per_capita, n_perm = 0)
  knn <- morans_i(snap, gdp_per_capita, n_perm = 0,
                  weights = country_weights("knn", k = 5))
  # knn reaches the islands, so it uses far more countries.
  expect_gt(knn$n, contig$n)
  expect_lt(knn$n_excluded, contig$n_excluded)
  expect_false(isTRUE(all.equal(knn$i, contig$i)))
  expect_true(is.finite(knn$i))
})

test_that("local_morans classifies clusters and lisa_map draws them", {
  set.seed(1)
  w <- country_weights("knn", k = 5)
  lm1 <- local_morans(snap, gdp_per_capita, weights = w, n_perm = 99)
  expect_named(lm1, c("iso3c", "value", "lag", "ii", "p_value", "cluster"))
  expect_true(all(levels(lm1$cluster) %in%
                    c("High-High", "Low-Low", "High-Low", "Low-High",
                      "Not significant")))
  expect_true(any(lm1$cluster == "High-High"))
  expect_true(all(lm1$p_value >= 0 & lm1$p_value <= 1, na.rm = TRUE))
  # The lag really is the neighbour mean of the centred values.
  expect_equal(nrow(lm1), length(unique(lm1$iso3c)))

  p <- lisa_map(poly_df(), gdp_per_capita, weights = w, n_perm = 19)
  renders(p)
  expect_s3_class(attr(p, "countryatlas_lisa"), "tbl_df")
})

test_that("gearys_c is centred on 1 and points the other way from Moran", {
  set.seed(1)
  w <- country_weights("knn", k = 5)
  g <- gearys_c(snap, gdp_per_capita, weights = w, n_perm = 99)
  expect_equal(g$expected, 1)
  # Positive autocorrelation: Moran's I above its expectation, Geary's C below 1.
  m <- morans_i(snap, gdp_per_capita, weights = w, n_perm = 0)
  expect_gt(m$i, m$expected)
  expect_lt(g$c, 1)
  expect_true(g$p_value < 0.1)
})

test_that("getis_ord returns local and global forms", {
  w <- country_weights("knn", k = 5)
  loc <- getis_ord(snap, gdp_per_capita, weights = w)
  expect_named(loc, c("iso3c", "gi_star", "z_score", "p_value"))
  expect_true(all(loc$p_value >= 0 & loc$p_value <= 1, na.rm = TRUE))
  glob <- getis_ord(snap, gdp_per_capita, weights = w, local = FALSE)
  expect_named(glob, c("g", "expected", "n", "n_links"))
})

test_that("spatial_lag is the neighbour average", {
  w <- country_weights("knn", k = 5)
  out <- spatial_lag(snap, gdp_per_capita, weights = w)
  expect_true("gdp_per_capita_lag" %in% names(out))
  # Hand-check one country against the weights matrix.
  m <- as.matrix(w)
  al <- countryatlas:::align_weights(snap, "gdp_per_capita", w)
  i <- 1L
  expect_equal(out$gdp_per_capita_lag[match(al$iso3c[i], out$iso3c)],
               sum(al$m[i, ] * al$x), tolerance = 1e-9)
})

test_that("a weight scheme that reaches nobody errors clearly", {
  one <- snap[snap$iso3c %in% c("JPN", "AUS"), ]
  skip_if_no_sf_geometry()
  expect_error(morans_i(one, gdp_per_capita, n_perm = 0),
               "Not enough connected countries")
})

# --- data sources ----------------------------------------------------------------

test_that("the built-in sources are registered at load", {
  s <- country_sources()
  expect_true(all(c("wdi", "owid", "eurostat", "oecd", "comtrade") %in% s$source))
  expect_named(s, c("source", "meta", "key_col", "key_type", "cache",
                    "available", "citation"))
  # Every bundled source reads its key as iso3c; that default is exactly why
  # key_col's second life as a coding scheme went unnoticed.
  expect_true(all(s$key_type == "iso3c"))
  expect_true(s$available[s$source == "wdi"])
})

test_that("a user source round-trips through the contract", {
  register_country_source(
    "test_src",
    fetch = function(indicator, countries = NULL, years = NULL) {
      d <- data.frame(iso3c = c("USA", "FRA", "JPN"), year = 2020L,
                      demo = c(1, 2, 3))
      if (!is.null(countries)) d <- d[d$iso3c %in% countries, ]
      d
    },
    meta = "test", citation = "nobody"
  )
  on.exit(rm("test_src", envir = countryatlas:::the_sources), add = TRUE)
  expect_true("test_src" %in% country_sources()$source)
  out <- fetch_indicator("test_src", "demo")
  expect_equal(nrow(out), 3L)
  expect_true(all(c("iso3c", "year", "demo") %in% names(out)))
  # countries= is forwarded
  expect_equal(nrow(fetch_indicator("test_src", "demo", countries = "USA")), 1L)
})

test_that("the contract is enforced with named errors", {
  expect_error(fetch_indicator("no_such_source", "x"), "Unknown source")
  expect_error(register_country_source("bad", fetch = 42), "must be a function")
  register_country_source("junk_src", function(...) 42)
  register_country_source("nokey_src", function(...) data.frame(a = 1))
  on.exit({
    rm("junk_src", envir = countryatlas:::the_sources)
    rm("nokey_src", envir = countryatlas:::the_sources)
  }, add = TRUE)
  expect_error(fetch_indicator("junk_src", "x"), "not a data frame")
  expect_error(fetch_indicator("nokey_src", "x"), "no .*iso3c.* column")
})

test_that("add_indicator joins onto an existing frame", {
  register_country_source("add_src", function(indicator, countries = NULL,
                                              years = NULL) {
    data.frame(iso3c = c("USA", "FRA"), year = 2020L, extra = c(10, 20))
  })
  on.exit(rm("add_src", envir = countryatlas:::the_sources), add = TRUE)
  base <- data.frame(iso3c = c("USA", "FRA", "JPN"), v = 1:3)
  out <- add_indicator(base, "add_src", "extra")
  expect_equal(nrow(out), 3L)
  expect_equal(out$extra, c(10, 20, NA))
  expect_error(add_indicator(data.frame(x = 1), "add_src", "extra"), "iso3c")
})

test_that("compare_sources validates before it fetches", {
  expect_error(compare_sources("x", sources = "wdi", year = 2020),
               "at least two")
  expect_error(compare_sources("x", sources = c("wdi", "owid")), "year")
  expect_error(compare_sources(c(wdi = "a"), sources = c("wdi", "owid"),
                               year = 2020), "names no code")
})

test_that("an adapter reports an unreachable provider, not a missing column", {
  # The failure mode this guards: a client that answers a failed download with
  # an empty frame rather than an error.
  expect_error(
    countryatlas:::adapter_reshape(data.frame(entity = character(0)), "x",
                                   "entity", "year"),
    "returned no rows")
})

test_that("clear_country_cache validates the source name", {
  expect_error(clear_country_cache("no_such_source"), "Unknown source")
  expect_true(clear_country_cache())
})

# --- time --------------------------------------------------------------------------

test_that("country_groups_history reconciles with the current snapshot", {
  h <- countryatlas::country_groups_history
  expect_true(all(c("group", "iso3c", "country", "from", "to") %in% names(h)))
  expect_false(anyNA(h$from))
  expect_false(any(duplicated(h[, c("group", "iso3c")])))
  expect_true(all(is.na(h$to) | h$to > h$from))
  # Every group's members current today must equal country_groups_tbl.
  today <- Sys.Date()
  cur <- h[h$from <= today & (is.na(h$to) | h$to > today), ]
  for (g in unique(h$group)) {
    expect_setequal(
      cur$iso3c[cur$group == g],
      countryatlas::country_groups_tbl$iso3c[
        countryatlas::country_groups_tbl$group == g])
  }
})

test_that("as_of gives point-in-time membership", {
  expect_equal(nrow(country_groups("EU", as_of = 2016)), 28L)
  expect_equal(nrow(country_groups("EU", as_of = 2021)), 27L)
  expect_equal(nrow(country_groups("EU", as_of = 1990)), 12L)
  expect_true(in_group("United Kingdom", "EU", as_of = 2016))
  expect_false(in_group("United Kingdom", "EU", as_of = 2021))
  # NATO grew; EFTA shrank.
  expect_equal(nrow(country_groups("NATO", as_of = 1950)), 12L)
  expect_gt(nrow(country_groups("EFTA", as_of = 1965)),
            nrow(country_groups("EFTA", as_of = Sys.Date())))
})

test_that("as_of accepts dates, years and strings, and rejects the rest", {
  expect_equal(nrow(country_groups("EU", as_of = as.Date("2016-06-01"))), 28L)
  expect_equal(nrow(country_groups("EU", as_of = "2016-06-01")), 28L)
  for (bad in list("nope", 42, c(2000, 2001), NA, TRUE)) {
    expect_error(country_groups("EU", as_of = bad), "must be a")
  }
})

test_that("an undated group warns and falls back rather than inventing dates", {
  expect_warning(g <- country_groups("OPEC", as_of = 2000), "No dated membership")
  expect_equal(nrow(g), nrow(country_groups("OPEC")))
})

test_that("country_timeline reads the crosswalk both ways", {
  # "Wakanda" matches neither spine, which the function now reports rather than
  # leaving as a row of NA to be noticed.
  expect_warning(
    tl <- country_timeline(c("USSR", "Estonia", "France", "Wakanda")),
    "matched neither")
  expect_equal(tl$iso3c[1], "SUN")
  expect_equal(tl$dissolved[1], 1991L)
  expect_length(tl$successors[[1]], 15L)
  expect_true("RUS" %in% tl$successors[[1]])
  # Read in reverse: Estonia's predecessor is the USSR.
  expect_equal(tl$predecessors[[2]], "SUN")
  expect_true(is.na(tl$iso3c[4]))
  expect_equal(nrow(country_timeline(character(0))), 0L)
})

test_that("audit_time_coverage catches rows outside a country's existence", {
  panel <- data.frame(iso3c = c("SSD", "CZE", "FRA", "RUS"),
                      year = c(1995L, 2001L, 2001L, 1985L))
  out <- audit_time_coverage(panel, quiet = TRUE)
  expect_true("SSD" %in% out$iso3c)
  expect_true(all(out$issue %in% c("before_existence", "after_dissolution")))
  expect_false("FRA" %in% out$iso3c)
  expect_equal(nrow(audit_time_coverage(data.frame(iso3c = "FRA", year = 2000L),
                                        quiet = TRUE)), 0L)
  expect_error(audit_time_coverage(data.frame(x = 1)), "iso3c")
})

test_that("historical_geometry draws the world as it was", {
  skip_if_not_installed("cshapes")
  skip_if_not_installed("sf")
  g70 <- historical_geometry(1970)
  expect_s3_class(g70, "sf")
  expect_true(all(c("gwcode", "country", "iso3c") %in% names(g70)))
  # Decolonisation is visible: 1950 with dependencies has far more entities.
  g50 <- historical_geometry(1950, dependencies = TRUE)
  expect_gt(nrow(g50), nrow(g70))
  # gwcode is complete; iso3c is best-effort and NA for pre-ISO entities.
  expect_false(anyNA(g70$gwcode))
  expect_true(anyNA(g50$iso3c))
  expect_error(historical_geometry(2030), "1886-2019")
  expect_error(historical_geometry("x"), "single year")
})

test_that("world_geometry and attach_geometry route year to CShapes", {
  skip_if_not_installed("cshapes")
  skip_if_not_installed("sf")
  expect_s3_class(world_geometry("countries", year = 1970), "sf")
  expect_error(world_geometry("coastline", year = 1970), "only available for")
  expect_error(world_geometry("countries", year = 1970, region = "Africa"),
               "cannot be combined")
  h <- suppressWarnings(attach_geometry(snap[, c("iso3c", "gdp_per_capita")],
                                        year = 1970))
  expect_s3_class(h, "sf")
  expect_true(sum(!is.na(h$gdp_per_capita)) > 50)
})

# --- disputes, uncertainty, imputation -------------------------------------------

test_that("disputed_territories is scoped and internally consistent", {
  dt <- countryatlas::disputed_territories
  expect_false(any(duplicated(dt$territory)))
  expect_false(anyNA(dt$note))
  expect_true(all(dt$status %in% c("un_member", "un_observer",
                                   "partially_recognised", "administered",
                                   "claimed")))
  # Most disputed territories have no ISO code at all -- that is the point.
  expect_true(sum(is.na(dt$iso3c)) > 0)
  expect_true(all(is.na(dt$iso3c) | dt$iso3c %in% countryatlas:::wdj_known_iso3c()))
})

test_that("disputed_territories' party codes are ISO or a documented placeholder", {
  dt <- countryatlas::disputed_territories
  known <- countryatlas:::wdj_known_iso3c()
  # These columns look like iso3c and mostly are, but six parties are entities
  # ISO gives no code to. Nothing said so, so reading the column as iso3c
  # produced silent NAs. Pin the exact set: a new placeholder must be
  # documented, and a typo in an existing one must fail here.
  placeholders <- c("ABK", "CYP-N", "OST", "PMR", "SAH", "SOL")
  split1 <- function(x) unlist(strsplit(as.character(x), "[;] *"))
  parties <- stats::na.omit(c(split1(dt$administered_by),
                              split1(dt$claimed_by)))
  expect_true(all(parties %in% c(known, placeholders)))
  expect_setequal(setdiff(unique(parties), known), placeholders)
  on <- function(col, code) {
    grepl(paste0("(^|; *)", code, "( *;|$)"), col)
  }
  # Five are self-administering entities ISO codes nowhere: they appear in
  # `administered_by` for the like-named territory, which has no iso3c either.
  for (p in c("ABK", "CYP-N", "OST", "PMR", "SOL")) {
    hit <- on(dt$administered_by, p)
    expect_true(any(hit), label = paste(p, "administers something"))
    expect_true(all(is.na(dt$iso3c[hit])),
                label = paste(p, "administers a row with no iso3c"))
  }
  # SAH is the exception, and the reason a uniform rule cannot be asserted: it
  # is a claimant only, of a territory ISO *does* code.
  expect_false(any(on(dt$administered_by, "SAH")))
  sah <- dt[on(dt$claimed_by, "SAH"), ]
  expect_equal(nrow(sah), 1L)
  expect_equal(sah$territory, "Western Sahara")
  expect_equal(sah$iso3c, "ESH")
  expect_equal(sah$administered_by, "MAR")
  # And they are genuinely not resolvable, which is why they are documented.
  expect_true(all(is.na(suppressWarnings(
    convert_country(placeholders, to = "country", from = "iso3c",
                    warn = FALSE)))))
})

test_that("dispute_policy records a convention and warns about de jure", {
  old <- dispute_policy()
  on.exit(dispute_policy(old), add = TRUE)
  expect_equal(dispute_policy("neutral"), "neutral")
  expect_equal(dispute_policy(), "neutral")
  # Selecting de jure must not silently imply the shapes changed.
  expect_warning(dispute_policy("de_jure"), "still de facto")
  expect_error(dispute_policy("nonsense"), "`policy`")
})

test_that("check_dispute_coverage reports both directions", {
  out <- check_dispute_coverage(snap, quiet = TRUE)
  expect_true("in_data" %in% names(out))
  expect_equal(nrow(out), nrow(countryatlas::disputed_territories))
  expect_true(any(out$in_data))
  expect_error(check_dispute_coverage(data.frame(x = 1)), "iso3c")
})

test_that("world_map(disputes) marks and annotates", {
  mapdf <- poly_df()
  plain <- world_map(mapdf, gdp_per_capita)
  marked <- world_map(mapdf, gdp_per_capita, disputes = "mark")
  renders(marked)
  expect_equal(length(marked$layers), length(plain$layers) + 1L)
  expect_match(marked$labels$caption, "Disputed territories")
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

test_that("world_map(uncertainty) draws a VSUP with a complete legend", {
  mapdf <- poly_df()
  set.seed(1)
  mapdf$se <- abs(stats::rnorm(nrow(mapdf))) * mapdf$gdp_per_capita * 0.3
  p <- world_map(mapdf, gdp_per_capita, uncertainty = se, n_bins = 5,
                 n_uncertainty = 3)
  renders(p)
  # Every value x uncertainty cell has a key, including unobserved ones.
  expect_length(p$scales$scales[[1]]$get_limits(), 15L)
  expect_error(world_map(mapdf, gdp_per_capita, uncertainty = se,
                         n_uncertainty = 99), "n_uncertainty")
  expect_error(world_map(mapdf, gdp_per_capita, uncertainty = country),
               "numeric")
})

test_that("interpolate_missing flags every value it invents", {
  p <- data.frame(iso3c = "USA", year = 2000:2008,
                  gdp = c(1, NA, NA, 4, NA, NA, NA, NA, 9))
  out <- interpolate_missing(p, "gdp")
  expect_true("gdp_imputed" %in% names(out))
  expect_equal(out$gdp[2:3], c(2, 3))
  expect_true(all(out$gdp_imputed[2:3]))
  # A gap longer than max_gap is left alone rather than invented across.
  expect_true(all(is.na(out$gdp[5:8])))
  expect_false(any(out$gdp_imputed[5:8]))
  # Observed values are never flagged.
  expect_false(any(out$gdp_imputed[c(1, 4, 9)]))
  expect_equal(attr(out, "countryatlas_imputed"), "gdp_imputed")
})

test_that("a map of imputed data says so in the caption", {
  mapdf <- poly_df()
  mapdf$gdp_imputed <- FALSE
  mapdf$gdp_imputed[mapdf$iso3c == "FRA"] <- TRUE
  cap <- world_map(mapdf, gdp_per_capita)$labels$caption
  expect_match(cap, "interpolated")
})

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
  d0 <- deflate(data.frame(iso3c = "A", year = 2000:2001, g = c(1, 2),
                           d = c(0, 1)), g, base_year = 2001, deflator = d)
  # Dividing by a zero index produced Inf, which then propagated silently into
  # every scale and summary downstream.
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

# --- networks --------------------------------------------------------------------

test_that("flow_matrix accumulates repeated pairs", {
  od <- data.frame(from = c("China", "China"), to = c("USA", "USA"),
                   value = c(300, 200))
  m <- flow_matrix(od, from, to, value)
  expect_equal(unname(m["CHN", "USA"]), 500)
  expect_equal(unname(m["USA", "CHN"]), 0)
  ms <- flow_matrix(od, from, to, value, symmetric = TRUE)
  expect_equal(unname(ms["USA", "CHN"]), 500)
})

test_that("flow_matrix warns about endpoints it cannot resolve", {
  od <- data.frame(from = c("China", "Wakanda"), to = c("USA", "USA"),
                   value = c(1, 2))
  expect_warning(m <- flow_matrix(od, from, to, value), "did not resolve")
  expect_equal(nrow(m), 2L)
  expect_error(
    suppressWarnings(flow_matrix(data.frame(from = "Wakanda", to = "Atlantis"),
                                 from, to)),
    "No usable flows left")
  # An unusable *weight* is a different failure from an unresolvable country,
  # and must not be reported as one.
  expect_warning(
    flow_matrix(data.frame(from = c("United States", "China"),
                           to = c("China", "Japan"), value = c(NA_real_, 5)),
                from, to, value),
    "weight is missing or infinite")
})

test_that("country_network summarises nodes and edges", {
  od <- data.frame(from = c("China", "China", "USA", "Mexico"),
                   to = c("USA", "Germany", "Mexico", "USA"),
                   value = c(500, 100, 300, 320))
  n <- country_network(od, from, to, value)
  expect_named(n, c("nodes", "edges"))
  expect_true(all(c("out_flow", "in_flow", "net_flow", "strength_share") %in%
                    names(n$nodes)))
  chn <- n$nodes[n$nodes$iso3c == "CHN", ]
  expect_equal(chn$out_flow, 600)
  expect_equal(chn$in_flow, 0)
  # USA <-> Mexico is reciprocal; China -> Germany is not.
  usa_mex <- n$edges[n$edges$from == "USA" & n$edges$to == "MEX", ]
  expect_equal(usa_mex$reciprocity, 320 / 300, tolerance = 1e-9)
})

test_that("od_map draws one panel per origin", {
  skip_if_not_installed("maps")
  od <- data.frame(from = rep(c("China", "Germany", "USA"), each = 3),
                   to = c("USA", "Japan", "Brazil", "France", "Italy", "Poland",
                          "Mexico", "Canada", "Japan"),
                   value = c(500, 200, 90, 80, 70, 60, 300, 280, 120))
  p <- od_map(od, from, to, value, origins = 3)
  renders(p)
  expect_equal(length(unique(ggplot2::ggplot_build(p)$data[[1]]$PANEL)), 3L)
  renders(od_map(od, from, to, value, origins = c("China", "USA")))
  renders(od_map(od, from, to, value, origins = 2, direction = "in"))
  expect_error(od_map(od, from, to, value, origins = "Wakanda"), "did not resolve")
})

# --- reporting --------------------------------------------------------------------

test_that("country_factsheet assembles what the package knows", {
  fs <- country_factsheet("Brazil")
  expect_s3_class(fs, "countryatlas_factsheet")
  expect_equal(fs$iso3c, "BRA")
  expect_true(nrow(fs$groups) > 0)
  expect_true(nrow(fs$indicators) > 0)
  # Numbers are rounded rather than dumped at full double precision.
  area <- fs$geography$value[fs$geography$field == "area_km2"]
  expect_false(grepl("\\.", area))
  msg <- capture.output(out <- capture.output(print(fs)), type = "message")
  expect_match(paste(c(msg, out), collapse = "\n"), "Brazil")
  expect_error(country_factsheet("Wakanda"), "did not resolve")
  expect_error(country_factsheet(c("Brazil", "France")), "single country")
})

test_that("world_table ranks and formats", {
  t1 <- world_table(snap, gdp_per_capita, top_n = 5, engine = "tibble")
  expect_equal(nrow(t1), 5L)
  expect_equal(t1$rank, 1:5)
  expect_true(all(diff(t1$gdp_per_capita) <= 0))
  t2 <- world_table(snap, gdp_per_capita, top_n = 5, desc = FALSE,
                    engine = "tibble")
  expect_true(all(diff(t2$gdp_per_capita) >= 0))
  skip_if_not_installed("gt")
  expect_s3_class(world_table(snap, gdp_per_capita, top_n = 5), "gt_tbl")
})

# --- cartograms and projections ---------------------------------------------------

test_that("gridded_cartogram allocates exactly the cells requested", {
  # The centroid warning is expected and correct here -- a handful of
  # territories have no bundled centroid; it is asserted separately below.
  p <- suppressWarnings(gridded_cartogram(snap, population, cells = 400))
  renders(p)
  expect_warning(gridded_cartogram(snap, population, cells = 400),
                 "no bundled centroid")
  cells <- attr(p, "countryatlas_cells")
  expect_equal(sum(cells$cells), 400L)
  expect_true(all(cells$cells >= 0))
  # Every placeable country is reported, including the ones that rounded to
  # zero -- which is what makes the rounding inspectable and `share` sum to 1.
  expect_equal(sum(cells$share), 1, tolerance = 1e-9)
  expect_true(any(cells$cells == 0L))
  # Largest-remainder: a bigger country never gets fewer cells than a smaller.
  ord <- order(cells$value, decreasing = TRUE)
  expect_false(is.unsorted(rev(cells$cells[ord])))
  # An awkward total still allocates exactly, with no cells lost to a country
  # that has no centroid to be placed at.
  odd <- attr(suppressWarnings(gridded_cartogram(snap, population, cells = 997)),
              "countryatlas_cells")
  expect_equal(sum(odd$cells), 997L)
  expect_error(gridded_cartogram(snap, population, cells = 0), "cells")
})

test_that("cartogram_diagnostics measures the residual area error", {
  skip_if_not_installed("sf")
  skip_if_not_installed("cartogram")
  skip_if_not_installed("rnaturalearth")
  d <- sf_df()
  cg <- cartogram_map(d, population)
  diag <- cartogram_diagnostics(cg)
  expect_true(all(c("target_share", "actual_share", "area_error") %in% names(diag)))
  s <- attr(diag, "countryatlas_cartogram")
  expect_true(is.finite(s$mean_abs_error))
  # Sorted worst-first.
  expect_false(is.unsorted(rev(abs(diag$area_error))))
  expect_error(cartogram_diagnostics(d), "weight.* is required")
  expect_error(cartogram_diagnostics(42), "must be a cartogram plot")
})

test_that("projection_distortion agrees with what each projection claims", {
  skip_if_not_installed("sf")
  areal <- function(p) attr(projection_distortion(p, "areal", spacing = 20),
                            "countryatlas_distortion")
  angular <- function(p) attr(projection_distortion(p, "angular", spacing = 20),
                              "countryatlas_distortion")
  # Equal-area projections have areal distortion of exactly 1...
  for (p in c("equal_earth", "mollweide", "gall_peters")) {
    expect_equal(areal(p)$mean, 1, tolerance = 0.01, label = p)
  }
  # ...and Mercator, which is not equal-area, does not.
  expect_gt(areal("mercator")$mean, 2)
  # Mercator is conformal, so angular distortion is ~0; equal-area ones are not.
  expect_lt(angular("mercator")$mean, 1)
  expect_gt(angular("equal_earth")$mean, 10)
  expect_error(projection_distortion("nope"), "`projection` must be one of")
})

# --- renderers ----------------------------------------------------------------------

test_that("interactive_map gains a mapgl engine", {
  skip_if_not_installed("mapgl")
  skip_if_no_sf_geometry()
  d <- sf_df()
  expect_s3_class(interactive_map(d, gdp_per_capita, engine = "mapgl"),
                  "maplibregl")
  expect_s3_class(interactive_map(d, continent, engine = "mapgl"), "maplibregl")
  skip_if_not_installed("maps")
  expect_error(interactive_map(poly_df(), gdp_per_capita, engine = "mapgl"),
               "needs an sf frame")
})

test_that("globe_map(interactive) returns a WebGL globe", {
  skip_if_not_installed("mapgl")
  skip_if_no_sf_geometry()
  expect_s3_class(globe_map(sf_df(), gdp_per_capita, interactive = TRUE),
                  "maplibregl")
  expect_error(globe_map(snap, gdp_per_capita, interactive = TRUE),
               "needs an sf frame")
})

test_that("world_map(engine = 'tmap') renders through tmap", {
  skip_if_not_installed("tmap")
  skip_if_no_sf_geometry()
  expect_s3_class(world_map(sf_df(), gdp_per_capita, engine = "tmap"), "tmap")
  skip_if_not_installed("maps")
  expect_error(world_map(poly_df(), gdp_per_capita, engine = "tmap"),
               "needs an sf frame")
})

test_that("world_query gained layers, faceting and binning", {
  q <- world_query(gdp, layer = "binned", n_bins = 4, facet = "year")
  expect_match(q, "BIN fill INTO 4")
  expect_match(q, "FACET BY year")
  b <- world_query(gdp, layer = "bubble", size = "population")
  expect_match(b, "population AS size")
  expect_match(b, "DRAW spatial_point")
  expect_error(world_query(gdp, layer = "bubble"), "needs a .*size. column")
  # The default is unchanged.
  expect_match(world_query(gdp), "DRAW spatial")
})

# --- the alternate spine and the deprecations ----------------------------------------

test_that("country_join can key on COW/Gleditsch-Ward codes", {
  a <- data.frame(country = c("Czechia", "South Korea"), gdp = 1:2)
  b <- data.frame(nation = c("Czech Republic", "Korea, Rep."), pop = c(10, 51))
  iso <- country_join(a, b, country, nation)
  expect_true("iso3c" %in% names(iso))
  gw <- country_join(a, b, country, nation, key = "gwn")
  expect_true("gwn" %in% names(gw))
  expect_false("iso3c" %in% names(gw))
  expect_equal(nrow(gw), 2L)
  expect_error(country_join(a, b, country, nation, key = "nope"), "`key`")
})

test_that("the alternate spine warns about the territories it cannot carry", {
  a <- data.frame(country = "Hong Kong", gdp = 1)
  b <- data.frame(nation = "Hong Kong SAR, China", pop = 7)
  # COW/GW cover sovereign states, so a dependency has no code. A two-sided
  # join warns once per side, and the two must be distinguishable -- they were
  # once the identical sentence twice, with nothing to say which table each
  # referred to.
  w <- character(0)
  withCallingHandlers(country_join(a, b, country, nation, key = "gwn"),
                      warning = function(x) {
                        w <<- c(w, conditionMessage(x))
                        invokeRestart("muffleWarning")
                      })
  expect_length(w, 2L)
  expect_match(w[1], "in .x.")
  expect_match(w[2], "in .y.")
  expect_true(all(grepl("no .*gwn.* code", w)))
})

test_that("the renamed holdovers now announce their deprecation", {
  # Structural, not behavioural: the notice is `.frequency = "once"`, so whether
  # it fires here depends on whether another test tripped it first. The package
  # tests its other one-shot notices the same way.
  src <- paste(deparse(countryatlas::wdj_overrides), collapse = " ")
  expect_match(src, "is deprecated", fixed = TRUE)
  expect_match(src, "deprecatedWarning", fixed = TRUE)
  expect_false(grepl("is deprecated",
                     paste(deparse(countryatlas::country_overrides),
                           collapse = " "), fixed = TRUE))
  # ...and it still returns the same table it always did.
  expect_identical(suppressWarnings(wdj_overrides()), country_overrides())
})

# --- subnational ----------------------------------------------------------------------

test_that("standardize_subnational passes ISO 3166-2 codes through", {
  d <- data.frame(region = c("DE-BY", "DE-HE", "Nowhere at all"), v = 1:3)
  out <- suppressWarnings(standardize_subnational(d, region, country = "Germany"))
  expect_true(all(c("iso3c", "iso_3166_2") %in% names(out)))
  expect_equal(out$iso3c, rep("DEU", 3))
  expect_equal(out$iso_3166_2[1:2], c("DE-BY", "DE-HE"))
  # Never a guess: an unresolvable region is NA.
  expect_true(is.na(out$iso_3166_2[3]))
})

test_that("standardize_subnational takes country as a column or a literal", {
  d <- data.frame(region = c("DE-BY", "FR-ARA"),
                  cty = c("Germany", "France"), v = 1:2)
  out <- suppressWarnings(standardize_subnational(d, region, country = cty))
  expect_equal(out$iso3c, c("DEU", "FRA"))
})

test_that("nuts_geometry validates the vintage before reaching the network", {
  skip_if_not_installed("giscoR")
  expect_error(nuts_geometry(year = 1999), "NUTS vintage")
  expect_error(nuts_geometry(level = 9), "level")
})

# --- independent validation against spdep -----------------------------------------
#
# The spatial statistics are implemented from the papers rather than delegated,
# so they need an outside opinion. spdep is the reference implementation; these
# check the arithmetic, not the API.

test_that("the spatial statistics match spdep", {
  skip_if_not_installed("spdep")
  w <- country_weights("knn", k = 5)
  al <- countryatlas:::align_weights(snap, "gdp_per_capita", w)
  m <- al$m; x <- al$x; n <- length(x)
  lw <- suppressWarnings(spdep::mat2listw(m, style = "W", zero.policy = TRUE))

  expect_equal(morans_i(snap, gdp_per_capita, weights = w, n_perm = 0)$i,
               spdep::moran(x, lw, n = n, S0 = spdep::Szero(lw),
                            zero.policy = TRUE)$I,
               tolerance = 1e-8)

  expect_equal(gearys_c(snap, gdp_per_capita, weights = w, n_perm = 0)$c,
               spdep::geary(x, lw, n = n, n1 = n - 1, S0 = spdep::Szero(lw),
                            zero.policy = TRUE)$C,
               tolerance = 1e-8)

  expect_equal(
    as.numeric(local_morans(snap, gdp_per_capita, weights = w, n_perm = 0)$ii),
    as.numeric(spdep::localmoran(x, lw, zero.policy = TRUE)[, "Ii"]),
    tolerance = 1e-6)

  sl <- spatial_lag(snap, gdp_per_capita, weights = w)
  expect_equal(sl$gdp_per_capita_lag[match(al$iso3c, sl$iso3c)],
               as.numeric(spdep::lag.listw(lw, x, zero.policy = TRUE)),
               tolerance = 1e-8)
})

test_that("getis_ord matches spdep's G*i", {
  skip_if_not_installed("spdep")
  w <- country_weights("knn", k = 5)
  al <- countryatlas:::align_weights(snap, "gdp_per_capita", w)
  ms <- al$m; diag(ms) <- 1
  lws <- suppressWarnings(spdep::mat2listw(ms, style = "B", zero.policy = TRUE))
  # spdep switches from Gi to G*i only when the neighbour list is *marked* as
  # self-inclusive -- mat2listw does not set that attribute, so without this the
  # comparison silently pits our G*i against spdep's Gi and looks like a bug.
  attr(lws$neighbours, "self.included") <- TRUE
  expect_equal(as.numeric(getis_ord(snap, gdp_per_capita, weights = w)$z_score),
               as.numeric(spdep::localG(al$x, lws, zero.policy = TRUE)),
               tolerance = 1e-8)
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

# --- provenance is a promise, so it has to hold for every verb ----------------------

test_that("every map verb carries provenance", {
  skip_if_not_installed("maps")
  poly <- poly_df()
  # map_provenance() documents itself as reading "any plot the package's map
  # verbs produced". For most of 3.0.0's development that was true of world_map()
  # alone -- the ten verbs that assemble their own ggplot carried nothing, and
  # the gap was invisible until someone relied on it.
  verbs <- list(
    world_map          = function() world_map(poly, gdp_per_capita),
    bubble_map         = function() bubble_map(snap, population),
    spike_map          = function() spike_map(snap, population),
    tile_map           = function() tile_map(snap, gdp_per_capita),
    flow_map           = function() flow_map(data.frame(from = "France",
                                                        to = "Germany"), from, to),
    facet_map          = function() facet_map(poly, gdp_per_capita, continent),
    coverage_map       = function() coverage_map(poly, gdp_per_capita),
    classify_compare   = function() classify_compare(poly, gdp_per_capita),
    value_by_alpha_map = function() value_by_alpha_map(poly, gdp_per_capita,
                                                       population),
    gridded_cartogram  = function() suppressWarnings(
      gridded_cartogram(snap, population, cells = 200))
  )
  for (nm in names(verbs)) {
    # bubble_map()/spike_map() now warn about the countries with no bundled
    # centroid; that behaviour has its own test, and this one is about
    # provenance.
    prov <- map_provenance(suppressWarnings(verbs[[nm]]()))
    # expect_s3_class() takes no label, so name the verb via expect_true().
    expect_true(inherits(prov, "countryatlas_provenance"), info = nm)
    expect_false(is.na(prov$backend), label = nm)
    expect_equal(prov$countryatlas,
                 as.character(utils::packageVersion("countryatlas")), label = nm)
  }
})

test_that("every sf map verb carries provenance", {
  skip_if_no_sf_geometry()
  d <- sf_df()
  expect_s3_class(map_provenance(world_map(d, gdp_per_capita)),
                  "countryatlas_provenance")
  expect_s3_class(
    map_provenance(suppressWarnings(bubble_map(d, population, backend = "sf"))),
    "countryatlas_provenance")
  expect_s3_class(map_provenance(globe_map(d, gdp_per_capita)),
                  "countryatlas_provenance")
  skip_if_not_installed("mapproj")
  expect_s3_class(
    map_provenance(globe_map(snap, continent, backend = "polygon",
                             style = "categorical")),
    "countryatlas_provenance")
  skip_if_not_installed("biscale")
  expect_s3_class(map_provenance(bivariate_map(d, gdp_per_capita,
                                               life_expectancy)),
                  "countryatlas_provenance")
  skip_if_not_installed("cartogram")
  expect_s3_class(map_provenance(cartogram_map(d, population)),
                  "countryatlas_provenance")
  expect_s3_class(map_provenance(dorling_map(d, population)),
                  "countryatlas_provenance")
})

# --- interactions between world_map()'s new arguments -------------------------------

test_that("the new world_map arguments combine without breaking each other", {
  skip_if_not_installed("maps")
  mapdf <- poly_df()
  set.seed(1)
  mapdf$se <- abs(stats::rnorm(nrow(mapdf))) * mapdf$gdp_per_capita * 0.3
  grid <- expand.grid(na_style = c("grey", "hatched", "outline", "omit"),
                      disputes = c("ignore", "mark"), unc = c(FALSE, TRUE),
                      stringsAsFactors = FALSE)
  for (i in seq_len(nrow(grid))) {
    g <- grid[i, ]
    args <- list(data = mapdf, fill = rlang::sym("gdp_per_capita"),
                 style = "quantile", na_style = g$na_style,
                 disputes = g$disputes, footnote = "auto")
    if (g$unc) args$uncertainty <- rlang::sym("se")
    expect_s3_class(ggplot2::ggplotGrob(do.call(world_map, args)), "gtable")
  }
})

test_that("a VSUP on a categorical fill is refused with useful advice", {
  skip_if_not_installed("maps")
  mapdf <- poly_df()
  mapdf$se <- 1
  # Falling through to the generic numeric check told the user to convert
  # `continent` to a number, which is nonsense advice for a category error.
  expect_error(world_map(mapdf, continent, style = "categorical",
                         uncertainty = se),
               "needs a numeric")
  expect_error(world_map(mapdf, continent, style = "categorical",
                         uncertainty = se),
               "no range to narrow")
})

test_that("coverage and the classification report count the same countries", {
  skip_if_not_installed("maps")
  mapdf <- poly_df()
  for (ns in c("grey", "omit")) {
    p <- world_map(mapdf, gdp_per_capita, style = "quantile", na_style = ns,
                   classification_report = TRUE)
    expect_equal(sum(attr(p, "countryatlas_classification")$n),
                 map_provenance(p)$n_countries, label = ns)
  }
  # `omit` drops rows before drawing, but coverage is counted before that, so
  # the reported numbers must not move.
  a <- map_provenance(world_map(mapdf, gdp_per_capita, na_style = "grey"))
  b <- map_provenance(world_map(mapdf, gdp_per_capita, na_style = "omit"))
  expect_equal(a$n_countries, b$n_countries)
  expect_equal(a$n_missing, b$n_missing)
})

test_that("map_provenance surfaces every field the verbs record", {
  skip_if_not_installed("maps")
  mapdf <- poly_df()
  set.seed(1)
  mapdf$se <- abs(stats::rnorm(nrow(mapdf)))
  mapdf$gdp_imputed <- mapdf$iso3c %in% c("FRA", "DEU")
  pr <- map_provenance(world_map(mapdf, gdp_per_capita, uncertainty = se,
                                 disputes = "mark", footnote = "auto"))
  # These were recorded by world_map() but dropped on the way out, so the
  # fields existed and could not be read.
  expect_equal(pr$uncertainty, "se")
  expect_equal(pr$disputes, "mark")
  expect_true(pr$n_imputed > 0)
  expect_false(is.na(pr$dispute_policy))
})

test_that("printing a subset of a provenance object does not crash", {
  skip_if_not_installed("maps")
  pr <- map_provenance(world_map(poly_df(), gdp_per_capita))
  # Subsetting a tibble keeps its class, so the print method still dispatches
  # with most columns absent -- which used to fail on `if (!is.na(NULL))`.
  expect_no_error(capture.output(print(pr[, c("fill", "style")]),
                                 type = "message"))
  expect_no_error(capture.output(print(pr[, "fill"]), type = "message"))
  expect_no_error(capture.output(print(pr), type = "message"))
})

# --- options are validated where they are read --------------------------------------

test_that("an unrecognised dispute_policy option falls back rather than propagating", {
  old <- getOption("countryatlas.dispute_policy")
  withr::defer(options(countryatlas.dispute_policy = old))
  # Every other option the package reads is validated on read; this one was not,
  # so a typo in .Rprofile printed "Convention: nonsense" on a published map --
  # on the very feature whose job is to state the convention truthfully.
  for (bad in list("nonsense", 42, c("none", "neutral"), TRUE)) {
    options(countryatlas.dispute_policy = bad)
    expect_equal(suppressWarnings(dispute_policy()), "none")
  }
  options(countryatlas.dispute_policy = NULL)
  expect_equal(dispute_policy(), "none")
  dispute_policy("neutral")
  expect_equal(dispute_policy(), "neutral")
})

test_that("a bogus dispute_policy cannot reach a map caption", {
  skip_if_not_installed("maps")
  old <- getOption("countryatlas.dispute_policy")
  withr::defer(options(countryatlas.dispute_policy = old))
  options(countryatlas.dispute_policy = "nonsense")
  cap <- suppressWarnings(
    world_map(poly_df(), gdp_per_capita, disputes = "mark")$labels$caption)
  expect_match(cap, "Convention: none")
  expect_false(grepl("nonsense", cap, fixed = TRUE))
})

# --- the extended functions stayed backward compatible ------------------------------

test_that("positional calls that worked before still mean the same thing", {
  # Every function that gained an argument this release: the new ones were
  # appended, so an existing positional call must be unaffected.
  expect_equal(nrow(country_groups("EU")), 27L)
  expect_true(in_group("FRA", "EU", "iso3c"))
  a <- data.frame(country = c("Czechia", "South Korea"), gdp = 1:2)
  b <- data.frame(nation = c("Czech Republic", "Korea, Rep."), pop = c(10, 51))
  j <- country_join(a, b, country, nation, "country.name", "country.name",
                    "left", c(".x", ".y"))
  expect_equal(nrow(j), 2L)
  expect_true("iso3c" %in% names(j))
  q <- world_query(gdp, "src", "robinson", "magma", "log10", "T", "spatial")
  expect_match(q, "PROJECT TO robinson")
  skip_if_not_installed("maps")
  expect_gt(nrow(world_geometry("countries", "polygon", "small", NULL,
                                "equal_earth", NULL)), 1000)
  expect_gt(nrow(attach_geometry(snap, "iso3c", "polygon", "small", NULL,
                                 "equal_earth", NULL)), 1000)
})

test_that("registering the built-in sources twice does not duplicate them", {
  n1 <- nrow(country_sources())
  countryatlas:::register_builtin_sources()
  expect_equal(nrow(country_sources()), n1)
})

test_that("country_join_all generalises country_join's key argument too", {
  t1 <- data.frame(country = c("Czechia", "South Korea"), gdp = c(1, 2))
  t2 <- data.frame(country = c("Czech Republic", "Korea, Rep."), pop = c(10, 51))
  t3 <- data.frame(country = c("Czechia", "Korea"), area = c(79, 100))
  # It documents itself as "the many-table generalisation of country_join()",
  # so it has to generalise the whole interface, not part of it.
  iso <- country_join_all(list(t1, t2, t3), by = "country")
  expect_true("iso3c" %in% names(iso))
  gw <- country_join_all(list(t1, t2, t3), by = "country", key = "gwn")
  expect_true("gwn" %in% names(gw))
  expect_false("iso3c" %in% names(gw))
  expect_equal(nrow(gw), 2L)
  # Positional calls from before the argument existed are unaffected.
  expect_equal(nrow(country_join_all(list(t1, t2), "country", "country.name",
                                     "full")), 2L)
  expect_error(country_join_all(list(t1, t2), by = "country", key = "nope"),
               "`key`")
})

test_that("an alternate-key multi-table join names which table it lost", {
  h <- list(data.frame(country = "Hong Kong", g = 1),
            data.frame(country = "France", p = 2))
  w <- character(0)
  withCallingHandlers(country_join_all(h, by = "country", key = "gwn"),
                      warning = function(x) {
                        w <<- c(w, conditionMessage(x))
                        invokeRestart("muffleWarning")
                      })
  expect_length(w, 1L)
  expect_match(w[1], "table 1")
})

# --- choice arguments name themselves when rejected ---------------------------------

test_that("a bad projection or scale is reported by name, from any entry point", {
  # match.arg() on a variable inside a helper produces R's anonymous
  # "'arg' should be one of ..." -- naming neither the argument nor the function
  # the user actually called. Seventeen exported functions take `projection` and
  # nine take `scale`, so this was one bad message reachable a great many ways.
  skip_if_no_sf_geometry()
  d <- sf_df()
  named <- function(expr) {
    e <- tryCatch(expr, error = function(e) e)
    expect_s3_class(e, "countryatlas_error")
    conditionMessage(e)
  }
  expect_match(named(world_map(d, gdp_per_capita, projection = "nope")),
               "`projection` must be one of")
  expect_match(named(tissot_map("nope")), "`projection` must be one of")
  expect_match(named(projection_distortion("nope")), "`projection` must be one of")
  expect_match(named(world_geometry("countries", "sf", scale = "nope")),
               "`scale` must be one of")
  expect_match(named(country_borders(scale = "nope")), "`scale` must be one of")
  expect_match(named(neighbors("France", scale = "nope")), "`scale` must be one of")
  expect_match(named(morans_i(snap, gdp_per_capita, scale = "nope", n_perm = 0)),
               "`scale` must be one of")
  skip_if_not_installed("cartogram")
  expect_match(named(dorling_map(d, population, projection = "nope")),
               "`projection` must be one of")
})

test_that("check_choice accepts the documented default and rejects the rest", {
  ch <- c("a", "b", "c")
  # A caller that passed nothing hands the whole default vector through, exactly
  # as match.arg() would, and must get the first element.
  expect_equal(countryatlas:::check_choice(ch, "x", ch), "a")
  expect_equal(countryatlas:::check_choice("b", "x", ch), "b")
  expect_error(countryatlas:::check_choice("z", "x", ch), "`x` must be one of")
  expect_error(countryatlas:::check_choice(c("a", "b"), "x", ch), "Got 2 values")
  expect_error(countryatlas:::check_choice(42, "x", ch), "`x` must be one of")
  expect_error(countryatlas:::check_choice(NULL, "x", ch), "`x` must be one of")
  # The defaults every caller relies on still resolve.
  expect_match(countryatlas:::wdj_crs(), "+proj=eqearth", fixed = TRUE)
  expect_identical(countryatlas:::ne_scale(), 110L)
})

test_that("wdj_workers honours the contract it documents", {
  w <- countryatlas:::wdj_workers
  # Every branch guarantees at least one worker, then min(workers, n_tasks)
  # undid it for zero tasks -- returning 0, which is exactly what `mc.cores`
  # refuses. wdj_lapply() short-circuits an empty input before it gets here, so
  # nothing hit it; the contract should not depend on the only caller
  # remembering to guard.
  expect_true(all(vapply(0:20, function(i) w(i) >= 1L, logical(1))))
  expect_true(all(vapply(1:20, function(i) w(i) <= i, logical(1))))
  old <- getOption("countryatlas.workers")
  withr::defer(options(countryatlas.workers = old))
  options(countryatlas.workers = 1)
  expect_equal(w(100), 1L)
})

test_that("wdj_lapply agrees with lapply and preserves order", {
  f <- function(i) i^2
  expect_identical(countryatlas:::wdj_lapply(1:6, f, parallel = TRUE),
                   countryatlas:::wdj_lapply(1:6, f, parallel = FALSE))
  expect_identical(unlist(countryatlas:::wdj_lapply(1:6, f, parallel = TRUE)),
                   (1:6)^2)
  expect_identical(countryatlas:::wdj_lapply(integer(0), f), list())
})

test_that("repair_country_names returns the documented repairs attribute", {
  r <- suppressMessages(repair_country_names(c("Fr4nce", "France")))
  expect_identical(as.character(r), c("France", "France"))
  a <- attr(r, "repairs")
  expect_s3_class(a, "tbl_df")
  expect_equal(nrow(a), 1L)
  expect_equal(a$from, "Fr4nce")
  expect_equal(a$to, "France")
  # An input needing no repair still carries the attribute, empty.
  expect_equal(nrow(attr(suppressMessages(repair_country_names("France")),
                         "repairs")), 0L)
})

test_that("every override maps to a code the package recognises", {
  ov <- country_overrides()
  expect_true(all(unname(ov) %in% countryatlas:::wdj_known_iso3c()))
  # And the overrides reach every entry point, not just one.
  probe <- names(ov)[1:6]
  expect_false(anyNA(standardize_country(data.frame(country = probe),
                                         country)$iso3c))
  expect_false(anyNA(convert_country(probe, to = "iso3c")))
  expect_identical(standardize_country(data.frame(country = probe), country)$iso3c,
                   unname(convert_country(probe, to = "iso3c")))
})

test_that("the source adapters validate `indicator` before doing anything else", {
  # All four are exported in their own right, so each has to repeat the check
  # fetch_indicator() does at its front door. Before this, fetch_owid(NULL) and
  # its eurostat/oecd siblings returned a silent NULL -- lapply() over an empty
  # vector produces no frames and Reduce() over an empty list is NULL -- while
  # fetch_comtrade() leaked comtradr's "subscript out of bounds". The check runs
  # ahead of need_pkg(), so this test needs none of the four clients installed.
  adapters <- list(owid = fetch_owid, eurostat = fetch_eurostat,
                   oecd = fetch_oecd, comtrade = fetch_comtrade)
  for (nm in names(adapters)) {
    for (bad in list(NULL, character(0), NA, 1L, list("a"))) {
      expect_error(adapters[[nm]](bad), "non-empty character vector",
                   info = paste(nm, deparse(bad)[1]))
    }
  }
  # The front door keeps its own guard.
  expect_error(fetch_indicator("wdi", NULL), "non-empty character vector")
})

test_that("subnational_map reports missing arguments and columns, not internals", {
  expect_error(subnational_map(NULL), "`fill` is required")
  expect_error(subnational_map(data.frame(geo = "DE1", v = 1), nope),
               "not found in `data`")
})

test_that("adapter_reshape names a missing column instead of failing on recycling", {
  # entity_col was checked; value_col was not, although fetch_eurostat() passes
  # "values" outright and fetch_oecd() guesses between two spellings. A provider
  # that changed shape produced as.numeric(NULL) -- a zero-length column in a
  # full-length tibble -- and a recycling error several frames away.
  ar <- countryatlas:::adapter_reshape
  raw <- tibble::tibble(geo = c("DE", "FR"), year = c(2020L, 2020L),
                        wrongname = c(1, 2))
  expect_error(ar(raw, "v", entity_col = "geo", year_col = "year",
                  value_col = "values"), "value column")
  expect_error(ar(raw, "v", entity_col = "nope", year_col = "year",
                  value_col = "wrongname"), "entity column")
  ok <- ar(raw, "v", entity_col = "geo", year_col = "year",
           value_col = "wrongname", origin = "eurostat")
  expect_named(ok, c("iso3c", "year", "v"))
  expect_equal(nrow(ok), 2L)
})

test_that("compare_sources summarises each pair on that pair alone", {
  # Every column of the summary is pairwise; n_disagree was not. It read the
  # row-wise `disagrees`, i.e. the spread across *all* sources, so with three
  # or more a pair that agreed exactly was counted as disagreeing whenever some
  # third source was the outlier.
  iso <- c("FRA", "DEU", "ITA", "ESP")
  mk <- function(v) function(indicator, countries = NULL, years = NULL, ...) {
    tibble::tibble(iso3c = iso, year = 2020L, value = v)
  }
  register_country_source("test_a", mk(c(100, 200, 300, 400)))
  register_country_source("test_b", mk(c(100, 200, 300, 400)))
  register_country_source("test_c", mk(rep(999, 4)))
  withr::defer(for (s in c("test_a", "test_b", "test_c"))
    suppressWarnings(rm(list = s, envir = countryatlas:::the_sources)))

  cmp <- compare_sources("x", sources = c("test_a", "test_b", "test_c"),
                         year = 2020)
  s <- attr(cmp, "countryatlas_source_summary")
  ab <- s[s$source_x == "test_a" & s$source_y == "test_b", ]
  expect_equal(ab$n_disagree, 0L)      # identical sources
  expect_equal(ab$correlation, 1)
  expect_equal(s$n_disagree[s$source_y == "test_c"], c(4L, 4L))
  # The row-wise column still reports the spread over all three.
  expect_true(all(cmp$rel_diff > 0))
})

test_that("a constant source gives NA correlation without warning", {
  iso <- c("FRA", "DEU", "ITA", "ESP")
  mk <- function(v) function(indicator, countries = NULL, years = NULL, ...) {
    tibble::tibble(iso3c = iso, year = 2020L, value = v)
  }
  register_country_source("test_v", mk(c(1, 2, 3, 4)))
  register_country_source("test_k", mk(rep(7, 4)))
  withr::defer(for (s in c("test_v", "test_k"))
    suppressWarnings(rm(list = s, envir = countryatlas:::the_sources)))
  expect_no_warning(
    cmp <- compare_sources("x", sources = c("test_v", "test_k"), year = 2020)
  )
  expect_true(is.na(attr(cmp, "countryatlas_source_summary")$correlation))
})

test_that("flow_matrix fill applies only to pairs with no flow", {
  # `fill` is documented as the value for pairs with no flow, but the matrix was
  # initialised to it and the weights accumulated on top, so fill = -1 turned a
  # flow of 10 into 9 -- and symmetric = TRUE doubled the fill on top of that.
  od <- data.frame(from = c("France", "Germany", "France"),
                   to   = c("Germany", "Italy", "Germany"),
                   w    = c(10, 20, 5))
  m <- flow_matrix(od, from, to, w, fill = -1)
  expect_equal(m["FRA", "DEU"], 15)   # accumulated, not 14
  expect_equal(m["DEU", "ITA"], 20)
  expect_equal(m["FRA", "ITA"], -1)   # genuinely absent
  # The default is unchanged.
  m0 <- flow_matrix(od, from, to, w)
  expect_equal(unname(m0[c("FRA", "DEU"), c("DEU", "ITA")][1, 1]), 15)
  expect_equal(m0["FRA", "ITA"], 0)
  # Symmetrising must not add the fill to itself.
  ms <- flow_matrix(od, from, to, w, symmetric = TRUE, fill = -1)
  expect_equal(ms["FRA", "DEU"], 15)
  expect_equal(ms["DEU", "FRA"], 15)
  expect_equal(ms["FRA", "ITA"], -1)
})

test_that("od_map says when a named origin sends no flow", {
  # Italy appears only as a destination, so it has nothing to draw. Filtering
  # the top-N list silently is what "top N" means; dropping an origin the
  # caller named by hand is not.
  od <- data.frame(from = c("France", "France"),
                   to   = c("Germany", "Italy"), w = c(10, 20))
  expect_warning(od_map(od, from, to, w, origins = c("France", "Italy")),
                 "named origin")
  expect_no_warning(od_map(od, from, to, w, origins = 6))
  # Nothing left to draw is still an error, not an empty plot.
  only_in <- data.frame(from = "France", to = "Germany", w = 1)
  expect_error(suppressWarnings(od_map(only_in, from, to, w,
                                       origins = "Germany")),
               "None of the chosen origins")
})

test_that("top_n is validated, not just tested for finiteness", {
  # check_number() rejects Inf, which is the documented "no limit", so the guard
  # was `if (is.finite(top_n))` alone -- and everything is.finite() rejects then
  # skipped validation entirely. top_n = "5" and NA silently returned every row.
  snap <- world_snapshot$countries
  for (bad in list("5", NA, NULL, character(0), c(1, 2))) {
    expect_error(world_table(snap, gdp_per_capita, top_n = bad,
                             engine = "tibble"), "top_n")
  }
  expect_equal(nrow(world_table(snap, gdp_per_capita, top_n = 5,
                                engine = "tibble")), 5L)
  # Inf still means no limit.
  expect_gt(nrow(world_table(snap, gdp_per_capita, top_n = Inf,
                             engine = "tibble")), 5L)
  # country_network() carried the same unguarded pattern.
  od <- data.frame(from = "France", to = "Germany", w = 1)
  expect_error(country_network(od, from, to, w, top_n = "5"), "top_n")
})

test_that("world_table rejects a subtitle with no title", {
  # gt draws the subtitle inside the header block a title opens, so on its own
  # it had nowhere to go and was dropped without a word.
  skip_if_not_installed("gt")
  snap <- world_snapshot$countries
  expect_error(world_table(snap, gdp_per_capita, top_n = 3, subtitle = "x"),
               "needs a")
  expect_s3_class(world_table(snap, gdp_per_capita, top_n = 3,
                              title = "t", subtitle = "x"), "gt_tbl")
})

test_that("interpolate_missing flags the rows it actually filled", {
  # The "was missing" vectors were captured off the input and compared against
  # the output further down -- but the pipeline in between arranges by
  # (iso3c, year), so the two lined up only for an already-sorted input. Given
  # anything else the flags landed on the wrong rows: observed values came back
  # marked imputed, imputed ones came back marked observed, and world_map()
  # believes this column when it writes its caption.
  unsorted <- tibble::tibble(
    iso3c = c("FRA", "DEU", "FRA", "DEU", "FRA", "DEU"),
    year  = c(2022, 2022, 2021, 2021, 2020, 2020),
    v     = c(30, 300, NA, NA, 10, 100))
  out <- interpolate_missing(unsorted, "v")

  # Only the two 2021 cells were ever missing.
  filled <- out$iso3c[out$v_imputed]
  expect_setequal(paste(out$iso3c, out$year)[out$v_imputed],
                  c("DEU 2021", "FRA 2021"))
  expect_equal(sum(out$v_imputed), 2L)
  # and they are the interpolated midpoints, not the observed endpoints.
  expect_equal(out$v[out$v_imputed], c(200, 20))
  expect_false(any(out$v_imputed[out$year != 2021]))

  # An already-sorted frame gives the same answer, as it always did.
  sorted <- dplyr::arrange(unsorted, iso3c, year)
  expect_equal(interpolate_missing(sorted, "v")$v_imputed,
               c(FALSE, TRUE, FALSE, FALSE, TRUE, FALSE))
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

test_that("value_by_alpha_map keeps opacity absolute", {
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

test_that("a VSUP counts coverage on both columns, not just the fill", {
  # A value-suppressing palette needs a value *and* an uncertainty, so a country
  # with only the first gets no colour. `coverage` counted missing fill values
  # alone, so footnote = "auto" -- the feature whose whole job is to stop a map
  # overstating what it covers -- claimed every one of those countries was
  # shown.
  skip_if_no_sf_geometry()
  set.seed(1)
  snap <- world_snapshot$countries
  snap$unc <- abs(stats::rnorm(nrow(snap)))
  snap$unc[1:120] <- NA_real_
  m <- attach_geometry(snap, geometry = "sf")
  # Count distinct countries, as na_coverage() does -- the sf frame carries more
  # than one row for a few of them, so a row count is off by a couple.
  n_countries <- function(x, ...) {
    d <- sf::st_drop_geometry(x)
    ok <- Reduce(`&`, lapply(c(...), function(v) !is.na(d[[v]])))
    length(unique(stats::na.omit(d$iso3c[ok])))
  }
  both <- n_countries(m, "gdp_per_capita", "unc")

  expect_warning(
    p <- world_map(m, gdp_per_capita, uncertainty = unc, footnote = "auto"),
    "no colour to give")
  expect_match(p$labels$caption, paste0("^", both, " of "))
  expect_equal(attr(p, "countryatlas_provenance")$coverage$n_shown, both)

  # Without `uncertainty`, coverage is the fill column exactly as before.
  p2 <- world_map(m, gdp_per_capita, footnote = "auto")
  expect_equal(attr(p2, "countryatlas_provenance")$coverage$n_shown,
               n_countries(m, "gdp_per_capita"))
  # And a fully-covered uncertainty column changes nothing and stays quiet.
  snap2 <- world_snapshot$countries
  snap2$unc <- abs(stats::rnorm(nrow(snap2)))
  m2 <- attach_geometry(snap2, geometry = "sf")
  expect_no_warning(
    p3 <- world_map(m2, gdp_per_capita, uncertainty = unc, footnote = "auto"))
  expect_equal(attr(p3, "countryatlas_provenance")$coverage$n_shown,
               n_countries(m2, "gdp_per_capita"))
})

test_that("bivariate_map counts coverage on both variables", {
  # A bivariate class needs both variables, so a country holding only one is
  # drawn as no-data -- but provenance counted the x column alone and called it
  # shown. Same overstatement the VSUP path made, in a different verb.
  skip_if_not_installed("sf")
  skip_if_not_installed("biscale")
  skip_if_not_installed("rnaturalearth")
  snap <- world_snapshot$countries
  snap$y2 <- snap$life_expectancy
  snap$y2[1:120] <- NA_real_
  m <- attach_geometry(snap, geometry = "sf")
  drop_geom <- sf::st_drop_geometry(m)
  both <- length(unique(stats::na.omit(
    drop_geom$iso3c[!is.na(drop_geom$gdp_per_capita) & !is.na(drop_geom$y2)])))

  expect_warning(p <- bivariate_map(m, gdp_per_capita, y2), "no class to give")
  expect_equal(attr(p, "countryatlas_provenance")$coverage$n_shown, both)

  # Two fully-covered variables stay quiet and report the usual number.
  m2 <- attach_geometry(world_snapshot$countries, geometry = "sf")
  expect_no_warning(p2 <- bivariate_map(m2, gdp_per_capita, life_expectancy))
  expect_gt(attr(p2, "countryatlas_provenance")$coverage$n_shown, both)
})

test_that("a cartogram reports the world it started from, not the one it kept", {
  # A cartogram can only size a country it has a positive weight for, so the
  # rest are dropped -- silently, and provenance was computed on the survivors,
  # so n_total shrank to match. A map of 69 countries out of 175 reported
  # "69 of 73", i.e. near-complete coverage of a world it had quietly cut down.
  skip_if_not_installed("sf")
  skip_if_not_installed("cartogram")
  skip_if_not_installed("rnaturalearth")
  snap <- world_snapshot$countries
  snap$w2 <- snap$population
  snap$w2[1:120] <- NA_real_
  m <- attach_geometry(snap, geometry = "sf")
  full_total <- length(unique(stats::na.omit(sf::st_drop_geometry(m)$iso3c)))

  expect_warning(p <- dorling_map(m, w2, fill = gdp_per_capita), "cannot be sized")
  cov <- attr(p, "countryatlas_provenance")$coverage
  expect_gte(cov$n_total, full_total)      # the whole world, not the survivors
  expect_lt(cov$n_shown, cov$n_total)
  # Distinct countries, as na_coverage() counts them: the sf frame carries more
  # than one row for a few, so a row count is off by a couple.
  d <- sf::st_drop_geometry(m)
  expect_equal(cov$n_shown, length(unique(stats::na.omit(
    d$iso3c[!is.na(d$w2) & !is.na(d$gdp_per_capita)]))))

  # A fully-weighted frame keeps the old numbers and stays quiet.
  m2 <- attach_geometry(world_snapshot$countries, geometry = "sf")
  expect_no_warning(p2 <- dorling_map(m2, population, fill = gdp_per_capita))
  cov2 <- attr(p2, "countryatlas_provenance")$coverage
  expect_equal(cov2$n_total, cov$n_total)
})

test_that("gridded_cartogram reports the whole input as its denominator", {
  # Two filters drop countries the grid cannot represent -- no positive value,
  # no bundled centroid -- and provenance was computed on whatever survived
  # them, so n_total shrank to match. A grid covering 94 of 215 countries
  # reported "94 of 94", i.e. perfect coverage of a world it had cut down. Only
  # the centroid drop was ever mentioned.
  snap <- world_snapshot$countries
  snap$w2 <- snap$population
  snap$w2[1:120] <- NA_real_
  n_in <- length(unique(stats::na.omit(snap$iso3c)))

  # Two warnings here: the missing weights, and the one country with no bundled
  # centroid. Nest so neither escapes into the suite summary.
  expect_warning(
    expect_warning(p <- gridded_cartogram(snap, w2, cells = 300), "no positive"),
    "no bundled centroid")
  cov <- attr(suppressWarnings(gridded_cartogram(snap, w2, cells = 300)),
              "countryatlas_provenance")$coverage
  expect_equal(cov$n_total, n_in)
  expect_lt(cov$n_shown, cov$n_total)
  # `shown` is exactly what got cells.
  expect_equal(cov$n_shown, nrow(attr(p, "countryatlas_cells")))
})

test_that("coverage does not count an uncoded geometry row as a country", {
  # The bundled sf basemap carries one row with no iso3c. Counting it put a
  # phantom in the denominator and in n_missing, while missing_iso3c -- which
  # sorts, and so drops NA -- listed one fewer than n_missing claimed: the
  # caption said "17 missing" where provenance could name only 16.
  skip_if_no_sf_geometry()
  m <- attach_geometry(world_snapshot$countries, geometry = "sf")
  d <- sf::st_drop_geometry(m)
  skip_if(!any(is.na(d$iso3c)), "basemap has no uncoded row to exclude")

  cov <- countryatlas:::na_coverage(m, "gdp_per_capita")
  expect_equal(cov$n_missing, length(cov$missing_iso3c))
  expect_equal(cov$n_total, dplyr::n_distinct(stats::na.omit(d$iso3c)))
  expect_false(anyNA(cov$missing_iso3c))
  # And the caption agrees with what provenance can actually name.
  p <- world_map(m, gdp_per_capita, footnote = "auto")
  expect_match(p$labels$caption,
               paste0(cov$n_missing, " missing"), fixed = TRUE)
})

test_that("a bare `as_of` year means 1 January of that year", {
  # The convention decides the answer at every mid-year accession, and reading
  # `as_of = 2013` as "during 2013" gives the opposite result. Pinned so it
  # cannot drift away from what the documentation now promises.
  expect_equal(countryatlas:::as_of_date(2013), as.Date("2013-01-01"))
  # Croatia joined on 2013-07-01.
  expect_false(in_group("Croatia", "EU", as_of = 2013))
  expect_false(in_group("Croatia", "EU", as_of = "2013-06-30"))
  expect_true(in_group("Croatia", "EU", as_of = "2013-07-01"))
  expect_true(in_group("Croatia", "EU", as_of = 2014))
  # The UK left on 2020-01-31, so a bare 2020 still counts it in.
  expect_true(in_group("United Kingdom", "EU", as_of = 2020))
  expect_false(in_group("United Kingdom", "EU", as_of = "2020-06-01"))
  # The 2004 enlargement -- ten countries on 2004-05-01 -- is the largest
  # single accession and the one most likely to be entered as a bare year.
  for (cty in c("Poland", "Czechia", "Hungary", "Estonia")) {
    expect_false(in_group(cty, "EU", as_of = 2004), info = cty)
    expect_false(in_group(cty, "EU", as_of = "2004-04-30"), info = cty)
    expect_true(in_group(cty, "EU", as_of = "2004-05-01"), info = cty)
    expect_true(in_group(cty, "EU", as_of = 2005), info = cty)
  }
  # A 1 January accession is in on the day: Estonia adopted the euro
  # 2011-01-01, so a bare 2011 counts it in where a bare 2004 did not.
  expect_true(in_group("Estonia", "EuroZone", as_of = 2011))
  expect_false(in_group("Estonia", "EuroZone", as_of = 2010))
})

test_that("add_indicator overwrites a clashing column, as its warning says", {
  # warn_overwrite() promised "Overwriting ... rename them first to keep the
  # original values", but the left_join underneath suffixed both sides to
  # `x.x`/`x.y` instead -- so the caller got neither the column they asked for
  # nor the one they had, and the advice described a mechanism that never ran.
  mk <- function(v) function(indicator, countries = NULL, years = NULL, ...) {
    tibble::tibble(iso3c = c("FRA", "DEU"), val = v)
  }
  register_country_source("test_clash", mk(c(99, 98)))
  withr::defer(suppressWarnings(
    rm(list = "test_clash", envir = countryatlas:::the_sources)))

  d <- tibble::tibble(iso3c = c("FRA", "DEU"), val = c(1, 2))
  expect_warning(out <- add_indicator(d, "test_clash", "x"), "Overwriting")
  expect_named(out, c("iso3c", "val"))
  expect_equal(out$val, c(99, 98))
  expect_false(any(grepl("[.](x|y)$", names(out))))

  # No clash: unchanged, and quiet.
  d2 <- tibble::tibble(iso3c = c("FRA", "DEU"), other = c(1, 2))
  expect_no_warning(o2 <- add_indicator(d2, "test_clash", "x"))
  expect_named(o2, c("iso3c", "other", "val"))
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
    aggregate_regions(d, v, "region", fun = "weighted_mean", weight = w)$v[1]
  }
  expect_true(is.na(g(c(10, 20), c(0, 0))))
  expect_false(is.nan(g(c(10, 20), c(0, 0))))
  expect_true(is.na(g(c(10, 20), c(5, -5))))   # cancel to zero
  expect_true(is.na(g(c(NA, NA), c(1, 3))))
  # Unchanged where there is weight to go on.
  expect_equal(g(c(10, 20), c(1, 3)), 17.5)
  expect_equal(g(c(10, NA), c(1, 3)), 10)
})

test_that("country_join reports names that reconcile to nothing", {
  # Reconciling both sides to a common key is the whole premise, so a name that
  # reconciles to nothing is the failure this verb exists to prevent -- and it
  # was the one join that never said so. wdj_to_key() only speaks up when a
  # name resolves to iso3c but has no COW/GW code, which on the default
  # key = "iso3c" is never.
  a <- tibble::tibble(country = c("France", "Germany", "Freedonia"), x = 1:3)
  b <- tibble::tibble(nation  = c("France", "Italy", "Ruritania"), y = 4:6)

  # Nested, so both warnings are consumed as well as asserted: one per side,
  # and an escaping warning would show up as noise in the suite summary.
  expect_warning(
    expect_warning(country_join(a, b, country, nation), "Freedonia"),
    "Ruritania")
  # Each side is named separately.
  w <- character(0)
  withCallingHandlers(country_join(a, b, country, nation),
                      warning = function(e) {
                        w <<- c(w, conditionMessage(e))
                        invokeRestart("muffleWarning")
                      })
  expect_length(w, 2L)
  expect_true(any(grepl("`x`", w, fixed = TRUE)))
  expect_true(any(grepl("`y`", w, fixed = TRUE)))

  # Opt out, and stay quiet when everything resolves.
  expect_no_warning(country_join(a, b, country, nation, warn = FALSE))
  clean_a <- tibble::tibble(country = "France", x = 1)
  clean_b <- tibble::tibble(nation = "France", y = 2)
  expect_no_warning(country_join(clean_a, clean_b, country, nation))
  # The join itself is unchanged.
  expect_equal(nrow(suppressWarnings(country_join(a, b, country, nation))), 3L)

  # country_join_all reports per table.
  expect_warning(
    expect_warning(country_join_all(list(a, b), by = c("country", "nation")),
                   "Freedonia"),
    "Ruritania")
  expect_no_warning(country_join_all(list(clean_a, clean_b),
                                     by = c("country", "nation")))
})

test_that("audit_coverage lists every unmatched country, not just one", {
  # The de-duplication that stops a polygon frame counting a country once per
  # vertex used distinct() on iso3c -- which treats NA as a single value, so
  # every *uncoded* country collapsed into one row. The tool the package points
  # at for "which countries are missing" named one of four, and `n` -- the
  # denominator of every na_rate it reports -- was short by the rest.
  d <- tibble::tibble(
    country = c("France", "Germany", "Freedonia", "Ruritania", "Elbonia"),
    iso3c   = c("FRA", "DEU", NA, NA, NA),
    gdp     = c(1, 2, 3, 4, 5))
  a <- audit_coverage(d)
  expect_equal(nrow(a$unmatched), 3L)
  expect_setequal(a$unmatched$country, c("Freedonia", "Ruritania", "Elbonia"))
  expect_equal(a$na_rates$n[1], 5L)
  expect_equal(a$na_rates$na_rate[1], 0)

  # Coded duplicates are still collapsed, so a polygon frame is not counted
  # once per vertex.
  dup <- tibble::tibble(country = c("France", "France", "Germany"),
                        iso3c = c("FRA", "FRA", "DEU"), gdp = c(1, 1, 2))
  expect_equal(audit_coverage(dup)$na_rates$n[1], 2L)
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

test_that("audit_coverage's numeric columns carry no vapply names", {
  # vapply() names its result after `indicator`, so a$na_rates$na_rate handed
  # back c(gdp = 0.1) rather than 0.1 -- the same wart country_network() calls
  # unname() on.
  d <- tibble::tibble(iso3c = c("FRA", "DEU"), country = c("France", "Germany"),
                      gdp = c(1, NA))
  a <- audit_coverage(d)
  expect_null(names(a$na_rates$na_rate))
  expect_null(names(a$na_rates$n_missing))
  expect_equal(a$na_rates$na_rate, 0.5)
})

test_that("a blank cell gets no country suggestion", {
  # The guard was nzchar() alone, so a whitespace-only cell went through to the
  # fuzzy matcher -- and Jaro-Winkler finds spurious similarity between a
  # two-space string and a name containing spaces, so "  " came back suggesting
  # "Congo - Kinshasa" at distance 0.29, well inside the 0.35 threshold. A
  # padded empty cell is the commonest thing a CSV import produces.
  r <- suppressWarnings(
    check_country_match(c("France", "  ", "", "\t\n", NA, "Frnace")))
  blank <- r$input %in% c("  ", "", "\t\n") | is.na(r$input)
  expect_true(all(is.na(r$suggestion[blank])))
  # A real typo still gets one. (%in%, not ==: `input` holds an NA, and
  # NA == "Frnace" is NA, which widens the subset rather than dropping it.)
  expect_equal(r$suggestion[r$input %in% "Frnace"], "France")
  expect_true(all(r$matched[r$input %in% "France"]))
})

test_that("subnational_map notices regions that match no geometry", {
  # The join keeps the geometry and discards unmatched data, so a caller whose
  # codes come from a different NUTS vintage lost those rows silently -- only a
  # *total* wipe-out was reported, though that error names the vintage problem
  # exactly. The counting is split out so it needs no GISCO round-trip.
  u <- countryatlas:::unmatched_keys
  expect_length(u(c("DE1", "DE2"), c("DE1", "DE2", "DE3")), 0L)
  expect_setequal(u(c("DE1", "XX9", "YY8"), c("DE1", "DE2")), c("XX9", "YY8"))
  expect_length(u(c("DE1", NA), "DE1"), 0L)          # NA is not a key
  expect_length(u(c("XX9", "XX9"), "DE1"), 1L)       # reported once
  expect_length(u(character(0), "DE1"), 0L)
})

test_that("projection_info's properties agree with measured distortion", {
  # The table is a set of factual claims about thirteen projections, and
  # projection_distortion() can check every one of them from the Jacobian. The
  # separation is two orders of magnitude, so this is a real assertion rather
  # than a tuned threshold: equal-area projections hold areal scale to a spread
  # of <= 0.014, every other projection spreads by >= 0.99; Mercator's maximum
  # angular deformation is 0.4 degrees, every non-conformal projection exceeds
  # 100. It also guards the sign convention -- the angular measure was once
  # written upside down, which put Mercator at 170 degrees instead of nearly 0.
  skip_if_not_installed("sf")
  info <- projection_info()

  for (p in info$projection[info$equal_area]) {
    d <- projection_distortion(p, measure = "areal", spacing = 20)$distortion
    expect_lt(diff(range(d, na.rm = TRUE)), 0.1)
  }
  for (p in info$projection[!info$equal_area]) {
    d <- projection_distortion(p, measure = "areal", spacing = 20)$distortion
    expect_gt(diff(range(d, na.rm = TRUE)), 0.1)
  }
  for (p in info$projection[info$conformal]) {
    d <- projection_distortion(p, measure = "angular", spacing = 20)$distortion
    expect_lt(max(d, na.rm = TRUE), 5)
  }
  for (p in info$projection[!info$conformal]) {
    d <- projection_distortion(p, measure = "angular", spacing = 20)$distortion
    expect_gt(max(d, na.rm = TRUE), 5)
  }
})

test_that("counts coerced with as.integer() carry an upper bound", {
  # check_number() with only `lo` lets a value past 2^31-1 through, and the
  # as.integer() below each of these turns it into NA with R's bare "NAs
  # introduced by coercion to integer range": world_query() then emitted
  # "BIN fill INTO NA", od_map()'s min(NA, nrow) reached seq_len(NA), and
  # convergence_club()'s size comparisons all became NA. compute_breaks() has
  # carried this bound since 2.0.0; these three had not.
  od <- data.frame(from = c("France", "Germany"),
                   to = c("Germany", "Italy"), w = c(1, 2))
  panel <- tibble::tibble(iso3c = rep(c("A", "B", "C"), each = 6),
                          year = rep(2000:2005, 3), v = as.numeric(1:18))
  expect_error(world_query(gdp, layer = "binned", n_bins = 3e9), "n_bins")
  expect_error(od_map(od, from, to, w, origins = 3e9), "origins")
  expect_error(convergence_club(panel, v, min_size = 3e9), "min_size")
  # Ordinary values are unaffected.
  expect_match(world_query(gdp, layer = "binned", n_bins = 5), "BIN fill INTO 5")
})

test_that("world_map says when it is handed a panel", {
  # attach_geometry() joins a panel deliberately -- facet_map() and
  # animate_world() are built on it -- so a multi-year frame reaching a single
  # static map draws each country once per year and lets the last row win,
  # silently, with a caption that still counts each country once.
  skip_if_not_installed("maps")
  snap <- world_snapshot$countries[, c("iso3c", "gdp_per_capita", "continent")]
  panel <- do.call(rbind, lapply(2018:2020, function(y) {
    s <- snap; s$year <- y; s
  }))
  pl <- suppressWarnings(attach_geometry(panel, geometry = "polygon"))

  expect_warning(world_map(pl, gdp_per_capita), "spans 3 years")
  # Faceting by year resolves the panel, so the warning would be wrong there.
  expect_no_warning(facet_map(pl, gdp_per_capita, year))
  expect_no_warning(animate_world(pl, gdp_per_capita))
  # Faceting by anything else does not resolve it: each continent panel still
  # stacks all three years, so there the warning is exactly right.
  expect_warning(facet_map(pl, gdp_per_capita, continent), "spans 3 years")
  # A cross-section is quiet.
  one <- suppressWarnings(attach_geometry(snap, geometry = "polygon"))
  expect_no_warning(world_map(one, gdp_per_capita))
  # Muffling is by class, so other warnings still get through.
  expect_true(is.function(countryatlas:::without_panel_warning))
})

test_that("one-row-per-country verbs say when they collapse a panel", {
  # Collapsing to one row per country is for repeated *geometry* rows, not for
  # time. Handed a panel these kept whichever row sorted first -- France's 2018
  # value of 10 out of 10/20/30 -- and presented that year as the answer with
  # nothing to say a choice had been made.
  panel <- tibble::tibble(
    iso3c = rep(c("FRA", "DEU"), each = 3),
    year  = rep(2018:2020, 2),
    v     = c(10, 20, 30, 100, 200, 300),
    pop   = rep(c(1e6, 2e6), each = 3),
    cases = 1:6)
  expect_warning(world_table(panel, v, engine = "tibble"), "spans 3 years")
  expect_warning(rate_check(panel, cases, pop), "spans 3 years")
  expect_warning(correlate_indicators(panel, v, pop), "spans 3 years")
  expect_warning(audit_coverage(panel), "spans 3 years")
  expect_warning(gridded_cartogram(panel, v, cells = 50), "spans 3 years")

  # A cross-section is quiet, and so is a geometry frame with one year.
  cs <- panel[panel$year == 2020, ]
  expect_no_warning(world_table(cs, v, engine = "tibble"))
  skip_if_not_installed("maps")
  poly <- suppressWarnings(
    attach_geometry(world_snapshot$countries, geometry = "polygon"))
  expect_no_warning(world_table(poly, gdp_per_capita, engine = "tibble"))
})

test_that("a repeated country-year is reported before it corrupts a lag", {
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

test_that("attach_geometry says when the key matches nothing at all", {
  # An unmatched code is ordinary here -- the basemap holds fewer countries than
  # the snapshot, since small states have no polygon at 110m -- so warning about
  # one would be noise. Zero matches is different: lowercase, mixed-case and
  # padded iso3c all matched nothing, and every country then drew as no-data
  # with nothing said. standardize_country() normalises all three.
  skip_if_not_installed("maps")
  bad <- function(v) tibble::tibble(iso3c = v, v = seq_along(v))
  for (v in list(c("fra", "deu"), c("Fra", "Deu"), c(" FRA ", " DEU "))) {
    expect_warning(attach_geometry(bad(v), geometry = "polygon"),
                   "matches the geometry")
  }
  # Correct codes, and the full snapshot, stay quiet.
  expect_no_warning(attach_geometry(bad(c("FRA", "DEU")), geometry = "polygon"))
  expect_no_warning(
    attach_geometry(world_snapshot$countries, geometry = "polygon"))
  # And the same for the sf backend.
  skip_if_no_sf_geometry()
  expect_warning(attach_geometry(bad(c("fra", "deu")), geometry = "sf"),
                 "matches the geometry")
  expect_no_warning(
    attach_geometry(world_snapshot$countries, geometry = "sf"))
})

test_that("tile_map and add_indicator say when the key matches nothing", {
  # Same failure as attach_geometry(): a lowercase or padded iso3c matches
  # nothing, so every tile drew grey and the fetched indicator arrived as a
  # column of pure NA -- which reads as "the provider has no data" rather than
  # "the join failed".
  lo <- tibble::tibble(iso3c = c("fra", "deu"), v = c(1, 2))
  up <- tibble::tibble(iso3c = c("FRA", "DEU"), v = c(1, 2))

  # Nothing joins, so the grid also reports both countries as unplaceable;
  # muffle that so the assertion stays on the key-matching warning.
  expect_warning(
    withCallingHandlers(
      tile_map(lo, v),
      countryatlas_no_centroid = function(c) invokeRestart("muffleWarning")),
    "matches the geometry")
  expect_no_warning(tile_map(up, v))
  # Placeable countries only: the grid omits Hong Kong and Macao, which
  # tile_map() reports separately, and this test is about key matching.
  placeable <- world_snapshot$countries[
    world_snapshot$countries$iso3c %in% world_tiles$iso3c, ]
  expect_no_warning(tile_map(placeable, gdp_per_capita))

  register_country_source("test_probe", function(indicator, countries = NULL,
                                                 years = NULL, ...) {
    tibble::tibble(iso3c = c("FRA", "DEU"), val = c(9, 8))
  })
  withr::defer(suppressWarnings(
    rm(list = "test_probe", envir = countryatlas:::the_sources)))

  expect_warning(out <- add_indicator(lo, "test_probe", "x"),
                 "none of which joined")
  expect_true(all(is.na(out$val)))
  expect_no_warning(ok <- add_indicator(up, "test_probe", "x"))
  expect_equal(ok$val, c(9, 8))
})

test_that("simplify_geometry and theme_world_map validate their first argument", {
  # Both checked their *second* argument carefully and their first not at all.
  # simplify_geometry() reached rmapshaper and leaked "no applicable method for
  # 'ms_simplify' applied to an object of class NULL" -- naming rmapshaper's
  # generic, not the argument -- and failed differently again through the
  # st_simplify() fallback, so the message depended on which optional package
  # the caller had. theme_world_map() got base R's bare "non-numeric argument
  # to binary operator".
  skip_if_not_installed("sf")
  for (bad in list(NULL, list(), NA, data.frame())) {
    expect_error(simplify_geometry(bad), "must be an <sf> frame")
  }
  expect_error(theme_world_map(list()), "base_size")
  expect_error(theme_world_map("a"), "base_size")
  expect_error(theme_world_map(NULL), "base_size")
  expect_error(theme_world_map(base_family = 1), "base_family")

  # Both still work on valid input, sf frame and bare sfc alike.
  skip_if_not_installed("rnaturalearth")
  g <- suppressWarnings(
    attach_geometry(world_snapshot$countries, geometry = "sf"))
  expect_s3_class(suppressWarnings(simplify_geometry(g, keep = 0.1)), "sf")
  expect_s3_class(suppressWarnings(
    simplify_geometry(sf::st_geometry(g), keep = 0.1)), "sfc")
  expect_s3_class(theme_world_map(), "theme")
  expect_s3_class(theme_world_map(14), "theme")
})

test_that("distance_between separates a missing centroid from a bad name", {
  # Two reasons for an NA distance, and only one is the documented gap.
  # "Resolved to a country that has no bundled centroid" is expected --
  # ?distance_between says so and country_weights() already reports it -- so it
  # must stay quiet. "Did not resolve to a country at all", usually the wrong
  # `origin`, returned a column of NA with nothing said.
  meta <- countryatlas::country_meta
  no_centroid <- setdiff(meta$iso3c,
                         meta$iso3c[!is.na(meta$centroid_lon)])

  # The documented gaps stay quiet.
  if (length(no_centroid)) {
    expect_no_warning(
      distance_between(utils::head(no_centroid, 3), "FRA", origin = "iso3c"))
  }
  expect_no_warning(distance_between("Kosovo", "Serbia"))
  expect_no_warning(distance_between("France", "Germany"))

  # A name that is not a country does not.
  expect_warning(distance_between("France", "Freedonia"),
                 "did not resolve to a country")
  # Nor does the classic mistake of reading names with origin = "iso3c".
  expect_warning(d <- distance_between("France", "Germany", origin = "iso3c"),
                 "Check `origin`")
  expect_true(is.na(d))
  # The distances themselves are unchanged.
  expect_equal(round(distance_between("France", "Germany")), 802)
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

test_that("tile_map draws one cell per country, panel or not", {
  # The grid has exactly one cell per country, so joining a panel to it fanned
  # the cells out -- 239 became 659 overlapping tiles, each country's drawn once
  # per year with the last row winning, silently. The other one-cell-per-country
  # verbs go through distinct_countries(); this one joined the grid directly and
  # was missed when they were converted.
  snap <- world_snapshot$countries[, c("iso3c", "gdp_per_capita")]
  panel <- do.call(rbind, lapply(2018:2020, function(y) {
    s <- snap; s$year <- y; s
  }))
  cells <- function(p) nrow(ggplot2::ggplot_build(p)$data[[1]])
  grid_n <- nrow(countryatlas::world_tiles)

  cs <- suppressWarnings(tile_map(snap, gdp_per_capita))
  expect_equal(cells(cs), grid_n)
  # tile_map() also reports the countries the grid cannot place; muffle just
  # that so the assertion stays on the panel warning under test.
  expect_warning(
    pn <- withCallingHandlers(
      tile_map(panel, gdp_per_capita),
      countryatlas_no_centroid = function(c) invokeRestart("muffleWarning")),
    "spans 3 years")
  expect_equal(cells(pn), grid_n)
})

test_that("interpolate_missing reports a repeated country-year", {
  # Worse here than a wrong lag: stats::approx() collapses tied x-values to
  # their mean, so the two rows for the repeated year were *overwritten* with
  # the average -- 20 and 999 both became 509.5 -- and `_imputed` said FALSE for
  # them, because it compares "was NA" against "is not NA" and neither was ever
  # NA. The safeguard the code documents (a filler that changes an observed
  # value shows up as a flagged cell) cannot catch that, so the input is
  # reported instead.
  dup <- tibble::tibble(iso3c = rep("FRA", 5),
                        year = c(2018L, 2019L, 2019L, 2020L, 2021L),
                        v = c(10, 20, 999, NA, 40))
  expect_warning(interpolate_missing(dup, "v"), "repeated country-year")

  # A clean panel is silent, fills the gap linearly, and flags exactly it.
  clean <- tibble::tibble(iso3c = rep("FRA", 4), year = 2018:2021,
                          v = c(10, 20, NA, 40))
  expect_no_warning(out <- interpolate_missing(clean, "v"))
  expect_equal(out$v[out$year == 2020], 30)
  expect_true(out$v_imputed[out$year == 2020])
  expect_false(any(out$v_imputed[out$year != 2020]))
  # Observed values are untouched.
  expect_equal(out$v[out$year != 2020], c(10, 20, 40))

  # complete_years() shares the interpolator and must stay quiet too.
  expect_no_warning(cy <- complete_years(clean, value = "v", method = "linear"))
  expect_equal(cy$v[cy$year == 2020], 30)
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

test_that("compare_sources rejects an unnamed multi-code indicator", {
  # The named branch's error already told callers to "pass a single unnamed
  # code", but nothing enforced it: an unnamed vector was truncated to its
  # first element and broadcast to every source. For this verb specifically
  # that is the worst possible failure -- it then compares a code against
  # itself and reports the sources as agreeing perfectly.
  iso <- c("FRA", "DEU")
  mk <- function() function(indicator, countries = NULL, years = NULL, ...) {
    tibble::tibble(iso3c = iso, year = 2020L,
                   value = if (identical(indicator[[1]], "A")) c(1, 2) else c(9, 9))
  }
  register_country_source("test_s1", mk())
  register_country_source("test_s2", mk())
  withr::defer(for (s in c("test_s1", "test_s2"))
    suppressWarnings(rm(list = s, envir = countryatlas:::the_sources)))
  src <- c("test_s1", "test_s2")

  expect_error(compare_sources(c("A", "B"), sources = src, year = 2020),
               "must be a single code")
  # The three documented shapes still work.
  expect_equal(nrow(compare_sources("A", sources = src, year = 2020)), 2L)
  named <- compare_sources(c(test_s1 = "A", test_s2 = "B"), sources = src,
                           year = 2020)
  expect_equal(nrow(named), 2L)
  # A named vector really does give each source its own code.
  expect_false(isTRUE(all.equal(named$test_s1, named$test_s2)))
  expect_error(compare_sources(c(test_s1 = "A"), sources = src, year = 2020),
               "names no code")
})

test_that("audit_coverage's by_group names the indicator it measured", {
  # The rate has always been computed on indicator[1] -- with the default
  # indicator = NULL that is whichever numeric column comes first -- but the
  # column was called plain `na_rate` under a heading reading "Coverage by
  # group", so it read as the group's overall coverage while the other
  # indicators were silently left out.
  snap <- world_snapshot$countries
  a <- audit_coverage(snap)
  expect_true("indicator" %in% names(a$by_group))
  expect_equal(unique(a$by_group$indicator), a$na_rates$indicator[1])
  # na_rates still covers every indicator, and they genuinely differ -- which is
  # why naming the one in by_group matters.
  expect_gt(nrow(a$na_rates), 1L)
  expect_gt(length(unique(a$na_rates$na_rate)), 1L)
  # The by_group rate is that indicator's rate, not an average across them.
  first <- a$na_rates$indicator[1]
  expect_equal(
    weighted.mean(a$by_group$na_rate, a$by_group$n_countries),
    mean(is.na(snap[[first]])), tolerance = 1e-8)
  # An explicit indicator is named as itself.
  b <- audit_coverage(snap, indicator = "co2_per_capita")
  expect_equal(unique(b$by_group$indicator), "co2_per_capita")
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

test_that("wdi_search and spin_globe validate the arguments they were missing", {
  # wdi_search() checked `field` and nothing else. A non-string `pattern` went
  # straight into the regex and matched something: wdi_search(1) returned
  # 10,125 rows and wdi_search(NA) the entire catalogue, both silently.
  for (bad in list(1, NA, c("a", "b"), list(), character(0))) {
    expect_error(wdi_search(bad), "must be a single string")
  }
  expect_gt(nrow(wdi_search("energy")), 0L)
  # `cache` is a WDIcache() object; anything atomic reached WDI and died on
  # "$ operator is invalid for atomic vectors".
  expect_error(wdi_search("energy", cache = "yes"), "WDIcache")
  expect_error(wdi_search("energy", cache = TRUE), "WDIcache")
  expect_gt(nrow(wdi_search("energy", cache = NULL)), 0L)

  # spin_globe() validates every other argument before gating on the animation
  # packages -- its own comment says a bad argument is the caller's bug -- but
  # `file` slipped through to base R's "invalid 'path' argument".
  skip_if_not_installed("maps")
  snap <- world_snapshot$countries
  for (bad in list(1, NA, c("a", "b"))) {
    expect_error(spin_globe(snap, gdp_per_capita, file = bad,
                            backend = "polygon", n_frames = 2),
                 "must be a single string")
  }
})

test_that("custom_match must be a name -> iso3c map", {
  # `origin` was checked and the override table was not, though every value in
  # it lands in the iso3c column -- and wdj_to_iso3c()'s iso3c branch
  # whitelists those values as valid by construction, so nothing downstream
  # rejected them either. custom_match = c(Freedonia = 1) put "1" in iso3c.
  d <- tibble::tibble(n = c("France", "Freedonia"))
  expect_error(standardize_country(d, n, custom_match = c(Freedonia = 1)),
               "named character vector")
  expect_error(standardize_country(d, n, custom_match = c("FRA")),
               "named character vector")
  expect_error(standardize_country(d, n, custom_match = c(Freedonia = TRUE)),
               "named character vector")

  # The shapes that worked still work.
  ok <- suppressWarnings(
    standardize_country(d, n, custom_match = c(Freedonia = "FRA")))
  expect_equal(ok$iso3c, c("FRA", "FRA"))
  expect_no_error(suppressWarnings(
    standardize_country(d, n, custom_match = character(0))))
  expect_no_error(suppressWarnings(standardize_country(d, n)))
  # Including the bundled table, which is exactly this shape.
  expect_type(country_overrides(), "character")
  expect_false(is.null(names(country_overrides())))
})

test_that("`add` reports its own problems, not countrycode's", {
  # `add` names attributes to derive from iso3c. Unvalidated, its problems came
  # back under somebody else's argument: countrycode's `destination` for an
  # unknown name ("must be ... one of the column names in the conversion
  # directory"), convert_country()'s `to` in locate_country(), and base R's
  # bare "missing value where TRUE/FALSE needed" for an NA.
  d <- tibble::tibble(n = "France")
  expect_error(standardize_country(d, n, add = "nope"), "`add` names")
  expect_error(standardize_country(d, n, add = 1), "`add` must be a character")
  expect_error(standardize_country(d, n, add = NA), "`add` must be a character")
  expect_error(standardize_country(d, n, add = TRUE), "`add` must be a character")

  # Both kinds of valid name still work: the shortcuts and any raw countrycode
  # destination.
  expect_no_error(suppressWarnings(standardize_country(d, n, add = "continent")))
  expect_no_error(suppressWarnings(standardize_country(d, n, add = "iso4217c")))
  expect_no_error(suppressWarnings(standardize_country(d, n, add = character(0))))
  expect_equal(ncol(suppressWarnings(standardize_country(d, n))), 5L)

  # locate_country() shares the check.
  skip_if_no_sf_geometry()
  expect_error(locate_country(2.35, 48.86, add = "nope"), "`add` names")
  expect_error(locate_country(2.35, 48.86, add = 1), "`add` must be a character")

  # The shortcut table and the validator cannot drift: check_add() validates
  # against exactly the map wdj_derive_from_iso3c() uses.
  expect_true(all(names(countryatlas:::WDJ_DEST_MAP) %in%
                    c("iso2c", "continent", "region", "region23", "un_region",
                      "country", "flag", "currency", "tld")))
})

test_that("region reports a no-match instead of drawing an empty map", {
  # `region` accepts a continent, a group, iso3c codes, country names or a
  # bounding box -- and anything that matched none of those fell through to
  # name-matching, resolved to NA, and produced a silent empty subset. A typo
  # like "Europ" gave a blank map with no explanation, and NA reached the
  # nchar()/%in% tests as base R's "missing value where TRUE/FALSE needed".
  skip_if_not_installed("maps")
  wg <- function(r) world_geometry("countries", geometry = "polygon", region = r)

  expect_error(wg("Nowhere"), "matched no countries")
  expect_error(wg("Europ"), "matched no countries")
  expect_error(wg(1), "matched no countries")
  expect_error(wg(NA), "must not contain missing values")
  expect_error(wg(c("France", NA)), "must not contain missing values")

  # All five documented forms still work.
  expect_gt(nrow(wg("Europe")), 0L)              # continent
  expect_gt(nrow(wg("EU")), 0L)                  # group
  expect_gt(nrow(wg(c("FRA", "DEU"))), 0L)       # iso3c
  expect_gt(nrow(wg(c("France", "Germany"))), 0L) # names
  # A bounding box warns that it clips vertices, which is its own test.
  expect_gt(nrow(suppressWarnings(wg(c(-10, 30, 40, 48)))), 0L) # bounding box
  expect_gt(nrow(world_geometry("countries", geometry = "polygon")), 0L) # NULL
  # Codes and names for the same countries agree.
  expect_equal(nrow(wg(c("FRA", "DEU"))), nrow(wg(c("France", "Germany"))))
})

test_that("world_data validates classify and language before fetching", {
  # `classify` was filtered with intersect(), which silently dropped anything
  # unrecognised -- so classify = "incomes" added no classification columns and
  # said nothing -- and `language` went straight to WDI, where a length-2 value
  # surfaced as "the condition has length > 1". Both are checked before the
  # network call, which is also why this test needs no connection.
  expect_error(world_data(2020, classify = "incomes"), "must be one of")
  expect_error(world_data(2020, classify = c("income", "nope")), "must be one of")
  expect_error(world_data(2020, classify = 1), "must be a character")
  expect_error(world_data(2020, classify = NA), "must be a character")
  expect_error(world_data(2020, language = 1), "must be a single string")
  expect_error(world_data(2020, language = c("en", "fr")), "single string")

  # country_data takes the same two arguments and shares the checks.
  expect_error(country_data(2020, classify = "incomes"), "must be one of")
  expect_error(country_data(2020, language = c("en", "fr")), "single string")

  # Asking for no classification at all stays valid -- that is what
  # character(0) means -- and so does any subset.
  expect_error(world_data(2020, classify = character(0)), NA)
  expect_error(world_data(2020, classify = c("income", "region")), NA)
})

test_that("clear_wdi_cache(disk = FALSE) does not touch the disk", {
  # memoise's cache_filesystem()$reset() is literally
  # file.remove(list.files(dir, full.names = TRUE)), so forget() on a
  # disk-backed memo was never an in-memory operation: the call the examples
  # label "forget the in-session memo" deleted the persistent cache and every
  # unrelated file sharing that directory. Dropping the memo reference is what
  # "in-session" means; the next call rebuilds it and reads the disk back.
  d <- file.path(tempdir(), paste0("cc-", as.integer(runif(1, 1, 1e6))))
  dir.create(d, showWarnings = FALSE)
  withr::defer(unlink(d, recursive = TRUE))
  withr::local_options(countryatlas.cache_dir = d)

  hits <- 0L
  orig <- countryatlas:::fetch_one_indicator
  stub <- function(code, name, start, end, language = "en") {
    hits <<- hits + 1L
    x <- tibble::tibble(iso2c = "US", iso3c = "USA", country = "US",
                        year = 2000L)
    x[[name]] <- 1
    x
  }
  assignInNamespace("fetch_one_indicator", stub, "countryatlas")
  withr::defer(assignInNamespace("fetch_one_indicator", orig, "countryatlas"))

  invisible(countryatlas:::fetch_wdi(c(x = "I1"), 2000, 2000, parallel = FALSE))
  skip_if(hits == 0L, "disk cache unavailable in this environment")
  bystander <- file.path(d, "unrelated-user-file.txt")
  writeLines("keepme", bystander)
  n_before <- length(list.files(d))

  clear_wdi_cache(disk = FALSE)
  expect_true(file.exists(bystander))          # the caller's own file
  expect_equal(length(list.files(d)), n_before)
  # And the entries really are still usable: no second provider call.
  invisible(countryatlas:::fetch_wdi(c(x = "I1"), 2000, 2000, parallel = FALSE))
  expect_equal(hits, 1L)

  # disk = TRUE still removes it, which is what that argument is for.
  clear_wdi_cache(disk = TRUE)
  expect_false(dir.exists(d))
})

test_that("`years` means the same thing for every source", {
  # It is documented as "a numeric year vector", and adapter_reshape() honours
  # that for the four adapters (year %in% years). The WDI path used min/max as
  # a fetch range and never filtered, so years = c(2000, 2020) asked for two
  # years and got twenty-one -- the same argument meaning different things
  # depending on which source you named.
  withr::local_options(
    countryatlas.cache_dir = file.path(tempdir(), "cc-years"))
  orig <- countryatlas:::fetch_one_indicator
  stub <- function(code, name, start, end, language = "en") {
    yrs <- seq(start, end)
    x <- tibble::tibble(iso2c = "US", iso3c = "USA", country = "US",
                        year = as.integer(yrs))
    x[[name]] <- seq_along(yrs)
    x
  }
  assignInNamespace("fetch_one_indicator", stub, "countryatlas")
  withr::defer(assignInNamespace("fetch_one_indicator", orig, "countryatlas"))

  two <- fetch_indicator("wdi", c(x = "I1"), years = c(2000, 2020))
  expect_equal(nrow(two), 2L)
  expect_setequal(two$year, c(2000L, 2020L))
  # A contiguous request still gets the whole span.
  expect_equal(nrow(fetch_indicator("wdi", c(x = "I1"), years = 2000:2020)), 21L)
  expect_equal(nrow(fetch_indicator("wdi", c(x = "I1"), years = 2005)), 1L)
})

test_that("hatching and dispute marks do not discard the projection", {
  # ggpattern::geom_sf_pattern() and the geom_sf() inside dispute_layer() each
  # return list(<layer>, <CoordSf>) -- a default coord_sf(crs = NULL) -- and
  # ggplot2's ggplot_add.Coord replaces the plot's coord unconditionally. Added
  # after wdj_coord_sf(), they threw the requested projection away along with
  # its latitude clip, so `mercator + hatched` and `robinson + hatched` drew
  # byte-identical maps. Both na_style = "hatched" and disputes = "mark" are
  # honesty features; silently reprojecting the map is the opposite.
  skip_if_no_sf_geometry()
  sfd <- suppressWarnings(
    attach_geometry(world_snapshot$countries, geometry = "sf"))
  yrange <- function(...) {
    p <- suppressMessages(world_map(sfd, gdp_per_capita, ...))
    range(ggplot2::ggplot_build(p)$layout$panel_params[[1]]$y_range)
  }
  merc <- yrange(projection = "mercator")
  robin <- yrange(projection = "robinson")
  expect_false(isTRUE(all.equal(merc, robin)))     # the two really differ

  # Adding either layer must not change the extent.
  expect_equal(yrange(projection = "mercator", na_style = "hatched"), merc)
  expect_equal(yrange(projection = "robinson", na_style = "hatched"), robin)
  expect_equal(yrange(projection = "mercator", disputes = "mark"), merc)
  # And Mercator's latitude clip survives: it reaches far past Equal Earth's.
  expect_gt(max(merc), max(yrange(projection = "equal_earth",
                                  na_style = "hatched")))
})

test_that("bubble_map and spike_map count only the countries they can place", {
  # The bundled centroid table does not cover every code in the codelist, so a
  # point-per-country verb silently loses Hong Kong, Macao, Gibraltar, the
  # British Virgin Islands and Tuvalu. bubble_map left-joined and drew a point
  # at (NA, NA) -- ggplot2 muttered "Removed 5 rows" -- while spike_map
  # inner-joined and said nothing. Both then computed provenance on the frame as
  # it arrived, so a population map missing Hong Kong reported "215 of 215".
  snap <- world_snapshot$countries
  cent <- world_geometry("centroids", geometry = "polygon")
  n_lost <- sum(!snap$iso3c %in% cent$iso3c & !is.na(snap$population))
  expect_gt(n_lost, 0)                       # the premise holds on this snapshot

  # geom_point puts every bubble in one group, so count rows there and groups
  # for the spike triangles (3 vertices per country).
  verbs <- list(
    bubble_map = list(f = bubble_map, count = function(d) nrow(d)),
    spike_map  = list(f = spike_map,  count = function(d) length(unique(d$group)))
  )
  for (nm in names(verbs)) {
    expect_warning(p <- verbs[[nm]]$f(snap, population),
                   class = "countryatlas_no_centroid")
    cov <- attr(p, "countryatlas_provenance")$coverage
    expect_equal(cov$n_missing, n_lost)
    expect_equal(cov$n_shown, cov$n_total - n_lost)
    expect_true("HKG" %in% cov$missing_iso3c)
    # n_shown must equal what is on the page, not what came in.
    b <- ggplot2::ggplot_build(p)
    expect_equal(verbs[[nm]]$count(b$data[[2]]), cov$n_shown)
  }
  # And ggplot2 no longer has NA coordinates to complain about.
  expect_silent(suppressWarnings({
    p <- bubble_map(snap, population)
    invisible(ggplot2::ggplot_build(p))
  }))
})

test_that("n_bins means the same thing in every binned style", {
  # style = "binned" passed n_bins to ggplot2 as `n.breaks`, which is only a
  # hint: scales::extended_breaks() snaps to round numbers, so n_bins of 5, 6
  # and 7 all drew five bins and 3 drew four. `n_bins` is documented as "number
  # of bins for binned/quantile/jenks styles", so it has to mean that.
  mapdf <- suppressWarnings(
    attach_geometry(world_snapshot$countries, geometry = "polygon"))
  # Every verb that takes `style` and `n_bins` must agree on what n_bins means,
  # not just world_map(): globe_map() and value_by_alpha_map() call the same
  # scale builder and had the same bug.
  scale_bins <- function(p) {
    length(ggplot2::ggplot_build(p)$plot$scales$get_scales("fill")$get_breaks()) + 1L
  }
  # globe_map(backend = "polygon") needs mapproj; the other two do not, so
  # gate only that one rather than skipping the whole property.
  has_mapproj <- requireNamespace("mapproj", quietly = TRUE)
  for (nb in c(3, 7)) {
    expect_equal(scale_bins(world_map(mapdf, gdp_per_capita, style = "binned",
                                      n_bins = nb)), nb)
    if (has_mapproj) {
      expect_equal(scale_bins(globe_map(mapdf, gdp_per_capita,
                                        backend = "polygon", style = "binned",
                                        n_bins = nb)), nb)
    }
    expect_equal(scale_bins(value_by_alpha_map(mapdf, gdp_per_capita, population,
                                               style = "binned", n_bins = nb)), nb)
    # ... and each records the boundaries it used, so map_provenance() can say.
    provs <- c(
      if (has_mapproj) list(globe_map(mapdf, gdp_per_capita,
                                      backend = "polygon", style = "binned",
                                      n_bins = nb)),
      list(value_by_alpha_map(mapdf, gdp_per_capita, population,
                              style = "binned", n_bins = nb)))
    for (p in provs) {
      expect_equal(length(attr(p, "countryatlas_provenance")$breaks) - 1L, nb)
    }
  }
  for (nb in c(3, 5, 7, 9)) {
    for (st in c("binned", "quantile")) {
      p <- world_map(mapdf, gdp_per_capita, style = st, n_bins = nb,
                     classification_report = TRUE)
      br <- attr(p, "countryatlas_provenance")$breaks
      expect_equal(length(br) - 1L, nb, info = paste(st, nb))
      rep <- attr(p, "countryatlas_classification")
      expect_equal(nrow(rep), nb, info = paste(st, nb))
      expect_equal(sum(rep$n), sum(!is.na(
        dplyr::distinct(mapdf, iso3c, .keep_all = TRUE)$gdp_per_capita)))
    }
  }
})

test_that("a continuous colourbar reports no classes rather than inventing them", {
  # The fallback was as.factor(vals) -- one "class" per distinct value -- so a
  # continuous fill produced a 189-row report of n = 1 that looked like a
  # classification and was not one.
  mapdf <- suppressWarnings(
    attach_geometry(world_snapshot$countries, geometry = "polygon"))
  expect_warning(
    p <- world_map(mapdf, gdp_per_capita, style = "continuous",
                   classification_report = TRUE),
    class = "countryatlas_no_classes")
  expect_null(attr(p, "countryatlas_classification"))
  # A categorical fill still gets a genuine per-level table.
  p2 <- world_map(mapdf, continent, style = "categorical",
                  classification_report = TRUE)
  expect_true(nrow(attr(p2, "countryatlas_classification")) < 10)
})

test_that("point verbs tolerate data that already carries centroid columns", {
  # world_geometry("centroids") output, or anything joined to it, collided with
  # the internal join: dplyr suffixed both sides to .x/.y and the aes() looking
  # for `.data$centroid_lon` found no such column.
  d <- world_snapshot$countries
  d$centroid_lon <- 0
  d$centroid_lat <- 0
  for (f in list(bubble_map, spike_map)) {
    p <- suppressWarnings(f(d, population))
    expect_s3_class(ggplot2::ggplot_build(p), "ggplot_built")
    # The bundled centroids win -- nothing is drawn at the planted (0, 0).
    xy <- ggplot2::ggplot_build(p)$data[[2]]
    expect_false(all(xy$x == 0))
  }
})

test_that("flow_map arcs cross the antimeridian instead of the whole map", {
  # A great circle Tokyo -> Los Angeles runs ...178, 179, -179, -178..., and
  # geom_path() under coord_quickmap() joined those two points literally: every
  # trans-Pacific flow was drawn as a horizontal streak back across Africa.
  d <- data.frame(from = c("Japan", "Fiji"), to = c("United States", "Peru"),
                  vol = c(10, 5))
  p <- flow_map(d, from, to, weight = vol)
  arc <- ggplot2::ggplot_build(p)$data[[2]]
  jumps <- unlist(lapply(split(arc$x, arc$group), function(x) abs(diff(x))))
  expect_lt(max(jumps), 180)
  # Each Pacific flow is drawn as two pieces meeting exactly on the edge.
  expect_equal(length(unique(arc$group)), 4L)
  edges <- sort(unique(round(range(arc$x), 6)))
  expect_equal(edges, c(-180, 180))
  # And a flow that does not cross the dateline stays in one piece.
  p2 <- flow_map(data.frame(from = "France", to = "Germany"), from, to)
  expect_equal(length(unique(ggplot2::ggplot_build(p2)$data[[2]]$group)), 1L)
})

test_that("flow_map legends carry the caller's weight column name", {
  # The internal arc frame's column is literally called `weight`, so ggplot2
  # titled both legends "weight" whatever the user had mapped.
  d <- data.frame(from = "France", to = "Germany", trade_volume = 7)
  p <- flow_map(d, from, to, weight = trade_volume)
  nms <- vapply(p$scales$scales, function(s) s$name %||% NA_character_, "")
  expect_true("trade_volume" %in% nms)
  expect_false("weight" %in% nms)
  # Same name on both scales, so the two guides merge into one legend.
  expect_equal(sum(nms == "trade_volume", na.rm = TRUE), 2L)
})

test_that("geom_country_labels accepts a mapping and still honours flag", {
  # to_centroids() reduced the frame to iso3c/long/lat/flag, so a mapping
  # naming any other column died on "object 'continent' not found" -- the
  # ordinary reason to pass a mapping. And modifyList(base, mapping) dropped
  # the default `label`, taking flag = TRUE with it.
  mapdf <- suppressWarnings(
    attach_geometry(world_snapshot$countries, geometry = "polygon"))
  labels_of <- function(...) {
    b <- ggplot2::ggplot_build(world_map(mapdf, gdp_per_capita) +
                                 geom_country_labels(..., repel = FALSE))
    b$data[[length(b$data)]]
  }
  lyr <- labels_of(ggplot2::aes(colour = continent))
  expect_gt(sum(!is.na(lyr$label)), 100)      # labels survive a custom mapping
  expect_gt(length(unique(lyr$colour)), 1)    # and the mapping took effect
  # flag = TRUE works with and without a mapping. A flag emoji is a pair of
  # regional-indicator code points (U+1F1E6..U+1F1FF).
  #
  # Compared as code points, not with a regex: `\p{Regional_Identifier}` is not
  # a property this PCRE build has, and the obvious fallback -- the range
  # "[\U0001F1E6-\U0001F1FF]" -- is not portable either. R's default engine
  # (TRE) cannot form a character range over non-BMP code points, so on Windows
  # that pattern is an error, not a non-match: "invalid regular expression,
  # reason 'Invalid character range'". utf8ToInt() involves no regex engine and
  # gives the same answer on every platform.
  is_flag <- function(x) {
    cps <- unlist(lapply(enc2utf8(as.character(x)), utf8ToInt),
                  use.names = FALSE)
    any(!is.na(cps) & cps >= 0x1F1E6L & cps <= 0x1F1FFL)
  }
  plain <- stats::na.omit(labels_of()$label)
  for (lab in list(labels_of(flag = TRUE),
                   labels_of(ggplot2::aes(colour = continent), flag = TRUE))) {
    txt <- stats::na.omit(lab$label)
    expect_true(is_flag(txt))
    expect_false(any(txt %in% plain))          # flags, not the ISO codes
  }
})

test_that("animate_world keeps a title the caller asked for", {
  skip_if_not_installed("gganimate")
  mapdf <- suppressWarnings(
    attach_geometry(world_snapshot$countries, geometry = "polygon"))
  pan <- do.call(rbind, lapply(2018:2020, function(y) {
    z <- mapdf; z$year <- y; z
  }))
  a <- animate_world(pan, gdp_per_capita, year, title = "MY TITLE")
  expect_equal(format(a$labels$title), "MY TITLE")
  expect_equal(format(a$labels$subtitle), "{current_frame}")
  # With no title the frame marker still goes where it always did.
  b <- animate_world(pan, gdp_per_capita, year)
  expect_equal(format(b$labels$title), "{current_frame}")
})

test_that("every world_map style draws on the tmap engine", {
  # tm_scale_intervals() is the *interval* scale and "cont"/"cat" are not
  # interval styles -- they name different constructors. So the default style
  # could not draw at all ('Invalid style...') and a categorical fill warned
  # that an interval scale was being applied to non-numeric data.
  skip_if_not_installed("tmap")
  skip_if_no_sf_geometry()
  d <- attach_geometry(world_snapshot$countries, geometry = "sf")
  pdf(NULL)
  on.exit(grDevices::dev.off(), add = TRUE)
  for (st in c("continuous", "binned", "quantile", "jenks")) {
    expect_silent(print(world_map(d, gdp_per_capita, engine = "tmap",
                                  style = st)))
  }
  expect_silent(print(world_map(d, continent, engine = "tmap",
                                style = "categorical")))
})

test_that("a failed download is not written to the on-disk cache", {
  # memoise caches whatever the function returns, and the World Bank cache is on
  # disk. WDI() answers a failed download by warning and returning a zero-row
  # frame, so one call made while the network was down persisted an empty
  # result and every later session read it back instead of retrying.
  skip_if_not_installed("WDI")
  dir <- withr::local_tempdir()
  withr::local_options(countryatlas.cache_dir = dir)
  local_mocked_bindings(
    WDI = function(indicator, start, end, extra = FALSE, language = "en", ...) {
      warning("Unable to download data")
      d <- data.frame(iso2c = character(0), country = character(0),
                      year = integer(0))
      d[[names(indicator)[1]]] <- numeric(0)
      d
    }, .package = "WDI")
  suppressWarnings(suppressMessages(
    try(country_data(2020, c(gdp = "NY.GDP.PCAP.KD")), silent = TRUE)))
  expect_length(list.files(dir, recursive = TRUE), 0L)
  # And the user is told why, rather than silently getting nothing.
  # The stub emits WDI's own "Unable to download data" alongside ours; muffle
  # just that one so the assertion is about the condition we raise.
  expect_warning(
    withCallingHandlers(
      suppressMessages(countryatlas:::fetch_wdi(c(gdp = "NY.GDP.PCAP.KD"),
                                                2020, 2020)),
      warning = function(w) {
        if (grepl("Unable to download", conditionMessage(w), fixed = TRUE)) {
          invokeRestart("muffleWarning")
        }
      }),
    class = "countryatlas_no_data")
})

test_that("register_country_source(cache = ) actually memoises", {
  # `cache` was stored in the registry and reported by country_sources(), but
  # nothing ever read it: the documented per-session memoisation never happened
  # and cache = FALSE was equally inert.
  calls <- 0L
  fetcher <- function(indicator, countries, years, ...) {
    calls <<- calls + 1L
    tibble::tibble(iso3c = c("USA", "FRA"), year = 2020L, value = c(1, 2))
  }
  register_country_source("cachetest", fetch = fetcher, cache = TRUE)
  on.exit(clear_country_cache("cachetest"), add = TRUE)
  fetch_indicator("cachetest", "x")
  fetch_indicator("cachetest", "x")
  expect_equal(calls, 1L)                       # second call served from memo
  fetch_indicator("cachetest", "y")
  expect_equal(calls, 2L)                       # a different key refetches
  fetch_indicator("cachetest", "x", countries = "USA")
  expect_equal(calls, 3L)                       # so does a different subset
  clear_country_cache("cachetest")
  fetch_indicator("cachetest", "x")
  expect_equal(calls, 4L)                       # and clearing forces a refetch

  n2 <- 0L
  register_country_source("cachetest2", cache = FALSE,
    fetch = function(indicator, countries, years, ...) {
      n2 <<- n2 + 1L
      tibble::tibble(iso3c = "USA", year = 2020L, value = 1)
    })
  fetch_indicator("cachetest2", "x")
  fetch_indicator("cachetest2", "x")
  expect_equal(n2, 2L)                          # cache = FALSE stays uncached
})

test_that("the antimeridian splitter handles the degenerate crossings", {
  sp <- countryatlas:::split_antimeridian
  mk <- function(lon) data.frame(lon = lon, lat = seq_along(lon))
  cases <- list(
    none      = list(mk(c(0, 10, 20)),                       1L),
    one       = list(mk(c(170, 179, -179, -170)),            2L),
    on_plus   = list(mk(c(170, 180, -180, -170)),            2L),
    on_minus  = list(mk(c(-170, -180, 180, 170)),            2L),
    two_rows  = list(mk(c(179, -179)),                       2L),
    at_end    = list(mk(c(170, 179, -179)),                  2L),
    twice     = list(mk(c(170, 179, -179, -100, 100, 179, -179)), 4L)
  )
  for (nm in names(cases)) {
    d <- cases[[nm]][[1]]
    out <- sp(d, rep(1L, nrow(d)))
    # A point sitting exactly on the edge makes the crossing interpolation 0/0.
    expect_true(all(is.finite(out$lon)), info = nm)
    expect_true(all(is.finite(out$lat)), info = nm)
    expect_equal(length(unique(out$.grp)), cases[[nm]][[2]], info = nm)
    within <- unlist(lapply(split(out$lon, out$.grp),
                            function(x) if (length(x) > 1) abs(diff(x)) else 0))
    expect_lt(max(within), 180)
  }
})

test_that("every data-bearing map verb carries readable provenance", {
  # map_provenance() is only useful if the verbs actually attach the attribute,
  # and an early return that skips it is invisible. Sweep them rather than
  # trusting each one's own test. tissot_map() is deliberately absent: it draws
  # indicatrices, not country data, so it has no coverage to report.
  snap <- world_snapshot$countries
  mapdf <- suppressWarnings(attach_geometry(snap, geometry = "polygon"))
  verbs <- list(
    world_map      = function() world_map(mapdf, gdp_per_capita),
    coverage_map   = function() coverage_map(mapdf, gdp_per_capita),
    facet_map      = function() facet_map(mapdf, gdp_per_capita, continent),
    bubble_map     = function() bubble_map(snap, population),
    spike_map      = function() spike_map(snap, population),
    tile_map       = function() tile_map(snap, gdp_per_capita),
    flow_map       = function() flow_map(data.frame(from = "France",
                                                    to = "Germany"), from, to),
    value_by_alpha = function() value_by_alpha_map(mapdf, gdp_per_capita,
                                                   population),
    classify_cmp   = function() classify_compare(mapdf, gdp_per_capita)
  )
  for (nm in names(verbs)) {
    p <- suppressWarnings(suppressMessages(verbs[[nm]]()))
    expect_false(is.null(attr(p, "countryatlas_provenance")), info = nm)
    pv <- suppressMessages(map_provenance(p))
    expect_s3_class(pv, "tbl_df")
    # Coverage must add up wherever the verb reports it at all.
    cov <- attr(p, "countryatlas_provenance")$coverage
    if (!is.null(cov) && !is.na(cov$n_total)) {
      expect_equal(cov$n_shown + cov$n_missing, cov$n_total, info = nm)
      expect_lte(cov$n_shown, cov$n_total)
      expect_length(cov$missing_iso3c, cov$n_missing)
    }
  }
  # And a plot with no provenance says so rather than returning nonsense.
  expect_error(map_provenance(ggplot2::ggplot()), "provenance")
})

test_that("world_table only claims a rank when it ranked something", {
  # With value = NULL the frame keeps whatever order it arrived in (iso3c, for
  # the bundled snapshot), so head() takes an arbitrary slice. Numbering that
  # 1..n under a column called `rank` told the reader these were the top n by
  # something: world_table(snap, top_n = 5) labelled Afghanistan "rank 1" with
  # an empty GDP cell beside it.
  snap <- world_snapshot$countries
  expect_warning(w <- world_table(snap, top_n = 5, engine = "tibble"),
                 class = "countryatlas_unranked_top_n")
  expect_false("rank" %in% names(w))
  expect_equal(nrow(w), 5L)
  # Ranking on a column gives a real rank, in the right direction.
  r <- world_table(snap, gdp_per_capita, top_n = 5, engine = "tibble")
  expect_equal(r$rank, 1:5)
  expect_false(is.unsorted(rev(r$gdp_per_capita)))
  expect_false(anyNA(r$gdp_per_capita))
  # Ascending too.
  a <- world_table(snap, gdp_per_capita, top_n = 5, desc = FALSE,
                   engine = "tibble")
  expect_false(is.unsorted(a$gdp_per_capita))
  # No truncation, no warning: nothing was misrepresented.
  expect_silent(world_table(snap, top_n = Inf, engine = "tibble"))
})

test_that("a column argument that is not a column says so, in every verb", {
  # quo_arg_name() called rlang::as_name() straight out, so anything that was
  # not a symbol or a string threw rlang's own error -- "Can't convert a double
  # vector to a string", or for `gdp + 1` the worse "Can't convert a call to a
  # string". That names neither the argument nor the function nor what was
  # wanted, and it reached the user from all ~66 unquoted column arguments in
  # the package.
  mapdf <- suppressWarnings(
    attach_geometry(world_snapshot$countries, geometry = "polygon"))
  snap <- world_snapshot$countries
  # A literal.
  expect_error(world_map(mapdf, 5), "`fill` must name a column")
  expect_error(world_map(mapdf, 5), "unquoted")
  expect_error(world_map(mapdf, TRUE), "must name a column")
  # An expression -- a natural thing to try -- gets the mutate-first hint.
  expect_error(world_map(mapdf, gdp_per_capita + 1), "gdp_per_capita \\+ 1")
  expect_error(world_map(mapdf, gdp_per_capita + 1), "mutate")
  # The .data pronoun gets told the bare name.
  expect_error(world_map(mapdf, .data$gdp_per_capita),
               "Name the column directly: fill = gdp_per_capita")
  # The argument named is the one the caller passed, not always "fill".
  expect_error(rank_countries(snap, 5), "`value` must name a column")
  expect_error(bubble_map(snap, 3), "`size` must name a column")
  expect_error(to_ppp(data.frame(iso3c = "USA", year = 2000L, v = 1), v,
                      factor = 1.5), "`factor` must name a column")
  # And the two forms that must keep working, do.
  expect_s3_class(suppressMessages(world_map(mapdf, gdp_per_capita)), "ggplot")
  expect_equal(nrow(interpolate_missing(
    data.frame(iso3c = "USA", year = 2000:2002, v = c(1, NA, 3)), "v")), 3L)
})

test_that("the microstate border gap is named rather than silently counted", {
  # country_borders() computes adjacency from Natural Earth, and the default
  # 110m basemap has no polygon at all for the European microstates. They
  # contribute no rows, so the five of them report zero land neighbours and
  # their neighbours report short: France came back with 8 instead of 10, under
  # a heading that stated the count as fact.
  expect_true(all(countryatlas:::WDJ_MICROSTATES %in% country_meta$iso3c))
  # cli_fmt(), not capture.output(type = "message"): testthat's reporter has
  # already redirected that stream, so the nested capture comes back empty.
  txt <- function(x) paste(cli::ansi_strip(cli::cli_fmt(print(x))),
                           collapse = " ")
  fr <- txt(country_factsheet("France"))
  expect_match(fr, "Excludes Andorra, Monaco")
  expect_match(fr, "scale = \"medium\"", fixed = TRUE)
  it <- txt(country_factsheet("Italy"))
  expect_match(it, "San Marino")
  # A microstate says its zero is an artefact, not a fact.
  mc <- txt(country_factsheet("Monaco"))
  expect_match(mc, "Not 0")
  # An unaffected country stays silent.
  expect_no_match(txt(country_factsheet("Germany")), "110m basemap")
})

test_that("the pinned microstate lists match what the finer basemap shows", {
  # WDJ_MICROSTATES and WDJ_MICROSTATE_NEIGHBOURS are hard-coded, so pin them
  # against scale = "medium", which does carry the five. A Natural Earth update
  # that changes either must fail here rather than leave the factsheet note
  # quietly wrong.
  skip_if_no_sf_geometry()
  skip_on_cran()
  med <- country_borders(scale = "medium")
  small <- country_borders(scale = "small")
  micro <- countryatlas:::WDJ_MICROSTATES
  # Present at 50m, absent at 110m -- the premise of the whole note.
  expect_true(all(micro %in% c(med$iso3c_a, med$iso3c_b)))
  expect_false(any(micro %in% c(small$iso3c_a, small$iso3c_b)))
  # And the neighbour map is exactly who borders them at 50m.
  pairs <- rbind(
    data.frame(a = med$iso3c_a, b = med$iso3c_b),
    data.frame(a = med$iso3c_b, b = med$iso3c_a))
  observed <- lapply(split(pairs$b, pairs$a), function(x) sort(intersect(x, micro)))
  observed <- observed[vapply(observed, length, 0L) > 0 &
                         !names(observed) %in% micro]
  expected <- lapply(countryatlas:::WDJ_MICROSTATE_NEIGHBOURS, sort)
  expect_equal(observed[order(names(observed))], expected[order(names(expected))])
})

test_that("a factsheet for a code with no metadata row is still named", {
  # `name = first_or_na(row$country) %||% iso` -- but %||% only replaces NULL,
  # and first_or_na() returns NA_character_ when the code has no row in
  # country_meta. The fallback was written and never fired, so Kosovo (XKX,
  # which countrycode carries no metadata for) printed a header of literally
  # "NA (XKX)" while listing four real land neighbours underneath.
  expect_false("XKX" %in% country_meta$iso3c)     # the premise
  k <- country_factsheet("Kosovo")
  expect_equal(k$iso3c, "XKX")
  expect_equal(k$name, "Kosovo")                  # the caller's own name
  expect_false(is.na(k$name))
  hdr <- paste(cli::ansi_strip(cli::cli_fmt(print(k))), collapse = " ")
  expect_match(hdr, "Kosovo (XKX)", fixed = TRUE)
  expect_no_match(hdr, "NA (XKX)", fixed = TRUE)
  # Falls back to the code when that is all the caller gave.
  expect_equal(country_factsheet("XKX", origin = "iso3c")$name, "XKX")
  # A country with metadata is unaffected.
  expect_equal(country_factsheet("France")$name, "France")
})

test_that("country_meta encodes 'unknown' one way", {
  # WDI_data uses "" for an unknown capital and it passed straight through, so
  # five countries had a blank capital alongside 34 NAs -- is.na(capital) was
  # wrong for those five and the factsheet printed "capital: " with nothing
  # after it.
  cm <- countryatlas::country_meta
  for (col in names(cm)[vapply(cm, is.character, logical(1))]) {
    blanks <- sum(!is.na(cm[[col]]) & trimws(cm[[col]]) == "")
    expect_equal(blanks, 0L, info = col)
  }
  expect_true(is.na(cm$capital[cm$iso3c == "HKG"]))
  expect_equal(nrow(cm), 249L)                    # nothing lost in the rewrite
})

test_that("subnational frames are counted by region, not collapsed to countries", {
  # na_coverage(), classification_table(), apply_binned_fill() and
  # imputed_count() all de-duplicate before counting, because the polygon
  # backend repeats a country's value down every vertex. They keyed on iso3c --
  # but a subnational frame carries iso3c *and* a region code, so every NUTS
  # region of a country collapsed to one row.
  mk <- function(v) data.frame(
    nuts_id = c(paste0("FR", 1:5), paste0("DE", 1:4), paste0("IT", 1:3)),
    iso3c = c(rep("FRA", 5), rep("DEU", 4), rep("ITA", 3)), v = v)

  # 12 regions across 3 countries: the denominator is 12.
  d1 <- mk(c(NA, 2:5, 6:9, 10:12))
  cv1 <- countryatlas:::na_coverage(d1, "v")
  expect_equal(cv1$n_total, 12L)
  expect_equal(cv1$n_missing, 1L)
  expect_equal(cv1$n_shown + cv1$n_missing, cv1$n_total)

  # distinct() keeps the first row per key, so when a country's *first* region
  # had data the later blank ones vanished: four grey regions on the map were
  # reported as zero missing -- complete coverage claimed for a map with holes.
  d2 <- mk(c(1, NA, NA, NA, NA, 6:9, 10:12))
  cv2 <- countryatlas:::na_coverage(d2, "v")
  expect_equal(cv2$n_missing, 4L)
  expect_equal(cv2$n_total, 12L)

  # The colour scale was derived the same way: quantiles over 3 values, not 12.
  br <- attr(countryatlas:::apply_binned_fill(mk(1:12), rlang::quo(v), "v",
                                              "quantile", 4), "breaks")
  expect_equal(length(br) - 1L, 4L)
  expect_equal(range(br), c(1, 12))
  # An iso_3166_2 frame (standardize_subnational's output) keys the same way.
  d3 <- data.frame(iso_3166_2 = c("DE-BY", "DE-BW", "FR-IDF"),
                   iso3c = c("DEU", "DEU", "FRA"), v = c(1, NA, 3))
  expect_equal(countryatlas:::na_coverage(d3, "v")$n_total, 3L)
  expect_equal(countryatlas:::na_coverage(d3, "v")$n_missing, 1L)
  # Country-level frames are untouched.
  cvc <- countryatlas:::na_coverage(world_snapshot$countries, "gdp_per_capita")
  expect_equal(cvc$n_total, dplyr::n_distinct(world_snapshot$countries$iso3c))
})

test_that("country_join says when standardising collapsed two names into one", {
  # wdj_to_key() maps distinct inputs onto one code -- "France" and "FRANCE ",
  # or "Congo" and "Congo-Kinshasa" -- and the join then multiplies the other
  # side's rows. dplyr does not warn: with unique keys on one side that is an
  # ordinary one-to-many, not the many-to-many it flags. So two rows became
  # three, France appeared twice with different values, and any downstream sum
  # double-counted it, with nothing on screen to say so.
  x <- data.frame(country = c("France", "Germany"), gdp = c(1, 2))
  y <- data.frame(nation = c("France", "FRANCE ", "Germany"), pop = c(10, 11, 20))
  expect_warning(r <- country_join(x, y, country, nation),
                 class = "countryatlas_key_collapse")
  expect_match(
    conditionMessage(tryCatch(country_join(x, y, country, nation),
                              warning = function(w) w)),
    "FRA", fixed = TRUE)
  expect_equal(nrow(r), 3L)                    # the behaviour is unchanged
  expect_silent(country_join(x, y, country, nation, warn = FALSE))

  # A country-by-year panel is a legitimate one-to-many: the same input name
  # maps to the same code, nothing was collapsed, so nothing is said.
  pan <- data.frame(nation = rep(c("France", "Germany"), each = 3),
                    year = rep(2018:2020, 2), pop = 1:6)
  expect_silent(country_join(x, pan, country, nation))
  # Neither is a side whose duplicates were already in the input under one name.
  dup <- data.frame(nation = c("France", "France"), pop = c(1, 2))
  expect_silent(country_join(x, dup, country, nation))

  # country_join_all() carries the same guard, per table.
  expect_warning(
    country_join_all(list(x, y), by = c("country", "nation")),
    class = "countryatlas_key_collapse")
})

test_that("standardize_country says when it clobbers columns you did not ask for", {
  # `add` defaults to c("iso3c", "iso2c", "continent", "region"), so the call
  # everyone makes -- standardize_country(d, country), to get iso3c -- also
  # replaced any continent/region/iso2c the caller already had, silently. Eleven
  # other column-adding verbs report exactly this via warn_overwrite(); the
  # package's headline function did not. A user's own regional classification is
  # not the package's to discard without a word.
  d <- data.frame(country = c("France", "Brazil"),
                  continent = c("MY-EU", "MY-SA"), region = c("R1", "R2"),
                  v = 1:2)
  expect_warning(standardize_country(d, country),
                 class = "countryatlas_unasked_overwrite")
  expect_warning(standardize_country(d, country), "continent")
  expect_warning(standardize_country(d, country), "region")

  # Naming `add` yourself means you asked for it: no warning, per the
  # documented contract that `add` names the columns literally.
  expect_silent(standardize_country(d, country, add = c("iso3c", "continent")))
  # And asking only for the code leaves your columns alone.
  expect_silent(r <- standardize_country(d, country, add = "iso3c"))
  expect_identical(r$continent, d$continent)
  expect_identical(r$region, d$region)
  expect_equal(r$iso3c, c("FRA", "BRA"))
  # warn = FALSE silences it; a frame with nothing to clobber is quiet anyway.
  expect_silent(standardize_country(d, country, warn = FALSE))
  expect_silent(standardize_country(data.frame(country = "France"), country))
  # iso3c is never counted: replacing it is the point of the function.
  d2 <- data.frame(country = "France", iso3c = "XXX")
  expect_silent(s2 <- standardize_country(d2, country, add = "iso3c"))
  expect_equal(s2$iso3c, "FRA")
})

test_that("the one-row-per-country rule really takes the earliest year", {
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

test_that("the spatial statistics take a deterministic cross-section of a panel", {
  # align_weights() -- shared by morans_i, gearys_c, getis_ord, local_morans,
  # spatial_lag and lisa_map -- reduced to one row per country with a bare
  # distinct(iso3c, .keep_all = TRUE). Handed a panel it kept whichever row
  # came first in the frame, so Moran's I on the same data came back 0.47 or
  # 0.29 depending only on row order, and unlike the map verbs it said nothing.
  skip_if_not_installed("sf")
  set.seed(11)
  snap <- world_snapshot$countries
  pan <- do.call(rbind, lapply(2000:2002, function(y) {
    z <- snap; z$year <- y
    z$gdp_per_capita <- z$gdp_per_capita * (1 + 3 * (y - 2000))
    z
  }))
  shuf <- pan[sample(nrow(pan)), ]
  w <- country_weights("knn", k = 5)
  mi <- function(d) suppressWarnings(
    morans_i(d, gdp_per_capita, weights = w, n_perm = 0))

  expect_equal(mi(pan)$i, mi(shuf)$i)                    # order cannot matter
  expect_equal(mi(shuf)$i, mi(pan[pan$year == 2000, ])$i) # and it is the earliest
  # The choice is announced, as it is everywhere else in the package.
  expect_warning(morans_i(pan, gdp_per_capita, weights = w, n_perm = 0),
                 class = "countryatlas_panel")
  # A genuine cross-section is untouched and silent.
  expect_silent(morans_i(snap, gdp_per_capita, weights = w, n_perm = 0))
  # The sibling verbs inherit both properties from the same helper.
  expect_warning(gearys_c(pan, gdp_per_capita, weights = w, n_perm = 0),
                 class = "countryatlas_panel")
  expect_equal(suppressWarnings(gearys_c(pan, gdp_per_capita, weights = w,
                                         n_perm = 0)),
               suppressWarnings(gearys_c(shuf, gdp_per_capita, weights = w,
                                         n_perm = 0)))
  # spatial_lag() is the exception, and deliberately so: it computes a lag per
  # year rather than reducing to one, so it discards nothing and has nothing to
  # warn about. Its own test covers the per-year values.
  expect_no_warning(spatial_lag(pan, gdp_per_capita, weights = w),
                    class = "countryatlas_panel")
  # It returns the caller's rows with a column added, so its row order follows
  # the input by design; compare the values, not the ordering.
  lag_by <- function(d) {
    r <- suppressWarnings(spatial_lag(d, gdp_per_capita, weights = w))
    r <- r[order(r$iso3c, r$year), c("iso3c", "year", "gdp_per_capita_lag")]
    `rownames<-`(as.data.frame(r), NULL)
  }
  expect_equal(lag_by(pan), lag_by(shuf))
})

test_that("spatial_lag gives a panel a lag per year, not the first year's", {
  # spatial_lag() is the one spatial verb that returns a column aligned to the
  # caller's own rows, so a panel mismatch is invisible. It matched on iso3c
  # alone, giving every year the earliest year's neighbour average: France's
  # value ran 39,683 -> 158,734 -> 277,784 while its lag sat at 63,409 for all
  # three, so value / lag silently compared 2002 against 2000.
  skip_if_not_installed("sf")
  snap <- world_snapshot$countries
  pan <- do.call(rbind, lapply(2000:2002, function(y) {
    z <- snap; z$year <- y
    z$gdp_per_capita <- z$gdp_per_capita * (1 + 3 * (y - 2000))
    z
  }))
  w <- country_weights("knn", k = 5)
  r <- spatial_lag(pan, gdp_per_capita, weights = w)
  expect_equal(nrow(r), nrow(pan))                 # still every caller row
  fr <- r[r$iso3c == "FRA", ]
  fr <- fr[order(fr$year), ]
  expect_equal(length(unique(fr$gdp_per_capita_lag)), 3L)
  # Every value was scaled by the same per-year factor, so the ratio must be
  # constant -- it was not when the lag came from a single year.
  expect_equal(diff(range(fr$gdp_per_capita / fr$gdp_per_capita_lag)), 0)
  # Each year matches computing that year on its own.
  for (y in 2000:2002) {
    one <- spatial_lag(pan[pan$year == y, ], gdp_per_capita, weights = w)
    expect_equal(r$gdp_per_capita_lag[r$year == y], one$gdp_per_capita_lag,
                 info = y)
  }
  # A cross-section is unchanged, and silent.
  expect_silent(s <- spatial_lag(snap, gdp_per_capita, weights = w))
  expect_equal(s$gdp_per_capita_lag,
               spatial_lag(pan[pan$year == 2000, ], gdp_per_capita,
                           weights = w)$gdp_per_capita_lag)
})

test_that("the coverage caption reads as English at every size", {
  # These land on published maps, and were built with bare sprintf(): a
  # single-country frame produced "All 1 countries shown." and an empty one
  # "All 0 countries shown." The same noun appears in coverage_map()'s caption
  # and in map_provenance()'s print block.
  rf <- countryatlas:::resolve_footnote
  cv <- function(t, s, m) list(n_total = t, n_shown = s, n_missing = m)
  expect_equal(rf("auto", cv(240, 187, 53)),
               "187 of 240 countries shown; 53 missing.")
  expect_equal(rf("auto", cv(240, 240, 0)), "All 240 countries shown.")
  expect_equal(rf("auto", cv(1, 1, 0)), "All 1 country shown.")
  expect_equal(rf("auto", cv(1, 0, 1)), "0 of 1 country shown; 1 missing.")
  expect_equal(rf("auto", cv(2, 1, 1)), "1 of 2 countries shown; 1 missing.")
  # An empty frame gets a sentence, not "All 0 countries shown."
  expect_equal(rf("auto", cv(0, 0, 0)), "No countries to show.")
  # No coverage to report at all means no caption, rather than "All NA".
  expect_null(rf("auto", cv(NA_integer_, NA_integer_, NA_integer_)))
  # A caller's own string is untouched, and NULL still means no caption.
  expect_equal(rf("my note", cv(5, 5, 0)), "my note")
  expect_null(rf(NULL, cv(5, 5, 0)))

  # The provenance print block agrees.
  p1 <- suppressWarnings(suppressMessages(
    tile_map(data.frame(iso3c = "FRA", gdp_per_capita = 40000), gdp_per_capita)))
  txt <- paste(cli::ansi_strip(cli::cli_fmt(
    print(suppressMessages(map_provenance(p1))))), collapse = " ")
  expect_match(txt, "1 country shown", fixed = TRUE)
  expect_no_match(txt, "1 countries", fixed = TRUE)
})

test_that("map_provenance carries the denominator, not just the numerator", {
  # `n_countries` is coverage$n_shown -- the countries actually drawn with a
  # value. The name reads like the map's country total, which is
  # n_countries + n_missing, so anyone taking it as the denominator understated
  # their own coverage. Carry n_total explicitly rather than making the reader
  # reconstruct it.
  snap <- world_snapshot$countries
  p <- suppressWarnings(suppressMessages(
    tile_map(snap[1:3, c("iso3c", "gdp_per_capita")], gdp_per_capita)))
  pv <- suppressMessages(map_provenance(p))
  expect_true("n_total" %in% names(pv))
  expect_equal(pv$n_countries + pv$n_missing, pv$n_total)
  # It agrees with the attribute the verbs actually recorded.
  cov <- attr(p, "countryatlas_provenance")$coverage
  expect_equal(pv$n_total, cov$n_total)
  expect_equal(pv$n_countries, cov$n_shown)
  # And with the caption drawn from the same numbers.
  mapdf <- suppressWarnings(attach_geometry(snap, geometry = "polygon"))
  q <- suppressMessages(world_map(mapdf, gdp_per_capita, footnote = "auto"))
  qv <- suppressMessages(map_provenance(q))
  expect_match(q$labels$caption,
               sprintf("%d of %d countries shown", qv$n_countries, qv$n_total),
               fixed = TRUE)
})

test_that("a constant column makes the spatial statistics say so, not return NaN", {
  # Moran's I, Geary's C, Getis-Ord and the local variants all divide by the
  # cross-sectional variance, so a column with no variation is 0/0. They
  # returned NaN -- and getis_ord's z-score Inf -- with nothing said, which for
  # a statistic is worse than an error: it reads like a computed result.
  skip_if_not_installed("sf")
  snap <- world_snapshot$countries
  w <- country_weights("knn", k = 5)
  flat <- snap[1:50, c("iso3c", "gdp_per_capita")]
  flat$gdp_per_capita <- 100

  expect_warning(m <- morans_i(flat, gdp_per_capita, weights = w, n_perm = 0),
                 class = "countryatlas_zero_variance")
  expect_true(is.na(m$i))
  expect_warning(g <- gearys_c(flat, gdp_per_capita, weights = w, n_perm = 0),
                 class = "countryatlas_zero_variance")
  expect_true(is.na(g$c))
  expect_warning(l <- local_morans(flat, gdp_per_capita, weights = w,
                                   n_perm = 0),
                 class = "countryatlas_zero_variance")
  expect_true(all(is.na(l$ii)))
  expect_warning(go <- getis_ord(flat, gdp_per_capita, weights = w),
                 class = "countryatlas_zero_variance")
  expect_true(all(is.na(go$z_score)))
  # No NaN or Inf survives into any of them.
  for (r in list(m, g, l, go)) {
    num <- unlist(r[, vapply(r, is.numeric, logical(1)), drop = FALSE])
    expect_false(any(is.nan(num)))
    expect_false(any(is.infinite(num)))
  }
  # An all-zero column is the same degenerate case, and gi_star cannot divide
  # by its own zero sum either.
  zero <- flat; zero$gdp_per_capita <- 0
  expect_warning(gz <- getis_ord(zero, gdp_per_capita, weights = w),
                 class = "countryatlas_zero_variance")
  expect_true(all(is.na(gz$gi_star)))

  # Real data is untouched and silent.
  expect_silent(mi <- morans_i(snap, gdp_per_capita, weights = w, n_perm = 0))
  expect_true(is.finite(mi$i))
  expect_silent(gg <- getis_ord(snap, gdp_per_capita, weights = w))
  expect_true(all(is.finite(gg$z_score)))
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

test_that("as_ggsql_source is explicit about who owns the connection", {
  # format = "duckdb" hands back a live connection and duckdb keeps its
  # in-memory database alive until the handle is released, but neither @return
  # nor @param said the caller owns it -- while the parquet branch quietly
  # closed its own. Pin all three lifecycles so they cannot drift apart.
  skip_if_not_installed("DBI")
  skip_if_not_installed("duckdb")
  d <- data.frame(iso3c = c("USA", "FRA"), v = 1:2)

  # Ours to close, and usable when we get it.
  con <- as_ggsql_source(d, format = "duckdb")
  expect_true(DBI::dbIsValid(con))
  expect_equal(nrow(DBI::dbReadTable(con, "countryatlas_world")), 2L)
  DBI::dbDisconnect(con, shutdown = TRUE)

  # Parquet closes the connection it opened and returns only the path.
  path <- as_ggsql_source(d, format = "parquet")
  expect_true(file.exists(path))
  expect_type(path, "character")

  # A connection we were handed is never ours to close, in either format.
  own <- DBI::dbConnect(duckdb::duckdb())
  on.exit(try(DBI::dbDisconnect(own, shutdown = TRUE), silent = TRUE), add = TRUE)
  back <- as_ggsql_source(d, con = own)
  expect_identical(back, own)
  expect_true(DBI::dbIsValid(own))
  invisible(as_ggsql_source(d, format = "parquet", con = own))
  expect_true(DBI::dbIsValid(own))

  # The instruction must be in the help, not only in a code comment. Read the
  # source .Rd: an installed package has no man/ directory (the help is
  # compiled), so system.file() returns "" there and readLines("") errors --
  # the same source-tree assumption the helper below exists to avoid.
  skip_if_no_source_tree()
  rd <- "../../man/as_ggsql_source.Rd"
  skip_if_not(file.exists(rd), "Rd source not present")
  expect_match(paste(readLines(rd, warn = FALSE), collapse = " "),
               "dbDisconnect", fixed = TRUE)
})

test_that("country_weights validates a custom matrix instead of failing later", {
  # weights_custom() checked the row/column names and nothing else, so three
  # kinds of bad input leaked a bare base-R error from somewhere downstream --
  # a character matrix reached rowSums() as "'x' must be numeric", an NA entry
  # was accepted here and died later as "subscript out of bounds", and an NA
  # endpoint in a long frame surfaced as "NAs are not allowed in subscripted
  # assignments". An NA weight was accepted outright and turned every statistic
  # built on it into a silent NA.
  nm <- c("USA", "FRA", "DEU")
  sq <- function(v) matrix(v, 3, 3, dimnames = list(nm, nm))

  expect_error(country_weights("custom", w = sq(as.character(0:8))),
               "must be numeric")
  na1 <- sq(0); na1[1, 2] <- NA
  expect_error(country_weights("custom", w = na1), "must not contain")
  expect_error(country_weights("custom", w = na1), "1 entry is missing")
  na2 <- na1; na2[2, 1] <- NA
  expect_error(country_weights("custom", w = na2), "2 entries are missing")
  expect_error(
    country_weights("custom",
                    w = data.frame(iso3c = c("USA", NA), neighbor = c("FRA", "DEU"))),
    "missing an endpoint")
  expect_error(
    country_weights("custom",
                    w = data.frame(iso3c = "USA", neighbor = "FRA",
                                   weight = NA_real_)),
    "1 weight is missing")

  # The forms that were always valid still are: numeric and logical matrices,
  # and a long frame.
  ok <- sq(0); ok[1, 2] <- ok[2, 1] <- 1
  expect_s3_class(country_weights("custom", w = ok), "countryatlas_weights")
  lg <- sq(FALSE); lg[1, 2] <- lg[2, 1] <- TRUE
  expect_s3_class(country_weights("custom", w = lg), "countryatlas_weights")
  expect_s3_class(
    country_weights("custom",
                    w = data.frame(iso3c = "USA", neighbor = "FRA", weight = 1)),
    "countryatlas_weights")
  # And a valid custom matrix still drives a statistic end to end. A chain of
  # four, because align_weights() needs three *connected* countries and `ok`
  # above links only two.
  nm4 <- c("USA", "FRA", "DEU", "BRA")
  chain <- matrix(0, 4, 4, dimnames = list(nm4, nm4))
  for (i in 1:3) chain[i, i + 1] <- chain[i + 1, i] <- 1
  d <- data.frame(iso3c = nm4, v = c(1, 2, 3, 4))
  mi <- morans_i(d, v, weights = country_weights("custom", w = chain),
                 n_perm = 0)
  expect_true(is.finite(mi$i))
  expect_equal(mi$n, 4L)
})

test_that("smooth_rates and to_ppp say when they had nothing to work with", {
  # rate_check() had exactly this bug fixed already -- "returned an all-NA
  # flagged column in silence" -- but its two siblings kept it. With no usable
  # denominator every rate is NA and the smoothed column with it; with no usable
  # conversion factor every converted value is NA. Correct arithmetic either
  # way, but the result looked like a computation that ran rather than one with
  # nothing to run on.
  mk <- function(den) do.call(rbind, lapply(2000:2002, function(y)
    data.frame(iso3c = paste0("C", 1:6), year = y, num = 1:6, den = den)))

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

test_that("the weights print method describes every scheme it can build", {
  # 16 uncovered lines: the print method's per-scheme description branches were
  # never exercised, so the text a user reads to check they built what they
  # meant was unverified.
  # skip_if_no_sf_geometry(), not skip_if_not_installed("sf"): the contiguity
  # scheme goes through country_borders() -> build_world_sf(), which needs the
  # Natural Earth data packages too. A sandboxed HOME hid the user library and
  # this ran with sf present and rnaturalearth absent -- exactly the case the
  # helper's own comment was written about.
  skip_if_no_sf_geometry()
  nm <- c("USA", "FRA", "DEU", "BRA")
  chain <- matrix(0, 4, 4, dimnames = list(nm, nm))
  for (i in 1:3) chain[i, i + 1] <- chain[i + 1, i] <- 1
  txt <- function(w) paste(cli::ansi_strip(cli::cli_fmt(print(w))), collapse = " ")

  expect_match(txt(country_weights("contiguity")), "shared land border")
  expect_match(txt(country_weights("knn", k = 5)), "5 nearest centroids")
  expect_match(txt(country_weights("distance", cutoff_km = 2000)),
               "within 2000 km")
  expect_match(txt(country_weights("custom", w = chain)),
               "user-supplied adjacency")
  # Style is spelled out both ways, not left as a bare letter.
  expect_match(txt(country_weights("knn", k = 3)), "row-standardised (W)",
               fixed = TRUE)
  expect_match(txt(country_weights("knn", k = 3, style = "B")), "binary (B)",
               fixed = TRUE)
  # A country with no links is named, not just counted.
  iso <- chain; iso[3, 4] <- iso[4, 3] <- 0
  out <- txt(country_weights("custom", w = iso))
  expect_match(out, "isolated: 1")
  expect_match(out, "BRA")
  # print() returns its argument invisibly, as print methods must.
  w <- country_weights("knn", k = 3)
  expect_identical(withVisible(print(w))$value, w)
  expect_false(withVisible(print(w))$visible)
})

test_that("weights that link nothing say so at construction", {
  # An edgeless graph built happily and then failed wherever it was used, as
  # "Not enough connected countries with data" -- an error about the *data*,
  # raised far from the cutoff or the matrix that actually caused it.
  # Contiguity needs the whole sf geometry stack, not just sf.
  skip_if_no_sf_geometry()
  nm <- c("USA", "FRA", "DEU")

  expect_warning(w <- country_weights("distance", cutoff_km = 1),
                 class = "countryatlas_empty_weights")
  expect_equal(w$n_links, 0L)
  # The reason names the argument that caused it, not the data.
  expect_warning(country_weights("distance", cutoff_km = 1), "within")
  expect_warning(country_weights("custom",
                                 w = matrix(0, 3, 3, dimnames = list(nm, nm))),
                 "no non-zero entries")

  # Schemes that do link countries stay silent.
  expect_silent(country_weights("knn", k = 5))
  expect_silent(country_weights("contiguity"))
  expect_silent(country_weights("distance", cutoff_km = 2000))

  # And the promise holds: a statistic on empty weights refuses to run, so the
  # warning is the only place the cause is visible.
  d <- data.frame(iso3c = nm, v = c(1, 2, 3))
  expect_error(morans_i(d, v, weights = suppressWarnings(w), n_perm = 0),
               "Not enough connected")
})

test_that("per_capita gives NA, not Inf, for an unusable population", {
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

test_that("tile_map counts only the countries the grid can place", {
  # The same overstatement bubble_map() and spike_map() had: the bundled grid
  # does not cover every code -- Hong Kong and Macao have snapshot data and no
  # tile -- so counting the input's coded countries as "shown" claimed two more
  # than the map could draw.
  snap <- world_snapshot$countries
  placeable <- sum(!is.na(snap$gdp_per_capita) &
                     snap$iso3c %in% world_tiles$iso3c)
  have <- sum(!is.na(snap$gdp_per_capita))
  expect_lt(placeable, have)                       # the premise holds

  expect_warning(p <- tile_map(snap, gdp_per_capita),
                 class = "countryatlas_no_centroid")
  cov <- attr(p, "countryatlas_provenance")$coverage
  expect_equal(cov$n_shown, placeable)
  expect_equal(cov$n_shown + cov$n_missing, cov$n_total)
  expect_true(all(c("HKG", "MAC") %in% cov$missing_iso3c))
  # The message names the grid, not a centroid.
  expect_warning(tile_map(snap, gdp_per_capita), "tile in the bundled grid")
  # The grid itself is still drawn whole.
  expect_equal(nrow(ggplot2::ggplot_build(p)$data[[1]]), nrow(world_tiles))

  # And the shared helper's default wording is still right for the point verbs.
  expect_warning(bubble_map(snap, population), "bundled centroid")
})

test_that("bivariate_map refuses a column it cannot classify", {
  # classInt needs two distinct values per axis to cut `dim` classes from. A
  # constant column reached it as classIntervals()'s bare "single unique
  # value" -- a simpleError from a third-party package naming neither the
  # column nor the function, with nothing to act on.
  skip_if_not_installed("biscale")
  skip_if_no_sf_geometry()
  sfd <- suppressWarnings(
    attach_geometry(world_snapshot$countries, geometry = "sf"))

  expect_error(bivariate_map(transform(sfd, k = 1), gdp_per_capita, k),
               class = "countryatlas_not_classifiable")
  expect_error(bivariate_map(transform(sfd, k = 1), gdp_per_capita, k),
               "1 distinct value")
  # Either axis, and the message names the offending column.
  expect_error(bivariate_map(transform(sfd, k = 1), k, gdp_per_capita),
               "k has 1 distinct value")
  # Two values against the default dim = 3 is also too few, and used to leak
  # classInt's "n greater than number of different finite values".
  two <- transform(sfd, k = rep(c(1, 2), length.out = nrow(sfd)))
  expect_error(bivariate_map(two, gdp_per_capita, k),
               class = "countryatlas_not_classifiable")
  # ... but it is enough for dim = 2, where classInt notes that each value
  # becomes its own class. That note is accurate and deliberately not muffled,
  # unlike biscale's "missing values" one.
  expect_warning(b2 <- bivariate_map(two, gdp_per_capita, k, dim = 2),
                 "same as number of different")
  expect_s3_class(b2, "ggplot")
  # More distinct values than classes proceeds silently.
  many <- transform(sfd, k = rep(seq_len(6), length.out = nrow(sfd)))
  expect_silent(bivariate_map(many, gdp_per_capita, k))
  expect_s3_class(bivariate_map(sfd, gdp_per_capita, life_expectancy), "ggplot")
})

test_that("adapter_reshape says when no entity resolved to a country", {
  # The entity column is resolved with suppressWarnings(), deliberately: every
  # OWID/Eurostat response carries aggregate rows ("World", "EU27") that never
  # resolve, so the per-name warning would fire on every call. The cost is that
  # a provider renaming its entities was swallowed with them -- the adapter
  # returned an empty frame in silence, sending the reader to check their own
  # indicator code, while the same function goes to some trouble to explain an
  # empty *input* a few lines earlier.
  ar <- countryatlas:::adapter_reshape

  # Aggregates alongside a real country: still dropped quietly, as intended.
  keep <- ar(data.frame(entity = c("France", "World", "EU27"), year = 2020L,
                        v = 1:3), "v", "entity", "year")
  expect_equal(keep$iso3c, "FRA")

  # Nothing resolving at all is never just aggregates.
  expect_error(ar(data.frame(entity = "Atlantis", year = 2020L, v = 1),
                  "v", "entity", "year"),
               class = "countryatlas_no_entities")
  expect_error(ar(data.frame(entity = "Atlantis", year = 2020L, v = 1),
                  "v", "entity", "year"), "None of the 1 entity")
  expect_error(ar(data.frame(entity = c("Nowhere", "Atlantis"), year = 2020L,
                             v = 1:2), "v", "entity", "year"),
               "None of the 2 entities")
  # The message names what it could not resolve.
  expect_error(ar(data.frame(entity = "Atlantis", year = 2020L, v = 1),
                  "v", "entity", "year"), "Atlantis")

  # An empty result from *filtering* is a different thing and must not be
  # mistaken for it: the entities resolved fine, the year simply excluded them.
  empty <- ar(data.frame(entity = "France", year = 2020L, v = 1),
              "v", "entity", "year", years = 1999L)
  expect_equal(nrow(empty), 0L)
  expect_named(empty, c("iso3c", "year", "v"))
})

test_that("the adapters read a year from whatever shape the provider sends", {
  # `...` forwards to the client, so the caller controls the time column's
  # type: eurostat's time_format = "num" gives a numeric year, "raw" a
  # character one, the default a Date. Reading each with one assumption failed
  # loudly for eurostat -- format(numeric, "%Y") is base R's opaque "invalid
  # 'trim' argument" -- and *silently wrongly* for OECD, where as.integer() on
  # a Date returned 18262, the day count, as the year, and "2020-Q1" became NA.
  ay <- countryatlas:::read_year
  expect_equal(ay(as.Date(c("2020-01-01", "1999-06-30")), "p"), c(2020L, 1999L))
  expect_equal(ay(c(2020, 1999), "p"), c(2020L, 1999L))
  expect_equal(ay(c("2020", "1999"), "p"), c(2020L, 1999L))
  expect_equal(ay(c("2020-01-01", "2020-Q1", "2020M03"), "p"), rep(2020L, 3))
  # A genuine NA stays NA without comment; there is nothing to report.
  expect_silent(expect_equal(ay(c(2020, NA), "p"), c(2020L, NA)))

  # Unusable values are dropped *and* named, both when they parse to something
  # implausible and when they do not parse at all.
  expect_warning(expect_equal(ay(c(2020, 5), "p"), c(2020L, NA)),
                 class = "countryatlas_bad_year")
  expect_warning(expect_equal(ay(c("2020", "junk"), "p"), c(2020L, NA)),
                 class = "countryatlas_bad_year")
  expect_warning(ay(c("2020", "junk"), "OECD"), "OECD: 1 time value is")
  expect_warning(ay(c("junk", "rubbish"), "OECD"), "2 time values are")

  # End to end through both adapters, on the shapes that used to break.
  skip_if_not_installed("eurostat")
  skip_if_not_installed("OECD")
  euro <- function(tp) {
    local_mocked_bindings(
      get_eurostat = function(id, ...) data.frame(
        geo = c("FR", "DE"), TIME_PERIOD = tp, values = c(1, 2)),
      .package = "eurostat")
    fetch_eurostat(c(x = "ID"))$year
  }
  expect_equal(euro(c(2020, 2020)), c(2020L, 2020L))       # was "invalid 'trim'"
  expect_equal(euro(c("2020", "2020")), c(2020L, 2020L))
  oecd <- function(tt) {
    local_mocked_bindings(
      get_dataset = function(id, ...) data.frame(
        LOCATION = c("FRA", "DEU"), Time = tt, ObsValue = c(1, 2)),
      .package = "OECD")
    fetch_oecd(c(x = "ID"))$year
  }
  expect_equal(oecd(as.Date(c("2020-01-01", "2020-01-01"))), c(2020L, 2020L))
  expect_equal(oecd(c("2020-Q1", "2020-Q2")), c(2020L, 2020L))
})

test_that("every source path reads the year the same way", {
  # The bare as.integer() bug reached six sites, not two: all four adapters,
  # adapter_reshape() itself (which fetch_owid reaches without preprocessing),
  # and fetch_indicator() -- the *public extension point*, where the year is
  # whatever a third-party fetch function chose to return.
  ar <- countryatlas:::adapter_reshape

  # adapter_reshape's own year column (the fetch_owid path).
  expect_equal(suppressWarnings(ar(
    data.frame(entity = "France", year = as.Date("2020-06-01"), v = 1),
    "v", "entity", "year"))$year, 2020L)

  # A registered source may return any of these; all must mean 2020.
  shapes <- list(date = as.Date(c("2020-01-01", "2020-01-01")),
                 quarterly = c("2020-Q1", "2020-Q2"),
                 monthly = c("202001", "202002"),
                 integer = c(2020L, 2020L))
  for (nm in names(shapes)) {
    register_country_source(
      "probe_year",
      function(indicator, countries, years, ...) {
        tibble::tibble(iso3c = c("USA", "FRA"), year = shapes[[nm]],
                       value = c(1, 2))
      }, cache = FALSE)
    got <- suppressWarnings(fetch_indicator("probe_year", "x"))
    expect_equal(got$year, c(2020L, 2020L), info = nm)
  }
  clear_country_cache("probe_year")

  # comtradr's `period` is YYYYMM for monthly data, which `...` can select.
  skip_if_not_installed("comtradr")
  ct <- function(per) {
    local_mocked_bindings(
      ct_get_data = function(...) data.frame(
        reporter_iso = c("FRA", "DEU"), period = per,
        primary_value = c(1, 2)), .package = "comtradr")
    fetch_comtrade(c(x = "0101"))$year
  }
  expect_equal(ct(c("202001", "202002")), c(2020L, 2020L))  # was 202001
  expect_equal(ct(as.Date(c("2020-01-01", "2020-01-01"))), c(2020L, 2020L))
  expect_equal(ct(c(2020L, 2020L)), c(2020L, 2020L))
})

test_that("a year is read the same way outside the source adapters too", {
  # The bare as.integer() assumption was not confined to sources.R. Two more
  # sites took a year from the caller and read it wrong.
  # audit_time_coverage(): a Date year column became day counts
  # (1990-01-01 -> 7305), and the existence audit then flagged *both* USSR rows
  # as post-dissolution -- silently wrong output from the one verb whose job is
  # catching that class of mistake.
  ussr <- function(y) data.frame(iso3c = c("SUN", "SUN"), year = y)
  for (y in list(c(1990L, 1995L), as.Date(c("1990-01-01", "1995-01-01")),
                 c("1990", "1995"))) {
    got <- suppressWarnings(audit_time_coverage(ussr(y), quiet = TRUE))
    expect_equal(nrow(got), 1L)
    expect_equal(got$year, 1995L)   # the USSR dissolved in 1991
  }

  # deflate(): a Date base_year was reported back as its day count, a number
  # the caller never supplied.
  p <- data.frame(iso3c = "USA", year = 2000:2002, v = c(1, 2, 3),
                  d = c(90, 100, 105))
  expect_equal(nrow(deflate(p, v, 2001, deflator = d)), 3L)
  expect_equal(nrow(deflate(p, v, as.Date("2001-06-01"), deflator = d)), 3L)
  expect_equal(nrow(deflate(p, v, "2001", deflator = d)), 3L)
  # Bad input now shows what was actually passed, not a day count.
  expect_error(deflate(p, v, NA, deflator = d), "single year")
  expect_error(deflate(p, v, c(2000, 2001), deflator = d), "2000, 2001")
  expect_error(deflate(p, v, 1999, deflator = d), "1999 is not in")
})

test_that("a factor value column is read as numbers, not level indices", {
  # as.numeric() on a factor returns its *level indices*, so a provider value
  # column of factor("10", "20") became 1, 2 -- silently wrong numbers.
  # check_numeric_col() rejects a factor outright with exactly this advice
  # ("as.numeric(as.character(x))") and its comment notes how easily a factor
  # column happens; the adapters take theirs from a third party, so they cannot
  # reject it, but they must not misread it either.
  ar <- countryatlas:::adapter_reshape
  vals <- function(v) suppressWarnings(ar(
    data.frame(entity = c("France", "Germany"), year = 2020L, v = v),
    "v", "entity", "year", value_col = "v"))$v

  expect_equal(vals(c(10, 20)), c(10, 20))
  expect_equal(vals(c("10", "20")), c(10, 20))
  expect_equal(vals(factor(c("10", "20"))), c(10, 20))       # was c(1, 2)
  expect_equal(vals(factor(c("1.5", "2.5"))), c(1.5, 2.5))
  # Levels in a different order than the values must not change the answer --
  # the failure mode that makes the index bug hard to spot.
  expect_equal(vals(factor(c("10", "20"), levels = c("20", "10"))), c(10, 20))
})

test_that("fetch_indicator does not trust a source's key_col claim", {
  # key_col = "iso3c" is the source's *claim*, not a guarantee, and this is the
  # public extension point. Trusting it let lowercase codes ("usa") through
  # unchanged, kept a factor a factor, and passed numeric UN M49 codes (840)
  # along as numbers -- each producing rows that silently joined to nothing and
  # read as "the provider has no data".
  probe <- function(iso) {
    register_country_source(
      "probe_key", function(indicator, countries, years, ...) {
        tibble::tibble(iso3c = iso, year = 2020L, value = seq_along(iso))
      }, cache = FALSE)
    fetch_indicator("probe_key", "x")
  }
  on.exit(clear_country_cache("probe_key"), add = TRUE)

  # Already-correct codes are untouched and silent.
  expect_silent(good <- probe(c("USA", "FRA")))
  expect_equal(good$iso3c, c("USA", "FRA"))
  # Lowercase and factor keys are standardised rather than passed through.
  expect_silent(expect_equal(probe(c("usa", "fra"))$iso3c, c("USA", "FRA")))
  expect_silent(expect_equal(probe(factor(c("USA", "FRA")))$iso3c,
                             c("USA", "FRA")))
  # Unusable keys become NA *and* are reported, in both numbers.
  expect_warning(m49 <- probe(c(840, 250)), class = "countryatlas_bad_key")
  expect_true(all(is.na(m49$iso3c)))
  expect_warning(probe(c("USA", "ZZZ")), "1 value that is not usable")
  expect_warning(probe(c("YYY", "ZZZ")), "2 values that are not usable")
})

test_that("the numeric-column verbs reject a non-numeric column up front", {
  # country_network() validates its weight with check_numeric_col(); four verbs
  # shaped exactly like it did not. bubble_map() and flow_map() reached
  # ggplot2's bare "Discrete value supplied to a continuous scale" -- and only
  # at *build* time, so the call itself returned happily and the failure landed
  # when the plot was printed. spike_map() blamed the join ("No rows with a
  # non-negative <col> joined to a centroid") and convergence_club() blamed the
  # panel ("Not enough countries with a complete series"), when in both cases
  # the column simply was not a number.
  snap <- world_snapshot$countries
  expect_error(bubble_map(snap, country), "must be numeric")
  expect_error(spike_map(snap, country), "must be numeric")
  expect_error(
    flow_map(data.frame(from = "France", to = "Germany", w = "x"), from, to, w),
    "must be numeric")
  pan <- do.call(rbind, lapply(2000:2010, function(y)
    data.frame(iso3c = c("USA", "FRA"), year = y, v = c("a", "b"))))
  expect_error(convergence_club(pan, v), "must be numeric")
  # The error names the column, and arrives from the call rather than the print.
  expect_error(bubble_map(snap, country), "country", fixed = TRUE)

  # Numeric columns are unaffected.
  expect_s3_class(suppressWarnings(bubble_map(snap, population)), "ggplot")
  expect_s3_class(suppressWarnings(spike_map(snap, population)), "ggplot")
  expect_s3_class(
    flow_map(data.frame(from = "France", to = "Germany", w = 5), from, to, w),
    "ggplot")
  # flow_map's weight is optional; omitting it must stay legal.
  expect_s3_class(flow_map(data.frame(from = "France", to = "Germany"),
                           from, to), "ggplot")
})

test_that("rank_countries and share_of_world report a repeated country-year", {
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
  expect_warning(lag_by_country(dup, v), "read neighbouring rows")

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
  expect_silent(rank_countries(two_years, v))

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

test_that("a wrong `origin` is our error, naming the scheme you meant", {
  # `origin` is user-facing on a dozen exported functions -- neighbors(),
  # country_join(), standardize_country(), in_group() -- and check_string()
  # only proved it was a string. An invalid scheme therefore travelled into
  # countrycode::countrycode() and died there, blaming an `origin` argument
  # the caller never passed and listing forty schemes.
  expect_error(neighbors("France", origin = "country"),
               class = "countryatlas_bad_origin")
  expect_error(country_timeline("FRA", origin = "ISO3C"),
               class = "countryatlas_bad_origin")
  expect_error(in_group("France", "EU", origin = "name"),
               class = "countryatlas_bad_origin")

  # The scheme someone half-remembers is a *fragment* of the real name, which
  # edit distance ranks badly: "country" is five edits from "country.name", so
  # the one suggestion that mattered was missing, while "name" was answered
  # with "fao" and "imf" at distance three.
  hint <- function(o) {
    msg <- cli::ansi_strip(tryCatch(wdj_to_iso3c("France", origin = o),
                                    error = conditionMessage))
    gsub("[[:space:]]+", " ", msg)
  }
  expect_match(hint("country"), "Did you mean [^?]*country[.]name")
  expect_match(hint("name"), "Did you mean [^?]*country[.]name")
  expect_match(hint("country_name"), "Did you mean [^?]*country[.]name")
  expect_match(hint("iso3"), "Did you mean [^?]*iso3c")
  expect_match(hint("ISO3C"), "Did you mean [^?]*iso3c")
  # Nonsense gets no invented suggestion.
  expect_false(grepl("Did you mean", hint("zzz")))

  # Valid schemes are untouched, including the iso3c fast path.
  expect_identical(wdj_to_iso3c("France"), "FRA")
  expect_identical(wdj_to_iso3c("fra", origin = "iso3c"), "FRA")
  expect_identical(wdj_to_iso3c("FR", origin = "iso2c"), "FRA")
  expect_identical(wdj_to_iso3c("FRA", origin = "wb"), "FRA")
})

test_that("a source's key column is a column name, not a coding scheme", {
  # key_col is documented as "the country-key column `fetch` returns" and is
  # used to index that column -- but it was also handed to countrycode as
  # `origin`, so the only registrations that worked were ones whose column
  # happened to be named after a coding scheme. All five builtins use the
  # "iso3c" default, which short-circuits before countrycode ever sees it, so
  # nothing in the package exercised the path.
  register_country_source("kt_named", key_col = "country",
                          key_type = "country.name",
                          fetch = function(indicator, countries = NULL,
                                           years = NULL) {
                            data.frame(country = c("France", "Japan"),
                                       year = 2020L, v = c(1, 2))
                          })
  on.exit(rm("kt_named", envir = countryatlas:::the_sources), add = TRUE)
  expect_silent(got <- fetch_indicator("kt_named", "v"))
  expect_identical(got$iso3c, c("FRA", "JPN"))
  expect_true("key_type" %in% names(country_sources()))

  # A bad scheme fails at registration, where the mistake is, and names
  # `key_type` rather than the internal `origin`.
  err <- tryCatch(register_country_source("kt_bad", key_type = "country",
                                          fetch = function(...) NULL),
                  error = identity)
  expect_s3_class(err, "countryatlas_bad_origin")
  expect_match(cli::ansi_strip(conditionMessage(err)), "key_type",
               fixed = TRUE)

  # Country names left under the default iso3c scheme resolve to nothing, so
  # say which knob fixes it rather than only that the values were unusable.
  register_country_source("kt_misconf", key_col = "country",
                          fetch = function(indicator, countries = NULL,
                                           years = NULL) {
                            data.frame(country = "France", year = 2020L, v = 1)
                          })
  on.exit(rm("kt_misconf", envir = countryatlas:::the_sources), add = TRUE)
  w <- tryCatch(fetch_indicator("kt_misconf", "v"), warning = identity)
  expect_s3_class(w, "countryatlas_bad_key")
  expect_match(cli::ansi_strip(conditionMessage(w)), "country.name",
               fixed = TRUE)
})

test_that("the COW/GW key warning agrees with its own count", {
  # `where` sat between the count and `ha{?s/ve}`, so cli keyed the agreement
  # to a length-1 string and every plural read "5 countries ... has".
  msg <- function(n, side) {
    iso <- c("HKG", "PRI", "MAC", "GRL", "ABW")[seq_len(n)]
    w <- tryCatch(
      countryatlas:::wdj_to_key(iso, origin = "iso3c", key = "cowc",
                                side = side),
      warning = function(x) {
        cli::ansi_strip(paste(conditionMessage(x), collapse = " "))
      })
    gsub("[[:space:]]+", " ", w)
  }
  expect_match(msg(1, NULL), "1 country resolved", fixed = TRUE)
  expect_match(msg(1, NULL), "has no cowc code", fixed = TRUE)
  expect_match(msg(3, NULL), "3 countries resolved", fixed = TRUE)
  expect_match(msg(3, NULL), "have no cowc code", fixed = TRUE)
  # `side` still distinguishes the two halves of a two-sided join, inline --
  # the wording another test pins.
  expect_match(msg(3, "`x`"), "in `x`", fixed = TRUE)
  expect_match(msg(3, "`x`"), "have no cowc code", fixed = TRUE)
  expect_false(grepl("in `x`", msg(3, NULL), fixed = TRUE))
})

test_that("interactive_map names dots the engine cannot use", {
  skip_if_no_sf_geometry()
  g <- world_geometry(geometry = "sf")
  g <- g[g$iso3c %in% c("FRA", "DEU", "ESP", "ITA"), ]
  g$gdp <- c(1, 2, 3, 4)

  # `...` was documented as reaching world_map() for ggiraph, but that branch
  # builds its own ggplot, so `style = "quantile"` was silently dropped and
  # the map came back with the default continuous fill.
  skip_if_not_installed("ggiraph")
  expect_warning(
    interactive_map(g, gdp, engine = "ggiraph", style = "quantile"),
    class = "countryatlas_engine_ignored")
  expect_no_warning(interactive_map(g, gdp, engine = "ggiraph"))

  skip_if_not_installed("leaflet")
  w <- tryCatch(
    interactive_map(g, gdp, engine = "leaflet", style = "quantile",
                    n_bins = 3),
    warning = function(x) x)
  msg <- cli::ansi_strip(paste(conditionMessage(w), collapse = " "))
  expect_match(msg, "these arguments", fixed = TRUE)
  expect_match(msg, "style", fixed = TRUE)
  expect_match(msg, "n_bins", fixed = TRUE)
  expect_no_warning(interactive_map(g, gdp, engine = "leaflet"))

  # plotly genuinely forwards, so it stays quiet and still rejects nonsense.
  skip_if_not_installed("plotly")
  expect_no_warning(interactive_map(g, gdp, engine = "plotly",
                                    style = "quantile"))
  expect_error(interactive_map(g, gdp, engine = "plotly", nonsense_arg = 1))
})

test_that('world_table(engine = "tibble") names the title it cannot draw', {
  d <- data.frame(iso3c = c("FRA", "DEU", "ESP"), gdp = c(3, 2, 1))
  # A tibble has no header, and both were dropped without a word.
  expect_warning(world_table(d, "gdp", engine = "tibble", title = "T"),
                 class = "countryatlas_engine_ignored")
  w <- tryCatch(
    world_table(d, "gdp", engine = "tibble", title = "T", subtitle = "S"),
    warning = function(x) x)
  msg <- cli::ansi_strip(paste(conditionMessage(w), collapse = " "))
  expect_match(msg, "these arguments", fixed = TRUE)
  expect_match(msg, "title", fixed = TRUE)
  expect_match(msg, "subtitle", fixed = TRUE)
  # Silent when there is nothing to drop, and on the engine that draws them.
  expect_no_warning(world_table(d, "gdp", engine = "tibble"))
  skip_if_not_installed("gt")
  expect_no_warning(world_table(d, "gdp", engine = "gt", title = "T"))
  # The gt path's existing objection is unchanged.
  expect_error(world_table(d, "gdp", engine = "gt", subtitle = "S"),
               "needs a")
})

test_that("index_to says base_year is required, as deflate does", {
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
  expect_true(all(is.na(index_to(d, gdp, base_year = 1999)$gdp_index)))
})

test_that("every character column argument catches a bare symbol", {
  d <- data.frame(iso3c = c("FRA", "DEU", "ESP", "ITA"), year = 2000L,
                  gdp = c(1, 2, 3, 4), region = c("A", "B", "A", "B"))
  # These take strings but sit beside an argument that takes a bare column, so
  # `by = region` is the natural slip -- and it failed during evaluation, as
  # base R's "object 'region' not found", before validation could run.
  expect_error(aggregate_regions(d, "gdp", by = region),
               "takes column names as strings")
  expect_error(world_table(d, "gdp", columns = gdp),
               "takes column names as strings")
  expect_error(country_codes(codes = iso3c),
               "takes column names as strings")
  # The already-guarded three still behave.
  expect_error(complete_years(d, 2000:2001, value = gdp),
               "takes column names as strings")
  expect_error(interpolate_missing(d, value = gdp),
               "takes column names as strings")
  expect_error(audit_coverage(d, indicator = gdp),
               "takes column names as strings")
  # ...and the string form is unaffected.
  expect_s3_class(aggregate_regions(d, "gdp", by = "region"), "tbl_df")
  expect_s3_class(country_codes(codes = "iso3c"), "tbl_df")
  # rank_countries() documents both forms, so a bare symbol is valid there.
  expect_s3_class(rank_countries(d, "gdp", within = region), "tbl_df")
  expect_s3_class(rank_countries(d, "gdp", within = "region"), "tbl_df")
})

test_that("spatial_lag names the countries its weights exclude", {
  skip_if_no_sf_geometry()
  w <- country_weights("contiguity")
  islands <- data.frame(
    iso3c = c("FRA", "DEU", "ESP", "ITA", "BEL", "NLD", "ISL", "JPN", "AUS"),
    gdp = as.numeric(1:9))
  connected <- islands[islands$iso3c %in%
                         c("FRA", "DEU", "ESP", "ITA", "BEL", "NLD"), ]

  # An NA here is indistinguishable from one caused by a missing input value,
  # so the codes travel as an attribute -- the frame-shaped counterpart to the
  # `excluded` column morans_i() returns. Deliberately not a warning: on real
  # geography some country always lacks a land neighbour, so a warning would
  # fire on every ordinary call (and test-features-3.0.0.R pins the silence).
  got <- spatial_lag(islands, "gdp", weights = w)
  expect_equal(attr(got, "countryatlas_excluded"), c("AUS", "ISL", "JPN"))
  expect_true(all(is.na(got$gdp_lag[got$iso3c %in% c("ISL", "JPN", "AUS")])))
  expect_no_warning(spatial_lag(islands, "gdp", weights = w))

  # It agrees with what morans_i() reports for the same input.
  mi <- morans_i(islands, "gdp", weights = w, n_perm = 0)
  expect_setequal(attr(got, "countryatlas_excluded"), mi$excluded[[1]])
  expect_equal(length(attr(got, "countryatlas_excluded")), mi$n_excluded)

  # Empty (not absent) when every country is connected, and values untouched.
  ok <- spatial_lag(connected, "gdp", weights = w)
  expect_equal(attr(ok, "countryatlas_excluded"), character(0))
  expect_false(anyNA(ok$gdp_lag))
  expect_equal(got$gdp_lag[got$iso3c %in% connected$iso3c], ok$gdp_lag)

  # The panel branch carries the union across years.
  pan <- rbind(transform(islands, year = 2000L),
               transform(islands, year = 2001L))
  expect_equal(attr(spatial_lag(pan, "gdp", weights = w),
                    "countryatlas_excluded"), c("AUS", "ISL", "JPN"))
})

test_that("neighbors tells a typo from a country with no land border", {
  skip_if_no_sf_geometry()
  # Both return zero rows. Only one of them is a mistake, and the function used
  # to be silent about either -- while distance_between() and convert_country()
  # both report an unresolved value.
  expect_no_warning(fr <- neighbors("France"))
  expect_gt(nrow(fr), 0L)
  expect_no_warning(ice <- neighbors("Iceland"))
  expect_equal(nrow(ice), 0L)            # a real zero stays quiet

  w <- tryCatch(neighbors("Nowhereland"), warning = function(x) x)
  msg <- gsub("[[:space:]]+", " ",
              cli::ansi_strip(paste(conditionMessage(w), collapse = " ")))
  expect_match(msg, "1 value did not resolve", fixed = TRUE)
  expect_match(msg, "it has no neighbours", fixed = TRUE)
  expect_match(msg, "Nowhereland", fixed = TRUE)
  # Agrees at n = 2, verb included.
  expect_match(gsub("[[:space:]]+", " ", cli::ansi_strip(paste(conditionMessage(
    tryCatch(neighbors(c("Nowhereland", "Atlantis")), warning = function(x) x)),
    collapse = " "))), "2 values did not resolve", fixed = TRUE)

  # A resolved name still returns its borders even alongside an unresolved one.
  got <- suppressWarnings(neighbors(c("France", "Nowhereland")))
  expect_equal(nrow(got), nrow(fr))
  expect_no_warning(neighbors("Nowhereland", warn = FALSE))
  expect_error(neighbors("France", warn = "x"), "`warn`")
})

test_that("country_timeline reports a name it cannot resolve", {
  # It returned a row of NA in silence, where dissolve_country() -- same input
  # shape -- has always warned.
  w <- tryCatch(country_timeline("Nowhereland"), warning = function(x) x)
  msg <- gsub("[[:space:]]+", " ",
              cli::ansi_strip(paste(conditionMessage(w), collapse = " ")))
  expect_match(msg, "1 name matched neither", fixed = TRUE)
  expect_match(msg, "Nowhereland", fixed = TRUE)
  expect_match(msg, "check_country_match", fixed = TRUE)
  # Agrees at n = 2.
  expect_match(gsub("[[:space:]]+", " ", cli::ansi_strip(paste(conditionMessage(
    tryCatch(country_timeline(c("Nowhereland", "Atlantis")),
             warning = function(x) x)), collapse = " "))),
    "2 names matched neither", fixed = TRUE)

  # A historical name must stay silent: "USSR" is meant to fail the ISO lookup
  # and be picked up by the historical spine.
  expect_no_warning(country_timeline(c("USSR", "Estonia", "France")))
  expect_no_warning(country_timeline(character(0)))
  expect_no_warning(country_timeline("Nowhereland", warn = FALSE))
  expect_error(country_timeline("France", warn = "x"), "`warn`")

  # The returned values are unchanged.
  out <- suppressWarnings(country_timeline(c("France", "Nowhereland")))
  expect_equal(out$iso3c, c("FRA", NA))
  expect_equal(out$input, c("France", "Nowhereland"))
})

test_that("a panel verb that computes nothing says so", {
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

test_that("country_network checks top_n before building the network", {
  d <- data.frame(o = c("France", "Germany"), d = c("Germany", "France"),
                  w = c(1, 2))
  # It used to build the matrix, node table and sorted edge list first.
  expect_error(country_network(d, o, d, w, top_n = "x"), "`top_n`")
  expect_error(country_network(d, o, d, w, top_n = -1), "`top_n`")
  net <- country_network(d, o, d, w, top_n = 1)
  expect_equal(nrow(net$edges), 1L)
  expect_named(net, c("nodes", "edges"))
})

test_that("share_of_world reports a total it cannot use", {
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

test_that("the tmap engine names an older tmap instead of failing opaquely", {
  # DESCRIPTION pins no version on any Suggests package, so need_pkg("tmap") is
  # satisfied by any tmap -- including a 3.x that exports none of the scale
  # constructors this engine builds with. The capability is checked, not a
  # version number, so this stays right whichever release introduced them.
  expect_true(isTRUE(countryatlas:::check_tmap_api(
    have = countryatlas:::tmap_scale_api)))

  # A tmap 3-shaped export list: tm_shape and tm_polygons, no tm_scale_*().
  err <- tryCatch(
    countryatlas:::check_tmap_api(have = c("tm_shape", "tm_polygons")),
    error = function(e) e)
  expect_s3_class(err, "countryatlas_old_tmap")
  msg <- gsub("[[:space:]]+", " ",
              cli::ansi_strip(paste(conditionMessage(err), collapse = " ")))
  expect_match(msg, "too old", fixed = TRUE)
  expect_match(msg, "tm_scale_intervals", fixed = TRUE)
  expect_match(msg, "ggplot2", fixed = TRUE)

  # A partial upgrade is still too old, and the message names only what is
  # actually missing.
  partial <- tryCatch(
    countryatlas:::check_tmap_api(
      have = c("tm_scale_intervals", "tm_shape")),
    error = function(e) e)
  expect_s3_class(partial, "countryatlas_old_tmap")
  pmsg <- cli::ansi_strip(paste(conditionMessage(partial), collapse = " "))
  expect_match(pmsg, "tm_scale_continuous", fixed = TRUE)
  expect_false(grepl("tm_scale_intervals", pmsg, fixed = TRUE))

  # And the installed tmap really does satisfy it.
  skip_if_not_installed("tmap")
  expect_true(isTRUE(countryatlas:::check_tmap_api()))
})

test_that("the tmap engine honours projection and names what it cannot do", {
  skip_if_not_installed("tmap")
  skip_if_no_sf_geometry()
  g <- world_geometry(geometry = "sf")
  g$gdp <- as.numeric(seq_len(nrow(g)))

  # projection / recenter were dropped, so even the documented default went
  # unapplied -- and a bad projection name was never rejected.
  expect_no_warning(world_map(g, gdp, engine = "tmap"))
  expect_no_warning(world_map(g, gdp, engine = "tmap",
                              projection = "mollweide"))
  expect_error(world_map(g, gdp, engine = "tmap", projection = "nope"),
               "must be one of", class = "countryatlas_error")
  # The engine's own contract: printing stays silent.
  expect_silent(print(world_map(g, gdp, engine = "tmap")))

  # What tmap genuinely cannot do is named rather than quietly skipped, and
  # the message agrees with its own count at 1 and at 2.
  one <- tryCatch(world_map(g, gdp, engine = "tmap", footnote = "x"),
                  warning = function(w) w)
  expect_s3_class(one, "countryatlas_engine_ignored")
  m1 <- cli::ansi_strip(paste(conditionMessage(one), collapse = " "))
  expect_match(m1, "this argument", fixed = TRUE)
  expect_match(m1, "ignores it", fixed = TRUE)
  expect_match(m1, "footnote", fixed = TRUE)

  two <- tryCatch(
    world_map(g, gdp, engine = "tmap", footnote = "x", disputes = "mark"),
    warning = function(w) w)
  m2 <- cli::ansi_strip(paste(conditionMessage(two), collapse = " "))
  expect_match(m2, "these arguments", fixed = TRUE)
  expect_match(m2, "ignores them", fixed = TRUE)

  for (a in list(list(na_style = "hatched"), list(classification_report = TRUE),
                 list(disputes = "mark"))) {
    expect_warning(
      do.call(world_map, c(list(g, quote(gdp), engine = "tmap"), a)),
      class = "countryatlas_engine_ignored")
  }
  # The ggplot2 engine supports all of them, so it stays quiet.
  expect_no_warning(world_map(g, gdp, footnote = "x", disputes = "mark"))
})

test_that("globe_map(interactive = TRUE) validates before handing off", {
  skip_if_no_sf_geometry()
  skip_if_not_installed("mapgl")
  g <- world_geometry(geometry = "sf")
  g$gdp <- as.numeric(seq_len(nrow(g)))
  # arg_match() and check_label_args() sat *below* the hand-off, so nothing
  # was checked on this path.
  expect_error(globe_map(g, gdp, interactive = TRUE, style = "nonsense"),
               "must be one of")
  expect_error(globe_map(g, gdp, interactive = TRUE,
                         title = c("a", "b", "c")),
               "single value")
  # ...and the ggplot2 styling that cannot travel to MapLibre is named.
  expect_warning(globe_map(g, gdp, interactive = TRUE, style = "quantile",
                           palette = "magma", title = "t"),
                 class = "countryatlas_engine_ignored")
  # The static path is unaffected.
  expect_no_warning(globe_map(g, gdp, style = "quantile", palette = "magma"))
})

test_that("the tmap engine honours na_label", {
  skip_if_not_installed("tmap")
  skip_if_no_sf_geometry()
  g <- world_geometry(geometry = "sf")
  g <- g[g$iso3c %in% c("FRA", "DEU", "USA", "BRA", "CHN", "IND"), ]
  g$gdp <- c(1, 2, 3, NA, 5, NA)
  # It was passed into the backend and never used, so tmap's own default label
  # appeared and the caller had no sign their label had been dropped.
  seen <- function(p) {
    grepl("Nothing here", paste(utils::capture.output(str(p, max.level = 8)),
                                collapse = " "), fixed = TRUE)
  }
  for (st in c("quantile", "continuous")) {
    expect_true(seen(world_map(g, "gdp", style = st, engine = "tmap",
                               na_label = "Nothing here")),
                label = paste("na_label reaches tmap for style", st))
  }
  gc2 <- g
  gc2$gdp <- c("a", "b", "a", NA, "b", NA)
  expect_true(seen(world_map(gc2, "gdp", style = "categorical",
                             engine = "tmap", na_label = "Nothing here")))
  # A length-1 NA or NULL means "leave the engine's formatter alone", the same
  # contract the ggplot2 path has always had.
  expect_no_error(world_map(g, "gdp", style = "quantile", engine = "tmap",
                            na_label = NA))
  expect_no_error(world_map(g, "gdp", style = "quantile", engine = "tmap",
                            na_label = NULL))
  # Both engines read the argument the same way.
  expect_null(countryatlas:::na_label_value(NULL))
  expect_null(countryatlas:::na_label_value(NA))
  expect_null(countryatlas:::na_label_value(character()))
  expect_equal(countryatlas:::na_label_value(c("first", "second")),
               "first")
})

test_that("the polygon backend says when it is ignoring projection", {
  # `recenter` already warned when it could not be honoured; `projection` was
  # documented for the sf backend but taken and dropped in silence.
  expect_warning(world_geometry(projection = "mollweide"),
                 class = "countryatlas_projection_ignored")
  d <- data.frame(iso3c = c("FRA", "DEU"), gdp = 1:2)
  expect_warning(attach_geometry(d, projection = "mollweide"),
                 class = "countryatlas_projection_ignored")
  # The default, and an explicit restatement of it, stay quiet.
  expect_no_warning(world_geometry())
  expect_no_warning(world_geometry(projection = "equal_earth"))
  # The sf backend honours both, so neither warns there.
  skip_if_no_sf_geometry()
  expect_no_warning(world_geometry(geometry = "sf", projection = "mollweide"))
  expect_no_warning(world_geometry(geometry = "sf", recenter = 150))
})

test_that('world_data(geometry = "none") warns for every sf-only argument', {
  fake <- tibble::tibble(iso3c = c("FRA", "DEU"), country = c("a", "b"),
                         gdp_per_capita = c(1, 2))
  local_mocked_bindings(country_data = function(...) fake,
                        .package = "countryatlas")
  # No geometry is fetched at all, so none of the three can be honoured.
  expect_warning(world_data(2020, geometry = "none", projection = "mollweide"),
                 class = "countryatlas_projection_ignored")
  expect_warning(world_data(2020, geometry = "none", recenter = 150),
                 class = "countryatlas_recenter_ignored")
  expect_warning(world_data(2020, geometry = "none", scale = "large"),
                 class = "countryatlas_scale_ignored")
  expect_no_warning(world_data(2020, geometry = "none"))
})

test_that('world_data(geometry = "none") still honours region', {
  # region was only applied inside attach_geometry(), which this branch skips,
  # so asking for one continent quietly returned the whole world.
  fake <- tibble::tibble(
    iso3c = c("FRA", "DEU", "USA", "BRA", "CHN"),
    country = c("France", "Germany", "United States", "Brazil", "China"),
    gdp_per_capita = c(1, 2, 3, 4, 5))
  local_mocked_bindings(country_data = function(...) fake,
                        .package = "countryatlas")

  expect_equal(nrow(world_data(2020, geometry = "none")), 5L)
  expect_equal(world_data(2020, geometry = "none", region = "Europe")$iso3c,
               c("FRA", "DEU"))
  expect_equal(
    world_data(2020, geometry = "none", region = c("FRA", "BRA"))$iso3c,
    c("FRA", "BRA"))
  # A bounding box needs shapes to clip; refuse rather than return the world.
  expect_error(world_data(2020, geometry = "none", region = c(-10, 35, 30, 60)),
               class = "countryatlas_bbox_without_geometry")
  # `scale` is an sf-backend option, so it cannot be honoured here either.
  expect_warning(world_data(2020, geometry = "none", scale = "large"),
                 class = "countryatlas_scale_ignored")
  expect_no_warning(world_data(2020, geometry = "none"))
})

test_that("a multi-value scale is rejected before it becomes a cache key", {
  skip_if_no_sf_geometry()
  # paste0("scale_", scale) vectorised, so `[[` on the cache environment failed
  # with base R's "wrong arguments for subsetting an environment". The scalar
  # bad values all reached the real check and reported properly.
  expect_error(country_borders(scale = c("small", "large")),
               "must be one of", class = "countryatlas_error")
  expect_error(world_geometry(geometry = "sf", scale = c("small", "large")),
               "must be one of", class = "countryatlas_error")
  for (bad in list("smal", 2, NA_character_, NULL)) {
    expect_error(country_borders(scale = bad), class = "countryatlas_error")
  }
  # Passing the full choice vector still means "take the default", as
  # match.arg() would.
  expect_s3_class(world_geometry(geometry = "sf",
                                 scale = c("small", "medium", "large")), "sf")
})

test_that("the polygon backend says when it is ignoring scale", {
  # It serves one bundled resolution, so `scale` cannot be honoured -- but it
  # was accepted in silence, and `scale = 2` was not even rejected.
  expect_warning(world_geometry(scale = "large"),
                 class = "countryatlas_scale_ignored")
  expect_warning(world_geometry(scale = 2),
                 class = "countryatlas_scale_ignored")
  d <- data.frame(iso3c = c("FRA", "DEU"), gdp = 1:2)
  expect_warning(attach_geometry(d, scale = "large"),
                 class = "countryatlas_scale_ignored")
  # The default is what the backend actually serves, so it stays quiet.
  expect_no_warning(world_geometry())
  expect_no_warning(attach_geometry(d))
  expect_no_warning(world_geometry(scale = "small"))
})

test_that("cartogram_diagnostics names invalid geometry, not s2's loop", {
  skip_if_not_installed("sf")
  bow <- sf::st_polygon(list(rbind(c(0, 0), c(2, 2), c(2, 0), c(0, 2), c(0, 0))))
  sq <- function(x0) sf::st_polygon(list(rbind(
    c(x0, 0), c(x0 + 1, 0), c(x0 + 1, 1), c(x0, 1), c(x0, 0))))
  bad <- sf::st_sf(iso3c = c("USA", "FRA"), gdp = c(1, 2),
                   geometry = sf::st_sfc(bow, sq(3), crs = 4326))
  expect_error(cartogram_diagnostics(bad, "gdp"),
               class = "countryatlas_invalid_geometry")
  # It names the country rather than "Loop 0", and agrees at n = 1...
  err <- tryCatch(cartogram_diagnostics(bad, "gdp"), error = function(e) e)
  msg <- cli::ansi_strip(paste(conditionMessage(err), collapse = " "))
  expect_match(msg, "USA", fixed = TRUE)
  expect_match(msg, "1 geometry is invalid", fixed = TRUE)
  expect_match(msg, "st_make_valid", fixed = TRUE)
  # ...and at n = 2, where cli's agreement markers key to the wrong number if
  # anything numeric is interpolated between the count and the marker.
  bow2 <- sf::st_polygon(list(rbind(c(5, 0), c(7, 2), c(7, 0), c(5, 2), c(5, 0))))
  bad2 <- sf::st_sf(iso3c = c("USA", "FRA"), gdp = c(1, 2),
                    geometry = sf::st_sfc(bow, bow2, crs = 4326))
  err2 <- tryCatch(cartogram_diagnostics(bad2, "gdp"), error = function(e) e)
  expect_match(cli::ansi_strip(paste(conditionMessage(err2), collapse = " ")),
               "2 geometries are invalid", fixed = TRUE)
  # Valid geometry is untouched.
  good <- sf::st_sf(iso3c = c("USA", "FRA"), gdp = c(1, 2),
                    geometry = sf::st_sfc(sq(0), sq(3), crs = 4326))
  expect_s3_class(cartogram_diagnostics(good, "gdp"), "tbl_df")
})

test_that("complete_years keeps sf and gives invented years real geometry", {
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

test_that("no verb hands back a grouping the caller did not ask for", {
  iso <- c("USA", "FRA", "DEU", "BRA")
  d <- expand.grid(iso3c = iso, year = 2000:2002, stringsAsFactors = FALSE)
  for (cc in c("gdp", "pop", "num", "den")) {
    d[[cc]] <- as.numeric(seq_len(nrow(d))) + 10
  }
  d$region <- ifelse(d$iso3c %in% c("USA", "BRA"), "Americas", "Other")
  gd <- dplyr::group_by(d, .data$region)
  # to_ppp() and smooth_rates() ended in a bare `data`, so the grouping came
  # straight back out and the caller's next mutate() computed per region.
  verbs <- list(
    share_of_world      = function(x) share_of_world(x, "gdp"),
    per_capita          = function(x) per_capita(x, "gdp", "pop"),
    index_to            = function(x) index_to(x, "gdp", 2000),
    growth_rate         = function(x) growth_rate(x, "gdp"),
    rank_countries      = function(x) rank_countries(x, "gdp"),
    to_ppp              = function(x) to_ppp(x, "gdp", "pop"),
    smooth_rates        = function(x) smooth_rates(x, "num", "den"),
    lag_by_country      = function(x) lag_by_country(x, "gdp"),
    diff_by_country     = function(x) diff_by_country(x, "gdp"),
    interpolate_missing = function(x) interpolate_missing(x, "gdp"),
    complete_years      = function(x) complete_years(x, 2000:2002, "gdp"),
    aggregate_regions   = function(x) aggregate_regions(x, "gdp")
  )
  # Every *mode*, not just the default: the leak survived on early-return
  # paths (`method = "none"`) of verbs whose main path had been fixed.
  verbs <- c(verbs, list(
    `smooth_rates(none)` = function(x) {
      smooth_rates(x, "num", "den", method = "none")
    },
    `interpolate_missing(none)` = function(x) {
      interpolate_missing(x, "gdp", method = "none")
    },
    `interpolate_missing(locf)` = function(x) {
      interpolate_missing(x, "gdp", method = "locf")
    },
    `complete_years(locf)` = function(x) {
      complete_years(x, 2000:2002, "gdp", method = "locf")
    },
    `growth_rate(cagr)` = function(x) growth_rate(x, "gdp", type = "cagr"),
    `smooth_rates(1 row)` = function(x) {
      smooth_rates(x[1, , drop = FALSE], "num", "den")
    }
  ))
  for (nm in names(verbs)) {
    out <- suppressWarnings(suppressMessages(verbs[[nm]](gd)))
    expect_false(dplyr::is_grouped_df(out), label = paste(nm, "returns grouped"))
    # A plain data.frame comes back as a tibble whichever mode ran.
    plain <- suppressWarnings(suppressMessages(verbs[[nm]](d)))
    expect_s3_class(plain, "tbl_df")
    # ...and the values do not depend on the grouping either.
    expect_equal(as.data.frame(dplyr::ungroup(out)), as.data.frame(plain),
                 ignore_attr = TRUE, label = paste(nm, "differs when grouped"))
  }
})

test_that("spatial_lag normalises on both of its branches", {
  skip_if_no_sf_geometry()
  iso <- c("FRA", "DEU", "ESP", "ITA", "BEL", "NLD")
  d <- expand.grid(iso3c = iso, year = 2000:2002, stringsAsFactors = FALSE)
  d$gdp <- as.numeric(seq_len(nrow(d)))
  d$region <- ifelse(d$iso3c %in% c("FRA", "BEL"), "A", "B")
  w <- country_weights("contiguity")
  # It takes a different path for a panel than for a cross-section, and both
  # ended in a bare `data`.
  for (dd in list(d, d[d$year == 2000, ])) {
    out <- suppressWarnings(spatial_lag(dplyr::group_by(dd, .data$region),
                                        "gdp", weights = w))
    expect_false(dplyr::is_grouped_df(out))
    expect_s3_class(suppressWarnings(spatial_lag(dd, "gdp", weights = w)),
                    "tbl_df")
  }
})

test_that('join_world(geometry = "none") still honours region', {
  d <- data.frame(country = c("France", "Germany", "Brazil", "China"),
                  gdp = 1:4)
  # Same defect as world_data(): the "none" branch returned before any of the
  # geometry arguments were applied.
  all_rows <- join_world(d, country, geometry = "none", warn = FALSE)
  expect_equal(nrow(all_rows), 4L)
  eu <- join_world(d, country, geometry = "none", region = "Europe",
                   warn = FALSE)
  expect_setequal(eu$iso3c, c("FRA", "DEU"))
  expect_setequal(
    join_world(d, country, geometry = "none", region = c("BRA", "CHN"),
               warn = FALSE)$iso3c,
    c("BRA", "CHN"))
  expect_error(
    join_world(d, country, geometry = "none", region = c(-10, 35, 30, 60),
               warn = FALSE),
    class = "countryatlas_bbox_without_geometry")
  expect_warning(
    join_world(d, country, geometry = "none", scale = "large", warn = FALSE),
    class = "countryatlas_scale_ignored")
  expect_no_warning(join_world(d, country, geometry = "none", warn = FALSE))
})

test_that("standardize_subnational says when it has no usable crosswalk", {
  # It looks for geo_name/name/region_name in regions::nuts_lau_2019 or
  # all_valid_nuts_codes. regions 0.1.8 exposes neither, so the lookup is
  # skipped -- silently, leaving the caller with "did not resolve" and a hint
  # about European coverage that was never consulted.
  # Structural for the notice, behavioural for the result: the note is
  # `.frequency = "once"`, so whether it fires *here* depends on whether an
  # earlier test tripped it first. The package tests its one-shot notices the
  # same way.
  # The block lives in the internal helper, not the exported wrapper.
  src <- paste(deparse(countryatlas:::subnational_lookup), collapse = " ")
  expect_match(src, "no name-to-code crosswalk", fixed = TRUE)
  expect_match(src, "subnational-no-crosswalk", fixed = TRUE)

  # The condition that makes the note fire: neither candidate dataset in the
  # installed `regions` exposes a name column the lookup recognises, so the
  # crosswalk is skipped rather than consulted.
  skip_if_not_installed("regions")
  cand <- c("geo_name", "name", "region_name")
  cw <- tryCatch(regions::nuts_lau_2019, error = function(e) NULL)
  skip_if(is.null(cw), "regions::nuts_lau_2019 unavailable")
  expect_false(any(cand %in% names(cw)))

  # And the documented promise holds either way: a code passes through, a name
  # gets NA rather than a guess from a different code system.
  d <- data.frame(reg = c("Bayern", "DE-BY"), ctry = "Germany")
  out <- suppressMessages(suppressWarnings(
    standardize_subnational(d, reg, ctry)))
  expect_equal(out$iso_3166_2, c(NA, "DE-BY"))
})

test_that("an unreachable or misshapen GISCO response is named", {
  # giscoR answers a failed download with NULL rather than an error, the same
  # shape fetch_owid() guards for owidR. Unguarded it reached sf as "no
  # applicable method for 'st_as_sf' applied to an object of class NULL"; a
  # response without NUTS_ID gave base R's "replacement has 0 rows".
  skip_if_not_installed("giscoR")
  skip_if_not_installed("sf")
  mk <- function(ids) {
    if (!length(ids)) {
      return(sf::st_sf(NUTS_ID = character(0), NAME_LATN = character(0),
                       LEVL_CODE = integer(0),
                       geometry = sf::st_sfc(crs = 4326)))
    }
    pts <- sf::st_sfc(lapply(seq_along(ids),
                             function(i) sf::st_point(c(i, i))), crs = 4326)
    sf::st_sf(NUTS_ID = ids, NAME_LATN = paste0("R", seq_along(ids)),
              LEVL_CODE = 2L, geometry = pts)
  }
  ret <- NULL
  local_mocked_bindings(gisco_get_nuts = function(...) ret, .package = "giscoR")

  ret <- mk(c("FR10", "DE21", "IT11"))
  got <- suppressWarnings(nuts_geometry(level = 2))
  expect_s3_class(got, "sf")
  expect_true(all(c("nuts_id", "iso3c") %in% names(got)))

  ret <- NULL
  expect_error(nuts_geometry(level = 2), class = "countryatlas_no_nuts")
  ret <- mk(character(0))
  expect_error(nuts_geometry(level = 2), class = "countryatlas_no_nuts")

  ret <- mk(c("FR10", "DE21"))
  names(ret)[names(ret) == "NUTS_ID"] <- "ID"
  expect_error(nuts_geometry(level = 2), class = "countryatlas_bad_response")
  expect_match(cli::ansi_strip(conditionMessage(tryCatch(
    nuts_geometry(level = 2), error = identity))), "no NUTS_ID column",
    fixed = TRUE)
})

test_that("a changed World Bank response shape is named, not called a failure", {
  # countrycode() is handed raw$iso2c directly, so a response with neither key
  # raised its own "sourcevar must be a character or numeric vector", which the
  # fetch wrapper relabelled "Could not fetch ... from the World Bank API" --
  # blaming the network for a response-shape change.
  skip_if_not_installed("WDI")
  wd <- NULL
  local_mocked_bindings(WDI = function(...) wd, .package = "WDI")
  msg <- function(e) cli::ansi_strip(conditionMessage(tryCatch(e,
    warning = identity)))

  wd <- data.frame(country = c("France", "Japan"), year = 2020L, v = c(1, 2))
  expect_warning(fetch_wdi(c(v = "ZK1"), start = 2020, end = 2020),
                 class = "countryatlas_bad_response")
  m <- msg(fetch_wdi(c(v = "ZK2"), start = 2020, end = 2020))
  expect_match(m, "carries no country key", fixed = TRUE)
  expect_false(grepl("Could not fetch", m, fixed = TRUE))
  expect_false(grepl("sourcevar", m, fixed = TRUE))

  # Either key on its own is fine, and an empty response keeps its own
  # diagnosis -- unique codes throughout, because the fetch is memoised.
  wd <- data.frame(iso2c = c("FR", "JP"), country = c("France", "Japan"),
                   year = 2020L, v = c(1, 2))
  expect_silent(fetch_wdi(c(v = "ZK3"), start = 2020, end = 2020))
  wd <- data.frame(iso3c = c("FRA", "JPN"), country = c("France", "Japan"),
                   year = 2020L, v = c(1, 2))
  expect_silent(fetch_wdi(c(v = "ZK4"), start = 2020, end = 2020))
  wd <- data.frame(iso2c = character(0), country = character(0),
                   year = integer(0), v = numeric(0))
  expect_warning(fetch_wdi(c(v = "ZK5"), start = 2020, end = 2020),
                 class = "countryatlas_no_data")
})

test_that("a non-numeric provider response is reported, not silently NA", {
  # as.numeric() turns non-numeric text into NA without complaint, so a
  # provider answering with "n/a" or ".." handed back a column of pure NA that
  # reads as "no data for these countries" rather than "not numeric".
  # fetch_eurostat()/fetch_oecd() name the value column outright, so they reach
  # the coercion; fetch_owid() auto-detects and refuses a non-numeric column.
  skip_if_not_installed("OECD")
  oe <- NULL
  local_mocked_bindings(get_dataset = function(...) oe, .package = "OECD")

  oe <- data.frame(LOCATION = c("FRA", "JPN"), Time = 2020L,
                   obsValue = c(1, 2))
  expect_silent(fetch_oecd("x"))
  # A value the provider itself reports as missing is already NA, not a parse
  # failure, so it must stay silent.
  oe <- data.frame(LOCATION = c("FRA", "JPN"), Time = 2020L,
                   obsValue = c(NA_real_, 2))
  expect_silent(fetch_oecd("x"))

  oe <- data.frame(LOCATION = c("FRA", "JPN"), Time = 2020L,
                   obsValue = c("1.5", "n/a"), stringsAsFactors = FALSE)
  expect_warning(out <- fetch_oecd("x"),
                 class = "countryatlas_unparsed_values")
  expect_equal(out$x, c(1.5, NA))
  msg <- function(e) cli::ansi_strip(conditionMessage(tryCatch(e,
    warning = identity)))
  expect_match(msg(fetch_oecd("x")), "1 value in the provider's response is",
               fixed = TRUE)
  oe <- data.frame(LOCATION = c("FRA", "JPN"), Time = 2020L,
                   obsValue = c("n/a", ".."), stringsAsFactors = FALSE)
  expect_match(msg(fetch_oecd("x")), "2 values in the provider's response are",
               fixed = TRUE)

  # A factor value column must still give the labels, not the level indices.
  oe <- data.frame(LOCATION = c("FRA", "JPN"), Time = 2020L,
                   obsValue = factor(c("10", "20")))
  expect_silent(fac <- fetch_oecd("x"))
  expect_equal(fac$x, c(10, 20))
})

test_that("the provider adapters report the rows they discard", {
  # Each adapter ends by keeping one row per country-year -- the contract the
  # joins rely on -- but kept whichever came first and said nothing, so a
  # provider answering with two different values for one country-year handed
  # back an arbitrary one, order-dependently and invisibly.
  skip_if_not_installed("owidR")
  ret <- NULL
  local_mocked_bindings(owid = function(...) ret, .package = "owidR")

  ret <- data.frame(entity = c("France", "Japan"), year = 2020L, v = c(10, 20))
  expect_silent(fetch_owid("x"))

  ret <- data.frame(entity = c("France", "France"), year = 2020L, v = c(1, 99))
  expect_warning(out <- fetch_owid("x"),
                 class = "countryatlas_provider_duplicates")
  expect_identical(nrow(out), 1L)
  expect_match(cli::ansi_strip(conditionMessage(tryCatch(fetch_owid("x"),
    warning = identity))), "1 duplicate country-year row,", fixed = TRUE)

  ret <- data.frame(entity = c("France", "France", "Japan", "Japan"),
                    year = 2020L, v = c(1, 99, 2, 3))
  expect_match(cli::ansi_strip(conditionMessage(tryCatch(fetch_owid("x"),
    warning = identity))), "2 duplicate country-year rows", fixed = TRUE)

  # A country with two years is a panel, not a duplicate.
  ret <- data.frame(entity = c("France", "France"), year = c(2019L, 2020L),
                    v = c(1, 2))
  expect_silent(fetch_owid("x"))
})

test_that("a source whose keys collapse warns instead of repeating rows", {
  # Standardisation merges keys as well as failing on them: "United States"
  # and "USA" both reach USA, and add_indicator()'s left_join then matches
  # twice, so a two-row frame came back with three rows and one country
  # holding two different values -- silently, because dplyr only warns on
  # many-to-many, not one-to-many. join_world() has warned about exactly this
  # since it gained warn_key_collapse(); the source adapters never did.
  register_country_source("kc_dup", key_col = "country",
                          key_type = "country.name",
                          fetch = function(indicator, countries = NULL,
                                           years = NULL) {
                            data.frame(country = c("United States", "USA"),
                                       year = 2020L, v = c(1, 2))
                          })
  on.exit(rm("kc_dup", envir = countryatlas:::the_sources), add = TRUE)
  expect_warning(fetch_indicator("kc_dup", "v"),
                 class = "countryatlas_key_collapse")

  # The source's own key column is not the caller's data. `add_cols` excluded
  # only "iso3c", so a source keyed on any other column handed that raw column
  # over as though it had been requested -- a stray `country` column in a
  # frame that already had iso3c.
  # The collapse check only sees a code reached from more than one raw value.
  # A source returning the same key twice collapses nothing, so it warned about
  # nothing -- while add_indicator()'s join still turned two rows into three.
  mk <- function(iso, v, yr = 2020L) {
    function(indicator, countries = NULL, years = NULL) {
      data.frame(iso3c = iso, year = yr, v = v)
    }
  }
  register_country_source("kc_same", fetch = mk(c("USA", "USA"), c(1, 99)))
  register_country_source("kc_two", fetch = mk(c("USA", "USA", "FRA", "FRA"),
                                               c(1, 99, 2, 3)))
  register_country_source("kc_panel",
                          fetch = function(indicator, countries = NULL,
                                           years = NULL) {
                            data.frame(iso3c = rep(c("USA", "FRA"), each = 2),
                                       year = rep(2019:2020, 2), v = 1:4)
                          })
  on.exit(for (s in c("kc_same", "kc_two", "kc_panel"))
    rm(list = s, envir = countryatlas:::the_sources), add = TRUE)
  expect_warning(fetch_indicator("kc_same", "v"),
                 class = "countryatlas_duplicate_key")
  expect_match(cli::ansi_strip(conditionMessage(tryCatch(
    fetch_indicator("kc_same", "v"), warning = identity))),
    "1 duplicate key row.", fixed = TRUE)
  expect_match(cli::ansi_strip(conditionMessage(tryCatch(
    fetch_indicator("kc_two", "v"), warning = identity))),
    "2 duplicate key rows", fixed = TRUE)
  # A real panel has several years per country and must not be flagged: the
  # key is iso3c *and* year wherever a year column exists.
  expect_silent(fetch_indicator("kc_panel", "v"))

  register_country_source("kc_clean", key_col = "country",
                          key_type = "country.name",
                          fetch = function(indicator, countries = NULL,
                                           years = NULL) {
                            data.frame(country = c("France", "Japan"),
                                       year = 2020L, v = c(1, 2))
                          })
  on.exit(rm("kc_clean", envir = countryatlas:::the_sources), add = TRUE)
  base <- data.frame(iso3c = c("FRA", "JPN"), year = 2020L, gdp = c(5, 6))
  expect_silent(out <- add_indicator(base, "kc_clean", "v"))
  expect_identical(names(out), c("iso3c", "year", "gdp", "v"))
  expect_identical(nrow(out), 2L)
})

test_that("re-registering a source drops its memoised answers", {
  # The cache key hashes indicator, countries and years but not `fetch`, so
  # correcting a broken adapter and registering it again kept serving the
  # broken result -- which is exactly what developing an adapter looks like.
  mk <- function(val) function(indicator, countries = NULL, years = NULL) {
    data.frame(iso3c = "FRA", year = 2020L, v = val)
  }
  register_country_source("memo_src", fetch = mk(1))
  on.exit(rm("memo_src", envir = countryatlas:::the_sources), add = TRUE)
  expect_identical(fetch_indicator("memo_src", "v")$v, 1)
  register_country_source("memo_src", fetch = mk(999))
  expect_identical(fetch_indicator("memo_src", "v")$v, 999)

  # Memoisation itself still works: two calls, one fetch.
  calls <- 0L
  register_country_source("memo_count",
                          fetch = function(indicator, countries = NULL,
                                           years = NULL) {
                            calls <<- calls + 1L
                            data.frame(iso3c = "FRA", year = 2020L, v = calls)
                          })
  on.exit(rm("memo_count", envir = countryatlas:::the_sources), add = TRUE)
  invisible(fetch_indicator("memo_count", "v"))
  invisible(fetch_indicator("memo_count", "v"))
  expect_identical(calls, 1L)
  clear_country_cache("memo_count")
  invisible(fetch_indicator("memo_count", "v"))
  expect_identical(calls, 2L)
})

test_that("a bare column in a string-taking verb says what to write", {
  # Nine of these verbs take a bare column through tidy eval; three take
  # strings -- interpolate_missing(value), complete_years(value) and
  # audit_coverage(indicator). Writing the bare column that works everywhere
  # else got base R's "object 'v' not found", which names neither the argument
  # nor the string it wanted.
  pan <- data.frame(iso3c = rep(c("USA", "FRA"), each = 4),
                    year = rep(2017:2020, 2),
                    v = c(1, NA, 3, 4, 5, 6, NA, 8),
                    d = c(2, 2, 2, 2, 4, 4, 4, 4))
  expect_error(interpolate_missing(pan, v), class = "countryatlas_bare_column")
  expect_error(complete_years(pan, value = v),
               class = "countryatlas_bare_column")
  # audit_coverage() takes one row per country, so it gets a cross-section --
  # handing it the panel makes it warn about the span, which is a separate and
  # correct complaint.
  xs <- data.frame(iso3c = c("USA", "FRA"), v = c(1, 2))
  expect_error(audit_coverage(xs, v), class = "countryatlas_bare_column")

  # The message quotes the column back, so the fix is copy-pasteable, and
  # handles a c() of bare columns too.
  msg <- function(e) cli::ansi_strip(conditionMessage(tryCatch(e,
    error = identity)))
  expect_match(msg(interpolate_missing(pan, v)), 'value = "v"', fixed = TRUE)
  expect_match(msg(interpolate_missing(pan, c(v, d))),
               'value = c("v", "d")', fixed = TRUE)
  expect_match(msg(audit_coverage(xs, v)), 'indicator = "v"', fixed = TRUE)

  # Strings, and the NULL default, still work.
  expect_s3_class(interpolate_missing(pan, "v"), "data.frame")
  expect_s3_class(interpolate_missing(pan, c("v", "d")), "data.frame")
  expect_s3_class(interpolate_missing(pan), "data.frame")
  expect_s3_class(complete_years(pan, value = "v"), "data.frame")
  expect_s3_class(audit_coverage(xs, "v"), "countryatlas_coverage")

  # Only a bare symbol is claimed: a genuine error in the argument, and a
  # string naming a column that is not there, must both survive intact.
  expect_error(interpolate_missing(pan, stop("boom")), "boom")
  expect_error(interpolate_missing(pan, "nope"), class = "countryatlas_error")
  expect_error(audit_coverage(xs, "nope"), class = "countryatlas_error")
})

test_that("a brace in borrowed text does not replace the message", {
  # A cli bullet is a template, so text borrowed from somewhere else -- a
  # worker's error, a cache read failure, countrycode's own complaint -- had
  # its braces interpolated. A FUN failing with `bad json {"a": 1}` reported
  # "Could not evaluate cli `{}` expression" and the real failure was gone,
  # which is the worst possible time to lose it.
  # suppressWarnings() around the call, not the assertion: mclapply() emits its
  # own "2 function calls resulted in an error" alongside, which is not what
  # this test is about and would otherwise show up as an uncaught warning.
  err <- tryCatch(
    suppressWarnings(wdj_lapply(1:2, function(i) stop('bad json {"a": 1}'))),
    error = identity)
  expect_match(cli::ansi_strip(conditionMessage(err)), 'bad json {"a": 1}',
               fixed = TRUE)
  expect_false(grepl("Could not evaluate cli",
                     cli::ansi_strip(conditionMessage(err))))

  # Same for the origin error's fallback, used when countrycode's message
  # cannot be parsed for the scheme list.
  e2 <- tryCatch(
    abort_bad_origin("zz", simpleError("weird {brace} message"),
                     rlang::current_env()),
    error = identity)
  expect_match(cli::ansi_strip(conditionMessage(e2)), "weird {brace} message",
               fixed = TRUE)
})

test_that("a cross-section joined to a multi-year fetch keeps its year", {
  # Dropping the fetch's year column is right for a single-year fetch, where
  # it just broadcasts the value. Done unconditionally it turned a two-row
  # cross-section into six rows -- the same `gdp` three times, against values
  # whose year had just been deleted, so nothing said which year any of them
  # was. The keys never collapse here, so the collapse check cannot see it.
  mk <- function(yrs) function(indicator, countries = NULL, years = NULL) {
    data.frame(iso3c = rep(c("USA", "FRA"), each = length(yrs)),
               year = rep(yrs, 2), v = seq_len(2 * length(yrs)))
  }
  register_country_source("fanout_m3", fetch = mk(2018:2020))
  register_country_source("fanout_m1", fetch = mk(2020L))
  on.exit(for (s in c("fanout_m3", "fanout_m1"))
    rm(list = s, envir = countryatlas:::the_sources), add = TRUE)

  xs <- data.frame(iso3c = c("USA", "FRA"), gdp = c(10, 20))
  w <- tryCatch(add_indicator(xs, "fanout_m3", "v"), warning = identity)
  expect_s3_class(w, "countryatlas_year_fanout")
  out <- suppressWarnings(add_indicator(xs, "fanout_m3", "v"))
  expect_true("year" %in% names(out))
  expect_identical(nrow(out), 6L)
  expect_setequal(unique(out$year), 2018:2020)

  # One year still broadcasts silently, dropping the column as before.
  expect_silent(one <- add_indicator(xs, "fanout_m1", "v"))
  expect_false("year" %in% names(one))
  expect_identical(nrow(one), 2L)

  # A panel joins on iso3c and year, untouched either way.
  pnl <- data.frame(iso3c = rep(c("USA", "FRA"), each = 3),
                    year = rep(2018:2020, 2), gdp = 1:6)
  expect_silent(p3 <- add_indicator(pnl, "fanout_m3", "v"))
  expect_identical(nrow(p3), 6L)
  expect_silent(p1 <- add_indicator(pnl, "fanout_m1", "v"))
  expect_identical(nrow(p1), 6L)
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
  expect_true(all(is.na(index_to(absent, v, 2000)$v_index)))
})

test_that("compare_sources drops an unparseable year instead of inventing a row", {
  # read_year() deliberately puts NA in the year column for a time value it
  # could not parse, and d[NA, ] appends a row of all-NA -- a phantom country
  # with no iso3c that then survived the join into the comparison table.
  register_country_source("cs_na_a", fetch = function(indicator,
                                                      countries = NULL,
                                                      years = NULL) {
    data.frame(iso3c = c("USA", "FRA", "JPN"),
               year = c("2020", "2020", "bogus"), cs_na_a = c(10, 20, 30))
  })
  register_country_source("cs_na_b", fetch = function(indicator,
                                                      countries = NULL,
                                                      years = NULL) {
    data.frame(iso3c = c("USA", "FRA"), year = c("2020", "2020"),
               cs_na_b = c(11, 19))
  })
  on.exit(for (s in c("cs_na_a", "cs_na_b"))
    rm(list = s, envir = countryatlas:::the_sources), add = TRUE)

  out <- suppressWarnings(compare_sources(
    c(cs_na_a = "x", cs_na_b = "x"),
    sources = c("cs_na_a", "cs_na_b"), year = 2020))
  expect_identical(sum(is.na(out$iso3c)), 0L)
  expect_setequal(out$iso3c, c("USA", "FRA"))
})

test_that("convert_country names its own from and to on a bad value", {
  # Every scheme other than "country.name" and "iso3c" skips the iso3c hop, so
  # `from` reaches countrycode() directly -- the one call the guard inside
  # wdj_to_iso3c() could not cover -- and was blamed on `origin`, which is not
  # an argument of this function. `to` was not checked at all.
  err <- tryCatch(convert_country("FRA", from = "country", to = "iso2c"),
                  error = identity)
  expect_s3_class(err, "countryatlas_bad_origin")
  expect_match(cli::ansi_strip(conditionMessage(err)), "`from`", fixed = TRUE)

  bad_to <- tryCatch(convert_country("France", to = "nonsense"),
                     error = identity)
  expect_s3_class(bad_to, "countryatlas_bad_destination")
  expect_match(cli::ansi_strip(conditionMessage(bad_to)), "`to`", fixed = TRUE)

  # The suggestion has to work for a destination too.
  msg <- function(e) gsub("[[:space:]]+", " ",
                          cli::ansi_strip(conditionMessage(tryCatch(e,
                            error = identity))))
  expect_match(msg(convert_country("France", to = "contnent")),
               "Did you mean [^?]*continent")
  expect_match(msg(convert_country("France", to = "iso")),
               "Did you mean [^?]*iso3c")

  # Every documented destination, including the package's own shortcuts and
  # the localised names, still resolves.
  for (d in c("iso3c", "iso2c", "iso3n", "country", "name", "continent",
              "region", "region23", "un_region", "flag", "currency", "tld",
              "calling_code", "cown", "name_fr")) {
    expect_false(is.na(suppressWarnings(convert_country("France", to = d))),
                 info = d)
  }
  # And so does every scheme that skips the iso3c hop.
  expect_identical(suppressWarnings(convert_country("FR", from = "iso2c",
                                                    to = "iso3c")), "FRA")
  expect_identical(suppressWarnings(convert_country("FRA", from = "wb",
                                                    to = "iso2c")), "FR")
})

test_that("an optional column argument is validated like a required one", {
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

test_that("interpolate_missing rejects duplicate column names", {
  # complete_years() and audit_coverage() both reject this frame -- vctrs does
  # it for them -- but interpolate_missing() did not, and the dplyr pipeline
  # quietly repaired the names instead: given two columns called `v` it filled
  # the first and handed back the second as `v.1`, a column the caller never
  # created and was never told about.
  d <- data.frame(iso3c = rep("USA", 3), year = 2018:2020,
                  v = c(1, NA, 3), v = c(10, 20, 30), check.names = FALSE)
  expect_error(interpolate_missing(d, "v"), class = "countryatlas_error")
  expect_error(interpolate_missing(d, "v"), "duplicated column name")

  ok <- data.frame(iso3c = rep("USA", 3), year = 2018:2020,
                   v = c(1, NA, 3), w = c(10, 20, 30))
  filled <- interpolate_missing(ok, "v")
  expect_identical(names(filled), c("iso3c", "year", "v", "w", "v_imputed"))
  expect_equal(filled$v, c(1, 2, 3))
})

test_that("n_perm = 0 skips the permutation test on all three statistics", {
  # morans_i() documented "use 0 to skip the test" and all three validate with
  # lo = 0, so the escape hatch is deliberate -- but local_morans() and
  # gearys_c() documented only "permutations for the pseudo-p-value", leaving
  # their users an undocumented column of NA. Pin the behaviour the docs now
  # promise on all three.
  skip_if_no_sf_geometry()
  d <- world_snapshot$countries
  w <- suppressWarnings(country_weights(type = "knn", countries = d$iso3c,
                                        k = 4))

  set.seed(1)
  lm0 <- suppressWarnings(local_morans(d, gdp_per_capita, weights = w,
                                       n_perm = 0))
  expect_true(all(is.na(lm0$p_value)))
  set.seed(1)
  gc0 <- suppressWarnings(gearys_c(d, gdp_per_capita, weights = w, n_perm = 0))
  expect_true(is.na(gc0$p_value))
  set.seed(1)
  mi0 <- suppressWarnings(morans_i(d, gdp_per_capita, weights = w, n_perm = 0))
  expect_true(is.na(mi0$p_value))

  # A real permutation count still produces usable p-values, and the same seed
  # reproduces them.
  set.seed(1)
  a <- suppressWarnings(local_morans(d, gdp_per_capita, weights = w,
                                     n_perm = 99))
  set.seed(1)
  b <- suppressWarnings(local_morans(d, gdp_per_capita, weights = w,
                                     n_perm = 99))
  expect_equal(a, b)
  expect_false(any(is.na(a$p_value)))
})

test_that("recenter says so instead of being dropped on the polygon backend", {
  # The polygon backend hands back lon/lat vertices, and recentring them means
  # re-splitting every ring at the new antimeridian -- which is what
  # sf::st_break_antimeridian() does on the other backend. `recenter` was
  # simply dropped here, so join_world(recenter = 150) returned byte-identical
  # coordinates to recenter = NULL and drew an Atlantic-centred map for someone
  # who had asked for a Pacific-centred one.
  skip_if_no_sf_geometry()
  snap <- world_snapshot$countries

  expect_warning(join_world(snap, recenter = 150),
                 class = "countryatlas_recenter_ignored")
  expect_warning(world_geometry(recenter = 150),
                 class = "countryatlas_recenter_ignored")
  expect_warning(attach_geometry(snap, recenter = 150),
                 class = "countryatlas_recenter_ignored")

  # Nothing was asked for, so nothing is said.
  expect_no_warning(join_world(snap, recenter = 0))
  expect_no_warning(join_world(snap))

  # And the backend that *can* recentre stays quiet and actually moves.
  expect_no_warning(a <- join_world(snap, geometry = "sf", recenter = 150))
  b <- suppressWarnings(join_world(snap, geometry = "sf"))
  expect_false(isTRUE(all.equal(unname(sf::st_bbox(a)["xmin"]),
                                unname(sf::st_bbox(b)["xmin"]))))
})

test_that("aggregate_regions handles an sf frame instead of crashing", {
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

test_that("a verb hands back the class it was given", {
  # per_capita(), share_of_world() and standardize_country() document their
  # result as "`data` with the requested columns added", and rank_countries()
  # honours that -- but these three ended with as_tibble(), which strips the sf
  # class. The geometry column survived, so nothing looked wrong until the next
  # verb reported "`data` has no map geometry".
  skip_if_no_sf_geometry()
  snap <- world_snapshot$countries
  gsf <- suppressWarnings(join_world(snap, geometry = "sf"))
  gsf$pop <- gsf$population

  expect_s3_class(suppressWarnings(per_capita(gsf, population, pop = pop)), "sf")
  expect_s3_class(suppressWarnings(share_of_world(gsf, population)), "sf")
  expect_s3_class(suppressWarnings(standardize_country(gsf, iso3c,
                                                       origin = "iso3c")), "sf")
  expect_s3_class(suppressWarnings(rank_countries(gsf, population)), "sf")

  # The pipelines that used to die.
  expect_s3_class(suppressWarnings(
    world_map(per_capita(gsf, population, pop = pop),
              population_per_capita)), "ggplot")
  expect_s3_class(suppressWarnings(
    world_map(share_of_world(gsf, population), population_share)), "ggplot")

  # sf is the only class carried through: everything else is still normalised
  # to a tibble, and grouping is still dropped -- as_tibble() was doing both
  # jobs at these return points and only the sf part was wrong.
  d <- data.frame(iso3c = c("USA", "FRA"), v = c(1, 2), pop = c(10, 20))
  expect_s3_class(per_capita(d, v, pop = pop), "tbl_df")
  expect_s3_class(share_of_world(d, v), "tbl_df")
  expect_s3_class(standardize_country(data.frame(nm = "France"), nm,
                                      warn = FALSE), "tbl_df")
  grp <- dplyr::group_by(data.frame(iso3c = c("USA", "FRA"), v = c(1, 2),
                                    pop = c(10, 20)), iso3c)
  expect_false(dplyr::is_grouped_df(per_capita(grp, v, pop = pop)))
  # share_of_world() deliberately says it is ignoring the grouping, because the
  # share is of the world total and not the group's -- so assert that rather
  # than let it surface as an uncaught warning.
  expect_warning(out <- share_of_world(grp, v), "grouping is ignored")
  expect_false(dplyr::is_grouped_df(out))
  expect_equal(share_of_world(d, v)$v_share, c(1 / 3, 2 / 3))
  expect_equal(per_capita(d, v, pop = pop)$v_per_capita, c(0.1, 0.1))
})

test_that("a caller column named x0/y0/x1/y1 does not break flow_map", {
  # The arc endpoints are joined in under those names, and a caller who
  # geocoded their own endpoints -- the shape of frame this verb is for -- has
  # them already. dplyr suffixed both sides and the completeness check failed
  # with vctrs' "Can't subset columns that don't exist".
  fl <- data.frame(from = c("United States", "France"),
                   to = c("France", "Japan"), w = c(5, 3))
  for (nm in c("x0", "y0", "x1", "y1")) {
    d <- fl
    d[[nm]] <- 1
    expect_s3_class(suppressWarnings(flow_map(d, from, to, w)), "ggplot")
  }
  a <- suppressWarnings(ggplot2::ggplot_build(flow_map(fl, from, to, w)))
  d2 <- fl
  d2$x0 <- 1
  b <- suppressWarnings(ggplot2::ggplot_build(flow_map(d2, from, to, w)))
  expect_equal(a$data, b$data)

  # A column flow_map actually reads cannot be dropped, so it is refused.
  d3 <- fl
  names(d3)[3] <- "x0"
  expect_error(flow_map(d3, from, to, x0), class = "countryatlas_error")
})

test_that("a caller column named row or col does not break tile_map", {
  # The tile grid supplies `row` and `col`, common enough names that a caller's
  # frame may carry its own. dplyr then suffixed both sides of the join to
  # `.x`/`.y` and aes(.data$col, -.data$row) failed with ggplot2's "Problem
  # while computing aesthetics".
  snap <- world_snapshot$countries
  for (nm in c("row", "col")) {
    d <- snap
    d[[nm]] <- 1
    expect_s3_class(suppressWarnings(tile_map(d, population)), "ggplot")
  }
  # Dropping the caller's copy must not change what is drawn.
  a <- suppressWarnings(ggplot2::ggplot_build(tile_map(snap, population)))
  d2 <- snap
  d2$row <- 1
  b <- suppressWarnings(ggplot2::ggplot_build(tile_map(d2, population)))
  expect_equal(a$data, b$data)

  # A fill column of that name cannot be both the value and a coordinate, so
  # it is refused rather than silently dropped.
  d3 <- snap
  d3$row <- snap$population
  expect_error(tile_map(d3, row), class = "countryatlas_error")
  expect_match(cli::ansi_strip(conditionMessage(tryCatch(tile_map(d3, row),
    error = identity))), "cannot be", fixed = TRUE)
})

test_that("a pre-joined centroid column does not break the cartogram", {
  # country_meta carries centroid_lon/centroid_lat, so joining it for capitals
  # or area before drawing is ordinary. gridded_cartogram() then joined the
  # centroids again without dropping the caller's, dplyr suffixed both sides to
  # `.x`/`.y`, and the filter failed with vctrs' "Can't subset rows with
  # `is.na(df$centroid_lon) | ...`". bubble_map() and spike_map() already
  # guarded the same join.
  skip_if_no_sf_geometry()
  snap <- world_snapshot$countries
  cm <- countryatlas::country_meta[, c("iso3c", "centroid_lon", "centroid_lat")]
  withc <- dplyr::left_join(snap, cm, by = "iso3c")

  expect_s3_class(suppressWarnings(gridded_cartogram(withc, population)),
                  "ggplot")
  expect_s3_class(suppressWarnings(bubble_map(withc, population)), "ggplot")
  expect_s3_class(suppressWarnings(spike_map(withc, population)), "ggplot")

  # Dropping the caller's columns must not change what is drawn.
  a <- suppressWarnings(ggplot2::ggplot_build(gridded_cartogram(snap,
                                                                population)))
  b <- suppressWarnings(ggplot2::ggplot_build(gridded_cartogram(withc,
                                                                population)))
  expect_equal(a$data, b$data)
})

test_that("audit_coverage refuses a bare vector instead of reporting nothing", {
  # as_tibble() turns a vector into a one-column tibble called `value`, which
  # has no iso3c and no indicators -- so a character vector of country codes
  # produced a coverage object whose three tables were all empty, reading as
  # "no missing data" when nothing had been examined.
  expect_error(audit_coverage(c("USA", "FRA")), class = "countryatlas_error")
  expect_match(cli::ansi_strip(conditionMessage(tryCatch(
    audit_coverage(c("USA", "FRA")), error = identity))),
    "must be a data frame", fixed = TRUE)
  # A real frame still works, and so does the shape that legitimately takes a
  # vector.
  expect_s3_class(audit_coverage(data.frame(iso3c = c("USA", "FRA"),
                                            v = c(1, NA))),
                  "countryatlas_coverage")
  expect_s3_class(check_dispute_coverage(c("USA", "FRA")), "tbl_df")
})

test_that("world_table says when the value column emptied the table", {
  # Rows with no value cannot be ranked, so they go -- but if that empties the
  # table the caller gets a 0-row result from a frame that had rows in it, and
  # no way to tell "the column is empty" from "there was nothing to report".
  # gridded_cartogram() aborts on the same shape; a table is recoverable, so
  # this warns and carries on.
  allna <- data.frame(iso3c = c("USA", "FRA", "JPN"), v = rep(NA_real_, 3))
  expect_warning(out <- world_table(allna, v, engine = "tibble"),
                 class = "countryatlas_all_missing")
  expect_identical(nrow(out), 0L)
  expect_match(cli::ansi_strip(conditionMessage(tryCatch(
    world_table(allna, v, engine = "tibble"), warning = identity))),
    "all 3 countries", fixed = TRUE)
  # Singular reads correctly too -- the count and the agreement sit together.
  one <- data.frame(iso3c = "USA", v = NA_real_)
  expect_match(cli::ansi_strip(conditionMessage(tryCatch(
    world_table(one, v, engine = "tibble"), warning = identity))),
    "all 1 country", fixed = TRUE)

  # Everything that is not "data in, nothing out" stays silent: a partial drop
  # is the normal case, and a 0-row frame returns 0 rows as every panel helper
  # does.
  expect_silent(world_table(data.frame(iso3c = c("USA", "FRA", "JPN"),
                                       v = c(1, NA, 3)), v, engine = "tibble"))
  expect_silent(world_table(data.frame(iso3c = c("USA", "FRA"), v = c(1, 2)),
                            v, engine = "tibble"))
  expect_silent(world_table(data.frame(iso3c = character(0), v = numeric(0)),
                            v, engine = "tibble"))
  expect_silent(world_table(data.frame(iso3c = c("USA", "FRA"), v = c(1, 2)),
                            engine = "tibble"))
})

test_that("a data frame is refused where a country vector belongs", {
  # as.character() on a data frame deparses each *column* into a string, so
  # neighbors(my_df) came back with the two "countries" `c("USA", "FRA")` and
  # `c(1, 2)` -- silently, because those are just strings that match nothing
  # and every row then reads as "country not found". Nearly every other verb
  # here takes `data` first, so handing a frame to the ones that take a vector
  # is the natural mistake. gini() and theil() already refused it; these eight
  # did not.
  d <- data.frame(iso3c = c("USA", "FRA"), v = c(1, 2))
  expect_error(neighbors(d), class = "countryatlas_frame_as_vector")
  expect_error(convert_country(d), class = "countryatlas_frame_as_vector")
  expect_error(country_timeline(d), class = "countryatlas_frame_as_vector")
  expect_error(dissolve_country(d), class = "countryatlas_frame_as_vector")
  expect_error(in_group(d, "EU"), class = "countryatlas_frame_as_vector")
  expect_error(distance_between(d, d), class = "countryatlas_frame_as_vector")
  expect_error(check_country_match(d), class = "countryatlas_frame_as_vector")
  expect_error(repair_country_names(d), class = "countryatlas_frame_as_vector")

  # Four of them run as.character() before reaching wdj_to_iso3c(), so the
  # guard has to sit at each coercion point, not only at the shared one.
  expect_match(cli::ansi_strip(conditionMessage(tryCatch(
    check_country_match(d), error = identity))), "not a data frame",
    fixed = TRUE)

  # A data frame is only the common case: as.character() deparses any list
  # element that is not a single value, so list(c("FRA", "DEU")) collapsed to
  # the one string `c("FRA", "DEU")` and convert_country() returned a single NA
  # where two codes were asked for.
  expect_error(convert_country(list(c("FRA", "DEU")), from = "iso3c"),
               class = "countryatlas_frame_as_vector")
  expect_error(neighbors(list(c("FRA", "DEU")), origin = "iso3c"),
               class = "countryatlas_frame_as_vector")
  expect_error(dissolve_country(list(c("USSR", "Yugoslavia"))),
               class = "countryatlas_frame_as_vector")
  expect_error(convert_country(list(NULL), from = "iso3c"),
               class = "countryatlas_frame_as_vector")

  # Shapes that as.character() coerces correctly are left alone: a flat list of
  # scalars, a matrix, and an empty list.
  expect_identical(convert_country(list("FRA", "DEU"), from = "iso3c"),
                   c("FRA", "DEU"))
  expect_identical(convert_country(matrix(c("FRA", "DEU")), from = "iso3c"),
                   c("FRA", "DEU"))
  expect_length(convert_country(list(), from = "iso3c"), 0L)

  # Vectors of every shape still work, including factors and empty ones.
  expect_s3_class(dissolve_country(c("USSR", "Yugoslavia")), "data.frame")
  expect_s3_class(dissolve_country(character(0)), "data.frame")
  expect_s3_class(check_country_match(c("France", "Narnia")), "data.frame")
  expect_type(repair_country_names(c("Frnace", "Japan")), "character")
  expect_type(repair_country_names(factor("Frnace")), "character")
  expect_type(convert_country(factor("France")), "character")
  expect_true(suppressWarnings(in_group("FRA", "EU", origin = "iso3c")))
})
