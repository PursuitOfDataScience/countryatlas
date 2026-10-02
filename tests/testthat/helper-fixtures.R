# Fixtures shared by the module test files.

snap <- countryatlas::world_snapshot$countries

poly_df <- function() {
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
  expect_s3_class(ggplot2::ggplotGrob(p), "gtable")
  invisible(p)
}

# A plot's caption, whichever ggplot2 is installed.
gg_caption_of <- function(p) {
  if ("get_labs" %in% getNamespaceExports("ggplot2")) {
    ggplot2::get_labs(p)$caption
  } else {
    p$labels$caption
  }
}
