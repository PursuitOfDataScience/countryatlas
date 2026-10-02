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
#' @section Backend:
#' Either backend, as [world_map()]: the frame decides, and both draw in Equal
#' Earth unless `projection` is passed on through `...`.
#'
#' @return A `ggplot` object.
#' @seealso [audit_coverage()], [world_map()]
#' @export
#' @examples
#' \donttest{
#' snap <- countryatlas::world_snapshot$countries
#' attach_geometry(snap, geometry = "polygon") |>
#'   coverage_map(gdp_per_capita)
#' }
coverage_map <- function(data, value, by = NULL, title = NULL, ...) {
  refuse_reserved_dots(rlang::list2(...), c("style", "legend"), "coverage_map")
  value_q <- rlang::enquo(value)
  value_name <- quo_arg_name(value_q, "value")
  by_q <- rlang::enquo(by)
  check_cols(data, value_name)
  check_map_geometry(data)
  if (!is.null(title)) check_string(title, "title")

  cov <- na_coverage(data, value_name)
  # has_value(), the same test the caption's count uses: an infinite value
  # cannot be mapped, so painting it "Reported" while the caption counted it
  # missing put two answers on one plot.
  data[[".wdj_available"]] <- factor(
    ifelse(has_value(data[[value_name]]), "Reported", "Missing"),
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
        caption = paste(stats::na.omit(c(
          sprintf("%d of %d %s report a value; %d missing.",
                  cov$n_shown, cov$n_total, countries_noun(cov$n_total),
                  cov$n_missing),
          source_caption(fill_source_info(data, value_name)))), collapse = " ")
      )
  )
  if (!rlang::quo_is_null(by_q)) {
    by_name <- quo_arg_name(by_q, "by")
    check_cols(data, by_name)
    p <- p + ggplot2::facet_wrap(ggplot2::vars(.data[[by_name]]))
  }
  restate_provenance(p, data, value_name)
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
#'   `"jenks"`, `"fisher"`, `"headtails"`, `"equal"`, `"pretty"` and `"sd"`,
#'   with the breaks [world_map()] would draw for each. `"jenks"` and
#'   `"fisher"` need the optional `classInt`; without it they fall back to
#'   quantile breaks with a warning.
#' @param n_bins Number of classes (default `5`), as the map verbs call it;
#'   `"headtails"` and `"pretty"` choose their own.
#' @param n `r lifecycle::badge("deprecated")` Use `n_bins`.
#' @param ncol Number of facet columns.
#' @param ... Passed to [world_map()].
#'
#' @return A faceted `ggplot` object, with the per-method break and class-count
#'   table attached as the `"countryatlas_classification"` attribute (and
#'   readable with [map_provenance()]). Each method's rows also carry three
#'   measures of fit: `gvf`, the goodness of variance fit, and `tai`, the
#'   tabular accuracy index (both Jenks & Caspall 1971; 1 is a perfect fit),
#'   and `max_class_share`, the share of countries in the fullest class.
#'
#' @section No number picks a classification:
#' GVF and TAI measure how homogeneous the classes are, which is what natural
#' breaks optimise; they rate a map that puts most countries in one class
#' highly, and they say nothing about how well readers read the map. They are
#' reported to inform the choice, never to rank the methods: Brewer & Pickle's
#' finding that quantiles read best stands beside them, and
#' `max_class_share` flags the map whose fullest class swallows the rest.
#'
#' @references
#' Brewer, C. A. & Pickle, L. (2002). Evaluation of methods for classifying
#' epidemiological data on choropleth maps in series. *Annals of the
#' Association of American Geographers* 92(4), 662-681.
#' \doi{10.1111/1467-8306.00310}
#'
#' Jenks, G. F. & Caspall, F. C. (1971). Error on choroplethic maps:
#' definition, measurement, reduction. *Annals of the Association of American
#' Geographers* 61(2), 217-244. \doi{10.1111/j.1467-8306.1971.tb00779.x}
#'
#' Jiang, B. (2013). Head/tail breaks: a new classification scheme for data
#' with a heavy-tailed distribution. *The Professional Geographer* 65(3),
#' 482-494. \doi{10.1080/00330124.2012.700499}
#'
#' @seealso [world_map()], [map_provenance()]
#' @export
#' @examples
#' \donttest{
#' snap <- countryatlas::world_snapshot$countries
#' cmp <- attach_geometry(snap, geometry = "polygon") |>
#'   classify_compare(gdp_per_capita)
#' attr(cmp, "countryatlas_classification")
#' }
classify_compare <- function(data, value,
                             methods = c("quantile", "jenks", "fisher",
                                         "headtails", "equal", "pretty"),
                             n_bins = 5, ncol = NULL, ..., n = deprecated()) {
  # Errors name the argument the caller wrote, the deprecated one included.
  n_arg <- "n_bins"
  if (lifecycle::is_present(n)) {
    lifecycle::deprecate_warn("4.0.0", "classify_compare(n)",
                              "classify_compare(n_bins)")
    n_bins <- n
    n_arg <- "n"
  }
  n <- n_bins
  refuse_reserved_dots(rlang::list2(...), c("style", "legend"), "classify_compare")
  value_q <- rlang::enquo(value)
  value_name <- quo_arg_name(value_q, "value")
  check_cols(data, value_name)
  check_numeric_col(data, value_name)
  check_map_geometry(data)
  check_number(n, n_arg, lo = 2, hi = .Machine$integer.max)
  n <- as.integer(n)
  known <- c("quantile", "jenks", "fisher", "headtails", "equal", "pretty", "sd")
  bad <- setdiff(methods, known)
  if (length(bad)) {
    # cli::qty(): with {?s} ahead of the value, cli reaches for the most
    # recent interpolation to get a quantity, and a *numeric* vector there is
    # read as the quantity itself -- which must be length 1, so a length-2
    # numeric died on cli's own "length(object) == 1 is not TRUE" instead of
    # reporting the bad input. A character vector works, which is why this
    # only showed up for numeric arguments. qty(length(x)) states the count
    # outright; qty(x) on a numeric hits the same trap, since cli reads a
    # numeric as the count itself.
    wdj_abort(c("Unknown classification method{cli::qty(length(bad))}{?s} {.val {bad}}.",
                "i" = "Available: {.val {known}}."))
  }
  if (!length(methods)) wdj_abort("{.arg methods} must name at least one method.")
  # One panel per method. A repeat is a panel that says nothing new, and it
  # died on base R's "factor level [2] is duplicated" when the panels were
  # labelled below.
  methods <- unique(methods)

  # Break on one value per country, for the same reason world_map() does: on the
  # polygon backend a country contributes one row per boundary vertex, so raw
  # quantiles would weight each country by the complexity of its coastline.
  #
  # De-duplicate (country, value) pairs rather than taking one row per country.
  # Those vertex rows all carry the same value and collapse either way, but
  # "one row per country" also picked an arbitrary row when a country's rows
  # genuinely differ, i.e. a panel -- and here that was worse than a different
  # break set. Every row is cut() against these breaks below, so the rows the
  # chosen year did not cover fell outside the range and came back NA: half the
  # panel silently drew as grey, and which half depended on the caller's row
  # order. Same fix as apply_binned_fill().
  df <- tibble::as_tibble(sf_drop(data))
  key <- wdj_unit_key(names(df))
  one <- if (length(key)) {
    dplyr::distinct(df, .data[[key[1]]], .data[[value_name]])
  } else {
    df
  }
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
    cls <- bin_values(vals, br)
    tab <- table(cls)
    fit <- class_fit(vals, br)
    tibble::tibble(method = methods[i], class = names(tab), n = as.integer(tab),
                   share = as.integer(tab) / max(1L, sum(tab)),
                   gvf = fit$gvf, tai = fit$tai,
                   max_class_share = fit$max_class_share)
  }))

  class_sym <- rlang::sym(".wdj_class")
  p <- suppressMessages(
    world_map(combined, !!class_sym, style = "categorical",
              legend = paste0(value_name, "\nclass"), ...) +
      ggplot2::scale_fill_viridis_d(name = paste0(value_name, "\nclass"),
                                    na.value = "grey85", drop = FALSE,
                                    labels = discrete_na_labels("No data")) +
      ggplot2::facet_wrap(ggplot2::vars(.data$.wdj_method), ncol = ncol)
  )
  attr(p, "countryatlas_classification") <- report
  restate_provenance(p, data, value_name)
}

# Breaks for classify_compare()'s methods: the package's own compute_breaks()
# for every style world_map() offers, so the comparison matches what it would
# draw.
classify_breaks <- function(x, method, n) {
  x <- x[is.finite(x)]
  if (length(unique(x)) < 2L) return(compute_breaks(x, "quantile", n))
  if (identical(method, "pretty")) return(unique(pretty(x, n = n)))
  compute_breaks(x, method, n)
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
#' @param style Classification for the colour channel, as in [world_map()]
#'   (any of its styles but `"categorical"`).
#' @param palette,breaks,midpoint As in [world_map()].
#' @param n_bins Number of colour bins for the binned styles.
#' @param alpha_range Minimum and maximum opacity (default `c(0.15, 1)`).
#' @param transform Transform applied to `equalize` before it is mapped to
#'   opacity: `"rank"` (default, robust to the extreme skew of population),
#'   `"log10"` or `"identity"`.
#' @param background Colour behind the countries, which shows through where
#'   opacity is low (default a dark neutral).
#' @param title,legend Optional plot title and legend title.
#' @param projection Projection, as in [world_map()].
#' @param footnote,small_states,small_area_km2 As in [world_map()]. A small
#'   state drawn as a point takes its opacity from `equalize` too.
#'
#' @section Backend:
#' Either backend, from the frame: an `sf` frame draws through `coord_sf()`, a
#' polygon frame on the polygon backend, both in `projection` (Equal Earth by
#' default).
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
#' attach_geometry(snap, geometry = "polygon") |>
#'   value_by_alpha_map(gdp_per_capita, population)
#' }
value_by_alpha_map <- function(data, value, equalize,
                               style = c("quantile", "continuous", "binned",
                                         "equal", "jenks", "fisher",
                                         "headtails", "sd", "fixed"),
                               palette = NULL, n_bins = 5, breaks = NULL,
                               midpoint = NULL,
                               alpha_range = c(0.15, 1),
                               transform = c("rank", "log10", "identity"),
                               background = "grey20",
                               title = NULL, legend = NULL,
                               projection = "equal_earth", footnote = "auto",
                               small_states = c("auto", "none", "dots"),
                               small_area_km2 = 1000) {
  style_given <- !missing(style)
  style <- rlang::arg_match(style)
  small_states <- rlang::arg_match(small_states)
  check_number(small_area_km2, "small_area_km2", lo = 0)
  transform <- rlang::arg_match(transform)
  value_q <- rlang::enquo(value)
  value_name <- quo_arg_name(value_q, "value")
  eq_name <- quo_arg_name(rlang::enquo(equalize), "equalize")
  check_cols(data, c(value_name, eq_name))
  check_numeric_col(data, eq_name)
  check_map_geometry(data)
  style <- resolve_style(style, style_given, breaks, midpoint, n_bins,
                         data[[value_name]], allow_categorical = FALSE)
  # Every style this verb offers bins or scales a number. world_map() has
  # refused a non-numeric fill for these styles since 2.0.0; this verb did not,
  # so value_by_alpha_map(d, continent, population) drew the categories on a
  # discrete scale and recorded "value-by-alpha (quantile, rank)": a quantile
  # classification it never computed.
  check_categorical_fill(style, data[[value_name]], value_name)
  # An infinity draws as no data here too; see world_map().
  warn_infinite_fill(data, value_name)
  check_string(background, "background")
  check_label_args(palette, title, legend, "No data")
  # `n_bins` means nothing to a continuous colourbar, the same notice
  # world_map() gives. This verb has its own copy of the argument rather than
  # passing it through, so it needs its own notice.
  # Validated here, as world_map() does, and before the notice: unchecked, a bad
  # value was first reported as ignored and then refused by an internal helper
  # the error named ("Error in `compute_breaks()`").
  check_number(n_bins, "n_bins", lo = 2, hi = .Machine$integer.max)
  if (!identical(as.numeric(n_bins), 5)) warn_n_bins_ignored(style)
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
    # because it keeps the whole opacity range in play. Ranked once per
    # country: see unit_percent_rank().
    rank     = unit_percent_rank(eq, unit_ids(data)),
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
  # Gated on the number of *distinct* usable values, not on any() being finite.
  # A column that is constant but finite is worse than an empty one and was
  # unguarded: percent_rank(constant) is 0 for every row, so the default
  # transform put every country at the floor of `alpha_range` over a grey20
  # background -- an effectively blank map -- while "identity" and "log10" go
  # through rescale01(), which returns 1 for a constant vector and draws every
  # country fully opaque. Three transforms, two opposite wrong answers, and no
  # warning for either.
  usable <- unique(eq[is.finite(eq)])
  if (length(usable) < 2L) {
    wdj_warn(c(
      "{.arg {eq_name}} has {cli::qty(length(usable))}{?no/only one} distinct
       usable value, so opacity carries no information.",
      "i" = "Every country is drawn at the same opacity. {.fn world_map} is
             the honest choice for a frame with no equalising variable."
    ), class = "countryatlas_no_equalize")
  }
  data[[".wdj_alpha"]] <- a

  pf <- prepare_fill(data, value_name, style, n_bins, breaks, midpoint,
                     small_states, small_area_km2)
  binned <- pf$binned
  data <- pf$data
  fill_mapped <- pf$fill
  pts <- pf$points
  # A small state's opacity comes from the same transform, against the
  # polygons' values: its rank among them, or its place in their range.
  if (!is.null(pts) && nrow(pts) && eq_name %in% names(pts)) {
    ev <- pts[[eq_name]]
    pa <- switch(
      transform,
      rank = {
        ref <- unique(eq[is.finite(eq)])
        vapply(ev, function(v) if (!is.finite(v) || length(ref) < 2L) NA_real_ else
          mean(ref < v) * length(ref) / (length(ref) - 1L), numeric(1))
      },
      log10 = {
        rng <- range(log10(pmax(eq[is.finite(eq)], 0) + 1))
        (log10(pmax(ev, 0) + 1) - rng[1]) / diff(rng)
      },
      identity = {
        rng <- range(eq[is.finite(eq)])
        (ev - rng[1]) / diff(rng)
      })
    pa <- pmin(pmax(pa, 0), 1)
    pa[!is.finite(pa)] <- 0
    pts[[".wdj_alpha"]] <- pa
  }
  sf_mode <- is_sf(data)

  alpha_col <- if (!is.null(pts) && ".wdj_alpha" %in% names(pts)) ".wdj_alpha"
  if (sf_mode) data <- clip_for_projection(data, projection)
  p <- if (sf_mode) {
    ggplot2::ggplot(data) +
      ggplot2::geom_sf(ggplot2::aes(fill = !!fill_mapped,
                                    alpha = .data$.wdj_alpha),
                       color = NA) +
      small_state_layer(pts, fill_mapped, TRUE, NULL, projection,
                        alpha = alpha_col) +
      wdj_coord_sf(projection)
  } else {
    pc <- wdj_polygon_coord(projection)
    data <- apply_polygon_transform(data, pc)
    ggplot2::ggplot(data, ggplot2::aes(x = .data$long, y = .data$lat,
                                       group = .data$group)) +
      ggplot2::geom_polygon(ggplot2::aes(fill = !!fill_mapped,
                                         alpha = .data$.wdj_alpha),
                            color = NA) +
      small_state_layer(pts, fill_mapped, FALSE, pc, projection,
                        alpha = alpha_col) +
      pc$coord
  }

  p <- p +
    add_fill_scale(style, palette, n_bins, "No data",
                   legend %||% legend_title(data, value_name),
                   binned = binned, limits = pf$limits,
                   na_present = pf$na_present) +
    # limits: `a` is already normalised to [0, 1] by every branch of the
    # transform above, so pinning them makes the mapping absolute -- 0 is always
    # the floor and 1 always the ceiling, whatever spread this particular frame
    # happens to have. Without it a degenerate frame rescaled to the midpoint,
    # and two maps of different subsets were not comparable.
    ggplot2::scale_alpha_continuous(name = eq_name, range = alpha_range,
                                    limits = c(0, 1),
                                    guide = ggplot2::guide_legend(order = 2)) +
    theme_world_map() +
    # The dark ground the faded countries sink into, as the panel itself. An
    # annotate("rect") at +/-Inf was a layer in data space, which coord_sf()
    # reprojects from lon/lat on the polygon backend: it came out as a lens
    # between two meridians across Europe and Africa.
    ggplot2::theme(panel.background = ggplot2::element_rect(fill = background,
                                                            colour = NA))
  if (!is.null(title)) p <- p + ggplot2::labs(title = title)
  wdj_provenance(p, data, value_name, if (sf_mode) "sf" else "polygon",
                 if (sf_mode) projection else pc$label,
                 style = paste0("value-by-alpha (", style, ", ", transform, ")"),
                 extra = list(n_bins = n_bins, breaks = attr(binned, "breaks"),
                              midpoint = midpoint, coverage = pf$coverage),
                 footnote = footnote, notes = small_state_note(pf$ss))
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

# --- Value-Suppressing Uncertainty Palettes -------------------------------------
#
# Correll, Moritz & Heer (CHI 2018): a 2-D palette where the *value* range
# contracts as uncertainty rises, so an uncertain estimate cannot claim an
# extreme colour. Their crowdsourced study found readers weighted uncertainty
# more heavily with a VSUP than with an ordinary bivariate map. The construction
# here is the continuous form: a country's position along the value ramp is
# pulled toward the middle in proportion to its uncertainty, and the legend is
# laid out as the value x uncertainty grid the palette actually is.

# Build the per-row fill colour and the matching legend levels.
# One resolution of the value-suppressing ramp, for the map and its legend both.
#
# vsup_fill() resolved it with a tryCatch fallback to viridis while vsup_scale()
# hard-coded viridis, so the two could disagree about what the swatches mean.
# hcl.colors() also takes a *different* set of names from
# scale_fill_viridis_c(): it accepts "plasma", "inferno", "cividis", "mako" and
# "rocket" but rejects "magma" and "turbo", which the rest of world_map()
# honours. Falling back in silence would reproduce the bug this replaced --
# `palette` accepted and quietly ignored -- so say so once.
vsup_cols <- function(option = "viridis") {
  base <- grDevices::hcl.colors(256, palette = "viridis")
  if (identical(option, "viridis") || is.null(option)) return(base)
  cols <- tryCatch(grDevices::hcl.colors(256, palette = option),
                   error = function(e) NULL)
  if (is.null(cols)) {
    wdj_warn(c(
      "{.arg palette} {.val {option}} is not available for a value-suppressing
       palette; viridis is used.",
      "i" = 'The uncertainty ramp is built with {.fn grDevices::hcl.colors},
             which takes {.val plasma}, {.val inferno}, {.val cividis},
             {.val mako} or {.val rocket} -- not {.val magma} or {.val turbo}.'
    ), class = "countryatlas_vsup_palette_ignored", .frequency = "once",
       .frequency_id = paste0("vsup-palette-", option))
    return(base)
  }
  cols
}

vsup_fill <- function(value, uncertainty, n_bins = 4, n_uncertainty = 3,
                      option = "viridis", suppress = 0.85, unit = NULL) {
  ok <- is.finite(value) & is.finite(uncertainty)
  v_rank <- rep(NA_real_, length(value))
  u_rank <- rep(NA_real_, length(value))
  if (any(ok)) {
    # Rank, not linear rescaling. Both axes here are typically skewed -- on
    # `world_snapshot`'s GDP per capita a linear stretch put 174 of 191
    # countries in the bottom bin and left most of the palette unused, which
    # defeats the entire point of a 2-D palette. Ranking also matches the
    # quantile default the rest of the package uses for choropleths, and like
    # those breaks it is taken once per country (`unit`), not once per
    # polygon vertex: see unit_percent_rank().
    v_rank[ok] <- unit_percent_rank(value[ok], unit[ok])
    u_rank[ok] <- unit_percent_rank(uncertainty[ok], unit[ok])
    # percent_rank() is (rank - 1)/(n - 1), so it is NaN when exactly one row
    # is usable -- and cut() then gave NA, the row got no colour, and the map
    # drew a country whose value and uncertainty were both present as though
    # neither were. That is not a one-row-input curiosity: a mostly-missing
    # uncertainty column with a single usable country blanked the whole VSUP
    # layer. A lone observation has no rank position relative to others, so
    # the honest place for it is the middle of each ramp, claiming neither
    # extreme -- which is also where a maximally uncertain value lands.
    v_rank[ok & !is.finite(v_rank)] <- 0.5
    u_rank[ok & !is.finite(u_rank)] <- 0.5
  }
  v_bin <- cut(v_rank, breaks = seq(0, 1, length.out = n_bins + 1L),
               include.lowest = TRUE, labels = FALSE)
  u_bin <- cut(u_rank, breaks = seq(0, 1, length.out = n_uncertainty + 1L),
               include.lowest = TRUE, labels = FALSE)

  # Value position at the centre of its bin, then suppressed toward 0.5 by the
  # uncertainty level. At the top uncertainty bin the whole value range
  # collapses to a narrow band around the middle of the ramp -- which is the
  # point: an uncertain estimate should not be allowed to look extreme.
  centre <- (v_bin - 0.5) / n_bins
  shrink <- 1 - suppress * ((u_bin - 1) / max(1L, n_uncertainty - 1L))
  pos <- 0.5 + (centre - 0.5) * shrink
  cols <- vsup_cols(option)
  fill <- rep(NA_character_, length(value))
  idx <- pmax(1L, pmin(256L, round(pos * 255) + 1L))
  fill[!is.na(idx)] <- cols[idx[!is.na(idx)]]
  # `fill` looks unused -- world_map() maps `label` through vsup_scale() and
  # never reads it -- but it is the only handle on the *colours* this function
  # produces, and two tests use it to assert the defining VSUP property (each
  # uncertainty band spans a narrower slice of the value ramp than the one
  # below). Checking `label` cannot show that: the labels are the same
  # whatever palette the ramp is. Keep it; the cost is one hcl.colors(256) per
  # map.
  list(fill = fill, v_bin = v_bin, u_bin = u_bin,
       label = ifelse(is.na(v_bin) | is.na(u_bin), NA_character_,
                      sprintf("v%d / u%d", v_bin, u_bin)))
}

# The legend: one swatch per (value, uncertainty) cell, laid out as a grid so
# the 2-D structure is visible rather than asserted.
# `option` and `suppress` are taken rather than assumed: both were hard-coded
# here while vsup_fill() took them as arguments, so the legend could not follow
# the map -- world_map(palette = ) reached neither, and any future change to
# either default would have had to be made twice. Defaults match vsup_fill()'s.
vsup_scale <- function(vs, n_bins, n_uncertainty, value_name, uncertainty_name,
                       option = "viridis", suppress = 0.85) {
  grid <- expand.grid(v = seq_len(n_bins), u = seq_len(n_uncertainty))
  # Compute the swatch colour from the *bin indices* directly, so the legend
  # cannot drift from the map when the data's range changes.
  centre <- (grid$v - 0.5) / n_bins
  shrink <- 1 - suppress * ((grid$u - 1) / max(1L, n_uncertainty - 1L))
  pos <- 0.5 + (centre - 0.5) * shrink
  cols <- vsup_cols(option)
  swatch <- cols[pmax(1L, pmin(256L, round(pos * 255) + 1L))]
  labels <- sprintf("v%d / u%d", grid$v, grid$u)
  values <- stats::setNames(swatch, labels)
  ggplot2::scale_fill_manual(
    name = paste0(value_name, "\nby ", uncertainty_name),
    # breaks as well as limits: with limits alone ggplot2 still omitted a key
    # for a value x uncertainty cell no country happened to fall in, and an
    # incomplete grid defeats a legend whose entire job is to show the grid.
    values = values, na.value = "grey85", drop = FALSE,
    limits = labels, breaks = labels,
    guide = ggplot2::guide_legend(ncol = n_uncertainty, byrow = FALSE,
                                  reverse = FALSE)
  )
}
