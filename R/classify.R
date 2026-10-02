# Classification: breaks, classes, labels and fill scales -----------------------------
#
# Every choropleth verb bins through here, so a quantile map, its legend, its
# classification report and its provenance all describe the same classes.

# Styles that cut the fill into classes (a discrete legend), and the ones that
# keep a colourbar.
CLASSED_STYLES <- c("quantile", "jenks", "fisher", "headtails", "sd", "fixed")
BAR_STYLES <- c("binned", "equal")
MAP_STYLES <- c("quantile", "continuous", "binned", "equal", "jenks", "fisher",
                "headtails", "sd", "fixed", "categorical")

# Compute classInt-style breaks. quantile, equal, sd and headtails are computed
# here and agree with classInt's; jenks and fisher need classInt and fall back
# to quantile breaks, with a warning, without it.
compute_breaks <- function(x, style, n_bins, call = rlang::caller_env()) {
  # classInt rejects n < 2 with a bare "n less than 2", and an NA got as far as
  # "missing value where TRUE/FALSE needed". The upper bound matters because
  # callers coerce counts with as.integer(), which returns NA past 2^31-1.
  check_number(n_bins, "n_bins", lo = 2, hi = .Machine$integer.max, call = call)
  # Truncate to a whole number of bins so every path agrees: classInt
  # truncates internally, but the base-quantile fallback would pass a fractional
  # count to seq(length.out = ), giving one break more. The bin count must not
  # depend on whether classInt happens to be installed.
  n_bins <- as.integer(n_bins)
  x <- x[is.finite(x)]
  if (length(unique(x)) < 2L) {
    if (!length(x)) return(c(0, 1))
    v <- unique(x)[1]
    return(c(v - 0.5, v + 0.5))
  }
  if (style %in% c("binned", "equal")) {
    return(unique(seq(min(x), max(x), length.out = n_bins + 1)))
  }
  if (identical(style, "headtails")) return(headtails_breaks(x))
  if (identical(style, "sd")) return(sd_breaks(x, n_bins))
  if (style %in% c("jenks", "fisher")) {
    if (has_pkg("classInt")) {
      # classInt is chatty when n equals the number of distinct values, or on
      # ties; the binning is still valid, so don't leak the warning to callers.
      br <- suppressWarnings(suppressMessages(
        classInt::classIntervals(x, n = n_bins, style = style)
      ))$brks
      return(unique(br))
    }
    wdj_warn("Package {.pkg classInt} not installed; using quantile breaks
              instead of {.val {style}}.", class = "countryatlas_style_fallback")
  }
  unique(stats::quantile(x, probs = seq(0, 1, length.out = n_bins + 1),
                         na.rm = TRUE, names = FALSE))
}

# Head/tail breaks (Jiang 2013): split at the mean, keep the head above it,
# and repeat while the head stays a minority (at most 40%). Made for the
# heavy-tailed variables a world map is usually of, and it chooses its own
# class count. The same algorithm as classInt's style = "headtails".
headtails_breaks <- function(x, thr = 0.4) {
  head <- x
  br <- min(x)
  for (i in seq_len(100L)) {
    mu <- mean(head)
    br <- c(br, mu)
    n <- length(head)
    head <- head[head > mu]
    if (!(length(head) / n <= thr && length(head) > 1L)) break
  }
  sort(unique(c(br, max(x))))
}

# Standard-deviation breaks: pretty breaks on the standardised variable, put
# back on its scale -- the mean plus or minus whole and half standard
# deviations. The same algorithm as classInt's style = "sd".
sd_breaks <- function(x, n) {
  m <- mean(x)
  s <- stats::sd(x)
  br <- pretty((x - m) / s, n = n) * s + m
  br[1] <- min(br[1], min(x))
  br[length(br)] <- max(br[length(br)], max(x))
  unique(br)
}

# Numbers for a legend, SI-shortened ("1.14K", "250M") to three significant
# figures, with more where two adjacent edges would otherwise read the same.
si_label <- function(x) {
  fmt <- function(v, digits) {
    out <- character(length(v))
    for (i in seq_along(v)) {
      a <- abs(v[i])
      if (!is.finite(v[i])) {
        out[i] <- if (is.na(v[i])) "NA" else if (v[i] > 0) "Inf" else "-Inf"
        next
      }
      k <- findInterval(a, c(1e3, 1e6, 1e9, 1e12))
      div <- c(1, 1e3, 1e6, 1e9, 1e12)[k + 1L]
      sfx <- c("", "K", "M", "B", "T")[k + 1L]
      out[i] <- paste0(formatC(signif(v[i] / div, digits), format = "fg",
                               digits = digits), sfx)
    }
    trimws(out)
  }
  for (d in 3:8) {
    lab <- fmt(x, d)
    fin <- is.finite(x)
    if (!anyDuplicated(lab[fin]) || d == 8L) return(lab)
  }
}

# Legend text for the classes between consecutive breaks: "1.14K to 4.47K",
# with "< b" and ">= b" for a class open at either end.
class_labels <- function(breaks) {
  k <- length(breaks) - 1L
  lab <- si_label(breaks)
  out <- paste(lab[-(k + 1L)], "to", lab[-1L])
  lo_open <- is.infinite(breaks[1]) && breaks[1] < 0
  hi_open <- is.infinite(breaks[k + 1L]) && breaks[k + 1L] > 0
  if (lo_open && hi_open && k == 1L) return("All values")
  if (lo_open) out[1] <- paste("<", lab[2])
  if (hi_open) out[k] <- paste(">=", lab[k])
  out
}

# Cut into classes. Computed breaks close on the right, as classInt's do;
# fixed thresholds close on the left, so "1,136 and over" means what it says.
bin_values <- function(x, breaks, right = TRUE) {
  cut(x, breaks = breaks, labels = class_labels(breaks), include.lowest = TRUE,
      right = right)
}

# Validate a caller's fixed breaks.
check_breaks <- function(breaks, call = rlang::caller_env()) {
  if (!is.numeric(breaks) || length(breaks) < 2L || anyNA(breaks) ||
      is.unsorted(breaks, strictly = TRUE)) {
    wdj_abort(c(
      "{.arg breaks} must be a sorted, unique numeric vector of at least two
       values.",
      "x" = "Got {.obj_type_friendly {breaks}}{if (is.numeric(breaks))
              paste0(': ', paste(utils::head(breaks, 6), collapse = ', ')) else ''}.",
      "i" = "Use {.code -Inf} and {.code Inf} to open the end classes."
    ), call = call)
  }
  invisible(breaks)
}

# Values below the first break or above the last fall in open end classes:
# say so unless the caller opened the ends themselves.
open_breaks <- function(breaks, x, fill_name) {
  x <- x[is.finite(x)]
  lo <- length(x) && min(x) < breaks[1]
  hi <- length(x) && max(x) > breaks[length(breaks)]
  if (lo || hi) {
    n_out <- sum(x < breaks[1]) + sum(x > breaks[length(breaks)])
    wdj_warn(c(
      "{n_out} value{?s} of {.field {fill_name}} {cli::qty(n_out)}fall{?s/}
       outside {.arg breaks}; {cli::qty(n_out)}{?it goes/they go} in an
       open-ended end class.",
      "i" = "Start {.arg breaks} with {.code -Inf} or end it with {.code Inf}
             to open the classes yourself and silence this."
    ), class = "countryatlas_breaks_open")
    if (lo) breaks <- c(-Inf, breaks)
    if (hi) breaks <- c(breaks, Inf)
  }
  breaks
}

# The style a map is drawn in, from what the caller passed: `breaks` implies
# "fixed", and a style that needs what was not given is refused.
resolve_style <- function(style, style_given, breaks, midpoint, n_bins, vals,
                          allow_categorical = TRUE,
                          call = rlang::caller_env()) {
  if (!is.null(midpoint)) check_number(midpoint, "midpoint", call = call)
  # The default is now "quantile", which a categorical column cannot take: a
  # factor or character fill falls back to its categories, as a caller who
  # left `style` alone means -- where the verb draws categories at all.
  if (allow_categorical && !style_given && is.null(breaks) &&
      !is.numeric(vals) && !is.null(vals)) {
    style <- "categorical"
  }
  if (!is.null(midpoint) && identical(style, "categorical")) {
    wdj_abort(c(
      '{.arg midpoint} needs a numeric scale; {.code style = "categorical"}
       has none.',
      "i" = "Drop {.arg midpoint}, or map a numeric column."
    ), call = call)
  }
  if (!is.null(breaks)) {
    check_breaks(breaks, call)
    if (style_given && !identical(style, "fixed")) {
      wdj_abort(c(
        '{.arg breaks} sets the classes, so it implies {.code style = "fixed"}.',
        "x" = 'Got {.code style = "{style}"} as well.',
        "i" = "Drop one of the two."
      ), class = "countryatlas_breaks_style", call = call)
    }
    return("fixed")
  }
  if (identical(style, "fixed")) {
    wdj_abort(c('{.code style = "fixed"} needs {.arg breaks}.',
                "i" = "Pass the class boundaries, e.g. {.code breaks = c(0, 1000, 5000, Inf)}."),
              call = call)
  }
  style
}

# `n_bins` only means something to a style that takes a class count. It was
# silently inert under "continuous" (a colourbar has no classes) and
# "categorical" (the classes are the values); "fixed" takes its classes from
# `breaks`, and "headtails" chooses its own.
warn_n_bins_ignored <- function(style, call = rlang::caller_env()) {
  if (!style %in% c("continuous", "categorical", "fixed", "headtails")) {
    return(invisible(NULL))
  }
  wdj_warn(c(
    "{.arg n_bins} does not apply to {.code style = \"{style}\"} and is ignored.",
    "i" = switch(style,
      continuous = 'A continuous colourbar has no classes; use {.code style = "quantile"},
                    {.code "binned"} or {.code "jenks"} to bin.',
      categorical = "The classes are the values of the fill column.",
      fixed = "The classes are the ones {.arg breaks} sets.",
      headtails = "Head/tail breaks choose their own number of classes.")
  ), class = "countryatlas_n_bins_ignored", call = call)
  invisible(NULL)
}

# --- Palettes --------------------------------------------------------------------

VIRIDIS_OPTIONS <- c("magma", "inferno", "plasma", "viridis", "cividis",
                     "rocket", "mako", "turbo", LETTERS[1:8])

# The categorical default: an HCL qualitative palette, hues of equal
# lightness, rather than the "turbo" rainbow 3.0.0 used (Crameri, Shephard &
# Heron 2020).
CATEGORICAL_PALETTE <- "Dark 3"


# Base R's diverging HCL palettes: the ColorBrewer ones ("RdBu", "BrBG", ...)
# and the rest, less the two in "divergingx" that do not diverge.
diverging_palettes <- function() {
  setdiff(c(grDevices::hcl.pals("diverging"), grDevices::hcl.pals("divergingx")),
          c("Zissou 1", "Cividis"))
}

# Resolve `palette`: a viridis option or any base R HCL palette, and a
# diverging one whenever a midpoint is given.
resolve_palette <- function(palette, midpoint, default = "viridis",
                            call = rlang::caller_env()) {
  if (!is.null(midpoint)) {
    palette <- palette %||% "RdBu"
    if (!palette %in% diverging_palettes()) {
      wdj_abort(c(
        "{.arg midpoint} needs a diverging {.arg palette}; {.val {palette}} is
         sequential.",
        "i" = "A diverging palette has a neutral centre for the midpoint to
               sit on. Try {.val RdBu} (the default), {.val BrBG} or
               {.val PuOr}."
      ), class = "countryatlas_palette_not_diverging", call = call)
    }
    return(palette)
  }
  palette <- palette %||% default
  if (!palette %in% c(VIRIDIS_OPTIONS, grDevices::hcl.pals())) {
    wdj_abort(c(
      "{.arg palette} {.val {palette}} is not a palette this package knows.",
      "i" = "Use a viridis option ({.val viridis}, {.val magma}, ...) or a base
             R HCL palette ({.code grDevices::hcl.pals()}), such as
             {.val RdBu}."
    ), class = "countryatlas_unknown_palette", call = call)
  }
  palette
}

# Class colours either side of a midpoint, from the centre of a diverging
# palette outwards, so the first class above the midpoint and the first below
# it are equally light whatever the counts on each side.
diverging_class_colours <- function(n_below, n_above, palette) {
  side <- max(n_below, n_above, 1L)
  full <- grDevices::hcl.colors(2L * side + 1L, palette)
  low <- full[seq_len(side)]
  high <- full[side + 1L + seq_len(side)]
  c(utils::tail(low, n_below), utils::head(high, n_above))
}

# Rescale so `mid` lands exactly on the centre of the palette, stretching the
# longer side to the end of the range and the shorter one proportionally.
mid_rescaler <- function(mid) {
  force(mid)
  function(x, to = c(0, 1), from = range(x, na.rm = TRUE, finite = TRUE)) {
    ext <- max(abs(from - mid))
    if (!is.finite(ext) || ext == 0) return(rep(mean(to), length(x)))
    (x - mid) / ext / 2 * diff(to) + mean(to)
  }
}

# --- Binning a frame --------------------------------------------------------------

# Pre-compute the classes: cut the fill column into an ordered factor and
# return the aesthetic to map, or the original column for the styles that do
# not bin.
#
# Breaks are computed on ONE value per country. The polygon backend repeats a
# country's value once per boundary point, so breaking on the raw column would
# weight each country by its geometric complexity and a "quantile" map would no
# longer hold ~equal countries per colour. The sf backend is *nearly* one row
# per country but not exactly: divided countries occupy two rows sharing one
# iso3c (Cyprus at 110m; Cyprus and India at 50m), which was enough to shift the
# breaks and move a couple of countries into the wrong bin. So de-duplicate on
# the key whenever there is one, on either backend.
#
# `extra` is more values the classes must cover: the small states drawn as
# points, which are on the same scale as the polygons.
apply_binned_fill <- function(data, fill_name, style, n_bins, breaks = NULL,
                              midpoint = NULL, extra = NULL) {
  vals <- data[[fill_name]]
  # A character fill column reaches ggplot2 unfactored, and its discrete scale
  # then derives the level order by sorting -- using the session's collation
  # locale. Same script, same data, different machine: the legend read
  # "Belgium, Chad, Zambia, aland, <A-ring>land" under C collation and
  # "aland, <A-ring>land, Belgium, Chad, Zambia" under en_US, so every category
  # was drawn in a different colour. Pin the order here, byte-wise, so it is
  # the same everywhere. method = "radix" is the point: plain sort() consults
  # the locale. An incoming factor is left alone -- the caller has already
  # chosen an order, and overriding it would be the real surprise.
  if (is.character(vals)) {
    lv <- unique(vals[!is.na(vals)])
    data[[fill_name]] <- factor(vals, levels = lv[order(lv, method = "radix")])
  }
  none <- structure(list(data = data, fill = quo_col_mapping(fill_name)),
                    breaks = NULL, midpoint = midpoint)
  if (!style %in% c(CLASSED_STYLES, BAR_STYLES) || !is.numeric(vals)) {
    return(none)
  }
  break_vals <- vals
  key <- wdj_unit_key(names(data))
  if (length(key)) {
    # De-duplicate (unit, value) pairs, not "one row per unit". The de-dup is
    # here so a polygon-backend frame -- one row per vertex, hundreds per
    # country, all carrying the same fill -- does not weight the quantiles by
    # how complex a country's outline is; those rows collapse to one either
    # way. What "one row per unit" also did was pick an arbitrary row when a
    # country's rows genuinely differ, i.e. a panel: the same panel reordered
    # gave breaks of 10-100 or of 1000-10000, so the map's colours depended on
    # the caller's row order and nothing said so. Keeping the distinct values
    # spans the whole panel instead, which is what facet_map(facet = "year")
    # wants from a shared scale, and is order-independent either way because
    # breaks depend on the multiset of values and not their order.
    break_vals <- dplyr::distinct(tibble::as_tibble(sf_drop(data)),
                                  .data[[key[1]]], .data[[fill_name]])[[fill_name]]
  }
  break_vals <- c(break_vals, extra)
  right <- TRUE
  br <- if (identical(style, "fixed")) {
    right <- FALSE
    open_breaks(breaks, break_vals, fill_name)
  } else {
    compute_breaks(break_vals, style, n_bins)
  }
  # A midpoint is a class boundary, so a diverging palette can change hue there.
  if (!is.null(midpoint) && midpoint > br[1] && midpoint < br[length(br)] &&
      !any(abs(br - midpoint) <= 1e-12 * max(1, abs(midpoint)))) {
    br <- sort(c(br, midpoint))
  }
  # "binned" keeps the continuous colourbar -- it is the one style whose point
  # is a bar rather than discrete keys -- so it takes the breaks and not the
  # cut.
  if (style %in% BAR_STYLES) {
    return(structure(list(data = data, fill = quo_col_mapping(fill_name)),
                     breaks = br, midpoint = midpoint))
  }
  data[[".wdj_bin"]] <- bin_values(vals, br, right)
  # The breaks ride along as an attribute so classification_report and
  # map_provenance() can name them without recomputing (and so risking a
  # different answer from a different de-duplication).
  structure(list(data = data, fill = rlang::quo(.data[[".wdj_bin"]])),
            breaks = br, right = right, midpoint = midpoint)
}

# One row per class: the interval, and how many countries fall in it, cut
# exactly as the map is.
classification_table <- function(data, fill_name, style, n_bins, binned) {
  breaks <- attr(binned, "breaks")
  df <- tibble::as_tibble(sf_drop(data))
  key <- wdj_unit_key(names(df))
  # One row per country is the right shape here -- the report counts countries
  # per class, so a country must not land in two. But by the earliest year
  # rather than distinct()'s first row, or the same panel reordered gave a
  # different report of the same map.
  if (length(key)) df <- earliest_per_unit(df, key[1])
  vals <- df[[fill_name]]
  # A continuous fill has no classes; say so instead of inventing one per
  # distinct value, which is what the fallback used to report.
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
    bin_values(vals, breaks, attr(binned, "right") %||% TRUE)
  } else {
    # as.factor() orders its levels with the session's collation locale, so the
    # report's rows came out in a different order on a different machine.
    # Byte order, as for the fill levels themselves.
    lv <- unique(as.character(vals[!is.na(vals)]))
    factor(as.character(vals), levels = lv[order(lv, method = "radix")])
  }
  tab <- as.data.frame(table(class = cls, useNA = "no"), stringsAsFactors = FALSE)
  out <- tibble::tibble(
    method = style, class = tab$class, n = as.integer(tab$Freq),
    share = as.integer(tab$Freq) / max(1L, sum(tab$Freq))
  )
  if (!is.null(breaks)) {
    fit <- class_fit(vals, breaks, attr(binned, "right") %||% TRUE)
    out$gvf <- fit$gvf
    out$tai <- fit$tai
  }
  out
}

# How well a set of classes fits the values (Jenks & Caspall 1971): the
# goodness of variance fit, 1 - (squared deviations from the class means) /
# (squared deviations from the mean), and the tabular accuracy index, the same
# with absolute deviations. Both are 1 for a perfect fit and fall towards 0.
class_fit <- function(x, breaks, right = TRUE) {
  x <- x[is.finite(x)]
  if (!length(x)) {
    return(list(gvf = NA_real_, tai = NA_real_, max_class_share = NA_real_))
  }
  cls <- cut(x, breaks = breaks, include.lowest = TRUE, right = right)
  dev <- function(f) {
    sum(vapply(split(x, cls), function(v) if (length(v)) sum(f(v - mean(v))) else 0,
               numeric(1)))
  }
  sdam <- sum((x - mean(x))^2)
  tam <- sum(abs(x - mean(x)))
  n <- table(cls)
  list(gvf = if (sdam > 0) 1 - dev(function(d) d^2) / sdam else 1,
       tai = if (tam > 0) 1 - dev(abs) / tam else 1,
       max_class_share = max(n) / sum(n))
}

# --- Fill scales ------------------------------------------------------------------

# Choose the fill scale for the style. `binned` is apply_binned_fill()'s
# result, which carries the breaks and the midpoint.
add_fill_scale <- function(style, palette, n_bins, na_label, legend,
                           na_value = "grey85", binned = NULL, limits = NULL,
                           na_present = TRUE, call = rlang::caller_env()) {
  check_number(n_bins, "n_bins", lo = 2, hi = .Machine$integer.max, call = call)
  n_bins <- as.integer(n_bins)
  breaks <- attr(binned, "breaks")
  midpoint <- attr(binned, "midpoint")
  palette <- resolve_palette(palette, midpoint,
                             if (identical(style, "categorical")) CATEGORICAL_PALETTE else "viridis",
                             call = call)
  viridis <- palette %in% VIRIDIS_OPTIONS
  # A midpoint is the only reason to rescale: it lands on the palette's centre.
  mid <- if (!is.null(midpoint)) list(rescaler = mid_rescaler(midpoint))
  if (identical(style, "continuous")) {
    if (viridis && is.null(midpoint)) {
      return(ggplot2::scale_fill_viridis_c(
        name = legend, na.value = na_value, option = palette,
        labels = scales_format()))
    }
    return(do.call(ggplot2::scale_fill_gradientn, c(list(
      name = legend, na.value = na_value,
      colours = grDevices::hcl.colors(11L, palette), labels = scales_format()),
      mid)))
  }
  if (style %in% BAR_STYLES) {
    # scale_*_binned() reads `breaks` as the interior boundaries, so k of them
    # give k + 1 bins; compute_breaks() returns the outer edges too. "binned"
    # used to hand n_bins to ggplot2 as `n.breaks`, which is only a suggestion
    # (extended_breaks() snaps to round numbers), so the caller now passes
    # explicit equal-interval boundaries.
    inner <- if (!is.null(breaks) && length(breaks) > 2L) {
      breaks[-c(1L, length(breaks))]
    } else NULL
    if (viridis && is.null(midpoint)) {
      if (is.null(inner)) {
        return(ggplot2::scale_fill_viridis_b(
          name = legend, na.value = na_value, n.breaks = n_bins,
          option = palette, labels = scales_format()))
      }
      return(ggplot2::scale_fill_viridis_b(
        name = legend, na.value = na_value, breaks = inner, option = palette,
        labels = scales_format()))
    }
    return(do.call(ggplot2::scale_fill_stepsn, c(list(
      name = legend, na.value = na_value,
      colours = grDevices::hcl.colors(11L, palette),
      breaks = inner %||% ggplot2::waiver(), labels = scales_format()), mid)))
  }
  labels <- discrete_na_labels(na_label)
  # Fixed breaks keep every class in the legend and in its colour, so two
  # maps on the same thresholds read the same however the data falls. Every
  # classed style states its classes in order, and a categorical map the
  # categories it draws: trained layer by layer, a class or category only the
  # small-state points use was appended after the others.
  fixed <- identical(style, "fixed") && !is.null(breaks)
  lv <- if (style %in% CLASSED_STYLES && !is.null(breaks)) class_labels(breaks) else limits
  # Explicit limits drop the no-data key from the legend unless NA is one of
  # them, so it is added back when the map has countries to put under it.
  if (!is.null(lv) && isTRUE(na_present)) lv <- c(lv, NA)
  if (style %in% CLASSED_STYLES && !is.null(breaks) && !is.null(midpoint)) {
    k <- length(breaks) - 1L
    lv <- class_labels(breaks)
    n_below <- sum(breaks[-1L] <= midpoint + 1e-12 * max(1, abs(midpoint)))
    cols <- diverging_class_colours(n_below, k - n_below, palette)
    return(ggplot2::scale_fill_manual(
      name = legend, values = stats::setNames(cols, lv),
      limits = c(lv, if (isTRUE(na_present)) NA),
      drop = FALSE, na.value = na_value, labels = labels))
  }
  if (viridis) {
    return(ggplot2::scale_fill_viridis_d(
      name = legend, na.value = na_value, option = palette, labels = labels,
      limits = lv, drop = !fixed))
  }
  ggplot2::discrete_scale(
    aesthetics = "fill", name = legend, na.value = na_value, labels = labels,
    limits = lv, drop = !fixed,
    palette = function(n) grDevices::hcl.colors(n, palette))
}
