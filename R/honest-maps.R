# Honesty verbs -----------------------------------------------------------------
# The package's description promises "honest maps". Equal-area projections were
# the only part of that claim the code actually delivered. These verbs cover the
# rest of what the cartographic literature means by it: say which classification
# you chose and what it did (classify_compare), show where the data is not
# (coverage_map), and equalise a rate's visual weight by its denominator instead
# of letting the smallest denominators shout loudest (value_by_alpha_map).

#' Map the data availability itself
#'
#' A choropleth of *whether* a value is present, rather than what it is. The
#' companion to [audit_coverage()], which reports the same thing as a table: a
#' world map with a large well-covered region and a systematically empty one is
#' telling you something about the indicator that the headline map hides behind
#' a uniform grey.
#'
#' @param data A map-ready frame (polygon or `sf`).
#' @param value The column whose availability to map (unquoted).
#' @param by Optional grouping column for a panel: with a `year` column, use
#'   `by = year` to see coverage change over time.
#' @param title Optional plot title (defaults to a generated one).
#' @param ... Passed to [world_map()].
#'
#' @return A `ggplot` object.
#' @seealso [audit_coverage()], [world_map()]
#' @export
#' @examples
#' \donttest{
#' snap <- countryatlas::world_snapshot$countries
#' if (requireNamespace("maps", quietly = TRUE)) {
#'   attach_geometry(snap, geometry = "polygon") |>
#'     coverage_map(gdp_per_capita)
#' }
#' }
coverage_map <- function(data, value, by = NULL, title = NULL, ...) {
  value_q <- rlang::enquo(value)
  value_name <- quo_arg_name(value_q, "value")
  by_q <- rlang::enquo(by)
  check_cols(data, value_name)
  check_map_geometry(data)
  if (!is.null(title)) check_string(title, "title")

  cov <- na_coverage(data, value_name)
  data[[".wdj_available"]] <- factor(
    ifelse(is.na(data[[value_name]]), "Missing", "Reported"),
    levels = c("Reported", "Missing")
  )
  avail_sym <- rlang::sym(".wdj_available")
  # Two colours, not viridis: this is a two-level presence/absence variable and
  # a sequential ramp would invite reading it as a quantity. Replacing
  # world_map()'s scale is the point, so suppress ggplot2's note about it.
  p <- suppressMessages(
    world_map(data, !!avail_sym, style = "categorical",
              legend = value_name, ...) +
      ggplot2::scale_fill_manual(
        name = value_name,
        values = c(Reported = "#2166AC", Missing = "#F4A582"),
        na.value = "grey85", drop = FALSE
      ) +
      ggplot2::labs(
        title = title %||% paste0("Coverage of ", value_name),
        caption = sprintf("%d of %d %s report a value; %d missing.",
                          cov$n_shown, cov$n_total,
                          countries_noun(cov$n_total), cov$n_missing)
      )
  )
  if (!rlang::quo_is_null(by_q)) {
    by_name <- quo_arg_name(by_q, "by")
    check_cols(data, by_name)
    p <- p + ggplot2::facet_wrap(ggplot2::vars(.data[[by_name]]))
  }
  p
}

#' The same map under several classifications
#'
#' Small multiples of one choropleth, drawn once per classification method, plus
#' the break table and the count of countries in each class. The point is that
#' the choice is consequential and usually unexamined: Brewer & Pickle (2002)
#' found quantiles among the best methods for general choropleth reading and
#' natural breaks (Jenks) below 70% as accurate, which is the reverse of the
#' common GIS default.
#'
#' @param data A map-ready frame (polygon or `sf`).
#' @param value The value column (unquoted).
#' @param methods Classification styles to compare. Any of `"quantile"`,
#'   `"jenks"`, `"equal"`, `"pretty"` and `"sd"`. `"jenks"` needs the optional
#'   `classInt`; without it, it falls back to quantile breaks with a warning.
#' @param n Number of classes (default `5`).
#' @param ncol Number of facet columns.
#' @param ... Passed to [world_map()].
#'
#' @return A faceted `ggplot` object, with the per-method break and class-count
#'   table attached as the `"countryatlas_classification"` attribute (and
#'   readable with [map_provenance()]).
#'
#' @references
#' Brewer, C. A. & Pickle, L. (2002). Evaluation of methods for classifying
#' epidemiological data on choropleth maps in series. *Annals of the
#' Association of American Geographers* 92(4), 662-681.
#' \doi{10.1111/1467-8306.00310}
#'
#' @seealso [world_map()], [map_provenance()]
#' @export
#' @examples
#' \donttest{
#' snap <- countryatlas::world_snapshot$countries
#' if (requireNamespace("maps", quietly = TRUE)) {
#'   cmp <- attach_geometry(snap, geometry = "polygon") |>
#'     classify_compare(gdp_per_capita)
#'   attr(cmp, "countryatlas_classification")
#' }
#' }
classify_compare <- function(data, value,
                             methods = c("quantile", "jenks", "equal", "pretty"),
                             n = 5, ncol = NULL, ...) {
  value_q <- rlang::enquo(value)
  value_name <- quo_arg_name(value_q, "value")
  check_cols(data, value_name)
  check_numeric_col(data, value_name)
  check_map_geometry(data)
  check_number(n, "n", lo = 2, hi = .Machine$integer.max)
  n <- as.integer(n)
  known <- c("quantile", "jenks", "equal", "pretty", "sd")
  bad <- setdiff(methods, known)
  if (length(bad)) {
    wdj_abort(c("Unknown classification method{?s} {.val {bad}}.",
                "i" = "Available: {.val {known}}."))
  }
  if (!length(methods)) wdj_abort("{.arg methods} must name at least one method.")

  # Break on one value per country, for the same reason world_map() does: on the
  # polygon backend a country contributes one row per boundary vertex, so raw
  # quantiles would weight each country by the complexity of its coastline.
  df <- tibble::as_tibble(sf_drop(data))
  key <- wdj_unit_key(names(df))
  one <- if (length(key)) dplyr::distinct(df, .data[[key[1]]], .keep_all = TRUE) else df
  vals <- one[[value_name]]

  # Map the class *index*, not the interval label. Labels differ between
  # methods, so a shared discrete scale would pool all of them and hand each
  # panel a different slice of the palette -- quantile blue, Jenks green, equal
  # yellow -- which makes four views of one variable look like four variables.
  # Indexing gives every panel the same low-to-high ramp, so the eye compares
  # what actually differs: which countries land in which class. The interval
  # values are not lost; they are in the attached report.
  # Compute every method's breaks first: "pretty" in particular does not
  # promise exactly `n` classes, and factors bound together with different
  # level sets lose rows to "invalid factor level, NA generated". One level set,
  # sized to the most generous method, keeps the panels comparable and intact.
  all_breaks <- lapply(methods, function(m) classify_breaks(vals, m, n))
  n_class <- max(vapply(all_breaks, function(b) length(b) - 1L, integer(1)))
  panels <- lapply(seq_along(methods), function(i) {
    br <- all_breaks[[i]]
    d <- data
    idx <- as.integer(cut(d[[value_name]], breaks = br, include.lowest = TRUE))
    d[[".wdj_class"]] <- factor(idx, levels = seq_len(n_class))
    d$.wdj_method <- factor(methods[i], levels = methods)
    list(data = d, breaks = br)
  })
  combined <- do.call(rbind, lapply(panels, `[[`, "data"))

  report <- do.call(rbind, lapply(seq_along(methods), function(i) {
    br <- all_breaks[[i]]
    cls <- cut(vals, breaks = br, include.lowest = TRUE, dig.lab = 4)
    tab <- table(cls)
    tibble::tibble(method = methods[i], class = names(tab), n = as.integer(tab),
                   share = as.integer(tab) / max(1L, sum(tab)))
  }))

  class_sym <- rlang::sym(".wdj_class")
  p <- suppressMessages(
    world_map(combined, !!class_sym, style = "categorical",
              legend = paste0(value_name, "\nclass"), ...) +
      ggplot2::scale_fill_viridis_d(name = paste0(value_name, "\nclass"),
                                    na.value = "grey85", drop = FALSE) +
      ggplot2::facet_wrap(ggplot2::vars(.data$.wdj_method), ncol = ncol)
  )
  attr(p, "countryatlas_classification") <- report
  p
}

# Breaks for classify_compare()'s methods. quantile/jenks reuse the package's
# own compute_breaks() so the comparison matches what world_map() would draw.
classify_breaks <- function(x, method, n) {
  x <- x[is.finite(x)]
  if (length(unique(x)) < 2L) return(compute_breaks(x, "quantile", n))
  switch(
    method,
    quantile = compute_breaks(x, "quantile", n),
    jenks    = compute_breaks(x, "jenks", n),
    equal    = seq(min(x), max(x), length.out = n + 1L),
    pretty   = unique(pretty(x, n = n)),
    sd       = {
      m <- mean(x); s <- stats::sd(x)
      br <- m + s * seq(-floor(n / 2), ceiling(n / 2))
      unique(sort(c(min(x), br[br > min(x) & br < max(x)], max(x))))
    }
  )
}

#' Value-by-alpha: equalise a rate by its denominator
#'
#' A choropleth where colour carries the value and **opacity** carries an
#' equalising variable (usually population), over a neutral background. It is
#' the answer to the small-number problem -- a rate computed over eleven
#' thousand people shouts as loudly as one computed over a billion -- and unlike
#' a cartogram it solves it **without distorting geometry**, which is the main
#' objection to cartograms. Roth, Woodruff & Johnson (2010) introduced it for
#' exactly this purpose.
#'
#' @param data A map-ready frame (polygon or `sf`).
#' @param value The value column, carried by colour (unquoted).
#' @param equalize The equalising column, carried by opacity (unquoted) --
#'   population, total counts, or whatever denominator the rate was built on.
#' @param style Classification for the colour channel (as [world_map()]).
#' @param palette Optional viridis palette name.
#' @param n_bins Number of colour bins for the binned styles.
#' @param alpha_range Minimum and maximum opacity (default `c(0.15, 1)`).
#' @param transform Transform applied to `equalize` before it is mapped to
#'   opacity: `"rank"` (default, robust to the extreme skew of population),
#'   `"log10"` or `"identity"`.
#' @param background Colour behind the countries, which shows through where
#'   opacity is low (default a dark neutral).
#' @param title,legend Optional plot title and legend title.
#' @param projection Projection for the `sf` backend.
#'
#' @return A `ggplot` object.
#'
#' @references
#' Roth, R. E., Woodruff, A. W. & Johnson, Z. F. (2010). Value-by-alpha maps: an
#' alternative technique to the cartogram. *The Cartographic Journal* 47(2),
#' 130-140. \doi{10.1179/000870409X12488753453372}
#'
#' @seealso [cartogram_map()] and [dorling_map()] (the geometry-distorting
#'   answers to the same problem), [world_map()]
#' @export
#' @examples
#' \donttest{
#' snap <- countryatlas::world_snapshot$countries
#' if (requireNamespace("maps", quietly = TRUE)) {
#'   attach_geometry(snap, geometry = "polygon") |>
#'     value_by_alpha_map(gdp_per_capita, population)
#' }
#' }
value_by_alpha_map <- function(data, value, equalize,
                               style = c("quantile", "continuous", "binned",
                                         "jenks"),
                               palette = NULL, n_bins = 5,
                               alpha_range = c(0.15, 1),
                               transform = c("rank", "log10", "identity"),
                               background = "grey20",
                               title = NULL, legend = NULL,
                               projection = "equal_earth") {
  style <- rlang::arg_match(style)
  transform <- rlang::arg_match(transform)
  value_q <- rlang::enquo(value)
  value_name <- quo_arg_name(value_q, "value")
  eq_name <- quo_arg_name(rlang::enquo(equalize), "equalize")
  check_cols(data, c(value_name, eq_name))
  check_numeric_col(data, eq_name)
  check_map_geometry(data)
  check_string(background, "background")
  check_label_args(palette, title, legend, "No data")
  if (!is.numeric(alpha_range) || length(alpha_range) != 2L ||
      anyNA(alpha_range) || any(alpha_range < 0) || any(alpha_range > 1) ||
      alpha_range[1] >= alpha_range[2]) {
    wdj_abort(c(
      "{.arg alpha_range} must be two increasing values within [0, 1].",
      "x" = "Got {.val {alpha_range}}."
    ))
  }

  eq <- data[[eq_name]]
  a <- switch(
    transform,
    # Population spans five orders of magnitude, so on a linear scale China and
    # India are opaque and every other country is a smudge. Rank is the default
    # because it keeps the whole opacity range in play.
    rank     = dplyr::percent_rank(eq),
    log10    = { v <- log10(pmax(eq, 0) + 1); rescale01(v) },
    identity = rescale01(eq)
  )
  # A country with no equalising value has no claim on the reader's attention,
  # and ggplot2 draws an NA alpha at full opacity -- so Antarctica, which has no
  # population, came out as the brightest thing on the map. Send it to the floor
  # instead, where the neutral background shows through.
  a[!is.finite(a)] <- 0
  # With nothing usable in `equalize` every country lands on the same alpha,
  # and a scale with no spread to rescale puts them all at the *midpoint* --
  # a uniformly half-lit map that reads as "equally weighted", which is the one
  # impression this verb exists to prevent.
  if (!any(is.finite(eq))) {
    wdj_warn(c(
      "No usable values in {.arg {eq_name}}, so opacity carries no information.",
      "i" = "Every country is drawn at the floor of {.arg alpha_range}.
             {.fn world_map} is the honest choice for a frame with no
             equalising variable."
    ))
  }
  data[[".wdj_alpha"]] <- a

  binned <- apply_binned_fill(data, value_q, value_name, style, n_bins)
  data <- binned$data
  fill_mapped <- binned$fill
  sf_mode <- is_sf(data)

  base_rect <- ggplot2::annotate("rect", xmin = -Inf, xmax = Inf,
                                 ymin = -Inf, ymax = Inf, fill = background)
  p <- if (sf_mode) {
    ggplot2::ggplot(data) + base_rect +
      ggplot2::geom_sf(ggplot2::aes(fill = !!fill_mapped,
                                    alpha = .data$.wdj_alpha),
                       color = NA) +
      wdj_coord_sf(projection)
  } else {
    ggplot2::ggplot(data, ggplot2::aes(x = .data$long, y = .data$lat,
                                       group = .data$group)) + base_rect +
      ggplot2::geom_polygon(ggplot2::aes(fill = !!fill_mapped,
                                         alpha = .data$.wdj_alpha),
                            color = NA) +
      ggplot2::coord_quickmap()
  }

  p <- p +
    add_fill_scale(style, palette, n_bins, "No data", legend %||% value_name,
                   breaks = attr(binned, "breaks")) +
    # limits: `a` is already normalised to [0, 1] by every branch of the
    # transform above, so pinning them makes the mapping absolute -- 0 is always
    # the floor and 1 always the ceiling, whatever spread this particular frame
    # happens to have. Without it a degenerate frame rescaled to the midpoint,
    # and two maps of different subsets were not comparable.
    ggplot2::scale_alpha_continuous(name = eq_name, range = alpha_range,
                                    limits = c(0, 1),
                                    guide = ggplot2::guide_legend(order = 2)) +
    theme_world_map()
  if (!is.null(title)) p <- p + ggplot2::labs(title = title)
  wdj_provenance(p, data, value_name, if (sf_mode) "sf" else "polygon",
                 if (sf_mode) projection else "coord_quickmap",
                 style = paste0("value-by-alpha (", style, ", ", transform, ")"),
                 extra = list(n_bins = n_bins, breaks = attr(binned, "breaks")))
}

# Rescale to [0, 1], tolerating a constant vector (which would otherwise be 0/0).
rescale01 <- function(x) {
  ok <- is.finite(x)
  # An all-NA (or all-infinite) column has no range at all, and range() answers
  # that with Inf/-Inf plus two warnings rather than an error.
  if (!any(ok)) return(rep(1, length(x)))
  rng <- range(x[ok])
  if (rng[1] == rng[2]) return(rep(1, length(x)))
  (x - rng[1]) / (rng[2] - rng[1])
}
