# Analysis helpers --------------------------------------------------------------

#' Normalise an indicator by population
#'
#' Removes the "is this map just a population map?" footgun by dividing a value
#' column by population. If no population column is supplied, `SP.POP.TOTL` is
#' pulled automatically for the relevant countries and years.
#'
#' @param data A country-level (or panel) data frame with `iso3c`.
#' @param value The value column to normalise (unquoted).
#' @param pop Optional population column (unquoted). If absent, population is
#'   fetched from WDI.
#' @param suffix Suffix for the new column (default `"_per_capita"`).
#' @param cache Whether to use the WDI cache when fetching population.
#'
#' @return `data` with a new per-capita column.
#' @export
#' @examples
#' df <- data.frame(iso3c = c("USA", "CHN"), year = 2020L,
#'                  co2 = c(5e6, 1e7), pop = c(331e6, 1402e6))
#' per_capita(df, co2, pop)
per_capita <- function(data, value, pop = NULL, suffix = "_per_capita",
                       cache = TRUE) {
  check_bool(cache, "cache")
  val_name <- quo_arg_name(rlang::enquo(value), "value")
  if (!val_name %in% names(data)) {
    wdj_abort("Column {.val {val_name}} not found in {.arg data}.")
  }
  check_numeric_col(data, val_name)
  pop_q <- rlang::enquo(pop)
  if (!rlang::quo_is_null(pop_q)) {
    pop_name <- rlang::as_name(pop_q)
    pop_vec <- data[[pop_name]]
  } else {
    if (!"iso3c" %in% names(data)) {
      wdj_abort("{.arg data} needs an {.field iso3c} column to fetch population.")
    }
    years <- if ("year" %in% names(data)) unique(stats::na.omit(data$year)) else NULL
    # An all-NA (or absent) year column leaves nothing to bound the fetch with;
    # min()/max() would return Inf/-Inf and the World Bank request would be
    # nonsense. Fall back to last year, as for a frame with no year at all.
    if (!length(years)) years <- as.integer(format(Sys.Date(), "%Y")) - 1L
    popdf <- fetch_wdi(c(.wdj_pop = "SP.POP.TOTL"),
                       start = min(years), end = max(years), cache = cache)
    # A failed or empty World Bank fetch comes back as a keys-only tibble
    # (fetch_wdi() degrades rather than erroring), so say so instead of
    # dying on a "column `.wdj_pop` doesn't exist" subscript error. Check every
    # column the join below needs, `year` included, so a partial result can't
    # crash with a raw vctrs subscript error either.
    need <- c("iso3c", if ("year" %in% names(data)) "year", ".wdj_pop")
    if (!all(need %in% names(popdf)) || !nrow(popdf)) {
      wdj_abort(c(
        "Could not fetch population ({.val SP.POP.TOTL}) from the World Bank.",
        "i" = "Pass a population column with {.arg pop} to compute per-capita values offline."
      ))
    }
    # A caller's own `.wdj_pop` column would collide in the join below: dplyr
    # would suffix both sides to `.wdj_pop.x`/`.wdj_pop.y`, leaving
    # `data[[".wdj_pop"]]` NULL, and the division then failed with base R's
    # "replacement has 0 rows, data has 2". Drop it -- the fetched population is
    # what this branch is for, and the column is removed again below either way.
    data[[".wdj_pop"]] <- NULL
    if ("year" %in% names(data)) {
      data <- dplyr::left_join(data, popdf[, c("iso3c", "year", ".wdj_pop")],
                               by = c("iso3c", "year"), na_matches = "never")
    } else {
      popdf <- dplyr::distinct(popdf, .data$iso3c, .keep_all = TRUE)
      data <- dplyr::left_join(data, popdf[, c("iso3c", ".wdj_pop")], by = "iso3c",
                               na_matches = "never")
    }
    pop_vec <- data[[".wdj_pop"]]
    data[[".wdj_pop"]] <- NULL
  }

  check_string(suffix, "suffix")
  new_col <- paste0(val_name, suffix)
  warn_overwrite(data, new_col)
  data[[new_col]] <- data[[val_name]] / pop_vec
  tibble::as_tibble(data)
}

#' Roll countries up to region / income / continent
#'
#' Aggregate a country-level value to a coarser grouping, optionally with
#' population-weighted means.
#'
#' @param data A country-level data frame.
#' @param value The value column to aggregate (unquoted).
#' @param by Grouping column(s) (character), default `"region"`. Combine with
#'   `"year"` for panel roll-ups.
#' @param fun Aggregation: `"sum"` (default), `"mean"`, `"median"`, `"min"`,
#'   `"max"` or `"weighted_mean"`.
#' @param weight Optional weight column (unquoted) for `"weighted_mean"`.
#'
#' @section Groups with no data:
#' Missing values are dropped before aggregating, so a group is summarised from
#' whatever it does have. A group with *no* non-missing value returns `NA`
#' rather than a figure: `sum()` would otherwise report `0`, `mean()` `NaN` and
#' `min()`/`max()` `-Inf`/`Inf`, each of which reads as a real total for a
#' region we simply have no data for. Use [audit_coverage()] to see where those
#' gaps are.
#'
#' @return A tibble of `by` plus the aggregated value.
#' @export
#' @examples
#' df <- data.frame(iso3c = c("USA", "CAN", "BRA"),
#'                  region = c("North America", "North America", "Latin America"),
#'                  gdp = c(21, 1.7, 1.4))
#' aggregate_regions(df, gdp, fun = "sum")
aggregate_regions <- function(data, value, by = "region", fun = "sum",
                              weight = NULL) {
  val_name <- quo_arg_name(rlang::enquo(value), "value")
  fun <- match.arg(fun, c("sum", "mean", "median", "min", "max", "weighted_mean"))
  if (!is.character(by) || !length(by) || anyNA(by)) {
    wdj_abort(c("{.arg by} must name at least one grouping column.",
                "x" = if (!length(by)) "Got 0 values." else "Got {.val {by}}."))
  }
  check_cols(data, val_name)
  check_numeric_col(data, val_name)
  # A geometry-joined frame has one row per polygon vertex, so summing it counts
  # each country once per vertex -- for the bundled snapshot that turned a
  # regional total of 497,265 into 280,951,373, silently. We cannot just
  # de-duplicate on iso3c, because `by = c("region", "year")` panel roll-ups
  # legitimately have many rows per country, so say what looks wrong instead.
  if (has_map_geometry(data)) {
    wdj_warn(c(
      "{.arg data} looks like it has map geometry attached.",
      "!" = "Aggregating it counts each country once per geometry row.",
      "i" = "Aggregate the country-level table first, then attach geometry."
    ))
  }
  missing_by <- setdiff(by, names(data))
  if (length(missing_by)) {
    wdj_abort("Grouping column{?s} {.val {missing_by}} not found in {.arg data}.")
  }
  w_q <- rlang::enquo(weight)
  has_w <- !rlang::quo_is_null(w_q)
  if (fun == "weighted_mean" && !has_w) {
    wdj_abort('{.arg weight} is required when {.code fun = "weighted_mean"}.')
  }
  # The mirror image was silent: `weight` is read only by "weighted_mean", so
  # fun = "mean" with a weight returned the *unweighted* mean -- the wrong
  # number, with nothing to say so.
  if (has_w && fun != "weighted_mean") {
    wdj_abort(c(
      '{.arg weight} is only used when {.code fun = "weighted_mean"}.',
      "x" = 'Got {.code fun = "{fun}"}, which ignores it.',
      "i" = 'Pass {.code fun = "weighted_mean"} to weight, or drop {.arg weight}.'
    ))
  }

  grouped <- dplyr::group_by(data, dplyr::across(dplyr::all_of(by)))
  out <- if (fun == "weighted_mean") {
    w_name <- rlang::as_name(w_q)
    dplyr::summarise(
      grouped,
      "{val_name}" := {
        ok <- !is.na(.data[[val_name]]) & !is.na(.data[[w_name]])
        if (!any(ok)) NA_real_ else
          stats::weighted.mean(.data[[val_name]][ok], .data[[w_name]][ok])
      },
      .groups = "drop"
    )
  } else {
    # A group with no non-NA values has nothing to aggregate, and every base
    # function gets that wrong differently: sum() returns 0, mean() NaN, and
    # min()/max() -Inf/Inf with a warning. All three read as a real figure --
    # "this region's total is 0" is a claim, not an absence. NA is the honest
    # answer, and min/max already returned it; do the same for every `fun`.
    empty_is_na <- function(f) {
      function(v, na.rm = TRUE) {
        u <- if (isTRUE(na.rm)) v[!is.na(v)] else v
        if (!length(u)) return(NA_real_)
        f(u)
      }
    }
    f <- empty_is_na(switch(fun, sum = sum, mean = mean, median = stats::median,
                            min = min, max = max))
    dplyr::summarise(
      grouped,
      "{val_name}" := f(.data[[val_name]], na.rm = TRUE),
      .groups = "drop"
    )
  }
  out
}

#' Add rank, percentile and z-score
#'
#' Adds `rank`, `percentile` and `z_score` for a value column, optionally within
#' a group (region, year, ...), for "top 10" tables and labelling.
#'
#' @param data A data frame.
#' @param value The value column to rank (unquoted).
#' @param within Optional grouping column(s) (unquoted or character) to rank
#'   within.
#' @param desc Rank descending (largest = rank 1); default `TRUE`.
#'
#' @return `data` with `rank`, `percentile` and `z_score` columns added.
#' @export
#' @examples
#' df <- data.frame(iso3c = c("USA", "CHN", "IND"), gdp = c(21, 17, 3))
#' rank_countries(df, gdp)
rank_countries <- function(data, value, within = NULL, desc = TRUE) {
  check_bool(desc, "desc")
  val_name <- quo_arg_name(rlang::enquo(value), "value")
  if (!val_name %in% names(data)) {
    wdj_abort("Column {.val {val_name}} not found in {.arg data}.")
  }
  check_numeric_col(data, val_name)
  within_q <- rlang::enquo(within)
  if (!rlang::quo_is_null(within_q)) {
    within_cols <- tryCatch(
      rlang::as_name(within_q),
      error = function(e) as.character(rlang::eval_tidy(within_q))
    )
    data <- dplyr::group_by(data, dplyr::across(dplyr::all_of(within_cols)))
  } else {
    # `within` is the only thing that should decide the ranking scope. A grouped
    # frame arriving from upstream in the pipe would otherwise be honoured by
    # mutate() below, silently turning the documented global ranking into a
    # within-group one. Every other function here likewise imposes its own
    # grouping rather than inheriting the caller's.
    data <- dplyr::ungroup(data)
  }
  ord <- if (isTRUE(desc)) function(x) dplyr::desc(x) else function(x) x
  warn_overwrite(data, c("rank", "percentile", "z_score"))
  out <- dplyr::mutate(
    data,
    rank = dplyr::min_rank(ord(.data[[val_name]])),
    percentile = dplyr::percent_rank(.data[[val_name]]),
    z_score = as.numeric(scale(.data[[val_name]]))
  )
  dplyr::ungroup(out)
}

#' Fill or interpolate panel gaps
#'
#' Completes a panel so every country has every year, optionally filling missing
#' values by carry-forward (`"locf"`) or linear interpolation (`"linear"`) so
#' animations do not flicker on missing years.
#'
#' @param data A panel with `iso3c` and `year`.
#' @param years The full set of years to complete to. Defaults to the observed
#'   min:max.
#' @param value Optional value column(s) (character) to fill. If `NULL`, all
#'   numeric columns except `year` are filled.
#' @param method `"none"` (default; just complete the grid), `"locf"` or
#'   `"linear"`.
#'
#' @return A completed (and optionally filled) panel tibble.
#' @export
#' @examples
#' df <- data.frame(iso3c = "USA", year = c(2000L, 2002L), gdp = c(1, 3))
#' complete_years(df, 2000:2002, method = "linear")
complete_years <- function(data, years = NULL, value = NULL,
                           method = c("none", "locf", "linear")) {
  method <- match.arg(method)
  if (!all(c("iso3c", "year") %in% names(data))) {
    wdj_abort("{.arg data} must have {.field iso3c} and {.field year} columns.")
  }
  # A frame with no rows has no span to infer, so leave `years` alone rather
  # than reaching seq(min(numeric(0)), max(numeric(0))).
  if (is.null(years) && nrow(data)) {
    years <- seq(min(data$year), max(data$year))
  }
  # as.integer() turned a non-numeric `years` into NA with only base R's "NAs
  # introduced by coercion" warning, and a zero-length one silently completed
  # nothing. Anything the caller passed is still checked, 0 rows or not.
  if (!is.null(years)) {
    if (!is.numeric(years) || !length(years) || anyNA(years)) {
      wdj_abort(c(
        "{.arg years} must be a non-empty numeric vector without {.code NA}.",
        "x" = if (!length(years)) "Got 0 values." else "Got {.val {years}}."
      ))
    }
    years <- as.integer(years)
  }

  measures <- setdiff(names(data)[vapply(data, is.numeric, logical(1))], "year")
  if (is.null(value)) {
    value <- measures
  } else {
    check_cols(data, value)
  }

  # Nothing to complete: no countries to complete for, and no span to complete
  # over. Every other panel helper returns 0 rows for a 0-row frame; this one
  # died inside seq() on "'from' must be a finite number", or -- with `years`
  # supplied -- on tidyr's "Can't recycle `year` (size 3) to size 0".
  if (!nrow(data)) return(tibble::as_tibble(data))

  # Carry static attributes (country name, region, ...) into the rows `complete()`
  # invents. Excluding only `value` here meant a numeric column the caller left
  # out of `value` counted as an attribute and got carry-filled -- so naming
  # *fewer* columns fabricated *more* data, and even `method = "none"` ("just
  # complete the grid") invented figures. Every measure column is excluded,
  # named or not; an unnamed one stays NA in the new rows.
  static <- setdiff(names(data), c("year", measures, value))

  out <- data %>%
    dplyr::group_by(.data$iso3c) %>%
    tidyr::complete(year = years) %>%
    tidyr::fill(dplyr::all_of(setdiff(static, "iso3c")),
                .direction = "downup")

  if (method == "locf") {
    out <- tidyr::fill(out, dplyr::all_of(value), .direction = "down")
  } else if (method == "linear") {
    out <- out %>%
      dplyr::arrange(.data$year, .by_group = TRUE) %>%
      dplyr::mutate(dplyr::across(
        dplyr::all_of(value),
        ~ wdj_interp_linear(.data$year, .x)
      ))
  }
  dplyr::ungroup(out)
}

# Linear interpolation of interior NAs (no extrapolation beyond observed range).
wdj_interp_linear <- function(x, y) {
  ok <- !is.na(y)
  if (sum(ok) < 2L) return(y)
  stats::approx(x[ok], y[ok], xout = x, rule = 1)$y
}

#' Year-on-year (or compound) growth rate
#'
#' Adds a growth-rate column to a panel: either the period-over-period change
#' (`"yoy"`) or the compound annual growth rate from the first observed year
#' (`"cagr"`), computed per country.
#'
#' @param data A panel with `iso3c` and `year`.
#' @param value The value column (unquoted).
#' @param type `"yoy"` (default, period-over-period) or `"cagr"` (compound
#'   annual growth rate vs. the first non-`NA` year).
#' @param suffix Suffix for the new column (default `"_growth"`).
#'
#' @return `data` with a growth-rate column added (a proportion, so 0.03 = 3%).
#' @export
#' @examples
#' df <- data.frame(iso3c = "USA", year = 2000:2002, gdp = c(100, 110, 121))
#' growth_rate(df, gdp)
growth_rate <- function(data, value, type = c("yoy", "cagr"),
                        suffix = "_growth") {
  type <- match.arg(type)
  val_name <- quo_arg_name(rlang::enquo(value), "value")
  if (!all(c("iso3c", "year") %in% names(data))) {
    wdj_abort("{.arg data} must have {.field iso3c} and {.field year} columns.")
  }
  if (!val_name %in% names(data)) {
    wdj_abort("Column {.val {val_name}} not found in {.arg data}.")
  }
  check_numeric_col(data, val_name)
  check_string(suffix, "suffix")
  new_col <- paste0(val_name, suffix)
  warn_overwrite(data, new_col)
  out <- data %>%
    dplyr::group_by(.data$iso3c) %>%
    dplyr::arrange(.data$year, .by_group = TRUE)
  out <- if (type == "yoy") {
    dplyr::mutate(
      out,
      "{new_col}" := .data[[val_name]] / dplyr::lag(.data[[val_name]]) - 1
    )
  } else {
    dplyr::mutate(
      out,
      "{new_col}" := {
        base_i <- which(!is.na(.data[[val_name]]))[1]
        v0 <- .data[[val_name]][base_i]; y0 <- .data$year[base_i]
        n <- .data$year - y0
        ifelse(n > 0 & !is.na(v0) & v0 > 0,
               (.data[[val_name]] / v0)^(1 / n) - 1, NA_real_)
      }
    )
  }
  dplyr::ungroup(out)
}

#' Rebase a series to an index (base year = 100)
#'
#' Rescales a value column so the chosen base year equals `to` (100 by default),
#' per country -- the standard way to compare trajectories that start at very
#' different levels.
#'
#' @param data A panel with `iso3c` and `year`.
#' @param value The value column (unquoted).
#' @param base_year The year set equal to `to`.
#' @param to The index value the base year maps to (default `100`).
#' @param suffix Suffix for the new column (default `"_index"`).
#'
#' @return `data` with an index column added.
#' @export
#' @examples
#' df <- data.frame(iso3c = "USA", year = 2000:2002, gdp = c(50, 55, 60))
#' index_to(df, gdp, base_year = 2000)
index_to <- function(data, value, base_year, to = 100, suffix = "_index") {
  val_name <- quo_arg_name(rlang::enquo(value), "value")
  check_panel_cols(data, val_name)
  check_numeric_col(data, val_name)
  check_number(base_year, "base_year")
  check_number(to, "to")
  check_string(suffix, "suffix")
  new_col <- paste0(val_name, suffix)
  warn_overwrite(data, new_col)
  out <- data %>%
    dplyr::group_by(.data$iso3c) %>%
    dplyr::mutate(
      "{new_col}" := {
        base <- .data[[val_name]][.data$year == base_year][1]
        if (length(base) == 0L || is.na(base) || base == 0) NA_real_
        else .data[[val_name]] / base * to
      }
    )
  dplyr::ungroup(out)
}

#' Pairwise correlation of indicators on the spine
#'
#' Which indicators move together across countries? Computes pairwise
#' correlations between indicator columns (pairwise-complete, so patchy
#' coverage doesn't shrink every pair to the common subset), with the per-pair
#' `n` reported so a headline `r` computed on 12 countries can't masquerade as
#' a world fact.
#'
#' @param data A country-level (or map-ready) data frame; map-ready frames are
#'   reduced to one row per country first, so the reported `n` counts countries
#'   rather than geometry rows.
#' @param ... <[`tidy-select`][dplyr::dplyr_tidy_select]> Indicator columns to
#'   correlate. If empty, all numeric columns except coordinates, `year` and
#'   other structural columns are used.
#' @param method `"pearson"` (default) or `"spearman"`.
#' @param min_n Minimum number of complete pairs for a correlation to be
#'   reported (default `3`).
#'
#' @return A tibble with one row per indicator pair: `var_x`, `var_y`, `r`,
#'   `n` (complete pairs), sorted by `|r|` descending.
#' @export
#' @examples
#' correlate_indicators(countryatlas::world_snapshot$countries)
correlate_indicators <- function(data, ..., method = c("pearson", "spearman"),
                                 min_n = 3) {
  # An NA gave "missing value where TRUE/FALSE needed" and a length-2 value "the
  # condition has length > 1" -- the tell-tale unchecked-scalar messages.
  check_number(min_n, "min_n", lo = 1, hi = .Machine$integer.max)
  method <- match.arg(method)
  data <- tibble::as_tibble(data)
  # One row per country. Gating on `group` only caught polygon frames; an sf
  # frame has no `group` column yet still repeats divided countries (Cyprus at
  # 110m), which inflated the reported `n` -- the very number this function
  # exists to keep honest.
  if ("iso3c" %in% names(data)) {
    data <- dplyr::distinct(data, .data$iso3c, .keep_all = TRUE)
  }
  sel <- rlang::enquos(...)
  if (length(sel)) {
    vals <- dplyr::select(data, !!!sel)
  } else {
    num <- names(data)[vapply(data, is.numeric, logical(1))]
    keep <- setdiff(num, c("year", "long", "lat", "group", "order",
                           "centroid_lon", "centroid_lat", "row", "col"))
    vals <- data[, keep, drop = FALSE]
  }
  bad <- names(vals)[!vapply(vals, is.numeric, logical(1))]
  if (length(bad)) {
    wdj_abort("Column{?s} {.val {bad}} {?is/are} not numeric.")
  }
  if (ncol(vals) < 2L) {
    wdj_abort("Need at least two numeric indicator columns to correlate.")
  }
  nms <- names(vals)
  pairs <- utils::combn(nms, 2, simplify = FALSE)
  out <- lapply(pairs, function(p) {
    x <- vals[[p[1]]]; y <- vals[[p[2]]]
    ok <- is.finite(x) & is.finite(y)
    n <- sum(ok)
    r <- if (n >= min_n) {
      suppressWarnings(stats::cor(x[ok], y[ok], method = method))
    } else {
      NA_real_
    }
    tibble::tibble(var_x = p[1], var_y = p[2], r = r, n = n)
  })
  out <- dplyr::bind_rows(out)
  out[order(-abs(out$r), na.last = TRUE), ]
}

#' Panel lag / difference by country
#'
#' The two panel primitives everyone hand-rolls (and gets subtly wrong when the
#' frame isn't sorted): the value `n` years back, and the change since then --
#' grouped by `iso3c`, ordered by `year`, so country A's 1960 never leaks into
#' country B's first row.
#'
#' @param data A panel with `iso3c` and `year`.
#' @param value The value column (unquoted).
#' @param n Number of periods to lag / difference over (default `1`).
#' @param suffix Suffix for the new column. Defaults to `"_lag"` / `"_diff"`
#'   (with `n` appended when `n > 1`, e.g. `"_lag5"`).
#'
#' @return `data` with the lagged / differenced column added.
#' @export
#' @examples
#' df <- data.frame(iso3c = "USA", year = 2000:2003, gdp = c(100, 110, 121, 133))
#' lag_by_country(df, gdp)
#' diff_by_country(df, gdp)
lag_by_country <- function(data, value, n = 1, suffix = NULL) {
  val_name <- quo_arg_name(rlang::enquo(value), "value")
  check_panel_cols(data, val_name)
  check_number(n, "n", lo = 1, hi = .Machine$integer.max)
  n <- as.integer(n)
  if (!is.null(suffix)) check_string(suffix, "suffix")
  new_col <- paste0(val_name, suffix %||% paste0("_lag", if (n > 1L) n else ""))
  warn_overwrite(data, new_col)
  out <- data %>%
    dplyr::group_by(.data$iso3c) %>%
    dplyr::arrange(.data$year, .by_group = TRUE) %>%
    dplyr::mutate("{new_col}" := dplyr::lag(.data[[val_name]], n = n))
  dplyr::ungroup(out)
}

#' @rdname lag_by_country
#' @export
diff_by_country <- function(data, value, n = 1, suffix = NULL) {
  val_name <- quo_arg_name(rlang::enquo(value), "value")
  check_panel_cols(data, val_name)
  check_numeric_col(data, val_name)
  check_number(n, "n", lo = 1, hi = .Machine$integer.max)
  n <- as.integer(n)
  if (!is.null(suffix)) check_string(suffix, "suffix")
  new_col <- paste0(val_name, suffix %||% paste0("_diff", if (n > 1L) n else ""))
  warn_overwrite(data, new_col)
  out <- data %>%
    dplyr::group_by(.data$iso3c) %>%
    dplyr::arrange(.data$year, .by_group = TRUE) %>%
    dplyr::mutate(
      "{new_col}" := .data[[val_name]] - dplyr::lag(.data[[val_name]], n = n)
    )
  dplyr::ungroup(out)
}

# Shared validation for the panel helpers.
check_panel_cols <- function(data, val_name, call = rlang::caller_env()) {
  if (!all(c("iso3c", "year") %in% names(data))) {
    wdj_abort("{.arg data} must have {.field iso3c} and {.field year} columns.",
              call = call)
  }
  if (!val_name %in% names(data)) {
    wdj_abort("Column {.val {val_name}} not found in {.arg data}.", call = call)
  }
  invisible(TRUE)
}

#' Beta convergence (growth regression)
#'
#' Do poor countries grow faster than rich ones? The classic unconditional
#' beta-convergence test: each country's average log growth rate is regressed
#' on its log *initial* level. A significantly negative `beta` is convergence;
#' the implied convergence `speed` and `half_life` (years to close half the
#' gap) are derived from it.
#'
#' @param data A panel with `iso3c` and `year`.
#' @param value The value column (unquoted); must be positive (log scale).
#'
#' @return A one-row tibble: `beta`, `se`, `t_value`, `p_value`, `r_squared`,
#'   `n` (countries), `speed` (annual convergence rate, `NA` when `beta >= 0`)
#'   and `half_life` (years). The fitted [lm] object is attached as the
#'   `"model"` attribute.
#' @export
#' @seealso [sigma_convergence()] for the dispersion-over-time counterpart.
#' @examples
#' set.seed(1)
#' start <- runif(20, 6, 11)                              # log initial level
#' growth <- 0.05 - 0.004 * start + rnorm(20, 0, 0.002)   # poorer grow faster
#' panel <- data.frame(
#'   iso3c = rep(sprintf("C%02d", 1:20), each = 2),
#'   year  = rep(c(2000L, 2020L), 20),
#'   gdp   = as.vector(rbind(exp(start), exp(start + growth * 20)))
#' )
#' beta_convergence(panel, gdp)
beta_convergence <- function(data, value) {
  val_name <- quo_arg_name(rlang::enquo(value), "value")
  check_panel_cols(data, val_name)
  check_numeric_col(data, val_name)

  per_country <- data %>%
    dplyr::filter(!is.na(.data[[val_name]]), .data[[val_name]] > 0) %>%
    dplyr::group_by(.data$iso3c) %>%
    dplyr::arrange(.data$year, .by_group = TRUE) %>%
    dplyr::summarise(
      y0 = dplyr::first(.data$year),
      y1 = dplyr::last(.data$year),
      v0 = dplyr::first(.data[[val_name]]),
      v1 = dplyr::last(.data[[val_name]]),
      .groups = "drop"
    ) %>%
    dplyr::filter(.data$y1 > .data$y0)

  if (nrow(per_country) < 3L) {
    wdj_abort(c(
      "Not enough countries with two positive observations to run the regression.",
      "i" = "Got {nrow(per_country)}; need at least 3."
    ))
  }
  growth <- (log(per_country$v1) - log(per_country$v0)) /
    (per_country$y1 - per_country$y0)
  log_v0 <- log(per_country$v0)
  fit <- stats::lm(growth ~ log_v0)
  co <- summary(fit)$coefficients
  # With no spread in the initial levels the predictor is constant, so lm()
  # returns an NA coefficient and summary() drops the row entirely -- which
  # surfaced as a bare "subscript out of bounds" from the lookup below.
  if (!"log_v0" %in% rownames(co)) {
    wdj_abort(c(
      "Cannot estimate a convergence rate: the initial levels have no spread.",
      "x" = "Every country starts at the same value of {.field {val_name}}.",
      "i" = "Beta convergence regresses growth on the initial level, so that level has to vary across countries."
    ))
  }
  beta <- co["log_v0", "Estimate"]
  span <- mean(per_country$y1 - per_country$y0)
  # Implied annual convergence speed: beta = -(1 - exp(-lambda * T)) / T.
  speed <- if (beta < 0 && (1 + beta * span) > 0) {
    -log(1 + beta * span) / span
  } else {
    NA_real_
  }
  out <- tibble::tibble(
    beta = beta,
    se = co["log_v0", "Std. Error"],
    t_value = co["log_v0", "t value"],
    p_value = co["log_v0", "Pr(>|t|)"],
    r_squared = summary(fit)$r.squared,
    n = nrow(per_country),
    speed = speed,
    half_life = if (is.na(speed)) NA_real_ else log(2) / speed
  )
  attr(out, "model") <- fit
  out
}

#' Sigma convergence (dispersion over time)
#'
#' Is the cross-country distribution actually narrowing? Reports the dispersion
#' of a (positive) indicator across countries for every year of a panel --
#' falling dispersion is sigma convergence. The natural companion to
#' [beta_convergence()]: beta convergence is necessary but not sufficient for
#' sigma convergence.
#'
#' @param data A panel with `iso3c` and `year`.
#' @param value The value column (unquoted).
#' @param measure `"sd_log"` (default; standard deviation of log values, the
#'   standard choice) or `"cv"` (coefficient of variation).
#'
#' @return A tibble with one row per year: `year`, `n` (countries with
#'   positive values) and `sigma`.
#' @export
#' @seealso [beta_convergence()] for the growth-regression counterpart.
#' @examples
#' df <- data.frame(
#'   iso3c = rep(c("A", "B", "C"), 2),
#'   year = rep(c(2000L, 2010L), each = 3),
#'   gdp = c(1, 10, 100, 2, 11, 60)   # dispersion falls
#' )
#' sigma_convergence(df, gdp)
sigma_convergence <- function(data, value, measure = c("sd_log", "cv")) {
  measure <- match.arg(measure)
  val_name <- quo_arg_name(rlang::enquo(value), "value")
  check_panel_cols(data, val_name)
  check_numeric_col(data, val_name)
  data %>%
    dplyr::filter(!is.na(.data[[val_name]]), .data[[val_name]] > 0) %>%
    dplyr::group_by(.data$year) %>%
    dplyr::summarise(
      n = dplyr::n(),
      sigma = if (measure == "sd_log") {
        stats::sd(log(.data[[val_name]]))
      } else {
        stats::sd(.data[[val_name]]) / mean(.data[[val_name]])
      },
      .groups = "drop"
    ) %>%
    dplyr::arrange(.data$year)
}

#' Gini coefficient (population-weightable)
#'
#' The Gini index of inequality across countries, optionally weighted (weight
#' by population and the statistic describes inequality between *people*
#' assigned their country's mean, not between country units).
#'
#' @param x A numeric vector (e.g. GDP per capita by country).
#' @param weights Optional non-negative weights (e.g. population), either the
#'   same length as `x` or length 1. `NULL` (default) weights all values
#'   equally.
#' @param na.rm Whether to drop `NA` values (pairwise with their weight;
#'   default `TRUE`).
#'
#' @return A single number in `[0, 1]`: `0` is perfect equality.
#' @export
#' @seealso [theil()], which adds a between/within-group decomposition.
#' @examples
#' snap <- countryatlas::world_snapshot$countries
#' gini(snap$gdp_per_capita)                          # between countries
#' gini(snap$gdp_per_capita, weights = snap$population)  # between people
gini <- function(x, weights = NULL, na.rm = TRUE) {
  check_bool(na.rm, "na.rm")
  if (!is.numeric(x)) {
    wdj_abort("{.arg x} must be numeric, not {.obj_type_friendly {x}}.")
  }
  if (!is.null(weights)) {
    if (!is.numeric(weights)) {
      wdj_abort("{.arg weights} must be numeric, not {.obj_type_friendly {weights}}.")
    }
    check_along(weights, length(x), "weights")
  }
  w <- if (is.null(weights)) rep(1, length(x)) else rep_len(as.numeric(weights),
                                                            length(x))
  if (isTRUE(na.rm)) {
    ok <- !is.na(x) & !is.na(w)
    x <- x[ok]; w <- w[ok]
  }
  if (length(x) == 0L || anyNA(x) || anyNA(w)) return(NA_real_)
  if (any(w < 0)) wdj_abort("{.arg weights} must be non-negative.")
  # Inf survives na.rm (it is not NA) and then poisons the mean, so the answer
  # came back as a silent NaN. Every other verb propagates an infinity visibly --
  # Inf in, Inf out -- but an inequality index has no such value to report, and
  # the package's convention is NA plus a word about why (as for zero weights).
  # is.infinite() rather than !is.finite(): NA/NaN are handled above.
  if (any(is.infinite(x)) || any(is.infinite(w))) {
    wdj_warn("{.arg x} has infinite values; Gini is undefined. Returning {.code NA}.")
    return(NA_real_)
  }
  if (any(x < 0)) { wdj_warn("{.arg x} has negative values; Gini needs x >= 0. Returning {.code NA}."); return(NA_real_) }
  sw <- sum(w)
  mu <- sum(w * x) / sw
  if (sw == 0 || mu <= 0) return(NA_real_)
  # Weighted mean absolute difference, sum_{i,j} w_i w_j |x_i - x_j|, computed
  # from the sorted cumulative sums. The direct pairwise form this replaces
  # built an n-by-n matrix via outer(): fine for the ~200 countries gini() is
  # written for, but it is exported and takes any numeric vector, and a
  # geometry-joined column (99,338 polygon rows) needs ~79 GB -- which killed
  # the R process outright, with no error to explain it. This form is O(n log n)
  # in time and O(n) in memory, and agrees with the pairwise version to
  # floating-point noise (ties, zero weights and single values included).
  o <- order(x)
  xs <- x[o]
  ws <- w[o]
  cw <- cumsum(ws)
  cwx <- cumsum(ws * xs)
  # Each i contributes w_i x_i * W_(<i) - w_i * sum_(j<i) w_j x_j. Writing that
  # with the inclusive cumulative sums leaves a +/- w_i^2 x_i pair that cancels,
  # so the self-terms need no separate correction.
  num <- 2 * sum(ws * (xs * cw - cwx))
  num / (2 * sw^2 * mu)
}

#' Theil index, with between/within decomposition
#'
#' The Theil T inequality index -- less famous than Gini, but it decomposes
#' *exactly* into a between-group and a within-group component, answering "how
#' much of world inequality is between continents vs within them?" in one
#' call. Weight by population to describe inequality between people rather
#' than between country units.
#'
#' @param x A positive numeric vector (log scale; zero/negative values are
#'   dropped with a warning).
#' @param weights Optional non-negative weights (e.g. population), either the
#'   same length as `x` or length 1.
#' @param groups Optional grouping vector (e.g. continent), the same length as
#'   `x` (or length 1). When supplied, the decomposition is returned instead of
#'   the scalar. A row whose group is missing is dropped along with the rows
#'   whose value is missing, so the decomposition's `total` is computed over the
#'   grouped subset and can differ from the ungrouped `theil(x)`. For
#'   `world_snapshot`, Puerto Rico has no `region`, which is the whole of the
#'   difference there.
#' @param na.rm Whether to drop `NA` values (default `TRUE`).
#'
#' @return Without `groups`: a single non-negative number (`0` = perfect
#'   equality). With `groups`: a tibble with components `"total"`,
#'   `"between"` and `"within"` (`total = between + within`) and each
#'   component's `share` of the total (`NA` when the total is `0`, i.e.
#'   perfect equality, and the shares are undefined).
#'
#'   When there is nothing to compute -- no values left after `na.rm`, a zero
#'   total weight, or an infinity in `x` or `weights` -- the result is a single
#'   `NA` whatever `groups` says, so reach for the components only after checking
#'   `is.data.frame()`.
#' @export
#' @seealso [gini()] for the more familiar single-number summary, which does not
#'   decompose.
#' @examples
#' snap <- countryatlas::world_snapshot$countries
#' theil(snap$gdp_per_capita, weights = snap$population)
#' theil(snap$gdp_per_capita, weights = snap$population, groups = snap$continent)
theil <- function(x, weights = NULL, groups = NULL, na.rm = TRUE) {
  check_bool(na.rm, "na.rm")
  if (!is.numeric(x)) {
    wdj_abort("{.arg x} must be numeric, not {.obj_type_friendly {x}}.")
  }
  if (!is.null(weights)) {
    if (!is.numeric(weights)) {
      wdj_abort("{.arg weights} must be numeric, not {.obj_type_friendly {weights}}.")
    }
    check_along(weights, length(x), "weights")
  }
  if (!is.null(groups)) check_along(groups, length(x), "groups")
  w <- if (is.null(weights)) rep(1, length(x)) else rep_len(as.numeric(weights),
                                                            length(x))
  g <- if (is.null(groups)) NULL else rep_len(as.character(groups), length(x))
  if (isTRUE(na.rm)) {
    ok <- !is.na(x) & !is.na(w) & (if (is.null(g)) TRUE else !is.na(g))
    x <- x[ok]; w <- w[ok]; g <- g[ok]
  }
  # See gini(): +Inf passes na.rm and the non-positive filter, then makes every
  # share Inf/Inf, so the total came back a silent NaN.
  if (any(is.infinite(x)) || any(is.infinite(w))) {
    wdj_warn("{.arg x} has infinite values; Theil is undefined. Returning {.code NA}.")
    return(NA_real_)
  }
  bad <- x <= 0
  if (any(bad, na.rm = TRUE)) {
    wdj_warn("Dropping {sum(bad)} non-positive value{?s} (Theil needs x > 0).")
    x <- x[!bad]; w <- w[!bad]; g <- g[!bad]
  }
  if (length(x) == 0L || anyNA(x) || anyNA(w)) return(NA_real_)
  if (any(w < 0)) wdj_abort("{.arg weights} must be non-negative.")
  sw <- sum(w)
  # All-zero weights leave every share 0/0; NA is the honest answer (gini()
  # guards the same way).
  if (sw == 0) return(NA_real_)
  mu <- sum(w * x) / sw
  theil_t <- function(x, w, sw, mu) sum((w / sw) * (x / mu) * log(x / mu))
  total <- theil_t(x, w, sw, mu)
  if (is.null(g)) return(total)

  parts <- lapply(split(seq_along(x), g), function(i) {
    swg <- sum(w[i]); mug <- sum(w[i] * x[i]) / swg
    tibble::tibble(
      between = (swg / sw) * (mug / mu) * log(mug / mu),
      within = (swg / sw) * (mug / mu) * theil_t(x[i], w[i], swg, mug)
    )
  })
  parts <- dplyr::bind_rows(parts)
  between <- sum(parts$between)
  within <- sum(parts$within)
  # Perfect equality gives total == 0, and 0/0 shares are undefined, not NaN.
  share <- if (total == 0) c(NA_real_, NA_real_, NA_real_) else
    c(1, between / total, within / total)
  tibble::tibble(
    component = c("total", "between", "within"),
    value = c(total, between, within),
    share = share
  )
}

#' Each country's share of the world total
#'
#' Adds a column giving each country's value as a share of the (year's) world
#' total -- e.g. share of global emissions or GDP. Operates within `year` when a
#' panel is supplied. A `dplyr` grouping on `data` is ignored -- the denominator
#' is always the world (or the year's) total, never the group's.
#'
#' @param data A country-level (or panel) data frame.
#' @param value The value column (unquoted).
#' @param suffix Suffix for the new column (default `"_share"`).
#'
#' @return `data` with a share column added (a proportion in `[0, 1]`).
#' @export
#' @examples
#' df <- data.frame(iso3c = c("USA", "CHN"), co2 = c(5, 10))
#' share_of_world(df, co2)
share_of_world <- function(data, value, suffix = "_share") {
  val_name <- quo_arg_name(rlang::enquo(value), "value")
  if (!val_name %in% names(data)) {
    wdj_abort("Column {.val {val_name}} not found in {.arg data}.")
  }
  check_numeric_col(data, val_name)
  check_string(suffix, "suffix")
  new_col <- paste0(val_name, suffix)
  warn_overwrite(data, new_col)
  # On a grouped frame with no `year`, the sum() below is per group, so a "share
  # of the world" silently became a share of the group: grouped by continent the
  # column summed to 5 instead of 1. A panel was already safe by accident, since
  # group_by(year) replaces the caller's groups -- so warn only where it mattered.
  grouped <- inherits(data, "grouped_df")
  data <- dplyr::ungroup(data)
  has_year <- "year" %in% names(data)
  if (grouped && !has_year) {
    wdj_warn(c(
      "{.arg data} is grouped; the grouping is ignored.",
      "!" = "The share is of the world total, not the group's.",
      "i" = "For a within-group share use
             {.code mutate(x_share = x / sum(x, na.rm = TRUE))}."
    ))
  }
  out <- if (has_year) dplyr::group_by(data, .data$year) else data
  out <- dplyr::mutate(
    out,
    "{new_col}" := { .wdj_tot <- sum(.data[[val_name]], na.rm = TRUE); if (!is.finite(.wdj_tot) || .wdj_tot == 0) NA_real_ else .data[[val_name]] / .wdj_tot }
  )
  dplyr::ungroup(tibble::as_tibble(out))
}
