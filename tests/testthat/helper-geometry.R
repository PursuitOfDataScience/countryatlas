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
