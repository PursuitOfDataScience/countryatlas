# Every exported function's documented \value, asserted as an executable
# contract. Rd prose can drift from the code silently; these tests make the
# documented shape a thing that breaks when it stops being true.

snap <- countryatlas::world_snapshot$countries
panel <- data.frame(iso3c = rep(c("USA", "CHN", "IND", "BRA"), each = 3),
                    year  = rep(2000:2002, 4),
                    gdp   = c(100, 110, 121, 50, 60, 72, 20, 25, 31, 70, 77, 85))

test_that("diagnostic verbs return their documented columns", {
  expect_named(check_country_match("USA"),
               c("input", "iso3c", "matched", "historical", "suggestion"))
  expect_named(dissolve_country("USSR"),
               c("input", "historical", "dissolved", "iso3c", "country"))
  expect_type(dissolve_country("France", warn = FALSE)$dissolved, "integer")
  a <- audit_coverage(snap)
  expect_named(a, c("unmatched", "na_rates", "by_group"))
  expect_s3_class(a, "countryatlas_coverage")
  r <- repair_country_names(c("Brzil", "Germny"), verbose = FALSE)
  expect_type(r, "character")
  expect_length(r, 2L)
  expect_s3_class(attr(r, "repairs"), "tbl_df")
})

test_that("statistics return their documented shape", {
  b <- beta_convergence(panel, gdp)
  expect_equal(nrow(b), 1L)
  expect_named(b, c("beta", "se", "t_value", "p_value", "r_squared", "n",
                    "speed", "half_life"))
  expect_s3_class(attr(b, "model"), "lm")     # documented attribute
  expect_named(sigma_convergence(panel, gdp), c("year", "n", "sigma"))
  ci <- correlate_indicators(snap)
  expect_named(ci, c("var_x", "var_y", "r", "n"))
  expect_false(is.unsorted(rev(abs(ci$r[!is.na(ci$r)]))))   # sorted by |r| desc
  d <- theil(c(1, 2, 4, 8), groups = c("a", "a", "b", "b"))
  expect_named(d, c("component", "value", "share"))
  expect_equal(d$component, c("total", "between", "within"))
  expect_equal(d$value[1], d$value[2] + d$value[3])          # decomposes exactly
  expect_length(theil(c(1, 2, 4)), 1L)
  g <- gini(snap$gdp_per_capita)
  expect_length(g, 1L)
  expect_gte(g, 0); expect_lte(g, 1)                         # documented [0, 1]
})

test_that("panel helpers add the documented column", {
  gr <- growth_rate(panel, gdp)
  expect_true("gdp_growth" %in% names(gr))
  # Documented as a proportion, so 0.03 means 3%.
  expect_equal(gr$gdp_growth[gr$iso3c == "USA"][2], 0.10)
  expect_equal(index_to(panel, gdp, base_year = 2000)$gdp_index[1], 100)
  sw <- share_of_world(data.frame(iso3c = c("A", "B"), v = c(1, 3)), v)
  expect_equal(sum(sw$v_share), 1)                           # proportion in [0,1]
  expect_equal(per_capita(data.frame(iso3c = "A", v = 10, p = 2), v, p)$v_per_capita, 5)
  # n = 5 is longer than this panel's span, so both columns come out NA
  # throughout -- which the verbs now report. The contract under test here is
  # the column *name* (the suffix carries `n` when n > 1), so assert both.
  expect_warning(l5 <- lag_by_country(panel, gdp, n = 5),
                 class = "countryatlas_all_na_result")
  expect_true("gdp_lag5" %in% names(l5))
  expect_warning(d5 <- diff_by_country(panel, gdp, n = 5),
                 class = "countryatlas_all_na_result")
  expect_true("gdp_diff5" %in% names(d5))
  expect_named(aggregate_regions(snap, population, by = "region"),
               c("region", "population"))
  expect_true(all(c("rank", "percentile", "z_score") %in%
                    names(rank_countries(snap, gdp_per_capita))))
  cy <- complete_years(data.frame(iso3c = "A", year = c(2000L, 2002L), g = c(1, 3)))
  expect_s3_class(cy, "tbl_df")
  expect_equal(nrow(cy), 3L)
})

test_that("reference and join verbs return their documented shape", {
  expect_named(country_groups("EU"), c("group", "iso3c", "country"))
  expect_type(in_group(c("France", "Japan", "Brazil"), "EU"), "logical")
  expect_length(in_group(c("France", "Japan", "Brazil"), "EU"), 3L)
  cc <- country_codes()
  expect_s3_class(cc, "tbl_df")
  expect_false(anyNA(cc$iso3c))
  expect_equal(anyDuplicated(cc$iso3c), 0L)
  expect_named(wdi_search("CO2 emissions"), c("indicator", "name"))
  expect_warning(d <- distance_between(c("France", "Wakanda"), "Germany"),
                 "did not resolve to a country")
  expect_type(d, "double")
  expect_true(is.na(d[2]))                                   # NA for unmatched
  expect_true(all(c("iso3c", "iso2c", "continent", "region") %in%
                    names(standardize_country(data.frame(n = "France"), n,
                                              warn = FALSE))))
  j <- country_join_all(list(data.frame(country = "Czechia", a = 1),
                             data.frame(country = "Czech Republic", b = 2)),
                        by = "country")
  expect_s3_class(j, "tbl_df")
  expect_true("iso3c" %in% names(j))
  expect_equal(nrow(j), 1L)                                  # reconciled to one
})

test_that("plot and geometry verbs return their documented objects", {
  expect_s3_class(theme_world_map(), "theme")
  expect_s3_class(geom_country_labels(), "Layer")
  q <- world_query(x)
  expect_s3_class(q, "ggsql_query")
  expect_type(unclass(q), "character")
  # suppressWarnings(): wdj_overrides() is deprecated and warns once per
  # session (.frequency = "once"), so a bare call here made the result depend
  # on file order -- whichever file ran first consumed the one-shot, and the
  # other saw nothing. test-features-3.0.0.R wraps its call for this reason.
  o <- suppressWarnings(wdj_overrides())
  expect_type(o, "character")
  expect_false(is.null(names(o)))
  expect_true(isTRUE(clear_wdi_cache()))                     # invisibly TRUE
})

test_that("sf-backed verbs return their documented shape", {
  skip_if_no_sf_geometry()
  expect_s3_class(world_geometry("countries", geometry = "sf"), "sf")
  expect_s3_class(attach_geometry(snap, geometry = "sf"), "sf")
  m <- morans_i(snap, gdp_per_capita, n_perm = 0)
  expect_equal(nrow(m), 1L)
  expect_named(m, c("i", "expected", "n", "n_excluded", "n_links", "p_value",
                    "excluded"))
  # The exclusion report is the point: islands carry no land-border weight, so
  # `n` alone cannot reveal how much of the world sat the analysis out.
  expect_type(m$excluded, "list")
  expect_equal(m$n_excluded, length(m$excluded[[1]]))
  expect_true(m$n_excluded > 0)
  expect_true("JPN" %in% m$excluded[[1]])
  b <- country_borders(region = "Europe")
  expect_named(b, c("iso3c_a", "country_a", "iso3c_b", "country_b"))
  expect_true(all(b$iso3c_a <= b$iso3c_b))                   # canonical order
  nb <- neighbors("France")
  expect_named(nb, c("iso3c", "neighbor", "neighbor_country"))
  expect_equal(nrow(neighbors("Japan")), 0L)                 # island: no border
  l <- locate_country(lon = 2.35, lat = 48.85, add = "country")
  expect_named(l, c("iso3c", "country"))
  expect_equal(l$iso3c, "FRA")
})

test_that("polygon-backed verbs return their documented shape", {
  skip_if_not_installed("maps")
  expect_s3_class(world_geometry("countries", geometry = "polygon"), "tbl_df")
  expect_s3_class(attach_geometry(snap, geometry = "polygon"), "tbl_df")
})

test_that("every convert_country shortcut maps to the scheme its name promises", {
  # `calling_code` was mapped to `genc3c` -- an alpha-3 COUNTRY code -- so
  # to = "calling_code" silently returned "FRA" instead of 33. A shortcut whose
  # name promises one thing and returns another is the worst kind of bug, so
  # pin a known value for each.
  expect_equal(as.numeric(convert_country("France", to = "calling_code")), 33)
  expect_equal(as.numeric(convert_country(c("USA", "JPN"), to = "calling_code",
                                          from = "iso3c")), c(1, 81))
  expect_equal(convert_country("France", to = "iso3c"), "FRA")
  expect_equal(convert_country("France", to = "iso2c"), "FR")
  expect_equal(convert_country("France", to = "currency"), "EUR")
  expect_equal(convert_country("France", to = "tld"), ".fr")
  expect_equal(convert_country("France", to = "continent"), "Europe")
  expect_equal(convert_country("France", to = "region"), "Europe & Central Asia")
  expect_equal(as.numeric(convert_country("France", to = "cown")), 220)
  expect_equal(convert_country("France", to = "country"), "France")
  expect_equal(convert_country("Germany", to = "name_fr"), "Allemagne")
  # A calling code is a number, not a country code: no shortcut should return
  # something that looks like an iso3c unless that is what it promises.
  code_like <- c("calling_code", "currency", "tld", "cown")
  vals <- vapply(code_like, function(k)
    as.character(convert_country("France", to = k, warn = FALSE)), character(1))
  expect_false(any(vals == "FRA"))
})

test_that("every shortcut in convert_dest_map resolves to a real destination", {
  m <- countryatlas:::convert_dest_map()
  cl <- names(countrycode::codelist)
  # Each mapped destination must be a column countrycode actually has.
  expect_true(all(unname(m) %in% cl),
              info = paste("not in codelist:",
                           paste(setdiff(unname(m), cl), collapse = ", ")))
  # And each shortcut must return something for a well-known country.
  for (k in names(m)) {
    v <- convert_country("France", to = k, warn = FALSE)
    expect_length(v, 1L)
  }
})

test_that("the 2.0.0 exports keep their leading argument order", {
  # Positional calls are the part of an API users cannot see changing. 3.0.0
  # deliberately inserted `data` as geom_country_labels()'s second argument --
  # the one break NEWS records -- and an audit against the installed 2.0.0
  # confirmed it is the *only* one: nothing was removed, no argument was
  # dropped, and no other shared argument moved. Nothing pinned that, though:
  # the suite had a single formals() assertion in it. Pin the first three
  # formals of every 2.0.0-era export so a future reordering has to be
  # deliberate rather than accidental.
  expected <- c(
    aggregate_regions = "data, value, by",
    animate_world = "data, fill, time",
    as_ggsql_source = "data, name, format",
    attach_geometry = "data, by, geometry",
    audit_coverage = "data, indicator, by",
    beta_convergence = "data, value",
    bivariate_map = "data, fill_x, fill_y",
    bubble_map = "data, size, color",
    cartogram_map = "data, weight, type",
    check_country_match = "x, origin, custom_match",
    clear_wdi_cache = "disk",
    complete_years = "data, years, value",
    convert_country = "x, to, from",
    correlate_indicators = "data, ..., method",
    country_borders = "scale, region",
    country_codes = "codes",
    country_data = "year, indicator, latest",
    country_groups = "group, as_of",
    country_join = "x, y, by_x",
    country_join_all = "tables, by, origin",
    country_overrides = "extra",
    diff_by_country = "data, value, n",
    dissolve_country = "x, warn",
    distance_between = "a, b, origin",
    dorling_map = "data, weight, fill",
    facet_map = "data, fill, facet",
    flow_map = "data, from, to",
    geom_country_labels = "mapping, data, repel",
    gini = "x, weights, na.rm",
    globe_map = "data, fill, lon",
    growth_rate = "data, value, type",
    in_group = "x, group, origin",
    index_to = "data, value, base_year",
    interactive_map = "data, fill, tooltip",
    join_world = "data, country_col, origin",
    lag_by_country = "data, value, n",
    locate_country = "lon, lat, points",
    morans_i = "data, value, scale",
    neighbors = "x, origin, scale",
    per_capita = "data, value, pop",
    rank_countries = "data, value, within",
    repair_country_names = "x, threshold, origin",
    share_of_world = "data, value, suffix",
    sigma_convergence = "data, value, measure",
    simplify_geometry = "x, keep, ...",
    spike_map = "data, height, max_height",
    spin_globe = "data, fill, lat",
    standardize_country = "data, country_col, origin",
    theil = "x, weights, groups",
    theme_world_map = "base_size, base_family",
    tile_map = "data, fill, label",
    wdi_search = "pattern, field, cache",
    wdj_overrides = "extra",
    world_data = "year, indicator, geometry",
    world_geometry = "what, geometry, scale",
    world_map = "data, fill, style",
    world_query = "fill, source, projection"
  )
  for (fn in names(expected)) {
    got <- paste(utils::head(names(formals(get(fn, envir = asNamespace(
      "countryatlas")))), 3), collapse = ", ")
    expect_equal(got, expected[[fn]], info = fn)
  }
  # And every one of them still exists.
  expect_length(setdiff(names(expected),
                        getNamespaceExports(asNamespace("countryatlas"))), 0L)
})

test_that("every map verb's provenance names the column the caller asked about", {
  # One loop over every verb that carries provenance. The verbs that draw
  # through world_map() with an internal fill -- `.wdj_available`,
  # `.wdj_class`, `.wdj_cluster` -- used to report *that* column, and
  # `.wdj_available` is never NA, so coverage_map()'s provenance said
  # `n_missing = 0` while its own caption said otherwise.
  skip_if_not_installed("maps")
  skip_if_not_installed("ggplot2")
  d <- data.frame(iso3c = c("FRA","DEU","ITA","ESP","POL","NLD"),
                  value = c(10, 20, NA, 40, 15, 55), unc = c(1,2,3,4,5,6),
                  stringsAsFactors = FALSE)
  g <- suppressMessages(attach_geometry(d, geometry = "polygon"))
  pan <- rbind(cbind(g, year = 2000), cbind(g, year = 2001))
  # `na_coverage()` counts *countries*, not rows, and the geometry-attached
  # frames carry every country in the backend's map -- so the invariant that
  # holds for every verb is the count of countries that have a value: five of
  # the six, since ITA is NA.
  cases <- list(
    world_map          = function() world_map(g, value),
    coverage_map       = function() coverage_map(g, value),
    classify_compare   = function() classify_compare(g, value),
    facet_map          = function() facet_map(pan, value, facet = "year"),
    bubble_map         = function() bubble_map(d, value),
    spike_map          = function() spike_map(d, value),
    tile_map           = function() tile_map(d, value),
    value_by_alpha_map = function() value_by_alpha_map(g, value, unc),
    gridded_cartogram  = function() gridded_cartogram(d, value)
  )
  # lisa_map() defaults to contiguity weights, which need sf. The loop asserts
  # a per-verb invariant, so drop just this verb rather than the whole test:
  # the block is guarded for maps, so a machine with maps and no sf reached it.
  if (requireNamespace("sf", quietly = TRUE)) {
    cases$lisa_map <- function() lisa_map(g, value)
  }
  for (nm in names(cases)) {
    p <- suppressWarnings(suppressMessages(cases[[nm]]()))
    prov <- attr(p, "countryatlas_provenance")
    expect_false(is.null(prov), label = paste(nm, "carries provenance"))
    expect_identical(prov$fill, "value", label = paste(nm, "provenance fill"))
    # The coverage must describe the caller's column, not an internal fill such
    # as `.wdj_available` that is never NA and so always reported every country
    # as shown and none as missing.
    expect_equal(prov$coverage$n_shown, 5L, label = paste(nm, "n_shown"))
    expect_equal(prov$coverage$n_missing, prov$coverage$n_total - 5L,
                 label = paste(nm, "n_missing"))
    expect_gt(prov$coverage$n_missing, 0)
  }
})

test_that("a perfect regression fit is reported, not leaked from summary.lm", {
  # summary.lm() warns "essentially perfect fit: summary may be unreliable"
  # when the residual variance is ~0. That reached the caller verbatim: it
  # names neither the verb nor the column, and from convergence_club() it
  # described an internal log-t regression the caller does not know exists.
  iso <- c("USA", "FRA", "CHN", "IND", "BRA", "ZAF")
  # Each country's value is the same geometric ramp times a constant, so every
  # country's growth is identical and the fit has nothing left to explain.
  perfect <- tibble::tibble(
    iso3c = rep(iso, each = 20),
    year = rep(2000:2019, length(iso)),
    v = as.numeric(rep(seq_len(20), length(iso))) *
      rep(c(1, 2, 5, 10, 20, 50), each = 20))

  expect_warning(res <- beta_convergence(perfect, v),
                 class = "countryatlas_perfect_fit")
  # The message must be ours, not base R's.
  w <- tryCatch(beta_convergence(perfect, v), warning = function(w) w)
  expect_false(grepl("essentially perfect fit", conditionMessage(w)))
  # beta is still the fitted slope, and the meaningless columns are still
  # returned rather than blanked -- the warning is what says not to read them.
  expect_true(is.finite(res$beta))
  expect_equal(nrow(res), 1L)

  # The internal log-t fit must not surface at all: its statistic is the only
  # thing convergence_club() reports, and a degenerate one already returns NA.
  expect_no_warning(suppressWarnings({
    cl <- withCallingHandlers(
      convergence_club(perfect, v),
      warning = function(w) {
        if (grepl("essentially perfect fit", conditionMessage(w))) {
          stop("base R's perfect-fit warning leaked from log_t_stat()")
        }
        invokeRestart("muffleWarning")
      })
  }))

  # An ordinary noisy panel says nothing.
  set.seed(20260909)
  noisy <- perfect
  noisy$v <- noisy$v * exp(stats::rnorm(nrow(noisy), 0, 0.05))
  expect_silent(force(beta_convergence(noisy, v)))
})

test_that("every world_geometry() what returns a column named `geometry`", {
  # Two of the six returned `x`: st_as_sf() on a bare sfc names the column
  # after the object, and "coastline" and "ocean" are both built by unioning
  # into one shape. The name is part of the documented return contract, so code
  # written against the other four broke on exactly those two.
  skip_if_no_sf_geometry()
  for (what in c("countries", "centroids", "coastline", "borders",
                 "graticule", "ocean")) {
    g <- suppressMessages(suppressWarnings(
      world_geometry(what, geometry = "sf")))
    expect_identical(attr(g, "sf_column"), "geometry",
                     label = paste("world_geometry", what, "geometry column"))
    expect_true("geometry" %in% names(g))
  }
})
