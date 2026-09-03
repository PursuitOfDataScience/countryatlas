# 2.1.0: the bug fixes and the Wave 1 honesty features.

snap <- countryatlas::world_snapshot$countries

poly_df <- function() {
  skip_if_not_installed("maps")
  attach_geometry(snap, geometry = "polygon")
}
sf_df <- function() {
  skip_if_no_sf_geometry()
  attach_geometry(snap, geometry = "sf")
}
# Build *and render*: ggplot_build() misses draw-time failures (facet/coord
# incompatibilities only surface in ggplot_gtable()), which is exactly how the
# first cut of projection_compare() passed its own test while being unplottable.
renders <- function(p) {
  expect_s3_class(p, "ggplot")
  expect_silent_grob <- ggplot2::ggplotGrob(p)
  expect_s3_class(expect_silent_grob, "gtable")
  invisible(p)
}

# --- Bug: a categorical fill died at print time on a hardcoded viridis_c -------

test_that("cartogram_map and dorling_map accept a categorical fill", {
  skip_if_not_installed("cartogram")
  d <- sf_df()
  # Each of these used to reach ggplot2's bare "Discrete value supplied to a
  # continuous scale" at *print* time, long after the call that caused it.
  renders(cartogram_map(d, population, fill = continent))
  renders(dorling_map(d, population, fill = continent))
  renders(cartogram_map(d, population, type = "noncontiguous", fill = continent))
  # ...and the numeric path still gets a continuous scale.
  renders(cartogram_map(d, population, fill = gdp_per_capita))
})

test_that("tile_map accepts a categorical fill", {
  # The grid cannot place a few snapshot countries; that has its own test.
  renders(suppressWarnings(tile_map(snap, continent)))
  renders(suppressWarnings(tile_map(snap, gdp_per_capita)))
  renders(suppressWarnings(tile_map(snap, income)))
})

test_that("auto_fill_scale picks the scale from the column type", {
  expect_s3_class(countryatlas:::auto_fill_scale(c(1, 2, 3), "x"), "ScaleContinuous")
  expect_s3_class(countryatlas:::auto_fill_scale(c("a", "b"), "x"), "ScaleDiscrete")
  expect_s3_class(countryatlas:::auto_fill_scale(factor(c("a", "b")), "x"), "ScaleDiscrete")
})

# --- Bug: geom_country_labels(data =) collided with the hardcoded data --------

test_that("geom_country_labels takes a data argument", {
  mapdf <- poly_df()
  keep <- c("USA", "CHN", "IND", "BRA")
  # "formal argument \"data\" matched by multiple actual arguments" -- `data`
  # was hard-wired in the layer call while `...` forwarded to the same call.
  renders(world_map(mapdf, gdp_per_capita) +
            geom_country_labels(data = subset(mapdf, iso3c %in% keep)))
  renders(world_map(mapdf, gdp_per_capita) +
            geom_country_labels(data = function(d) subset(d, iso3c %in% keep)))
  renders(world_map(mapdf, gdp_per_capita) +
            geom_country_labels(data = ~ subset(.x, iso3c %in% keep)))
  renders(world_map(mapdf, gdp_per_capita) + geom_country_labels())
  # ... and `...` still reaches the text geom.
  renders(world_map(mapdf, gdp_per_capita) +
            geom_country_labels(data = subset(mapdf, iso3c %in% keep),
                                size = 4, colour = "white"))
})

test_that("geom_country_labels labels only the countries it was given", {
  mapdf <- poly_df()
  keep <- c("USA", "CHN", "IND", "BRA")
  p <- world_map(mapdf, gdp_per_capita) +
    geom_country_labels(data = subset(mapdf, iso3c %in% keep), repel = FALSE)
  drawn <- ggplot2::ggplot_build(p)$data[[2]]
  expect_equal(nrow(drawn), length(keep))
})

test_that("an explicit data frame without geometry is named, not silently empty", {
  mapdf <- poly_df()
  expect_error(
    ggplot2::ggplotGrob(world_map(mapdf, gdp_per_capita) +
                          geom_country_labels(data = snap)),
    "long"
  )
})

# --- Bug: locate_country(points=) leaked a raw sf error -----------------------

test_that("locate_country names a bad points argument", {
  skip_if_no_sf_geometry()
  expect_error(locate_country(points = data.frame(lon = 1, lat = 1)),
               "must be an .*sf.* POINT object")
  expect_error(locate_country(points = data.frame(lon = 1, lat = 1)), "st_as_sf")
  expect_error(locate_country(points = "nope"), "must be an .*sf.* POINT object")
  expect_error(locate_country(points = 42), "lon")
})

# --- Bug: world_map(projection = "mercator") drew a sliver over a grey slab ---

test_that("mercator is clipped to a usable latitude band", {
  d <- sf_df()
  expect_equal(countryatlas:::wdj_lat_limits("mercator"), c(-85.05113, 85.05113))
  expect_null(countryatlas:::wdj_lat_limits("equal_earth"))
  # Unclipped, Natural Earth's Antarctica reaches -90 where Mercator's y goes to
  # infinity: PROJ clamped rather than erroring and the panel came out three
  # times taller than the world is wide, the inhabited part a sliver at the top.
  b <- ggplot2::ggplot_build(world_map(d, gdp_per_capita, projection = "mercator"))
  pp <- b$layout$panel_params[[1]]
  aspect <- diff(pp$y_range) / diff(pp$x_range)
  expect_lt(aspect, 1.6)
})

# --- morans_i reports what it dropped ----------------------------------------

test_that("morans_i reports the countries it excluded", {
  skip_if_no_sf_geometry()
  out <- morans_i(snap, gdp_per_capita, n_perm = 0)
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

# --- na_style / footnote / classification_report ------------------------------

test_that("na_style changes how missing countries are drawn", {
  mapdf <- poly_df()
  for (ns in c("grey", "hatched", "outline", "omit")) {
    renders(world_map(mapdf, gdp_per_capita, style = "quantile", na_style = ns))
  }
  # Names the argument, not R's anonymous "'arg' should be one of".
  expect_error(world_map(mapdf, gdp_per_capita, na_style = "nope"), "`na_style`")
})

test_that("na_style = 'omit' drops the no-data countries from the drawn data", {
  mapdf <- poly_df()
  kept <- ggplot2::ggplot_build(
    world_map(mapdf, gdp_per_capita, na_style = "omit"))$data[[1]]
  all_rows <- ggplot2::ggplot_build(
    world_map(mapdf, gdp_per_capita, na_style = "grey"))$data[[1]]
  expect_lt(nrow(kept), nrow(all_rows))
})

test_that("na_style = 'hatched' adds a layer when ggpattern is available", {
  skip_if_not_installed("ggpattern")
  mapdf <- poly_df()
  plain <- world_map(mapdf, gdp_per_capita, na_style = "grey")
  hatched <- world_map(mapdf, gdp_per_capita, na_style = "hatched")
  expect_equal(length(hatched$layers), length(plain$layers) + 1L)
})

test_that("na_style = 'hatched' degrades loudly when ggpattern is missing", {
  mapdf <- poly_df()
  # Asking for hatching and silently getting grey is the one thing worse than
  # not offering hatching, so the fallback announces itself and still draws.
  testthat::local_mocked_bindings(
    has_pkg = function(pkg) if (identical(pkg, "ggpattern")) FALSE else
      isTRUE(requireNamespace(pkg, quietly = TRUE))
  )
  rlang::local_options(rlib_message_verbosity = "verbose")
  expect_message(world_map(mapdf, gdp_per_capita, na_style = "hatched"),
                 "ggpattern")
  p <- suppressMessages(world_map(mapdf, gdp_per_capita, na_style = "hatched"))
  expect_s3_class(ggplot2::ggplotGrob(p), "gtable")
  expect_equal(length(p$layers),
               length(world_map(mapdf, gdp_per_capita)$layers))
})

test_that("na_style = 'hatched' adds nothing when there is nothing missing", {
  mapdf <- poly_df()
  full <- mapdf; full$gdp_per_capita <- 1
  hatched <- world_map(full, gdp_per_capita, na_style = "hatched")
  plain <- world_map(full, gdp_per_capita)
  # "adds nothing" is a layer-count claim, as the two sibling tests above
  # assert. A gtable comes back whether or not a spurious hatch layer was added.
  expect_equal(length(hatched$layers), length(plain$layers))
  expect_s3_class(ggplot2::ggplotGrob(hatched), "gtable")
})

test_that("footnote = 'auto' states coverage and cannot overstate it", {
  mapdf <- poly_df()
  cap <- world_map(mapdf, gdp_per_capita, footnote = "auto")$labels$caption
  expect_match(cap, "countries shown")
  cov <- countryatlas:::na_coverage(mapdf, "gdp_per_capita")
  expect_match(cap, as.character(cov$n_shown), fixed = TRUE)
  expect_match(cap, as.character(cov$n_missing), fixed = TRUE)
  expect_equal(cov$n_shown + cov$n_missing, cov$n_total)
  # a complete column says so rather than reporting "0 missing"
  full <- mapdf; full$gdp_per_capita <- 1
  expect_match(world_map(full, gdp_per_capita, footnote = "auto")$labels$caption,
               "All .* countries shown")
  # a literal string is used as given
  expect_equal(world_map(mapdf, gdp_per_capita, footnote = "Source: WDI")$labels$caption,
               "Source: WDI")
  expect_error(world_map(mapdf, gdp_per_capita, footnote = 42), "single string")
})

test_that("na_coverage counts countries, not polygon vertices", {
  mapdf <- poly_df()
  cov <- countryatlas:::na_coverage(mapdf, "gdp_per_capita")
  expect_lt(cov$n_total, 400)          # ~240 map regions, not ~99,000 vertices
  # Distinct *coded* countries: a geometry row with no iso3c is a fragment the
  # basemap has and the codelist does not, and is not counted as a country.
  expect_equal(cov$n_total,
               dplyr::n_distinct(stats::na.omit(mapdf$iso3c)))
  expect_equal(cov$n_missing, length(cov$missing_iso3c))
})

test_that("classification_report counts countries per class", {
  mapdf <- poly_df()
  p <- world_map(mapdf, gdp_per_capita, style = "quantile",
                 classification_report = TRUE)
  rep <- attr(p, "countryatlas_classification")
  expect_s3_class(rep, "tbl_df")
  expect_named(rep, c("method", "class", "n", "share"))
  expect_equal(unique(rep$method), "quantile")
  # quantile bins are near-equal by construction -- that is the check that would
  # have caught the vertex-weighted-breaks bug fixed in 2.0.0.
  expect_lte(max(rep$n) - min(rep$n), 2L)
  expect_equal(sum(rep$share), 1, tolerance = 1e-9)
  expect_null(attr(world_map(mapdf, gdp_per_capita), "countryatlas_classification"))
})

# --- coverage_map / classify_compare / value_by_alpha_map ---------------------

test_that("coverage_map maps availability", {
  mapdf <- poly_df()
  p <- coverage_map(mapdf, gdp_per_capita)
  renders(p)
  expect_match(p$labels$caption, "report a value")
  expect_match(p$labels$title, "Coverage of gdp_per_capita")
  renders(coverage_map(mapdf, co2_per_capita, title = "Custom"))
  expect_error(coverage_map(mapdf, not_a_column), "not found")
})

test_that("classify_compare reports how unbalanced each method is", {
  mapdf <- poly_df()
  # "jenks" falls back to quantile breaks, with a warning, when classInt is
  # absent -- which is the documented degraded path and is exercised under
  # _R_CHECK_DEPENDS_ONLY_. The assertions below hold either way.
  p <- suppressWarnings(classify_compare(mapdf, gdp_per_capita))
  renders(p)
  rep <- attr(p, "countryatlas_classification")
  expect_setequal(unique(rep$method), c("quantile", "jenks", "equal", "pretty"))
  # The point of the feature: equal-interval piles most countries into one
  # class on a skewed indicator, quantile does not.
  worst <- function(m) max(rep$n[rep$method == m]) / sum(rep$n[rep$method == m])
  expect_lt(worst("quantile"), 0.3)
  expect_gt(worst("equal"), 0.7)
  expect_error(classify_compare(mapdf, gdp_per_capita, methods = "nope"),
               "Unknown classification method")
  expect_error(classify_compare(mapdf, country), "numeric")
})

test_that("classify_breaks produces n+1 finite, increasing breaks", {
  x <- snap$gdp_per_capita[!is.na(snap$gdp_per_capita)]
  for (m in c("quantile", "jenks", "equal", "pretty", "sd")) {
    # Without classInt, "jenks" warns and returns quantile breaks; these are
    # structural properties that must hold on either path.
    br <- suppressWarnings(countryatlas:::classify_breaks(x, m, 5))
    expect_true(all(is.finite(br)), info = m)
    expect_false(is.unsorted(br), info = m)
    expect_gt(length(br), 2L)
  }
})

test_that("jenks really is jenks when classInt is available", {
  # The structural assertions above are satisfied by quantile breaks too, so
  # without this the jenks case passes vacuously wherever classInt is missing
  # -- which is exactly where the fallback silently substitutes quantile.
  skip_if_not_installed("classInt")
  x <- snap$gdp_per_capita[!is.na(snap$gdp_per_capita)]
  jen <- countryatlas:::classify_breaks(x, "jenks", 5)
  quant <- countryatlas:::classify_breaks(x, "quantile", 5)
  expect_false(isTRUE(all.equal(jen, quant)))
  expect_silent(countryatlas:::classify_breaks(x, "jenks", 5))
})

test_that("value_by_alpha_map maps the equalising variable to opacity", {
  mapdf <- poly_df()
  renders(value_by_alpha_map(mapdf, gdp_per_capita, population))
  renders(value_by_alpha_map(mapdf, gdp_per_capita, population, transform = "log10"))
  renders(value_by_alpha_map(mapdf, gdp_per_capita, population, transform = "identity"))
  expect_error(value_by_alpha_map(mapdf, gdp_per_capita, population,
                                  alpha_range = c(2, 3)), "alpha_range")
  expect_error(value_by_alpha_map(mapdf, gdp_per_capita, population,
                                  alpha_range = c(0.9, 0.1)), "increasing")
  expect_error(value_by_alpha_map(mapdf, gdp_per_capita, country), "numeric")
})

test_that("rescale01 survives a constant vector", {
  expect_equal(countryatlas:::rescale01(c(1, 3, 5)), c(0, 0.5, 1))
  expect_equal(countryatlas:::rescale01(rep(2, 4)), rep(1, 4))
  expect_equal(countryatlas:::rescale01(c(NA, NA)), c(1, 1))
})

# --- projections ---------------------------------------------------------------

test_that("projection_info covers every projection wdj_crs can build", {
  info <- projection_info()
  expect_setequal(info$projection, countryatlas:::wdj_projections())
  expect_named(info, c("projection", "family", "property", "equal_area",
                       "conformal", "note", "proj4"))
  # The property flags have to agree with the PROJ string actually emitted.
  expect_true(info$equal_area[info$projection == "equal_earth"])
  expect_false(info$equal_area[info$projection == "mercator"])
  expect_true(info$conformal[info$projection == "mercator"])
  expect_match(info$proj4[info$projection == "equal_earth"], "+proj=eqearth",
               fixed = TRUE)
  expect_equal(nrow(projection_info("mercator")), 1L)
  expect_error(projection_info("nope"), "Unknown projection")
})

test_that("projection_compare draws one panel per projection", {
  d <- sf_df()
  p <- projection_compare(d, gdp_per_capita, style = "quantile")
  renders(p)
  built <- ggplot2::ggplot_build(p)
  expect_equal(length(unique(built$data[[1]]$PANEL)), 4L)
  renders(projection_compare(d, gdp_per_capita, projections = "mollweide"))
  renders(projection_compare(d, gdp_per_capita, labeller = "property"))
  expect_error(projection_compare(d, gdp_per_capita, projections = "nope"),
               "Unknown projection")
  expect_error(projection_compare(d, gdp_per_capita, projections = character(0)),
               "at least one")
})

test_that("projection_compare rejects the polygon backend rather than ignoring it", {
  skip_if_not_installed("maps")
  # Without sf the need_pkg() guard fires first and says so instead; that is a
  # different (and correct) refusal, not the one under test here.
  skip_if_not_installed("sf")
  expect_error(projection_compare(poly_df(), gdp_per_capita), "needs an sf frame")
})

test_that("projection_compare leaves the s2 setting as it found it", {
  d <- sf_df()
  before <- sf::sf_use_s2()
  invisible(ggplot2::ggplotGrob(projection_compare(d, gdp_per_capita)))
  expect_equal(sf::sf_use_s2(), before)
})

test_that("tissot_map draws equal-area circles on an equal-area projection", {
  skip_if_no_sf_geometry()
  renders(tissot_map("equal_earth"))
  renders(tissot_map("mercator", spacing = 45))
  expect_error(tissot_map("equal_earth", spacing = 0), "spacing")
  expect_error(tissot_map("equal_earth", radius_km = 0), "radius_km")
  expect_error(tissot_map("equal_earth", max_lat = 95), "max_lat")
})

test_that("the Earth radius is one constant, not three literals", {
  expect_equal(countryatlas:::EARTH_RADIUS_KM, 6371.0088)
  # Deparse the functions rather than reading R/geometry.R: the source tree is
  # not there under `R CMD check`, and the thing worth asserting is that these
  # three all reach for the shared constant, not that one file happens to
  # contain the number once.
  bodies <- vapply(
    list(countryatlas:::ring_area_km2, countryatlas:::haversine_km,
         countryatlas::tissot_map),
    function(f) paste(deparse(f), collapse = " "), character(1))
  expect_false(any(grepl("6371", bodies, fixed = TRUE)))
  expect_true(all(grepl("EARTH_RADIUS_KM", bodies, fixed = TRUE)))
})

# --- provenance ----------------------------------------------------------------

test_that("map_provenance reports what went into a map", {
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

test_that("CITATION parses and credits the data sources, not just the package", {
  path <- system.file("CITATION", package = "countryatlas")
  skip_if(!nzchar(path), "CITATION not installed")
  cit <- utils::readCitationFile(path)
  expect_gt(length(cit), 4L)
  txt <- paste(format(cit, style = "text"), collapse = " ")
  expect_match(txt, "countrycode")
  expect_match(txt, "World Bank")
  expect_match(txt, "Natural Earth")
  expect_match(txt, "Equal Earth")
})

# --- cartogramR ------------------------------------------------------------------

test_that("cartogram_map(type = 'flow') uses cartogramR", {
  skip_if_no_sf_geometry()
  skip_if_not_installed("cartogramR")
  d <- sf_df()
  renders(suppressWarnings(cartogram_map(d, population, type = "flow")))
})

test_that("each cartogram type gates on the package it actually needs", {
  # "flow" must not demand `cartogram`, nor the others `cartogramR`.
  src <- paste(deparse(cartogram_map), collapse = " ")
  expect_match(src, "cartogramR")
  expect_match(src, 'identical\\(type, "flow"\\)')
})
