# Colour-vision checks ---------------------------------------------------------------

#' Check a map's colours under colour-vision deficiency
#'
#' Simulate how the map's fill colours look with deuteranopia, protanopia and
#' tritanopia -- the Machado, Oliveira & Fernandes (2009) model, through the
#' optional `colorspace` -- and report the smallest colour difference between
#' adjacent classes under each. Two classes a reader cannot tell apart are two
#' classes the map does not have. Roughly one man in twelve has a red-green
#' deficiency.
#'
#' The difference is CIE 1976 \eqn{\Delta E^*_{ab}}, the distance between the
#' two colours in CIELAB. A difference under about 10 is hard to tell apart
#' at the size of a small country on a map; the package's own defaults (the
#' viridis family) clear it under all three simulations.
#'
#' @param p A map from one of the package's map verbs, or a character vector
#'   of colours in class order.
#' @param threshold The smallest acceptable difference between adjacent
#'   classes (default `10`). Below it, a warning of class
#'   `countryatlas_palette_cvd` names the vision type and the two classes.
#'
#' @return A tibble with one row per vision type (`normal`, `deuteranopia`,
#'   `protanopia`, `tritanopia`): `min_delta_e`, and `between`, the two classes
#'   that come closest.
#' @references
#' Machado, G. M., Oliveira, M. M. & Fernandes, L. A. F. (2009). A
#' physiologically-based model for simulation of color vision deficiency.
#' *IEEE Transactions on Visualization and Computer Graphics* 15(6),
#' 1291-1298. \doi{10.1109/TVCG.2009.113}
#'
#' Crameri, F., Shephard, G. E. & Heron, P. J. (2020). The misuse of colour in
#' science communication. *Nature Communications* 11, 5444.
#' \doi{10.1038/s41467-020-19160-7}
#' @export
#' @examples
#' \donttest{
#' if (requireNamespace("colorspace", quietly = TRUE)) {
#'   snap <- countryatlas::world_snapshot$countries
#'   check_palette(world_map(attach_geometry(snap), gdp_per_capita))
#'   # A rainbow fails all three simulations:
#'   check_palette(grDevices::rainbow(7))
#' }
#' }
check_palette <- function(p, threshold = 10) {
  check_number(threshold, "threshold", lo = 0)
  need_pkg("colorspace", "to simulate colour-vision deficiency")
  cols <- if (is.character(p)) p else map_class_colours(p)
  if (length(cols) < 2L) {
    wdj_abort(c("There is nothing to compare: the map has fewer than two fill
                 colours."))
  }
  if (is.null(names(cols))) names(cols) <- seq_along(cols)
  sims <- list(normal = cols,
               deuteranopia = colorspace::deutan(cols),
               protanopia = colorspace::protan(cols),
               tritanopia = colorspace::tritan(cols))
  lab <- function(x) {
    grDevices::convertColor(t(grDevices::col2rgb(x)) / 255, from = "sRGB",
                            to = "Lab")
  }
  adjacent <- function(x) sqrt(rowSums(diff(lab(x))^2))
  out <- tibble::tibble(
    vision = names(sims),
    min_delta_e = vapply(sims, function(s) min(adjacent(s)), numeric(1)),
    between = vapply(sims, function(s) {
      i <- which.min(adjacent(s))
      paste(names(cols)[i], "and", names(cols)[i + 1L])
    }, character(1)))
  bad <- out$min_delta_e < threshold
  if (any(bad)) {
    wdj_warn(c(
      "Adjacent classes are hard to tell apart under
       {.val {out$vision[bad]}}.",
      "*" = "{out$vision[bad]}: {out$between[bad]} (difference
             {round(out$min_delta_e[bad], 1)}).",
      "i" = "Use fewer classes, or a palette whose lightness changes
             monotonically, such as {.val viridis} or {.val cividis}."
    ), class = "countryatlas_palette_cvd")
  }
  out
}

# The fill colours a map draws, in class order: each class of a discrete
# scale, each bin of a binned one, and seven steps along a colourbar.
map_class_colours <- function(p) {
  if (!inherits(p, "ggplot")) {
    wdj_abort(c("{.arg p} must be a map or a vector of colours.",
                "x" = "Got {.obj_type_friendly {p}}."))
  }
  b <- ggplot2::ggplot_build(p)
  sc <- b$plot$scales$get_scales("fill")
  if (is.null(sc)) wdj_abort("The map has no fill scale to check.")
  if (inherits(sc, "ScaleDiscrete")) {
    lim <- sc$get_limits()
    lim <- lim[!is.na(lim)]
    return(stats::setNames(sc$map(lim), lim))
  }
  lim <- sc$get_limits()
  if (inherits(sc, "ScaleBinned")) {
    br <- sc$get_breaks()
    edges <- sort(unique(c(lim[1], br[is.finite(br)], lim[2])))
    mids <- (edges[-1] + edges[-length(edges)]) / 2
    return(stats::setNames(sc$map(mids), si_label(mids)))
  }
  at <- seq(lim[1], lim[2], length.out = 7)
  stats::setNames(sc$map(at), si_label(at))
}
