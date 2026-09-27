# Regression tests for the second 3.0.0 polish pass. Each block pins a defect
# that shipped silently -- a wrong colour, a dropped row, a fabricated number
# -- and states the contract the fix restores.

# --- ranking once per country ------------------------------------------------

test_that("value_by_alpha_map() ranks opacity once per country, not per vertex", {
  # FRA has far more vertex rows than the others and the lowest population,
  # so a rank over the raw rows pushed everyone above it up the scale.
  d <- toy_polygons(c(FRA = 1, DEU = 2, ITA = 3, ESP = 4),
                    n_vertices = c(60, 4, 4, 4))
  d$pop <- c(10, 20, 30, 40)[d$group]
  p <- value_by_alpha_map(d, v, pop)
  drawn <- unique(ggplot2::ggplot_build(p)$plot$data[, c("iso3c", ".wdj_alpha")])
  expect_equal(drawn$.wdj_alpha[match(c("FRA", "DEU", "ITA", "ESP"), drawn$iso3c)],
               c(0, 1, 2, 3) / 3)
  # The same countries drawn with equal outlines get the same opacity.
  eq <- toy_polygons(c(FRA = 1, DEU = 2, ITA = 3, ESP = 4))
  eq$pop <- c(10, 20, 30, 40)[eq$group]
  eq_drawn <- unique(ggplot2::ggplot_build(value_by_alpha_map(eq, v, pop))$plot$data[
    , c("iso3c", ".wdj_alpha")])
  expect_equal(eq_drawn$.wdj_alpha, drawn$.wdj_alpha)
})

test_that("world_map(uncertainty = ) places each country in its VSUP cell once", {
  vals <- c(FRA = 1, DEU = 2, ITA = 3, ESP = 4, PRT = 5, POL = 6)
  d <- toy_polygons(vals, n_vertices = c(80, 4, 4, 4, 4, 4))
  d$se <- c(0.1, 0.5, 0.2, 0.9, 0.3, 0.6)[d$group]
  p <- world_map(d, v, uncertainty = se, n_bins = 3)
  drawn <- unique(ggplot2::ggplot_build(p)$plot$data[, c("iso3c", ".wdj_vsup")])
  one <- unique(d[, c("iso3c", "v", "se")])
  want <- countryatlas:::vsup_fill(one$v, one$se, n_bins = 3, n_uncertainty = 3)
  expect_equal(as.character(drawn$.wdj_vsup[match(one$iso3c, drawn$iso3c)]),
               want$label)
  # A lone usable country sits mid-ramp however many vertices it has.
  lone <- toy_polygons(c(FRA = 1, DEU = 2), n_vertices = c(40, 4))
  lone$se <- c(0.5, NA)[lone$group]
  r <- countryatlas:::vsup_fill(lone$v, lone$se, n_bins = 3,
                                unit = lone$iso3c)
  expect_equal(unique(r$v_bin[lone$iso3c == "FRA"]), 2L)
})

# --- attach_geometry() ---------------------------------------------------------

test_that("attach_geometry() refuses a column the polygon backend draws with", {
  for (col in c("group", "lat", "long", "order")) {
    d <- data.frame(iso3c = c("FRA", "DEU"), value = 1:2)
    d[[col]] <- c(1, 2)
    expect_error(attach_geometry(d, geometry = "polygon"),
                 class = "countryatlas_geometry_column_clash")
    expect_error(attach_geometry(d, geometry = "polygon"), col, fixed = TRUE)
  }
  # The sf backend keeps its geometry in one column, so the same frame is fine.
  skip_if_no_sf_geometry()
  d <- data.frame(iso3c = c("FRA", "DEU"), value = 1:2, group = c("a", "b"))
  out <- suppressWarnings(attach_geometry(d, geometry = "sf"))
  expect_s3_class(out, "sf")
  expect_equal(out$group[out$iso3c %in% "FRA"], "a")
})

# --- rates.R -------------------------------------------------------------------

test_that("convergence_club() returns a country with a gap as unclassified", {
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
  d <- data.frame(iso3c = c("A", "B", "C"), cases = c(-5, 10, 20),
                  pop = c(1000, 2000, 3000))
  expect_warning(out <- rate_check(d, cases, pop),
                 class = "countryatlas_negative_count")
  expect_true(is.na(out$expected_se[out$iso3c == "A"]))
  expect_false(anyNA(out$expected_se[out$iso3c != "A"]))
})

# --- analysis.R ----------------------------------------------------------------

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

# --- geometry.R ----------------------------------------------------------------

test_that("a region vector with a name that matches nothing says so", {
  expect_warning(iso <- countryatlas:::resolve_region(c("France", "Germny")),
                 class = "countryatlas_region_unmatched")
  expect_equal(stats::na.omit(iso)[[1]], "FRA")
  expect_warning(countryatlas:::resolve_region(c("France", "Germny")), "Germny")
  # Continent names are taken only on their own, and the refusal says that.
  expect_error(countryatlas:::resolve_region(c("Europe", "Asia")),
               "only on its own")
  # One resolvable name, or a code vector, stays silent.
  expect_silent(countryatlas:::resolve_region(c("France", "Germany")))
  expect_silent(countryatlas:::resolve_region(c("FRA", "DEU")))
})

# --- spatial-stats.R -----------------------------------------------------------

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

# --- visualization.R -----------------------------------------------------------

test_that("bivariate_map() validates `dim` before anything else", {
  d <- data.frame(iso3c = "FRA", x = 1, y = 1)
  for (bad in list("a", NA, c(2, 3), 5, 1)) {
    expect_error(bivariate_map(d, x, y, dim = bad), "dim")
  }
  expect_error(bivariate_map(d, x, y, dim = 2.5), "whole number")
})

test_that("a non-finite year is refused as such, without a coercion warning", {
  expect_error(country_data(Inf), "finite")
  expect_error(country_data(c(2000, Inf)), "finite")
  expect_no_warning(try(country_data(Inf), silent = TRUE))
})

test_that("the tmap engine draws 'binned' as equal intervals, like ggplot2", {
  skip_if_not_installed("tmap")
  skip_if_no_sf_geometry()
  sfd <- suppressWarnings(attach_geometry(countryatlas::world_snapshot$countries,
                                          geometry = "sf"))
  got <- NULL
  orig <- tmap::tm_scale_intervals
  local_mocked_bindings(tm_scale_intervals = function(...) {
    got <<- list(...)
    orig(...)
  }, .package = "tmap")
  world_map(sfd, gdp_per_capita, style = "binned", engine = "tmap")
  expect_equal(got$style, "equal")
  world_map(sfd, gdp_per_capita, style = "quantile", engine = "tmap")
  expect_equal(got$style, "quantile")
})

test_that("world_map() does not call n_bins ignored when the VSUP uses it", {
  d <- toy_polygons(c(FRA = 1, DEU = 2, ITA = 3, ESP = 4, PRT = 5, POL = 6))
  d$se <- c(0.1, 0.5, 0.2, 0.9, 0.3, 0.6)[d$group]
  expect_no_warning(p <- world_map(d, v, uncertainty = se, n_bins = 3))
  # ... and it really is used: three value classes, not the default five.
  lv <- levels(ggplot2::ggplot_build(p)$plot$data$.wdj_vsup)
  expect_equal(sort(unique(sub(" /.*", "", lv))), c("v1", "v2", "v3"))
  # Without `uncertainty` the notice is still right.
  expect_warning(world_map(d, v, n_bins = 3),
                 class = "countryatlas_n_bins_ignored")
})

test_that("world_map() says n_uncertainty does nothing without uncertainty", {
  d <- toy_polygons(c(FRA = 1, DEU = 2, ITA = 3))
  expect_warning(world_map(d, v, n_uncertainty = 5),
                 class = "countryatlas_n_uncertainty_ignored")
  expect_warning(world_map(d, v, n_uncertainty = "a"),
                 class = "countryatlas_n_uncertainty_ignored")
  expect_silent(world_map(d, v))
  expect_silent(world_map(d, v, n_uncertainty = 3L))
})

# --- networks.R, time.R, sources.R ---------------------------------------------

test_that("od_map() names a destination the basemap cannot draw", {
  skip_if_not_installed("maps")
  od <- data.frame(from = "China", to = c("Hong Kong", "USA", "Japan"),
                   value = c(900, 500, 200))
  expect_warning(p <- od_map(od, from, to, value, origins = 1),
                 class = "countryatlas_no_geometry")
  expect_warning(od_map(od, from, to, value, origins = 1), "HKG")
  # Every destination drawable: nothing to say.
  ok <- od[od$to != "Hong Kong", ]
  expect_no_warning(od_map(ok, from, to, value, origins = 1),
                    class = "countryatlas_no_geometry")
})

test_that("historical_geometry() gives no code to a state not yet born", {
  skip_if_not_installed("cshapes")
  skip_if_not_installed("sf")
  skip_on_cran()
  g80 <- sf::st_drop_geometry(historical_geometry(1980, projection = NULL))
  # GW code 365 is the USSR in 1980 and Russia from 1992; historical_codes has
  # Russia as one of fifteen successors, born in 1991.
  expect_true(is.na(g80$iso3c[g80$gwcode == 365]))
  expect_equal(g80$iso3c[g80$gwcode == 2], "USA")
  g10 <- sf::st_drop_geometry(historical_geometry(2010, projection = NULL))
  expect_equal(g10$iso3c[g10$gwcode == 365], "RUS")
  # The documented `owner`: a sovereign state carries its own code.
  if ("owner" %in% names(g80)) {
    expect_false(anyNA(g80$owner[g80$gwcode == 2]))
    # cshapes stores it as text; the value is the state's own code.
    expect_equal(as.numeric(g80$owner[g80$gwcode == 2]), 2)
  }
  # attach_geometry(year = ) no longer paints the USSR with Russia's value.
  d <- data.frame(iso3c = c("RUS", "USA"), v = c(1, 2))
  out <- suppressWarnings(attach_geometry(d, year = 1980))
  expect_true(is.na(out$v[out$gwcode == 365]))
})

test_that("audit_time_coverage() and historical_geometry() agree on births", {
  born <- countryatlas:::successor_born_years()
  expect_equal(unname(born["RUS"]), 1991)
  flagged <- audit_time_coverage(data.frame(iso3c = "RUS", year = 1980L),
                                 quiet = TRUE)
  expect_equal(flagged$issue, "before_existence")
})

test_that("compare_sources() refuses a source named twice", {
  expect_error(compare_sources("x", sources = c("wdi", "wdi"), year = 2020),
               "distinct")
})

test_that("lisa_map()'s provenance counts the countries it colours", {
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

test_that("standardize_subnational() normalises an ISO 3166-2 code's case and padding", {
  d <- data.frame(region = c("DE-BY", "de-by", "DE-BY ", "\u00a0DE-HE", "US-CA"),
                  value = 1:5)
  out <- suppressWarnings(suppressMessages(
    standardize_subnational(d, region, country = "Germany")))
  expect_equal(out$iso_3166_2, c("DE-BY", "DE-BY", "DE-BY", "DE-HE", NA))
})

test_that("a bad cache limit option is named, not blamed on the directory", {
  td <- tempfile("cachelim")
  dir.create(td)
  old <- options(countryatlas.cache_dir = td)
  on.exit({
    unlink(td, recursive = TRUE)
    options(old)
    options(countryatlas.cache_max_age = NULL, countryatlas.cache_max_size = NULL)
    clear_wdi_cache()
  }, add = TRUE)
  for (opt in c("countryatlas.cache_max_age", "countryatlas.cache_max_size")) {
    for (bad in list("a", NA, -1, c(1, 2))) {
      do.call(options, stats::setNames(list(bad), opt))
      clear_wdi_cache()
      expect_error(countryatlas:::get_fetch_fun(TRUE), opt, fixed = TRUE)
    }
    do.call(options, stats::setNames(list(NULL), opt))
  }
  # Inf is "no limit" and keeps the disk cache.
  options(countryatlas.cache_max_age = Inf)
  clear_wdi_cache()
  expect_no_error(countryatlas:::get_fetch_fun(TRUE))
  expect_true(countryatlas:::.wdj_state$fetch_on_disk)
})

test_that("join_world() says when it replaces a column of the caller's", {
  d <- data.frame(country = c("France", "Kenya"), region = c("North", "South"),
                  v = 1:2)
  expect_warning(out <- join_world(d, country, geometry = "none"),
                 class = "countryatlas_unasked_overwrite")
  expect_equal(out$region, c("Europe & Central Asia", "Sub-Saharan Africa"))
  expect_no_warning(join_world(d, country, geometry = "none", warn = FALSE))
  # Replacing a column with the values it already holds is not worth a word.
  # A frame standardised here, not the bundled snapshot: the snapshot's regions
  # are the World Bank's as of its build, and countrycode can move a country.
  std <- standardize_country(d[, c("country", "v")], country, warn = FALSE)
  expect_no_warning(join_world(std, country, geometry = "none"),
                    class = "countryatlas_unasked_overwrite")
})

test_that("audit_coverage() and coverage_map() agree about an infinity", {
  d <- data.frame(iso3c = c("FRA", "DEU", "ITA", "ESP"),
                  region = c("Europe", "Europe", "Europe", "Europe"),
                  v = c(1, Inf, NA, 4))
  a <- audit_coverage(d, "v")
  expect_equal(a$na_rates$n_missing, 2L)
  expect_equal(a$by_group$na_rate, 0.5)
  g <- toy_polygons(c(FRA = 1, DEU = Inf, ITA = NA, ESP = 4))
  cm <- suppressWarnings(coverage_map(g, v))
  expect_equal(map_provenance(cm)$n_missing, 2L)
})

test_that("a non-breaking space does not turn the USSR into Russia", {
  nb <- intToUtf8(0xa0)
  x <- c(paste0("USSR", nb), paste0(nb, "Yugoslavia"), paste0("East", nb, "Germany"))
  d <- dissolve_country(x)
  expect_equal(sort(unique(d$historical)),
               c("East Germany", "Soviet Union", "Yugoslavia"))
  expect_equal(sum(d$input == x[1]), 15L)
  expect_true(all(check_country_match(x)$historical))
  expect_equal(country_timeline(x)$country,
               c("Soviet Union", "Yugoslavia", "East Germany"))
})

test_that("the interactive engines draw a fill with nothing to scale", {
  skip_if_no_sf_geometry()
  sfd <- suppressWarnings(attach_geometry(countryatlas::world_snapshot$countries,
                                          geometry = "sf"))
  sfd$allna <- NA_real_
  sfd$oneval <- NA_real_
  sfd$oneval[sfd$iso3c %in% "FRA"] <- 5
  sfd$const <- 3
  sfd$catna <- NA_character_
  if (requireNamespace("leaflet", quietly = TRUE)) {
    # colorNumeric() died on "Wasn't able to determine range of domain".
    for (col in c("allna", "oneval", "const", "catna")) {
      expect_no_error(interactive_map(sfd, !!rlang::sym(col), engine = "leaflet"))
    }
  }
  if (requireNamespace("mapgl", quietly = TRUE)) {
    # One distinct value gave one break and two colours; none at all was
    # refused by mapgl outright.
    for (col in c("allna", "oneval", "const", "catna")) {
      expect_no_warning(w <- interactive_map(sfd, !!rlang::sym(col),
                                             engine = "mapgl"))
      expect_s3_class(w, "maplibregl")
    }
  }
})

test_that("an orthographic view can be drawn from any side", {
  skip_if_no_sf_geometry()
  skip_on_cran()
  sfd <- suppressWarnings(attach_geometry(countryatlas::world_snapshot$countries,
                                          geometry = "sf"))
  draw <- function(p) {
    f <- tempfile(fileext = ".png")
    on.exit(unlink(f))
    grDevices::png(f, width = 120, height = 120)
    on.exit(grDevices::dev.off(), add = TRUE, after = FALSE)
    print(p)
    TRUE
  }
  # These viewpoints built and then failed when drawn: a country on the
  # horizon (Chad, at lon 120 / lat 20) projected to a one-point ring and grid
  # refused it with "Invalid graphics path".
  for (v in list(c(120, 20), c(140, 20), c(10, -60), c(50, 45), c(330, 70))) {
    expect_true(draw(globe_map(sfd, gdp_per_capita, lon = v[1], lat = v[2])))
  }
  expect_true(draw(world_map(sfd, gdp_per_capita, projection = "orthographic",
                             recenter = 140)))
  expect_true(draw(tissot_map("orthographic")))
  if (requireNamespace("tmap", quietly = TRUE) &&
      all(c("tm_scale_intervals", "tm_scale_continuous") %in%
            getNamespaceExports("tmap"))) {
    tm <- world_map(sfd, gdp_per_capita, engine = "tmap",
                    projection = "orthographic", recenter = 120)
    f <- tempfile(fileext = ".png")
    expect_no_error(suppressMessages(tmap::tmap_save(tm, f, width = 200,
                                                     height = 200)))
    unlink(f)
  }
  # The cut keeps every row, so the colour scale and the coverage are the same
  # from every side; what is out of view is empty, and nothing projects to a
  # non-finite or degenerate ring.
  cut <- countryatlas:::clip_to_hemisphere(sfd, 120, 20)
  expect_equal(nrow(cut), nrow(sfd))
  expect_equal(sf::st_drop_geometry(cut), sf::st_drop_geometry(sfd))
  pr <- sf::st_transform(cut, countryatlas:::wdj_crs("orthographic", 120, 20))
  xy <- sf::st_coordinates(pr[!sf::st_is_empty(pr), ])
  expect_true(all(is.finite(xy[, 1:2])))
  ring <- interaction(as.data.frame(xy[, setdiff(colnames(xy), c("X", "Y"))]),
                      drop = TRUE)
  expect_true(all(table(ring) >= 4L))
  expect_equal(map_provenance(globe_map(sfd, gdp_per_capita, lon = 120))$n_total,
               map_provenance(globe_map(sfd, gdp_per_capita, lon = 0))$n_total)
})

test_that("countries with no data are drawn in every period, not in an NA one", {
  vals <- c(FRA = 1, DEU = 2, ITA = 3)
  d <- toy_polygons(vals)
  d$year <- NA_integer_
  panel <- rbind(transform(d[d$iso3c != "ITA", ], year = 2000L),
                 transform(d[d$iso3c != "ITA", ], year = 2010L),
                 d[d$iso3c == "ITA", ])
  panel$v[panel$iso3c == "ITA"] <- NA
  p <- facet_map(panel, v, year)
  b <- ggplot2::ggplot_build(p)
  expect_equal(as.character(b$layout$layout$year), c("2000", "2010"))
  # ITA, which has no data, is in both panels.
  per_panel <- tapply(b$plot$data$iso3c, b$plot$data$year,
                      function(z) "ITA" %in% z)
  expect_true(all(per_panel))
  expect_equal(map_provenance(p)$n_total, 3L)
  expect_equal(map_provenance(p)$n_missing, 1L)
  # The same frame animated: no NA frame for gganimate to coerce.
  skip_if_not_installed("gganimate")
  a <- animate_world(panel, v)
  dd <- tempfile("anim")
  dir.create(dd)
  on.exit(unlink(dd, recursive = TRUE), add = TRUE)
  expect_no_warning(gganimate::animate(
    a, nframes = 2, fps = 1, width = 80, height = 60,
    renderer = gganimate::file_renderer(dir = dd, overwrite = TRUE)))
})

test_that("historical borders draw in the orthographic projection", {
  skip_if_not_installed("cshapes")
  skip_if_not_installed("sf")
  skip_on_cran()
  # Repairing CShapes geometry gives geometry collections (a polygon plus a
  # sliver of line), and casting one keeps only its first part, which failed
  # with "polygons require at least 4 points".
  hist <- suppressWarnings(historical_geometry(1950, dependencies = TRUE))
  cut <- countryatlas:::clip_to_hemisphere(hist, 0, 20)
  expect_equal(nrow(cut), nrow(hist))
  expect_true(all(sf::st_geometry_type(cut) == "MULTIPOLYGON"))
  f <- tempfile(fileext = ".png")
  grDevices::png(f, width = 120, height = 120)
  on.exit({ grDevices::dev.off(); unlink(f) }, add = TRUE)
  expect_no_error(print(suppressWarnings(
    world_map(hist, gwcode, projection = "orthographic", recenter = 120))))
})

test_that("polygon_parts() keeps one feature per input and only polygons", {
  skip_if_not_installed("sf")
  sq <- sf::st_polygon(list(rbind(c(0, 0), c(1, 0), c(1, 1), c(0, 1), c(0, 0))))
  ln <- sf::st_linestring(rbind(c(2, 2), c(3, 3)))
  g <- sf::st_sfc(sf::st_geometrycollection(list(ln, sq)), sq,
                  sf::st_geometrycollection(list(ln)), sf::st_multipolygon())
  out <- countryatlas:::polygon_parts(g)
  expect_length(out, 4L)
  expect_true(all(sf::st_geometry_type(out) == "MULTIPOLYGON"))
  expect_equal(sf::st_is_empty(out), c(FALSE, FALSE, TRUE, TRUE))
})

test_that("a factsheet says when neighbours could not be computed", {
  local_mocked_bindings(neighbors = function(...) {
    rlang::abort("The package \"sf\" is required.")
  })
  for (x in c("France", "Andorra")) {
    out <- cli::cli_fmt(print(country_factsheet(x)))
    expect_true(any(grepl("Not computed", out)))
    # The microstate note blamed the basemap for what the lookup never did.
    expect_false(any(grepl("basemap", out)))
    expect_false(any(grepl("None found", out)))
  }
})

test_that("the plotly engine refuses the orthographic view by name", {
  skip_if_not_installed("plotly")
  skip_if_no_sf_geometry()
  sfd <- suppressWarnings(attach_geometry(countryatlas::world_snapshot$countries,
                                          geometry = "sf"))
  expect_error(interactive_map(sfd, gdp_per_capita, engine = "plotly",
                               projection = "orthographic"),
               class = "countryatlas_engine_projection")
  expect_s3_class(interactive_map(sfd, gdp_per_capita, engine = "plotly"),
                  "plotly")
})

test_that("an error raised inside a verb's own handler names the verb", {
  snap <- countryatlas::world_snapshot$countries
  # Raised from a tryCatch() handler or an lapply() function written inline in
  # the verb, these were headed "Error in `value[[3L]]()`" or "Error in `FUN()`".
  header <- function(expr) {
    e <- tryCatch(expr, error = identity)
    expect_s3_class(e, "countryatlas_error")
    as.character(conditionCall(e)[[1]])
  }
  expect_equal(header(complete_years(snap, value = gdp_per_capita)),
               "complete_years")
  expect_equal(header(audit_coverage(snap, gdp_per_capita)), "audit_coverage")
  expect_equal(header(country_join_all(list(snap, snap), by = "nope")),
               "country_join_all")
  expect_equal(header(correlate_indicators(snap, nope, gdp_per_capita)),
               "correlate_indicators")
  expect_equal(header(geom_country_labels(data = snap)), "geom_country_labels")
  register_country_source("polish_down", function(indicator, countries, years, ...) {
    stop("provider is down")
  }, cache = FALSE)
  withr::defer(remove_country_source("polish_down"))
  expect_equal(header(fetch_indicator("polish_down", "x")), "fetch_indicator")
})

test_that("an error raised by an internal helper names the verb called", {
  snap <- countryatlas::world_snapshot$countries
  header <- function(expr) {
    e <- tryCatch(expr, error = identity)
    expect_s3_class(e, "countryatlas_error")
    as.character(conditionCall(e)[[1]])
  }
  # Each was headed with the helper's own name: weights_custom(),
  # weights_knn(), wdj_to_iso3c(), build_overrides(), get_world_sf(),
  # resolve_footnote(), compute_breaks().
  expect_equal(header(country_weights(type = "custom")), "country_weights")
  expect_equal(header(country_weights(type = "knn", k = 0)), "country_weights")
  expect_equal(header(neighbors("France", origin = c("a", "b"))), "neighbors")
  expect_equal(header(convert_country("France", custom_match = 1)),
               "convert_country")
  expect_equal(header(country_overrides(1)), "country_overrides")
  x <- data.frame(country = "France", a = 1)
  expect_equal(header(country_join(x, x, country, country, origin_x = 1)),
               "country_join")
  # ...and the argument the caller wrote, not the helper's own `origin`.
  expect_error(country_join(x, x, country, country, origin_y = 1), "origin_y")
  # The polygon backend needs `maps`, which refuses before `region` is read.
  skip_if_not_installed("maps")
  expect_equal(header(world_geometry(region = NA)), "world_geometry")
  poly <- suppressWarnings(attach_geometry(snap))
  expect_equal(header(world_map(poly, gdp_per_capita, footnote = 1)), "world_map")
  expect_equal(header(value_by_alpha_map(poly, gdp_per_capita, population,
                                         n_bins = 1)),
               "value_by_alpha_map")
  skip_if_no_sf_geometry()
  expect_equal(header(country_borders(scale = "huge")), "country_borders")
})

test_that("a bad option is reported without blaming an internal helper", {
  e <- tryCatch(
    withr::with_options(list(countryatlas.cache_max_age = -1),
                        countryatlas:::wdj_disk_cache()),
    error = identity)
  expect_s3_class(e, "countryatlas_bad_option")
  expect_null(conditionCall(e))
})

test_that("recenter = 360 works on the sf backend and 500 is refused by name", {
  skip_if_no_sf_geometry()
  # Both reached sf::st_break_antimeridian() unvalidated and failed with
  # "polygons require at least 4 points".
  g360 <- suppressWarnings(world_geometry(geometry = "sf", recenter = 360))
  g0 <- suppressWarnings(world_geometry(geometry = "sf"))
  expect_equal(nrow(g360), nrow(g0))
  expect_error(world_geometry(geometry = "sf", recenter = 500),
               "must be between -360 and 360", class = "countryatlas_error")
  expect_error(attach_geometry(countryatlas::world_snapshot$countries,
                               geometry = "sf", recenter = -400),
               "must be between -360 and 360", class = "countryatlas_error")
})

test_that("bubble_map() says the polygon backend ignores `projection`", {
  skip_if_not_installed("maps")
  snap <- countryatlas::world_snapshot$countries
  # Five countries have no bundled centroid, which is reported on its own.
  bubbles <- function(...) {
    withCallingHandlers(bubble_map(snap, population, ...),
                        countryatlas_no_centroid = function(w) {
                          invokeRestart("muffleWarning")
                        })
  }
  w <- tryCatch(bubbles(projection = "robinson"), warning = identity)
  expect_s3_class(w, "countryatlas_projection_ignored")
  expect_match(conditionMessage(w), 'backend = "sf"', fixed = TRUE)
  expect_no_warning(bubbles())
})

test_that("cartograms draw in the orthographic and Winkel Tripel projections", {
  skip_if_not_installed("cartogram")
  skip_if_no_sf_geometry()
  skip_on_cran()
  sfd <- suppressWarnings(attach_geometry(countryatlas::world_snapshot$countries,
                                          geometry = "sf"))
  draw <- function(p) {
    f <- tempfile(fileext = ".png")
    grDevices::png(f, width = 120, height = 120)
    on.exit({ grDevices::dev.off(); unlink(f) })
    print(p)
    TRUE
  }
  # The far side reached cartogram as empty geometry: "all sizes are missing
  # and/or non-positive". It is out of view, not missing, so coverage is
  # unchanged.
  flat <- suppressWarnings(dorling_map(sfd, population, itermax = 10))
  ortho <- suppressWarnings(dorling_map(sfd, population, itermax = 10,
                                        projection = "orthographic"))
  expect_true(draw(ortho))
  expect_equal(map_provenance(ortho)$n_missing, map_provenance(flat)$n_missing)
  # Printing computed a graticule over the cartogram's box and died on GEOS's
  # "point array must contain 0 or >1 elements".
  expect_true(draw(suppressWarnings(
    cartogram_map(sfd, population, itermax = 2, projection = "winkel_tripel"))))
})

test_that("compare_sources() survives a year no source covers, and an infinity", {
  register_country_source("pol_a", function(indicator, countries, years, ...) {
    data.frame(iso3c = c("USA", "FRA", "DEU"), year = 2019L, v = c(Inf, 2, 3))
  }, cache = FALSE)
  register_country_source("pol_b", function(indicator, countries, years, ...) {
    data.frame(iso3c = c("USA", "FRA", "DEU"), year = 2019L, v = c(1, 2, 3))
  }, cache = FALSE)
  withr::defer(remove_country_source(c("pol_a", "pol_b")))
  # No row for 2020 anywhere: base R's "subscript out of bounds".
  expect_warning(
    empty <- compare_sources("v", sources = c("pol_a", "pol_b"), year = 2020),
    class = "countryatlas_no_data")
  expect_equal(nrow(empty), 0L)
  expect_named(empty, c("iso3c", "pol_a", "pol_b", "n_sources", "rel_diff",
                        "disagrees"))
  # The infinity made rel_diff NaN, which `disagrees` read as agreement.
  expect_warning(
    r <- compare_sources("v", sources = c("pol_a", "pol_b"), year = 2019),
    class = "countryatlas_infinite_value")
  usa <- r[r$iso3c == "USA", ]
  expect_equal(usa$pol_a, Inf)
  expect_equal(usa$n_sources, 1)
  expect_true(is.na(usa$rel_diff))
  expect_false(usa$disagrees)
  expect_equal(attr(r, "countryatlas_source_summary")$n_both, 2L)
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
