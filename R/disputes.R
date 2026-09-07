# Disputed territories, uncertainty and imputation --------------------------------
#
# Every world map takes a political position, including the ones that think they
# do not. Natural Earth documents an explicit de facto policy; the EU's
# data-visualisation guidance counts roughly 188 disputed areas and notes that
# official publications must reflect an official position.
#
# This package's position is that it has none, and that pretending otherwise is
# the failure mode. So: [disputed_territories] records *that* a dispute exists
# and *who the parties are*, [dispute_policy()] lets the user state which
# convention they are using, and nothing here adjudicates. What the package can
# usefully do is stop a disputed area passing unremarked.

#' State which map convention you are using
#'
#' Disputed territories are drawn differently by different conventions, and a
#' map that does not say which one it used is making a choice silently. This
#' sets the session's convention so [world_map()] can record it and
#' [map_provenance()] can report it.
#'
#' @param policy One of:
#'   * `"none"` (default) -- no convention stated. Maps carry no dispute
#'     annotation, exactly as before.
#'   * `"de_facto"` -- boundaries as administered on the ground, which is what
#'     Natural Earth (and therefore this package's geometry) uses.
#'   * `"de_jure"` -- boundaries as claimed. The package does **not** ship de
#'     jure geometry; selecting this records the intent and warns that the
#'     shapes drawn are still de facto.
#'   * `"neutral"` -- disputed areas marked as disputed rather than assigned.
#'
#'   Called with no argument, returns the current policy.
#'
#' @return The policy in effect, invisibly when setting.
#'
#' @section What this does and does not do:
#' It records a choice and makes it visible. It does not redraw any boundary,
#' and selecting `"de_jure"` will not give you claimed-boundary geometry,
#' because the package does not have any -- Natural Earth's auxiliary claim
#' lines are not bundled. Anyone publishing under an institutional convention
#' should verify the shapes against that institution's own basemap rather than
#' trusting a setting.
#'
#' @seealso [disputed_territories], [check_dispute_coverage()], [world_map()]
#' @export
#' @examples
#' old <- dispute_policy()
#' dispute_policy("neutral")
#' dispute_policy()
#' dispute_policy(old)
dispute_policy <- function(policy = NULL) {
  valid <- c("none", "de_facto", "de_jure", "neutral")
  if (is.null(policy)) {
    # Validate on *read*, not only on write. Setting the option directly is
    # documented as discouraged but perfectly possible, and every other option
    # the package reads is checked when it is read. It matters more here than
    # elsewhere: this option's whole job is to state a convention truthfully on
    # a published map, and an unchecked typo printed "Convention: nonsense".
    got <- getOption("countryatlas.dispute_policy", "none")
    if (length(got) != 1L || !is.character(got) || !got %in% valid) {
      wdj_warn(c(
        "{.code countryatlas.dispute_policy} is set to an unrecognised value;
         using {.val none}.",
        "x" = "Got {.val {got}}.",
        "i" = "Valid values are {.val {valid}}. Set it with
               {.fn dispute_policy} rather than {.fn options}."
      ), .frequency = "once", .frequency_id = "dispute-policy-invalid")
      return("none")
    }
    return(got)
  }
  policy <- rlang::arg_match(policy, valid)
  if (identical(policy, "de_jure")) {
    wdj_warn(c(
      "The geometry is still de facto.",
      "!" = "{.pkg countryatlas} ships Natural Earth's administered boundaries
             and no claimed-boundary layer, so this records your intent but does
             not change a single shape.",
      "i" = "Verify against your institution's own basemap before publishing."
    ))
  }
  options(countryatlas.dispute_policy = policy)
  invisible(policy)
}

#' Which disputed territories does your data touch?
#'
#' Cross-references your data against [disputed_territories] so a contested area
#' does not pass unremarked. Reports both directions: the disputed territories
#' your data covers, and those it is silent about.
#'
#' @param data A frame with `iso3c`, or a character vector of codes.
#' @param quiet Suppress the console summary.
#'
#' @return A tibble of every disputed territory the package knows about, with
#'   `in_data` saying whether your data covers it. The scope caveat in
#'   [disputed_territories] applies: this is a documented subset, not every
#'   dispute in the world.
#'
#' @seealso [disputed_territories], [dispute_policy()], [audit_coverage()]
#' @export
#' @examples
#' check_dispute_coverage(countryatlas::world_snapshot$countries)
check_dispute_coverage <- function(data, quiet = FALSE) {
  check_bool(quiet, "quiet")
  iso <- if (is.character(data)) {
    data
  } else if (is.data.frame(data)) {
    if (!"iso3c" %in% names(data)) {
      wdj_abort("{.arg data} must contain an {.field iso3c} column.")
    }
    unique(stats::na.omit(sf_drop(data)$iso3c))
  } else {
    wdj_abort("{.arg data} must be a data frame with {.field iso3c}, or a character vector.")
  }
  dt <- countryatlas::disputed_territories
  out <- dt
  out$in_data <- !is.na(dt$iso3c) & dt$iso3c %in% iso
  if (!quiet) {
    n_cov <- sum(out$in_data)
    n_uncodeable <- sum(is.na(dt$iso3c))
    wdj_inform(c(
      # Agreements sit against their own count: "1 have no ISO code" and
      # "1 ... territories appear" are both wrong, and both are reachable --
      # the bundled table has 22 rows, of which a caller's data may cover one.
      "i" = "{n_cov} tracked disputed territor{?y/ies} {?appears/appear} in the
             data, of {nrow(dt)} tracked.",
      "*" = "{n_uncodeable} {?has/have} no ISO code at all and cannot appear in
             any iso3c-keyed dataset.",
      " " = "Set a convention with {.fn dispute_policy} so the map says which
             one it used."
    ))
  }
  out
}

# The layer world_map(disputes = "mark") adds: an outline over the disputed
# territories that are actually present, so a reader can see which shapes are
# contested without the package deciding anything about them.
dispute_layer <- function(data, sf_mode) {
  dt <- countryatlas::disputed_territories
  codes <- stats::na.omit(dt$iso3c)
  if (!"iso3c" %in% names(data)) return(NULL)
  hit <- data[data$iso3c %in% codes, , drop = FALSE]
  if (!nrow(hit)) return(NULL)
  if (sf_mode) {
    ggplot2::geom_sf(data = hit, fill = NA, colour = "#B2182B",
                     linewidth = 0.45, linetype = "21", inherit.aes = FALSE)
  } else {
    ggplot2::geom_polygon(
      data = hit,
      mapping = ggplot2::aes(x = .data$long, y = .data$lat, group = .data$group),
      fill = NA, colour = "#B2182B", linewidth = 0.45, linetype = "21",
      inherit.aes = FALSE
    )
  }
}

# The caption fragment describing the dispute treatment, appended to whatever
# footnote the caller asked for.
dispute_note <- function(disputes, data) {
  if (identical(disputes, "ignore")) return(NULL)
  dt <- countryatlas::disputed_territories
  n_marked <- if ("iso3c" %in% names(data)) {
    length(intersect(unique(data$iso3c), stats::na.omit(dt$iso3c)))
  } else 0L
  pol <- dispute_policy()
  paste0(
    "Disputed territories: ", n_marked, " marked, ",
    sum(is.na(dt$iso3c)), " untracked (no ISO code). Convention: ", pol, "."
  )
}

#' Fill missing values, and say that you did
#'
#' Interpolate or carry forward missing observations in a panel. Every value this
#' invents is flagged in a companion column, and that flag is **not optional** --
#' an imputed value that travels through a pipeline looking like data is exactly
#' the failure this package exists to prevent.
#'
#' @param data A panel with `iso3c` and `year`.
#' @param value Column(s) to fill (character). `NULL` fills every numeric column
#'   except `year`.
#' @param method `"linear"` (default, interior gaps only), `"locf"` (carry the
#'   last observation forward) or `"none"`.
#' @param max_gap Longest run of consecutive missing years to fill. Gaps longer
#'   than this are left alone, because interpolating across a decade is not
#'   interpolation. Default `3`.
#'
#' @return `data` with the gaps filled and, for each filled column, a logical
#'   `<column>_imputed` companion. The map verbs count those *columns* when they
#'   write provenance, so they keep working through any verb that preserves
#'   columns. An `"countryatlas_imputed"` attribute lists the flag columns for
#'   convenience, but nothing in the package reads it, and `dplyr` drops it as
#'   it drops most attributes -- rely on the columns, not the attribute. Rows
#'   come back sorted by `iso3c` then `year`.
#'
#' @section The hard rule:
#' The flag cannot be turned off. [world_map()] reads it and refuses to draw
#' imputed values as though they were observed without at least noting it in the
#' caption. If you need values with no flag, compute them yourself -- the
#' package will not hand you a frame where invented numbers are indistinguishable
#' from measured ones.
#'
#' @seealso [complete_years()], [rate_check()], [coverage_map()]
#' @export
#' @examples
#' p <- data.frame(iso3c = "USA", year = 2000:2005,
#'                 gdp = c(1, NA, NA, 4, NA, 6))
#' interpolate_missing(p, "gdp")
interpolate_missing <- function(data, value = NULL,
                                method = c("linear", "locf", "none"),
                                max_gap = 3) {
  method <- rlang::arg_match(method)
  check_number(max_gap, "max_gap", lo = 1, hi = .Machine$integer.max)
  max_gap <- as.integer(max_gap)
  if (!all(c("iso3c", "year") %in% names(data))) {
    wdj_abort("{.arg data} must have {.field iso3c} and {.field year} columns.")
  }
  # A repeated country-year is not just a wrong lag here: stats::approx()
  # collapses tied x-values to their mean, so the two rows for that year are
  # *overwritten* with the average -- 20 and 999 both became 509.5 -- and the
  # `_imputed` flag says FALSE for them, because it compares "was NA" against
  # "is not NA" and neither was ever NA. The comparison below is documented as
  # catching a filler that changes an observed value; it cannot catch this one,
  # so the malformed input has to be reported instead.
  # This function used to carry its own duplicate-column-name guard as well,
  # which became unreachable once check_panel_unique() grew one; coverage
  # showed the block never running, so it is gone. Note the name check is
  # belt-and-braces -- a validator further down rejects duplicate names too,
  # so removing this call still errors on them. What only this call catches is
  # the duplicate *row* case above, which is why it stays.
  check_panel_unique(data)
  measures <- setdiff(names(data)[vapply(data, is.numeric, logical(1))], "year")
  value_expr <- substitute(value)
  value <- tryCatch(value %||% measures, error = function(e) {
    abort_bare_column(value_expr, "value", e)
  })
  check_cols(data, value)
  # "Do not interpolate" still has to return the same shape as the other two
  # methods: a bare `data` here leaked an incoming grouping and gave back a
  # data.frame where `method = "linear"` gives a tibble.
  if (identical(method, "none")) return(wdj_return_frame(data))
  # Only "linear" cares about the year's type: it interpolates *on* the year
  # via approx(), so a labelled year column reached approx() as NA and surfaced
  # its "need at least two non-NA values to interpolate" wrapped in a dplyr
  # across() error, naming neither the column nor its type. "locf" carries the
  # last value forward in row order and needs no arithmetic, so guarding it
  # would reject input it handles correctly.
  #
  # Coercibility, not check_numeric_col(): approx() reads "2000" happily, so a
  # character year works here and demanding is.numeric() would refuse input
  # this verb has always handled. That is the difference from deflate() and
  # beta_convergence(), which do the arithmetic themselves.
  if (identical(method, "linear")) {
    yr <- suppressWarnings(as.numeric(as.character(data$year)))
    unreadable <- unique(as.character(data$year)[!is.na(data$year) & is.na(yr)])
    if (length(unreadable)) {
      wdj_abort(c(
        "{.field year} must be readable as a number for
         {.code method = \"linear\"}.",
        "x" = "{length(unreadable)} value{?s} {?is/are} not:
               {.val {utils::head(unreadable, 5)}}.",
        "i" = "Linear interpolation places the filled value *along* the year
               axis. {.code method = \"locf\"} carries the last value forward
               and needs no arithmetic."
      ))
    }
  }

  flags <- paste0(value, "_imputed")
  # Warn only about a flag column we cannot carry forward. A logical one is
  # this function's own provenance record and is preserved below, so
  # warn_overwrite()'s "rename them first to keep the original values" would be
  # false advice; anything else really is being clobbered.
  warn_overwrite(data, flags[vapply(flags, function(f)
    f %in% names(data) && !is.logical(data[[f]]), logical(1))])
  # "This value was imputed" is a property of the data, not of the call that
  # produced it. Running interpolate_missing() twice on the same column
  # recomputed the flag from scratch, and the cells the first call filled are
  # no longer NA -- so every TRUE became FALSE and the flag was, in effect,
  # turned off. The documented hard rule is that it cannot be, and world_map()
  # relies on that to avoid drawing imputed values as observed with no caption.
  # Carried as a column for the same reason the "was missing" flags below are:
  # the pipeline arranges by (iso3c, year), so a vector held aside would land
  # the old flags on the wrong rows.
  prior <- paste0(".countryatlas_prior_", flags)
  for (i in seq_along(flags)) {
    p <- if (flags[i] %in% names(data)) data[[flags[i]]] else NULL
    data[[prior[i]]] <- if (is.logical(p)) !is.na(p) & p else FALSE
  }
  # Record "was missing" as columns, so it travels with the rows. It used to be
  # captured as plain vectors off `data` and compared against `out` further
  # down -- but the pipeline below arranges by (iso3c, year), so the two lined
  # up only when the caller happened to hand over an already-sorted frame. On
  # anything else the flags landed on the wrong rows: observed values came back
  # marked imputed and imputed ones came back marked observed, and world_map()
  # believes this column when it writes its caption.
  for (i in seq_along(value)) data[[flags[i]]] <- is.na(data[[value[i]]])

  out <- data %>%
    group_by_unit() %>%
    dplyr::arrange(year_sort_key(.data$year), .by_group = TRUE) %>%
    dplyr::mutate(dplyr::across(
      dplyr::all_of(value),
      ~ fill_capped(.data$year, .x, method, max_gap)
    )) %>%
    dplyr::ungroup()

  # Flag exactly the cells that were NA before and are not now. Computed by
  # comparison rather than tracked inside the filler, so a filler that ever
  # changes an observed value would show up here as a flagged cell.
  for (i in seq_along(value)) {
    out[[flags[i]]] <- (out[[flags[i]]] & !is.na(out[[value[i]]])) | out[[prior[i]]]
  }
  # ".wdj_unit" alongside the prior-flag columns: this verb returns the result
  # of its own column surgery rather than wdj_return_frame(), which is where
  # the key is normally dropped.
  out <- out[, setdiff(names(out), c(prior, ".wdj_unit")), drop = FALSE]
  attr(out, "countryatlas_imputed") <- flags
  out
}

# Fill a single country's series, refusing runs longer than max_gap.
fill_capped <- function(x, y, method, max_gap) {
  na <- is.na(y)
  if (!any(na) || sum(!na) < 1L) return(y)
  # Identify runs of NA, so an over-long gap stays empty. Measured in *years*,
  # not in rows: max_gap is documented as "the longest run of consecutive
  # missing years ... because interpolating across a decade is not
  # interpolation", and counting rows defeats that on any panel that is not
  # annual. A decadal panel of 2000, 2010, 2020 with 2010 missing is one
  # missing row, so the default max_gap = 3 filled it -- inventing a value 10
  # years from either anchor, which is the exact thing the parameter exists to
  # refuse. Five-yearly data spanned 15 years the same way.
  #
  # The span is the distance between the observations that bracket the run,
  # which on an annual panel equals the number of missing rows exactly, so
  # annual behaviour is unchanged. A run with an observation on only one side
  # is measured from that side, which is what LOCF carrying forward cares
  # about. A non-numeric year (read.csv gives "2000", and this verb otherwise
  # tolerates it) falls back to the row count rather than erroring.
  r <- rle(na)
  keep <- rep(TRUE, length(y))
  xn <- suppressWarnings(as.numeric(as.character(x)))
  if (anyNA(xn)) xn <- NULL
  pos <- 1L
  for (i in seq_along(r$lengths)) {
    if (r$values[i]) {
      lo <- pos
      hi <- pos + r$lengths[i] - 1L
      # Two conditions, because one alone gets a case wrong.
      #
      # The run length in rows is what an annual panel means by "consecutive
      # missing years", and keeping it preserves annual behaviour exactly.
      #
      # The years condition is how far the invented value actually sits from
      # real data: the distance from each filled year to its *nearest*
      # observation. Measuring the bracketing span instead punishes a point
      # that is close to one anchor merely because the other is distant --
      # 2000, 2001, 2005 with 2001 missing spans five years, but the filled
      # point is one year from 2000 and interpolating it is perfectly sound.
      # The nearest-anchor distance catches what matters: 2000, 2010, 2020
      # with 2010 missing puts the invented value ten years from anything
      # observed, which is the "interpolating across a decade" the parameter
      # exists to refuse.
      too_long <- r$lengths[i] > max_gap
      if (!too_long && !is.null(xn)) {
        prev_obs <- if (lo > 1L) xn[lo - 1L] else NA_real_
        next_obs <- if (hi < length(xn)) xn[hi + 1L] else NA_real_
        gap_yrs <- vapply(lo:hi, function(j) {
          min(c(if (!is.na(prev_obs)) xn[j] - prev_obs,
                if (!is.na(next_obs)) next_obs - xn[j]), Inf)
        }, numeric(1))
        too_long <- anyNA(gap_yrs) || max(gap_yrs) > max_gap
      }
      if (too_long) keep[lo:hi] <- FALSE
    }
    pos <- pos + r$lengths[i]
  }
  filled <- if (identical(method, "linear")) {
    wdj_interp_linear(x, y)
  } else {
    # LOCF, without pulling in another dependency. Assignment rather than
    # ifelse() so the fill keeps whatever type arrived; positions before the
    # first observation are left holding y's own typed NA.
    idx <- cumsum(!is.na(y))
    seen <- idx > 0L
    out <- y
    out[seen] <- y[!is.na(y)][idx[seen]]
    out
  }
  # ifelse() drops attributes, so a classed column came back stripped: a Date
  # of 2020-01-01 returned as the bare number 18262. Worse, it only happened
  # when the series actually had a gap, because the no-NA path above returns
  # `y` untouched -- so the same column changed type depending on its data.
  # Assigning into a copy of `y` preserves the class through `[<-`.
  out <- y
  out[keep] <- filled[keep]
  out
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
vsup_fill <- function(value, uncertainty, n_bins = 4, n_uncertainty = 3,
                      option = "viridis", suppress = 0.85) {
  ok <- is.finite(value) & is.finite(uncertainty)
  v_rank <- rep(NA_real_, length(value))
  u_rank <- rep(NA_real_, length(value))
  if (any(ok)) {
    # Rank, not linear rescaling. Both axes here are typically skewed -- on
    # `world_snapshot`'s GDP per capita a linear stretch put 174 of 191
    # countries in the bottom bin and left most of the palette unused, which
    # defeats the entire point of a 2-D palette. Ranking also matches the
    # quantile default the rest of the package uses for choropleths.
    v_rank[ok] <- dplyr::percent_rank(value[ok])
    u_rank[ok] <- dplyr::percent_rank(uncertainty[ok])
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
  cols <- grDevices::hcl.colors(256, palette = "viridis")
  if (!identical(option, "viridis")) {
    cols <- tryCatch(grDevices::hcl.colors(256, palette = option),
                     error = function(e) cols)
  }
  fill <- rep(NA_character_, length(value))
  idx <- pmax(1L, pmin(256L, round(pos * 255) + 1L))
  fill[!is.na(idx)] <- cols[idx[!is.na(idx)]]
  list(fill = fill, v_bin = v_bin, u_bin = u_bin,
       label = ifelse(is.na(v_bin) | is.na(u_bin), NA_character_,
                      sprintf("v%d / u%d", v_bin, u_bin)))
}

# The legend: one swatch per (value, uncertainty) cell, laid out as a grid so
# the 2-D structure is visible rather than asserted.
vsup_scale <- function(vs, n_bins, n_uncertainty, value_name, uncertainty_name) {
  grid <- expand.grid(v = seq_len(n_bins), u = seq_len(n_uncertainty))
  # Compute the swatch colour from the *bin indices* directly, so the legend
  # cannot drift from the map when the data's range changes.
  centre <- (grid$v - 0.5) / n_bins
  shrink <- 1 - 0.85 * ((grid$u - 1) / max(1L, n_uncertainty - 1L))
  pos <- 0.5 + (centre - 0.5) * shrink
  cols <- grDevices::hcl.colors(256, palette = "viridis")
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
