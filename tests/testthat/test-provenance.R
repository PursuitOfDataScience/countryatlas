# --- provenance ----------------------------------------------------------------

test_that("map_provenance reports what went into a map", {
  skip_slow_on_cran()
  mapdf <- poly_df()
  p <- world_map(mapdf, gdp_per_capita, style = "quantile", n_bins = 4,
                 na_style = "outline")
  prov <- map_provenance(p)
  expect_s3_class(prov, "countryatlas_provenance")
  expect_equal(prov$fill, "gdp_per_capita")
  expect_equal(prov$style, "quantile")
  expect_equal(prov$backend, "polygon")
  expect_equal(prov$n_bins, 4L)
  expect_equal(prov$na_style, "outline")
  expect_equal(prov$countryatlas, as.character(utils::packageVersion("countryatlas")))
  expect_equal(prov$snapshot_year, countryatlas::world_snapshot$year)
  expect_length(prov$breaks[[1]], 5L)            # n_bins + 1
  # cli headings go to the message stream, the rest to stdout -- same split
  # print.countryatlas_coverage is tested through.
  msg <- capture.output(out <- capture.output(print(prov)), type = "message")
  both <- paste(c(msg, out), collapse = "\n")
  expect_match(both, "countryatlas map provenance")
  expect_match(both, "gdp_per_capita")
  expect_match(both, "quantile")
  expect_match(both, "breaks")
})

test_that("map_provenance records the sf projection", {
  skip_slow_on_cran()
  d <- sf_df()
  prov <- map_provenance(world_map(d, gdp_per_capita, projection = "robinson"))
  expect_equal(prov$backend, "sf")
  expect_equal(prov$projection, "robinson")
})

test_that("map_provenance works on a data frame and refuses anything else", {
  mapdf <- poly_df()
  prov <- map_provenance(mapdf, gdp_per_capita)
  expect_equal(prov$fill, "gdp_per_capita")
  expect_true(prov$n_missing > 0)
  expect_true(is.na(prov$style))
  expect_error(map_provenance(mapdf), "value.* is required")
  expect_error(map_provenance(42), "no countryatlas provenance")
})

# --- provenance is a promise, so it has to hold for every verb ----------------------

test_that("every map verb carries provenance", {
  skip_slow_on_cran()
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
  skip_slow_on_cran()
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

test_that("map_provenance surfaces every field the verbs record", {
  skip_slow_on_cran()
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
  skip_slow_on_cran()
  pr <- map_provenance(world_map(poly_df(), gdp_per_capita))
  # Subsetting a tibble keeps its class, so the print method still dispatches
  # with most columns absent -- which used to fail on `if (!is.na(NULL))`.
  expect_no_error(capture.output(print(pr[, c("fill", "style")]),
                                 type = "message"))
  expect_no_error(capture.output(print(pr[, "fill"]), type = "message"))
  expect_no_error(capture.output(print(pr), type = "message"))
})

test_that("every data-bearing map verb carries readable provenance", {
  skip_slow_on_cran()
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

test_that("map_provenance carries the denominator, not just the numerator", {
  skip_slow_on_cran()
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
