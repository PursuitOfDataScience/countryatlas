test_that("no verb leaves the caller's global state modified", {
  skip_slow_on_cran()
  # CRAN policy: a package must not change the user's options, working directory
  # or other global settings. The sf backend genuinely has to toggle
  # sf::sf_use_s2() (Natural Earth rings are invalid as spherical geometry) and
  # with_c_numbers() has to normalise OutDec/scipen for two upstream bugs, so
  # each is paired with an on.exit() restore -- which a later edit could drop
  # without any other test noticing. Error paths matter as much as happy ones.
  skip_if_no_sf_geometry()
  snap <- countryatlas::world_snapshot$countries
  sfd <- attach_geometry(snap, geometry = "sf")

  state <- function() {
    list(opts = options()[c("OutDec", "scipen", "digits", "warn")],
         s2 = sf::sf_use_s2(), wd = getwd())
  }
  unchanged_by <- function(expr) {
    before <- state()
    invisible(tryCatch(suppressWarnings(suppressMessages(force(expr))),
                       error = function(e) NULL))
    identical(before, state())
  }

  # Happy paths, including every sf_use_s2() toggle site and with_c_numbers().
  expect_true(unchanged_by(world_geometry("countries", geometry = "sf",
                                          region = c(-10, 30, 40, 48))))
  expect_true(unchanged_by(country_borders()))
  expect_true(unchanged_by(locate_country(lon = 2.3, lat = 48.8)))
  expect_true(unchanged_by(simplify_geometry(sfd, keep = 0.3)))
  expect_true(unchanged_by(world_geometry("graticule", geometry = "sf")))
  expect_true(unchanged_by(ggplot2::ggplot_build(world_map(sfd, gdp_per_capita))))

  # Error paths: on.exit() must run even when the call aborts.
  expect_true(unchanged_by(world_geometry("ocean", geometry = "sf",
                                          projection = "orthographic")))
  expect_true(unchanged_by(simplify_geometry(sfd, keep = 0)))
  expect_true(unchanged_by(locate_country(lon = 1, lat = 1, tolerance_km = -1)))
  expect_true(unchanged_by(world_map(sfd, gdp_per_capita, palette = c("a", "b"))))
})

test_that("a correct call to any verb is completely silent", {
  skip_slow_on_cran()
  # Six warning sites went in during the pre-CRAN work (warn_overwrite, the
  # share_of_world grouping note, flow_map's dropped flows, na_label, the
  # latest/panel conflict, the ggrepel fallback). None of them may fire on a
  # correct call: users run with options(warn = 2) in CI, where a stray warning
  # becomes an error.
  skip_if_no_sf_geometry()
  snap <- countryatlas::world_snapshot$countries
  sfd <- attach_geometry(snap, geometry = "sf")
  poly <- attach_geometry(snap, geometry = "polygon")
  pan <- tibble::tibble(iso3c = rep(c("USA", "FRA", "CHN", "IND"), each = 3),
                        year = rep(2000:2002, 4),
                        v = c(1, 2, 3, 10, 20, 30, 100, 150, 200, 5, 6, 7),
                        population = 1e6)

  expect_silent(force(world_map(sfd, gdp_per_capita)))
  expect_silent(force(world_map(poly, gdp_per_capita, style = "quantile")))
  expect_silent(force(bubble_map(sfd, population, backend = "sf")))
  expect_silent(force(spike_map(poly, population)))
  # Restrict to countries the bundled grid can place: tile_map() reports the
  # ones it cannot (as gridded_cartogram() does), so passing the whole snapshot
  # would be testing that warning rather than the absence of stray ones.
  expect_silent(force(tile_map(
    snap[snap$iso3c %in% countryatlas::world_tiles$iso3c, ], gdp_per_capita)))
  expect_silent(force(per_capita(snap, gdp_per_capita, pop = population)))
  expect_silent(force(share_of_world(snap, population)))
  expect_silent(force(rank_countries(snap, gdp_per_capita)))
  expect_silent(force(aggregate_regions(snap, population, by = "continent")))
  expect_silent(force(growth_rate(pan, v)))
  expect_silent(force(index_to(pan, v, base_year = 2000)))
  expect_silent(force(lag_by_country(pan, v)))
  expect_silent(force(diff_by_country(pan, v)))
  expect_silent(force(complete_years(pan)))
  expect_silent(force(correlate_indicators(snap)))
  expect_silent(force(gini(snap$population)))
  expect_silent(force(theil(snap$population)))
  expect_silent(force(flow_map(tibble::tibble(f = "France", t = "Japan"), f, t)))
  expect_silent(force(morans_i(sfd, gdp_per_capita, n_perm = 0)))
  expect_silent(force(attach_geometry(snap, geometry = "sf")))
  expect_silent(force(neighbors("France")))
  expect_silent(force(locate_country(lon = 2.3, lat = 48.8)))
  expect_silent(force(dissolve_country("USSR")))
  expect_silent(force(standardize_country(tibble::tibble(c = "France"), "c")))
})

test_that("the 3.0.0 verbs are silent on a correct call too", {
  skip_slow_on_cran()
  # Same contract as the block above, extended to the verbs that gained warning
  # sites in this release -- the panel guards, the unstandardised-key guards and
  # the coverage reports. Every one of them must stay quiet on ordinary input,
  # or `options(warn = 2)` turns a working script into a failing one.
  skip_if_no_sf_geometry()
  snap <- countryatlas::world_snapshot$countries
  sfd <- attach_geometry(snap, geometry = "sf")
  poly <- attach_geometry(snap, geometry = "polygon")

  expect_silent(force(world_table(snap, gdp_per_capita, engine = "tibble")))
  expect_silent(force(audit_coverage(snap)))
  expect_silent(force(rate_check(snap, population, gdp_per_capita)))
  expect_silent(force(coverage_map(sfd, gdp_per_capita)))
  expect_silent(force(value_by_alpha_map(sfd, gdp_per_capita, population)))
  expect_silent(force(classify_compare(poly, gdp_per_capita)))
  expect_silent(force(distance_between("France", "Germany")))
  expect_silent(force(simplify_geometry(sfd, keep = 0.1)))
  expect_silent(force(country_join(tibble::tibble(a = "France", x = 1),
                                   tibble::tibble(b = "France", y = 2), a, b)))
  expect_silent(force(country_sources()))
  expect_silent(force(projection_info()))
  expect_silent(force(country_timeline("France")))
})

test_that("the silence policy reaches every offline verb, not just 39 of them", {
  skip_slow_on_cran()
  # The two blocks above cover 39 of the 102 exports, and every warning bug
  # found in the pre-CRAN review sat in the gap: the hatched/disputes message
  # (world_map() was covered, but never with those two arguments), the constant
  # `equalize` note (value_by_alpha_map() was covered -- with a *varying*
  # population), and share_of_world()'s phantom year (covered -- with no NA and
  # a nonzero total). Coverage of the verb is not coverage of the contract.
  #
  # Every verb named here is offline and deterministic. The network verbs and
  # the deprecated clear_wdi_cache() are deliberately absent: the first cannot
  # run here, and the second is *meant* to speak.
  skip_if_no_sf_geometry()
  snap <- countryatlas::world_snapshot$countries
  sfd <- attach_geometry(snap, geometry = "sf")
  poly <- attach_geometry(snap, geometry = "polygon")
  pan <- tibble::tibble(iso3c = rep(c("USA", "FRA", "CHN", "IND"), each = 3),
                        year = rep(2000:2002, 4),
                        v = c(1, 2, 3, 10, 20, 30, 100, 150, 200, 5, 6, 7),
                        deaths = c(1:12), population = 1e6,
                        ppp = 2, defl = rep(c(1, 1.02, 1.05), 4))
  flows <- tibble::tibble(f = c("France", "Japan", "Brazil"),
                          t = c("Japan", "Brazil", "France"), w = c(1, 2, 3))
  cross <- snap[!is.na(snap$gdp_per_capita), ]
  # The convergence verbs run a log-t regression, which correctly warns below
  # 15 periods (Phillips & Sul) -- so a short panel is not a *correct* call and
  # testing it here would be testing that warning.
  # The noise is deliberate: a panel built from an exact formula makes the
  # log-t and beta regressions fit perfectly, which the verbs now (rightly)
  # report -- so the clean version would be testing that report instead.
  iso <- c("USA", "FRA", "CHN", "IND", "BRA", "ZAF")
  set.seed(20260909)
  long <- tibble::tibble(
    iso3c = rep(iso, each = 20),
    year = rep(2000:2019, length(iso)),
    v = as.numeric(rep(seq_len(20), length(iso))) *
      rep(c(1, 2, 5, 10, 20, 50), each = 20))
  long$v <- long$v * exp(stats::rnorm(nrow(long), 0, 0.05))

  # -- rates and time series
  expect_silent(force(smooth_rates(cross, population, gdp_per_capita)))
  expect_silent(force(to_ppp(pan, v, factor = ppp)))
  expect_silent(force(deflate(pan, v, base_year = 2000,
                              deflator = defl)))
  expect_silent(force(interpolate_missing(pan, "v")))

  # -- spatial statistics
  expect_silent(force(getis_ord(sfd, gdp_per_capita)))
  expect_silent(force(gearys_c(sfd, gdp_per_capita, n_perm = 0)))
  expect_silent(force(local_morans(sfd, gdp_per_capita, n_perm = 0)))
  expect_silent(force(spatial_lag(sfd, gdp_per_capita)))
  expect_silent(force(country_weights("contiguity",
                                      countries = c("FRA", "DEU", "ITA"))))

  # -- flows and networks
  expect_silent(force(flow_matrix(flows, f, t, w)))
  expect_silent(force(country_network(flows, f, t, w)))

  # -- convergence
  expect_silent(force(convergence_club(long, v)))
  expect_silent(force(sigma_convergence(long, v)))
  expect_silent(force(beta_convergence(long, v)))

  # -- maps
  expect_silent(force(facet_map(rbind(cbind(poly, year = 2000L),
                                      cbind(poly, year = 2001L)),
                                gdp_per_capita, facet = "year")))
  expect_silent(force(globe_map(sfd, gdp_per_capita)))
  expect_silent(force(lisa_map(sfd, gdp_per_capita, n_perm = 0)))
  expect_silent(force(od_map(flows, f, t, w)))
  expect_silent(force(projection_compare(sfd, gdp_per_capita,
                                         projections = c("robinson", "mollweide"))))
  expect_silent(force(projection_distortion("robinson")))
  expect_silent(force(tissot_map("robinson")))
  expect_silent(force(geom_country_labels()))

  # -- reference and lookup
  expect_silent(force(country_codes(c("iso3c", "continent"))))
  expect_silent(force(country_groups("EU")))
  expect_silent(force(in_group(c("FRA", "USA"), "EU")))
  expect_silent(force(join_world(tibble::tibble(c = "France"), "c")))
  expect_silent(force(country_join_all(list(
    tibble::tibble(c = "France", x = 1),
    tibble::tibble(c = "France", y = 2)), by = "c")))
  expect_silent(force(repair_country_names(c("France", "Germany"))))
  expect_silent(force(check_country_match(c("France", "Germany"))))
  expect_silent(force(map_provenance(world_map(sfd, gdp_per_capita))))
})

test_that("a zero-row frame is silent and typed, not warned about", {
  # `ifelse(usable, x / y, NA_real_)` returns logical(0) on a 0-row input --
  # ifelse() takes its result type from `test`, and with length 0 neither
  # branch runs -- and `if (!any(usable))` is TRUE for logical(0), so six verbs
  # both mistyped the column and warned "No usable population, so nothing
  # could be put per capita." about a frame that had no rows to be usable.
  # Neither block above had a 0-row leg.
  snap <- countryatlas::world_snapshot$countries
  empty <- snap[0, ]
  pan0 <- tibble::tibble(iso3c = character(), year = integer(),
                         v = numeric(), population = numeric(),
                         ppp = numeric(), defl = numeric())

  expect_silent(out <- per_capita(empty, gdp_per_capita, pop = population))
  expect_equal(nrow(out), 0L)
  expect_type(out[[ncol(out)]], "double")

  expect_silent(out <- to_ppp(pan0, v, factor = ppp))
  expect_type(out[[ncol(out)]], "double")

  expect_silent(out <- smooth_rates(empty, population, gdp_per_capita))
  expect_type(out[[ncol(out)]], "double")

  expect_silent(out <- rate_check(empty, population, gdp_per_capita))
  expect_equal(nrow(out), 0L)

  # This one aborted rather than warned: nothing is `%in%` an empty vector,
  # so the base_year guard fired and reported "Years present: Inf and -Inf"
  # from range() of nothing.
  expect_silent(out <- deflate(pan0, v, base_year = 2000, deflator = defl))
  expect_type(out[[ncol(out)]], "double")

  expect_silent(out <- share_of_world(empty, population))
  expect_type(out[[ncol(out)]], "double")

  expect_silent(out <- growth_rate(pan0, v))
  expect_type(out[[ncol(out)]], "double")
})

# The 4.0.0 verbs and arguments (T2): a correct call is silent, a zero-row
# input has a defined answer, every argument is validated by name, and the new
# map arguments are exercised against na_style and style.
silence_400_fixtures <- function() {
  snap <- countryatlas::world_snapshot$countries
  snap$chg <- log(snap$gdp_per_capita / stats::median(snap$gdp_per_capita,
                                                      na.rm = TRUE))
  set.seed(3)
  d <- snap[!is.na(snap$population) & snap$population > 0 & snap$iso3c != "GIB", ]
  d$deaths <- stats::rpois(nrow(d), d$population * 0.008)
  pan <- expand.grid(iso3c = countryatlas::world_tiles$iso3c[1:40],
                     year = 2000:2010, stringsAsFactors = FALSE)
  pan$v <- exp(stats::rnorm(nrow(pan)))
  mix <- snap
  mix$a <- stats::runif(nrow(mix), 1, 4)
  mix$b <- stats::runif(nrow(mix), 2, 6)
  mix$c <- stats::runif(nrow(mix), 4, 9)
  list(snap = snap, poly = attach_geometry(snap), d = d, pan = pan, mix = mix)
}

test_that("the 4.0.0 verbs are silent on a correct call", {
  skip_slow_on_cran()
  f <- silence_400_fixtures()
  p <- world_map(f$poly, gdp_per_capita)
  expect_silent(ggplot2::ggplotGrob(tile_trend_map(f$pan, v)))
  expect_silent(ggplot2::ggplotGrob(ternary_map(attach_geometry(f$mix), a, b, c)))
  expect_silent(ggplot2::ggplotGrob(zoom_map(p, xlim = c(-10, 40), ylim = c(35, 70))))
  expect_silent(ggplot2::ggplotGrob(value_by_alpha_map(f$poly, gdp_per_capita,
                                                       population)))
  expect_silent(force(project_lonlat(c(0, 10), c(0, 10))))
  expect_silent(force(map_alt_text(p)))
  expect_silent(force(map_citation(p)))
  if (requireNamespace("colorspace", quietly = TRUE)) {
    expect_silent(force(check_palette(p)))
  }
  expect_silent(force(inequality(stats::na.omit(f$snap$gdp_per_capita))))
  expect_silent(force(eb_morans_i(f$d, deaths, population, n_perm = 0)))
  expect_silent(force(smooth_rates(f$d, deaths, population, method = "local_eb")))
  expect_silent(force(bivariate_lisa(f$d, gdp_per_capita, life_expectancy,
                                     n_perm = 99)))
  expect_silent(force(join_counts(f$d, income, n_perm = 99)))
  expect_silent(force(rate_funnel(f$d, deaths, population)))
  expect_silent(force(transition_matrix(f$pan, v)))
  expect_silent(force(spatial_markov(f$pan, v, n_classes = 3)))
  expect_silent(force(rank_mobility(f$pan, v, 2000, 2010)))
  expect_silent(force(aggregate_groups(f$snap, gdp_per_capita, groups = "EU")))
  expect_silent(force(classify_countries(data.frame(iso3c = "VNM", year = 2025),
                                         "income")))
})

test_that("the 4.0.0 verbs have a defined answer for a zero-row input", {
  skip_slow_on_cran()
  f <- silence_400_fixtures()
  d0 <- f$d[0, ]
  pan0 <- f$pan[0, ]
  expect_silent(out <- inequality(numeric(0)))
  expect_true(all(is.na(out$value)))
  # The spatial statistics refuse as morans_i() does, naming no internal
  # column: an empty frame reached a numeric check on `.wdj_rate`.
  few <- "countryatlas_too_few_connected"
  expect_error(eb_morans_i(d0, deaths, population, n_perm = 0), class = few)
  expect_error(bivariate_lisa(d0, gdp_per_capita, life_expectancy), class = few)
  expect_error(join_counts(d0, income), class = few)
  expect_error(rate_funnel(d0, deaths, population), "at least two countries")
  expect_error(rank_mobility(pan0, v, 2000, 2010), "Too few countries")
  expect_silent(tm <- transition_matrix(pan0, v))
  expect_identical(sum(tm$n), 0L)
  expect_silent(spatial_markov(pan0, v))
  # An empty panel draws the bare tile grid: range() of nothing warned twice.
  expect_silent(ggplot2::ggplotGrob(tile_trend_map(pan0, v)))
  expect_silent(ggplot2::ggplotGrob(
    world_map(attach_geometry(f$snap[0, ]), gdp_per_capita, breaks = c(0, 1, 2))))
  expect_silent(ggplot2::ggplotGrob(
    world_map(attach_geometry(f$snap[0, ]), chg, midpoint = 0)))
  expect_error(ternary_map(attach_geometry(f$mix[0, ]), a, b, c),
               "No country has all three")
  expect_silent(aggregate_groups(f$snap[0, ], gdp_per_capita, groups = "EU"))
  expect_silent(classify_countries(data.frame(iso3c = character(),
                                              year = integer()), "income"))
})

test_that("every 4.0.0 argument is validated, and the error names it", {
  skip_slow_on_cran()
  f <- silence_400_fixtures()
  poly <- f$poly
  p <- world_map(poly, gdp_per_capita)
  x <- stats::na.omit(f$snap$gdp_per_capita)
  cases <- list(
    list(quote(world_map(poly, gdp_per_capita, breaks = "a")), "`breaks`"),
    list(quote(world_map(poly, gdp_per_capita, breaks = c(5, 1, 3))), "`breaks`"),
    list(quote(world_map(poly, gdp_per_capita, midpoint = c(1, 2))), "`midpoint`"),
    list(quote(world_map(poly, gdp_per_capita, small_states = "x")), "`small_states`"),
    list(quote(world_map(poly, gdp_per_capita, small_area_km2 = -1)), "`small_area_km2`"),
    list(quote(world_map(poly, gdp_per_capita, footnote = 3)), "`footnote`"),
    list(quote(tile_trend_map(f$pan, v, scales = "x")), "`scales`"),
    list(quote(tile_trend_map(f$pan, v, years = "a")), "`years`"),
    list(quote(inequality(x, measures = "nope")), "`measures`"),
    list(quote(inequality(x, epsilon = -1)), "`epsilon`"),
    list(quote(rate_funnel(f$d, deaths, population, limits = 2)), "`limits`"),
    list(quote(rate_funnel(f$d, deaths, population, target = -1)), "`target`"),
    list(quote(rate_funnel(f$d, deaths, population, overdispersion = "y")), "`overdispersion`"),
    list(quote(transition_matrix(f$pan, v, n_classes = 1)), "`n_classes`"),
    list(quote(transition_matrix(f$pan, v, step = 0)), "`step`"),
    list(quote(transition_matrix(f$pan, v, classes = "x")), "`classes`"),
    list(quote(rank_mobility(f$pan, v, 2000, 2010, k = 0)), "`k`"),
    list(quote(eb_morans_i(f$d, deaths, population, n_perm = -1)), "`n_perm`"),
    list(quote(bivariate_lisa(f$d, gdp_per_capita, life_expectancy, alpha = 2)), "`alpha`"),
    list(quote(bivariate_lisa(f$d, gdp_per_capita, life_expectancy, p_adjust = "x")), "`p_adjust`"),
    list(quote(join_counts(f$d, income, n_perm = 0)), "`n_perm`"),
    list(quote(smooth_rates(f$d, deaths, population, method = "x")), "`method`"),
    list(quote(map_alt_text(p, level = 3)), "`level`"),
    list(quote(check_palette(p, threshold = -1)), "`threshold`"),
    list(quote(map_citation(p, format = "x")), "`format`"),
    list(quote(zoom_map(p, xlim = 1, ylim = c(0, 10))), "`xlim`"),
    list(quote(project_lonlat("a", 1)), "`lon`"),
    list(quote(facet_map(rbind(cbind(poly, year = 2000L), cbind(poly, year = 2001L)),
                         gdp_per_capita, facet = "year", breaks_by = "x")), "`breaks_by`"),
    list(quote(attach_geometry(f$snap, worldview = 3)), "`worldview`"),
    list(quote(lag_by_country(f$pan, v, by = "x")), "`by`"),
    list(quote(theil(x, type = "x")), "`type`"),
    list(quote(ternary_map(attach_geometry(f$mix), a, b, c, centre = 1)), "`centre`")
  )
  for (cs in cases) {
    err <- tryCatch(eval(cs[[1]]), error = identity)
    expect_s3_class(err, "error")
    expect_match(cli::ansi_strip(conditionMessage(err)), cs[[2]], fixed = TRUE,
                 info = paste(deparse(cs[[1]]), collapse = " "))
  }
})

test_that("breaks, midpoint and small_states cross na_style and style silently", {
  skip_slow_on_cran()
  f <- silence_400_fixtures()
  poly <- attach_geometry(f$snap)
  rng <- range(f$snap$chg, na.rm = TRUE)
  br <- c(rng[1], -1, 0, 1, rng[2])
  na_styles <- c("grey", "hatched", "outline", "omit")
  ss <- c("auto", "none", "dots")
  styles <- c("quantile", "continuous", "equal", "headtails")
  # Every pair of levels appears at least once: na_style x small_states runs
  # in full (by the Chinese remainder theorem over 12 rows), and the
  # breaks/midpoint and style columns cycle against both.
  for (i in 0:15) {
    args <- list(poly, quote(chg), na_style = na_styles[i %% 4 + 1],
                 small_states = ss[i %% 3 + 1],
                 midpoint = if (i %% 2) 0)
    if ((i %/% 2) %% 2) args$breaks <- br else args$style <- styles[(i %/% 4) %% 4 + 1]
    # Hatching without ggpattern says, once, that it draws grey instead.
    if (identical(args$na_style, "hatched") && !requireNamespace("ggpattern", quietly = TRUE)) {
      expect_no_warning(suppressMessages(ggplot2::ggplotGrob(do.call(world_map, args))))
    } else {
      expect_silent(ggplot2::ggplotGrob(do.call(world_map, args)))
    }
  }
  # p_adjust against na_style, on lisa_map().
  skip_if_no_sf_geometry()
  sfd <- attach_geometry(f$snap, geometry = "sf")
  for (i in 1:4) {
    expect_silent(ggplot2::ggplotGrob(
      lisa_map(sfd, gdp_per_capita, n_perm = 99,
               p_adjust = c("fdr", "bonferroni", "holm", "none")[i],
               na_style = na_styles[i])))
  }
})
