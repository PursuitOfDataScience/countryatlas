# Projection metadata, comparison and distortion ---------------------------------
# The package's tagline promises *honest* maps, and until now that meant "the
# equal-area projections are in the list". These verbs make the claim
# inspectable: what a projection preserves, what the same data looks like under
# several of them, and how much a given one actually distorts.

# The property table behind projection_info(). One row per projection in
# wdj_projections(); `family` is the construction, `property` is the thing a
# reader can rely on.
wdj_projection_table <- function() {
  tibble::tribble(
    ~projection,            ~family,      ~property,     ~equal_area, ~conformal, ~note,
    "equal_earth",          "pseudocylindrical", "equal-area",  TRUE,  FALSE,
    "Recommended default for world thematic maps: equal-area, Robinson-like in appearance (Savric, Patterson & Jenny 2019).",
    "robinson",             "pseudocylindrical", "compromise",  FALSE, FALSE,
    "Neither equal-area nor conformal; chosen for looks. Areas near the poles are overstated.",
    "mollweide",            "pseudocylindrical", "equal-area",  TRUE,  FALSE,
    "Equal-area, with strong shape distortion at the edges.",
    "natural_earth",        "pseudocylindrical", "compromise",  FALSE, FALSE,
    "Compromise projection in the Robinson tradition.",
    "plate_carree",         "cylindrical",       "equidistant", FALSE, FALSE,
    "Equirectangular. Neither equal-area nor conformal; convenient, not honest.",
    "mercator",             "cylindrical",       "conformal",   FALSE, TRUE,
    "Conformal, and famously area-dishonest: Greenland reads as the size of Africa. Do not use for choropleths.",
    "winkel_tripel",        "pseudoazimuthal",   "compromise",  FALSE, FALSE,
    "Compromise; minimises mean distortion of area, direction and distance.",
    "eckert4",              "pseudocylindrical", "equal-area",  TRUE,  FALSE,
    "Equal-area, with rounded poles.",
    "gall_peters",          "cylindrical",       "equal-area",  TRUE,  FALSE,
    "Equal-area cylindrical; shapes are badly stretched away from the standard parallels.",
    "orthographic",         "azimuthal",         "perspective", FALSE, FALSE,
    "A view of the globe from infinity; only one hemisphere is visible. See globe_map().",
    "azimuthal_equal_area", "azimuthal",         "equal-area",  TRUE,  FALSE,
    "Equal-area about a chosen centre.",
    "north_polar",          "azimuthal",         "equal-area",  TRUE,  FALSE,
    "Lambert azimuthal equal-area centred on the North Pole.",
    "south_polar",          "azimuthal",         "equal-area",  TRUE,  FALSE,
    "Lambert azimuthal equal-area centred on the South Pole."
  )
}

#' What a projection preserves
#'
#' Look up the properties of the projections [world_map()] understands: the
#' construction family, whether it is equal-area (a choropleth's ink is
#' proportional to ground area) or conformal (shapes are locally right), and the
#' PROJ string the package builds. Called with no arguments it returns the whole
#' table, which is the quickest way to see what is available.
#'
#' @param projection A projection name, or `NULL` (the default) for every one.
#'
#' @return A tibble with one row per projection: `projection`, `family`,
#'   `property`, `equal_area`, `conformal`, `note` and `proj4`.
#'
#' @section Choosing one:
#' For a world choropleth the honest choice is **equal-area**, because the eye
#' reads coloured area as quantity: a projection that inflates Greenland makes
#' Greenland's value look more important than it is. Equal Earth is the
#' recommended default (and the package's own) -- it is equal-area, close to
#' Robinson in appearance, and cheap to evaluate (Savric, Patterson & Jenny
#' 2019). `"mercator"` is conformal, not equal-area, and should not be used for
#' choropleths. Use [projection_compare()] to see the difference on your own
#' data, and [tissot_map()] to see it on the graticule.
#'
#' @references
#' Savric, B., Patterson, T. & Jenny, B. (2019). The Equal Earth map projection.
#' *International Journal of Geographical Information Science* 33(3), 454-465.
#' \doi{10.1080/13658816.2018.1504949}
#'
#' @seealso [projection_compare()], [tissot_map()], [world_map()]
#' @export
#' @examples
#' projection_info()
#' projection_info("mercator")
#' # every equal-area projection the package can build
#' subset(projection_info(), equal_area)$projection
projection_info <- function(projection = NULL) {
  tab <- wdj_projection_table()
  if (!is.null(projection)) {
    check_string(projection, "projection")
    if (!projection %in% tab$projection) {
      wdj_abort(c(
        "Unknown projection {.val {projection}}.",
        "i" = "Available: {.val {tab$projection}}."
      ))
    }
    tab <- tab[tab$projection == projection, ]
  }
  # Built rather than stored, so the table can never drift from wdj_crs().
  tab$proj4 <- vapply(tab$projection, function(p) wdj_crs(p), character(1),
                      USE.NAMES = FALSE)
  tab
}

#' The same map under several projections
#'
#' Small multiples of one choropleth, drawn once per projection, so the cost of
#' a projection choice is visible rather than asserted. The data and the
#' classification are held fixed; only the CRS varies.
#'
#' @param data An `sf` map-ready frame (projections are an `sf`-backend
#'   feature; the polygon backend draws in `coord_quickmap()` and cannot
#'   reproject).
#' @param fill The fill column (unquoted).
#' @param projections Projections to compare (default: Equal Earth, Robinson,
#'   Winkel tripel and Mercator -- an equal-area, two compromises and a
#'   conformal). See [projection_info()].
#' @param ncol Number of facet columns.
#' @param labeller `"name"` (default) labels each panel with the projection
#'   name; `"property"` appends what it preserves, which is the point of the
#'   comparison.
#' @param ... Passed to [world_map()] (e.g. `style`, `palette`, `n_bins`).
#'
#' @return A faceted `ggplot` object.
#' @seealso [projection_info()], [tissot_map()]
#' @export
#' @examples
#' \donttest{
#' if (requireNamespace("sf", quietly = TRUE) &&
#'     requireNamespace("rnaturalearth", quietly = TRUE)) {
#'   attach_geometry(countryatlas::world_snapshot$countries, geometry = "sf") |>
#'     projection_compare(gdp_per_capita, style = "quantile")
#' }
#' }
projection_compare <- function(data, fill,
                               projections = c("equal_earth", "robinson",
                                               "winkel_tripel", "mercator"),
                               ncol = NULL, labeller = c("name", "property"),
                               ...) {
  need_pkg("sf", "for projection_compare()")
  labeller <- rlang::arg_match(labeller)
  fill_q <- rlang::enquo(fill)
  fill_name <- quo_arg_name(fill_q, "fill")
  if (!is_sf(data)) {
    wdj_abort(c(
      "{.fn projection_compare} needs an sf frame.",
      "i" = 'Reprojection is an sf-backend feature; attach geometry with
             {.code attach_geometry(data, geometry = "sf")}.'
    ))
  }
  check_cols(data, fill_name)
  if (!length(projections)) {
    wdj_abort("{.arg projections} must name at least one projection.")
  }
  known <- wdj_projections()
  bad <- setdiff(projections, known)
  if (length(bad)) {
    wdj_abort(c(
      "Unknown projection{?s} {.val {bad}}.",
      "i" = "Available: {.val {known}}."
    ))
  }

  info <- projection_info()
  lab_of <- function(p) {
    if (identical(labeller, "name")) return(p)
    # Second line, not parentheses: the one-line form ran past the panel and got
    # clipped ("...inkel_tripel (compromise").
    paste0(p, "\n", info$property[info$projection == p])
  }
  # Reproject each panel's geometry separately, then bind: faceting one frame
  # cannot work, because a single coord_sf() carries a single CRS. rbind() on sf
  # refuses mixed CRSs ("arguments have different crs"), so drop the CRS once
  # each panel is projected -- the coordinates are already in that projection's
  # own plane, and what follows only has to draw them, not transform them again.
  levs <- vapply(projections, lab_of, character(1), USE.NAMES = FALSE)
  panels <- lapply(projections, function(p) {
    src <- data
    # Same clip world_map() applies via coord_sf(); here it has to happen on the
    # geometry, because these panels are pre-projected and carry no CRS for
    # coord_sf() to convert limits against.
    ylim <- wdj_lat_limits(p)
    if (!is.null(ylim)) {
      # In lon/lat, not in whatever CRS `data` arrived in: attach_geometry()
      # already projects (Equal Earth by default), so a degrees-valued box
      # against a metres CRS crops to nothing.
      box <- sf::st_bbox(c(xmin = -180, ymin = ylim[1], xmax = 180, ymax = ylim[2]),
                         crs = sf::st_crs(4326L))
      # Natural Earth's 110m rings include a self-intersecting one that the
      # strict S2 engine st_crop() defaults to on lon/lat geometry rejects
      # outright ("Loop 0 is not valid: Edge 77 crosses edge 79"). GEOS's planar
      # crop is plenty accurate for lopping off a polar cap -- the same fallback
      # country_borders() and locate_country() already make.
      use_s2 <- sf::sf_use_s2()
      on.exit(quietly_sf(sf::sf_use_s2(use_s2)), add = TRUE)
      src <- quietly_sf(suppressWarnings({
        sf::sf_use_s2(FALSE)
        sf::st_crop(sf::st_transform(src, 4326L), box)
      }))
    }
    g <- quietly_sf(sf::st_set_crs(sf::st_transform(src, wdj_crs(p)), NA))
    # Each projection lands in its own units and extent -- Mercator's y range is
    # orders of magnitude larger than Equal Earth's -- so at a shared scale
    # every panel but the biggest collapses to a speck. `scales = "free"` is not
    # the way out: facet_wrap() refuses free scales under coord_sf(). Instead
    # normalise each panel to a common box, *preserving aspect ratio*, which is
    # what carries the distortion signal. The comparison is of shape and
    # relative area, not of print size.
    bb <- sf::st_bbox(g)
    half <- max((bb$xmax - bb$xmin), (bb$ymax - bb$ymin)) / 2
    ctr <- c((bb$xmax + bb$xmin) / 2, (bb$ymax + bb$ymin) / 2)
    sf::st_geometry(g) <- (sf::st_geometry(g) - ctr) / half
    g$.wdj_projection <- factor(lab_of(p), levels = levs)
    g
  })
  combined <- do.call(rbind, panels)

  # Geometry is already reprojected and normalised, so coord_sf() must only draw
  # it: `datum = NA` stops it re-transforming or building a graticule for a CRS
  # these coordinates no longer carry. Replacing world_map()'s own coord is
  # deliberate, so suppress ggplot2's note about it.
  suppressMessages(
    world_map(combined, !!fill_q, ...) +
      ggplot2::coord_sf(datum = NA) +
      ggplot2::facet_wrap(ggplot2::vars(.data$.wdj_projection), ncol = ncol)
  )
}

#' Tissot's indicatrix: what a projection does to the ground
#'
#' Draws Tissot indicatrices -- small circles of equal ground radius, placed on
#' a graticule and projected with everything else. On an equal-area projection
#' every ellipse encloses the same area (though shapes shear); on a conformal
#' projection every ellipse stays circular but sizes explode. It is the standard
#' cartographic device for showing what a projection costs, and it makes the
#' package's "honest maps" claim visible instead of asserted.
#'
#' @param projection Projection to illustrate (see [projection_info()]).
#' @param spacing Degrees between indicatrices (default `30`).
#' @param radius_km Ground radius of each circle in kilometres (default `500`).
#' @param max_lat Absolute latitude limit for the circle centres (default `75`;
#'   the poles are singular in most projections).
#' @param fill,color Fill and outline colour for the ellipses.
#'
#' @return A `ggplot` object: the world outline with indicatrices on top.
#' @seealso [projection_info()], [projection_compare()]
#' @export
#' @examples
#' \donttest{
#' if (requireNamespace("sf", quietly = TRUE) &&
#'     requireNamespace("rnaturalearth", quietly = TRUE)) {
#'   tissot_map("mercator")      # circles stay round, and grow enormously
#'   tissot_map("equal_earth")   # equal areas, sheared shapes
#' }
#' }
tissot_map <- function(projection = "equal_earth", spacing = 30,
                       radius_km = 500, max_lat = 75,
                       fill = "#B2182B", color = "grey20") {
  need_pkg("sf", "for tissot_map()")
  check_number(spacing, "spacing", lo = 1, hi = 180)
  check_number(radius_km, "radius_km", lo = 1)
  check_number(max_lat, "max_lat", lo = 1, hi = 89)
  projection <- check_choice(projection, "projection", wdj_projections())
  crs <- wdj_crs(projection)

  lons <- seq(-180, 180, by = spacing)
  lons <- lons[lons < 180]                      # -180 and 180 are the same meridian
  lats <- seq(-max_lat, max_lat, by = spacing)
  centres <- expand.grid(lon = lons, lat = lats)

  # Build each circle on the sphere rather than in projected space: a fixed
  # ground radius is the whole point, so the vertices are generated by walking
  # `radius_km` out along every azimuth from the centre.
  circle <- function(lon0, lat0, n = 72) {
    az <- seq(0, 2 * pi, length.out = n + 1)
    d <- radius_km / EARTH_RADIUS_KM
    phi1 <- lat0 * pi / 180
    lam1 <- lon0 * pi / 180
    phi <- asin(sin(phi1) * cos(d) + cos(phi1) * sin(d) * cos(az))
    lam <- lam1 + atan2(sin(az) * sin(d) * cos(phi1),
                        cos(d) - sin(phi1) * sin(phi))
    cbind((lam * 180 / pi + 180) %% 360 - 180, phi * 180 / pi)
  }
  polys <- lapply(seq_len(nrow(centres)), function(i) {
    xy <- circle(centres$lon[i], centres$lat[i])
    # A circle that crosses the antimeridian would be drawn as a band right
    # across the map; drop those rather than lie about them.
    if (diff(range(xy[, 1])) > 180) return(NULL)
    sf::st_polygon(list(xy))
  })
  keep <- !vapply(polys, is.null, logical(1))
  ind <- sf::st_sf(id = seq_len(sum(keep)),
                   geometry = sf::st_sfc(polys[keep], crs = 4326L))

  base <- world_geometry("countries", geometry = "sf", projection = projection)
  ggplot2::ggplot() +
    ggplot2::geom_sf(data = base, fill = "grey92", color = "grey80",
                     linewidth = 0.1) +
    ggplot2::geom_sf(data = quietly_sf(sf::st_transform(ind, crs)),
                     fill = fill, alpha = 0.45, color = color, linewidth = 0.2) +
    wdj_coord_sf(projection) +
    ggplot2::labs(title = paste0(projection, " - ",
                                 projection_info(projection)$property)) +
    theme_world_map()
}

#' Measure what a projection distorts
#'
#' The numeric companion to [tissot_map()]: distortion sampled on a grid, so it
#' can be summarised, compared or mapped rather than eyeballed. Computed by
#' projecting a small circle at each grid point and measuring what happens to
#' it, which is the definition rather than an approximation of it.
#'
#' @param projection Projection to measure (see [projection_info()]).
#' @param measure `"areal"` (default; projected area divided by true ground
#'   area, so 1 is undistorted), `"angular"` (maximum angular deformation in
#'   degrees, 0 for a conformal projection) or `"max_scale"` (the larger
#'   principal scale factor).
#' @param spacing Grid spacing in degrees (default `10`).
#' @param max_lat Absolute latitude limit (default `85`).
#'
#' @return A tibble of `lon`, `lat` and `distortion`, with the area-weighted
#'   mean and the range attached as the `"countryatlas_distortion"` attribute.
#'
#' @section Reading the numbers:
#' An equal-area projection has `"areal"` distortion of 1 everywhere -- that is
#' what equal-area *means*, and it is worth checking rather than trusting.
#' A conformal projection has `"angular"` distortion of 0 everywhere and
#' unbounded areal distortion. A compromise projection is bad at both by a
#' little, everywhere, which is the trade it makes.
#'
#' @seealso [tissot_map()], [projection_info()], [projection_compare()]
#' @export
#' @examples
#' \donttest{
#' if (requireNamespace("sf", quietly = TRUE)) {
#'   d <- projection_distortion("mercator", measure = "areal")
#'   attr(d, "countryatlas_distortion")
#' }
#' }
projection_distortion <- function(projection = "equal_earth",
                                  measure = c("areal", "angular", "max_scale"),
                                  spacing = 10, max_lat = 85) {
  need_pkg("sf", "for projection_distortion()")
  measure <- rlang::arg_match(measure)
  check_number(spacing, "spacing", lo = 1, hi = 90)
  check_number(max_lat, "max_lat", lo = 1, hi = 89)
  projection <- check_choice(projection, "projection", wdj_projections())
  crs <- wdj_crs(projection)

  lons <- seq(-180, 180, by = spacing); lons <- lons[lons < 180]
  lats <- seq(-max_lat, max_lat, by = spacing)
  grid <- expand.grid(lon = lons, lat = lats)

  # Finite-difference the projection at each point: step a small distance east
  # and north, and read the local Jacobian off the projected offsets. Everything
  # below -- area, angle, scale -- is a function of its singular values.
  eps <- 1e-3
  base <- cbind(grid$lon, grid$lat)
  east <- cbind(grid$lon + eps, grid$lat)
  north <- cbind(grid$lon, grid$lat + eps)
  pr <- function(m) {
    p <- sf::st_as_sf(data.frame(x = m[, 1], y = m[, 2]),
                      coords = c("x", "y"), crs = 4326L)
    sf::st_coordinates(quietly_sf(suppressWarnings(sf::st_transform(p, crs))))
  }
  p0 <- pr(base); pe <- pr(east); pn <- pr(north)

  # Metres per degree on the sphere at this latitude, so the Jacobian is
  # dimensionless (projected metres per ground metre) rather than per-degree.
  d2r <- pi / 180
  mx <- EARTH_RADIUS_KM * 1000 * d2r * cos(grid$lat * d2r)
  my <- EARTH_RADIUS_KM * 1000 * d2r
  a <- (pe[, 1] - p0[, 1]) / (eps * mx)
  b <- (pn[, 1] - p0[, 1]) / (eps * my)
  cc <- (pe[, 2] - p0[, 2]) / (eps * mx)
  d <- (pn[, 2] - p0[, 2]) / (eps * my)

  det <- a * d - b * cc
  # Principal scale factors: the singular values of the 2x2 Jacobian. For a
  # matrix with Frobenius norm F and determinant D,
  #   (s1 + s2)^2 = F + 2|D|   and   (s1 - s2)^2 = F - 2|D|,
  # which gives both without forming an SVD per grid point.
  fro <- a^2 + b^2 + cc^2 + d^2
  sum_s <- sqrt(pmax(0, fro + 2 * abs(det)))     # s1 + s2
  dif_s <- sqrt(pmax(0, fro - 2 * abs(det)))     # |s1 - s2|
  s1 <- (sum_s + dif_s) / 2

  distortion <- switch(
    measure,
    areal = abs(det),
    # Tissot's maximum angular deformation: sin(omega/2) = (s1-s2)/(s1+s2).
    # It is 0 exactly when s1 == s2, i.e. for a conformal projection -- which
    # is the check that caught this being written upside down as s2/s1, giving
    # Mercator 170 degrees of angular distortion instead of none.
    angular = 2 * asin(pmin(1, ifelse(sum_s > 0, dif_s / sum_s, 0))) / d2r,
    max_scale = s1
  )
  out <- tibble::tibble(lon = grid$lon, lat = grid$lat,
                        distortion = as.numeric(distortion))
  out <- out[is.finite(out$distortion), ]
  w <- cos(out$lat * d2r)
  attr(out, "countryatlas_distortion") <- tibble::tibble(
    projection = projection, measure = measure,
    mean = stats::weighted.mean(out$distortion, w),
    min = min(out$distortion), max = max(out$distortion)
  )
  out
}
