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
  check_panel_unique(data)
  # complete_years() and audit_coverage() both reject a frame with duplicate
  # column names -- vctrs does it for them -- but this one did not, and the
  # dplyr pipeline below quietly repaired the names instead: given two columns
  # called `v` it filled the first and handed back the second as `v.1`, a
  # column the caller never created and was never told about.
  dup_names <- unique(names(data)[duplicated(names(data))])
  if (length(dup_names)) {
    wdj_abort(c(
      "{.arg data} has {length(dup_names)} duplicated column name{?s}:",
      "*" = "{.val {dup_names}}",
      "i" = "Rename or drop the duplicate -- which one to fill is ambiguous."
    ))
  }
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

  flags <- paste0(value, "_imputed")
  warn_overwrite(data, flags)
  # Record "was missing" as columns, so it travels with the rows. It used to be
  # captured as plain vectors off `data` and compared against `out` further
  # down -- but the pipeline below arranges by (iso3c, year), so the two lined
  # up only when the caller happened to hand over an already-sorted frame. On
  # anything else the flags landed on the wrong rows: observed values came back
  # marked imputed and imputed ones came back marked observed, and world_map()
  # believes this column when it writes its caption.
  for (i in seq_along(value)) data[[flags[i]]] <- is.na(data[[value[i]]])

  out <- data %>%
    dplyr::group_by(.data$iso3c) %>%
    dplyr::arrange(.data$year, .by_group = TRUE) %>%
    dplyr::mutate(dplyr::across(
      dplyr::all_of(value),
      ~ fill_capped(.data$year, .x, method, max_gap)
    )) %>%
    dplyr::ungroup()

  # Flag exactly the cells that were NA before and are not now. Computed by
  # comparison rather than tracked inside the filler, so a filler that ever
  # changes an observed value would show up here as a flagged cell.
  for (i in seq_along(value)) {
    out[[flags[i]]] <- out[[flags[i]]] & !is.na(out[[value[i]]])
  }
  attr(out, "countryatlas_imputed") <- flags
  out
}

# Fill a single country's series, refusing runs longer than max_gap.
fill_capped <- function(x, y, method, max_gap) {
  na <- is.na(y)
  if (!any(na) || sum(!na) < 1L) return(y)
  # Identify runs of NA and their lengths, so an over-long gap stays empty.
  r <- rle(na)
  keep <- rep(TRUE, length(y))
  pos <- 1L
  for (i in seq_along(r$lengths)) {
    if (r$values[i] && r$lengths[i] > max_gap) {
      keep[pos:(pos + r$lengths[i] - 1L)] <- FALSE
    }
    pos <- pos + r$lengths[i]
  }
  filled <- if (identical(method, "linear")) {
    wdj_interp_linear(x, y)
  } else {
    # LOCF, without pulling in another dependency.
    idx <- cumsum(!is.na(y))
    ifelse(idx == 0L, NA, y[!is.na(y)][pmax(idx, 1L)])
  }
  ifelse(keep, filled, y)
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
