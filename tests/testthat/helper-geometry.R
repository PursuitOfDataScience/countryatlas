# The sf *geometry backend* is not just sf. build_world_sf() gates on three
# packages (see need_pkg() in R/geometry.R), so skip_if_not_installed("sf")
# alone is an incomplete guard: on a machine that has sf but not the Natural
# Earth data packages, the test runs and errors instead of skipping. Three
# tests were failing that way, found only by checking under R 4.1 -- the
# maintainer's R 4.4 library happens to have rnaturalearth installed, which
# hid it.
skip_if_no_sf_geometry <- function() {
  testthat::skip_if_not_installed("sf")
  testthat::skip_if_not_installed("rnaturalearth")
  testthat::skip_if_not_installed("rnaturalearthdata")
}

# A tiny polygon-backend frame: one square per country, far enough apart not
# to touch. world_map() and friends only need long/lat/group, so this
# exercises the drawing and counting paths without the `maps` package.
# `n_vertices` gives each country that many vertex rows (default 4), which is
# what a test needs to catch a statistic weighted by outline complexity: the
# real polygon backend repeats a country's values down hundreds of vertices,
# and a different number for every country.
toy_polygons <- function(values, n_vertices = 4L) {
  iso <- names(values)
  n_vertices <- rep_len(n_vertices, length(iso))
  do.call(rbind, lapply(seq_along(iso), function(i) {
    k <- n_vertices[i]
    # The unit square for the default, and a regular k-gon inside the same
    # cell otherwise.
    a <- seq(0, 2 * pi, length.out = k + 1L)[-(k + 1L)]
    xy <- if (k == 4L) list(c(0, 1, 1, 0), c(0, 0, 1, 1)) else
      list(0.5 + 0.5 * cos(a), 0.5 + 0.5 * sin(a))
    data.frame(long = xy[[1]] + 3 * i, lat = xy[[2]],
               group = i, order = seq_len(k), iso3c = iso[i], v = values[[i]],
               stringsAsFactors = FALSE)
  }))
}
