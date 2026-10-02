# Small states, drawn rather than dropped ---------------------------------------------
#
# A country the basemap has no polygon for vanished from the map even when it
# had data: the sf backend at its default 1:110m carries 170 of the
# snapshot's 216 countries, and the 46 others were left out without a word.
# attach_geometry() now remembers the rows it could not place, and the map
# verbs draw them as points at their country_meta centroid, on the same scale
# as the polygons.

# The rows of `data` that attach_geometry() found no geometry for, kept on the
# result so a map can still draw them.
set_unplaced <- function(out, data, by, geom_keys) {
  rows <- tibble::as_tibble(sf_drop(data))
  rows <- rows[!is.na(rows[[by]]) & !rows[[by]] %in% geom_keys, , drop = FALSE]
  attr(out, "countryatlas_unplaced") <- if (nrow(rows)) rows
  out
}

# The points a map draws for small states: `"auto"`, the countries with a
# value and no polygon; `"dots"`, those and every country in the frame whose
# area is under `small_area_km2`. A country with neither a polygon nor a
# bundled centroid cannot be drawn at all and is reported by name.
small_state_points <- function(data, fill_name, mode, small_area_km2,
                               call = rlang::caller_env()) {
  empty <- list(points = NULL, unplaced = character(0), undrawable = character(0),
                n_unplaced_missing = 0L)
  if (identical(mode, "none")) return(empty)
  meta <- countryatlas::country_meta[, c("iso3c", "centroid_lon", "centroid_lat",
                                         "area_km2")]
  unplaced <- attr(data, "countryatlas_unplaced")
  pts <- NULL
  out <- empty
  if (!is.null(unplaced) && "iso3c" %in% names(unplaced) &&
      fill_name %in% names(unplaced)) {
    unplaced <- unplaced[!unplaced$iso3c %in% data$iso3c, , drop = FALSE]
    with_value <- has_value(unplaced[[fill_name]])
    out$unplaced <- sort(unique(unplaced$iso3c))
    out$n_unplaced_missing <- length(unique(unplaced$iso3c[!with_value]))
    pts <- unplaced[with_value, , drop = FALSE]
  }
  if (identical(mode, "dots") && "iso3c" %in% names(data)) {
    # One row per country of the frame; the polygon backend repeats a
    # country's values down every vertex.
    df <- tibble::as_tibble(sf_drop(data))
    df <- df[!duplicated(df$iso3c) & !is.na(df$iso3c), , drop = FALSE]
    df <- drop_map_geometry(df)
    tiny <- meta$iso3c[!is.na(meta$area_km2) & meta$area_km2 < small_area_km2]
    df <- df[df$iso3c %in% tiny & has_value(df[[fill_name]]), , drop = FALSE]
    pts <- dplyr::bind_rows(pts, df)
  }
  if (is.null(pts) || !nrow(pts)) return(out)
  pts <- drop_centroid_cols(pts)
  pts <- dplyr::left_join(pts, meta[, c("iso3c", "centroid_lon", "centroid_lat")],
                          by = "iso3c", na_matches = "never",
                          relationship = "many-to-one")
  ok <- !is.na(pts$centroid_lon) & !is.na(pts$centroid_lat)
  out$undrawable <- sort(unique(pts$iso3c[!ok]))
  pts <- pts[ok, , drop = FALSE]
  names(pts)[names(pts) == "centroid_lon"] <- ".wdj_pt_lon"
  names(pts)[names(pts) == "centroid_lat"] <- ".wdj_pt_lat"
  out$points <- pts
  out
}

# Coverage with the small states counted: the unplaced countries join the
# denominator, the ones drawn as points count as shown, and the rest -- no
# value, or nowhere to draw one -- as missing.
small_state_coverage <- function(coverage, ss) {
  if (!length(ss$unplaced)) return(coverage)
  drawn <- if (is.null(ss$points)) character(0) else
    intersect(unique(ss$points$iso3c), ss$unplaced)
  lost <- setdiff(ss$unplaced, drawn)
  coverage$n_total <- coverage$n_total + length(ss$unplaced)
  coverage$n_shown <- coverage$n_shown + length(drawn)
  coverage$n_missing <- coverage$n_missing + length(lost)
  coverage$missing_iso3c <- sort(c(coverage$missing_iso3c, lost))
  coverage
}

# The caption's sentence about them.
small_state_note <- function(ss) {
  n <- if (is.null(ss$points)) 0L else length(unique(ss$points$iso3c))
  parts <- c(
    if (n) sprintf("%d %s drawn as %s.", n, countries_noun(n),
                   if (n == 1L) "a point" else "points"),
    if (length(ss$undrawable)) {
      nm <- convert_country(ss$undrawable, to = "country", origin = "iso3c",
                            warn = FALSE)
      nm[is.na(nm)] <- ss$undrawable[is.na(nm)]
      sprintf("Not drawable (no polygon or centroid): %s.",
              paste(nm, collapse = ", "))
    })
  if (length(parts)) paste(parts, collapse = " ")
}

# The layer itself: filled points on the map's fill scale, in the map's
# coordinates. sf maps take them as sf points so coord_sf() projects them.
small_state_layer <- function(pts, fill_mapped, sf_mode, pc = NULL,
                              projection = NULL, recenter = NULL,
                              lat0 = ORTHO_LAT0, alpha = NULL) {
  if (is.null(pts) || !nrow(pts)) return(NULL)
  # An orthographic globe shows one hemisphere; a point on the far side has no
  # image.
  if (identical(projection, "orthographic")) {
    lon0 <- (recenter %||% 0) * pi / 180
    lat0 <- lat0 * pi / 180
    lam <- pts$.wdj_pt_lon * pi / 180
    phi <- pts$.wdj_pt_lat * pi / 180
    cosc <- sin(lat0) * sin(phi) + cos(lat0) * cos(phi) * cos(lam - lon0)
    pts <- pts[cosc > 0, , drop = FALSE]
    if (!nrow(pts)) return(NULL)
  }
  common <- list(shape = 21, size = 1.8, stroke = 0.25, colour = "grey25",
                 inherit.aes = FALSE, show.legend = FALSE)
  alpha_q <- if (!is.null(alpha)) rlang::quo(.data[[!!alpha]])
  if (sf_mode) {
    g <- sf::st_as_sf(pts, coords = c(".wdj_pt_lon", ".wdj_pt_lat"), crs = 4326L)
    map <- ggplot2::aes(fill = !!fill_mapped, alpha = !!alpha_q)
    return(do.call(ggplot2::geom_sf, c(list(data = g, mapping = map), common)))
  }
  if (!is.null(pc)) pts <- apply_polygon_transform(pts, pc, ".wdj_pt_lon", ".wdj_pt_lat")
  map <- ggplot2::aes(x = .data$.wdj_pt_lon, y = .data$.wdj_pt_lat,
                      fill = !!fill_mapped, alpha = !!alpha_q)
  do.call(ggplot2::geom_point, c(list(data = pts, mapping = map), common))
}

# The classification and the small states, as every choropleth verb other
# than world_map() (which interleaves them with the VSUP) runs them.
prepare_fill <- function(data, fill_name, style, n_bins, breaks = NULL,
                         midpoint = NULL, small_states = "auto",
                         small_area_km2 = 1000) {
  ss <- small_state_points(data, fill_name, small_states, small_area_km2)
  extra <- if (!is.null(ss$points)) {
    ss$points[[fill_name]][!ss$points$iso3c %in% data$iso3c]
  }
  binned <- apply_binned_fill(data, fill_name, style, n_bins, breaks = breaks,
                              midpoint = midpoint, extra = extra)
  pts <- ss$points
  if (!is.null(pts) && !is.null(attr(binned, "breaks")) &&
      style %in% CLASSED_STYLES) {
    pts[[".wdj_bin"]] <- bin_values(pts[[fill_name]], attr(binned, "breaks"),
                                    attr(binned, "right") %||% TRUE)
  }
  if (!is.null(pts) && is.factor(binned$data[[fill_name]]) &&
      !is.factor(pts[[fill_name]])) {
    pts[[fill_name]] <- factor(pts[[fill_name]],
                               levels = levels(binned$data[[fill_name]]))
  }
  bin_col <- if (".wdj_bin" %in% names(binned$data)) ".wdj_bin" else fill_name
  list(data = binned$data, fill = binned$fill, binned = binned, ss = ss,
       points = pts, limits = fill_limits(binned$data, pts, fill_name),
       na_present = anyNA(binned$data[[bin_col]]),
       coverage = small_state_coverage(na_coverage(data, fill_name), ss))
}

# The categories a map draws, in the fill's own level order, polygons and
# points together.
fill_limits <- function(data, pts, fill_name) {
  v <- data[[fill_name]]
  if (!is.factor(v) || is.null(pts) || !nrow(pts)) return(NULL)
  used <- unique(c(as.character(v), as.character(pts[[fill_name]])))
  levels(v)[levels(v) %in% used]
}
