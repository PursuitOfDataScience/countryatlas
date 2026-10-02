# Maps: symbols at centroids -------------------------------------------------
#
# Proportional symbols, spikes and great-circle flows: one mark per country or
# pair, placed at a centroid rather than filling a polygon.

# A great circle from Tokyo to Los Angeles crosses the Pacific, so its
# longitudes run ...178, 179, -179, -178... With coord_quickmap() and no
# wrapping, geom_path() joined those two points literally and drew a horizontal
# streak back across the entire map -- every trans-Pacific flow came out as a
# line through Africa. Cut the path where it crosses +/-180 and land each piece
# exactly on the edge, so the arc leaves one side and re-enters the other.
split_antimeridian <- function(df, id) {
  parts <- lapply(split(df, id), function(g) {
    jump <- which(abs(diff(g$lon)) > 180)
    if (!length(jump)) { g$.seg <- 1L; return(g) }
    pieces <- vector("list", length(jump) + 1L)
    start <- 1L
    for (k in seq_along(jump)) {
      i <- jump[k]
      # Unwrap the far point so the crossing latitude interpolates linearly.
      east <- g$lon[i] > 0
      far <- g$lon[i + 1L] + if (east) 360 else -360
      edge <- if (east) 180 else -180
      # A point sitting exactly on the edge makes far == lon[i], so the
      # interpolation is 0/0; the crossing latitude is then just this point's.
      denom <- far - g$lon[i]
      t <- if (denom == 0) 0 else (edge - g$lon[i]) / denom
      lat_c <- g$lat[i] + t * (g$lat[i + 1L] - g$lat[i])
      head_row <- g[i, , drop = FALSE]; head_row$lon <- edge; head_row$lat <- lat_c
      tail_row <- head_row; tail_row$lon <- -edge
      # The carry from the PREVIOUS crossing belongs at the front of this
      # piece. Every carry was computed and stored, but only the last one was
      # ever read (by `last`, below), and the rest were dropped by the
      # attr(x, "carry") <- NULL at the end -- so with two or more crossings
      # the middle segments began at their first raw vertex instead of at the
      # antimeridian edge, leaving a visible break on the re-entry side. The
      # code read as though it handled any number of crossings; it handled one.
      pieces[[k]] <- rbind(
        if (k > 1L) attr(pieces[[k - 1L]], "carry"),
        g[start:i, , drop = FALSE],
        head_row
      )
      pieces[[k]]$.seg <- k
      attr(pieces[[k]], "carry") <- tail_row
      start <- i + 1L
    }
    last <- rbind(attr(pieces[[length(jump)]], "carry"),
                  g[start:nrow(g), , drop = FALSE])
    last$.seg <- length(jump) + 1L
    pieces[[length(jump) + 1L]] <- last
    do.call(rbind, lapply(pieces, function(x) { attr(x, "carry") <- NULL; x }))
  })
  out <- do.call(rbind, parts)
  out$.grp <- paste(rep(names(parts), vapply(parts, nrow, 0L)), out$.seg, sep = ".")
  out
}

# A frame that already carries centroid_lon/centroid_lat -- the output of
# world_geometry("centroids"), or anything joined to it -- collided with the
# join below: dplyr suffixed both sides to .x/.y, and the aes() referring to
# `.data$centroid_lon` then found no such column, so bubble_map() and
# spike_map() failed outright on their own centroid table. The bundled columns
# are the authority here, so drop the incoming ones.
drop_centroid_cols <- function(data) {
  data[, setdiff(names(data), c("centroid_lon", "centroid_lat")), drop = FALSE]
}

# Coverage for the verbs that plot a *point* per country rather than a polygon.
# They join the bundled centroid table, which does not cover every code in the
# codelist -- Hong Kong, Macao, Gibraltar, the British Virgin Islands and Tuvalu
# have data in the bundled snapshot and no centroid. Left-joining then drew a
# row at (NA, NA) and let ggplot2 mutter "Removed 5 rows"; inner-joining dropped
# it without a word. Either way provenance was computed on the frame as it
# arrived, so a population map that never drew Hong Kong still reported
# "215 of 215". Count what is actually drawn, and name what is not.
centroid_coverage <- function(data, value_name, drawn_iso,
                              what = "bundled centroid") {
  # Coverage for the verbs that place one mark per country from a bundled
  # lookup -- centroids for bubble/spike, the tile grid for tile_map. Neither
  # lookup covers every code in the codelist, so counting the input's coded
  # countries as "shown" overstated the map by exactly the ones it could not
  # place: bubble_map() reported "215 of 215" while drawing 210.
  #
  # Reported both ways, as gridded_cartogram() already does for the same
  # limitation ("N countries have no bundled centroid and cannot be placed"):
  # in the coverage numbers, so the caption and map_provenance() are right, and
  # as a warning naming the countries, so it is visible without being asked
  # for. "A correct call to any verb is completely silent" holds for the six
  # pre-CRAN warning sites it was written about; a country the lookup cannot
  # place is information, not noise, and its sibling verb already says so.
  # has_value(): a value the verb cannot draw (an infinity, or a size the
  # caller's verb has already set aside) is not shown, and it is not a missing
  # centroid either, and blaming the lookup for it named the wrong cause.
  present <- has_value(data[[value_name]])
  shown <- data$iso3c %in% drawn_iso & present
  lost <- sort(data$iso3c[present & !data$iso3c %in% drawn_iso])
  if (length(lost)) {
    wdj_warn(c(
      "{.field {value_name}}: {length(lost)} countr{?y/ies} {?is/are} not
       drawn -- no {what}.",
      "*" = "{.val {lost}}",
      "i" = "They are counted as missing in the caption and in
             {.fun map_provenance}."
    ), class = "countryatlas_no_centroid")
  }
  na_coverage(data, value_name, shown = shown)
}

# Set aside the values a size-encoded mark cannot show: negative (an area or a
# height has no negative) and infinite. They become NA on this internal copy,
# so the drawing skips them and the coverage counts them as missing, and the
# countries are named once here so the reason is not left to be guessed.
drop_unusable_sizes <- function(data, col, mark) {
  v <- data[[col]]
  bad <- !is.na(v) & !(is.finite(v) & v >= 0)
  if (!any(bad)) return(data)
  who <- sort(unit_label(data[bad, , drop = FALSE]))
  wdj_warn(c(
    "{length(who)} countr{?y/ies} ha{?s/ve} a negative or infinite
     {.field {col}} and {cli::qty(length(who))}{?gets/get} no {mark}:",
    "*" = "{.val {utils::head(who, 8)}}",
    "i" = "A {mark} encodes a non-negative total; drawing the absolute value
           would misstate it. {cli::qty(length(who))}{?It is/They are} counted
           as missing in {.fn map_provenance}."
  ), class = "countryatlas_unusable_size")
  data[[col]][bad] <- NA
  data
}

#' Proportional-symbol (bubble) map
#'
#' Plots sized circles at country centroids -- the right idiom for *totals*
#' (population, total emissions, total GDP), which a choropleth misrepresents
#' because big values hide in small countries and vice versa.
#'
#' @param data A country-level frame with `iso3c` and the `size` column.
#' @param size The column controlling bubble size (unquoted).
#' @param color Optional column controlling bubble colour (unquoted).
#' @param projection Projection for the base map (sf path). See [world_map()] for the
#'   projections available.
#' @param backend `"polygon"` (default) or `"sf"` for the base map.
#' @param max_size Largest bubble size.
#' @param alpha Bubble transparency.
#' @param footnote The caption: `"auto"` (default) states the coverage and
#'   source, a string is used as given, `FALSE` adds nothing. See [world_map()].
#'
#' @return A `ggplot` object.
#' @export
#' @examples
#' \donttest{
#' snap <- countryatlas::world_snapshot$countries
#' bubble_map(snap, population)
#' }
bubble_map <- function(data, size, color = NULL, projection = "equal_earth",
                       backend = c("polygon", "sf"), max_size = 18, alpha = 0.7,
                       footnote = "auto") {
  backend <- rlang::arg_match(backend)
  size_q <- rlang::enquo(size)
  color_q <- rlang::enquo(color)
  if (!"iso3c" %in% names(data)) {
    wdj_abort("{.arg data} must contain an {.field iso3c} column.")
  }
  size_name <- quo_arg_name(size_q, "size")
  color_name <- if (!rlang::quo_is_null(color_q)) {
    quo_arg_name(color_q, "color")
  }
  check_cols(data, c(size_name, color_name))
  # Both aesthetics go through quo_col_mapping() below rather than splicing
  # `size_q`/`color_q` raw, so `size = "population"` maps the column and not
  # the constant string.
  size_mapped <- quo_col_mapping(size_name)
  color_mapped <- if (is.null(color_name)) NULL else quo_col_mapping(color_name)
  # `size` feeds scale_size_area(). A non-numeric column reached ggplot2 as its
  # bare "Discrete value supplied to a continuous scale" -- and only at *build*
  # time, so bubble_map() itself returned happily and the failure arrived when
  # the plot was printed, naming neither the argument nor the column.
  # country_network() gets this right through check_numeric_col(); so should
  # the verbs shaped like it.
  check_numeric_col(data, quo_arg_name(size_q, "size"))
  check_number(max_size, "max_size", lo = 0)
  check_number(alpha, "alpha", lo = 0, hi = 1)
  # One row per country, so a country contributes a single bubble.
  #
  # sf_drop() BEFORE as_tibble(), the order rate_check(), world_table(),
  # gridded_cartogram() and align_weights() all use. as_tibble() strips the
  # `sf` class but leaves the live sfc column in place, so the
  # st_drop_geometry() further down saw a plain tibble and returned it
  # unchanged -- and the join then carried the caller's geometry alongside the
  # basemap's, producing `geometry.x` / `geometry.y` and renaming the active
  # column out from under coord_sf(). The polygon path is unaffected: it draws
  # from country_meta centroids, and long/lat/group are ordinary columns that
  # sf_drop() does not touch.
  data <- distinct_countries(tibble::as_tibble(sf_drop(data)))
  # A bubble's area is the value, and scale_size_area() draws the *absolute*
  # value: France at -1.4e9 came out as big a bubble as China, and an infinite
  # value as an infinite one. Neither is a total a bubble can show, so they
  # are set aside, said here, and counted as missing below.
  data <- drop_unusable_sizes(data, size_name, "bubble")

  if (backend == "sf") {
    need_pkg("sf", "for bubble_map(backend = \"sf\")")
    # Keep the base map and the bubbles in the SAME projected CRS, then let
    # coord_sf() draw both. (The old code put metre-scale sf centroids on a
    # degree-scale polygon base map, so the bubbles flew off the map.)
    countries <- world_geometry("countries", geometry = "sf", projection = projection)
    pts_sf <- sf_centroids(countries)[, "iso3c"]
    # One bubble per country, as on the polygon path: Natural Earth gives a
    # divided country two rows sharing one iso3c.
    pts_sf <- pts_sf[!duplicated(pts_sf$iso3c), ]
    pts_sf <- dplyr::left_join(pts_sf, sf::st_drop_geometry(data), by = "iso3c",
                               na_matches = "never", relationship = "one-to-one")
    # Basemap countries the caller has no value for carry an NA size, and
    # geom_sf() drops them at draw time with a bare "Removed 7 rows". They are
    # already the grey base map underneath; the coverage numbers below account
    # for them, so drop them here rather than emit a count with no names.
    pts_sf <- pts_sf[!is.na(pts_sf[[size_name]]), , drop = FALSE]
    aes_pt <- if (!rlang::quo_is_null(color_q)) {
      ggplot2::aes(size = !!size_mapped, color = !!color_mapped)
    } else {
      ggplot2::aes(size = !!size_mapped)
    }
    countries <- clip_for_projection(countries, projection)
    p_sf <- ggplot2::ggplot() +
      ggplot2::geom_sf(data = countries, fill = "grey92", color = "grey80",
                       linewidth = 0.1) +
      ggplot2::geom_sf(data = pts_sf, mapping = aes_pt, alpha = alpha) +
      ggplot2::scale_size_area(max_size = max_size,
                             name = legend_title(data, size_name)) +
      wdj_coord_sf(projection) +
      theme_world_map()
    return(wdj_provenance(
      p_sf, data, quo_arg_name(size_q, "size"), "sf", projection,
      style = "proportional symbol",
      extra = list(coverage = centroid_coverage(
        data, quo_arg_name(size_q, "size"), countries$iso3c)),
      footnote = footnote))
  }

  # Polygon backend: base map and centroids go through the same coordinate
  # path as world_map(), so the bubbles land on the countries they belong to
  # in whichever projection the map is drawn.
  pc <- wdj_polygon_coord(projection)
  data <- drop_centroid_cols(data)
  cent <- world_geometry("centroids", geometry = "polygon")
  pts <- dplyr::left_join(data, cent[, c("iso3c", "centroid_lon", "centroid_lat")],
                          by = "iso3c", na_matches = "never",
                          relationship = "many-to-one")
  aes_pt <- if (!rlang::quo_is_null(color_q)) {
    ggplot2::aes(.data$centroid_lon, .data$centroid_lat,
                 size = !!size_mapped, color = !!color_mapped)
  } else {
    ggplot2::aes(.data$centroid_lon, .data$centroid_lat, size = !!size_mapped)
  }
  cov <- centroid_coverage(data, size_name, pts$iso3c[
    !is.na(pts$centroid_lon) & !is.na(pts$centroid_lat)])
  # Drop them here rather than handing ggplot2 a point at (NA, NA): the warning
  # above says which countries and why, which "Removed 5 rows" does not. A
  # missing size goes too, as it does on the sf path: geom_point() otherwise
  # announced "Removed 1 row containing missing values" at print time, a
  # count with no names for a country the coverage already reports.
  pts <- pts[!is.na(pts$centroid_lon) & !is.na(pts$centroid_lat) &
               !is.na(pts[[size_name]]), , drop = FALSE]
  pts <- apply_polygon_transform(pts, pc, "centroid_lon", "centroid_lat")
  p <- ggplot2::ggplot() +
    polygon_basemap(pc) +
    ggplot2::geom_point(data = pts, mapping = aes_pt, alpha = alpha) +
    ggplot2::scale_size_area(max_size = max_size,
                             name = legend_title(data, size_name)) +
    pc$coord +
    theme_world_map()
  wdj_provenance(p, data, quo_arg_name(size_q, "size"), "polygon",
                 pc$label, style = "proportional symbol",
                 extra = list(coverage = cov), footnote = footnote)
}

# The grey basemap the symbol verbs draw on, in the map's coordinate space.
polygon_basemap <- function(pc, fill = "grey92", color = "grey80") {
  base <- apply_polygon_transform(
    world_geometry("countries", geometry = "polygon"), pc)
  ggplot2::geom_polygon(
    data = base, ggplot2::aes(.data$long, .data$lat, group = .data$group),
    fill = fill, color = color, linewidth = 0.1)
}

#' Spike map (heights at country centroids)
#'
#' The classic "population spikes" display: a triangular spike at each country
#' centroid whose height encodes the value. Like [bubble_map()] it is the
#' honest idiom for *totals*, with a different visual trade-off: spikes
#' overplot less in dense regions (Europe, the Caribbean) because they only
#' grow upward. Uses the polygon backend, so it needs no extra package.
#'
#' @param data A country-level frame with `iso3c` and the `height` column.
#' @param height The column controlling spike height (unquoted).
#' @param max_height Height of the tallest spike, in degrees of latitude
#'   (default `20`). On a projected map that is a ground distance (one degree
#'   is about 111 km) laid out in the projection's own units, so every spike
#'   uses the same scale wherever it stands; with `projection = "none"` or
#'   `"orthographic"` it is in the map's degrees.
#' @param width Base width of each spike, in degrees of longitude at the
#'   equator (default `1.6`), measured the same way.
#' @param color Spike colour (default a warm red).
#' @param alpha Spike fill transparency.
#' @param projection Map projection, as in [world_map()] (default
#'   `"equal_earth"`).
#' @param footnote The caption: `"auto"` (default) states the coverage and
#'   source, a string is used as given, `FALSE` adds nothing. See [world_map()].
#'
#' @return A `ggplot` object.
#' @export
#' @examples
#' \donttest{
#' spike_map(countryatlas::world_snapshot$countries, population)
#' }
spike_map <- function(data, height, max_height = 20, width = 1.6,
                      color = "#B2182B", alpha = 0.65,
                      projection = "equal_earth", footnote = "auto") {
  height_q <- rlang::enquo(height)
  h_name <- quo_arg_name(height_q, "height")
  if (!"iso3c" %in% names(data)) {
    wdj_abort("{.arg data} must contain an {.field iso3c} column.")
  }
  check_cols(data, h_name)
  # Without this, a non-numeric height reached the non-negative filter and the
  # abort blamed the *join* -- "No rows with a non-negative <col> joined to a
  # centroid" -- when the column simply was not a number.
  check_numeric_col(data, h_name)
  check_number(max_height, "max_height", lo = 0)
  check_number(width, "width", lo = 0)
  check_number(alpha, "alpha", lo = 0, hi = 1)
  pc <- wdj_polygon_coord(projection)
  data <- drop_centroid_cols(distinct_countries(tibble::as_tibble(data)))
  # Negative and infinite heights were filtered out below in silence, and the
  # coverage warning then listed those countries as having "no bundled
  # centroid": the wrong reason, for countries whose centroid is right there.
  # Set them aside with their own message first, as bubble_map() does.
  data <- drop_unusable_sizes(data, h_name, "spike")
  cent <- world_geometry("centroids", geometry = "polygon")
  pts <- dplyr::inner_join(data, cent[, c("iso3c", "centroid_lon", "centroid_lat")],
                           by = "iso3c", na_matches = "never",
                           relationship = "many-to-one")
  pts <- pts[!is.na(pts[[h_name]]), ]
  if (!nrow(pts)) {
    wdj_abort("No rows with a non-negative {.val {h_name}} joined to a centroid.")
  }
  .mx <- max(pts[[h_name]]); h <- if (.mx > 0) pts[[h_name]] / .mx * max_height else rep(0, nrow(pts))

  # One triangle (3 vertices) per country: (x - w/2, y), (x, y + h), (x + w/2, y).
  # Built in the projection's own metres, so a spike's height does not depend
  # on where it stands: drawn in degrees and then projected, the same value
  # came out shorter towards the poles. "none" and orthographic draw in degrees.
  xy <- polygon_metres(pts$centroid_lon, pts$centroid_lat, pc)
  unit <- if (is.null(xy)) 1 else METRES_PER_DEGREE
  if (is.null(xy)) xy <- list(x = pts$centroid_lon, y = pts$centroid_lat)
  spikes <- tibble::tibble(
    iso3c = rep(pts$iso3c, each = 3L),
    long = as.vector(rbind(xy$x - width / 2 * unit, xy$x,
                           xy$x + width / 2 * unit)),
    lat = as.vector(rbind(xy$y, xy$y + h * unit, xy$y))
  )
  spikes <- spikes[stats::ave(is.finite(spikes$long) & is.finite(spikes$lat),
                              spikes$iso3c, FUN = all), , drop = FALSE]
  spike_layer <- if (!is.null(pc$crs)) {
    # coord_sf() reads ordinary layers as longitude/latitude, so a layer built
    # in metres goes in as sf, in the map's own CRS.
    rings <- split(spikes[, c("long", "lat")], spikes$iso3c)
    geom <- sf::st_sfc(lapply(rings, function(r) {
      m <- as.matrix(r)
      sf::st_polygon(list(rbind(m, m[1, ])))
    }), crs = pc$crs)
    ggplot2::geom_sf(data = sf::st_sf(iso3c = names(rings), geometry = geom),
                     fill = color, color = color, alpha = alpha,
                     linewidth = 0.3, inherit.aes = FALSE)
  } else {
    ggplot2::geom_polygon(
      data = spikes,
      ggplot2::aes(.data$long, .data$lat, group = .data$iso3c),
      fill = color, color = color, alpha = alpha, linewidth = 0.3
    )
  }
  p <- ggplot2::ggplot() +
    polygon_basemap(pc) +
    spike_layer +
    pc$coord +
    theme_world_map()
  wdj_provenance(p, data, h_name, "polygon", pc$label,
                 style = "spike",
                 extra = list(coverage = centroid_coverage(
                   data, h_name, pts$iso3c)), footnote = footnote)
}

#' Great-circle origin-destination flow map
#'
#' Draws great-circle arcs between country pairs from an origin-destination
#' table (trade, migration, flights, remittances), resolving both endpoints to
#' centroids automatically.
#'
#' @param data An OD table.
#' @param from,to The origin and destination country columns (unquoted; names
#'   or `iso3c`).
#' @param weight Optional column controlling arc width/alpha (unquoted).
#' @param origin How to read `from`/`to` (countrycode origin scheme).
#' @param arc_points Points per arc (default `50`): the smoothness of each
#'   great circle.
#' @param n `r lifecycle::badge("deprecated")` Use `arc_points`.
#' @param projection Map projection, as in [world_map()] (default
#'   `"equal_earth"`). The arcs are great circles in any projection.
#' @param footnote The caption: `"auto"` (default) says how many flows were
#'   drawn, a string is used as given, `FALSE` adds nothing.
#'
#' @section Backend:
#' The polygon backend draws it, in `projection` (Equal Earth by default), so it
#' needs no `sf`.
#'
#' @return A `ggplot` object.
#' @export
#' @examples
#' \donttest{
#' od <- data.frame(from = c("China", "Germany"),
#'                  to = c("United States", "France"),
#'                  value = c(500, 200))
#' flow_map(od, from, to, value)
#' }
flow_map <- function(data, from, to, weight = NULL, origin = "country.name",
                     arc_points = 50, projection = "equal_earth",
                     footnote = "auto", n = deprecated()) {
  # Errors name the argument the caller wrote, the deprecated one included.
  n_arg <- "arc_points"
  if (lifecycle::is_present(n)) {
    lifecycle::deprecate_warn("4.0.0", "flow_map(n)", "flow_map(arc_points)")
    arc_points <- n
    n_arg <- "n"
  }
  n <- arc_points
  from_name <- quo_arg_name(rlang::enquo(from), "from")
  to_name <- quo_arg_name(rlang::enquo(to), "to")
  weight_q <- rlang::enquo(weight)
  check_cols(data, c(
    from_name, to_name,
    if (!rlang::quo_is_null(weight_q)) quo_arg_name(weight_q, "weight")
  ))
  # `weight` drives linewidth and alpha, so the same "Discrete value supplied
  # to a continuous scale" applies -- at build time, not here, unless checked.
  if (!rlang::quo_is_null(weight_q)) {
    check_numeric_col(data, quo_arg_name(weight_q, "weight"))
  }
  # An arc needs at least two points; below that seq() errored on length.out.
  check_number(n, n_arg, lo = 2, hi = .Machine$integer.max)
  pc <- wdj_polygon_coord(projection)

  cent <- world_geometry("centroids", geometry = "polygon")
  cent <- cent[, c("iso3c", "centroid_lon", "centroid_lat")]

  data <- tibble::as_tibble(data)
  # The arc endpoints are joined in as `x0`/`y0`/`x1`/`y1`, and a caller who
  # geocoded their own endpoints -- which is exactly the shape of frame this
  # verb is for -- already has columns of those names. dplyr suffixed both
  # sides to `.x`/`.y`, and the completeness check below then failed with
  # vctrs' "Can't subset columns that don't exist". Drop the caller's copies:
  # the joined centroids are the ones drawn. A column this verb actually reads
  # cannot be dropped, so that clash is refused by name instead.
  arc_cols <- c("x0", "y0", "x1", "y1")
  read_cols <- c(from_name, to_name,
                 if (!rlang::quo_is_null(weight_q)) {
                   quo_arg_name(weight_q, "weight")
                 })
  clash <- intersect(read_cols, arc_cols)
  if (length(clash)) {
    wdj_abort(c(
      "A column {.fn flow_map} reads cannot be named {.val {clash}}: the arc
       endpoints are joined in under {.val {arc_cols}}.",
      "i" = "Rename it before drawing."
    ))
  }
  data <- data[, setdiff(names(data), arc_cols), drop = FALSE]
  data$.from_iso <- wdj_to_iso3c(data[[from_name]], origin = origin)
  data$.to_iso <- wdj_to_iso3c(data[[to_name]], origin = origin)
  data$.id <- seq_len(nrow(data))

  d <- dplyr::left_join(data, stats::setNames(cent, c(".from_iso", "x0", "y0")),
                        by = ".from_iso", na_matches = "never",
                        relationship = "many-to-one")
  d <- dplyr::left_join(d, stats::setNames(cent, c(".to_iso", "x1", "y1")),
                        by = ".to_iso", na_matches = "never",
                        relationship = "many-to-one")
  # A pair with an unresolvable endpoint has no centroid to draw an arc between,
  # so it drops out here. Say so: an unannounced drop renders a world map with
  # fewer arcs than rows -- or, when nothing resolves, no arcs at all -- and the
  # commonest cause is feeding iso3c codes while `origin` still says
  # "country.name". Same phrasing as standardize_country()'s warning.
  keep <- stats::complete.cases(d[, c("x0", "y0", "x1", "y1")])
  if (any(!keep)) {
    miss <- unique(c(as.character(d[[from_name]])[is.na(d$x0)],
                     as.character(d[[to_name]])[is.na(d$x1)]))
    miss <- miss[!is.na(miss)]
    wdj_warn(c(
      "{sum(!keep)} flow{?s} dropped: an endpoint has no centroid.",
      "*" = "{.val {miss}}",
      "i" = "Unrecognised names give no arc. Check {.arg origin} -- iso3c codes
             need {.code origin = \"iso3c\"} -- or use {.fn check_country_match}."
    ))
  }
  # A weight the scales cannot place: NA drew as ggplot2's "Removed 50 rows
  # containing missing values" at print time, and an infinite one did not draw
  # at all: grid refused the linewidth ("'lwd' must be non-negative and
  # finite") when the plot was printed, long after this returned. Drop those
  # arcs here and say so, the way flow_matrix() does for the same rows.
  if (!rlang::quo_is_null(weight_q)) {
    w_col <- quo_arg_name(weight_q, "weight")
    bad_w <- keep & !is.finite(d[[w_col]])
    if (any(bad_w)) {
      wdj_warn(c(
        "{sum(bad_w)} flow{?s} dropped: the weight is missing or infinite.",
        "i" = "Both endpoints resolved; it is {.field {w_col}} that is
               unusable."
      ))
      keep <- keep & !bad_w
    }
  }
  d <- d[keep, ]

  arcs <- do.call(rbind, lapply(seq_len(nrow(d)), function(i) {
    gc <- great_circle(d$x0[i], d$y0[i], d$x1[i], d$y1[i], n = n)
    gc$.id <- d$.id[i]
    if (!rlang::quo_is_null(weight_q)) {
      gc$weight <- d[[quo_arg_name(weight_q, "weight")]][i]
    }
    gc
  }))

  base <- ggplot2::ggplot() + polygon_basemap(pc)
  if (is.null(arcs) || !nrow(arcs)) {
    return(wdj_provenance(base + pc$coord + theme_world_map(),
                          data, NULL, "polygon", pc$label,
                          style = "great-circle flow (no arcs)",
                          footnote = footnote,
                          notes = flow_note(footnote, 0L, nrow(data))))
  }
  arcs <- split_antimeridian(arcs, arcs$.id)
  arcs <- apply_polygon_transform(arcs, pc, "lon", "lat")
  arc_aes <- if (!rlang::quo_is_null(weight_q)) {
    ggplot2::aes(.data$lon, .data$lat, group = .data$.grp,
                 linewidth = .data$weight, alpha = .data$weight)
  } else {
    ggplot2::aes(.data$lon, .data$lat, group = .data$.grp)
  }
  # Both scales carry the caller's column name, not the internal one. The arc
  # frame's column is literally called `weight`, so ggplot2 titled the legend
  # "weight" whatever the user had mapped; naming both identically also merges
  # what were two legends of the same variable into one.
  w_name <- if (rlang::quo_is_null(weight_q)) NULL else quo_arg_name(weight_q, "weight")
  p <- base +
    ggplot2::geom_path(data = arcs, mapping = arc_aes, color = "#2166AC") +
    # The lightest arc, at ggplot2's default alpha of 0.1 and 0.2 wide,
    # vanished into the grey basemap.
    ggplot2::scale_linewidth(name = w_name, range = c(0.35, 2)) +
    ggplot2::scale_alpha(name = w_name, range = c(0.35, 1)) +
    pc$coord +
    theme_world_map()
  wdj_provenance(p, data,
                 if (rlang::quo_is_null(weight_q)) NULL else quo_arg_name(weight_q, "weight"),
                 "polygon", pc$label, style = "great-circle flow",
                 footnote = footnote,
                 notes = flow_note(footnote, length(unique(arcs$.id)), nrow(data)))
}

# flow_map()'s automatic caption: flows, not countries, are what it counts.
flow_note <- function(footnote, drawn, total) {
  if (!identical(footnote, "auto") && !isTRUE(footnote)) return(NULL)
  if (drawn == total) {
    sprintf("%d %s drawn.", total, if (total == 1L) "flow" else "flows")
  } else {
    sprintf("%d of %d flows drawn.", drawn, total)
  }
}

# Great-circle interpolation (spherical slerp) between two lon/lat points.
great_circle <- function(lon1, lat1, lon2, lat2, n = 50) {
  d2r <- pi / 180
  phi1 <- lat1 * d2r; lam1 <- lon1 * d2r
  phi2 <- lat2 * d2r; lam2 <- lon2 * d2r
  # angular distance
  dlt <- acos(pmin(1, pmax(-1,
    sin(phi1) * sin(phi2) + cos(phi1) * cos(phi2) * cos(lam2 - lam1))))
  if (dlt == 0) {
    return(tibble::tibble(lon = rep(lon1, n), lat = rep(lat1, n)))
  }
  at <- function(f) {
    A <- sin((1 - f) * dlt) / sin(dlt)
    B <- sin(f * dlt) / sin(dlt)
    x <- A * cos(phi1) * cos(lam1) + B * cos(phi2) * cos(lam2)
    y <- A * cos(phi1) * sin(lam1) + B * cos(phi2) * sin(lam2)
    z <- A * sin(phi1) + B * sin(phi2)
    list(lon = atan2(y, x) / d2r, lat = atan2(z, sqrt(x^2 + y^2)) / d2r)
  }
  f <- seq(0, 1, length.out = n)
  pt <- at(f)
  # A near-antipodal arc passes within half a degree of a pole, and longitude
  # turns almost arbitrarily fast there: Belgium to Tonga stepped 131 degrees of
  # longitude between two consecutive points at the default n = 50, and
  # Greenland to Japan 121. split_antimeridian() below only cuts a step wider
  # than 180, so those were drawn as a straight streak across the top of the map
  # -- the same failure it was written to fix for the trans-Pacific case, caused
  # by the pole instead of the antimeridian. The path is right; 50 points is
  # simply too coarse where it turns fastest, and the step shrinks in proportion
  # to n (131 -> 75 -> 21 -> 4 at n = 50, 200, 1000, 5000). So refine only the
  # offending segments: an ordinary arc never trips the threshold and keeps its
  # n points exactly.
  #
  # pmin(d, 360 - d) measures the step the short way round, so a genuine
  # antimeridian crossing (179 to -179) reads as 2 degrees rather than 358 and
  # is left for split_antimeridian() to cut, which is its job.
  # No "stop when it stops improving" shortcut here: a pass halves only the
  # offending segments, so it can cut the worst step by well under 10% and
  # still be converging -- a guard on that basis stopped Belgium-Tonga at 119
  # degrees instead of 15. The iteration and point caps are the bound. Exactly
  # antipodal endpoints have no unique shortest path (sin(dlt) is 1e-16 and the
  # slerp is meaningless), so they exhaust the eight passes without converging;
  # that costs a few hundred points on input no pair of real centroids
  # produces, which is cheaper than risking the cases that do converge.
  for (i in seq_len(8L)) {
    d <- abs(diff(pt$lon))
    d <- pmin(d, 360 - d)
    # Compare each longitude step with the angular distance the segment
    # actually covers, rather than with a flat threshold. A flat one cannot
    # tell the two apart: 45 degrees of longitude along the equator at n = 3 is
    # honest coarseness the caller asked for, and it covers 45 degrees of arc;
    # 131 degrees of longitude beside a pole covers less than half a degree of
    # arc, and that is the streak. Haversine, so a densified and therefore
    # unevenly spaced `f` is measured correctly.
    la1 <- pt$lat[-length(pt$lat)] * d2r; la2 <- pt$lat[-1] * d2r
    ang <- 2 * asin(pmin(1, sqrt(sin((la2 - la1) / 2)^2 +
             cos(la1) * cos(la2) * sin(d * d2r / 2)^2))) / d2r
    gap <- which(d > 3 * ang & d > 5)
    if (!length(gap) || length(f) > 4000L) break
    f <- sort(unique(c(f, (f[gap] + f[gap + 1L]) / 2)))
    pt <- at(f)
  }
  tibble::tibble(lon = pt$lon, lat = pt$lat)
}
