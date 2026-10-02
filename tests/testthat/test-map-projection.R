# Projections on the polygon backend (R/map-projection.R).

# Drawn on a real device, not just built: 3.0.0's globes built fine and then
# failed when printed.
prints_png <- function(p) {
  f <- tempfile(fileext = ".png")
  grDevices::png(f, width = 360, height = 220)
  on.exit(grDevices::dev.off(), add = TRUE)
  print(p)
  invisible(p)
}

# Treat sf as unloadable, for the built-in path.
local_no_sf <- function(env = parent.frame()) {
  real <- countryatlas:::has_pkg
  local_mocked_bindings(
    has_pkg = function(pkg) if (identical(pkg, "sf")) FALSE else real(pkg),
    .env = env)
}

test_that("project_lonlat() is PROJ's spherical Equal Earth", {
  skip_if_not_installed("sf")
  g <- expand.grid(lon = seq(-180, 180, length.out = 40),
                   lat = seq(-90, 90, length.out = 25))
  expect_identical(nrow(g), 1000L)
  sph <- "+proj=longlat +R=6371007.181"
  for (lon0 in c(0, 150)) {
    ours <- project_lonlat(g$lon, g$lat, recenter = if (lon0) lon0)
    proj <- sf::sf_project(sph, sprintf("+proj=eqearth +R=6371007.181 +lon_0=%d", lon0),
                           cbind(g$lon, g$lat))
    expect_lt(max(abs(ours$x - proj[, 1])), 1e-6)
    expect_lt(max(abs(ours$y - proj[, 2])), 1e-6)
  }
})

test_that("the antimeridian stays where it is", {
  # A plain modulo sent +180 to -180, so every ring and arc split at the
  # antimeridian was drawn as a streak across the map.
  e <- project_lonlat(c(-180, 180), c(0, 0))
  expect_lt(e$x[1], 0)
  expect_gt(e$x[2], 0)
  expect_equal(e$x[1], -e$x[2])
  # Outside the window still wraps.
  expect_equal(project_lonlat(190, 10)$x, project_lonlat(-170, 10)$x)
})

test_that("project_lonlat() refuses what it cannot project", {
  expect_error(project_lonlat("a", 1), class = "countryatlas_error")
  expect_error(project_lonlat(1:2, 1), class = "countryatlas_error")
  expect_error(project_lonlat(0, 91), class = "countryatlas_error")
  expect_error(project_lonlat(0, 0, projection = "nope"))
  out <- project_lonlat(c(0, NA), c(0, 0))
  expect_true(is.na(out$x[2]))
})

test_that("the default polygon map is equal-area, and says which path drew it", {
  skip_if_not_installed("sf")
  p <- world_map(poly_df(), gdp_per_capita)
  expect_s3_class(p$coordinates, "CoordSf")
  expect_identical(map_provenance(p)$projection, "equal_earth")
  # The frame stays in degrees, so a layer added in lon/lat lands in place.
  expect_lte(max(abs(gg_plot_data(p)$long)), 180)
})

test_that("without sf the map uses the built-in Equal Earth", {
  skip_slow_on_cran()
  local_no_sf()
  p <- world_map(poly_df(), gdp_per_capita)
  # coord_fixed(): a CoordFixed before ggplot2 4.0, a CoordCartesian with an
  # aspect ratio since.
  expect_false(inherits(p$coordinates, c("CoordSf", "CoordMap", "CoordQuickmap")))
  expect_equal(p$coordinates$ratio, 1)
  expect_identical(map_provenance(p)$projection,
                   "equal_earth (spherical, built-in)")
  d <- gg_plot_data(p)
  # Metres, with the degrees kept for the steps that need geography.
  expect_gt(max(abs(d$long)), 1e6)
  expect_lte(max(abs(d$.wdj_lon)), 180)
  # Any other projection falls back to it, and says so.
  expect_warning(q <- world_map(poly_df(), gdp_per_capita, projection = "robinson"),
                 class = "countryatlas_projection_fallback")
  expect_identical(map_provenance(q)$projection,
                   "equal_earth (spherical, built-in)")
  prints_png(p)
})

test_that('projection = "none" is the 3.0.0 map', {
  p <- world_map(poly_df(), gdp_per_capita, projection = "none")
  expect_s3_class(p$coordinates, "CoordQuickmap")
  expect_identical(map_provenance(p)$projection, "none")
})

test_that("recentring cuts the rings at the new antimeridian", {
  skip_slow_on_cran()
  w <- world_geometry("countries", geometry = "polygon", recenter = 150)
  expect_gte(min(w$long), -30)
  expect_lte(max(w$long), 330)
  # No ring spans more than half the globe, which is what a streak would be --
  # except Antarctica's, which encircles the pole and so spans every
  # longitude, cut into two pieces at the new edge.
  span <- tapply(w$long, w$group, function(x) diff(range(x)))
  ata <- unique(w$group[w$iso3c %in% "ATA"])
  expect_lt(max(span[!names(span) %in% ata]), 180)
  # Ring areas are preserved: the pieces of a cut ring add up to it.
  area <- function(d) {
    sum(vapply(split(d, d$group), function(r) {
      abs(sum(r$long * c(r$lat[-1], r$lat[1]) - c(r$long[-1], r$long[1]) * r$lat)) / 2
    }, numeric(1)))
  }
  w0 <- world_geometry("countries", geometry = "polygon")
  rus0 <- w0[w0$iso3c %in% "RUS", ]
  rus <- w[w$iso3c %in% "RUS", ]
  expect_equal(area(rus), area(rus0), tolerance = 1e-6)
})

test_that("zoom_map() keeps the projection", {
  skip_slow_on_cran()
  skip_if_not_installed("sf")
  p <- world_map(poly_df(), gdp_per_capita)
  z <- zoom_map(p, xlim = c(-25, 45), ylim = c(34, 72))
  expect_s3_class(z$coordinates, "CoordSf")
  expect_identical(z$coordinates$crs, p$coordinates$crs)
  expect_identical(map_provenance(z)$projection, "equal_earth")
  expect_error(zoom_map(p, xlim = c(45, -25), ylim = c(34, 72)),
               class = "countryatlas_error")
  expect_error(zoom_map(1, c(0, 1), c(0, 1)), class = "countryatlas_error")
})

test_that("zoom_map() zooms the built-in projection in its own metres", {
  skip_slow_on_cran()
  local_no_sf()
  p <- world_map(poly_df(), gdp_per_capita)
  z <- zoom_map(p, xlim = c(-25, 45), ylim = c(34, 72))
  expect_false(inherits(z$coordinates, c("CoordSf", "CoordMap", "CoordQuickmap")))
  lim <- z$coordinates$limits
  e <- project_lonlat(c(-25, 45), c(34, 34))
  expect_equal(min(lim$x), min(e$x), tolerance = 0.05)
  prints_png(z)
})

test_that("every projection prints, for every polygon-backend verb", {
  skip_slow_on_cran()
  skip_if_not_installed("sf")
  skip_if_not_installed("mapproj")
  od <- data.frame(from = c("China", "Brazil"), to = c("United States", "Fiji"),
                   v = c(2, 1))
  pd <- poly_df()
  verbs <- list(
    world_map = function(pr) world_map(pd, gdp_per_capita, projection = pr),
    bubble_map = function(pr) bubble_map(snap, population, projection = pr),
    spike_map = function(pr) spike_map(snap, population, projection = pr),
    flow_map = function(pr) flow_map(od, from, to, v, projection = pr),
    value_by_alpha_map = function(pr) value_by_alpha_map(pd, gdp_per_capita,
                                                         population,
                                                         projection = pr),
    gridded_cartogram = function(pr) gridded_cartogram(snap, population,
                                                       cells = 200,
                                                       projection = pr)
  )
  # Every verb in every projection is about 90 seconds of drawing, so the full
  # matrix runs where it is asked for (CI sets it); world_map() always does.
  all <- identical(Sys.getenv("COUNTRYATLAS_RENDER_ALL"), "true")
  for (v in names(verbs)) {
    prjs <- if (all || v == "world_map") {
      c(countryatlas:::wdj_projections(), "none")
    } else {
      c("equal_earth", "orthographic", "mercator", "none")
    }
    for (pr in prjs) {
      p <- suppressWarnings(verbs[[v]](pr))
      expect_no_error(prints_png(p))
      expect_identical(map_provenance(p)$projection, pr, info = paste(v, pr))
    }
  }
})

test_that("spikes share one scale wherever they stand", {
  skip_slow_on_cran()
  skip_if_not_installed("sf")
  # Two countries of equal value far apart in latitude: drawn in degrees and
  # then projected, the northern one came out shorter.
  d <- data.frame(iso3c = c("NOR", "COD"), v = c(10, 10))
  p <- spike_map(d, v)
  b <- ggplot2::ggplot_build(p)
  sp <- b$data[[2]]
  h <- vapply(seq_len(nrow(sp)), function(i) {
    bb <- sf::st_bbox(sp$geometry[[i]])
    unname(bb["ymax"] - bb["ymin"])
  }, numeric(1))
  expect_length(h, 2L)
  expect_equal(h[[1]], h[[2]], tolerance = 1e-6)
})

test_that("labels land on the projected countries", {
  skip_slow_on_cran()
  local_no_sf()
  pd <- poly_df()
  p <- world_map(pd, gdp_per_capita) +
    geom_country_labels(data = ~ .x[.x$iso3c %in% c("FRA", "AUS"), ],
                        repel = FALSE)
  lab <- ggplot2::layer_data(p, 2)
  fra <- countryatlas::country_meta[countryatlas::country_meta$iso3c == "FRA", ]
  e <- project_lonlat(fra$centroid_lon, fra$centroid_lat)
  # Within a few hundred km of the bundled centroid, in the map's metres.
  expect_lt(min(abs(lab$x - e$x)), 5e5)
  expect_lt(min(abs(lab$y - e$y)), 5e5)
})

test_that("north_polar draws the countries, not Antarctica's ring around them", {
  skip_slow_on_cran()
  skip_if_not_installed("sf")   # north_polar is drawn through PROJ
  # Natural Earth closes Antarctica along the pole in two vertices, which the
  # north polar projection sends to one point on its rim: the ring then closed
  # around the whole map and painted every country grey on the sf backend.
  poly <- attach_geometry(snap)
  p <- world_map(poly, gdp_per_capita, projection = "north_polar")
  d <- countryatlas:::gg_plot_data(p)
  expect_false("ATA" %in% d$iso3c)
  expect_true("ATA" %in% poly$iso3c)
  # Coverage is counted on the frame as given, so it does not move.
  expect_identical(map_provenance(p)$n_total,
                   map_provenance(world_map(poly, gdp_per_capita))$n_total)
  renders(p)
  skip_if_no_sf_geometry()
  sfd <- attach_geometry(snap, geometry = "sf")
  q <- world_map(sfd, gdp_per_capita, projection = "north_polar")
  g <- sf::st_geometry(countryatlas:::gg_plot_data(q))
  ata <- countryatlas:::gg_plot_data(q)$iso3c %in% "ATA"
  expect_true(all(sf::st_is_empty(g[ata])))
  expect_false(any(sf::st_is_empty(g[countryatlas:::gg_plot_data(q)$iso3c %in% c("USA", "BRA")])))
  renders(q)
})

test_that("the polygon backend's polar views are not cropped to a band", {
  skip_slow_on_cran()
  skip_if_not_installed("sf")
  poly <- attach_geometry(snap)
  for (pr in c("north_polar", "south_polar")) {
    b <- ggplot2::ggplot_build(world_map(poly, gdp_per_capita, projection = pr))
    pp <- b$layout$panel_params[[1]]
    w <- diff(pp$x_range)
    h <- diff(pp$y_range)
    # The whole disc: as wide as it is tall.
    expect_lt(abs(w / h - 1), 0.1, label = pr)
  }
})

test_that("value_by_alpha_map()'s dark ground is the panel, whatever the projection", {
  skip_slow_on_cran()
  poly <- attach_geometry(snap)
  p <- value_by_alpha_map(poly, gdp_per_capita, population, background = "grey10")
  # It was an annotate("rect") at +/-Inf, which coord_sf() reprojected into a
  # lens between two meridians.
  expect_false(any(vapply(p$layers, function(l) inherits(l$geom, "GeomRect"),
                          logical(1))))
  expect_identical(ggplot2::calc_element("panel.background", ggplot2::theme_get() +
                                           p$theme)$fill, "grey10")
  renders(p)
})

test_that("classify_compare() names the missing class as every map does", {
  skip_slow_on_cran()
  poly <- attach_geometry(snap)
  p <- classify_compare(poly, gdp_per_capita, methods = c("quantile", "fisher"))
  b <- ggplot2::ggplot_build(p)
  labs <- b$plot$scales$get_scales("fill")$get_labels()
  expect_true("No data" %in% labs)
  expect_false("NA" %in% labs)
})
