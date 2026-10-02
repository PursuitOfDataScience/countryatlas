# Classification: breaks, classes, labels and fill scales (R/classify.R).

test_that("every computed style matches classInt on the bundled snapshot", {
  skip_if_not_installed("classInt")
  x <- unique(snap$gdp_per_capita[is.finite(snap$gdp_per_capita)])
  for (st in c("quantile", "equal", "jenks", "fisher", "headtails", "sd")) {
    ours <- countryatlas:::compute_breaks(x, st, 5)
    theirs <- suppressWarnings(classInt::classIntervals(x, n = 5, style = st))$brks
    expect_equal(ours, unique(theirs), info = st)
  }
})

test_that("head/tail breaks choose their own count on a heavy tail", {
  x <- c(rep(1, 50), rep(10, 10), rep(100, 3), 1000)
  br <- countryatlas:::headtails_breaks(x)
  expect_identical(br[1], 1)
  expect_identical(br[length(br)], 1000)
  # Each break is the mean of the head above the last one.
  expect_equal(br[2], mean(x))
  expect_equal(br[3], mean(x[x > mean(x)]))
  expect_true(!is.unsorted(br, strictly = TRUE))
})

test_that("GVF and TAI are right on a hand-worked example", {
  # x = 1, 2, 3 | 10, 12: mean 5.6, squared deviations 101.2 overall and 4
  # within the classes; absolute deviations 21.6 overall and 4 within.
  fit <- countryatlas:::class_fit(c(1, 2, 3, 10, 12), c(1, 3, 12))
  expect_equal(fit$gvf, 1 - 4 / 101.2)
  expect_equal(fit$tai, 1 - 4 / 21.6)
  expect_equal(fit$max_class_share, 3 / 5)
  # One class per value is a perfect fit.
  expect_equal(countryatlas:::class_fit(1:3, c(0.5, 1.5, 2.5, 3.5))$gvf, 1)
})

test_that("legend labels are SI-shortened and stay distinct", {
  lab <- countryatlas:::class_labels(c(258.3, 1136, 4466, 13846, 247000))
  expect_identical(lab, c("258 to 1.14K", "1.14K to 4.47K", "4.47K to 13.8K",
                          "13.8K to 247K"))
  open <- countryatlas:::class_labels(c(-Inf, 1136, 4466, Inf))
  expect_identical(open, c("< 1.14K", "1.14K to 4.47K", ">= 4.47K"))
  # Close edges get the digits they need to differ.
  close <- countryatlas:::si_label(c(1001, 1002, 1003))
  expect_false(anyDuplicated(close) > 0)
  expect_identical(countryatlas:::si_label(1.4e9), "1.4B")
})

test_that("quantile is the default style, and a factor fill is categorical", {
  skip_slow_on_cran()
  pd <- poly_df()
  p <- world_map(pd, gdp_per_capita)
  expect_identical(map_provenance(p)$style, "quantile")
  expect_identical(map_provenance(world_map(pd, continent))$style, "categorical")
  # The 3.0.0 default is one argument away.
  expect_identical(map_provenance(world_map(pd, gdp_per_capita,
                                            style = "continuous"))$style,
                   "continuous")
})

test_that("fixed breaks set the classes, open the ends and say so", {
  skip_slow_on_cran()
  pd <- poly_df()
  wb <- c(1136, 4466, 13846)
  expect_warning(p <- world_map(pd, gdp_per_capita, breaks = wb,
                                classification_report = TRUE),
                 class = "countryatlas_breaks_open")
  expect_identical(map_provenance(p)$style, "fixed")
  expect_equal(map_provenance(p)$breaks[[1]], c(-Inf, wb, Inf))
  rep <- attr(p, "countryatlas_classification")
  expect_identical(rep$class, c("< 1.14K", "1.14K to 4.47K", "4.47K to 13.8K",
                                ">= 13.8K"))
  # Left-closed: a value on a threshold is in the class it opens.
  one <- countryatlas:::bin_values(4466, c(-Inf, wb, Inf), right = FALSE)
  expect_identical(as.character(one), "4.47K to 13.8K")
  # Ends the caller opened: nothing to say.
  expect_no_warning(world_map(pd, gdp_per_capita, breaks = c(-Inf, wb, Inf)))
  # Every class stays in the legend, populated or not, so two maps on the same
  # thresholds read the same.
  q <- world_map(pd, gdp_per_capita, breaks = c(-Inf, 0, 1, wb, Inf))
  sc <- ggplot2::ggplot_build(q)$plot$scales$get_scales("fill")
  expect_length(setdiff(sc$get_limits(), NA), 6L)
})

test_that("breaks are validated, and do not fight `style`", {
  pd <- poly_df()
  expect_error(world_map(pd, gdp_per_capita, breaks = c(3, 1)),
               class = "countryatlas_error")
  expect_error(world_map(pd, gdp_per_capita, breaks = 1),
               class = "countryatlas_error")
  expect_error(world_map(pd, gdp_per_capita, breaks = c(1, 2), style = "jenks"),
               class = "countryatlas_breaks_style")
  expect_error(world_map(pd, gdp_per_capita, style = "fixed"), "breaks")
})

test_that("a midpoint lands on the centre of a diverging palette", {
  skip_slow_on_cran()
  d <- snap
  d$growth <- log(d$gdp_per_capita) - 9
  gm <- attach_geometry(d, geometry = "polygon")
  p <- world_map(gm, growth, style = "continuous", midpoint = 0.5)
  sc <- ggplot2::ggplot_build(p)$plot$scales$get_scales("fill")
  expect_equal(sc$rescale(0.5, sc$get_limits()), 0.5, tolerance = 1e-9)
  centre <- grDevices::hcl.colors(11L, "RdBu")[6]
  expect_identical(toupper(sc$map(0.5)), toupper(centre))
  # Classes: a break is forced at the midpoint, and the classes either side
  # take the two arms.
  q <- world_map(gm, growth, midpoint = 0)
  br <- map_provenance(q)$breaks[[1]]
  expect_true(any(abs(br) < 1e-12))
  # A sequential palette has no centre to put it on.
  expect_error(world_map(gm, growth, midpoint = 0, palette = "magma"),
               class = "countryatlas_palette_not_diverging")
  expect_error(world_map(gm, growth, palette = "nope"),
               class = "countryatlas_unknown_palette")
  expect_error(world_map(gm, continent, midpoint = 0), "categorical")
})

test_that("the coverage footnote is on by default and off with FALSE", {
  skip_slow_on_cran()
  pd <- poly_df()
  expect_match(gg_caption_of(world_map(pd, gdp_per_capita)),
               "countries shown", fixed = TRUE)
  expect_null(gg_caption_of(world_map(pd, gdp_per_capita, footnote = FALSE)))
  expect_identical(gg_caption_of(world_map(pd, gdp_per_capita,
                                           footnote = "Mine.")), "Mine.")
  # And on the other verbs that carry provenance.
  expect_match(gg_caption_of(suppressWarnings(bubble_map(snap, population))),
               "countries shown", fixed = TRUE)
  expect_null(gg_caption_of(suppressWarnings(
    bubble_map(snap, population, footnote = FALSE))))
  g <- suppressWarnings(gridded_cartogram(snap, population, cells = 200))
  expect_match(gg_caption_of(g), "^1 cell = [0-9.]+M population\\. .*countries shown")
})

test_that("classify_compare() reports fit without ranking", {
  skip_slow_on_cran()
  cmp <- suppressWarnings(classify_compare(poly_df(), gdp_per_capita))
  rep <- attr(cmp, "countryatlas_classification")
  expect_setequal(unique(rep$method),
                  c("quantile", "jenks", "fisher", "headtails", "equal", "pretty"))
  expect_true(all(rep$gvf >= 0 & rep$gvf <= 1))
  expect_true(all(rep$tai <= 1))
  expect_true(all(rep$max_class_share > 0 & rep$max_class_share <= 1))
})

test_that('breaks_by = "panel" classifies each panel on its own values', {
  skip_slow_on_cran()
  pan <- rbind(transform(snap, year = 2020L),
               transform(snap, year = 2024L, gdp_per_capita = gdp_per_capita * 10))
  pd <- attach_geometry(pan, geometry = "polygon")
  pooled <- facet_map(pd, gdp_per_capita, year)
  panel <- facet_map(pd, gdp_per_capita, year, breaks_by = "panel")
  expect_identical(map_provenance(panel)$style, "quantile (per panel)")
  # Pooled: the scaled-up year sits in the top classes. Per panel: the same
  # country is in the same class in both years.
  cls <- function(p) {
    d <- gg_plot_data(p)
    d <- d[d$iso3c %in% "FRA" & !duplicated(d[, c("iso3c", "year")]), ]
    as.character(d[[if (".wdj_panel_class" %in% names(d)) ".wdj_panel_class" else ".wdj_bin"]])
  }
  expect_identical(length(unique(cls(panel))), 1L)
  expect_identical(length(unique(cls(pooled))), 2L)
  expect_error(facet_map(pd, gdp_per_capita, year, breaks_by = "panel",
                         breaks = c(0, 1)), "same in every panel")
})

test_that("the default palettes pass the colour-vision check; a rainbow fails", {
  skip_slow_on_cran()
  skip_if_not_installed("colorspace")
  pd <- poly_df()
  for (st in c("quantile", "continuous", "binned")) {
    expect_no_warning(check_palette(world_map(pd, gdp_per_capita, style = st)))
  }
  expect_warning(out <- check_palette(grDevices::rainbow(7)),
                 class = "countryatlas_palette_cvd")
  expect_named(out, c("vision", "min_delta_e", "between"))
  expect_identical(out$vision, c("normal", "deuteranopia", "protanopia",
                                 "tritanopia"))
  # And no default is a rainbow (Crameri et al. 2020).
  expect_false(countryatlas:::CATEGORICAL_PALETTE %in% c("turbo", "rainbow", "jet"))
})

test_that("every map verb has alt text naming its fill and projection", {
  skip_slow_on_cran()
  pd <- poly_df()
  od <- data.frame(from = "China", to = "Brazil", v = 1)
  maps <- list(
    world_map = world_map(pd, gdp_per_capita),
    bubble_map = suppressWarnings(bubble_map(snap, population)),
    spike_map = suppressWarnings(spike_map(snap, population)),
    value_by_alpha_map = value_by_alpha_map(pd, gdp_per_capita, population),
    gridded_cartogram = suppressWarnings(gridded_cartogram(snap, population,
                                                           cells = 200)),
    tile_map = suppressWarnings(tile_map(snap, gdp_per_capita)),
    coverage_map = coverage_map(pd, gdp_per_capita),
    facet_map = facet_map(pd, gdp_per_capita, continent))
  for (nm in names(maps)) {
    alt <- ggplot2::get_alt_text(maps[[nm]])
    expect_true(nzchar(alt), info = nm)
    expect_match(alt, "projection", fixed = TRUE, info = nm)
  }
  expect_match(ggplot2::get_alt_text(maps$world_map), "gdp_per_capita", fixed = TRUE)
  expect_match(ggplot2::get_alt_text(maps$bubble_map), "population", fixed = TRUE)
  expect_match(map_alt_text(maps$world_map), "Highest: ", fixed = TRUE)
  expect_no_match(map_alt_text(maps$world_map, level = 1), "Highest", fixed = TRUE)
  expect_error(map_alt_text(maps$world_map, level = 3), "author")
})

test_that("provenance reports what the final plot shows", {
  skip_slow_on_cran()
  skip_if_not_installed("sf")
  pd <- poly_df()
  p <- world_map(pd, gdp_per_capita)
  expect_false(map_provenance(p)$modified)
  q <- suppressMessages(p + ggplot2::coord_sf(crs = countryatlas:::wdj_crs("robinson"),
                                              default_crs = sf::st_crs(4326)))
  expect_true(map_provenance(q)$modified)
  expect_identical(map_provenance(q)$projection, "robinson")
  r <- suppressMessages(world_map(pd, gdp_per_capita, style = "continuous") +
                          ggplot2::scale_fill_viridis_b())
  expect_true(map_provenance(r)$modified)
  expect_match(map_provenance(r)$style, "binned", fixed = TRUE)
})
