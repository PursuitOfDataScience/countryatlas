# Visualization -----------------------------------------------------------------

#' A clean theme for world maps
#'
#' Strips axes, panel grid and background so the map is the focus. Applied by
#' every plotting function in the package except [bivariate_map()], which uses
#' `biscale::bi_theme()` so the map matches its own legend, and exported here for
#' reuse on plots you build yourself.
#'
#' @param base_size Base font size.
#' @param base_family Base font family.
#' @return A `ggplot2` theme object.
#' @export
#' @examples
#' library(ggplot2)
#' ggplot() + theme_world_map()
theme_world_map <- function(base_size = 12, base_family = "") {
  ggplot2::theme_minimal(base_size = base_size, base_family = base_family) +
    ggplot2::theme(
      axis.title = ggplot2::element_blank(),
      axis.text = ggplot2::element_blank(),
      axis.ticks = ggplot2::element_blank(),
      panel.grid = ggplot2::element_blank(),
      panel.background = ggplot2::element_blank(),
      legend.position = "right",
      plot.title = ggplot2::element_text(face = "bold")
    )
}

# Is this an sf object?
is_sf <- function(x) inherits(x, "sf")

# Compute classInt-style breaks; falls back to base quantiles if classInt is
# unavailable.
compute_breaks <- function(x, style, n_bins) {
  # classInt rejects n < 2 with a bare "n less than 2", and an NA got as far as
  # "missing value where TRUE/FALSE needed". The upper bound matters because
  # callers coerce counts with as.integer(), which returns NA past 2^31-1.
  check_number(n_bins, "n_bins", lo = 2, hi = .Machine$integer.max)
  # Truncate to a whole number of bins so the two backends below agree: classInt
  # truncates internally, but the base-quantile fallback would pass a fractional
  # count to seq(length.out = ), giving one break more. The bin count must not
  # depend on whether classInt happens to be installed.
  n_bins <- as.integer(n_bins)
  x <- x[is.finite(x)]
  if (length(unique(x)) < 2L) { if (!length(x)) return(c(0, 1)); v <- unique(x)[1]; return(c(v - 0.5, v + 0.5)) }
  if (has_pkg("classInt")) {
    cls <- switch(style, quantile = "quantile", jenks = "jenks", "quantile")
    # classInt is chatty when n equals the number of distinct values, or on
    # ties; the binning is still valid, so don't leak the warning to callers.
    br <- suppressWarnings(
      classInt::classIntervals(x, n = n_bins, style = cls)
    )$brks
    return(unique(br))
  }
  if (style == "jenks") {
    wdj_warn("Package {.pkg classInt} not installed; using quantile breaks.")
  }
  unique(stats::quantile(x, probs = seq(0, 1, length.out = n_bins + 1),
                         na.rm = TRUE))
}

#' One-line choropleth, several honest styles
#'
#' Encapsulates the choropleth boilerplate and goes beyond a single style.
#' Auto-detects the polygon vs `sf` backend, applies [theme_world_map()], and --
#' for `sf` -- a real projection via [ggplot2::coord_sf()]. Binned / quantile /
#' jenks styles are offered because a continuous fill on a skewed indicator
#' hides almost all the variation; binning is the honest default for
#' choropleths.
#'
#' @param data A map-ready frame from [world_data()] / [join_world()] (polygon
#'   tibble or `sf`).
#' @param fill The fill column (unquoted).
#' @param style `"continuous"` (default), `"binned"`, `"quantile"`, `"jenks"`
#'   or `"categorical"`.
#' @param projection For the `sf` backend, any of the projections in
#'   [world_geometry()]: `"equal_earth"` (default), `"robinson"`, `"mollweide"`,
#'   `"natural_earth"`, `"plate_carree"`, `"mercator"`, `"winkel_tripel"`,
#'   `"eckert4"`, `"gall_peters"`, `"orthographic"`, `"azimuthal_equal_area"`,
#'   `"north_polar"` or `"south_polar"`.
#' @param palette Optional palette name passed to the relevant `ggplot2` scale.
#' @param n_bins Number of bins for binned/quantile/jenks styles.
#' @param borders Draw country borders (default `TRUE`).
#' @param title,legend Optional plot title and legend title.
#' @param na_label Legend key label for missing data, used by the styles with
#'   a discrete legend (`"quantile"`, `"jenks"`, `"categorical"`); the
#'   continuous and binned colourbars have no `NA` key to name.
#' @param recenter Optional central meridian for the `sf` backend.
#'
#' @return A `ggplot` object.
#' @export
#' @examples
#' \donttest{
#' snap <- countryatlas::world_snapshot$countries
#' if (requireNamespace("maps", quietly = TRUE)) {
#'   mapdf <- attach_geometry(snap, geometry = "polygon")
#'   world_map(mapdf, gdp_per_capita, style = "quantile")
#' }
#' }
world_map <- function(data, fill,
                      style = c("continuous", "binned", "quantile", "jenks",
                                "categorical"),
                      projection = "equal_earth",
                      palette = NULL, n_bins = 5, borders = TRUE,
                      title = NULL, legend = NULL, na_label = "No data",
                      recenter = NULL) {
  check_bool(borders, "borders")
  check_label_args(palette, title, legend, na_label)
  style <- match.arg(style)
  fill_q <- rlang::enquo(fill)
  fill_name <- quo_arg_name(fill_q, "fill")

  check_cols(data, fill_name)
  check_map_geometry(data)

  sf_mode <- is_sf(data)
  check_categorical_fill(style, data[[fill_name]], fill_name)

  binned <- apply_binned_fill(data, fill_q, fill_name, style, n_bins)
  data <- binned$data
  fill_mapped <- binned$fill

  if (sf_mode) {
    p <- ggplot2::ggplot(data) +
      ggplot2::geom_sf(ggplot2::aes(fill = !!fill_mapped),
                       color = if (borders) "grey30" else NA,
                       linewidth = 0.1) +
      wdj_coord_sf(projection, recenter)
  } else {
    p <- ggplot2::ggplot(
      data,
      ggplot2::aes(x = .data$long, y = .data$lat, group = .data$group,
                   fill = !!fill_mapped)
    ) +
      ggplot2::geom_polygon(
        color = if (borders) "grey30" else NA, linewidth = 0.1
      ) +
      ggplot2::coord_quickmap()
  }

  p <- p + add_fill_scale(style, palette, n_bins, na_label, legend %||% fill_name) +
    theme_world_map()
  if (!is.null(title)) p <- p + ggplot2::labs(title = title)
  p
}

# Pre-compute quantile/jenks binning: cut the fill column into an ordered
# factor and return the aesthetic to map, or the original quosure untouched for
# the styles that do not bin.
#
# Breaks are computed on ONE value per country. The polygon backend repeats a
# country's value once per boundary point, so breaking on the raw column would
# weight each country by its geometric complexity and a "quantile" map would no
# longer hold ~equal countries per colour. The sf backend is *nearly* one row
# per country but not exactly: divided countries occupy two rows sharing one
# iso3c (Cyprus at 110m; Cyprus and India at 50m), which was enough to shift the
# breaks and move a couple of countries into the wrong bin. So de-duplicate on
# the key whenever there is one, on either backend.
apply_binned_fill <- function(data, fill_q, fill_name, style, n_bins) {
  vals <- data[[fill_name]]
  if (!style %in% c("quantile", "jenks") || !is.numeric(vals)) {
    return(list(data = data, fill = fill_q))
  }
  break_vals <- vals
  key <- intersect(c("iso3c", "group"), names(data))
  if (length(key)) {
    break_vals <- dplyr::distinct(tibble::as_tibble(data),
                                  .data[[key[1]]], .keep_all = TRUE)[[fill_name]]
  }
  br <- compute_breaks(break_vals, style, n_bins)
  data[[".wdj_bin"]] <- cut(vals, breaks = br, include.lowest = TRUE,
                            dig.lab = 4)
  list(data = data, fill = rlang::quo(.data[[".wdj_bin"]]))
}

# Choose an appropriate fill scale for the chosen style.
add_fill_scale <- function(style, palette, n_bins, na_label, legend) {
  # Reached by every style; "binned" hands n_bins to ggplot2 directly rather
  # than through compute_breaks().
  check_number(n_bins, "n_bins", lo = 2, hi = .Machine$integer.max)
  n_bins <- as.integer(n_bins)
  na_val <- "grey85"
  switch(
    style,
    continuous = ggplot2::scale_fill_viridis_c(
      name = legend, na.value = na_val,
      option = palette %||% "viridis", labels = scales_format()
    ),
    binned = ggplot2::scale_fill_viridis_b(
      name = legend, na.value = na_val, n.breaks = n_bins,
      option = palette %||% "viridis", labels = scales_format()
    ),
    quantile = ,
    jenks = ggplot2::scale_fill_viridis_d(
      name = legend, na.value = na_val, option = palette %||% "viridis",
      labels = discrete_na_labels(na_label)
    ),
    categorical = ggplot2::scale_fill_viridis_d(
      name = legend, na.value = na_val, option = palette %||% "turbo",
      labels = discrete_na_labels(na_label)
    )
  )
}

# `style = "categorical"` maps onto a discrete scale, which ggplot2 refuses a
# numeric column outright -- but only at build time ("Continuous value supplied
# to a discrete scale"), long after the call and without naming the column or
# the style that caused it.
check_categorical_fill <- function(style, vals, fill_name,
                                   call = rlang::caller_env()) {
  # The numeric styles need a numeric column, and said so only obliquely and
  # late: "continuous" and "binned" reached ggplot2 and failed at *print* time
  # ("Discrete value supplied to a continuous scale", "Binned scales only
  # support continuous data"), neither naming the column. Worse, "quantile" and
  # "jenks" did not fail at all -- compute_breaks() returns early on a
  # non-numeric column, so the fill fell through to the discrete scale and drew
  # a perfectly plausible map whose legend claimed quantile bins it had never
  # computed.
  if (style %in% c("continuous", "binned", "quantile", "jenks") &&
      !is.numeric(vals)) {
    wdj_abort(c(
      '{.code style = "{style}"} needs a numeric {.arg fill} column.',
      "x" = "{.val {fill_name}} is {.cls {class(vals)}}.",
      "i" = 'Use {.code style = "categorical"} for a discrete column, or convert it with {.code as.numeric()}.'
    ), call = call)
  }
  if (!identical(style, "categorical") || !is.numeric(vals)) return(invisible(TRUE))
  wdj_abort(c(
    '{.code style = "categorical"} needs a discrete {.arg fill} column.',
    "x" = "{.val {fill_name}} is {.cls {class(vals)}}.",
    "i" = 'Use {.code style = "quantile"}, {.code "jenks"} or {.code "binned"} for a numeric column, or convert it to a factor first.'
  ), call = call)
}

# Label the discrete scales' NA key with `na_label` instead of a bare "NA".
# (Continuous / binned colourbars have no NA key to name, so they are left
# to the default formatter.)
discrete_na_labels <- function(na_label) {
  # Only the first element can label the single NA key; a NULL / empty / NA
  # label means "leave the default formatter alone". (Guarding with anyNA()
  # rather than is.na() so a length > 1 na_label can't error the condition.)
  if (is.null(na_label) || !length(na_label) || anyNA(na_label)) {
    return(ggplot2::waiver())
  }
  na_label <- as.character(na_label)[[1]]
  function(x) {
    x <- as.character(x)
    x[is.na(x)] <- as.character(na_label)
    x
  }
}

# Use scales::label_number if available, else identity labels. SI-style
# cut_short_scale() turns 4e+06 into "4M" so binned legends stay readable.
scales_format <- function() {
  if (has_pkg("scales")) {
    scales::label_number(scale_cut = scales::cut_short_scale())
  } else {
    ggplot2::waiver()
  }
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
#'
#' @return A `ggplot` object.
#' @export
#' @examples
#' \donttest{
#' snap <- countryatlas::world_snapshot$countries
#' if (requireNamespace("maps", quietly = TRUE)) {
#'   bubble_map(snap, population)
#' }
#' }
bubble_map <- function(data, size, color = NULL, projection = "equal_earth",
                       backend = c("polygon", "sf"), max_size = 18, alpha = 0.7) {
  backend <- match.arg(backend)
  size_q <- rlang::enquo(size)
  color_q <- rlang::enquo(color)
  if (!"iso3c" %in% names(data)) {
    wdj_abort("{.arg data} must contain an {.field iso3c} column.")
  }
  check_cols(data, c(
    quo_arg_name(size_q, "size"),
    if (!rlang::quo_is_null(color_q)) rlang::as_name(color_q)
  ))
  check_number(max_size, "max_size", lo = 0)
  check_number(alpha, "alpha", lo = 0, hi = 1)
  # One row per country, so a country contributes a single bubble.
  data <- dplyr::distinct(tibble::as_tibble(data), .data$iso3c, .keep_all = TRUE)

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
                               na_matches = "never")
    aes_pt <- if (!rlang::quo_is_null(color_q)) {
      ggplot2::aes(size = !!size_q, color = !!color_q)
    } else {
      ggplot2::aes(size = !!size_q)
    }
    return(
      ggplot2::ggplot() +
        ggplot2::geom_sf(data = countries, fill = "grey92", color = "grey80",
                         linewidth = 0.1) +
        ggplot2::geom_sf(data = pts_sf, mapping = aes_pt, alpha = alpha) +
        ggplot2::scale_size_area(max_size = max_size) +
        wdj_coord_sf(projection) +
        theme_world_map()
    )
  }

  # Polygon backend: base map and centroids are both in lon/lat degrees.
  cent <- world_geometry("centroids", geometry = "polygon")
  pts <- dplyr::left_join(data, cent[, c("iso3c", "centroid_lon", "centroid_lat")],
                          by = "iso3c", na_matches = "never")
  aes_pt <- if (!rlang::quo_is_null(color_q)) {
    ggplot2::aes(.data$centroid_lon, .data$centroid_lat,
                 size = !!size_q, color = !!color_q)
  } else {
    ggplot2::aes(.data$centroid_lon, .data$centroid_lat, size = !!size_q)
  }
  ggplot2::ggplot() +
    ggplot2::geom_polygon(
      data = world_geometry("countries", geometry = "polygon"),
      ggplot2::aes(.data$long, .data$lat, group = .data$group),
      fill = "grey92", color = "grey80", linewidth = 0.1
    ) +
    ggplot2::geom_point(data = pts, mapping = aes_pt, alpha = alpha) +
    ggplot2::scale_size_area(max_size = max_size) +
    ggplot2::coord_quickmap() +
    theme_world_map()
}

#' Spike map (heights at country centroids)
#'
#' The classic "population spikes" display: a triangular spike at each country
#' centroid whose height encodes the value. Like [bubble_map()] it is the
#' honest idiom for *totals*, with a different visual trade-off: spikes
#' overplot less in dense regions (Europe, the Caribbean) because they only
#' grow upward. Uses the polygon backend, so it needs only `maps`.
#'
#' @param data A country-level frame with `iso3c` and the `height` column.
#' @param height The column controlling spike height (unquoted).
#' @param max_height Height of the tallest spike, in degrees of latitude
#'   (default `20`).
#' @param width Base width of each spike, in degrees of longitude (default
#'   `1.6`).
#' @param color Spike colour (default a warm red).
#' @param alpha Spike fill transparency.
#'
#' @return A `ggplot` object.
#' @export
#' @examples
#' \donttest{
#' if (requireNamespace("maps", quietly = TRUE)) {
#'   spike_map(countryatlas::world_snapshot$countries, population)
#' }
#' }
spike_map <- function(data, height, max_height = 20, width = 1.6,
                      color = "#B2182B", alpha = 0.65) {
  height_q <- rlang::enquo(height)
  h_name <- quo_arg_name(height_q, "height")
  if (!"iso3c" %in% names(data)) {
    wdj_abort("{.arg data} must contain an {.field iso3c} column.")
  }
  check_cols(data, h_name)
  check_number(max_height, "max_height", lo = 0)
  check_number(width, "width", lo = 0)
  check_number(alpha, "alpha", lo = 0, hi = 1)
  data <- dplyr::distinct(tibble::as_tibble(data), .data$iso3c, .keep_all = TRUE)
  cent <- world_geometry("centroids", geometry = "polygon")
  pts <- dplyr::inner_join(data, cent[, c("iso3c", "centroid_lon", "centroid_lat")],
                           by = "iso3c", na_matches = "never")
  pts <- pts[is.finite(pts[[h_name]]) & pts[[h_name]] >= 0, ]
  if (!nrow(pts)) {
    wdj_abort("No rows with a non-negative {.val {h_name}} joined to a centroid.")
  }
  .mx <- max(pts[[h_name]]); h <- if (.mx > 0) pts[[h_name]] / .mx * max_height else rep(0, nrow(pts))

  # One triangle (3 vertices) per country: (x - w/2, y), (x, y + h), (x + w/2, y).
  spikes <- tibble::tibble(
    iso3c = rep(pts$iso3c, each = 3L),
    long = as.vector(rbind(pts$centroid_lon - width / 2,
                           pts$centroid_lon,
                           pts$centroid_lon + width / 2)),
    lat = as.vector(rbind(pts$centroid_lat,
                          pts$centroid_lat + h,
                          pts$centroid_lat))
  )
  ggplot2::ggplot() +
    ggplot2::geom_polygon(
      data = world_geometry("countries", geometry = "polygon"),
      ggplot2::aes(.data$long, .data$lat, group = .data$group),
      fill = "grey92", color = "grey80", linewidth = 0.1
    ) +
    ggplot2::geom_polygon(
      data = spikes,
      ggplot2::aes(.data$long, .data$lat, group = .data$iso3c),
      fill = color, color = color, alpha = alpha, linewidth = 0.3
    ) +
    ggplot2::coord_quickmap() +
    theme_world_map()
}

#' Two-variable bivariate choropleth
#'
#' A 2-D bivariate choropleth with a built-in 2-D legend (via the optional
#' `biscale` package), e.g. GDP per capita x life expectancy in one map.
#'
#' @param data An `sf` map-ready frame (use `geometry = "sf"`).
#' @param fill_x,fill_y The two value columns (unquoted).
#' @param palette A `biscale` palette name (default `"GrPink"`).
#' @param dim Bivariate dimension (2 or 3, default 3).
#' @param projection Projection; see [world_map()] for the ones available.
#'
#' @return A `ggplot` object (the map; combine with `biscale::bi_legend()` for a
#'   standalone legend).
#' @export
#' @examples
#' \donttest{
#' if (requireNamespace("sf", quietly = TRUE) &&
#'     requireNamespace("rnaturalearth", quietly = TRUE) &&
#'     requireNamespace("biscale", quietly = TRUE)) {
#'   attach_geometry(countryatlas::world_snapshot$countries, geometry = "sf") |>
#'     bivariate_map(gdp_per_capita, life_expectancy)
#' }
#' }
bivariate_map <- function(data, fill_x, fill_y, palette = "GrPink", dim = 3,
                          projection = "equal_earth") {
  need_pkg("biscale", "for bivariate_map()")
  need_pkg("sf", "for bivariate_map()")
  if (!is_sf(data)) wdj_abort("{.fn bivariate_map} needs an sf frame ({.code geometry = \"sf\"}).")
  x_name <- quo_arg_name(rlang::enquo(fill_x), "fill_x")
  y_name <- quo_arg_name(rlang::enquo(fill_y), "fill_y")

  for (nm in c(x_name, y_name)) {
    if (!nm %in% names(data)) {
      wdj_abort("Column {.val {nm}} not found in {.arg data}.")
    }
    check_numeric_col(data, nm)
  }
  # biscale indexes its break vector as sVar[1:(length(sVar) - 1)]. With nothing
  # to classify that is 1:-1, and the call dies on "only 0's may be mixed with
  # negative subscripts" -- which says nothing about the data. Note this bites
  # a *joined* frame too: attach_geometry() keeps every geometry row, so an
  # empty input arrives here as full-length columns of NA.
  if (!any(!is.na(data[[x_name]]) & !is.na(data[[y_name]]))) {
    wdj_abort(c(
      "No country has both {.val {x_name}} and {.val {y_name}}.",
      "i" = "A bivariate map needs values for both variables in the same row."
    ))
  }
  # bi_class() reads its x/y arguments with as.character(substitute(...)), not
  # tidy eval: a `!!sym()` injection deparses into a multi-element vector and
  # blows up inside biscale ("the condition has length > 1"), and a variable
  # holding the name deparses to the variable's own name. Build the call so
  # the column names are inlined as literals.
  bidata <- withCallingHandlers(
    do.call(
      biscale::bi_class,
      list(.data = data, x = x_name, y = y_name, style = "quantile", dim = dim)
    ),
    # Real-world indicators always have gaps, so biscale's "var has missing
    # values, omitted in finding classes" fires on essentially every call. The
    # classes are still valid; any other warning passes through untouched.
    warning = function(w) {
      if (grepl("missing values", conditionMessage(w), fixed = TRUE)) {
        invokeRestart("muffleWarning")
      }
    }
  )
  ggplot2::ggplot() +
    ggplot2::geom_sf(data = bidata, ggplot2::aes(fill = .data$bi_class),
                     color = "grey30", linewidth = 0.1, show.legend = FALSE) +
    biscale::bi_scale_fill(pal = palette, dim = dim) +
    wdj_coord_sf(projection) +
    biscale::bi_theme()
}

#' Area-honest cartogram
#'
#' Resizes countries by `weight` (population, GDP, ...) via the optional
#' `cartogram` package, defeating the "big empty countries dominate the eye"
#' bias of world choropleths.
#'
#' @param data An `sf` map-ready frame.
#' @param weight The column to resize by (unquoted).
#' @param type `"contiguous"` (default), `"dorling"` or `"noncontiguous"`.
#' @param fill Optional fill column (unquoted); defaults to `weight`.
#' @param projection Projection; an equal-area CRS is recommended. See
#'   [world_map()] for the projections available.
#' @param ... Passed to the underlying `cartogram::cartogram_*()` function
#'   (e.g. `itermax`, or `k` for `type = "dorling"` -- see [dorling_map()]).
#'
#' @return A `ggplot` object.
#' @export
#' @examples
#' \donttest{
#' if (requireNamespace("sf", quietly = TRUE) &&
#'     requireNamespace("rnaturalearth", quietly = TRUE) &&
#'     requireNamespace("cartogram", quietly = TRUE)) {
#'   attach_geometry(countryatlas::world_snapshot$countries, geometry = "sf") |>
#'     cartogram_map(population, type = "dorling")
#' }
#' }
cartogram_map <- function(data, weight, type = c("contiguous", "dorling",
                                                 "noncontiguous"),
                          fill = NULL, projection = "equal_earth", ...) {
  need_pkg(c("cartogram", "sf"), "for cartogram_map()")
  type <- match.arg(type)
  if (!is_sf(data)) wdj_abort("{.fn cartogram_map} needs an sf frame.")
  w_name <- quo_arg_name(rlang::enquo(weight), "weight")
  fill_q <- rlang::enquo(fill)
  fill_name <- if (rlang::quo_is_null(fill_q)) w_name else rlang::as_name(fill_q)
  check_cols(data, unique(c(w_name, fill_name)))

  check_numeric_col(data, w_name)
  data <- sf::st_transform(data, wdj_crs(projection))
  data <- data[!is.na(data[[w_name]]) & data[[w_name]] > 0, ]
  # cartogram iterates until `if (meanSizeError < maxSizeError) break`, which on
  # an empty frame compares NA and fails with "missing value where TRUE/FALSE
  # needed". Nothing left to weight is worth saying plainly.
  if (!nrow(data)) {
    wdj_abort(c(
      "No country has a positive {.val {w_name}} to size a cartogram by.",
      "i" = "Cartogram weights must be present and greater than zero."
    ))
  }
  carto <- switch(
    type,
    contiguous = cartogram::cartogram_cont(data, weight = w_name, ...),
    dorling = cartogram::cartogram_dorling(data, weight = w_name, ...),
    noncontiguous = cartogram::cartogram_ncont(data, weight = w_name, ...)
  )
  ggplot2::ggplot(carto) +
    ggplot2::geom_sf(ggplot2::aes(fill = .data[[fill_name]]),
                     color = "grey30", linewidth = 0.1) +
    ggplot2::scale_fill_viridis_c(name = fill_name) +
    theme_world_map()
}

#' Dorling cartogram (first-class verb)
#'
#' Non-overlapping proportional circles sized by `weight`, positioned to stay
#' as close as possible to each country's true location -- arguably the most
#' legible cartogram variant, since a microstate's circle is exactly as
#' visible as a giant country's. A first-class verb for
#' [cartogram_map()]`(type = "dorling")` that surfaces the Dorling-specific
#' tuning knobs.
#'
#' @param data An `sf` map-ready frame.
#' @param weight The column controlling circle size (unquoted).
#' @param fill Optional fill column (unquoted); defaults to `weight`.
#' @param k Share of the bounding box filled by the largest circle (default
#'   `5`; passed to `cartogram::cartogram_dorling()`).
#' @param itermax Maximum iterations of the circle-repulsion algorithm
#'   (default `1000`; raise it if circles still overlap in the result).
#' @param projection Projection; an equal-area CRS is recommended. See
#'   [world_map()] for the projections available.
#'
#' @return A `ggplot` object.
#' @export
#' @examples
#' \donttest{
#' if (requireNamespace("sf", quietly = TRUE) &&
#'     requireNamespace("rnaturalearth", quietly = TRUE) &&
#'     requireNamespace("cartogram", quietly = TRUE)) {
#'   attach_geometry(countryatlas::world_snapshot$countries, geometry = "sf") |>
#'     dorling_map(population)
#' }
#' }
dorling_map <- function(data, weight, fill = NULL, k = 5, itermax = 1000,
                        projection = "equal_earth") {
  # Unchecked, these surfaced as cartogram's own diagnostics -- "all sizes are
  # missing and/or non-positive" for k, and an assertion naming cartogram's
  # internal `maxiter` rather than our `itermax`.
  check_number(k, "k", lo = 0)
  check_number(itermax, "itermax", lo = 1, hi = .Machine$integer.max)
  # check_number()'s bounds are inclusive, but cartogram needs k > 0 and reports
  # a zero as "all sizes are missing and/or non-positive". Same shape as
  # simplify_geometry()'s keep guard. Anything above zero is fine (1e-6 works).
  if (k == 0) {
    wdj_abort(c(
      "{.arg k} must be greater than 0.",
      "x" = "A spread factor of {.val {k}} leaves every circle with no size."
    ))
  }
  cartogram_map(data, !!rlang::enquo(weight), type = "dorling",
                fill = !!rlang::enquo(fill), projection = projection,
                k = k, itermax = itermax)
}

#' Equal-area world tile grid
#'
#' A statebins-style equal-area tile grid of the world (one square per country)
#' so tiny states are actually visible. Uses the bundled [world_tiles] layout.
#' For small multiples of a tile grid, facet the result as you would any other
#' `ggplot` (or see [facet_map()] for the choropleth equivalent).
#'
#' Every tile in the layout is drawn, taking the scale's `na.value` fill where
#' `data` has no row for it. The converse also holds and is quieter: `data` rows
#' keyed on one of the 10 countries with no tile are dropped without a warning
#' (see [world_tiles] for which).
#'
#' @param data A country-level frame with `iso3c` and the `fill` column.
#' @param fill The fill column (unquoted).
#' @param label Whether to draw ISO codes on the tiles (default `TRUE`).
#'
#' @return A `ggplot` object.
#' @export
#' @examples
#' \donttest{
#' tile_map(countryatlas::world_snapshot$countries, gdp_per_capita)
#' }
tile_map <- function(data, fill, label = TRUE) {
  check_bool(label, "label")
  fill_q <- rlang::enquo(fill)
  fill_name <- quo_arg_name(fill_q, "fill")
  if (!"iso3c" %in% names(data)) {
    wdj_abort("{.arg data} must contain an {.field iso3c} column.")
  }
  check_cols(data, fill_name)
  grid <- countryatlas::world_tiles
  tiles <- dplyr::left_join(grid, tibble::as_tibble(data), by = "iso3c",
                            na_matches = "never")
  p <- ggplot2::ggplot(tiles, ggplot2::aes(.data$col, -.data$row)) +
    ggplot2::geom_tile(ggplot2::aes(fill = !!fill_q), color = "white") +
    ggplot2::scale_fill_viridis_c(name = fill_name, na.value = "grey90") +
    ggplot2::coord_equal() +
    theme_world_map()
  if (isTRUE(label)) {
    p <- p + ggplot2::geom_text(ggplot2::aes(label = .data$iso3c), size = 2.5)
  }
  p
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
#' @param n Points per arc (smoothness).
#'
#' @return A `ggplot` object.
#' @export
#' @examples
#' \donttest{
#' od <- data.frame(from = c("China", "Germany"),
#'                  to = c("United States", "France"),
#'                  value = c(500, 200))
#' if (requireNamespace("maps", quietly = TRUE)) {
#'   flow_map(od, from, to, value)
#' }
#' }
flow_map <- function(data, from, to, weight = NULL, origin = "country.name",
                     n = 50) {
  from_name <- quo_arg_name(rlang::enquo(from), "from")
  to_name <- quo_arg_name(rlang::enquo(to), "to")
  weight_q <- rlang::enquo(weight)
  check_cols(data, c(
    from_name, to_name,
    if (!rlang::quo_is_null(weight_q)) rlang::as_name(weight_q)
  ))
  # An arc needs at least two points; below that seq() errored on length.out.
  check_number(n, "n", lo = 2, hi = .Machine$integer.max)

  cent <- world_geometry("centroids", geometry = "polygon")
  cent <- cent[, c("iso3c", "centroid_lon", "centroid_lat")]

  data <- tibble::as_tibble(data)
  data$.from_iso <- wdj_to_iso3c(data[[from_name]], origin = origin)
  data$.to_iso <- wdj_to_iso3c(data[[to_name]], origin = origin)
  data$.id <- seq_len(nrow(data))

  d <- dplyr::left_join(data, stats::setNames(cent, c(".from_iso", "x0", "y0")),
                        by = ".from_iso", na_matches = "never")
  d <- dplyr::left_join(d, stats::setNames(cent, c(".to_iso", "x1", "y1")),
                        by = ".to_iso", na_matches = "never")
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
  d <- d[keep, ]

  arcs <- do.call(rbind, lapply(seq_len(nrow(d)), function(i) {
    gc <- great_circle(d$x0[i], d$y0[i], d$x1[i], d$y1[i], n = n)
    gc$.id <- d$.id[i]
    if (!rlang::quo_is_null(weight_q)) {
      gc$weight <- d[[rlang::as_name(weight_q)]][i]
    }
    gc
  }))

  base <- ggplot2::ggplot() +
    ggplot2::geom_polygon(
      data = world_geometry("countries", geometry = "polygon"),
      ggplot2::aes(.data$long, .data$lat, group = .data$group),
      fill = "grey92", color = "grey80", linewidth = 0.1
    )
  if (is.null(arcs) || !nrow(arcs)) return(base + ggplot2::coord_quickmap() + theme_world_map())
  arc_aes <- if (!rlang::quo_is_null(weight_q)) {
    ggplot2::aes(.data$lon, .data$lat, group = .data$.id,
                 linewidth = .data$weight, alpha = .data$weight)
  } else {
    ggplot2::aes(.data$lon, .data$lat, group = .data$.id)
  }
  base +
    ggplot2::geom_path(data = arcs, mapping = arc_aes, color = "#2166AC") +
    ggplot2::scale_linewidth(range = c(0.2, 2)) +
    ggplot2::coord_quickmap() +
    theme_world_map()
}

# Great-circle interpolation (spherical slerp) between two lon/lat points.
great_circle <- function(lon1, lat1, lon2, lat2, n = 50) {
  d2r <- pi / 180
  phi1 <- lat1 * d2r; lam1 <- lon1 * d2r
  phi2 <- lat2 * d2r; lam2 <- lon2 * d2r
  # angular distance
  dlt <- acos(pmin(1, pmax(-1,
    sin(phi1) * sin(phi2) + cos(phi1) * cos(phi2) * cos(lam2 - lam1))))
  f <- seq(0, 1, length.out = n)
  if (dlt == 0) {
    return(tibble::tibble(lon = rep(lon1, n), lat = rep(lat1, n)))
  }
  A <- sin((1 - f) * dlt) / sin(dlt)
  B <- sin(f * dlt) / sin(dlt)
  x <- A * cos(phi1) * cos(lam1) + B * cos(phi2) * cos(lam2)
  y <- A * cos(phi1) * sin(lam1) + B * cos(phi2) * sin(lam2)
  z <- A * sin(phi1) + B * sin(phi2)
  lat <- atan2(z, sqrt(x^2 + y^2)) / d2r
  lon <- atan2(y, x) / d2r
  tibble::tibble(lon = lon, lat = lat)
}

#' Animate a choropleth over time
#'
#' Given a panel from `world_data(2000:2020, ...)`, animate the choropleth over
#' `year` via the optional `gganimate` package, or fall back to a faceted
#' small-multiple when it is not installed.
#'
#' @param data A panel map-ready frame (polygon or sf) with a `time` column.
#' @param fill The fill column (unquoted).
#' @param time The time column (unquoted; default `year`).
#' @param projection Projection for the sf backend. See [world_map()] for the
#'   projections available.
#' @param ... Passed to [world_map()].
#'
#' @return A `gganim` object (if `gganimate` is available) or a faceted
#'   `ggplot`.
#' @export
#' @examples
#' \dontrun{
#' world_data(2000:2005, c(gdp = "NY.GDP.PCAP.KD")) |>
#'   animate_world(gdp)
#' }
animate_world <- function(data, fill, time = year, projection = "equal_earth",
                          ...) {
  fill_q <- rlang::enquo(fill)
  time_name <- rlang::as_name(rlang::enquo(time))
  if (!time_name %in% names(data)) {
    wdj_abort("Time column {.val {time_name}} not found in {.arg data}.")
  }
  p <- world_map(data, !!fill_q, projection = projection, ...)
  if (has_pkg("gganimate")) {
    p +
      gganimate::transition_manual(frames = .data[[time_name]]) +
      ggplot2::labs(title = paste0("{current_frame}"))
  } else {
    wdj_inform(c("i" = "Package {.pkg gganimate} not installed; faceting by {.val {time_name}} instead."))
    p + ggplot2::facet_wrap(stats::as.formula(paste0("~", time_name)))
  }
}

#' Web-ready interactive choropleth
#'
#' An interactive choropleth with hover and zoom, for dashboards and
#' R Markdown / Quarto. Engines are all optional `Suggests`.
#'
#' @param data A map-ready frame (polygon or sf). The `"leaflet"` engine will
#'   attach geometry itself if given a country-level table; the others require
#'   it already attached.
#' @param fill The fill column (unquoted).
#' @param tooltip Optional tooltip column (unquoted).
#' @param engine `"plotly"` (default), `"ggiraph"`, `"leaflet"` or `"ggsql"`
#'   (database-side rendering to a Vega-Lite widget; needs an `sf` frame and
#'   `ggsql` >= 0.4.1, the version that added the `DRAW spatial` clause).
#'   `tooltip` is honoured by the `"ggiraph"` and `"leaflet"` engines (defaults
#'   to `fill` when omitted); `"plotly"`'s hover is controlled by `world_map()`
#'   aesthetics instead, and `"ggsql"` has no hover concept.
#' @param ... Passed to [world_map()] for the plotly/ggiraph engines, or to
#'   [world_query()] for the `"ggsql"` engine.
#'
#' @return An interactive widget.
#' @export
#' @examples
#' \dontrun{
#' world_data(2020) |> interactive_map(gdp_per_capita)
#' world_data(2020, geometry = "sf") |>
#'   interactive_map(gdp_per_capita, engine = "ggsql", transform = "log10")
#' }
interactive_map <- function(data, fill, tooltip = NULL,
                            engine = c("plotly", "ggiraph", "leaflet", "ggsql"),
                            ...) {
  engine <- match.arg(engine)
  fill_q <- rlang::enquo(fill)
  tooltip_q <- rlang::enquo(tooltip)
  # Cheap checks before the environment gates, as in globe_map()/spin_globe():
  # a non-sf frame used to be told to install ggsql >= 0.4.1 (which has not
  # shipped in the R bindings at all), and would only learn the real problem
  # after chasing a package it did not need.
  if (identical(engine, "ggsql") && !is_sf(data)) {
    wdj_abort(c(
      '{.code engine = "ggsql"} needs an sf frame so {.code DRAW spatial} has geometry.',
      "i" = 'Build one with {.code world_data(..., geometry = "sf")} or {.fn attach_geometry}.'
    ))
  }
  # `DRAW spatial` -- the clause world_query() emits -- arrived in ggsql 0.4.1.
  # Older ggsql accepts the call and then fails inside its own SQL front end on
  # a clause it does not know, so gate on the version, not mere presence.
  need_pkg(engine, sprintf("for interactive_map(engine = \"%s\")", engine),
           version = if (identical(engine, "ggsql")) "0.4.1" else NULL)

  if (engine == "ggsql") {
    need_pkg(c("sf", "DBI", "duckdb"),
             "for interactive_map(engine = \"ggsql\")")
    reader <- ggsql::duckdb_reader()
    ggsql::ggsql_register(reader, ggsql_wkb_frame(data), "countryatlas_world")
    q <- world_query(!!fill_q, source = "countryatlas_world", ...)
    return(ggsql::ggsql_execute(reader, unclass(q)))
  }

  if (engine == "plotly") {
    p <- world_map(data, !!fill_q, ...)
    return(plotly::ggplotly(p))
  }
  if (engine == "ggiraph") {
    need_pkg("ggiraph")
    # This branch assembles its own ggplot instead of calling world_map(), so it
    # needs the same check: without it, a country-level frame reached
    # geom_polygon_interactive() and failed at render time on `.data$long`,
    # while engine = "plotly" reported the problem properly.
    check_map_geometry(data)
    check_cols(data, c(
      quo_arg_name(fill_q, "fill"),
      if (!rlang::quo_is_null(tooltip_q)) rlang::as_name(tooltip_q)
    ))
    tooltip_mapped <- if (rlang::quo_is_null(tooltip_q)) fill_q else tooltip_q
    if (is_sf(data)) {
      p <- ggplot2::ggplot(data) +
        ggiraph::geom_sf_interactive(
          ggplot2::aes(fill = !!fill_q, tooltip = !!tooltip_mapped, data_id = .data$iso3c)
        ) + theme_world_map()
    } else {
      p <- ggplot2::ggplot(
        data, ggplot2::aes(.data$long, .data$lat, group = .data$group)) +
        ggiraph::geom_polygon_interactive(
          ggplot2::aes(fill = !!fill_q, tooltip = !!tooltip_mapped, data_id = .data$iso3c)
        ) + ggplot2::coord_quickmap() + theme_world_map()
    }
    return(ggiraph::girafe(ggobj = p))
  }
  # leaflet
  need_pkg(c("leaflet", "sf"))
  check_cols(data, c(
    quo_arg_name(fill_q, "fill"),
    if (!rlang::quo_is_null(tooltip_q)) rlang::as_name(tooltip_q)
  ))
  if (!is_sf(data)) {
    # This branch gates on !is_sf, so `data` may be a *polygon* frame: reduced to
    # one row per country it still carries long/lat/group, which attach_geometry()
    # now (rightly) refuses. Strip them. (globe_map's polygon branch gates on the
    # columns themselves, so it needs no equivalent.)
    data <- attach_geometry(
      drop_map_geometry(
        dplyr::distinct(tibble::as_tibble(data), .data$iso3c, .keep_all = TRUE)),
      geometry = "sf")
  }
  fill_name <- quo_arg_name(fill_q, "fill")
  tooltip_name <- if (rlang::quo_is_null(tooltip_q)) fill_name else rlang::as_name(tooltip_q)
  pal <- leaflet::colorNumeric("viridis", domain = data[[fill_name]],
                               na.color = "#dddddd")
  leaflet::leaflet(sf::st_transform(data, 4326L)) |>
    leaflet::addPolygons(
      fillColor = ~ pal(get(fill_name)), weight = 0.5, color = "grey",
      fillOpacity = 0.8,
      label = ~ paste0(iso3c, ": ", get(tooltip_name))
    ) |>
    leaflet::addLegend(pal = pal, values = ~ get(fill_name), title = fill_name)
}

#' Centroid-anchored country labels
#'
#' A `ggplot2` layer that places labels (names, ISO codes or flag emoji) at
#' country centroids, with optional `ggrepel` collision avoidance. Designed for
#' the polygon backend produced by [world_data()] / [join_world()]: it reads the
#' `long`, `lat` and `group` columns, so it errors on an `sf` frame and points at
#' [ggplot2::geom_sf_text()] instead. Placement is exact only while `group` is
#' present -- that is what identifies each country's separate pieces, and the
#' label goes on the largest one.
#'
#' @param mapping Aesthetic mapping; defaults to `aes(label = iso3c)`.
#' @param repel Use `ggrepel` to avoid overlaps (default `TRUE`). Falls back to
#'   plain labels, with a one-time note, when `ggrepel` is not installed.
#' @param flag If `TRUE`, label with flag emoji instead of the mapped label.
#' @param size Label text size.
#' @param ... Passed to the underlying text geom.
#'
#' @return A `ggplot2` layer.
#' @export
#' @examples
#' \donttest{
#' library(ggplot2)
#' snap <- countryatlas::world_snapshot$countries
#' if (requireNamespace("maps", quietly = TRUE)) {
#'   mapdf <- attach_geometry(snap, geometry = "polygon")
#'   world_map(mapdf, gdp_per_capita) + geom_country_labels()
#' }
#' }
geom_country_labels <- function(mapping = NULL, repel = TRUE, flag = FALSE,
                                size = 3, ...) {
  check_bool(repel, "repel")
  check_bool(flag, "flag")
  label_data <- function(d) {
    # An sf frame has no long/lat columns, so the layer's own aes() died on
    # rlang's "Column `long` not found in `.data`" before ever reaching the
    # guard below. Say what to use instead.
    if (is_sf(d)) {
      wdj_abort(c(
        "{.fn geom_country_labels} needs the polygon backend.",
        "x" = "Got an sf frame, which has no {.field long}/{.field lat} columns.",
        "i" = 'Attach polygon geometry with
               {.code attach_geometry(data, geometry = "polygon")}, or label an
               sf map with {.code ggplot2::geom_sf_text(aes(label = iso3c))}.'
      ))
    }
    if (!all(c("long", "lat", "iso3c") %in% names(d))) {
      return(d[0, , drop = FALSE])
    }
    # An empty frame reaches range() with nothing to range over, which warns
    # (twice, plus a dplyr deprecation about the row count) before returning
    # Inf/-Inf. There are no labels to place, so stop before that.
    if (!nrow(d)) return(d[0, , drop = FALSE])
    # One antimeridian-safe centroid per country (largest piece), so the US /
    # Fiji / NZ labels don't drift into the wrong ocean.
    out <- if ("group" %in% names(d)) {
      polygon_centroids(d)
    } else {
      # Without `group` there are no piece boundaries, so the largest-piece rule
      # is unavailable and this is an approximation -- see
      # antimeridian_centre(). Keep `group` (the polygon backend always supplies
      # it) for exact placement.
      d %>%
        dplyr::group_by(.data$iso3c) %>%
        dplyr::summarise(
          centroid_lon = antimeridian_centre(.data$long),
          centroid_lat = mean(range(.data$lat, na.rm = TRUE)),
          .groups = "drop"
        )
    }
    names(out)[names(out) == "centroid_lon"] <- "long"
    names(out)[names(out) == "centroid_lat"] <- "lat"
    out$flag <- convert_country(out$iso3c, to = "flag", from = "iso3c",
                                warn = FALSE)
    out
  }
  # Build a self-contained mapping (don't inherit the plot's group/fill aes).
  lab <- if (isTRUE(flag)) ggplot2::aes(label = .data$flag) else
    ggplot2::aes(label = .data$iso3c)
  base_map <- ggplot2::aes(x = .data$long, y = .data$lat)
  full_map <- utils::modifyList(base_map, mapping %||% lab)

  if (isTRUE(repel) && has_pkg("ggrepel")) {
    ggrepel::geom_text_repel(mapping = full_map, data = label_data, size = size,
                             inherit.aes = FALSE, ...)
  } else {
    # Asking for repelling and silently not getting it was the one degraded
    # backend the package did not announce (classInt, gganimate and rmapshaper
    # all say so). `repel = TRUE` is the default, so say it once rather than on
    # every call -- the same treatment wdj_overrides() gets.
    if (isTRUE(repel)) {
      wdj_inform(
        c("i" = "Package {.pkg ggrepel} not installed; drawing plain labels without collision avoidance."),
        .frequency = "once", .frequency_id = "geom_country_labels-no-ggrepel"
      )
    }
    ggplot2::geom_text(mapping = full_map, data = label_data, size = size,
                       inherit.aes = FALSE, ...)
  }
}

#' Simplify (thin) geometry for faster plotting
#'
#' Reduce the vertex count of an `sf` object via the optional `rmapshaper`
#' package (falling back to [sf::st_simplify()]), for fast web/plotting.
#'
#' @param x An `sf` object.
#' @param keep Proportion of vertices to keep: greater than 0 and at most 1
#'   (`keep = 0` would leave nothing to draw and errors). Honoured as a proportion
#'   only by `rmapshaper`; without it the `sf::st_simplify()` fallback can work
#'   only from a distance tolerance, so `keep` is approximated (scaled to the
#'   object's extent) and simplifies less aggressively. Install `rmapshaper`
#'   for proportional control.
#' @param ... Passed to the underlying simplifier.
#'
#' @return A simplified `sf` object.
#' @export
#' @examples
#' \donttest{
#' if (requireNamespace("sf", quietly = TRUE) &&
#'     requireNamespace("rnaturalearth", quietly = TRUE)) {
#'   world_geometry(geometry = "sf") |> simplify_geometry(keep = 0.1)
#' }
#' }
simplify_geometry <- function(x, keep = 0.05, ...) {
  need_pkg("sf")
  check_number(keep, "keep", lo = 0, hi = 1)
  # A proportion of zero keeps no vertices. rmapshaper rejects it, but the
  # st_simplify() fallback silently accepted it, so the same call errored or
  # not depending on which optional package the caller happened to have.
  if (keep == 0) {
    wdj_abort(c(
      "{.arg keep} must be greater than 0.",
      "x" = "A proportion of {.val {keep}} would keep no vertices."
    ))
  }
  # Both simplifiers collapse a single-part MULTIPOLYGON to a POLYGON, so the
  # result is a mixed sfc_GEOMETRY column even though the input was uniform --
  # and sf::st_coordinates() is not implemented for that. get_world_sf() casts
  # for the same reason; simplifying undid it. A type change only.
  keep_multipolygon <- function(g) {
    if (!inherits(g, "sf") || !any(grepl("POLYGON", sf::st_geometry_type(g)))) {
      return(g)
    }
    suppressWarnings(sf::st_cast(g, "MULTIPOLYGON", warn = FALSE))
  }
  if (has_pkg("rmapshaper")) {
    return(keep_multipolygon(with_c_numbers(
      rmapshaper::ms_simplify(x, keep = keep, keep_shapes = TRUE, ...))))
  }
  wdj_warn("Package {.pkg rmapshaper} not installed; using {.fn sf::st_simplify}.")
  # st_simplify() takes a distance, not a proportion, so `keep` can only be
  # approximated. Scale the tolerance to the object's own extent rather than
  # assuming metres: a fixed 10000 meant 9 km on a projected frame (which barely
  # simplified anything) and 9000 degrees on a lon/lat one (meaningless, and
  # survivable only because preserveTopology keeps a husk).
  span <- suppressWarnings(as.numeric(diff(sf::st_bbox(x)[c(1, 3)])))
  if (!length(span) || !is.finite(span) || span <= 0) span <- 1
  keep_multipolygon(
    sf::st_simplify(x, dTolerance = (1 - keep) * span / 500,
                    preserveTopology = TRUE))
}

#' Orthographic globe choropleth
#'
#' The world as a globe (orthographic projection) centred on `lon`/`lat` -- the
#' honest answer to "the whole world on a rectangle exaggerates the poles". Takes
#' the same `fill` / `style` options as [world_map()]. The default `"sf"` backend
#' gives the cleanest limb; the `"polygon"` backend draws the globe with
#' [ggplot2::coord_map()] and needs only `maps` + `mapproj` (no `sf`).
#'
#' @param data A map-ready frame: an `sf` frame for `backend = "sf"`, or a
#'   country-level frame with `iso3c` (or a polygon frame) for
#'   `backend = "polygon"`.
#' @param fill The fill column (unquoted).
#' @param lon,lat The longitude / latitude the globe is centred on (the face
#'   pointing at the viewer).
#' @param backend `"sf"` (default, via [ggplot2::coord_sf()]) or `"polygon"`
#'   (via [ggplot2::coord_map()], no `sf` required).
#' @param style,palette,n_bins,borders,title,legend,na_label As in [world_map()].
#'
#' @return A `ggplot` object.
#' @export
#' @examples
#' \donttest{
#' # No sf required -- the polygon backend needs only maps + mapproj:
#' if (requireNamespace("maps", quietly = TRUE) &&
#'     requireNamespace("mapproj", quietly = TRUE)) {
#'   globe_map(countryatlas::world_snapshot$countries, continent,
#'             backend = "polygon", style = "categorical")
#' }
#' }
#' \dontrun{
#' # The sf backend gives the cleanest limb (needs a World Bank fetch):
#' world_data(2020, geometry = "sf") |>
#'   globe_map(gdp_per_capita, lon = 10, lat = 30)
#' }
globe_map <- function(data, fill, lon = 0, lat = 20,
                      backend = c("sf", "polygon"),
                      style = c("continuous", "binned", "quantile", "jenks",
                                "categorical"),
                      palette = NULL, n_bins = 5, borders = TRUE,
                      title = NULL, legend = NULL, na_label = "No data") {
  check_bool(borders, "borders")
  check_label_args(palette, title, legend, na_label)
  backend <- match.arg(backend)
  style <- match.arg(style)
  fill_q <- rlang::enquo(fill)
  fill_name <- quo_arg_name(fill_q, "fill")
  # The sf backend validates these via wdj_crs(), but the polygon backend goes
  # to coord_map() instead, which took a nonsense orientation without comment.
  check_number(lon, "lon", lo = -360, hi = 360)
  check_number(lat, "lat", lo = -90, hi = 90)

  if (backend == "polygon") {
    need_pkg("mapproj", "for globe_map(backend = \"polygon\")")
    # Bring a country-level table onto polygon geometry if it isn't already.
    if (!all(c("long", "lat", "group") %in% names(data))) {
      if (!"iso3c" %in% names(data)) {
        wdj_abort("{.arg data} needs an {.field iso3c} column (or polygon geometry).")
      }
      # No drop_map_geometry() here: this branch is reached only when the frame
      # lacks long/lat/group, so there is nothing to drop.
      data <- attach_geometry(
        dplyr::distinct(tibble::as_tibble(data), .data$iso3c, .keep_all = TRUE),
        geometry = "polygon"
      )
    }
    check_cols(data, fill_name)
    check_categorical_fill(style, data[[fill_name]], fill_name)
    binned <- apply_binned_fill(data, fill_q, fill_name, style, n_bins)
    data <- binned$data
    fill_mapped <- binned$fill
    p <- ggplot2::ggplot(
      data, ggplot2::aes(.data$long, .data$lat, group = .data$group,
                         fill = !!fill_mapped)
    ) +
      ggplot2::geom_polygon(color = if (borders) "grey25" else NA, linewidth = 0.1) +
      ggplot2::coord_map("orthographic", orientation = c(lat, lon, 0)) +
      add_fill_scale(style, palette, n_bins, na_label, legend %||% fill_name) +
      theme_world_map()
    if (!is.null(title)) p <- p + ggplot2::labs(title = title)
    return(p)
  }

  # sf backend.
  need_pkg("sf", "for globe_map()")
  if (!is_sf(data)) {
    wdj_abort("{.fn globe_map} needs an sf frame ({.code geometry = \"sf\"}) for {.code backend = \"sf\"}.")
  }
  check_cols(data, fill_name)
  check_categorical_fill(style, data[[fill_name]], fill_name)
  binned <- apply_binned_fill(data, fill_q, fill_name, style, n_bins)
  data <- binned$data
  fill_mapped <- binned$fill

  p <- ggplot2::ggplot(data) +
    ggplot2::geom_sf(ggplot2::aes(fill = !!fill_mapped),
                     color = if (borders) "grey30" else NA, linewidth = 0.1) +
    wdj_coord_sf("orthographic", recenter = lon, lat0 = lat) +
    add_fill_scale(style, palette, n_bins, na_label, legend %||% fill_name) +
    theme_world_map()
  if (!is.null(title)) p <- p + ggplot2::labs(title = title)
  p
}

#' Spin the globe
#'
#' An animated GIF of the world rotating on its axis: a sequence of orthographic
#' [globe_map()] frames at evenly spaced central longitudes, assembled into a
#' looping animation with the optional `gifski` (preferred) or `magick` package.
#' Embeds directly in R Markdown / Quarto / a README.
#'
#' @param data A map-ready frame (see [globe_map()]): a country-level frame with
#'   `iso3c` for the `"polygon"` backend, or an `sf` frame for `"sf"`.
#' @param fill The fill column (unquoted).
#' @param lat The latitude the globe is tilted toward (the viewer's eye line).
#' @param n_frames Number of frames in one full 360 degrees rotation.
#' @param fps Frames per second of the output animation.
#' @param backend `"polygon"` (default; needs `maps` + `mapproj`, no `sf`) or
#'   `"sf"`.
#' @param width,height Pixel dimensions of the animation.
#' @param file Optional output path (`.gif`); a temporary file is used if `NULL`.
#' @param ... Passed to [globe_map()] (e.g. `fill` `style`, `palette`).
#'
#' @return The path to the written GIF, invisibly.
#' @export
#' @examples
#' \dontrun{
#' # No sf required:
#' spin_globe(world_snapshot$countries, continent, backend = "polygon",
#'            style = "categorical")
#' }
spin_globe <- function(data, fill, lat = 20, n_frames = 60, fps = 15,
                       backend = c("polygon", "sf"), width = 480, height = 480,
                       file = NULL, ...) {
  backend <- match.arg(backend)
  fill_q <- rlang::enquo(fill)
  # Validate the arguments before gating on the animation packages: a bad
  # argument is the caller's bug and the message should not depend on which
  # optional packages happen to be installed. (globe_map() orders these the
  # same way.)
  check_number(n_frames, "n_frames", lo = 2, hi = .Machine$integer.max)
  check_number(fps, "fps", lo = 1)
  check_number(width, "width", lo = 1)
  check_number(height, "height", lo = 1)
  check_number(lat, "lat", lo = -90, hi = 90)
  # The scalars were moved ahead of the gate but the fill column was not, so a
  # mistyped column still reported a missing gifski.
  check_cols(data, quo_arg_name(fill_q, "fill"))
  if (!has_pkg("gifski") && !has_pkg("magick")) {
    need_pkg("gifski", "to assemble the animation (or install 'magick')")
  }
  n_frames <- as.integer(n_frames)

  # One full turn: drop the duplicated 360 == 0 frame so the loop is seamless.
  lons <- utils::head(seq(0, 360, length.out = n_frames + 1L), -1L)
  tmpdir <- tempfile("spin_globe_")
  dir.create(tmpdir)
  on.exit(unlink(tmpdir, recursive = TRUE), add = TRUE)
  frames <- file.path(tmpdir, sprintf("frame_%04d.png", seq_along(lons)))

  for (i in seq_along(lons)) {
    p <- globe_map(data, !!fill_q, lon = lons[i], lat = lat, backend = backend, ...)
    suppressWarnings(ggplot2::ggsave(
      frames[i], p, width = width / 72, height = height / 72, dpi = 72,
      bg = "white"
    ))
  }

  out <- file %||% tempfile(fileext = ".gif")
  if (has_pkg("gifski")) {
    gifski::gifski(frames, gif_file = out, width = width, height = height,
                   delay = 1 / fps, loop = TRUE, progress = FALSE)
  } else {
    anim <- magick::image_animate(magick::image_read(frames), fps = fps)
    magick::image_write(anim, out)
  }
  invisible(out)
}

#' Small-multiple choropleths
#'
#' Facet a choropleth into small multiples (one panel per group or per year) --
#' the static counterpart to [animate_world()], for print and side-by-side
#' comparison. Builds a [world_map()] and facets it on `facet`.
#'
#' @param data A map-ready frame (polygon or sf) containing the `facet` column.
#' @param fill The fill column (unquoted).
#' @param facet The faceting column (unquoted; e.g. `year` or `continent`).
#' @param ncol Number of facet columns (passed to [ggplot2::facet_wrap()]).
#' @param ... Passed to [world_map()] (e.g. `style`, `projection`).
#'
#' @return A faceted `ggplot` object.
#' @export
#' @examples
#' \donttest{
#' snap <- countryatlas::world_snapshot$countries
#' if (requireNamespace("maps", quietly = TRUE)) {
#'   mapdf <- attach_geometry(snap, geometry = "polygon")
#'   facet_map(mapdf, gdp_per_capita, continent, style = "quantile")
#' }
#' }
facet_map <- function(data, fill, facet, ncol = NULL, ...) {
  fill_q <- rlang::enquo(fill)
  facet_name <- quo_arg_name(rlang::enquo(facet), "facet")
  if (!facet_name %in% names(data)) {
    wdj_abort("Facet column {.val {facet_name}} not found in {.arg data}.")
  }
  # ggplot2 refuses to facet nothing -- "Faceting variables must have at least
  # one value" names neither the argument nor the package. Every other verb
  # draws an empty panel for an empty frame; this one cannot, so say why.
  if (!nrow(data)) {
    wdj_abort(c(
      "{.arg data} has no rows to facet.",
      "i" = "One panel per {.val {facet_name}} needs at least one row;
             the other map verbs will draw an empty panel."
    ))
  }
  world_map(data, !!fill_q, ...) +
    ggplot2::facet_wrap(ggplot2::vars(.data[[facet_name]]), ncol = ncol)
}
