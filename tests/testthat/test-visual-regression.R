# A regression net for the map verbs.
#
# The 2.0.0 audit found three separate *visual* correctness bugs -- quantile
# breaks weighted by polygon vertices rather than by country, sf bubbles sized in
# projected metres on a degrees map, and duplicate centroids fanning labels into
# the wrong ocean. None of them threw an error; each produced a plausible,
# wrong picture. This file is the net for that class of bug.
#
# It asserts on the *built* plot -- the computed positions, sizes, colours and
# break points ggplot2 will actually draw -- rather than on rendered pixels.
# That catches the same defects as an image snapshot while staying immune to the
# font and freetype differences that make image snapshots flap between machines.
# The optional vdiffr block at the bottom adds true image snapshots for anyone
# who wants them; see the comment there for why they are opt-in.

snap <- countryatlas::world_snapshot$countries

skip_poly <- function() skip_if_not_installed("maps")
skip_sf <- function() {
  skip_if_no_sf_geometry()
}
built <- function(p) ggplot2::ggplot_build(p)

# --- classification: bins must count countries, not vertices ------------------

test_that("quantile bins hold near-equal numbers of countries on both backends", {
  skip_poly()
  for (backend in c("polygon", "sf")) {
    if (backend == "sf") skip_sf()
    d <- attach_geometry(snap, geometry = backend)
    p <- world_map(d, gdp_per_capita, style = "quantile", n_bins = 5,
                   classification_report = TRUE)
    rep <- attr(p, "countryatlas_classification")
    # The vertex-weighted bug showed up here as wildly unequal counts: Canada
    # and Russia alone contribute thousands of rows to the polygon backend.
    expect_lte(max(rep$n) - min(rep$n), 2L, label = backend)
    expect_equal(nrow(rep), 5L)
  }
})

test_that("breaks are computed once per country, whatever the backend's row count", {
  skip_poly(); skip_sf()
  # The two backends genuinely carry different country sets -- map_data("world")
  # has ~240 regions, Natural Earth 110m has 177 -- so their quantiles differ
  # legitimately, and equality would be the wrong assertion. The invariant that
  # *was* broken in 2.0.0 is subtler: breaks must come from one value per
  # country, not one per row. Check that directly.
  for (backend in c("polygon", "sf")) {
    d <- attach_geometry(snap, geometry = backend)
    got <- map_provenance(world_map(d, gdp_per_capita, style = "quantile"))$breaks[[1]]
    one_per_country <- dplyr::distinct(
      tibble::as_tibble(countryatlas:::sf_drop(d)), iso3c, .keep_all = TRUE)
    want <- countryatlas:::compute_breaks(one_per_country$gdp_per_capita,
                                          "quantile", 5)
    expect_equal(got, want, tolerance = 1e-9, label = backend)
    # ...and emphatically not the row-weighted answer the bug produced.
    if (backend == "polygon") {
      rowwise <- countryatlas:::compute_breaks(d$gdp_per_capita, "quantile", 5)
      expect_false(isTRUE(all.equal(got, rowwise)))
    }
  }
})

# --- bubble sizing: radius must not be in projected metres --------------------

test_that("bubble_map sizes are comparable across backends", {
  skip_poly(); skip_sf()
  size_range <- function(backend) {
    d <- if (backend == "sf") attach_geometry(snap, geometry = "sf") else snap
    b <- built(suppressWarnings(bubble_map(d, population, backend = backend)))
    pt <- b$data[[length(b$data)]]
    range(pt$size, na.rm = TRUE)
  }
  poly_rng <- size_range("polygon")
  sf_rng <- size_range("sf")
  # The bug drew sf bubbles with radii in metres, so they covered the map.
  # Sizes are a plot aesthetic and must stay in the same order of magnitude.
  expect_lt(max(sf_rng), 100)
  expect_lt(max(poly_rng), 100)
  expect_equal(max(sf_rng), max(poly_rng), tolerance = 0.5)
})

# --- centroids: one per country, on the right side of the antimeridian --------

test_that("country label centroids land inside their own country", {
  skip_poly()
  mapdf <- attach_geometry(snap, geometry = "polygon")
  cent <- countryatlas:::polygon_centroids(mapdf)
  expect_equal(anyDuplicated(cent$iso3c), 0L)
  pick <- function(iso) cent[cent$iso3c == iso, ]
  # The antimeridian cases: averaging all pieces put the US label in the
  # mid-Atlantic and Fiji's in Africa.
  usa <- pick("USA")
  expect_true(usa$centroid_lon < -60 && usa$centroid_lon > -130)
  expect_true(usa$centroid_lat > 20 && usa$centroid_lat < 55)
  fji <- pick("FJI")
  expect_true(abs(fji$centroid_lon) > 150)
  nzl <- pick("NZL")
  expect_true(nzl$centroid_lon > 150 && nzl$centroid_lat < -30)
  fra <- pick("FRA")
  expect_true(fra$centroid_lon > -10 && fra$centroid_lon < 15)
})

# --- projections: the CRS actually reaches the panel --------------------------

test_that("every projection produces a distinct, finite panel extent", {
  skip_sf()
  d <- attach_geometry(snap, geometry = "sf")
  extents <- lapply(countryatlas:::wdj_projections(), function(pr) {
    pp <- built(world_map(d, life_expectancy, projection = pr))$layout$panel_params[[1]]
    c(diff(pp$x_range), diff(pp$y_range))
  })
  names(extents) <- countryatlas:::wdj_projections()
  for (nm in names(extents)) {
    expect_true(all(is.finite(extents[[nm]])), label = nm)
    expect_true(all(extents[[nm]] > 0), label = nm)
  }
  # A projection argument that silently did nothing would make these identical.
  expect_false(isTRUE(all.equal(extents$equal_earth, extents$mercator)))
  expect_false(isTRUE(all.equal(extents$equal_earth, extents$mollweide)))
  # Mercator must stay in its clipped band rather than running to the pole.
  expect_lt(extents$mercator[2] / extents$mercator[1], 1.6)
})

test_that("recenter moves the map rather than being ignored", {
  skip_sf()
  d <- attach_geometry(snap, geometry = "sf")
  x0 <- built(world_map(d, life_expectancy))$layout$panel_params[[1]]$x_range
  x1 <- built(world_map(d, life_expectancy, recenter = 150))$layout$panel_params[[1]]$x_range
  expect_false(isTRUE(all.equal(x0, x1)))
})

# --- na_style: the missing-data colour is the one that was asked for ----------

test_that("na_style controls the fill actually drawn for missing countries", {
  skip_poly()
  mapdf <- attach_geometry(snap, geometry = "polygon")
  na_fill <- function(ns) {
    b <- built(world_map(mapdf, gdp_per_capita, style = "quantile", na_style = ns))
    d <- b$data[[1]]
    unique(d$fill[is.na(mapdf$gdp_per_capita)[seq_len(nrow(d))]])
  }
  expect_true("grey85" %in% na_fill("grey"))
  expect_true("white" %in% na_fill("outline"))
})

# --- tile grid: one square per country, no overplotting -----------------------

test_that("tile_map draws every tile exactly once", {
  b <- built(suppressWarnings(tile_map(snap, gdp_per_capita)))
  tiles <- b$data[[1]]
  expect_equal(nrow(tiles), nrow(countryatlas::world_tiles))
  expect_equal(anyDuplicated(paste(tiles$x, tiles$y)), 0L)
})

# --- flow arcs: endpoints sit on the endpoints --------------------------------

test_that("flow_map arcs start and end at the right centroids", {
  skip_poly()
  od <- data.frame(from = "France", to = "Germany")
  b <- built(flow_map(od, from, to))
  arc <- b$data[[2]]
  cent <- countryatlas:::polygon_centroids(
    attach_geometry(snap, geometry = "polygon"))
  fra <- cent[cent$iso3c == "FRA", ]
  deu <- cent[cent$iso3c == "DEU", ]
  expect_equal(arc$x[1], fra$centroid_lon, tolerance = 0.01)
  expect_equal(arc$y[1], fra$centroid_lat, tolerance = 0.01)
  expect_equal(arc$x[nrow(arc)], deu$centroid_lon, tolerance = 0.01)
  expect_equal(arc$y[nrow(arc)], deu$centroid_lat, tolerance = 0.01)
})

# --- every map verb renders, not merely builds --------------------------------

test_that("every map verb produces a drawable grob", {
  skip_poly()
  mapdf <- attach_geometry(snap, geometry = "polygon")
  verbs <- list(
    world_map     = function() world_map(mapdf, gdp_per_capita, style = "quantile"),
    bubble_map    = function() suppressWarnings(bubble_map(snap, population)),
    spike_map     = function() suppressWarnings(spike_map(snap, population)),
    tile_map      = function() suppressWarnings(tile_map(snap, gdp_per_capita)),
    flow_map      = function() flow_map(data.frame(from = "France", to = "Germany"), from, to),
    facet_map     = function() facet_map(mapdf, gdp_per_capita, continent, style = "quantile"),
    globe_map     = function() { skip_if_not_installed("mapproj")
                                 globe_map(snap, continent, backend = "polygon",
                                           style = "categorical") },
    coverage_map  = function() coverage_map(mapdf, gdp_per_capita),
    classify_cmp  = function() classify_compare(mapdf, gdp_per_capita),
    value_by_alpha = function() value_by_alpha_map(mapdf, gdp_per_capita, population)
  )
  for (nm in names(verbs)) {
    expect_s3_class(ggplot2::ggplotGrob(verbs[[nm]]()), "gtable")
  }
})

test_that("every sf map verb produces a drawable grob", {
  skip_sf()
  d <- attach_geometry(snap, geometry = "sf")
  expect_s3_class(ggplot2::ggplotGrob(world_map(d, gdp_per_capita)), "gtable")
  expect_s3_class(ggplot2::ggplotGrob(globe_map(d, gdp_per_capita)), "gtable")
  expect_s3_class(ggplot2::ggplotGrob(projection_compare(d, gdp_per_capita)), "gtable")
  expect_s3_class(ggplot2::ggplotGrob(tissot_map("equal_earth")), "gtable")
  skip_if_not_installed("biscale")
  expect_s3_class(
    ggplot2::ggplotGrob(bivariate_map(d, gdp_per_capita, life_expectancy)), "gtable")
  skip_if_not_installed("cartogram")
  expect_s3_class(ggplot2::ggplotGrob(dorling_map(d, population)), "gtable")
})

# --- optional image snapshots --------------------------------------------------
#
# True image snapshots are opt-in rather than on by default. vdiffr compares
# rendered SVG, which depends on the host's font stack and freetype version, so
# committed snapshots taken on one machine routinely fail on another for reasons
# that have nothing to do with the package. The structural assertions above are
# the real net; this block is for a maintainer who wants pixels too. Enable with
#   Sys.setenv(COUNTRYATLAS_VDIFFR = "true")
# and run testthat::snapshot_accept() once to record the baseline.

test_that("map verbs match their image snapshots", {
  skip_on_cran()
  skip_if_not_installed("vdiffr")
  skip_if_not(identical(Sys.getenv("COUNTRYATLAS_VDIFFR"), "true"),
              "set COUNTRYATLAS_VDIFFR=true to run image snapshots")
  skip_poly()
  mapdf <- attach_geometry(snap, geometry = "polygon")
  vdiffr::expect_doppelganger("world_map quantile",
                              world_map(mapdf, gdp_per_capita, style = "quantile"))
  vdiffr::expect_doppelganger("world_map categorical",
                              world_map(mapdf, continent, style = "categorical"))
  vdiffr::expect_doppelganger("world_map hatched NA",
                              world_map(mapdf, gdp_per_capita, na_style = "hatched"))
  vdiffr::expect_doppelganger("bubble_map", bubble_map(snap, population))
  vdiffr::expect_doppelganger("spike_map", spike_map(snap, population))
  vdiffr::expect_doppelganger("tile_map", tile_map(snap, gdp_per_capita))
  vdiffr::expect_doppelganger("coverage_map", coverage_map(mapdf, gdp_per_capita))
  vdiffr::expect_doppelganger("value_by_alpha_map",
                              value_by_alpha_map(mapdf, gdp_per_capita, population))
})
