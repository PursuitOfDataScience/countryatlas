# Diagnostics & data quality ----------------------------------------------------

#' Pre-flight country-match report
#'
#' A report on what will and will not match before you trust the map: the
#' input, its `iso3c`, whether it `matched`, whether it is a `historical`
#' (dissolved) entity, and a `suggestion` (the closest known country name by
#' string distance) for misses. Surfaced automatically by [join_world()].
#'
#' The `historical` flag matters even for rows that *matched*: countrycode
#' silently resolves `"USSR"` to Russia's `RUS`, so Soviet-era data becomes
#' Russian data without a warning. Rows flagged `historical` should usually be
#' routed through [dissolve_country()] instead.
#'
#' @param x A vector of country names or codes.
#' @param origin How to read `x` (any countrycode origin scheme).
#' @param custom_match Overrides applied before matching (default
#'   [country_overrides()]).
#' @param suggest Whether to compute closest-name suggestions for misses
#'   (requires the optional `stringdist` package; default `TRUE`).
#'
#' @return A tibble with columns `input`, `iso3c`, `matched`, `historical`,
#'   `suggestion`.
#' @export
#' @seealso [dissolve_country()] for resolving the entities this flags as
#'   `historical` to their successor states, and [repair_country_names()] for
#'   applying the `suggestion` column automatically.
#' @examples
#' check_country_match(c("USA", "Cote d'Ivoire", "Yugoslavia", "Wakanda"))
#' # "USSR" matches (to RUS!) but is flagged historical:
#' check_country_match("USSR")
check_country_match <- function(x,
                                origin = "country.name",
                                custom_match = country_overrides(),
                                suggest = TRUE) {
  check_bool(suggest, "suggest")
  x <- as.character(x)
  iso3c <- wdj_to_iso3c(x, origin = origin, custom_match = custom_match)
  matched <- !is.na(iso3c)
  historical <- normalize_historical(x) %in% names(historical_aliases())

  suggestion <- rep(NA_character_, length(x))
  if (isTRUE(suggest) && any(!matched)) {
    known <- unique(stats::na.omit(countrycode::codelist$country.name.en))
    miss_idx <- which(!matched)
    if (has_pkg("stringdist")) {
      for (i in miss_idx) {
        if (is.na(x[i]) || !nzchar(x[i])) next
        d <- stringdist::stringdist(tolower(x[i]), tolower(known), method = "jw")
        best <- which.min(d)
        if (length(best) && d[best] < 0.35) suggestion[i] <- known[best]
      }
    } else {
      for (i in miss_idx) {
        if (is.na(x[i]) || !nzchar(x[i])) next
        d <- utils::adist(tolower(x[i]), tolower(known))[1, ]
        best <- which.min(d)
        if (length(best) && d[best] <= 3) suggestion[i] <- known[best]
      }
    }
  }

  tibble::tibble(
    input = x,
    iso3c = iso3c,
    matched = matched,
    historical = historical,
    suggestion = suggestion
  )
}

#' Coverage / missingness audit
#'
#' What is missing, before you trust the map: which countries are unmatched,
#' the `NA` rate per indicator, and which World Bank regions / income groups are
#' under-covered -- so a half-empty map is caught before it is published.
#'
#' @param data A country-level (or map-ready) data frame.
#' @param indicator Optional character vector of value columns to report `NA`
#'   rates for. If `NULL`, all numeric columns are used.
#' @param by Grouping for the coverage breakdown: `"region"` (default),
#'   `"income"` or `"continent"`.
#'
#' @return A list of class `countryatlas_coverage`, with elements `unmatched`,
#'   `na_rates` and `by_group`. It has a `print()` method, so at the console you
#'   see a formatted report rather than the raw list; reach into the elements by
#'   name to use the numbers programmatically.
#' @export
#' @examples
#' audit_coverage(countryatlas::world_snapshot$countries)
audit_coverage <- function(data,
                           indicator = NULL,
                           by = c("region", "income", "continent")) {
  by <- match.arg(by)
  data <- tibble::as_tibble(data)
  # Reduce to one row per country. Gating on `group` only caught polygon
  # frames; an sf frame has no `group` column yet still repeats divided
  # countries, which skewed both `n` and every NA rate.
  if ("iso3c" %in% names(data)) {
    data <- dplyr::distinct(data, .data$iso3c, .keep_all = TRUE)
  }

  unmatched <- if ("iso3c" %in% names(data)) {
    key <- if ("country" %in% names(data)) "country" else "iso3c"
    miss <- data[is.na(data$iso3c), , drop = FALSE]
    tibble::tibble(country = as.character(miss[[key]]))
  } else {
    tibble::tibble(country = character(0))
  }

  if (is.null(indicator)) {
    num <- names(data)[vapply(data, is.numeric, logical(1))]
    indicator <- setdiff(num, c("year", "long", "lat", "group", "order",
                                "centroid_lon", "centroid_lat"))
  } else {
    check_cols(data, indicator)
  }
  na_rates <- tibble::tibble(
    indicator = indicator,
    n = nrow(data),
    n_missing = vapply(indicator, function(i) sum(is.na(data[[i]])), integer(1)),
    na_rate = vapply(indicator, function(i) mean(is.na(data[[i]])), numeric(1))
  )

  by_group <- if (by %in% names(data) && length(indicator)) {
    data %>%
      dplyr::group_by(.data[[by]]) %>%
      dplyr::summarise(
        n_countries = dplyr::n(),
        na_rate = mean(is.na(.data[[indicator[1]]])),
        .groups = "drop"
      ) %>%
      dplyr::arrange(dplyr::desc(.data$na_rate))
  } else {
    tibble::tibble()
  }

  structure(
    list(unmatched = unmatched, na_rates = na_rates, by_group = by_group),
    class = "countryatlas_coverage"
  )
}

#' Auto-repair country names to their closest known match
#'
#' The "act on it" companion to [check_country_match()]: replaces unmatched
#' country names with their closest known country name (by string distance), but
#' only when the match is confident enough, and reports what it changed. Pipe the
#' result into [standardize_country()] / [join_world()].
#'
#' @param x A vector of country names.
#' @param threshold Maximum string distance to accept a repair (0 = identical,
#'   1 = unrelated). Lower is stricter; default `0.2`. Uses Jaro-Winkler when
#'   `stringdist` is installed, otherwise a length-normalised edit distance.
#'   The fallback is the more conservative of the two -- it repairs a subset of
#'   what Jaro-Winkler would, mainly missing transposed letters ("Frnace"), and
#'   never picks a different country -- so results can differ between machines
#'   depending on whether `stringdist` is available.
#' @param origin countrycode origin scheme (default `"country.name"`).
#' @param verbose Whether to message the substitutions made (default `TRUE`).
#'
#' @return A character vector the same length as `x`, with confident misses
#'   replaced by the closest known country name (others left unchanged). The
#'   applied substitutions are attached as the attribute `"repairs"`.
#' @export
#' @seealso [check_country_match()] for the report this acts on, and
#'   [dissolve_country()] for dissolved entities, which are deliberately not
#'   repaired.
#' @examples
#' repair_country_names(c("United States", "Brzil", "Germny"))
repair_country_names <- function(x, threshold = 0.2, origin = "country.name",
                                 verbose = TRUE) {
  check_bool(verbose, "verbose")
  check_number(threshold, "threshold", lo = 0, hi = 1)
  x <- as.character(x)
  report <- check_country_match(x, origin = origin, suggest = TRUE)
  out <- x
  changed <- !report$matched & !is.na(report$suggestion)
  repairs <- tibble::tibble(from = character(), to = character())
  for (i in which(changed)) {
    cand <- report$suggestion[i]
    # A dissolved entity (e.g. "Yugoslavia") exists in the codelist by name but
    # has no ISO code, so its own name comes back as the "suggestion" --
    # substituting it would be a no-op, not a repair. dissolve_country() is
    # the right tool there.
    if (identical(cand, x[i])) next
    d <- if (has_pkg("stringdist")) {
      stringdist::stringdist(tolower(x[i]), tolower(cand), method = "jw")
    } else {
      utils::adist(tolower(x[i]), tolower(cand))[1, 1] /
        max(nchar(x[i]), nchar(cand), 1L)
    }
    if (length(d) && !is.na(d) && d <= threshold) {
      out[i] <- cand
      repairs <- tibble::add_row(repairs, from = x[i], to = cand)
    }
  }
  if (isTRUE(verbose) && nrow(repairs)) {
    wdj_inform(c(
      "v" = "Repaired {nrow(repairs)} country name{?s}:",
      "*" = "{.val {paste0(repairs$from, ' -> ', repairs$to)}}"
    ))
  }
  attr(out, "repairs") <- repairs
  out
}

#' @export
print.countryatlas_coverage <- function(x, ...) {
  cli::cli_h1("Coverage audit")
  n_un <- nrow(x$unmatched)
  if (n_un > 0L) {
    cli::cli_alert_warning("{n_un} unmatched countr{?y/ies}: {.val {x$unmatched$country}}")
  } else {
    cli::cli_alert_success("All countries matched to an ISO code.")
  }
  if (nrow(x$na_rates)) {
    cli::cli_h2("Missingness by indicator")
    print(x$na_rates)
  }
  if (nrow(x$by_group)) {
    cli::cli_h2("Coverage by group")
    print(x$by_group)
  }
  invisible(x)
}
