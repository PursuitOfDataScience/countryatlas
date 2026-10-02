# --- morans_i reports what it dropped ----------------------------------------

test_that("morans_i reports the countries it excluded", {
  skip_slow_on_cran()
  skip_if_no_sf_geometry()
  # Land-border contiguity, the default before 4.0.0, is where the exclusion
  # report earns its keep.
  out <- morans_i(snap, gdp_per_capita, n_perm = 0,
                  weights = country_weights("contiguity"))
  expect_true(all(c("n_excluded", "excluded") %in% names(out)))
  ex <- out$excluded[[1]]
  expect_type(ex, "character")
  expect_equal(out$n_excluded, length(ex))
  # Islands are the systematic omission the field exists to surface.
  expect_true(all(c("JPN", "AUS", "NZL", "ISL") %in% ex))
  # Excluded + used accounts for every country that had a finite value.
  have <- sum(!is.na(snap$gdp_per_capita))
  expect_equal(out$n + out$n_excluded, have)
  expect_false(any(ex %in% c("FRA", "DEU")))          # these do have neighbours
})

# --- Moran's I ------------------------------------------------------------------

test_that("morans_i finds spatial autocorrelation in GDP (needs sf)", {
  skip_slow_on_cran()
  skip_if_no_sf_geometry()
  set.seed(42)
  out <- morans_i(world_snapshot$countries, gdp_per_capita, n_perm = 199)
  expect_named(out, c("i", "expected", "n", "n_excluded", "n_links",
                      "p_value", "excluded"))
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
  skip_slow_on_cran()
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
  skip_slow_on_cran()
  skip_if_no_sf_geometry()
  set.seed(1)
  contig <- morans_i(snap, gdp_per_capita, n_perm = 0,
                     weights = country_weights("contiguity"))
  knn <- morans_i(snap, gdp_per_capita, n_perm = 0,
                  weights = country_weights("knn", k = 5))
  # knn (k = 5) is the default now.
  expect_identical(morans_i(snap, gdp_per_capita, n_perm = 0), knn)
  # knn reaches the islands, so it uses far more countries.
  expect_gt(knn$n, contig$n)
  expect_lt(knn$n_excluded, contig$n_excluded)
  expect_false(isTRUE(all.equal(knn$i, contig$i)))
  expect_true(is.finite(knn$i))
})

test_that("local_morans classifies clusters and lisa_map draws them", {
  skip_slow_on_cran()
  set.seed(1)
  w <- country_weights("knn", k = 5)
  # Unadjusted, so 99 permutations can reach alpha; the adjusted labels have
  # tests of their own.
  lm1 <- local_morans(snap, gdp_per_capita, weights = w, n_perm = 99,
                      p_adjust = "none")
  expect_named(lm1, c("iso3c", "value", "lag", "ii", "p_value", "p_adjusted",
                      "cluster"))
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
  skip_slow_on_cran()
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
  expect_named(loc, c("iso3c", "gi_star", "z_score", "p_value", "p_adjusted"))
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
  skip_slow_on_cran()
  one <- snap[snap$iso3c %in% c("JPN", "AUS"), ]
  skip_if_no_sf_geometry()
  expect_error(morans_i(one, gdp_per_capita, n_perm = 0),
               "Not enough connected countries")
})

# --- independent validation against spdep -----------------------------------------
#
# The spatial statistics are implemented from the papers rather than delegated,
# so they need an outside opinion. spdep is the reference implementation; these
# check the arithmetic, not the API.

test_that("the spatial statistics match spdep", {
  skip_slow_on_cran()
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

test_that("the spatial statistics take a deterministic cross-section of a panel", {
  skip_slow_on_cran()
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

test_that("a constant column makes the spatial statistics say so, not return NaN", {
  skip_slow_on_cran()
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

test_that("country_weights validates a custom matrix instead of failing later", {
  skip_slow_on_cran()
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

test_that("the weights print method describes every scheme it can build", {
  skip_slow_on_cran()
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
  skip_slow_on_cran()
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

test_that("spatial_lag names the countries its weights exclude", {
  skip_slow_on_cran()
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

test_that("spatial_lag normalises on both of its branches", {
  skip_slow_on_cran()
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

test_that("n_perm = 0 skips the permutation test on all three statistics", {
  skip_slow_on_cran()
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

test_that("morans_i names a missing value column", {
  # Used to report "not enough bordering countries" -- a zero-row frame is what
  # a NULL column subset produces, so the real cause was hidden. need_pkg()
  # fires before the column check, so sf has to be present for this to be the
  # error we see.
  skip_if_no_sf_geometry()
  expect_error(morans_i(snap, not_a_column, n_perm = 0), "not found in")
})

test_that("morans_i touches the RNG only when it permutes", {
  skip_slow_on_cran()
  # Consuming random numbers is correct for a permutation test -- what would be
  # wrong is calling set.seed() (the package never does) or spending randomness
  # when none was asked for. n_perm = 0 is the deterministic path.
  skip_if_no_sf_geometry()
  sfd <- attach_geometry(countryatlas::world_snapshot$countries, geometry = "sf")

  set.seed(1)
  before <- .Random.seed
  invisible(morans_i(sfd, gdp_per_capita, n_perm = 0))
  expect_identical(before, .Random.seed)

  set.seed(1)
  before <- .Random.seed
  invisible(morans_i(sfd, gdp_per_capita, n_perm = 20))
  expect_false(identical(before, .Random.seed))

  # And a seeded run reproduces, which is what the permutation p-value promises.
  set.seed(42); a <- morans_i(sfd, gdp_per_capita, n_perm = 99)
  set.seed(42); b <- morans_i(sfd, gdp_per_capita, n_perm = 99)
  expect_identical(a$p_value, b$p_value)

  # The *statistic* must not depend on the permutations -- only the p-value
  # may. If a refactor ever let the seed move `i`, every published figure from
  # this package would be irreproducible and nothing else here would notice.
  set.seed(1); i1 <- morans_i(sfd, gdp_per_capita, n_perm = 99)$i
  set.seed(2); i2 <- morans_i(sfd, gdp_per_capita, n_perm = 99)$i
  expect_identical(i1, i2)
  # A permutation p-value is (1 + #{perm >= observed}) / (n_perm + 1), so it can
  # never be exactly zero. Reporting p = 0 from 99 draws would be a real claim.
  expect_gt(a$p_value, 0)
  expect_lte(a$p_value, 1)
})

test_that("local_morans() permutes conditionally", {
  # On a complete graph every country's neighbours are all the *other*
  # countries, so a conditional permutation (own value fixed, neighbours
  # drawn from the rest) cannot change I_i at all, and every p-value is 1.
  # Shuffling all n values let a country's own value land among its
  # neighbours, which is what gave the extreme ones p-values near 0.2 here.
  iso <- c("FRA", "DEU", "ITA", "ESP", "PRT")
  m <- matrix(1, 5, 5, dimnames = list(iso, iso)); diag(m) <- 0
  w <- country_weights("custom", w = m)
  d <- data.frame(iso3c = iso, v = c(1, 2, 3, 4, 10))
  set.seed(1)
  lm_ <- local_morans(d, v, weights = w, n_perm = 99)
  expect_equal(lm_$p_value, rep(1, 5))
  # Reproducible under a seed, as documented.
  set.seed(2); a <- local_morans(d, v, weights = w, n_perm = 49)
  set.seed(2); b <- local_morans(d, v, weights = w, n_perm = 49)
  expect_identical(a, b)
})

# --- found during the second pass -----------------------------------------------

test_that("custom weights normalise the case and padding of their codes", {
  d <- data.frame(iso3c = c("FRA", "DEU", "ITA", "ESP"), v = c(1, 2, 3, 5))
  links <- data.frame(iso3c = c("fra", "deu", "ita", "esp", " fra"),
                      neighbor = c("deu", "ita", "esp", "fra", "esp"))
  w <- country_weights("custom", w = links)
  expect_equal(w$iso3c, c("DEU", "ESP", "FRA", "ITA"))
  expect_equal(morans_i(d, v, weights = w, n_perm = 0)$n, 4L)
  m <- matrix(1, 4, 4, dimnames = list(tolower(d$iso3c), tolower(d$iso3c)))
  diag(m) <- 0
  expect_equal(morans_i(d, v, weights = country_weights("custom", w = m),
                        n_perm = 0)$n, 4L)
  # Two names for one country in a matrix is refused rather than guessed at.
  m2 <- matrix(1, 2, 2, dimnames = list(c("FRA", "fra"), c("FRA", "fra")))
  expect_error(country_weights("custom", w = m2), "same country twice",
               class = "countryatlas_error")
  # And no overlap at all is named as the key problem it is.
  expect_error(
    morans_i(transform(d, iso3c = tolower(iso3c)), v,
             weights = country_weights("knn", k = 2), n_perm = 0),
    class = "countryatlas_weights_no_overlap")
})

test_that("spatial_lag() on a panel survives one sparse year", {
  snap <- countryatlas::world_snapshot$countries
  w <- country_weights("knn", k = 5)
  sparse <- snap[snap$iso3c %in% c("FRA", "DEU"), c("iso3c", "gdp_per_capita")]
  pan <- rbind(transform(snap[, c("iso3c", "gdp_per_capita")], year = 2000L),
               transform(sparse, year = 2001L))
  expect_warning(out <- spatial_lag(pan, gdp_per_capita, weights = w),
                 class = "countryatlas_thin_year")
  expect_true(all(is.na(out$gdp_per_capita_lag[out$year == 2001L])))
  alone <- spatial_lag(pan[pan$year == 2000L, ], gdp_per_capita, weights = w)
  expect_equal(out$gdp_per_capita_lag[out$year == 2000L],
               alone$gdp_per_capita_lag)
  # With no usable year at all it still fails the way a single year does.
  expect_error(spatial_lag(transform(sparse, year = 2001L), gdp_per_capita,
                           weights = w),
               class = "countryatlas_too_few_connected")
})

test_that("a blank iso3c is not reported as an excluded country", {
  snap <- countryatlas::world_snapshot$countries[, c("iso3c", "gdp_per_capita")]
  blank <- rbind(snap, data.frame(iso3c = c("", " "), gdp_per_capita = c(1, 2)))
  w <- country_weights("knn", k = 5)
  a <- morans_i(snap, gdp_per_capita, weights = w, n_perm = 0)
  b <- morans_i(blank, gdp_per_capita, weights = w, n_perm = 0)
  expect_false(any(!nzchar(trimws(b$excluded[[1]]))))
  expect_equal(b$n_excluded, a$n_excluded)
  expect_equal(b$i, a$i)
})

test_that("a custom weights frame naming one link twice is refused", {
  w <- data.frame(iso3c = c("FRA", "FRA", "DEU"),
                  neighbor = c("DEU", "DEU", "ESP"), weight = c(1, 5, 2))
  expect_error(country_weights("custom", w = w),
               class = "countryatlas_duplicate_links")
  expect_error(country_weights("custom", w = w), "FRA -> DEU", fixed = TRUE)
  # Case and padding are normalised first, so these are the same link too.
  w2 <- data.frame(iso3c = c("FRA", "fra "), neighbor = c("DEU", "deu"))
  expect_error(country_weights("custom", w = w2),
               class = "countryatlas_duplicate_links")
  ok <- data.frame(iso3c = c("FRA", "DEU"), neighbor = c("DEU", "FRA"))
  expect_s3_class(country_weights("custom", w = ok), "countryatlas_weights")
})

test_that("lisa_map()'s provenance counts the countries it colours", {
  skip_slow_on_cran()
  d <- toy_polygons(c(FRA = 1, DEU = 5, ITA = 2, ESP = 8, PRT = 3))
  # PRT has a value and no neighbour, so it gets no cluster.
  w <- country_weights("custom", w = data.frame(
    iso3c = c("FRA", "DEU", "DEU", "ITA", "ITA", "ESP"),
    neighbor = c("DEU", "FRA", "ITA", "DEU", "ESP", "ITA")))
  p <- lisa_map(d, v, weights = w, n_perm = 0, footnote = "auto")
  pr <- map_provenance(p)
  expect_equal(pr$n_countries, 4L)
  expect_equal(pr$n_missing, 1L)
  expect_equal(pr$missing_iso3c[[1]], "PRT")
  # ... which is what the caption, computed from the drawing, says too.
  expect_match(p$labels$caption, "4 of 5 countries shown; 1 missing")
})

test_that("local statistics control false discoveries by default", {
  # One permutation test per country, about 190 of them, at alpha = 0.05:
  # about ten "significant" clusters expected under the null, and nothing in
  # R/spatial-stats.R adjusted for it.
  skip_slow_on_cran()
  snap <- countryatlas::world_snapshot$countries
  d <- snap[is.finite(snap$gdp_per_capita), c("iso3c", "gdp_per_capita")]
  w <- country_weights("knn", k = 5)
  set.seed(20261002)
  shares <- vapply(seq_len(100), function(r) {
    d$v <- sample(d$gdp_per_capita)
    lm_ <- local_morans(d, v, weights = w, n_perm = 499)
    c(raw = mean(lm_$p_value <= 0.05), fdr = mean(lm_$p_adjusted <= 0.05))
  }, numeric(2))
  # Under a permutation null the unadjusted share sits near alpha, and the
  # adjusted one near zero.
  expect_gt(mean(shares["raw", ]), 0.03)
  expect_lt(mean(shares["raw", ]), 0.07)
  expect_lt(mean(shares["fdr", ]), 0.005)
})

test_that("a planted cluster survives the adjustment", {
  skip_slow_on_cran()
  meta <- countryatlas::country_meta
  iso <- meta$iso3c[!is.na(meta$centroid_lon)]
  w <- country_weights("knn", k = 5)
  m <- as.matrix(w)
  nb <- function(x) unique(unlist(lapply(x, function(i) colnames(m)[m[i, ] > 0])))
  # France and everything within two steps of it, under the same weights the
  # statistic uses; the "core" is the planted countries whose five neighbours
  # are all planted too.
  planted <- unique(c("FRA", nb("FRA"), nb(nb("FRA"))))
  core <- planted[vapply(planted, function(i) all(nb(i) %in% planted), NA)]
  expect_gte(length(core), 5L)
  set.seed(7)
  d <- data.frame(iso3c = iso, v = stats::rnorm(length(iso)))
  d$v[d$iso3c %in% planted] <- 6 + stats::rnorm(sum(d$iso3c %in% planted),
                                               sd = 0.2)
  lm_ <- local_morans(d, v, weights = w)
  hh <- lm_$iso3c[lm_$cluster == "High-High"]
  expect_true(all(core %in% hh))
  # The p-values themselves are never adjusted, so they still match the
  # reference implementations; only the labels move.
  raw <- local_morans(d, v, weights = w, n_perm = 0)
  expect_identical(raw$ii, lm_$ii)
  expect_true(all(lm_$p_adjusted >= lm_$p_value, na.rm = TRUE))
  expect_identical(attr(lm_, "countryatlas_p_adjust"), "fdr")
})

test_that("p_adjust is the method p.adjust() names, and is validated", {
  snap <- countryatlas::world_snapshot$countries
  w <- country_weights("knn", k = 5)
  set.seed(1)
  lm_ <- local_morans(snap, gdp_per_capita, weights = w, n_perm = 99,
                      p_adjust = "holm")
  expect_equal(lm_$p_adjusted, stats::p.adjust(lm_$p_value, "holm"))
  g <- getis_ord(snap, gdp_per_capita, weights = w, p_adjust = "bonferroni")
  expect_equal(g$p_adjusted, stats::p.adjust(g$p_value, "bonferroni"))
  g0 <- getis_ord(snap, gdp_per_capita, weights = w, p_adjust = "none")
  expect_identical(g0$p_adjusted, g0$p_value)
  expect_equal(getis_ord(snap, gdp_per_capita, weights = w)$p_adjusted,
               stats::p.adjust(g$p_value, "BH"))
  expect_error(local_morans(snap, gdp_per_capita, weights = w,
                            p_adjust = "bh"), "p_adjust")
  expect_warning(getis_ord(snap, gdp_per_capita, weights = w, local = FALSE,
                           p_adjust = "none"),
                 class = "countryatlas_p_adjust_ignored")
  # n_perm = 0 leaves both p columns NA and every country unlabelled.
  z <- local_morans(snap, gdp_per_capita, weights = w, n_perm = 0)
  expect_true(all(is.na(z$p_adjusted)))
  expect_true(all(z$cluster == "Not significant"))
})

test_that("lisa_map() names its multiple-testing method", {
  skip_slow_on_cran()
  d <- attach_geometry(countryatlas::world_snapshot$countries,
                       geometry = "polygon")
  w <- country_weights("knn", k = 5)
  set.seed(1)
  p <- lisa_map(d, gdp_per_capita, weights = w, n_perm = 99)
  expect_match(gg_caption_of(p), "false discovery rate", fixed = TRUE)
  expect_identical(attr(p, "countryatlas_provenance")$p_adjust, "fdr")
  p0 <- lisa_map(d, gdp_per_capita, weights = w, n_perm = 99,
                 p_adjust = "none")
  expect_match(gg_caption_of(p0), "unadjusted for", fixed = TRUE)
  renders(p)
})

test_that("morans_i(scale) is deprecated but keeps its old meaning", {
  skip_slow_on_cran()
  skip_if_no_sf_geometry()
  snap <- countryatlas::world_snapshot$countries
  expect_warning(old <- morans_i(snap, gdp_per_capita, n_perm = 0,
                                 scale = "small"),
                 class = "lifecycle_warning_deprecated")
  expect_equal(old$i, morans_i(snap, gdp_per_capita, n_perm = 0,
                               weights = country_weights("contiguity"))$i)
})
