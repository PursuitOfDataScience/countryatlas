# Regression tests for the 3.0.0 pre-release review. Each block pins a defect
# that shipped silently (a wrong number, a wrong count, a crash at print time
# or a deleted file) and states the contract the fix restores.

# A tiny polygon-backend frame: one unit square per country, far enough apart
# not to touch. world_map() and friends only need long/lat/group, so this
# exercises the drawing and counting paths without the `maps` package.
toy_polygons <- function(values) {
  iso <- names(values)
  do.call(rbind, lapply(seq_along(iso), function(i) {
    data.frame(long = c(0, 1, 1, 0) + 3 * i, lat = c(0, 0, 1, 1),
               group = i, order = 1:4, iso3c = iso[i], v = values[[i]],
               stringsAsFactors = FALSE)
  }))
}

# --- analysis.R ---------------------------------------------------------------

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

test_that("interpolate_missing() neither crashes on nor overwrites an undated row", {
  d <- data.frame(iso3c = "A", year = c(2000, NA, 2002, 2003),
                  v = c(1, 5, NA, 4))
  out <- interpolate_missing(d, "v")
  # The undated observation survives (the filler used to write NA over it)
  # and is no anchor: 2002 sits between 2000 and 2003.
  expect_equal(out$v[is.na(out$year)], 5)
  expect_equal(out$v[out$year %in% 2002], 3)
  expect_false(out$v_imputed[is.na(out$year)])
  # And an undated missing value is not carried into.
  d2 <- data.frame(iso3c = "A", year = c(2000, 2001, NA), v = c(1, 2, NA))
  out2 <- interpolate_missing(d2, "v", method = "locf")
  expect_true(is.na(out2$v[is.na(out2$year)]))
  expect_false(out2$v_imputed[is.na(out2$year)])
})

test_that("per_capita() names an infinite population as one", {
  d <- data.frame(iso3c = c("USA", "CHN"), v = c(1, 2), p = c(Inf, 10))
  expect_warning(per_capita(d, v, p), "infinite",
                 class = "countryatlas_unusable_rows")
})

# --- rates.R ------------------------------------------------------------------

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
  set.seed(1)
  panel <- expand.grid(year = 2000:2024,
                       iso3c = c(paste0("A", 1:5), paste0("B", 1:5)),
                       stringsAsFactors = FALSE)[, c("iso3c", "year")]
  panel$y <- ifelse(startsWith(panel$iso3c, "A"), 100, 30) +
    stats::rnorm(nrow(panel), 0, 2)
  base <- convergence_club(panel, y)
  shuffled <- convergence_club(panel[sample(nrow(panel)), ], y)
  expect_equal(as.data.frame(shuffled), as.data.frame(base))
  # The first country lacking the first year used to put that year last.
  p2 <- panel[!(panel$iso3c == "A1" & panel$year == 2000), ]
  p3 <- rbind(p2[p2$iso3c != "A1", ], p2[p2$iso3c == "A1", ])
  expect_equal(as.data.frame(convergence_club(p2, y)),
               as.data.frame(convergence_club(p3, y)))
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

test_that("share_of_world() gives an undated row no share", {
  s <- data.frame(iso3c = c("A", "B", "C", "D"), year = c(2000, 2000, NA, NA),
                  v = c(1, 3, 5, 5))
  expect_silent(out <- share_of_world(s, v))
  expect_equal(out$v_share, c(0.25, 0.75, NA, NA))
})

test_that("world_table() gives tied values the same rank", {
  d <- data.frame(iso3c = c("A", "B", "C", "D"), v = c(5, 7, 7, 1))
  t1 <- world_table(d, v, engine = "tibble")
  expect_equal(t1$rank, c(1L, 1L, 3L, 4L))
  t2 <- world_table(d, v, desc = FALSE, engine = "tibble")
  expect_equal(t2$rank, c(1L, 2L, 3L, 3L))
})

test_that("gridded_cartogram() words the unusable-value warning for its count", {
  g <- countryatlas::world_snapshot$countries
  g$population[g$iso3c == "CHN"] <- Inf
  msgs <- character(0)
  withCallingHandlers(gridded_cartogram(g, population, cells = 50),
                      warning = function(w) {
                        msgs <<- c(msgs, conditionMessage(w))
                        invokeRestart("muffleWarning")
                      })
  msgs <- gsub("\\s+", " ", msgs)
  expect_true(any(grepl("1 country has no finite, positive population and gets",
                        msgs)))
})

# --- time.R / historical.R ----------------------------------------------------

test_that("pre-ISO historical entities are not reported as unmatched", {
  expect_silent(tl <- country_timeline(c("Tanganyika", "United Arab Republic",
                                         "Zanzibar")))
  expect_equal(tl$dissolved, c(1964L, 1961L, 1964L))
  w <- tryCatch(country_timeline(c("Tanganyika", "Freedonia", NA)),
                warning = function(w) conditionMessage(w))
  w <- gsub("\\s+", " ", w)
  expect_match(w, "1 name matched neither")
  expect_match(w, "Freedonia")
  expect_no_match(w, "Tanganyika")
  # A missing input is not a name that failed to match.
  expect_silent(dissolve_country(c("France", NA)))
})

test_that("audit_time_coverage() has no phantom row for an unreadable year", {
  p <- data.frame(iso3c = c("SUN", "SUN", "FRA"),
                  year = c("1995", "junk", "2000"))
  out <- suppressWarnings(audit_time_coverage(p, quiet = TRUE))
  expect_equal(nrow(out), 1L)
  expect_false(anyNA(out$iso3c))
  # And the dissolved code is named, which countrycode cannot do.
  expect_equal(out$country, "Soviet Union")
})

test_that("historical_geometry() refuses a year it cannot place", {
  skip_if_not_installed("cshapes")
  skip_if_not_installed("sf")
  expect_error(historical_geometry(Inf), class = "countryatlas_error")
  expect_error(historical_geometry(1e10), "1886-2019",
               class = "countryatlas_error")
})

# --- spatial-stats.R ----------------------------------------------------------

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

# --- geometry.R ---------------------------------------------------------------

test_that("a numeric region must be a well-formed bounding box", {
  rr <- countryatlas:::resolve_region
  # These were taken as unknown three-letter codes and drew an empty map.
  expect_error(rr(250), "four numbers", class = "countryatlas_error")
  expect_error(rr(c(100, 200, 300)), "four numbers",
               class = "countryatlas_error")
  expect_error(rr(c(10, 60, -10, 30)), "xmin < xmax",
               class = "countryatlas_error")
  expect_error(rr(c(-Inf, 30, 10, 60)), class = "countryatlas_error")
  expect_s3_class(rr(c(-10, 35, 30, 70)), "wdj_bbox")
})

test_that("locate_country() answers zero points with zero rows, silently", {
  skip_if_no_sf_geometry()
  expect_silent(out <- locate_country(numeric(0), numeric(0)))
  expect_equal(nrow(out), 0L)
  expect_named(out, c("iso3c", "country"))
})

# --- join.R -------------------------------------------------------------------

test_that("joining on an existing iso3c column is silent", {
  a <- data.frame(iso3c = c("FRA", "DEU"), gdp = 1:2)
  b <- data.frame(iso3c = c("fra ", "DEU"), pop = 3:4)
  expect_silent(j <- country_join(a, b, iso3c, iso3c, origin_x = "iso3c",
                                  origin_y = "iso3c"))
  expect_equal(j$pop, 3:4)
  expect_silent(country_join_all(list(a, b), by = "iso3c", origin = "iso3c"))
  # A *different* key column is still reported before it is replaced.
  a2 <- data.frame(country = c("France", "Germany"), iso3c = c("x", "y"))
  expect_warning(country_join(a2, b, country, iso3c, origin_y = "iso3c"),
                 class = "countryatlas_key_overwritten")
})

test_that("country_join_all(by = ) names an unquoted column", {
  a <- data.frame(iso3c = "FRA", gdp = 1)
  expect_error(country_join_all(list(a, a), by = iso3c, origin = "iso3c"),
               class = "countryatlas_bare_column")
  expect_error(country_join_all(list(a, a), by = 1),
               class = "countryatlas_error")
})

# --- visualization.R: counting what is drawn -----------------------------------

test_that("an infinite fill is counted as missing, and said to be", {
  d <- toy_polygons(c(FRA = Inf, DEU = 2, ITA = 3, ESP = NA))
  expect_warning(p <- world_map(d, v, footnote = "auto"),
                 class = "countryatlas_infinite_fill")
  prov <- map_provenance(p)
  expect_equal(prov$n_countries, 2L)
  expect_equal(prov$n_missing, 2L)
  expect_setequal(prov$missing_iso3c[[1]], c("ESP", "FRA"))
  # "omit" and "hatched" treat it as the no-data it is drawn as.
  p2 <- suppressWarnings(world_map(d, v, na_style = "omit"))
  expect_false("FRA" %in% countryatlas:::gg_plot_data(p2)$iso3c)
  # coverage_map() paints it the way its own caption counts it.
  cm <- suppressWarnings(coverage_map(d, v))
  cd <- countryatlas:::gg_plot_data(cm)
  avail <- unique(as.character(cd$.wdj_available[cd$iso3c == "FRA"]))
  expect_equal(avail, "Missing")
  expect_equal(map_provenance(cm)$n_missing, 2L)
})

test_that("bubble and spike maps refuse sizes they cannot draw", {
  skip_if_not_installed("maps")
  snap <- countryatlas::world_snapshot$countries[, c("iso3c", "population")]
  snap$population[snap$iso3c == "FRA"] <- -1.4e9
  snap$population[snap$iso3c == "DEU"] <- Inf
  snap$population[snap$iso3c == "ITA"] <- NA
  quiet_centroids <- function(expr) withCallingHandlers(
    expr, countryatlas_no_centroid = function(w) invokeRestart("muffleWarning"))
  expect_warning(p <- quiet_centroids(bubble_map(snap, population)),
                 class = "countryatlas_unusable_size")
  # No "Removed 1 row containing missing values" at build time for ITA.
  expect_no_warning(ggplot2::ggplot_build(p))
  prov <- map_provenance(p)
  expect_true(all(c("FRA", "DEU", "ITA") %in% prov$missing_iso3c[[1]]))
  # What is drawn is what is counted as shown: one point per country.
  expect_equal(nrow(ggplot2::layer_data(p, 2)), prov$n_countries)
  # spike_map() said these had "no bundled centroid".
  msgs <- character(0)
  withCallingHandlers(spike_map(snap, population),
                      warning = function(w) {
                        msgs <<- c(msgs, conditionMessage(w))
                        invokeRestart("muffleWarning")
                      })
  centroid_msg <- grep("no bundled centroid", msgs, value = TRUE)
  expect_length(centroid_msg, 1L)
  expect_no_match(centroid_msg, "FRA|DEU")
  expect_true(any(grepl("negative or infinite", msgs)))
})

test_that("flow_map() drops unusable weights before they reach the scales", {
  skip_if_not_installed("maps")
  od <- data.frame(from = c("China", "Germany", "United States", "Japan"),
                   to = c("United States", "France", "Mexico", "Brazil"),
                   value = c(500, NA, 300, Inf))
  expect_warning(p <- flow_map(od, from, to, value),
                 "2 flows dropped: the weight is missing or infinite")
  # Printing used to fail with grid's "'lwd' must be non-negative and finite".
  expect_no_warning(print(p))
})

test_that("value_by_alpha_map() refuses a non-numeric value", {
  d <- toy_polygons(c(FRA = 1, DEU = 2, ITA = 3))
  d$pop <- c(10, 20, 30)[d$group]
  d$label <- d$iso3c
  expect_error(value_by_alpha_map(d, label, pop), "needs a numeric",
               class = "countryatlas_error")
})

test_that("classify_compare() tolerates a repeated method", {
  d <- toy_polygons(c(FRA = 1, DEU = 2, ITA = 3, ESP = 4, PRT = 5, BEL = 6))
  p <- classify_compare(d, v, methods = c("quantile", "quantile", "equal"),
                        n = 2)
  expect_equal(levels(countryatlas:::gg_plot_data(p)$.wdj_method),
               c("quantile", "equal"))
})

# --- sources.R ----------------------------------------------------------------

test_that("compare_sources() leaves unresolved keys out of the comparison", {
  register_country_source("rev_a", function(indicator, countries, years, ...) {
    data.frame(iso3c = c("USA", "FRA", "XXA", "XXB"), year = 2020L,
               v = c(1, 2, 3, 4))
  }, cache = FALSE)
  register_country_source("rev_b", function(indicator, countries, years, ...) {
    data.frame(iso3c = c("USA", "FRA", "XXC"), year = 2020L, v = c(1, 2.5, 9))
  }, cache = FALSE)
  withr::defer(remove_country_source(c("rev_a", "rev_b")))
  msgs <- character(0)
  r <- withCallingHandlers(
    compare_sources("v", sources = c("rev_a", "rev_b"), year = 2020),
    warning = function(w) {
      msgs <<- c(msgs, conditionMessage(w))
      invokeRestart("muffleWarning")
    })
  expect_false(anyNA(r$iso3c))
  expect_setequal(r$iso3c, c("USA", "FRA"))
  s <- attr(r, "countryatlas_source_summary")
  expect_equal(c(s$only_x, s$only_y), c(0L, 0L))
  # Two unresolved rows are not "a duplicate country".
  expect_false(any(grepl("duplicate", msgs)))
})

# --- cache.R ------------------------------------------------------------------

test_that("the disk cache never deletes a file it did not write", {
  d <- file.path(tempdir(), paste0("ca-shared-", as.integer(stats::runif(1, 1, 1e6))))
  dir.create(d)
  withr::defer(unlink(d, recursive = TRUE))
  writeLines("mine", file.path(d, "notes.txt"))
  saveRDS(1:3, file.path(d, "analysis.rds"))
  dir.create(file.path(d, "sub"))
  writeLines("x", file.path(d, "sub", "keep.csv"))
  # Entries written by earlier versions, which are pruned.
  writeLines("old", file.path(d, "0123456789abcdef0123456789abcdef"))
  saveRDS(1, file.path(d, "fedcba9876543210fedcba9876543210.rds"))
  withr::local_options(countryatlas.cache_dir = d)
  orig <- countryatlas:::fetch_one_indicator
  stub <- function(code, name, start, end, language = "en") {
    x <- tibble::tibble(iso2c = "US", iso3c = "USA", country = "US",
                        year = 2000L)
    x[[name]] <- 1
    x
  }
  assignInNamespace("fetch_one_indicator", stub, "countryatlas")
  withr::defer(assignInNamespace("fetch_one_indicator", orig, "countryatlas"))
  withr::defer(clear_wdi_cache())
  clear_wdi_cache()
  invisible(countryatlas:::fetch_wdi(c(x = "I1"), 2000, 2000, parallel = FALSE))
  mine <- c("analysis.rds", "notes.txt", file.path("sub", "keep.csv"))
  left <- list.files(d, recursive = TRUE)
  expect_true(all(mine %in% left))
  expect_false(any(grepl("^[0-9a-f]{32}(\\.rds)?$", left)))
  expect_true(any(grepl("\\.countryatlas$", left)))
  clear_wdi_cache(disk = TRUE)
  # The cache's own entries go; the caller's files, and so the folder, stay.
  expect_setequal(list.files(d, recursive = TRUE), mine)
})

# --- reference data -----------------------------------------------------------

test_that("the United Kingdom is an EU member through 31 January 2020", {
  # `to` is the first day of non-membership, as for every EFTA departure.
  expect_true(in_group("United Kingdom", "EU", as_of = "2020-01-31"))
  expect_false(in_group("United Kingdom", "EU", as_of = "2020-02-01"))
  expect_true(in_group("Austria", "EFTA", as_of = "1994-12-31"))
  expect_false(in_group("Austria", "EFTA", as_of = "1995-01-01"))
  expect_true(in_group("Austria", "EU", as_of = "1995-01-01"))
})

# --- projections.R ------------------------------------------------------------

test_that("projection_distortion() measures against the datum it projects", {
  skip_if_not_installed("sf")
  ee <- projection_distortion("equal_earth", "areal", spacing = 15)
  expect_equal(range(ee$distortion), c(1, 1), tolerance = 1e-5)
  laea <- projection_distortion("north_polar", "areal", spacing = 15)
  expect_equal(range(laea$distortion), c(1, 1), tolerance = 1e-5)
  merc <- projection_distortion("mercator", "angular", spacing = 15)
  expect_lt(max(merc$distortion), 1e-3)
})

# --- subnational.R ------------------------------------------------------------

test_that("subnational_map()'s projection notice reads as text", {
  skip_if_not_installed("sf")
  sq <- function(x0, y0) sf::st_polygon(list(rbind(
    c(x0, y0), c(x0 + 1, y0), c(x0 + 1, y0 + 1), c(x0, y0 + 1), c(x0, y0))))
  fake <- function(level = 2, year = 2021, countries = NULL,
                   resolution = "60", projection = NULL) {
    sf::st_sf(nuts_id = c("DE21", "DE22"), iso3c = "DEU", name = c("A", "B"),
              level = 2L, geometry = sf::st_sfc(sq(10, 48), sq(11, 48),
                                                crs = 4326))
  }
  local_mocked_bindings(nuts_geometry = fake, .package = "countryatlas")
  d <- data.frame(nuts_id = c("DE21", "DE22"), value = c(1, 2))
  w <- tryCatch(subnational_map(d, value, projection = "mollweide"),
                countryatlas_projection_ignored = function(w) conditionMessage(w))
  expect_no_match(w, "{.fn", fixed = TRUE)
  expect_no_match(w, 'geometry = "sf"', fixed = TRUE)
  expect_silent(subnational_map(d, value, projection = "equal_earth"))
})

# --- diagnostics.R ------------------------------------------------------------

test_that("audit_coverage() lists a blank code as unmatched", {
  d <- data.frame(iso3c = c("FRA", "", NA),
                  country = c("France", "Nowhere", "Elsewhere"), v = 1:3)
  a <- audit_coverage(d)
  expect_setequal(a$unmatched$country, c("Nowhere", "Elsewhere"))
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

test_that("od_map() draws a repeated origin once", {
  skip_if_not_installed("maps")
  od <- data.frame(from = rep(c("China", "Germany"), each = 2),
                   to = c("United States", "Japan", "France", "Italy"),
                   value = c(5, 2, 3, 1))
  p <- od_map(od, from, to, value, origins = c("China", "China"))
  expect_equal(levels(countryatlas:::gg_plot_data(p)$.wdj_panel), "China")
})

test_that("check_dispute_coverage() reports each bad code once, and not NA", {
  msgs <- character(0)
  withCallingHandlers(
    check_dispute_coverage(c("ESH", NA, "xx", "xx"), quiet = TRUE),
    warning = function(w) {
      msgs <<- c(msgs, gsub("\\s+", " ", conditionMessage(w)))
      invokeRestart("muffleWarning")
    })
  expect_length(msgs, 1L)
  expect_match(msgs, "1 value in `data` is not")
  expect_no_match(msgs, "NA")
})

test_that("a character year is refused before a year-keyed join", {
  fake <- function(indicator, start, end, cache = TRUE, language = "en",
                   parallel = TRUE) {
    x <- tibble::tibble(iso2c = c("US", "CN"), iso3c = c("USA", "CHN"),
                        country = c("US", "CN"), year = 2020L)
    x[[names(indicator)]] <- c(331e6, 1402e6)
    x
  }
  local_mocked_bindings(fetch_wdi = fake, .package = "countryatlas")
  d <- data.frame(iso3c = c("USA", "CHN"), year = c("2020", "2020"),
                  co2 = c(5e6, 1e7))
  # The join's own error was dplyr's "Can't join `x$year` with `y$year`".
  expect_error(per_capita(d, co2), "must be numeric",
               class = "countryatlas_error")
  expect_error(to_ppp(d, co2), "must be numeric", class = "countryatlas_error")
  # A factor of the caller's own needs no join and still takes such a year.
  d$ppp <- c(1, 4)
  expect_equal(to_ppp(d, co2, factor = ppp)$co2_ppp, c(5e6, 2.5e6))
  register_country_source("rev_year", function(indicator, countries, years, ...) {
    data.frame(iso3c = c("USA", "CHN"), year = 2020L, zz = c(1, 2))
  }, cache = FALSE)
  withr::defer(remove_country_source("rev_year"))
  expect_error(add_indicator(d, "rev_year", "zz"), "must be numeric",
               class = "countryatlas_error")
  d$year <- 2020L
  expect_equal(add_indicator(d, "rev_year", "zz")$zz, c(1, 2))
})

test_that("every fill-drawing verb says when an infinity is drawn as no data", {
  d <- toy_polygons(c(FRA = Inf, DEU = 2, ITA = 3))
  d$pop <- c(10, 20, 30)[d$group]
  expect_warning(value_by_alpha_map(d, v, pop),
                 class = "countryatlas_infinite_fill")
  tiles <- data.frame(iso3c = c("FRA", "DEU", "ITA"), v = c(Inf, 2, 3))
  expect_warning(tile_map(tiles, v), class = "countryatlas_infinite_fill")
  skip_if_not_installed("sf")
  skip_if_not_installed("leaflet")
  skip_if_no_sf_geometry()
  ms <- suppressWarnings(attach_geometry(countryatlas::world_snapshot$countries,
                                         geometry = "sf"))
  ms$gdp_per_capita[ms$iso3c == "FRA"] <- Inf
  # leaflet's own colorNumeric() refused the column outright.
  expect_warning(w <- interactive_map(ms, gdp_per_capita, engine = "leaflet"),
                 class = "countryatlas_infinite_fill")
  expect_s3_class(w, "leaflet")
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
