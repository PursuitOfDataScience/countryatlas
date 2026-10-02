# Small states, drawn rather than dropped (R/small-states.R).

test_that("on sf at 1:110m every country with a value is a polygon or a point", {
  skip_slow_on_cran()
  skip_if_no_sf_geometry()
  sfd <- attach_geometry(snap, geometry = "sf")
  unplaced <- attr(sfd, "countryatlas_unplaced")
  expect_gt(nrow(unplaced), 30L)
  p <- world_map(sfd, gdp_per_capita)
  prov <- map_provenance(p)
  with_value <- snap$iso3c[!is.na(snap$gdp_per_capita)]
  pts <- ggplot2::layer_data(p, 2)
  expect_identical(prov$n_countries,
                   length(with_value) -
                     length(attr(p, "countryatlas_provenance")$undrawable))
  expect_identical(nrow(pts), attr(p, "countryatlas_provenance")$n_points)
  expect_match(gg_caption_of(p), "drawn as points", fixed = TRUE)
  prints <- tempfile(fileext = ".png")
  grDevices::png(prints, 400, 240)
  print(p)
  grDevices::dev.off()
  # The 3.0.0 behaviour, by name.
  q <- world_map(sfd, gdp_per_capita, small_states = "none")
  expect_lt(map_provenance(q)$n_countries, prov$n_countries)
  expect_no_match(gg_caption_of(q), "points", fixed = TRUE)
})

test_that("a country with neither polygon nor centroid is named", {
  skip_slow_on_cran()
  d <- data.frame(iso3c = c("GIB", "FRA"), v = c(5, 7))
  p <- world_map(attach_geometry(d, geometry = "polygon"), v)
  expect_match(gg_caption_of(p), "Not drawable (no polygon or centroid): Gibraltar.",
               fixed = TRUE)
  prov <- map_provenance(p)
  expect_true("GIB" %in% prov$missing_iso3c[[1]])
})

test_that('"dots" marks the countries too small to see', {
  skip_slow_on_cran()
  pd <- poly_df()
  auto <- world_map(pd, gdp_per_capita)
  dots <- world_map(pd, gdp_per_capita, small_states = "dots")
  n_auto <- attr(auto, "countryatlas_provenance")$n_points
  n_dots <- attr(dots, "countryatlas_provenance")$n_points
  expect_gt(n_dots, n_auto)
  tiny <- countryatlas::country_meta$iso3c[
    (countryatlas::country_meta$area_km2 < 1000) %in% TRUE]
  expect_gt(length(tiny), 5L)
  # Raising the threshold adds more.
  more <- world_map(pd, gdp_per_capita, small_states = "dots",
                    small_area_km2 = 20000)
  expect_gt(attr(more, "countryatlas_provenance")$n_points, n_dots)
})

test_that("points are on the polygons' scale, and in their classes", {
  skip_slow_on_cran()
  skip_if_no_sf_geometry()
  sfd <- attach_geometry(snap, geometry = "sf")
  p <- world_map(sfd, gdp_per_capita)
  b <- ggplot2::ggplot_build(p)
  pts <- b$data[[2]]
  polys <- b$data[[1]]
  # Every point colour is one of the class colours the polygons use.
  expect_true(all(pts$fill %in% c(unique(polys$fill))))
})
