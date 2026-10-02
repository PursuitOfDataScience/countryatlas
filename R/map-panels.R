# Maps: small multiples and animation -----------------------------------------
#
# facet_map() and animate_world() split one choropleth by a column, and carry
# the notes that have to appear on every panel (imputed values).

# facet_map(facet = year) and animate_world() resolve a panel rather than
# overplotting it, so world_map()'s panel warning is noise on their way through.
# Muffled by class, not suppressWarnings(): any *other* warning the call raises
# still has to reach the caller.
without_panel_warning <- function(expr) {
  withCallingHandlers(
    expr,
    countryatlas_panel = function(w) invokeRestart("muffleWarning"))
}

# Draw the countries that have no time value in every period.
#
# attach_geometry() returns the whole basemap, and a country the data does not
# cover carries NA in every data column -- its `year` included. A static map
# draws it in na.value, which is the point of returning it. Split by time, it
# belonged to no period: animate_world() drew it in no frame at all, so the
# countries with no data vanished rather than showing grey (gganimate warned
# "NAs introduced by coercion" twice while dropping them), and
# facet_map(facet = year) gave them a panel of their own, labelled NA. Copy
# those rows into every period present. Coverage is counted once per country,
# so the copies do not change it.
spread_undated <- function(data, col) {
  t <- data[[col]]
  undated <- is.na(t)
  periods <- unique(t[!undated])
  if (!any(undated) || !length(periods)) return(data)
  add <- data[undated, , drop = FALSE]
  copies <- lapply(seq_along(periods), function(i) {
    a <- add
    a[[col]] <- rep(periods[i], nrow(a))
    a
  })
  parts <- c(list(data[!undated, , drop = FALSE]), copies)
  if (is_sf(data)) do.call(rbind, parts) else dplyr::bind_rows(parts)
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
#' @param projection Projection; see [world_map()] for the projections
#'   available.
#' @param breaks_by `"pooled"` (default) classifies every panel together, with
#'   one set of breaks, so the same colour means the same value in every panel
#'   and the panels can be compared. `"panel"` classifies each panel on its own
#'   values -- each country's class within its own year -- and the legend says
#'   so; colours are then comparable as ranks, not as values.
#' @param ... Passed to [world_map()].
#'
#' @section Backend:
#' Either backend, as [world_map()]: the frame decides, and both draw in
#' `projection` (Equal Earth by default).
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
                          breaks_by = c("pooled", "panel"), ...) {
  breaks_by <- rlang::arg_match(breaks_by)
  fill_q <- rlang::enquo(fill)
  time_name <- quo_arg_name(rlang::enquo(time), "time")
  if (!time_name %in% names(data)) {
    wdj_abort("Time column {.val {time_name}} not found in {.arg data}.")
  }
  data <- spread_undated(data, time_name)
  p <- if (identical(breaks_by, "panel")) {
    panel_classes_map(data, quo_arg_name(fill_q, "fill"), time_name,
                      projection = projection, ...)
  } else {
    without_panel_warning(
      world_map(data, !!fill_q, projection = projection, ...))
  }
  if (has_pkg("gganimate")) {
    # The frame marker used to be written straight into `title`, which threw
    # away any title the caller passed through `...` to world_map(). Keep both:
    # the title stays put and the frame label moves to the subtitle.
    frame_lab <- "{current_frame}"
    p +
      gganimate::transition_manual(frames = .data[[time_name]]) +
      if (is.null(gg_title(p))) ggplot2::labs(title = frame_lab) else
        ggplot2::labs(subtitle = frame_lab)
  } else {
    wdj_inform(c("i" = "Package {.pkg gganimate} not installed; faceting by {.val {time_name}} instead."))
    p + ggplot2::facet_wrap(stats::as.formula(paste0("~", time_name)))
  }
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
#' @param breaks_by `"pooled"` (default) classifies every panel together, with
#'   one set of breaks, so the same colour means the same value in every panel
#'   and the panels can be compared. `"panel"` classifies each panel on its own
#'   values -- each country's class within its own year -- and the legend says
#'   so; colours are then comparable as ranks, not as values.
#' @param ... Passed to [world_map()] (e.g. `style`, `projection`).
#'
#' @section Backend:
#' Either backend, as [world_map()]: the frame decides, and both draw in
#' `projection` (Equal Earth by default).
#'
#' @return A faceted `ggplot` object.
#' @export
#' @examples
#' \donttest{
#' snap <- countryatlas::world_snapshot$countries
#' mapdf <- attach_geometry(snap, geometry = "polygon")
#' facet_map(mapdf, gdp_per_capita, continent, style = "quantile")
#' }
facet_map <- function(data, fill, facet, ncol = NULL,
                      breaks_by = c("pooled", "panel"), ...) {
  breaks_by <- rlang::arg_match(breaks_by)
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
  if (identical(facet_name, "year")) {
    # The countries with no data at all go into every year's panel rather than
    # a panel labelled NA: see spread_undated(). Faceting by anything else
    # keeps ggplot2's own NA panel, which there is a real group.
    data <- spread_undated(data, "year")
  }
  p <- if (identical(breaks_by, "panel")) {
    panel_classes_map(data, quo_arg_name(fill_q, "fill"), facet_name, ...)
  } else if (identical(facet_name, "year")) {
    without_panel_warning(world_map(data, !!fill_q, ...))
  } else {
    world_map(data, !!fill_q, ...)
  }
  p + ggplot2::facet_wrap(ggplot2::vars(.data[[facet_name]]), ncol = ncol)
}

# breaks_by = "panel": each panel classified on its own values. The fill
# becomes the class index within the panel, "1 (lowest)" to "k (highest)", so
# one legend can describe every panel, and it says the classes are per panel.
panel_classes_map <- function(data, fill_name, panel, ..., call = rlang::caller_env()) {
  dots <- list(...)
  style <- dots$style %||% "quantile"
  if (!is.null(dots$breaks) || !style %in% setdiff(CLASSED_STYLES, "fixed")) {
    wdj_abort(c(
      '{.code breaks_by = "panel"} classifies each panel, so it needs a style
       that computes classes.',
      "x" = if (!is.null(dots$breaks)) "Fixed {.arg breaks} are the same in every panel."
            else 'Got {.code style = "{style}"}.',
      "i" = 'Use {.code style = "quantile"} (the default), {.val jenks},
             {.val fisher}, {.val headtails} or {.val sd}, or
             {.code breaks_by = "pooled"}.'
    ), call = call)
  }
  check_cols(data, fill_name)
  check_numeric_col(data, fill_name)
  n_bins <- dots$n_bins %||% 5
  key <- wdj_unit_key(names(data))
  vals <- data[[fill_name]]
  cls <- rep(NA_integer_, length(vals))
  pnl <- as.character(data[[panel]])
  for (lv in unique(pnl[!is.na(pnl)])) {
    rows <- which(pnl %in% lv)
    v <- vals[rows]
    u <- if (length(key)) {
      v[!duplicated(data.frame(k = data[[key[1]]][rows], v = v))]
    } else v
    br <- compute_breaks(u, style, n_bins)
    cls[rows] <- as.integer(cut(v, br, include.lowest = TRUE))
  }
  k <- max(c(cls, 1L), na.rm = TRUE)
  lab <- paste0(seq_len(k), ifelse(seq_len(k) == 1L, " (lowest)",
                                   ifelse(seq_len(k) == k, " (highest)", "")))
  data[[".wdj_panel_class"]] <- factor(lab[cls], levels = lab)
  dots$style <- "categorical"
  dots$n_bins <- NULL
  dots$palette <- dots$palette %||% "viridis"
  dots$legend <- dots$legend %||% paste0(fill_name, "\n(", style, " classes,\neach panel)")
  sym <- rlang::sym(".wdj_panel_class")
  p <- without_panel_warning(rlang::inject(world_map(data, !!sym, !!!dots)))
  prov <- attr(p, "countryatlas_provenance")
  prov$style <- paste0(style, " (per panel)")
  prov$breaks_by <- "panel"
  attr(p, "countryatlas_provenance") <- prov
  restate_provenance(p, data, fill_name)
}

# How many cells in this frame were invented by interpolate_missing()? Read from
# the `*_imputed` flag columns it is required to leave behind.
imputed_count <- function(data) {
  flags <- grep("_imputed$", names(data), value = TRUE)
  flags <- flags[vapply(data[flags], is.logical, logical(1))]
  if (!length(flags)) return(0L)
  df <- tibble::as_tibble(sf_drop(data))
  key <- wdj_unit_key(names(df))
  if (!length(key)) {
    return(sum(vapply(flags, function(f) sum(df[[f]], na.rm = TRUE), integer(1))))
  }
  # Counted once per country, because a map draws one polygon per country. But
  # "imputed in any row for this country" rather than distinct()'s first row:
  # identical on the map-ready cross-section this is documented for, and honest
  # on a panel, where the first row is an arbitrary year -- a value
  # interpolated in any other year was reported as nothing imputed at all.
  unit <- df[[key[1]]]
  sum(vapply(flags, function(f) {
    v <- df[[f]]
    v[is.na(v)] <- FALSE
    sum(vapply(split(v, unit), any, logical(1)))
  }, integer(1)))
}

# The caption fragment for imputed values. Not optional and not suppressible:
# interpolate_missing() promises the flag survives, and a map that silently
# draws invented numbers as data is the failure that promise exists to prevent.
imputed_note <- function(data) {
  n <- imputed_count(data)
  if (!n) return(NULL)
  sprintf("%d value%s interpolated.", n, if (n == 1L) "" else "s")
}
