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
  # Both feed ggplot2's own arithmetic and font lookup, so a non-number
  # surfaced as base R's bare "non-numeric argument to binary operator" and a
  # non-string got no check at all.
  check_number(base_size, "base_size", lo = 0)
  check_string(base_family, "base_family", allow_empty = TRUE)
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

# facet_map(facet = year) and animate_world() resolve a panel rather than
# overplotting it, so world_map()'s panel warning is noise on their way through.
# Muffled by class, not suppressWarnings(): any *other* warning the call raises
# still has to reach the caller.
without_panel_warning <- function(expr) {
  withCallingHandlers(
    expr,
    countryatlas_panel = function(w) invokeRestart("muffleWarning"))
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
    cls <- switch(style, quantile = "quantile", jenks = "jenks",
                  equal = "equal", "quantile")
    # classInt is chatty when n equals the number of distinct values, or on
    # ties; the binning is still valid, so don't leak the warning to callers.
    br <- suppressWarnings(
      classInt::classIntervals(x, n = n_bins, style = cls)
    )$brks
    return(unique(br))
  }
  if (style == "equal") {
    return(unique(seq(min(x), max(x), length.out = n_bins + 1)))
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
#'   continuous and binned colourbars have no `NA` key to name. Honoured by
#'   both engines. A length-1 `NA` leaves the engine's own formatter alone.
#' @param recenter Optional central meridian for the `sf` backend.
#' @param na_style How to draw countries with no data: `"grey"` (default),
#'   `"hatched"` (diagonal hatching via the optional `ggpattern`, unmistakable
#'   and greyscale-safe), `"outline"` (white fill, keeping only the border) or
#'   `"omit"` (do not draw them at all). See the section below.
#' @param footnote Optional caption. `"auto"` generates a coverage line
#'   ("174 of 195 countries shown; 21 missing"), so the map cannot quietly
#'   overstate what it covers. A string is used verbatim; `NULL` (default) adds
#'   nothing.
#' @param uncertainty Optional uncertainty column (unquoted) -- a standard
#'   error, a confidence half-width, anything where larger means less certain.
#'   Supplying it switches the fill to a **value-suppressing uncertainty
#'   palette** (Correll, Moritz & Heer 2018): the value range contracts as
#'   uncertainty rises, so an uncertain estimate cannot claim an extreme colour,
#'   and the legend becomes the value x uncertainty grid.
#' @param n_uncertainty Number of uncertainty levels for the VSUP (default `3`).
#' @param engine `"ggplot2"` (default) or `"tmap"`. The package is
#'   ggplot2-native; the `tmap` path is an alternative renderer for people
#'   already working in tmap, and needs an `sf` frame. It honours `style`,
#'   `n_bins`, `palette`, `title` and `legend`, and ignores the ggplot2-specific
#'   arguments.
#' @param disputes `"ignore"` (default) or `"mark"`, which outlines the
#'   [disputed_territories] present in the data and notes the convention in the
#'   caption. See [dispute_policy()].
#' @param classification_report If `TRUE`, attach the breaks, the method and
#'   the count of countries per class to the returned plot as the
#'   `"countryatlas_classification"` attribute, and print them with
#'   [map_provenance()]. A map whose top class holds one country and whose
#'   bottom holds ninety is misleading, and the counts say so immediately.
#'   `style = "continuous"` draws a colourbar and so has no classes to report:
#'   there the attribute is `NULL` and a warning says why.
#'
#' @return A `ggplot` object.
#'
#' @section Missing data is not zero:
#' The default grey reads as "low" to many people, which is exactly wrong for
#' "unknown". `na_style = "hatched"` draws diagonal hatching instead --
#' unambiguous, and it survives greyscale printing. `"omit"` leaves a hole,
#' which is honest but can be mistaken for ocean. Whichever you pick,
#' `footnote = "auto"` states the count in words:
#' ```r
#' world_map(mapdf, gdp_per_capita, na_style = "hatched", footnote = "auto")
#' ```
#' [coverage_map()] goes further and maps availability itself.
#'
#' @section Choosing a classification:
#' The classification changes what readers conclude, and not by a little.
#' Brewer & Pickle's 56-subject study over nine map series found **quantiles**
#' among the best methods for general choropleth reading, and natural breaks
#' (Jenks) below 70% as accurate -- the opposite of the common GIS default.
#' `style = "quantile"` is therefore the safe choice for a general audience.
#' Jenks earns its place on strongly clustered distributions, where quantiles
#' would split a natural group across two colours. Use [classify_compare()] to
#' see the difference on your own data before committing.
#'
#' @references
#' Brewer, C. A. & Pickle, L. (2002). Evaluation of methods for classifying
#' epidemiological data on choropleth maps in series. *Annals of the
#' Association of American Geographers* 92(4), 662-681.
#' \doi{10.1111/1467-8306.00310}
#'
#' Correll, M., Moritz, D. & Heer, J. (2018). Value-suppressing uncertainty
#' palettes. *Proceedings of the 2018 CHI Conference on Human Factors in
#' Computing Systems*, 1-11. \doi{10.1145/3173574.3174216}
#'
#' @seealso [classify_compare()], [coverage_map()], [projection_compare()],
#'   [map_provenance()], [dispute_policy()]
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
                      recenter = NULL,
                      na_style = c("grey", "hatched", "outline", "omit"),
                      footnote = NULL, classification_report = FALSE,
                      uncertainty = NULL, n_uncertainty = 3,
                      disputes = c("ignore", "mark"),
                      engine = c("ggplot2", "tmap")) {
  engine <- rlang::arg_match(engine)
  check_bool(borders, "borders")
  check_bool(classification_report, "classification_report")
  disputes <- rlang::arg_match(disputes)
  check_label_args(palette, title, legend, na_label)
  style <- rlang::arg_match(style)
  na_style <- rlang::arg_match(na_style)
  fill_q <- rlang::enquo(fill)
  fill_name <- quo_arg_name(fill_q, "fill")

  check_cols(data, fill_name)
  check_map_geometry(data)

  sf_mode <- is_sf(data)
  check_categorical_fill(style, data[[fill_name]], fill_name)

  if (identical(engine, "tmap")) {
    # This engine used ten of world_map()'s arguments and dropped the rest
    # without a word. `na_label`, `projection` and `recenter` are now passed
    # through; what is left is genuinely ggplot2-specific -- hatched and
    # outlined NA fills, the footnote caption, the classification report, the
    # VSUP uncertainty scale and the dispute overlay -- so it is named instead
    # of quietly not happening.
    ignored <- c(
      if (!identical(na_style, "grey")) "na_style",
      if (!is.null(footnote)) "footnote",
      if (isTRUE(classification_report)) "classification_report",
      if (!is.null(uncertainty)) "uncertainty",
      if (!identical(disputes, "ignore")) "disputes"
    )
    warn_engine_ignored(ignored, "tmap", 'engine = "ggplot2"')
    return(world_map_tmap(data, fill_name, style, n_bins, palette, title,
                          legend, na_label, borders, sf_mode,
                          projection, recenter))
  }

  # A panel drawn as one static map overplots each country's years on top of
  # each other and whichever row happens to come last wins -- silently, and the
  # caption still counts each country once, so nothing looks wrong.
  # attach_geometry() joins a panel deliberately (facet_map() and
  # animate_world() are built on it, and its own comment says so), which is
  # exactly why the guard belongs here, where a single map is what was asked
  # for. Keyed on `year` rather than duplicate iso3c: the bundled sf basemap
  # legitimately carries one country twice, and the polygon backend carries
  # every country once per vertex.
  if ("year" %in% names(data)) {
    yrs <- unique(stats::na.omit(sf_drop(data)$year))
    if (length(yrs) > 1L) {
      wdj_warn(c(
        "{.arg data} spans {length(yrs)} years and a single map can show one.",
        "x" = "Each country is drawn once per year, so the last row wins.",
        "i" = "Filter to one year, or use {.fn facet_map} or
               {.fn animate_world}, which are built for a panel."
      ), class = "countryatlas_panel")
    }
  }

  # Coverage is counted before anything is dropped, so `na_style = "omit"` still
  # reports honestly on what it removed.
  coverage <- na_coverage(data, fill_name)
  # Kept for the VSUP recount below, which has to run against the frame as it
  # arrived rather than whatever `na_style = "omit"` leaves behind.
  data_full <- data
  missing_rows <- is.na(data[[fill_name]])
  if (identical(na_style, "omit")) data <- data[!missing_rows, , drop = FALSE]

  # A value-suppressing uncertainty palette replaces the ordinary fill entirely:
  # colour becomes a function of value *and* uncertainty, so it cannot go
  # through the usual style/scale machinery.
  unc_q <- rlang::enquo(uncertainty)
  vsup <- NULL
  if (!rlang::quo_is_null(unc_q)) {
    unc_name <- quo_arg_name(unc_q, "uncertainty")
    check_cols(data, unc_name)
    check_numeric_col(data, unc_name)
    # A VSUP contracts a *value range*, so there has to be one. Falling through
    # to check_numeric_col() named the right column but gave nonsense advice --
    # "convert `continent` to numeric" -- for what is really a category error.
    if (!is.numeric(data[[fill_name]])) {
      wdj_abort(c(
        "{.arg uncertainty} needs a numeric {.arg fill}.",
        "x" = "{.field {fill_name}} is {.cls {class(data[[fill_name]])[1]}}.",
        "i" = "A value-suppressing palette works by narrowing the value range as
               uncertainty rises; a categorical fill has no range to narrow.",
        "*" = "Map the uncertainty separately, or use {.fn coverage_map}."
      ))
    }
    check_number(n_uncertainty, "n_uncertainty", lo = 2, hi = 6)
    n_uncertainty <- as.integer(n_uncertainty)
    # A VSUP needs both numbers, so a country with a value but no uncertainty
    # gets no colour -- and `coverage`, which counts missing *fill* values,
    # said it was shown anyway. On a frame whose uncertainty column is sparser
    # than its value column, `footnote = "auto"` therefore overstated coverage
    # by every country the uncertainty join had missed, which is precisely the
    # claim that footnote exists to keep honest.
    coverage <- na_coverage(
      data_full, fill_name,
      shown = !is.na(data_full[[fill_name]]) & is.finite(data_full[[unc_name]]))
    lost <- setdiff(coverage$missing_iso3c,
                    na_coverage(data_full, fill_name)$missing_iso3c)
    if (length(lost)) {
      wdj_warn(c(
        "{length(lost)} countr{?y/ies} ha{?s/ve} {.field {fill_name}} but no
         {.field {unc_name}}, so the palette has no colour to give:",
        "*" = "{.val {utils::head(lost, 8)}}",
        "i" = "A value-suppressing palette encodes both numbers at once, so a
               country missing either one is drawn as no-data."
      ))
    }
    vsup <- vsup_fill(data[[fill_name]], data[[unc_name]],
                      n_bins = as.integer(n_bins),
                      n_uncertainty = n_uncertainty)
    data[[".wdj_vsup"]] <- factor(
      vsup$label,
      levels = sprintf("v%d / u%d",
                       rep(seq_len(as.integer(n_bins)), times = n_uncertainty),
                       rep(seq_len(n_uncertainty), each = as.integer(n_bins))))
  }

  binned <- apply_binned_fill(data, fill_q, fill_name, style, n_bins)
  data <- binned$data
  fill_mapped <- if (is.null(vsup)) binned$fill else rlang::quo(.data[[".wdj_vsup"]])

  na_value <- switch(na_style, grey = "grey85", outline = "white", "grey85")
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

  p <- p + if (is.null(vsup)) {
    add_fill_scale(style, palette, n_bins, na_label, legend %||% fill_name,
                   na_value = na_value, breaks = attr(binned, "breaks"))
  } else {
    vsup_scale(vsup, as.integer(n_bins), n_uncertainty,
               legend %||% fill_name, quo_arg_name(unc_q, "uncertainty"))
  }
  p <- p + theme_world_map()

  if (identical(na_style, "hatched")) {
    p <- p + na_hatch_layer(data, fill_name, sf_mode, borders)
  }
  if (identical(disputes, "mark")) {
    p <- p + dispute_layer(data, sf_mode)
  }
  # Re-assert the coordinate system after those two. Both return
  # list(<layer>, <CoordSf>) -- geom_sf() and ggpattern::geom_sf_pattern() each
  # carry a default coord_sf(crs = NULL) -- and ggplot2's ggplot_add.Coord
  # replaces the plot's coord unconditionally. Added after wdj_coord_sf() they
  # therefore threw the requested projection away along with its latitude clip,
  # so `mercator + hatched` and `robinson + hatched` drew byte-identical maps.
  # The coord is not a layer, so re-adding it here does not disturb draw order.
  if (sf_mode && (identical(na_style, "hatched") ||
                  identical(disputes, "mark"))) {
    p <- p + wdj_coord_sf(projection, recenter)
  }
  if (!is.null(title)) p <- p + ggplot2::labs(title = title)

  cap <- resolve_footnote(footnote, coverage)
  cap <- paste(stats::na.omit(c(cap, dispute_note(disputes, data),
                                imputed_note(data))), collapse = " ")
  if (nzchar(cap)) p <- p + ggplot2::labs(caption = cap)

  # Provenance travels on the object, not in a print side effect, so it survives
  # being saved, faceted or handed to map_provenance() later.
  attr(p, "countryatlas_provenance") <- list(
    fill = fill_name, style = style, projection = if (sf_mode) projection else "coord_quickmap",
    backend = if (sf_mode) "sf" else "polygon", n_bins = n_bins,
    na_style = na_style, coverage = coverage,
    breaks = attr(binned, "breaks"),
    disputes = disputes, dispute_policy = dispute_policy(),
    uncertainty = if (is.null(vsup)) NA_character_ else quo_arg_name(unc_q, "uncertainty"),
    n_imputed = imputed_count(data)
  )
  if (isTRUE(classification_report)) {
    attr(p, "countryatlas_classification") <-
      classification_table(data, fill_name, style, n_bins, attr(binned, "breaks"))
  }
  p
}

# Countries present vs countries with a value, counted once per country rather
# than once per polygon vertex (the polygon backend repeats a country's value
# for every boundary point, so a naive count would report tens of thousands).
# The column that identifies one drawable unit, most specific first. These
# frames are de-duplicated before counting or computing breaks, because the
# polygon backend repeats a country's value down every vertex. Keying on iso3c
# was wrong for a *subnational* frame, which carries iso3c as well as a region
# code: every NUTS region of a country collapsed to one row, so a 280-region map
# reported "27 of 27", four blank regions inside a country whose first region
# had data were reported as zero missing, and -- worst -- the quantile breaks
# were computed from 27 values instead of 280.
wdj_unit_key <- function(nms) {
  intersect(c("nuts_id", "iso_3166_2", "iso3c", "group"), nms)
}

na_coverage <- function(data, fill_name, shown = NULL) {
  df <- tibble::as_tibble(sf_drop(data))
  # `shown` joins the frame before the de-duplication so it survives it: a
  # value-suppressing palette needs the uncertainty column too, and "did this
  # country get a colour" is then no longer the same question as "is its fill
  # value present".
  if (!is.null(shown)) df[[".wdj_shown"]] <- shown
  # A geometry row carrying no ISO code is not a country -- it is a fragment the
  # basemap has and the codelist does not. Counting it put a phantom in the
  # denominator and in n_missing, while missing_iso3c (which sorts, and so drops
  # NA) listed one fewer than n_missing claimed: the caption said "17 missing"
  # where provenance could name only 16.
  if ("iso3c" %in% names(df)) df <- df[!is.na(df$iso3c), , drop = FALSE]
  key <- wdj_unit_key(names(df))
  if (length(key)) df <- dplyr::distinct(df, .data[[key[1]]], .keep_all = TRUE)
  ok <- if (is.null(shown)) !is.na(df[[fill_name]]) else df[[".wdj_shown"]]
  list(n_total = length(ok), n_shown = sum(ok), n_missing = sum(!ok),
       missing_iso3c = if ("iso3c" %in% names(df)) sort(df$iso3c[!ok]) else character(0))
}

# A frame that already carries centroid_lon/centroid_lat -- the output of
# world_geometry("centroids"), or anything joined to it -- collided with the
# join below: dplyr suffixed both sides to .x/.y, and the aes() referring to
# `.data$centroid_lon` then found no such column, so bubble_map() and
# spike_map() failed outright on their own centroid table. The bundled columns
# are the authority here, so drop the incoming ones.
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
      pieces[[k]] <- rbind(g[start:i, , drop = FALSE], head_row)
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
  shown <- data$iso3c %in% drawn_iso & !is.na(data[[value_name]])
  lost <- sort(data$iso3c[!is.na(data[[value_name]]) & !data$iso3c %in% drawn_iso])
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

# Drop sf geometry for counting without requiring sf to be attached.
sf_drop <- function(x) if (is_sf(x)) sf::st_drop_geometry(x) else x

resolve_footnote <- function(footnote, coverage) {
  if (is.null(footnote)) return(NULL)
  if (!identical(footnote, "auto")) {
    check_string(footnote, "footnote")
    return(footnote)
  }
  n_total <- coverage$n_total
  # This lands on a published map, so it has to read as English at every size.
  # sprintf() alone produced "All 1 countries shown." for a single-country
  # frame and "All 0 countries shown." for an empty one.
  if (length(n_total) != 1L || is.na(n_total)) return(NULL)
  if (n_total < 1L) return("No countries to show.")
  noun <- countries_noun(n_total)
  if (!coverage$n_missing) {
    return(sprintf("All %d %s shown.", n_total, noun))
  }
  sprintf("%d of %d %s shown; %d missing.",
          coverage$n_shown, n_total, noun, coverage$n_missing)
}

# Diagonal hatching over the no-data countries. ggpattern is optional, so say
# plainly when the request cannot be honoured rather than silently drawing grey.
na_hatch_layer <- function(data, fill_name, sf_mode, borders) {
  if (!has_pkg("ggpattern")) {
    wdj_inform(
      c("i" = "Package {.pkg ggpattern} not installed; drawing missing data in grey
              instead of hatched."),
      .frequency = "once", .frequency_id = "world_map-no-ggpattern"
    )
    return(NULL)
  }
  nd <- data[is.na(data[[fill_name]]), , drop = FALSE]
  if (!nrow(nd)) return(NULL)
  common <- list(
    data = nd, fill = "grey93", pattern = "stripe",
    pattern_fill = "grey55", pattern_colour = NA, pattern_angle = 45,
    pattern_density = 0.08, pattern_spacing = 0.012, pattern_size = 0.2,
    colour = if (borders) "grey30" else NA, linewidth = 0.1,
    inherit.aes = FALSE
  )
  if (sf_mode) {
    do.call(ggpattern::geom_sf_pattern, common)
  } else {
    do.call(ggpattern::geom_polygon_pattern, c(
      list(mapping = ggplot2::aes(x = .data$long, y = .data$lat,
                                  group = .data$group)), common
    ))
  }
}

# One row per class: the interval, and how many countries fall in it.
classification_table <- function(data, fill_name, style, n_bins, breaks) {
  df <- tibble::as_tibble(sf_drop(data))
  key <- wdj_unit_key(names(df))
  if (length(key)) df <- dplyr::distinct(df, .data[[key[1]]], .keep_all = TRUE)
  vals <- df[[fill_name]]
  # With no breaks the fallback was as.factor(vals) -- one "class" per distinct
  # value. For a continuous scale that produced a 189-row report of n = 1, which
  # says nothing about the map and looks like it does. A continuous fill has no
  # classes; say so instead of inventing 189 of them.
  if (is.null(breaks) && is.numeric(vals)) {
    wdj_warn(c(
      "{.arg style = \"{style}\"} draws a continuous colourbar, which has no
       classes to report.",
      i = "Use {.code style = \"quantile\"}, {.code \"jenks\"} or
           {.code \"binned\"} for a classification report."
    ), class = "countryatlas_no_classes")
    return(NULL)
  }
  cls <- if (!is.null(breaks)) {
    cut(vals, breaks = breaks, include.lowest = TRUE, dig.lab = 4)
  } else {
    as.factor(vals)
  }
  tab <- as.data.frame(table(class = cls, useNA = "no"), stringsAsFactors = FALSE)
  tibble::tibble(
    method = style, class = tab$class, n = as.integer(tab$Freq),
    share = as.integer(tab$Freq) / max(1L, sum(tab$Freq))
  )
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
  if (!style %in% c("quantile", "jenks", "binned") || !is.numeric(vals)) {
    return(structure(list(data = data, fill = fill_q), breaks = NULL))
  }
  break_vals <- vals
  key <- wdj_unit_key(names(data))
  if (length(key)) {
    break_vals <- dplyr::distinct(tibble::as_tibble(data),
                                  .data[[key[1]]], .keep_all = TRUE)[[fill_name]]
  }
  br <- compute_breaks(break_vals, if (style == "binned") "equal" else style,
                       n_bins)
  # "binned" keeps the continuous colourbar -- it is the one style whose point
  # is a bar rather than discrete keys -- so it takes the breaks and not the
  # cut. The other two map a factor.
  if (style == "binned") {
    return(structure(list(data = data, fill = fill_q), breaks = br))
  }
  data[[".wdj_bin"]] <- cut(vals, breaks = br, include.lowest = TRUE,
                            dig.lab = 4)
  # The breaks ride along as an attribute so classification_report and
  # map_provenance() can name them without recomputing (and so risking a
  # different answer from a different de-duplication).
  structure(list(data = data, fill = rlang::quo(.data[[".wdj_bin"]])),
            breaks = br)
}

# Pick the fill scale from the *column*, for the verbs that take a free-form
# `fill` rather than a `style`. cartogram_map() and tile_map() both hard-wired
# scale_fill_viridis_c(), so a categorical fill -- which their `fill` argument
# documents no restriction on, and which check_numeric_col() only rejects for
# `weight` -- was accepted at the call and then died at *print* time with
# ggplot2's bare "Discrete value supplied to a continuous scale". world_map()
# has had check_categorical_fill() guarding exactly this since 2.0.0; these two
# verbs never got the equivalent.
auto_fill_scale <- function(vals, name, na_value = "grey85") {
  if (is.numeric(vals)) {
    ggplot2::scale_fill_viridis_c(name = name, na.value = na_value,
                                  labels = scales_format())
  } else {
    ggplot2::scale_fill_viridis_d(name = name, na.value = na_value,
                                  option = "turbo")
  }
}

# Choose an appropriate fill scale for the chosen style.
add_fill_scale <- function(style, palette, n_bins, na_label, legend,
                           na_value = "grey85", breaks = NULL) {
  # "binned" used to hand n_bins to ggplot2 as `n.breaks`, which is only a
  # suggestion: scales::extended_breaks() snaps to round numbers, so n_bins of
  # 5, 6 and 7 all drew five bins and 3 drew four. `n_bins` is documented as
  # "number of bins for binned/quantile/jenks", so it now means the same thing
  # in all three -- the caller passes explicit equal-interval boundaries.
  check_number(n_bins, "n_bins", lo = 2, hi = .Machine$integer.max)
  n_bins <- as.integer(n_bins)
  # scale_*_binned() reads `breaks` as the interior boundaries, so k of them
  # give k + 1 bins; compute_breaks() returns the outer edges too.
  inner <- if (!is.null(breaks) && length(breaks) > 2L) {
    breaks[-c(1L, length(breaks))]
  } else NULL
  na_val <- na_value
  switch(
    style,
    continuous = ggplot2::scale_fill_viridis_c(
      name = legend, na.value = na_val,
      option = palette %||% "viridis", labels = scales_format()
    ),
    binned = if (is.null(inner)) {
      ggplot2::scale_fill_viridis_b(
        name = legend, na.value = na_val, n.breaks = n_bins,
        option = palette %||% "viridis", labels = scales_format()
      )
    } else {
      ggplot2::scale_fill_viridis_b(
        name = legend, na.value = na_val, breaks = inner,
        option = palette %||% "viridis", labels = scales_format()
      )
    },
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
# Only the first element can label the single NA key; a NULL / empty / NA
# label means "leave the default formatter alone". (Guarding with anyNA()
# rather than is.na() so a length > 1 na_label can't error the condition.)
# Shared with the tmap engine, which used to ignore `na_label` entirely, so
# the two backends agree on what the argument means by construction.
na_label_value <- function(na_label) {
  if (is.null(na_label) || !length(na_label) || anyNA(na_label)) return(NULL)
  as.character(na_label)[[1]]
}

discrete_na_labels <- function(na_label) {
  na_label <- na_label_value(na_label)
  if (is.null(na_label)) {
    return(ggplot2::waiver())
  }
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
  backend <- rlang::arg_match(backend)
  size_q <- rlang::enquo(size)
  color_q <- rlang::enquo(color)
  if (!"iso3c" %in% names(data)) {
    wdj_abort("{.arg data} must contain an {.field iso3c} column.")
  }
  check_cols(data, c(
    quo_arg_name(size_q, "size"),
    if (!rlang::quo_is_null(color_q)) quo_arg_name(color_q, "color")
  ))
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
  data <- distinct_countries(tibble::as_tibble(data))

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
    # Basemap countries the caller has no value for carry an NA size, and
    # geom_sf() drops them at draw time with a bare "Removed 7 rows". They are
    # already the grey base map underneath; the coverage numbers below account
    # for them, so drop them here rather than emit a count with no names.
    size_nm <- quo_arg_name(size_q, "size")
    pts_sf <- pts_sf[!is.na(pts_sf[[size_nm]]), , drop = FALSE]
    aes_pt <- if (!rlang::quo_is_null(color_q)) {
      ggplot2::aes(size = !!size_q, color = !!color_q)
    } else {
      ggplot2::aes(size = !!size_q)
    }
    p_sf <- ggplot2::ggplot() +
      ggplot2::geom_sf(data = countries, fill = "grey92", color = "grey80",
                       linewidth = 0.1) +
      ggplot2::geom_sf(data = pts_sf, mapping = aes_pt, alpha = alpha) +
      ggplot2::scale_size_area(max_size = max_size) +
      wdj_coord_sf(projection) +
      theme_world_map()
    return(wdj_provenance(
      p_sf, data, quo_arg_name(size_q, "size"), "sf", projection,
      style = "proportional symbol",
      extra = list(coverage = centroid_coverage(
        data, quo_arg_name(size_q, "size"), countries$iso3c))))
  }

  # Polygon backend: base map and centroids are both in lon/lat degrees.
  data <- drop_centroid_cols(data)
  cent <- world_geometry("centroids", geometry = "polygon")
  pts <- dplyr::left_join(data, cent[, c("iso3c", "centroid_lon", "centroid_lat")],
                          by = "iso3c", na_matches = "never")
  aes_pt <- if (!rlang::quo_is_null(color_q)) {
    ggplot2::aes(.data$centroid_lon, .data$centroid_lat,
                 size = !!size_q, color = !!color_q)
  } else {
    ggplot2::aes(.data$centroid_lon, .data$centroid_lat, size = !!size_q)
  }
  cov <- centroid_coverage(data, quo_arg_name(size_q, "size"), pts$iso3c[
    !is.na(pts$centroid_lon) & !is.na(pts$centroid_lat)])
  # Drop them here rather than handing ggplot2 a point at (NA, NA): the warning
  # above says which countries and why, which "Removed 5 rows" does not.
  pts <- pts[!is.na(pts$centroid_lon) & !is.na(pts$centroid_lat), , drop = FALSE]
  p <- ggplot2::ggplot() +
    ggplot2::geom_polygon(
      data = world_geometry("countries", geometry = "polygon"),
      ggplot2::aes(.data$long, .data$lat, group = .data$group),
      fill = "grey92", color = "grey80", linewidth = 0.1
    ) +
    ggplot2::geom_point(data = pts, mapping = aes_pt, alpha = alpha) +
    ggplot2::scale_size_area(max_size = max_size) +
    ggplot2::coord_quickmap() +
    theme_world_map()
  wdj_provenance(p, data, quo_arg_name(size_q, "size"), "polygon",
                 "coord_quickmap", style = "proportional symbol",
                 extra = list(coverage = cov))
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
  # Without this, a non-numeric height reached the non-negative filter and the
  # abort blamed the *join* -- "No rows with a non-negative <col> joined to a
  # centroid" -- when the column simply was not a number.
  check_numeric_col(data, h_name)
  check_number(max_height, "max_height", lo = 0)
  check_number(width, "width", lo = 0)
  check_number(alpha, "alpha", lo = 0, hi = 1)
  data <- drop_centroid_cols(distinct_countries(tibble::as_tibble(data)))
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
  p <- ggplot2::ggplot() +
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
  wdj_provenance(p, data, h_name, "polygon", "coord_quickmap",
                 style = "spike",
                 extra = list(coverage = centroid_coverage(
                   data, h_name, pts$iso3c)))
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
  # classInt needs at least two distinct values per axis to cut `dim` classes
  # from. A constant column reached it as classIntervals(...)'s bare "single
  # unique value" -- a simpleError from a third-party package naming neither
  # the column nor the function, and offering nothing to do about it.
  for (nm in c(x_name, y_name)) {
    nd <- length(unique(stats::na.omit(data[[nm]])))
    # Fewer distinct values than classes and classInt cannot cut them: a
    # constant column arrived as its bare "single unique value", and two values
    # against dim = 3 as "n greater than number of different finite values",
    # both simpleErrors/warnings from a third-party package naming neither the
    # column nor the function. Exactly `dim` distinct values is legal -- each
    # becomes its own class, and classInt says so, which is worth hearing.
    if (nd < dim) {
      wdj_abort(c(
        "{.field {nm}} has {nd} distinct value{?s}, too few for {dim} classes.",
        "i" = "A bivariate map cuts each variable into {dim} classes, so each
               axis needs at least that many different values. Lower
               {.arg dim}, or use {.fn world_map}."
      ), class = "countryatlas_not_classifiable")
    }
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
  p <- ggplot2::ggplot() +
    ggplot2::geom_sf(data = bidata, ggplot2::aes(fill = .data$bi_class),
                     color = "grey30", linewidth = 0.1, show.legend = FALSE) +
    biscale::bi_scale_fill(pal = palette, dim = dim) +
    wdj_coord_sf(projection) +
    biscale::bi_theme()
  # A bivariate class needs both variables, so a country holding only one is
  # drawn as no-data. Coverage counted on x alone called it shown -- the same
  # overstatement the VSUP path made, in a different verb.
  cov <- na_coverage(data, x_name,
                     shown = !is.na(data[[x_name]]) & !is.na(data[[y_name]]))
  lost <- setdiff(cov$missing_iso3c, na_coverage(data, x_name)$missing_iso3c)
  if (length(lost)) {
    wdj_warn(c(
      "{length(lost)} countr{?y/ies} ha{?s/ve} {.field {x_name}} but no
       {.field {y_name}}, so {.fn bivariate_map} has no class to give:",
      "*" = "{.val {utils::head(lost, 8)}}",
      "i" = "A bivariate map classifies the two together; a country missing
             either one is drawn as no-data."
    ))
  }
  wdj_provenance(p, data, x_name, "sf", projection,
                 style = paste0("bivariate ", dim, "x", dim, " (", palette, ")"),
                 extra = list(coverage = cov))
}

#' Area-honest cartogram
#'
#' Resizes countries by `weight` (population, GDP, ...) via the optional
#' `cartogram` package, defeating the "big empty countries dominate the eye"
#' bias of world choropleths.
#'
#' @section Which algorithm:
#' `"contiguous"` (Dougenik) and `"dorling"`/`"noncontiguous"` come from
#' `cartogram`. `"flow"` comes from `cartogramR` and implements the
#' Gastner-Seguy-More flow-based method, which is both the current state of the
#' art and far faster than diffusion-based approaches -- prefer it for
#' contiguous cartograms when `cartogramR` is available.
#'
#' Cartograms fail quietly: an under-converged one looks plausible while still
#' misrepresenting the areas it exists to make honest. Pass a larger `itermax`
#' if the result still looks close to the true map.
#'
#' @references
#' Gastner, M. T., Seguy, V. & More, P. (2018). Fast flow-based algorithm for
#' creating density-equalizing map projections. *Proceedings of the National
#' Academy of Sciences* 115(10), E2156-E2164. \doi{10.1073/pnas.1712674115}
#'
#' @param data An `sf` map-ready frame.
#' @param weight The column to resize by (unquoted).
#' @param type `"contiguous"` (default), `"dorling"`, `"noncontiguous"` or
#'   `"flow"`. `"flow"` is the Gastner-Seguy-More flow-based algorithm from the
#'   optional `cartogramR` package -- the current state of the art for
#'   contiguous cartograms, and seconds rather than minutes where the
#'   diffusion-based `"contiguous"` method is slow.
#' @param fill Optional fill column (unquoted); defaults to `weight`.
#' @param projection Projection; an equal-area CRS is recommended. See
#'   [world_map()] for the projections available.
#' @param ... Passed to the underlying `cartogram::cartogram_*()` function
#'   (e.g. `itermax`, or `k` for `type = "dorling"` -- see [dorling_map()]), or
#'   to `cartogramR::cartogramR()` for `type = "flow"`.
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
                                                 "noncontiguous", "flow"),
                          fill = NULL, projection = "equal_earth", ...) {
  type <- rlang::arg_match(type)
  # "flow" is cartogramR's algorithm, not cartogram's, so gate on the package
  # the chosen type actually needs rather than demanding both.
  need_pkg(if (identical(type, "flow")) c("cartogramR", "sf") else c("cartogram", "sf"),
           sprintf('for cartogram_map(type = "%s")', type))
  if (!is_sf(data)) wdj_abort("{.fn cartogram_map} needs an sf frame.")
  w_name <- quo_arg_name(rlang::enquo(weight), "weight")
  fill_q <- rlang::enquo(fill)
  fill_name <- if (rlang::quo_is_null(fill_q)) w_name else quo_arg_name(fill_q, "fill")
  check_cols(data, unique(c(w_name, fill_name)))

  check_numeric_col(data, w_name)
  data <- sf::st_transform(data, wdj_crs(projection))
  # A cartogram can only size a country it has a positive weight for, so the
  # rest have to go. That was happening silently, and provenance was then
  # computed on the survivors -- so n_total shrank to match and the map claimed
  # near-complete coverage of a world it had quietly cut down. Measure coverage
  # against the frame as it arrived, and say what could not be sized.
  keep <- !is.na(data[[w_name]]) & data[[w_name]] > 0
  full_cov <- na_coverage(sf_drop(data), fill_name,
                          shown = keep & !is.na(data[[fill_name]]))
  lost <- setdiff(full_cov$missing_iso3c,
                  na_coverage(sf_drop(data), fill_name)$missing_iso3c)
  # Only when something survives: if nothing does, the abort below says it
  # better on its own, and warning first just doubles the message.
  if (length(lost) && any(keep)) {
    wdj_warn(c(
      "{length(lost)} countr{?y/ies} ha{?s/ve} no positive {.field {w_name}} and
       cannot be sized, so the cartogram leaves them off:",
      "*" = "{.val {utils::head(lost, 8)}}",
      "i" = "A cartogram's area *is* the weight; there is no area to give a
             country the weight is missing for."
    ))
  }
  data <- data[keep, ]
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
    noncontiguous = cartogram::cartogram_ncont(data, weight = w_name, ...),
    # cartogramR returns a classed object carrying the deformed geometry plus
    # its own diagnostics; as.sf() is its documented way back to a plain sf
    # frame, and the non-geometry columns have to be reattached because it keeps
    # only the weight.
    flow = {
      cg <- cartogramR::cartogramR(data, count = w_name, ...)
      out <- cartogramR::as.sf(cg)
      sf::st_geometry(data) <- sf::st_geometry(out)
      data
    }
  )
  p <- ggplot2::ggplot(carto) +
    ggplot2::geom_sf(ggplot2::aes(fill = .data[[fill_name]]),
                     color = "grey30", linewidth = 0.1) +
    auto_fill_scale(carto[[fill_name]], fill_name) +
    theme_world_map()
  # Remember what it was weighted by, so cartogram_diagnostics() can check the
  # convergence without being told again.
  attr(p, "countryatlas_cartogram_weight") <- w_name
  wdj_provenance(p, sf_drop(carto), fill_name, "sf", projection,
                 style = paste0("cartogram (", type, ")"),
                 extra = list(coverage = full_cov))
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
  warn_no_geometry_match(data$iso3c, grid$iso3c, "iso3c")
  # One row per country before the join. The grid has exactly one cell per
  # country, so a panel fanned it out -- 239 cells became 659 overlapping ones,
  # each country's tile drawn once per year with the last row winning, and
  # nothing said. The other one-cell-per-country verbs go through the same
  # helper; this one joined the grid directly and was missed.
  # Deduplicated once and reused below: calling distinct_countries() a second
  # time for the coverage would emit its panel warning twice for one call.
  one_per_country <- distinct_countries(tibble::as_tibble(data))
  # The grid supplies `row` and `col`, and those are common enough column names
  # that a caller's frame may carry its own. They collided in the join below:
  # dplyr suffixed both sides to `.x`/`.y`, and aes(.data$col, -.data$row) then
  # failed with ggplot2's "Problem while computing aesthetics" about a column
  # renamed out from under it. Same fix as drop_centroid_cols() before the
  # centroid joins -- the grid's own coordinates are what this verb draws. The
  # one case that cannot be resolved by dropping is a fill column of that name,
  # which would have to be both the value and a coordinate.
  clash <- intersect(names(one_per_country), c("row", "col"))
  if (fill_name %in% clash) {
    wdj_abort(c(
      "{.arg fill} cannot be {.field {fill_name}}: the tile grid uses that name
       for its own coordinates.",
      "i" = "Rename the column before drawing."
    ))
  }
  one_per_country <- one_per_country[
    , setdiff(names(one_per_country), clash), drop = FALSE]
  tiles <- dplyr::left_join(grid,
                            one_per_country,
                            by = "iso3c", na_matches = "never")
  p <- ggplot2::ggplot(tiles, ggplot2::aes(.data$col, -.data$row)) +
    ggplot2::geom_tile(ggplot2::aes(fill = !!fill_q), color = "white") +
    auto_fill_scale(tiles[[fill_name]], fill_name, na_value = "grey90") +
    ggplot2::coord_equal() +
    theme_world_map()
  if (isTRUE(label)) {
    p <- p + ggplot2::geom_text(ggplot2::aes(label = .data$iso3c), size = 2.5)
  }
  # The bundled grid does not cover every code -- Hong Kong and Macao have data
  # in the snapshot and no tile -- so counting the input's coded countries as
  # "shown" overstated the map by exactly the ones it could not place, the same
  # way bubble_map() and spike_map() did.
  tile_cov <- centroid_coverage(one_per_country, fill_name, grid$iso3c,
                                "tile in the bundled grid")
  wdj_provenance(p, data, fill_name, "tile-grid", "equal-area tile grid",
                 style = "categorical tile",
                 extra = list(coverage = tile_cov))
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
    if (!rlang::quo_is_null(weight_q)) quo_arg_name(weight_q, "weight")
  ))
  # `weight` drives linewidth and alpha, so the same "Discrete value supplied
  # to a continuous scale" applies -- at build time, not here, unless checked.
  if (!rlang::quo_is_null(weight_q)) {
    check_numeric_col(data, quo_arg_name(weight_q, "weight"))
  }
  # An arc needs at least two points; below that seq() errored on length.out.
  check_number(n, "n", lo = 2, hi = .Machine$integer.max)

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
      gc$weight <- d[[quo_arg_name(weight_q, "weight")]][i]
    }
    gc
  }))

  base <- ggplot2::ggplot() +
    ggplot2::geom_polygon(
      data = world_geometry("countries", geometry = "polygon"),
      ggplot2::aes(.data$long, .data$lat, group = .data$group),
      fill = "grey92", color = "grey80", linewidth = 0.1
    )
  if (is.null(arcs) || !nrow(arcs)) {
    return(wdj_provenance(base + ggplot2::coord_quickmap() + theme_world_map(),
                          data, NULL, "polygon", "coord_quickmap",
                          style = "great-circle flow (no arcs)"))
  }
  arcs <- split_antimeridian(arcs, arcs$.id)
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
    ggplot2::scale_linewidth(name = w_name, range = c(0.2, 2)) +
    ggplot2::scale_alpha(name = w_name) +
    ggplot2::coord_quickmap() +
    theme_world_map()
  wdj_provenance(p, data,
                 if (rlang::quo_is_null(weight_q)) NULL else quo_arg_name(weight_q, "weight"),
                 "polygon", "coord_quickmap", style = "great-circle flow")
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
  time_name <- quo_arg_name(rlang::enquo(time), "time")
  if (!time_name %in% names(data)) {
    wdj_abort("Time column {.val {time_name}} not found in {.arg data}.")
  }
  p <- without_panel_warning(
    world_map(data, !!fill_q, projection = projection, ...))
  if (has_pkg("gganimate")) {
    # The frame marker used to be written straight into `title`, which threw
    # away any title the caller passed through `...` to world_map(). Keep both:
    # the title stays put and the frame label moves to the subtitle.
    frame_lab <- "{current_frame}"
    p +
      gganimate::transition_manual(frames = .data[[time_name]]) +
      if (is.null(p$labels$title)) ggplot2::labs(title = frame_lab) else
        ggplot2::labs(subtitle = frame_lab)
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
#' @param engine `"plotly"` (default), `"ggiraph"`, `"leaflet"`, `"mapgl"` or
#'   `"ggsql"`. `"mapgl"` renders through MapLibre GL -- vector tiles, smooth
#'   zoom and a genuine interactive globe, which is what turns [globe_map()]
#'   from a static novelty into something you can turn. It needs an `sf` frame
#'   (database-side rendering to a Vega-Lite widget; needs an `sf` frame and
#'   `ggsql` >= 0.4.1, the version that added the `DRAW spatial` clause).
#'   `tooltip` is honoured by the `"ggiraph"` and `"leaflet"` engines (defaults
#'   to `fill` when omitted); `"plotly"`'s hover is controlled by `world_map()`
#'   aesthetics instead, and `"ggsql"` has no hover concept.
#' @param ... Passed to [world_map()] for the `"plotly"` engine, to
#'   [world_query()] for `"ggsql"`, and to [mapgl::maplibre()] for `"mapgl"`.
#'   The `"ggiraph"` and `"leaflet"` engines assemble their own map and take no
#'   further arguments; they warn rather than ignore what they are given.
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
                            engine = c("plotly", "ggiraph", "leaflet", "ggsql",
                                       "mapgl"),
                            ...) {
  engine <- rlang::arg_match(engine)
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
  if (identical(engine, "mapgl") && !is_sf(data)) {
    wdj_abort(c(
      '{.code engine = "mapgl"} needs an sf frame: MapLibre draws real geometry,
       not a polygon table.',
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

  if (engine == "mapgl") {
    need_pkg(c("mapgl", "sf"), 'for interactive_map(engine = "mapgl")')
    fill_name <- quo_arg_name(fill_q, "fill")
    check_cols(data, fill_name)
    # MapLibre wants lon/lat; the package's sf frames are projected by default.
    g <- quietly_sf(sf::st_transform(data, 4326L))
    tip <- if (rlang::quo_is_null(tooltip_q)) fill_name else quo_arg_name(tooltip_q, "tooltip")
    check_cols(g, tip)
    m <- mapgl::maplibre(bounds = g, ...)
    m <- mapgl::add_fill_layer(
      m, id = "countryatlas", source = g,
      fill_color = if (is.numeric(g[[fill_name]])) {
        mapgl::interpolate_palette(data = g, column = fill_name,
                                   method = "quantile", n = 5,
                                   palette = viridis_hex)$expression
      } else {
        mapgl::match_expr(column = fill_name,
                          values = sort(unique(as.character(g[[fill_name]]))),
                          stops = viridis_hex(
                            length(unique(stats::na.omit(g[[fill_name]])))))
      },
      fill_opacity = 0.85, fill_outline_color = "#33333366",
      tooltip = tip, hover_options = list(fill_opacity = 1)
    )
    return(m)
  }

  if (engine == "plotly") {
    p <- world_map(data, !!fill_q, ...)
    return(plotly::ggplotly(p))
  }
  if (engine == "ggiraph") {
    need_pkg("ggiraph")
    # `...` is documented as going to world_map() for this engine, but the
    # branch below assembles its own ggplot instead (see the comment there),
    # so the dots went nowhere: `style = "quantile"` returned the default
    # continuous fill and said nothing. Name them.
    warn_dots_unused(rlang::list2(...), "ggiraph", 'engine = "plotly"')
    # This branch assembles its own ggplot instead of calling world_map(), so it
    # needs the same check: without it, a country-level frame reached
    # geom_polygon_interactive() and failed at render time on `.data$long`,
    # while engine = "plotly" reported the problem properly.
    check_map_geometry(data)
    check_cols(data, c(
      quo_arg_name(fill_q, "fill"),
      if (!rlang::quo_is_null(tooltip_q)) quo_arg_name(tooltip_q, "tooltip")
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
  # This engine builds its own leaflet map, so `...` reaches nothing here
  # either -- and unlike the other four it was not documented at all.
  warn_dots_unused(rlang::list2(...), "leaflet", 'engine = "plotly"')
  check_cols(data, c(
    quo_arg_name(fill_q, "fill"),
    if (!rlang::quo_is_null(tooltip_q)) quo_arg_name(tooltip_q, "tooltip")
  ))
  if (!is_sf(data)) {
    # This branch gates on !is_sf, so `data` may be a *polygon* frame: reduced to
    # one row per country it still carries long/lat/group, which attach_geometry()
    # now (rightly) refuses. Strip them. (globe_map's polygon branch gates on the
    # columns themselves, so it needs no equivalent.)
    data <- attach_geometry(
      drop_map_geometry(
        distinct_countries(tibble::as_tibble(data))),
      geometry = "sf")
  }
  fill_name <- quo_arg_name(fill_q, "fill")
  tooltip_name <- if (rlang::quo_is_null(tooltip_q)) fill_name else quo_arg_name(tooltip_q, "tooltip")
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
#' @param data Optional layer data, as for any `ggplot2` geom: a frame (label
#'   only those countries -- the usual way to label a handful rather than all
#'   two hundred), or a function of the plot's data. Whatever you pass is
#'   reduced to one centroid per country before it is drawn. Defaults to the
#'   plot's own data.
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
#'
#'   # Labelling all 188 countries at once is unreadable, and ggrepel responds
#'   # by dropping nearly every label. Pass `data` to choose a subset ...
#'   world_map(mapdf, gdp_per_capita) +
#'     geom_country_labels(
#'       data = ~ dplyr::filter(.x, iso3c %in% c("USA", "BRA", "CHN", "IND", "ZAF"))
#'     )
#'
#'   # ... or zoom in, where there is room for every label.
#'   europe <- attach_geometry(
#'     dplyr::filter(snap, continent == "Europe"), geometry = "polygon")
#'   world_map(europe, gdp_per_capita) +
#'     geom_country_labels(size = 2.5) +
#'     coord_quickmap(xlim = c(-25, 45), ylim = c(34, 72))
#' }
#' }
geom_country_labels <- function(mapping = NULL, data = NULL, repel = TRUE,
                                flag = FALSE, size = 3, ...) {
  check_bool(repel, "repel")
  check_bool(flag, "flag")
  explicit <- !is.null(data)
  to_centroids <- function(d) {
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
      # Silently empty is right for the *plot's* data (a multi-layer plot may
      # hand this geom a frame it has nothing to say about), but not for a frame
      # the caller passed on purpose -- that used to reach ggplot2's "Column
      # `long` not found in `.data`" from inside the layer's aes, naming neither
      # the geom nor the missing piece.
      if (explicit) {
        wdj_abort(c(
          "{.arg data} must carry the polygon backend's
           {.field long}/{.field lat}/{.field iso3c} columns.",
          "x" = "Got a frame with {.field {paste(setdiff(c('long','lat','iso3c'), names(d)), collapse = ', ')}} missing.",
          "i" = 'Subset the map frame itself
                 ({.code geom_country_labels(data = subset(mapdf, iso3c %in% keep))}),
                 or pass a function of the plot data
                 ({.code geom_country_labels(data = ~ subset(.x, continent == "Europe"))}).'
        ))
      }
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
    # The centroid reduction used to return iso3c/long/lat/flag and nothing
    # else, so geom_country_labels(mapping = aes(colour = continent)) died on
    # "object 'continent' not found" -- the ordinary reason to pass a mapping at
    # all. Carry each country's other columns through (first row per country;
    # the polygon backend repeats them down every vertex).
    rest <- setdiff(names(d), c(names(out), "long", "lat", "group", "order"))
    if (length(rest)) {
      keep <- d[!duplicated(d$iso3c), c("iso3c", rest), drop = FALSE]
      out <- dplyr::left_join(out, keep, by = "iso3c", na_matches = "never")
    }
    out
  }
  # `data` used to be hard-wired to the centroid function while `...` was
  # documented as "passed to the underlying text geom" and forwarded to the very
  # same call -- so the ordinary ggplot2 idiom for labelling a *subset* of
  # countries, geom_country_labels(data = big_ones), died on R's "formal
  # argument "data" matched by multiple actual arguments". Take `data` as a real
  # argument and compose the centroid step onto whatever the caller supplied,
  # so a frame, a function or nothing all work and the centroid rule still runs.
  label_data <- if (is.null(data)) {
    to_centroids
  } else if (is.function(data) || rlang::is_formula(data)) {
    fn <- rlang::as_function(data)
    function(d) to_centroids(fn(d))
  } else {
    to_centroids(data)
  }

  # Build a self-contained mapping (don't inherit the plot's group/fill aes).
  lab <- if (isTRUE(flag)) ggplot2::aes(label = .data$flag) else
    ggplot2::aes(label = .data$iso3c)
  base_map <- ggplot2::aes(x = .data$long, y = .data$lat)
  # The caller's mapping *adds to* the defaults rather than replacing them.
  # modifyList(base_map, mapping) dropped `label` the moment any mapping was
  # supplied, so geom_country_labels(aes(colour = continent), flag = TRUE) drew
  # no labels at all and silently ignored `flag`.
  full_map <- utils::modifyList(utils::modifyList(base_map, lab),
                                mapping %||% ggplot2::aes())

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
  # `keep` is validated carefully just below; `x` was not. A non-spatial object
  # reached rmapshaper and leaked "no applicable method for 'ms_simplify'
  # applied to an object of class NULL" -- naming rmapshaper's generic rather
  # than the argument -- and the st_simplify() fallback failed differently
  # again, inside st_bbox(), so the message depended on which optional package
  # the caller happened to have.
  if (!is_sf(x) && !inherits(x, "sfc")) {
    wdj_abort(c(
      "{.arg x} must be an {.cls sf} frame or an {.cls sfc} geometry column.",
      "x" = "Got {.cls {class(x)[1]}}.",
      "i" = 'Attach geometry first: {.code attach_geometry(data, geometry = "sf")}.'
    ))
  }
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
#' @param interactive If `TRUE`, return a MapLibre WebGL globe you can spin and
#'   zoom instead of a static image. Needs `mapgl` and an `sf` frame; `lon` and
#'   `lat` become the initial camera position and the drawing arguments above do
#'   not apply.
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
                      title = NULL, legend = NULL, na_label = "No data",
                      interactive = FALSE) {
  check_bool(borders, "borders")
  check_bool(interactive, "interactive")
  if (isTRUE(interactive)) {
    # MapLibre renders a real WebGL globe you can spin with the mouse, which is
    # the thing the static orthographic projection and spin_globe()'s GIF are
    # both approximating. Everything else about this function is about drawing
    # one fixed viewpoint, so hand off rather than reimplement.
    #
    # Validated *here*, because arg_match() and check_label_args() sat below
    # this branch: an interactive globe accepted `style = "nonsense"` and a
    # length-3 `title` without a murmur.
    check_label_args(palette, title, legend, na_label)
    backend <- rlang::arg_match(backend)
    style <- rlang::arg_match(style)
    check_number(lon, "lon", lo = -360, hi = 360)
    check_number(lat, "lat", lo = -90, hi = 90)
    # And the ggplot2 styling arguments cannot travel to MapLibre, which
    # builds its own scale and legend. They were accepted and dropped.
    ignored <- c(
      if (!identical(backend, "sf")) "backend",
      if (!identical(style, "continuous")) "style",
      if (!is.null(palette)) "palette",
      if (!identical(n_bins, 5) && !identical(n_bins, 5L)) "n_bins",
      if (!isTRUE(borders)) "borders",
      if (!is.null(title)) "title",
      if (!is.null(legend)) "legend",
      if (!identical(na_label, "No data")) "na_label"
    )
    warn_engine_ignored(ignored, "mapgl", "interactive = FALSE")
    fill_q0 <- rlang::enquo(fill)
    if (!is_sf(data)) {
      wdj_abort(c(
        "{.code interactive = TRUE} needs an sf frame.",
        "i" = 'Build one with {.code world_data(..., geometry = "sf")} or
               {.fn attach_geometry}.'
      ))
    }
    m <- interactive_map(data, !!fill_q0, engine = "mapgl",
                         center = c(lon, lat), zoom = 1)
    return(mapgl::add_globe_control(m))
  }
  check_label_args(palette, title, legend, na_label)
  backend <- rlang::arg_match(backend)
  style <- rlang::arg_match(style)
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
        distinct_countries(tibble::as_tibble(data)),
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
      add_fill_scale(style, palette, n_bins, na_label, legend %||% fill_name,
                     breaks = attr(binned, "breaks")) +
      theme_world_map()
    if (!is.null(title)) p <- p + ggplot2::labs(title = title)
    return(wdj_provenance(p, data, fill_name, "polygon",
                          sprintf("orthographic (lon %s, lat %s)",
                                  fmt_num(lon), fmt_num(lat)),
                          style = style,
                          extra = list(n_bins = n_bins,
                                       breaks = attr(binned, "breaks"))))
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
    add_fill_scale(style, palette, n_bins, na_label, legend %||% fill_name,
                   breaks = attr(binned, "breaks")) +
    theme_world_map()
  if (!is.null(title)) p <- p + ggplot2::labs(title = title)
  wdj_provenance(p, data, fill_name, backend,
                 sprintf("orthographic (lon %s, lat %s)", fmt_num(lon), fmt_num(lat)),
                 style = style,
                 extra = list(n_bins = n_bins, breaks = attr(binned, "breaks")))
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
#' # Six frames rather than the default 60, so this stays quick enough to be
#' # checked: \dontrun{} meant the example was never executed by anything, and
#' # an example nothing runs is an example free to rot.
#' \donttest{
#' if (requireNamespace("maps", quietly = TRUE) &&
#'     requireNamespace("mapproj", quietly = TRUE) &&
#'     (requireNamespace("gifski", quietly = TRUE) ||
#'      requireNamespace("magick", quietly = TRUE))) {
#'   # No sf required on the polygon backend.
#'   gif <- spin_globe(world_snapshot$countries, continent,
#'                     backend = "polygon", style = "categorical",
#'                     n_frames = 6, width = 200, height = 200)
#'   file.exists(gif)   # written to a temporary file
#' }
#' }
spin_globe <- function(data, fill, lat = 20, n_frames = 60, fps = 15,
                       backend = c("polygon", "sf"), width = 480, height = 480,
                       file = NULL, ...) {
  backend <- rlang::arg_match(backend)
  fill_q <- rlang::enquo(fill)
  # Validate the arguments before gating on the animation packages: a bad
  # argument is the caller's bug and the message should not depend on which
  # optional packages happen to be installed. (globe_map() orders these the
  # same way.)
  check_number(n_frames, "n_frames", lo = 2, hi = .Machine$integer.max)
  check_number(fps, "fps", lo = 1)
  # `file` was the one this block missed, so a non-string path leaked base R's
  # "invalid 'path' argument" -- or, for a length-2 vector, "the condition has
  # length > 1" -- from deep inside the writer.
  if (!is.null(file)) check_string(file, "file")
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
  # Faceting by year resolves the panel, so the warning would be wrong.
  # Faceting a panel by anything else does not -- each continent panel still
  # stacks every year on top of itself -- so there it is exactly right.
  p <- if (identical(facet_name, "year")) {
    without_panel_warning(world_map(data, !!fill_q, ...))
  } else {
    world_map(data, !!fill_q, ...)
  }
  p + ggplot2::facet_wrap(ggplot2::vars(.data[[facet_name]]), ncol = ncol)
}

# How many cells in this frame were invented by interpolate_missing()? Read from
# the `*_imputed` flag columns it is required to leave behind.
imputed_count <- function(data) {
  flags <- grep("_imputed$", names(data), value = TRUE)
  flags <- flags[vapply(data[flags], is.logical, logical(1))]
  if (!length(flags)) return(0L)
  df <- tibble::as_tibble(sf_drop(data))
  key <- wdj_unit_key(names(df))
  if (length(key)) df <- dplyr::distinct(df, .data[[key[1]]], .keep_all = TRUE)
  sum(vapply(flags, function(f) sum(df[[f]], na.rm = TRUE), integer(1)))
}

# The caption fragment for imputed values. Not optional and not suppressible:
# interpolate_missing() promises the flag survives, and a map that silently
# draws invented numbers as data is the failure that promise exists to prevent.
imputed_note <- function(data) {
  n <- imputed_count(data)
  if (!n) return(NULL)
  sprintf("%d value%s interpolated.", n, if (n == 1L) "" else "s")
}

#' One square per N people
#'
#' A gridded (or "waffle") cartogram: the world redrawn as equal cells, each
#' worth a fixed quantity, allocated to countries in proportion to their value
#' and placed near where they belong. Where a Dorling cartogram preserves
#' position and a contiguous one preserves adjacency, this preserves
#' *countability* -- the reader can literally count the cells.
#'
#' @param data A country-level or map-ready frame with `iso3c`.
#' @param value The column to allocate cells by (unquoted).
#' @param cells Total number of cells to distribute (default `1000`). Each cell
#'   is then worth `sum(value) / cells`.
#' @param fill Optional fill column (unquoted); defaults to `value`.
#' @param cell_size Grid spacing in degrees (default `2.5`).
#'
#' @return A `ggplot` object. The per-country cell allocation is attached as the
#'   `"countryatlas_cells"` attribute -- every placeable country, including the
#'   ones that rounded to zero cells, so `share` sums to 1 and the rounding is
#'   fully visible.
#'
#' @section Rounding is the whole difficulty:
#' Allocating a whole number of cells to each country cannot be exact, so the
#' remainder has to go somewhere. This uses the largest-remainder method, which
#' guarantees the cell total is exactly `cells` and that no country with a
#' positive value gets zero cells while a smaller one gets one. The attached
#' table reports each country's exact share alongside its integer allocation so
#' the rounding is inspectable rather than hidden.
#'
#' @seealso [cartogram_map()], [dorling_map()], [tile_map()]
#' @export
#' @examples
#' \donttest{
#' snap <- countryatlas::world_snapshot$countries
#' gridded_cartogram(snap, population, cells = 400)
#' }
gridded_cartogram <- function(data, value, cells = 1000, fill = NULL,
                              cell_size = 2.5) {
  value_q <- rlang::enquo(value)
  val_name <- quo_arg_name(value_q, "value")
  fill_q <- rlang::enquo(fill)
  check_number(cells, "cells", lo = 1, hi = 1e6)
  check_number(cell_size, "cell_size", lo = 0.1, hi = 30)
  cells <- as.integer(cells)
  if (!"iso3c" %in% names(data)) {
    wdj_abort("{.arg data} must contain an {.field iso3c} column.")
  }
  check_cols(data, val_name)
  check_numeric_col(data, val_name)

  df <- distinct_countries(tibble::as_tibble(sf_drop(data)))
  df <- df[!is.na(df$iso3c), ]
  fill_name <- if (rlang::quo_is_null(fill_q)) val_name else quo_arg_name(fill_q, "fill")
  check_cols(df, fill_name)
  # Held back so coverage can be measured against the frame as it arrived. The
  # two filters below drop countries the grid cannot represent, and provenance
  # was computed on whatever survived them -- so n_total shrank to match and a
  # grid covering 94 of 215 countries reported "94 of 94".
  df_all <- df
  usable <- is.finite(df[[val_name]]) & df[[val_name]] > 0
  # As in cartogram_map(): when nothing is usable the abort below is the whole
  # story, so do not warn first.
  if (any(!usable) && any(usable)) {
    wdj_warn(c(
      "{sum(!usable)} countr{?y/ies} ha{?s/ve} no positive {.field {val_name}}
       and get no cells:",
      "*" = "{.val {utils::head(sort(df$iso3c[!usable]), 8)}}",
      "i" = "A gridded cartogram allocates cells in proportion to the value,
             so there is no share to give without one."
    ))
  }
  df <- df[usable, ]
  if (!nrow(df)) {
    wdj_abort(c("No country has a positive {.val {val_name}} to allocate cells by.",
                "i" = "Gridded cartograms need positive weights."))
  }

  # Attach centroids and drop the unplaceable countries *before* allocating.
  # Allocating first and filtering after leaked cells: a country with no bundled
  # centroid still won its share, then vanished with it, so `cells = 997` laid
  # out 996 and the caption's "1 cell = N people" quietly stopped being true.
  cent <- countryatlas::country_meta[, c("iso3c", "centroid_lon", "centroid_lat")]
  # drop_centroid_cols() first, as bubble_map() and spike_map() do before the
  # same join. country_meta carries `centroid_lon`/`centroid_lat`, so a caller
  # who joined it for capitals or area already has those columns -- dplyr then
  # suffixed both sides to `.x`/`.y`, `df$centroid_lon` became NULL, and the
  # filter below failed with vctrs' "Can't subset rows with
  # `is.na(df$centroid_lon) | ...`" rather than anything about countries.
  df <- drop_centroid_cols(df)
  df <- dplyr::left_join(df, cent, by = "iso3c", na_matches = "never")
  lost <- df[is.na(df$centroid_lon) | is.na(df$centroid_lat), ]
  df <- df[!is.na(df$centroid_lon) & !is.na(df$centroid_lat), ]
  if (!nrow(df)) wdj_abort("No country has both a positive weight and a bundled centroid.")
  if (nrow(lost)) {
    wdj_warn(c(
      "{nrow(lost)} countr{?y/ies} ha{?s/ve} no bundled centroid and cannot be
       placed on the grid.",
      "*" = "{.val {utils::head(sort(lost$iso3c), 8)}}",
      "i" = "Their weight is excluded, so the cells shown cover
             {.val {round(100 * sum(df[[val_name]]) / (sum(df[[val_name]]) + sum(lost[[val_name]])), 1)}}% of the total."
    ))
  }

  # Largest-remainder allocation: floor everybody, then hand the leftover cells
  # to the largest fractional parts. Exact total, and no country rounded to
  # nothing while a smaller one keeps a cell.
  df$.wdj_share <- df[[val_name]] / sum(df[[val_name]])
  exact <- df$.wdj_share * cells
  n <- floor(exact)
  left <- cells - sum(n)
  if (left > 0) {
    ord <- order(exact - n, decreasing = TRUE)
    n[ord[seq_len(left)]] <- n[ord[seq_len(left)]] + 1L
  }
  df$.wdj_cells <- as.integer(n)
  # Keep the zero-cell countries in the reported table and drop them only from
  # the drawing. Which countries rounded away is exactly what the table exists
  # to show, and excluding them made `share` sum to less than 1.
  drawn <- df[df$.wdj_cells > 0, ]
  if (!nrow(drawn)) {
    wdj_abort(c(
      "Every country rounded to zero cells.",
      # "there are 1 countries to place" is reachable: a single-country frame
      # whose only weight rounds away lands here.
      "i" = "Raise {.arg cells}: there {?is/are} {nrow(df)} countr{?y/ies} to
             place."
    ))
  }

  # Lay each country's cells out as a compact block on the grid, centred on its
  # centroid. Overlap between crowded neighbours is possible and preferable to
  # a global packing solve, which would move countries far from where they are.
  blocks <- lapply(seq_len(nrow(drawn)), function(i) {
    k <- drawn$.wdj_cells[i]
    w <- ceiling(sqrt(k))
    idx <- seq_len(k) - 1L
    tibble::tibble(
      iso3c = drawn$iso3c[i],
      x = drawn$centroid_lon[i] + ((idx %% w) - (w - 1) / 2) * cell_size,
      y = drawn$centroid_lat[i] - ((idx %/% w) - (ceiling(k / w) - 1) / 2) * cell_size,
      .wdj_fill = drawn[[fill_name]][i]
    )
  })
  grid <- dplyr::bind_rows(blocks)

  per_cell <- sum(df[[val_name]]) / cells
  p <- ggplot2::ggplot(grid, ggplot2::aes(.data$x, .data$y)) +
    ggplot2::geom_tile(ggplot2::aes(fill = .data$.wdj_fill),
                       width = cell_size * 0.9, height = cell_size * 0.9) +
    auto_fill_scale(grid$.wdj_fill, fill_name) +
    ggplot2::coord_quickmap() +
    ggplot2::labs(caption = sprintf("1 cell = %s %s", fmt_num(signif(per_cell, 3)),
                                    val_name)) +
    theme_world_map()
  # share travels in `df`, so it stays aligned with the rows that survived the
  # centroid filter. Indexing a separately-computed vector by match(x, x) -- the
  # identity permutation -- silently kept the wrong values, and the shares
  # summed to 0.69 rather than 1.
  attr(p, "countryatlas_cells") <- tibble::tibble(
    iso3c = df$iso3c, value = df[[val_name]], share = df$.wdj_share,
    cells = df$.wdj_cells
  )
  # `shown` is exactly the set that survived both filters, so the count matches
  # what the grid actually draws while the denominator stays the whole input.
  wdj_provenance(p, df_all, fill_name, "grid", "gridded cartogram",
                 style = paste0(cells, " cells"),
                 extra = list(coverage = na_coverage(
                   df_all, fill_name, shown = df_all$iso3c %in% df$iso3c)))
}

#' Did the cartogram actually converge?
#'
#' Cartograms fail quietly. An under-converged one looks entirely plausible
#' while still misrepresenting the areas it exists to make honest. This reports
#' the residual error per country, so the failure is visible.
#'
#' @param x A `ggplot` from [cartogram_map()] or [dorling_map()], or the `sf`
#'   frame the cartogram was computed from.
#' @param weight The weight column (unquoted). Required when `x` is a plain `sf`
#'   frame; read from the plot otherwise.
#'
#' @return A tibble of `iso3c`, `target_share` (the country's share of the
#'   weight), `actual_share` (its share of the cartogram's area) and
#'   `area_error` (the relative difference). The summary -- mean absolute error,
#'   worst country -- is attached as the `"countryatlas_cartogram"` attribute.
#'
#' @section What counts as converged:
#' A perfect cartogram has `area_error` of 0 everywhere. In practice a mean
#' absolute error under a few percent is good and under 10% is usually
#' acceptable; a systematically large error, or one concentrated in the small
#' countries, means the algorithm stopped early. Raise `itermax` and try again.
#'
#' @seealso [cartogram_map()], [dorling_map()], [gridded_cartogram()]
#' @export
#' @examples
#' \donttest{
#' if (requireNamespace("sf", quietly = TRUE) &&
#'     requireNamespace("cartogram", quietly = TRUE) &&
#'     requireNamespace("rnaturalearth", quietly = TRUE)) {
#'   sfd <- attach_geometry(countryatlas::world_snapshot$countries,
#'                          geometry = "sf")
#'   cg <- cartogram_map(sfd, population)
#'   cartogram_diagnostics(cg)
#' }
#' }
cartogram_diagnostics <- function(x, weight = NULL) {
  need_pkg("sf", "for cartogram_diagnostics()")
  weight_q <- rlang::enquo(weight)
  geom <- NULL
  w_name <- NULL
  if (inherits(x, "ggplot")) {
    geom <- x$data
    prov <- attr(x, "countryatlas_cartogram_weight")
    w_name <- if (!rlang::quo_is_null(weight_q)) quo_arg_name(weight_q, "weight") else prov
    if (is.null(w_name)) {
      wdj_abort(c(
        "Cannot tell which column the cartogram was weighted by.",
        "i" = "Pass it as {.arg weight}."
      ))
    }
  } else if (is_sf(x)) {
    geom <- x
    if (rlang::quo_is_null(weight_q)) {
      wdj_abort("{.arg weight} is required when {.arg x} is an sf frame.")
    }
    w_name <- quo_arg_name(weight_q, "weight")
  } else {
    wdj_abort(c(
      "{.arg x} must be a cartogram plot or an sf frame.",
      "x" = "Got {.cls {class(x)[1]}}."
    ))
  }
  if (!is_sf(geom)) {
    wdj_abort("The plot's data is not an sf frame; this is not a cartogram.")
  }
  check_cols(geom, w_name)
  # An invalid ring makes s2 refuse st_area() outright, and its message --
  # "Loop 0 is not valid: Edge 0 crosses edge 2" -- names neither the country
  # nor the package, so a caller with one broken polygon had nothing to go on.
  # country_borders() and get_world_sf() hit the same wall and drop to GEOS's
  # planar predicate; an *area* is what this function reports, though, so
  # silently switching engines would change the numbers. Name the rows instead.
  area <- tryCatch(as.numeric(quietly_sf(sf::st_area(geom))),
                   error = function(e) {
    bad <- tryCatch(which(!sf::st_is_valid(geom)), error = function(e2) integer())
    who <- if (length(bad) && "iso3c" %in% names(geom)) {
      utils::head(geom$iso3c[bad], 4)
    } else if (length(bad)) {
      paste0("row ", utils::head(bad, 4))
    } else NULL
    wdj_abort(c(
      "Could not measure the geometry in {.arg x}.",
      "x" = if (!is.null(who)) {
        "{length(bad)} geometr{?y/ies} {?is/are} invalid: {.val {who}}."
      } else "The geometry engine rejected it: {conditionMessage(e)}",
      "i" = "Repair it with {.code sf::st_make_valid()} first."
    ), class = "countryatlas_invalid_geometry")
  })
  w <- geom[[w_name]]
  ok <- is.finite(area) & is.finite(w) & w > 0
  out <- tibble::tibble(
    iso3c = if ("iso3c" %in% names(geom)) geom$iso3c else NA_character_,
    target_share = ifelse(ok, w / sum(w[ok]), NA_real_),
    actual_share = ifelse(ok, area / sum(area[ok]), NA_real_)
  )
  out$area_error <- (out$actual_share - out$target_share) / out$target_share
  out <- dplyr::arrange(out, dplyr::desc(abs(.data$area_error)))
  attr(out, "countryatlas_cartogram") <- tibble::tibble(
    n = sum(ok),
    mean_abs_error = mean(abs(out$area_error), na.rm = TRUE),
    max_abs_error = max(abs(out$area_error), na.rm = TRUE),
    worst = out$iso3c[1]
  )
  out
}

# Viridis as plain hex, for the renderers that want colours rather than a
# ggplot2 scale (mapgl, and anything else speaking a web palette).
viridis_hex <- function(n = 5) {
  grDevices::hcl.colors(max(2L, as.integer(n)), palette = "viridis")
}

# The tmap backend. Deliberately thin: tmap has its own mature legend and layout
# machinery, so the job here is to hand it the same curated frame and the same
# classification choice, not to reproduce ggplot2's output through it. The
# package stays ggplot2-native -- this is an alternative renderer for people
# already working in tmap, not a second first-class path.
# The scale constructors this engine uses are the tmap 4 API; tmap 3 configured
# scales through arguments on tm_polygons() and exports none of them.
# DESCRIPTION pins no version on any Suggests package, so need_pkg("tmap") is
# satisfied by *any* tmap -- and an older one then failed on R's own
# "'tm_scale_intervals' is not an exported object from 'namespace:tmap'", which
# names neither the cause nor the cure. Detect the capability rather than a
# version number, exactly as as_ggsql_source() does for duckdb's `shared_home`:
# the capability is the thing actually required, and it stays correct whichever
# release introduced it.
tmap_scale_api <- c("tm_scale_intervals", "tm_scale_continuous",
                    "tm_scale_categorical")

check_tmap_api <- function(have = getNamespaceExports("tmap"),
                           call = rlang::caller_env()) {
  missing_api <- setdiff(tmap_scale_api, have)
  if (!length(missing_api)) return(invisible(TRUE))
  wdj_abort(c(
    "The installed {.pkg tmap} is too old for {.code engine = \"tmap\"}.",
    "x" = "It does not export {.fn {missing_api}}.",
    "i" = "The scale constructors arrived in {.pkg tmap} 4. Upgrade it, or use
           {.code engine = \"ggplot2\"}."
  ), class = "countryatlas_old_tmap", call = call)
}

world_map_tmap <- function(data, fill_name, style, n_bins, palette, title,
                           legend, na_label, borders, sf_mode,
                           projection = "equal_earth", recenter = NULL) {
  need_pkg("tmap", 'for world_map(engine = "tmap")')
  check_tmap_api()
  if (!sf_mode) {
    wdj_abort(c(
      '{.code engine = "tmap"} needs an sf frame.',
      "i" = 'tmap draws sf geometry; build one with
             {.code attach_geometry(data, geometry = "sf")}.',
      "*" = 'The polygon backend is ggplot2-only.'
    ))
  }
  # tm_scale_intervals() is the *interval* scale, and "cont"/"cat" are not
  # interval styles -- they name different constructors. Passing them through
  # meant the default style could not draw at all ('Invalid style. Style should
  # be one of "fixed", "sd", "equal", "pretty", ...') and a categorical fill
  # warned that an interval scale was being applied to non-numeric data. Each
  # style now reaches the constructor tmap actually has for it.
  # `na_label` arrived here and went nowhere: the ggplot path renames the NA
  # key through discrete_na_labels(), and every tmap scale takes `label.na`,
  # so a caller who set it just got tmap's own default with no sign that their
  # label had been dropped. Omit the argument entirely when the caller meant
  # "leave the default alone", so tmap's own formatting still applies.
  na_lab <- na_label_value(na_label)
  tm_scale <- function(f, ...) {
    args <- list(...)
    if (!is.null(na_lab)) args$label.na <- na_lab
    do.call(f, args)
  }
  fill_scale <- switch(
    style,
    continuous = tm_scale(tmap::tm_scale_continuous,
                          values = palette %||% "viridis"),
    categorical = tm_scale(tmap::tm_scale_categorical,
                           values = palette %||% "turbo"),
    tm_scale(tmap::tm_scale_intervals,
      style = switch(style, binned = "pretty", quantile = "quantile",
                     jenks = "jenks"),
      n = n_bins, values = palette %||% "viridis")
  )
  # `projection` and `recenter` were dropped here: this engine drew in the
  # frame's own CRS while world_map() documents the argument -- and the
  # default, Equal Earth, went unhonoured just as silently as an explicit
  # request. wdj_crs() resolves both and validates the name, and tm_shape()
  # takes the proj4 string it returns.
  tmap::tm_shape(data, crs = wdj_crs(projection, recenter)) +
    tmap::tm_polygons(
      fill = fill_name,
      fill.scale = fill_scale,
      fill.legend = tmap::tm_legend(title = legend %||% fill_name),
      col = if (borders) "grey30" else NULL,
      lwd = 0.2
    ) +
    (if (is.null(title)) tmap::tm_layout() else tmap::tm_title(title))
}
