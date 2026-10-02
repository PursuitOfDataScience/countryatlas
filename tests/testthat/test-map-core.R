test_that("auto_fill_scale picks the scale from the column type", {
  expect_s3_class(countryatlas:::auto_fill_scale(c(1, 2, 3), "x"), "ScaleContinuous")
  expect_s3_class(countryatlas:::auto_fill_scale(c("a", "b"), "x"), "ScaleDiscrete")
  expect_s3_class(countryatlas:::auto_fill_scale(factor(c("a", "b")), "x"), "ScaleDiscrete")
})

test_that("an explicit data frame without geometry is named, not silently empty", {
  skip_slow_on_cran()
  mapdf <- poly_df()
  expect_error(
    ggplot2::ggplotGrob(world_map(mapdf, gdp_per_capita) +
                          geom_country_labels(data = snap)),
    "long"
  )
})

# --- na_style / footnote / classification_report ------------------------------

test_that("na_style changes how missing countries are drawn", {
  skip_slow_on_cran()
  mapdf <- poly_df()
  for (ns in c("grey", "hatched", "outline", "omit")) {
    renders(world_map(mapdf, gdp_per_capita, style = "quantile", na_style = ns))
  }
  # Names the argument, not R's anonymous "'arg' should be one of".
  expect_error(world_map(mapdf, gdp_per_capita, na_style = "nope"), "`na_style`")
})

test_that("na_style = 'omit' drops the no-data countries from the drawn data", {
  skip_slow_on_cran()
  mapdf <- poly_df()
  kept <- ggplot2::ggplot_build(
    world_map(mapdf, gdp_per_capita, na_style = "omit"))$data[[1]]
  all_rows <- ggplot2::ggplot_build(
    world_map(mapdf, gdp_per_capita, na_style = "grey"))$data[[1]]
  expect_lt(nrow(kept), nrow(all_rows))
})

test_that("na_style = 'hatched' adds a layer when ggpattern is available", {
  skip_slow_on_cran()
  skip_if_not_installed("ggpattern")
  skip_if_not_installed("sf")      # gridpattern draws the stripes with sf
  mapdf <- poly_df()
  plain <- world_map(mapdf, gdp_per_capita, na_style = "grey")
  hatched <- world_map(mapdf, gdp_per_capita, na_style = "hatched")
  expect_equal(length(hatched$layers), length(plain$layers) + 1L)
})

test_that("na_style = 'hatched' clips its stripes once, not once per polygon", {
  skip_slow_on_cran()
  skip_if_not_installed("ggpattern")
  skip_if_not_installed("sf")
  mapdf <- poly_df()
  # gridpattern clips a fresh set of stripes to every group. One group per
  # polygon was 169 clips for co2_per_capita's no-data countries, and a world
  # map took 29s to print; one group, each polygon a subgroup, is one clip.
  p <- world_map(mapdf, co2_per_capita, na_style = "hatched")
  i <- which(vapply(p$layers, function(l) inherits(l$geom, "GeomPolygonPattern"),
                    logical(1)))
  expect_length(i, 1L)
  ld <- ggplot2::layer_data(p, i)
  expect_length(unique(ld$group), 1L)
  expect_gt(length(unique(ld$subgroup)), 100L)
  expect_s3_class(ggplot2::ggplotGrob(p), "gtable")
})

test_that("na_style = 'hatched' degrades loudly when ggpattern is missing", {
  skip_slow_on_cran()
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

test_that("na_style = 'hatched' degrades loudly when sf cannot be loaded", {
  skip_slow_on_cran()
  skip_if_not_installed("ggpattern")
  mapdf <- poly_df()
  # gridpattern clips the stripes with sf, but only when the map is drawn.
  # With sf installed and unloadable (its system libraries off the library
  # path) the plot built and then failed on print, which is how R CMD build
  # died weaving the honest-maps vignette. Now it is grey, and says so.
  testthat::local_mocked_bindings(
    has_pkg = function(pkg) if (identical(pkg, "sf")) FALSE else
      isTRUE(requireNamespace(pkg, quietly = TRUE))
  )
  rlang::local_options(rlib_message_verbosity = "verbose")
  expect_message(world_map(mapdf, gdp_per_capita, na_style = "hatched"),
                 "cannot be loaded")
  p <- suppressMessages(world_map(mapdf, gdp_per_capita, na_style = "hatched"))
  expect_s3_class(ggplot2::ggplotGrob(p), "gtable")
  expect_equal(length(p$layers),
               length(world_map(mapdf, gdp_per_capita)$layers))
})

test_that("na_style = 'hatched' adds nothing when there is nothing missing", {
  skip_slow_on_cran()
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
  skip_slow_on_cran()
  mapdf <- poly_df()
  cap <- world_map(mapdf, gdp_per_capita, footnote = "auto")$labels$caption
  expect_match(cap, "countries shown")
  cov <- countryatlas:::na_coverage(mapdf, "gdp_per_capita")
  expect_match(cap, as.character(cov$n_shown), fixed = TRUE)
  expect_match(cap, as.character(cov$n_missing), fixed = TRUE)
  expect_equal(cov$n_shown + cov$n_missing, cov$n_total)
  # a complete column says so rather than reporting "0 missing" -- here every
  # country on the basemap; Gibraltar, in the data with no polygon, is drawn
  # nowhere and counted.
  full <- mapdf; full$gdp_per_capita <- 1
  attr(full, "countryatlas_unplaced") <- NULL
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
  skip_slow_on_cran()
  mapdf <- poly_df()
  p <- world_map(mapdf, gdp_per_capita, style = "quantile",
                 classification_report = TRUE)
  rep <- attr(p, "countryatlas_classification")
  expect_s3_class(rep, "tbl_df")
  expect_named(rep, c("method", "class", "n", "share", "gvf", "tai"))
  expect_true(all(rep$gvf > 0 & rep$gvf <= 1))
  expect_equal(unique(rep$method), "quantile")
  # quantile bins are near-equal by construction -- that is the check that would
  # have caught the vertex-weighted-breaks bug fixed in 2.0.0.
  expect_lte(max(rep$n) - min(rep$n), 2L)
  expect_equal(sum(rep$share), 1, tolerance = 1e-9)
  expect_null(attr(world_map(mapdf, gdp_per_capita), "countryatlas_classification"))
})

# --- formatted binned legends ---------------------------------------------------

test_that("binned style builds with SI-formatted labels", {
  skip_slow_on_cran()
  skip_if_not_installed("scales")
  # The shared formatter renders 4e+06 as "4M".
  fmt <- countryatlas:::scales_format()
  expect_equal(unname(fmt(c(4e6, 2e9))), c("4M", "2B"))

  mapdf <- attach_geometry(world_snapshot$countries, geometry = "polygon")
  p <- world_map(mapdf, population, style = "binned")
  expect_s3_class(p, "ggplot")
  expect_silent(ggplot2::ggplot_build(p))
})

test_that("world_map(disputes) marks and annotates", {
  skip_slow_on_cran()
  mapdf <- poly_df()
  plain <- world_map(mapdf, gdp_per_capita)
  marked <- world_map(mapdf, gdp_per_capita, disputes = "mark")
  renders(marked)
  expect_equal(length(marked$layers), length(plain$layers) + 1L)
  expect_match(marked$labels$caption, "Disputed territories")
})

test_that("world_map(uncertainty) draws a VSUP with a complete legend", {
  skip_slow_on_cran()
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

test_that("a map of imputed data says so in the caption", {
  mapdf <- poly_df()
  mapdf$gdp_imputed <- FALSE
  mapdf$gdp_imputed[mapdf$iso3c == "FRA"] <- TRUE
  cap <- world_map(mapdf, gdp_per_capita)$labels$caption
  expect_match(cap, "interpolated")
})

test_that("world_map(engine = 'tmap') renders through tmap", {
  skip_slow_on_cran()
  skip_if_not_installed("tmap")
  skip_if_no_sf_geometry()
  expect_s3_class(world_map(sf_df(), gdp_per_capita, engine = "tmap"), "tmap")
  expect_error(world_map(poly_df(), gdp_per_capita, engine = "tmap"),
               "needs an sf frame")
})

# --- interactions between world_map()'s new arguments -------------------------------

test_that("the new world_map arguments combine without breaking each other", {
  skip_slow_on_cran()
  mapdf <- poly_df()
  set.seed(1)
  mapdf$se <- abs(stats::rnorm(nrow(mapdf))) * mapdf$gdp_per_capita * 0.3
  grid <- expand.grid(na_style = c("grey", "hatched", "outline", "omit"),
                      disputes = c("ignore", "mark"), unc = c(FALSE, TRUE),
                      stringsAsFactors = FALSE)
  for (i in seq_len(nrow(grid))) {
    g <- grid[i, ]
    args <- list(data = mapdf, fill = rlang::sym("gdp_per_capita"),
                 na_style = g$na_style,
                 disputes = g$disputes, footnote = "auto")
    # `style` only when no uncertainty column is given: a value-suppressing
    # palette sets its own classes, so passing both now reports that `style`
    # does not apply -- correct, and tested on its own.
    if (g$unc) args$uncertainty <- rlang::sym("se") else args$style <- "quantile"
    expect_s3_class(ggplot2::ggplotGrob(do.call(world_map, args)), "gtable")
  }
})

test_that("a VSUP on a categorical fill is refused with useful advice", {
  skip_slow_on_cran()
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
  skip_slow_on_cran()
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

test_that("a VSUP counts coverage on both columns, not just the fill", {
  skip_slow_on_cran()
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

  # Without `uncertainty`, coverage is the fill column exactly as before
  # (with the small states left out, which a VSUP does not draw).
  p2 <- world_map(m, gdp_per_capita, footnote = "auto", small_states = "none")
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
  skip_slow_on_cran()
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

test_that("coverage does not count an uncoded geometry row as a country", {
  skip_slow_on_cran()
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
  p <- world_map(m, gdp_per_capita, footnote = "auto", small_states = "none")
  expect_match(p$labels$caption,
               paste0(cov$n_missing, " missing"), fixed = TRUE)
})

test_that("world_map says when it is handed a panel", {
  skip_slow_on_cran()
  # attach_geometry() joins a panel deliberately -- facet_map() and
  # animate_world() are built on it -- so a multi-year frame reaching a single
  # static map draws each country once per year and lets the last row win,
  # silently, with a caption that still counts each country once.
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

test_that("hatching and dispute marks do not discard the projection", {
  skip_slow_on_cran()
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

test_that("n_bins means the same thing in every binned style", {
  skip_slow_on_cran()
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
  skip_slow_on_cran()
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

test_that("every world_map style draws on the tmap engine", {
  skip_slow_on_cran()
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
  br <- attr(countryatlas:::apply_binned_fill(mk(1:12), "v", "quantile", 4), "breaks")
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

test_that("the coverage caption reads as English at every size", {
  skip_slow_on_cran()
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

test_that("bivariate_map refuses a column it cannot classify", {
  skip_slow_on_cran()
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

test_that("the tmap engine honours projection and names what it cannot do", {
  skip_slow_on_cran()
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

test_that("the tmap engine honours na_label", {
  skip_slow_on_cran()
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

test_that("a multi-element na_label warns but does not error the legend", {
  skip_slow_on_cran()
  # There is one NA key, so discrete_na_labels() takes the first element -- that
  # tolerance is deliberate (a length-1 NA means "leave the default formatter
  # alone", and a length > 1 value must not reach a length-1 condition). It used
  # to happen in silence; now it says so, while title/legend, which have no such
  # contract, error like world_query()'s do.
  mapdf <- attach_geometry(snap, geometry = "polygon")
  expect_warning(
    p <- world_map(mapdf, gdp_per_capita, style = "quantile",
                   na_label = c("No data", "ignored")),
    "labels one key")
  expect_s3_class(p, "ggplot")
  expect_no_error(ggplot2::ggplot_build(p))
  expect_error(world_map(mapdf, gdp_per_capita, title = c("a", "b")),
               "must be a single value")
  expect_error(world_map(mapdf, gdp_per_capita, legend = c("a", "b")),
               "must be a single value")
  # NULL / NA keep the default formatter.
  expect_no_error(ggplot2::ggplot_build(
    world_map(mapdf, gdp_per_capita, style = "quantile", na_label = NA)))
})

test_that('style = "categorical" names the offending numeric column', {
  skip_slow_on_cran()
  mapdf <- attach_geometry(snap, geometry = "polygon")
  # ggplot2 used to raise "Continuous value supplied to a discrete scale" at
  # build time, naming neither the column nor the style.
  expect_error(world_map(mapdf, gdp_per_capita, style = "categorical"),
               class = "countryatlas_error")
  expect_error(world_map(mapdf, gdp_per_capita, style = "categorical"),
               "categorical")
  if (requireNamespace("mapproj", quietly = TRUE)) {
    expect_error(globe_map(snap, gdp_per_capita, backend = "polygon",
                           style = "categorical"),
                 class = "countryatlas_error")
  }
  # A discrete column is still fine.
  expect_no_error(ggplot2::ggplot_build(
    world_map(mapdf, continent, style = "categorical")))
})

test_that("bivariate_map does not leak biscale's missing-values warning", {
  skip_slow_on_cran()
  skip_if_no_sf_geometry()
  skip_if_not_installed("biscale")
  sfd <- attach_geometry(snap, geometry = "sf")
  expect_true(anyNA(sfd$gdp_per_capita) || anyNA(sfd$life_expectancy))
  expect_no_warning(bivariate_map(sfd, gdp_per_capita, life_expectancy))
})

test_that("classInt and the base fallback agree on quantile breaks", {
  # A result that changes with which optional package is installed is a bug;
  # for the quantile style these two paths must produce identical breaks.
  x <- countryatlas::world_snapshot$countries$gdp_per_capita
  x <- x[is.finite(x)]
  with_ci <- countryatlas:::compute_breaks(x, "quantile", 5)
  testthat::local_mocked_bindings(
    has_pkg = function(pkg) {
      if (identical(pkg, "classInt")) FALSE
      else isTRUE(requireNamespace(pkg, quietly = TRUE))
    }
  )
  expect_equal(countryatlas:::compute_breaks(x, "quantile", 5), with_ci)
})

test_that("world_map stays silent across the cross-product of its arguments", {
  skip_slow_on_cran()
  # Coverage of the verb was not coverage of the contract: the hatched/disputes
  # message fired only when `na_style` and `disputes` were passed *together*,
  # and world_map() was already in the silence block -- with neither.
  skip_if_no_sf_geometry()
  snap <- countryatlas::world_snapshot$countries
  sfd <- attach_geometry(snap, geometry = "sf")
  grid <- expand.grid(
    na_style = c("grey", "hatched"),
    disputes = c("ignore", "mark"),
    style = c("continuous", "quantile"),
    stringsAsFactors = FALSE
  )
  for (i in seq_len(nrow(grid))) {
    lbl <- paste(grid$na_style[i], grid$disputes[i], grid$style[i])
    # ggpattern is what draws a hatch; without it the verbs correctly *say* so,
    # and that notice is the one thing this block must not suppress.
    if (!requireNamespace("ggpattern", quietly = TRUE) &&
        grid$na_style[i] == "hatched") next
    expect_silent(force(world_map(sfd, gdp_per_capita,
                                  na_style = grid$na_style[i],
                                  disputes = grid$disputes[i],
                                  style = grid$style[i])))
  }
  # uncertainty is a separate axis: it swaps in the VSUP scale.
  expect_silent(force(world_map(sfd, gdp_per_capita,
                                uncertainty = population)))
})

test_that("an infinite fill is counted as missing, and said to be", {
  skip_slow_on_cran()
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

test_that("every fill-drawing verb says when an infinity is drawn as no data", {
  skip_slow_on_cran()
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

test_that("world_map(uncertainty = ) places each country in its VSUP cell once", {
  skip_slow_on_cran()
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

test_that("bivariate_map() validates `dim` before anything else", {
  skip_slow_on_cran()
  d <- data.frame(iso3c = "FRA", x = 1, y = 1)
  for (bad in list("a", NA, c(2, 3), 5, 1)) {
    expect_error(bivariate_map(d, x, y, dim = bad), "dim")
  }
  expect_error(bivariate_map(d, x, y, dim = 2.5), "whole number")
})

test_that("the tmap engine draws 'binned' as equal intervals, like ggplot2", {
  skip_slow_on_cran()
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
  skip_slow_on_cran()
  d <- toy_polygons(c(FRA = 1, DEU = 2, ITA = 3, ESP = 4, PRT = 5, POL = 6))
  d$se <- c(0.1, 0.5, 0.2, 0.9, 0.3, 0.6)[d$group]
  expect_no_warning(p <- world_map(d, v, uncertainty = se, n_bins = 3))
  # ... and it really is used: three value classes, not the default five.
  lv <- levels(ggplot2::ggplot_build(p)$plot$data$.wdj_vsup)
  expect_equal(sort(unique(sub(" /.*", "", lv))), c("v1", "v2", "v3"))
  # Without `uncertainty` the notice is still right.
  expect_warning(world_map(d, v, style = "continuous", n_bins = 3),
                 class = "countryatlas_n_bins_ignored")
})

test_that("world_map() says n_uncertainty does nothing without uncertainty", {
  skip_slow_on_cran()
  d <- toy_polygons(c(FRA = 1, DEU = 2, ITA = 3))
  expect_warning(world_map(d, v, n_uncertainty = 5),
                 class = "countryatlas_n_uncertainty_ignored")
  expect_warning(world_map(d, v, n_uncertainty = "a"),
                 class = "countryatlas_n_uncertainty_ignored")
  expect_silent(world_map(d, v))
  expect_silent(world_map(d, v, n_uncertainty = 3L))
})

test_that("world_map builds a ggplot for several styles", {
  skip_slow_on_cran()
  mapdf <- attach_geometry(snap, geometry = "polygon")
  for (style in c("continuous", "binned", "quantile", "categorical")) {
    fill_col <- if (style == "categorical") "continent" else "gdp_per_capita"
    p <- world_map(mapdf, !!rlang::sym(fill_col), style = style)
    expect_s3_class(p, "ggplot")
    expect_silent(ggplot2::ggplot_build(p))
  }
})

test_that("world_map renders in every documented projection", {
  skip_slow_on_cran()
  # Regression: winkel_tripel built a CRS fine and st_transform()ed fine, but
  # coord_sf()'s graticule collapsed to a degenerate point under it and GEOS
  # threw "point array must contain 0 or >1 elements" -- so one of the eight
  # projections 2.0.0 advertises errored on every render. Only a full
  # ggplot_build() over every projection catches this class of bug.
  skip_if_no_sf_geometry()
  sfdata <- attach_geometry(snap, geometry = "sf")
  for (proj in countryatlas:::wdj_projections()) {
    expect_no_error(
      ggplot2::ggplot_build(world_map(sfdata, gdp_per_capita, projection = proj))
    )
  }
})

test_that("na_label renames the discrete legend's NA key", {
  skip_slow_on_cran()
  mapdf <- attach_geometry(snap, geometry = "polygon")
  labels_of <- function(p) {
    ggplot2::ggplot_build(p)$plot$scales$scales[[1]]$get_labels()
  }
  # Default.
  expect_true("No data" %in% labels_of(world_map(mapdf, continent,
                                                 style = "categorical")))
  # Custom, for both the categorical and the binned-into-a-factor styles.
  expect_true("Not reported" %in%
    labels_of(world_map(mapdf, continent, style = "categorical",
                        na_label = "Not reported")))
  expect_true("Not reported" %in%
    labels_of(world_map(mapdf, gdp_per_capita, style = "quantile",
                        na_label = "Not reported")))
  # Real levels are untouched.
  expect_true("Europe" %in% labels_of(world_map(mapdf, continent,
                                                style = "categorical")))
})

test_that("theme_world_map is applied where the docs say it is", {
  # ?theme_world_map used to claim "all the package's plotting functions".
  # bivariate_map() is the documented exception -- it uses biscale::bi_theme()
  # so the map matches biscale's own legend. facet_map()/dorling_map() get the
  # theme indirectly, via world_map()/cartogram_map().
  direct <- c("world_map", "globe_map", "bubble_map", "spike_map",
              "cartogram_map", "tile_map", "flow_map")
  for (f in direct) {
    src <- paste(deparse(body(get(f, envir = asNamespace("countryatlas")))),
                 collapse = " ")
    expect_true(grepl("theme_world_map", src, fixed = TRUE), info = f)
  }
  for (f in c("facet_map", "dorling_map")) {
    src <- paste(deparse(body(get(f, envir = asNamespace("countryatlas")))),
                 collapse = " ")
    expect_false(grepl("theme_world_map", src, fixed = TRUE), info = f)
    expect_true(grepl("world_map\\(|cartogram_map\\(", src), info = f)
  }
  bi <- paste(deparse(body(bivariate_map)), collapse = " ")
  expect_false(grepl("theme_world_map", bi, fixed = TRUE))
  expect_true(grepl("bi_theme", bi, fixed = TRUE))
})

test_that("theme_world_map is a theme", {
  expect_s3_class(theme_world_map(), "theme")
})

test_that("sf-only plots error cleanly without sf", {
  skip_if(requireNamespace("sf", quietly = TRUE))
  # "cleanly" is the whole point of this test, so assert the package gate
  # rather than any error at all. bivariate_map() checks biscale before sf, so
  # the message names whichever is missing first -- pin the class, which holds
  # either way.
  expect_error(bivariate_map(snap, gdp_per_capita, life_expectancy),
               class = "rlib_error_package_not_found")
})

test_that("bivariate_map builds a ggplot (needs sf + biscale)", {
  skip_slow_on_cran()
  # Regression: the fill columns were injected into biscale::bi_class() with
  # `!!sym()`, but bi_class() reads them with as.character(substitute(...)),
  # so every call failed with "the condition has length > 1".
  skip_if_not_installed("sf")
  skip_if_not_installed("biscale")
  skip_if_not_installed("rnaturalearth")
  sfdata <- attach_geometry(snap, geometry = "sf")
  p <- suppressWarnings(bivariate_map(sfdata, gdp_per_capita, life_expectancy))
  expect_s3_class(p, "ggplot")
  expect_no_error(suppressWarnings(ggplot2::ggplot_build(p)))
  expect_s3_class(
    suppressWarnings(bivariate_map(sfdata, gdp_per_capita, life_expectancy,
                                   dim = 2)),
    "ggplot"
  )
  expect_error(bivariate_map(sfdata, not_a_column, life_expectancy),
               class = "countryatlas_error")
})

test_that("world_map quantile breaks are country-weighted, not vertex-weighted", {
  # One country (A) has 100 vertices, the others have 1; values are 1..4. The
  # quantile breaks must come from the 4 country values, so each country lands
  # in its own bin -- not be dominated by the 100 copies of value 1.
  df <- rbind(
    data.frame(iso3c = "A", group = 1, long = 0, lat = 0, val = 1)[rep(1, 100), ],
    data.frame(iso3c = "B", group = 2, long = 1, lat = 1, val = 2),
    data.frame(iso3c = "C", group = 3, long = 2, lat = 2, val = 3),
    data.frame(iso3c = "D", group = 4, long = 3, lat = 3, val = 4)
  )
  p <- world_map(df, val, style = "quantile", n_bins = 4)
  expect_equal(length(unique(stats::na.omit(as.character(p$data$.wdj_bin)))), 4L)
})

# Forgetting attach_geometry() is the easiest mistake in the package, and it is
# easy precisely because the other plotting verbs do not need it: tile_map(),
# bubble_map(), spike_map() and globe_map() all take a country-level frame. So
# world_map(snap, gdp) looks like it should work -- it returned a ggplot object
# with no complaint, then failed only when printed, with ggplot2's "Problem
# while computing aesthetics ... Caused by error in `.data$long`".

test_that("world_map rejects a frame with no geometry, at the call", {
  skip_slow_on_cran()
  snap <- countryatlas::world_snapshot$countries
  expect_error(world_map(snap, gdp_per_capita), "no map geometry")
  expect_error(world_map(snap, gdp_per_capita), class = "countryatlas_error")
  expect_error(world_map(snap, gdp_per_capita), "attach_geometry")
  # facet_map() delegates to world_map(), so it is covered too.
  expect_error(facet_map(snap, gdp_per_capita, region), "no map geometry")
  # A frame with only some of the polygon columns is not map-ready either.
  half <- snap
  half$long <- 1
  expect_error(world_map(half, gdp_per_capita), "no map geometry")
})

test_that("world_map still accepts every documented route to geometry", {
  skip_slow_on_cran()
  snap <- countryatlas::world_snapshot$countries
  poly <- attach_geometry(snap, geometry = "polygon")
  expect_s3_class(world_map(poly, gdp_per_capita), "ggplot")
  expect_s3_class(world_map(poly, gdp_per_capita, style = "quantile"), "ggplot")
  expect_s3_class(facet_map(attach_geometry(transform(snap, yr = 2020L),
                                            geometry = "polygon"),
                            gdp_per_capita, yr), "ggplot")
  # join_world() produces a map-ready frame from messy names.
  jw <- suppressWarnings(join_world(
    data.frame(country = c("France", "Brazil"), v = c(1, 2)), country,
    warn = FALSE))
  expect_s3_class(world_map(jw, v), "ggplot")
  if (requireNamespace("sf", quietly = TRUE) &&
      requireNamespace("rnaturalearth", quietly = TRUE)) {
    sfd <- suppressWarnings(attach_geometry(snap, geometry = "sf"))
    expect_s3_class(world_map(sfd, gdp_per_capita), "ggplot")
  }
})

test_that("a returned plot survives ordinary ggplot2 operations", {
  skip_slow_on_cran()
  snap <- countryatlas::world_snapshot$countries
  poly <- attach_geometry(snap, geometry = "polygon")
  plots <- suppressWarnings(
    list(world_map(poly, gdp_per_capita), tile_map(snap, gdp_per_capita),
         bubble_map(snap, population), spike_map(snap, population)))
  for (p in plots) {
    expect_s3_class(p, "ggplot")
    expect_no_error(ggplot2::ggplot_build(p + ggplot2::theme_minimal()))
    expect_no_error(ggplot2::ggplot_build(p + ggplot2::labs(title = "t")))
    expect_no_error(ggplot2::ggplot_build(
      p + ggplot2::theme(legend.position = "bottom")))
    f <- tempfile(fileext = ".png")
    # suppressWarnings: the snapshot has five countries with no population, so
    # geom_point() reports dropping them. That is ggplot2 behaving correctly,
    # and it is not what this test is about.
    suppressWarnings(suppressMessages(
      ggplot2::ggsave(f, p, width = 4, height = 3, dpi = 72)))
    expect_true(file.exists(f))
    unlink(f)
  }
})

# The numeric fill styles said so only obliquely and late. "continuous" and
# "binned" reached ggplot2 and failed at *print* time ("Discrete value supplied
# to a continuous scale", "Binned scales only support continuous data"), neither
# naming the column. "quantile" and "jenks" did not fail at all: compute_breaks()
# returns early on a non-numeric column, so the fill fell through to the discrete
# scale and drew a plausible map whose legend claimed quantile bins it had never
# computed. The reverse direction -- categorical on a numeric column -- was
# already guarded, so this closes the pair.

test_that("the numeric fill styles require a numeric column", {
  skip_slow_on_cran()
  snap <- countryatlas::world_snapshot$countries
  mapdf <- attach_geometry(snap, geometry = "polygon")
  chr <- mapdf; chr$g <- "a"
  fac <- mapdf; fac$g <- factor(rep(c("lo", "hi"), length.out = nrow(mapdf)))
  for (st in c("continuous", "binned", "quantile", "jenks")) {
    for (d in list(chr, fac)) {
      expect_error(world_map(d, g, style = st), "needs a numeric", info = st)
      expect_error(world_map(d, g, style = st), class = "countryatlas_error")
      # The message names the style and the column.
      expect_error(world_map(d, g, style = st), st, fixed = TRUE)
      expect_error(world_map(d, g, style = st), "\"g\"", fixed = TRUE)
    }
  }
  # And it fires at the call, not when the plot is drawn.
  expect_error(world_map(chr, g, style = "quantile"), "needs a numeric")
})

test_that("the legitimate style/column pairings are untouched", {
  skip_slow_on_cran()
  snap <- countryatlas::world_snapshot$countries
  mapdf <- attach_geometry(snap, geometry = "polygon")
  for (st in c("continuous", "binned", "quantile", "jenks")) {
    # suppressWarnings: `jenks` degrades to quantile breaks with a warning when
    # classInt is absent, as it is in a Suggests-free check. That is documented
    # behaviour, pinned by its own test below, and not what this one is about.
    expect_no_error(suppressWarnings(ggplot2::ggplot_build(
      world_map(mapdf, gdp_per_capita, style = st))))
  }
  fac <- mapdf; fac$g <- factor(rep(c("lo", "hi"), length.out = nrow(mapdf)))
  expect_no_error(ggplot2::ggplot_build(world_map(fac, g, style = "categorical")))
  chr <- mapdf; chr$g <- "a"
  expect_no_error(ggplot2::ggplot_build(world_map(chr, g, style = "categorical")))
  # The pre-existing reverse guard still fires.
  expect_error(world_map(mapdf, gdp_per_capita, style = "categorical"),
               "needs a discrete")
})

test_that("jenks degrades to quantile breaks when classInt is absent", {
  skip_slow_on_cran()
  # A documented fallback that had no test of its own: it surfaced only as an
  # unexplained warning in the Suggests-free check tally.
  snap <- countryatlas::world_snapshot$countries
  mapdf <- attach_geometry(snap, geometry = "polygon")
  local_mocked_bindings(has_pkg = function(pkg) {
    if (identical(pkg, "classInt")) FALSE
    else isTRUE(requireNamespace(pkg, quietly = TRUE))
  })
  expect_warning(world_map(mapdf, gdp_per_capita, style = "jenks"),
                 "classInt")
  p <- suppressWarnings(world_map(mapdf, gdp_per_capita, style = "jenks"))
  expect_s3_class(p, "ggplot")
  expect_no_error(suppressWarnings(ggplot2::ggplot_build(p)))
  # Only jenks needs classInt; quantile computes its own breaks either way.
  expect_no_warning(world_map(mapdf, gdp_per_capita, style = "quantile"))
})
