# Projections for the polygon backend ---------------------------------------------
#
# world_map()'s signature said `projection = "equal_earth"`, and on the polygon
# backend -- the default of world_data(), join_world() and attach_geometry() --
# it drew through coord_quickmap(), unprojected, and said nothing:
# warn_projection_ignored() returned early on the default, so the happy path
# the README showed was an unprojected map from a package whose DESCRIPTION
# promises "projected, area-honest maps". Every polygon-backend verb now draws
# through wdj_polygon_coord(): coord_sf() over the unchanged longitude/latitude
# frame when sf loads, a built-in spherical Equal Earth when it does not, and
# coord_quickmap() only when asked for with projection = "none".

# Spherical Equal Earth, forward (Savric, Patterson & Jenny 2019), in metres
# on the authalic sphere. Matches PROJ's +proj=eqearth +R=6371007.181.
EQEARTH_R <- 6371007.181
equal_earth_xy <- function(lon, lat, lon0 = 0) {
  A1 <- 1.340264; A2 <- -0.081106; A3 <- 0.000893; A4 <- 0.003796
  # Wrap only what lies outside [-180, 180]. A plain modulo sends +180 to
  # -180, and every ring and arc split at the antimeridian ends there, so each
  # one was drawn as a streak across the whole map.
  lam <- lon - lon0
  out <- !is.na(lam) & (lam > 180 | lam < -180)
  lam[out] <- ((lam[out] + 180) %% 360) - 180
  lam <- lam * pi / 180
  th <- asin(sqrt(3) / 2 * sin(lat * pi / 180))
  th2 <- th^2; th6 <- th2^3
  x <- 2 * sqrt(3) * lam * cos(th) /
    (3 * (9 * A4 * th6 * th2 + 7 * A3 * th6 + 3 * A2 * th2 + A1))
  y <- th * (A4 * th6 * th2 + A3 * th6 + A2 * th2 + A1)
  list(x = x * EQEARTH_R, y = y * EQEARTH_R)
}

#' Project longitude and latitude onto a countryatlas map
#'
#' The transform the polygon backend uses when `sf` cannot be loaded: a
#' spherical Equal Earth (Savric, Patterson & Jenny 2019) on the authalic
#' sphere, written out in base R so the default map is equal-area on any
#' installation. Use it to place your own points, labels or paths on such a
#' map, which is drawn in metres rather than degrees. Where `sf` loads, maps
#' are drawn with [ggplot2::coord_sf()] instead and take layers in longitude
#' and latitude directly, so there is nothing to convert.
#'
#' @param lon,lat Numeric vectors of longitude and latitude, in degrees.
#' @param projection `"equal_earth"` (default), computed here. Any other
#'   projection the package knows (see [projection_info()]) is computed by
#'   PROJ through `sf`, which must then be loadable.
#' @param recenter Optional central meridian, as in [world_map()].
#'
#' @return A tibble of `x` and `y`, in metres, one row per point; `NA` where a
#'   coordinate is missing.
#' @references
#' Savric, B., Patterson, T. & Jenny, B. (2019). The Equal Earth map
#' projection. *International Journal of Geographical Information Science*
#' 33(3), 454-465. \doi{10.1080/13658816.2018.1504949}
#' @seealso [world_map()], [zoom_map()]
#' @export
#' @examples
#' project_lonlat(c(2.35, -74.0), c(48.85, 40.7))   # Paris, New York
project_lonlat <- function(lon, lat, projection = "equal_earth",
                           recenter = NULL) {
  if (!is.numeric(lon) || !is.numeric(lat)) {
    wdj_abort(c(
      "{.arg lon} and {.arg lat} must be numeric.",
      "x" = "Got {.obj_type_friendly {lon}} and {.obj_type_friendly {lat}}."
    ))
  }
  if (length(lon) != length(lat)) {
    wdj_abort(c(
      "{.arg lon} and {.arg lat} must be the same length.",
      "x" = "Got {length(lon)} and {length(lat)}."
    ))
  }
  projection <- check_choice(projection, "projection", wdj_projections())
  if (!is.null(recenter)) check_number(recenter, "recenter", lo = -360, hi = 360)
  bad <- (!is.na(lat) & abs(lat) > 90) | (!is.na(lon) & !is.finite(lon))
  if (any(bad)) {
    wdj_abort("{.arg lat} must lie within [-90, 90] and {.arg lon} be finite.")
  }
  if (identical(projection, "equal_earth")) {
    xy <- equal_earth_xy(lon, lat, recenter %||% 0)
    return(tibble::tibble(x = xy$x, y = xy$y))
  }
  need_pkg("sf", sprintf('for project_lonlat(projection = "%s")', projection))
  ok <- !is.na(lon) & !is.na(lat)
  out <- matrix(NA_real_, length(lon), 2L)
  if (any(ok)) {
    out[ok, ] <- suppressWarnings(sf::sf_project(
      "EPSG:4326", wdj_crs(projection, recenter), cbind(lon[ok], lat[ok]),
      warn = FALSE))
  }
  tibble::tibble(x = out[, 1], y = out[, 2])
}

# How a polygon-backend map is drawn for `projection`: the coord to add, a
# transform the verb applies to its own lon/lat columns first (NULL when the
# coord projects for itself), the label provenance records, and the CRS a
# layer built in projected metres must be given in (NULL when there is none).
#
# 1. "none": coord_quickmap(), the 3.0.0 output, as the explicit way back.
# 2. "orthographic": coord_map() through mapproj, which cuts vertex data at the
#    horizon. coord_sf() cannot, and the far-side vertices are what produced
#    3.0.0's "Invalid graphics path" globes.
# 3. sf loads: coord_sf(crs, default_crs = 4326). The frame stays in
#    longitude/latitude, so any layer a caller adds in lon/lat is projected too.
#    `vertices = TRUE` projects the vertices here instead, under coord_fixed(),
#    for a renderer that ignores coord_sf() on ordinary layers (plotly).
# 4. sf does not load: the built-in spherical Equal Earth, applied to the
#    vertices, under coord_fixed(). Any other projection falls back to it with
#    a classed warning: equal-area beats unprojected as the fallback.
# Set while interactive_map(engine = "plotly") builds its map: plotly ignores
# coord_sf() on ordinary layers, so the vertices are projected instead.
.wdj_state <- new.env(parent = emptyenv())

wdj_polygon_coord <- function(projection = "equal_earth", recenter = NULL,
                              vertices = isTRUE(.wdj_state$project_vertices),
                              call = rlang::caller_env()) {
  if (identical(projection, "none")) {
    return(list(coord = ggplot2::coord_quickmap(), transform = NULL,
                label = "none", crs = NULL))
  }
  projection <- check_choice(projection, "projection", wdj_projections(),
                             call = call)
  if (!is.null(recenter)) {
    check_number(recenter, "recenter", lo = -360, hi = 360, call = call)
  }
  if (identical(projection, "orthographic")) {
    need_pkg("mapproj", 'for projection = "orthographic" on the polygon backend',
             call = call)
    return(list(coord = ggplot2::coord_map("orthographic",
                                           orientation = c(ORTHO_LAT0,
                                                           recenter %||% 0, 0)),
                transform = NULL, label = "orthographic", crs = NULL))
  }
  if (has_pkg("sf")) {
    crs <- wdj_crs(projection, recenter, call = call)
    if (isTRUE(vertices)) {
      lim <- wdj_lat_limits(projection)
      return(list(coord = ggplot2::coord_fixed(), label = projection, crs = NULL,
                  transform = function(lon, lat) {
                    if (!is.null(lim)) lat <- pmin(pmax(lat, lim[1]), lim[2])
                    sf_project_xy(lon, lat, crs)
                  }, transform_crs = crs))
    }
    return(list(coord = wdj_coord_sf(projection, recenter, lonlat = TRUE,
                                     call = call),
                transform = NULL, label = projection, crs = crs))
  }
  if (!identical(projection, "equal_earth")) {
    wdj_warn(c(
      "{.pkg sf} cannot be loaded, so {.val {projection}} cannot be drawn; the
       map uses the built-in Equal Earth instead.",
      "i" = "Equal-area is the safer fallback than no projection. Install or
             repair {.pkg sf} for the other projections, or pass
             {.code projection = \"none\"} for unprojected longitude/latitude."
    ), class = "countryatlas_projection_fallback")
  }
  lon0 <- recenter %||% 0
  list(coord = ggplot2::coord_fixed(),
       transform = function(lon, lat) equal_earth_xy(lon, lat, lon0),
       label = "equal_earth (spherical, built-in)", crs = NULL, lon0 = lon0)
}

# lon/lat to a CRS's metres through PROJ; NA where a point has no image.
sf_project_xy <- function(lon, lat, crs) {
  ok <- is.finite(lon) & is.finite(lat)
  out <- matrix(NA_real_, length(lon), 2L)
  if (any(ok)) {
    out[ok, ] <- suppressWarnings(sf::sf_project(
      "EPSG:4326", crs, cbind(lon[ok], lat[ok]), warn = FALSE))
  }
  out[!is.finite(out)] <- NA_real_
  list(x = out[, 1], y = out[, 2])
}

# One degree of latitude on the ground, in metres: the unit a spike's height
# and a grid cell's side are given in once a map is projected.
METRES_PER_DEGREE <- EQEARTH_R * pi / 180

# Apply a coord's transform to a polygon-backend frame's `long`/`lat`. The
# projected coordinates go into `long` and `lat` themselves, so every layer
# that maps those columns lands in the same space, and the degrees are kept in
# `.wdj_lon`/`.wdj_lat` for the steps that need geography (label centroids),
# with what it takes to project a new point the same way: `.wdj_lon0` for the
# built-in Equal Earth, `.wdj_crs` for PROJ.
apply_polygon_transform <- function(data, pc, lon = "long", lat = "lat") {
  # What the view cannot draw goes first, whichever coord projects the rest:
  # see clip_for_projection().
  if (identical(pc$label, "north_polar")) data <- drop_far_south(data, lat_col = lat)
  if (is.null(pc$transform) || !nrow(data)) return(data)
  data[[".wdj_lon"]] <- data[[lon]]
  data[[".wdj_lat"]] <- data[[lat]]
  xy <- pc$transform(data[[lon]], data[[lat]])
  data[[lon]] <- xy$x
  data[[lat]] <- xy$y
  data[[".wdj_projection"]] <- pc$label
  if (!is.null(pc$transform_crs)) {
    data[[".wdj_crs"]] <- pc$transform_crs
  } else {
    data[[".wdj_lon0"]] <- pc$lon0 %||% 0
  }
  data
}

# Project new points the way apply_polygon_transform() projected `d`.
reproject_like <- function(lon, lat, d) {
  if (".wdj_crs" %in% names(d)) return(sf_project_xy(lon, lat, d$.wdj_crs[1]))
  equal_earth_xy(lon, lat, if (".wdj_lon0" %in% names(d)) d$.wdj_lon0[1] else 0)
}

# Points in the projected metres of a polygon-backend map, for layers whose
# sizes must not change with latitude (spikes, grid cells): NULL when the map
# is drawn in degrees ("none", and orthographic through coord_map()).
polygon_metres <- function(lon, lat, pc) {
  if (!is.null(pc$transform)) return(pc$transform(lon, lat))
  if (is.null(pc$crs)) return(NULL)
  sf_project_xy(lon, lat, pc$crs)
}

# Cut a polygon-backend frame's rings at the antimeridian of a recentred map
# and shift every ring into the window [lon0 - 180, lon0 + 180). The bundled
# rings are already split at +/-180; recentring moves the edge to lon0 + 180,
# and a ring crossing it would be drawn as a streak across the whole map.
# Each ring is unwrapped, clipped against the window boundaries
# (Sutherland-Hodgman on a vertical line), and the pieces beyond a boundary are
# shifted back by 360 as rings of their own. Every other column is carried.
recenter_rings <- function(data, lon0) {
  if (is.null(lon0) || !nrow(data)) return(data)
  # Kept as given within a half-turn either way, so recenter = 180 runs from 0
  # to 360 rather than from -360 to 0; only a value past that is wrapped.
  if (lon0 > 180 || lon0 < -180) lon0 <- ((lon0 + 180) %% 360) - 180
  if (isTRUE(all.equal(lon0, 0))) return(data)
  lo <- lon0 - 180
  hi <- lon0 + 180
  data <- data[order(data$group, data$order), , drop = FALSE]
  idx <- split(seq_len(nrow(data)), data$group)
  next_group <- max(data$group, na.rm = TRUE)
  pieces <- vector("list", length(idx))
  for (g in seq_along(idx)) {
    rows <- idx[[g]]
    x <- data$long[rows]; y <- data$lat[rows]
    # Unwrap: no step longer than half the globe.
    d <- diff(x)
    d <- d - 360 * round(d / 360)
    x <- x[1] + c(0, cumsum(d))
    # Shift the ring's first vertex into the window.
    x <- x + 360 * ceiling((lo - x[1]) / 360)
    x <- x - 360 * (x[1] >= hi)
    if (all(x >= lo & x < hi)) {
      piece <- data[rows, , drop = FALSE]
      piece$long <- x
      pieces[[g]] <- piece
      next
    }
    out <- list()
    for (k in -1:1) {
      a <- lo + 360 * k; b <- hi + 360 * k
      cl <- clip_ring_x(x, y, a, b)
      if (length(cl$x) >= 3L) {
        piece <- data[rep(rows[1], length(cl$x)), , drop = FALSE]
        piece$long <- cl$x - 360 * k
        piece$lat <- cl$y
        piece$order <- seq_along(cl$x)
        if (length(out)) {
          next_group <- next_group + 1L
          piece$group <- next_group
        }
        out[[length(out) + 1L]] <- piece
      }
    }
    pieces[[g]] <- do.call(rbind, out)
  }
  out <- do.call(rbind, pieces)
  rownames(out) <- NULL
  out
}

# Clip one ring to a <= x <= b: Sutherland-Hodgman against each line in turn.
clip_ring_x <- function(x, y, a, b) {
  clip <- function(x, y, keep, edge) {
    n <- length(x)
    if (!n) return(list(x = numeric(), y = numeric()))
    ox <- numeric(); oy <- numeric()
    for (i in seq_len(n)) {
      j <- if (i == n) 1L else i + 1L
      pin <- keep(x[i]); qin <- keep(x[j])
      if (pin) { ox <- c(ox, x[i]); oy <- c(oy, y[i]) }
      if (pin != qin) {
        t <- (edge - x[i]) / (x[j] - x[i])
        ox <- c(ox, edge); oy <- c(oy, y[i] + t * (y[j] - y[i]))
      }
    }
    list(x = ox, y = oy)
  }
  r <- clip(x, y, function(v) v >= a, a)
  clip(r$x, r$y, function(v) v <= b, b)
}

#' Zoom a map without losing its projection
#'
#' Show part of a map by longitude and latitude limits while keeping the
#' projection it was drawn in. The 3.0.0 documentation zoomed with
#' `coord_quickmap(xlim, ylim)`, which on a projected map silently replaces
#' the projection with an unprojected one.
#'
#' @param p A map from one of the package's map verbs.
#' @param xlim,ylim Longitude and latitude limits, in degrees, each a pair
#'   `c(min, max)`.
#'
#' @return `p` with the view limited, in the same projection.
#' @seealso [world_map()], [project_lonlat()]
#' @export
#' @examples
#' \donttest{
#' snap <- countryatlas::world_snapshot$countries
#' europe <- attach_geometry(snap, geometry = "polygon") |>
#'   world_map(gdp_per_capita)
#' zoom_map(europe, xlim = c(-25, 45), ylim = c(34, 72))
#' }
zoom_map <- function(p, xlim, ylim) {
  if (!inherits(p, "ggplot")) {
    wdj_abort(c("{.arg p} must be a map from one of the package's map verbs.",
                "x" = "Got {.obj_type_friendly {p}}."))
  }
  for (nm in c("xlim", "ylim")) {
    v <- get(nm)
    if (!is.numeric(v) || length(v) != 2L || anyNA(v) || v[1] >= v[2]) {
      wdj_abort(c("{.arg {nm}} must be two increasing numbers, in degrees.",
                  "x" = "Got {.val {v}}."))
    }
  }
  if (abs(xlim[1]) > 360 || abs(xlim[2]) > 360 || any(abs(ylim) > 90)) {
    wdj_abort("{.arg xlim} and {.arg ylim} are longitude and latitude, in
               degrees.")
  }
  coord <- p$coordinates
  new <- if (inherits(coord, "CoordSf")) {
    # Limits in the default (lon/lat) CRS, converted by coord_sf() itself.
    zoomed <- ggplot2::coord_sf(crs = coord$crs, default_crs = sf::st_crs(4326L),
                                xlim = xlim, ylim = ylim, datum = coord$datum,
                                expand = FALSE)
    # A polygon-backend map keeps drawing its dense rings as given.
    if (isTRUE(coord$is_linear())) dense_coord(zoomed) else zoomed
  } else if (inherits(coord, "CoordMap")) {
    ggplot2::coord_map(coord$projection, parameters = coord$params,
                       orientation = coord$orientation, xlim = xlim, ylim = ylim)
  } else if (!inherits(coord, "CoordQuickmap") &&
             ".wdj_projection" %in% names(gg_plot_data(p) %||% list())) {
    # Vertices projected by the verb: the limits are degrees, the plot is
    # metres, so project the window's outline the way the vertices were.
    corners <- expand.grid(lon = seq(xlim[1], xlim[2], length.out = 25),
                           lat = seq(ylim[1], ylim[2], length.out = 25))
    xy <- reproject_like(corners$lon, corners$lat, gg_plot_data(p))
    ggplot2::coord_fixed(xlim = range(xy$x, na.rm = TRUE),
                         ylim = range(xy$y, na.rm = TRUE), expand = FALSE)
  } else {
    ggplot2::coord_quickmap(xlim = xlim, ylim = ylim)
  }
  out <- suppressMessages(p + new)
  # The provenance and the other attributes are the map's, not the coord's.
  for (a in setdiff(names(attributes(p)), names(attributes(out)))) {
    attr(out, a) <- attr(p, a)
  }
  out
}
