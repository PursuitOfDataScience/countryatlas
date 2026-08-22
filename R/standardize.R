# Country-name standardisation --------------------------------------------------

# Convert raw country identifiers to iso3c, applying overrides and (optionally)
# warning about misses. `origin` is any countrycode origin scheme
# ("country.name", "iso2c", "iso3c", "wb", ...).
wdj_to_iso3c <- function(x, origin = "country.name", custom_match = country_overrides()) {
  check_string(origin, "origin")
  x <- as.character(x)
  if (identical(origin, "iso3c")) {
    out <- ascii_upper(trimws(x))
    # Still let overrides repair known-bad spellings.
    if (length(custom_match)) {
      hit <- match(x, names(custom_match))
      out[!is.na(hit)] <- unname(custom_match[hit[!is.na(hit)]])
    }
    valid <- c(wdj_known_iso3c(), unname(custom_match))
    out[!is.na(out) & !(out %in% valid)] <- NA_character_
    return(out)
  }
  suppressWarnings(
    countrycode::countrycode(
      x,
      origin = origin,
      destination = "iso3c",
      custom_match = if (length(custom_match)) custom_match else NULL,
      warn = FALSE
    )
  )
}

# Derive a set of attributes from iso3c. `add` may name any countrycode
# destination; the common shortcuts (iso2c, continent, region) are handled
# explicitly with fallbacks for codes countrycode does not know.
wdj_derive_from_iso3c <- function(iso3c, add) {
  out <- tibble::tibble(iso3c = iso3c)
  dest_map <- c(
    iso2c     = "iso2c",
    continent = "continent",
    region    = "region",
    region23  = "region23",
    un_region = "un.region.name",
    country   = "country.name.en",
    flag      = "unicode.symbol",
    currency  = "iso4217c",
    tld       = "cctld"
  )
  for (a in add) {
    if (a == "iso3c") next
    dest <- if (a %in% names(dest_map)) dest_map[[a]] else a # allow raw countrycode destinations
    out[[a]] <- suppressWarnings(
      countrycode::countrycode(iso3c, origin = "iso3c", destination = dest, warn = FALSE)
    )
  }
  out <- apply_code_fallback(out)
  out
}

#' Add ISO codes and classifications to any data frame
#'
#' The package's mission, exposed for *your* data: take a data frame keyed on
#' messy country names (or codes) and attach standardised ISO codes plus useful
#' classifications, reconciling spellings via [countrycode::countrycode()] and
#' the curated [country_overrides()] table. The result joins cleanly to anything
#' else keyed on `iso3c`.
#'
#' @param data A data frame / tibble.
#' @param country_col The column holding country names or codes
#'   (unquoted, tidy-eval).
#' @param origin How to read `country_col`; any [countrycode::countrycode()]
#'   origin scheme such as `"country.name"` (default), `"iso2c"`, `"iso3c"`,
#'   `"wb"`, `"un"`.
#' @param add Character vector of attributes to add. Defaults to
#'   `c("iso3c", "iso2c", "continent", "region")`. Any countrycode destination
#'   is accepted, plus the shortcuts `"flag"`, `"currency"`, `"tld"`.
#' @param custom_match A named character vector of name -> iso3c overrides;
#'   defaults to [country_overrides()]. Merged on top of the built-in matching.
#' @param warn Whether to warn about unmatched countries (default `TRUE`).
#'
#' @return `data` with the requested columns added (and existing same-named
#'   columns overwritten).
#' @export
#' @examples
#' df <- data.frame(nation = c("U.S.", "S. Korea", "Czechia"), value = 1:3)
#' standardize_country(df, nation)
standardize_country <- function(data,
                                country_col,
                                origin = "country.name",
                                add = c("iso3c", "iso2c", "continent", "region"),
                                custom_match = country_overrides(),
                                warn = TRUE) {
  check_bool(warn, "warn")
  if (!is.data.frame(data)) {
    wdj_abort("{.arg data} must be a data frame.")
  }
  col_q <- rlang::enquo(country_col)
  if (rlang::quo_is_missing(col_q)) {
    wdj_abort("{.arg country_col} is required.")
  }
  col_name <- tryCatch(rlang::as_name(col_q), error = function(e) NULL)
  if (is.null(col_name) || !col_name %in% names(data)) {
    wdj_abort("Column {.val {col_name %||% rlang::as_label(col_q)}} not found in {.arg data}.")
  }

  add <- unique(c("iso3c", add))
  raw <- data[[col_name]]
  iso3c <- wdj_to_iso3c(raw, origin = origin, custom_match = custom_match)

  if (isTRUE(warn) && anyNA(iso3c)) {
    miss <- unique(as.character(raw)[is.na(iso3c)])
    miss <- miss[!is.na(miss)]
    if (length(miss)) {
      wdj_warn(c(
        "{length(miss)} value{?s} could not be matched to an ISO code:",
        "*" = "{.val {miss}}",
        "i" = "Use {.fn check_country_match} to inspect, or pass {.arg custom_match}."
      ))
    }
  }

  derived <- wdj_derive_from_iso3c(iso3c, add)
  # Drop any columns we are about to (re)create, then bind. No warn_overwrite()
  # here: `add` names the columns literally, so replacing an existing `continent`
  # is precisely what the caller asked for. The warning belongs where the package
  # invents the name (rank_countries) or composes it from a suffix (per_capita).
  data[intersect(names(derived), names(data))] <- NULL
  dplyr::bind_cols(tibble::as_tibble(data), derived)
}
