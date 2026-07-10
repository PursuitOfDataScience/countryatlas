# The join engine: user-facing joins -------------------------------------------

# Heuristic: find the most likely country column in a data frame.
detect_country_col <- function(data, call = rlang::caller_env()) {
  nms <- names(data)
  candidates <- c("country", "country_name", "countryname", "nation", "name",
                  "iso3c", "iso2c", "iso_a3", "iso", "region", "geo")
  for (cand in candidates) {
    m <- nms[tolower(nms) == cand]
    if (length(m)) return(m[1])
  }
  # Otherwise the first character/factor column that mostly matches ISO codes.
  for (nm in nms) {
    col <- data[[nm]]
    if (is.character(col) || is.factor(col)) {
      iso <- wdj_to_iso3c(as.character(col))
      if (mean(!is.na(iso)) > 0.5) return(nm)
    }
  }
  wdj_abort(c(
    "Could not auto-detect a country column in {.arg data}.",
    "i" = "Pass {.arg country_col} explicitly."
  ), call = call)
}

#' One call: your data, on a map
#'
#' Auto-detects the country column, standardises it to ISO codes (via
#' [standardize_country()]), attaches geometry and returns a plot-ready frame --
#' the function that fulfils the package's promise for *your* own data. Pipe the
#' result straight into [world_map()].
#'
#' @param data A data frame keyed on country names or codes.
#' @param country_col The country column (unquoted). If omitted, it is
#'   auto-detected.
#' @param origin How to read `country_col` (any countrycode origin scheme).
#' @param geometry `"polygon"` (default), `"sf"` or `"none"`.
#' @param scale Natural Earth resolution for the `sf` backend.
#' @param region Optional region subset (see [world_geometry()]).
#' @param projection,recenter Projection options for the `sf` backend.
#' @param warn Whether to report unmatched countries (default `TRUE`); also
#'   surfaces a [check_country_match()] summary.
#'
#' @return A plot-ready frame: polygon tibble, `sf` object, or (for
#'   `geometry = "none"`) the standardised table.
#' @export
#' @examples
#' rates <- data.frame(country = c("United States", "Brazil", "Kenya"),
#'                     vaccination_pct = c(0.7, 0.8, 0.6))
#' \donttest{
#' if (requireNamespace("maps", quietly = TRUE)) {
#'   joined <- join_world(rates, country)
#' }
#' }
join_world <- function(data,
                       country_col = NULL,
                       origin = "country.name",
                       geometry = c("polygon", "sf", "none"),
                       scale = "small",
                       region = NULL,
                       projection = "equal_earth",
                       recenter = NULL,
                       warn = TRUE) {
  geometry <- match.arg(geometry)
  col_q <- rlang::enquo(country_col)
  if (rlang::quo_is_null(col_q) || rlang::quo_is_missing(col_q)) {
    col_name <- detect_country_col(data)
  } else {
    col_name <- rlang::as_name(col_q)
  }

  if (isTRUE(warn)) {
    report <- check_country_match(data[[col_name]], origin = origin, suggest = TRUE)
    n_miss <- sum(!report$matched)
    if (n_miss > 0L) {
      miss <- report$input[!report$matched]
      wdj_warn(c(
        "{n_miss} countr{?y/ies} in {.val {col_name}} could not be matched:",
        "*" = "{.val {miss}}",
        "i" = "See {.fn check_country_match} for suggestions."
      ))
    }
  }

  std <- standardize_country(data, !!rlang::sym(col_name), origin = origin,
                             warn = FALSE)
  if (geometry == "none") return(std)
  attach_geometry(std, by = "iso3c", geometry = geometry, scale = scale,
                  region = region, projection = projection, recenter = recenter)
}

#' Reconcile and join two messy country tables
#'
#' The generic two-table version of the package's whole reason for being: join
#' *any* two data frames that each key on country names or codes, by reconciling
#' both sides to `iso3c` first. Tables keyed on `"Czech Republic"` vs
#' `"Czechia"`, or `"South Korea"` vs `"Korea, Rep."`, just work.
#'
#' @param x,y Data frames to join.
#' @param by_x,by_y The country columns in `x` and `y` (unquoted).
#' @param origin_x,origin_y How to read each key (countrycode origin schemes).
#' @param type Join type: `"left"` (default), `"inner"` or `"full"`.
#' @param suffix Suffix for clashing non-key columns (default
#'   `c(".x", ".y")`).
#'
#' @return A tibble joined on a reconciled `iso3c` key.
#' @export
#' @examples
#' a <- data.frame(country = c("Czechia", "South Korea"), gdp = c(1, 2))
#' b <- data.frame(nation = c("Czech Republic", "Korea, Rep."), pop = c(10, 51))
#' country_join(a, b, country, nation)
country_join <- function(x, y, by_x, by_y,
                         origin_x = "country.name",
                         origin_y = "country.name",
                         type = c("left", "inner", "full"),
                         suffix = c(".x", ".y")) {
  type <- match.arg(type)
  bx <- rlang::as_name(rlang::enquo(by_x))
  by_ <- rlang::as_name(rlang::enquo(by_y))
  if (!bx %in% names(x)) wdj_abort("Column {.val {bx}} not found in {.arg x}.")
  if (!by_ %in% names(y)) wdj_abort("Column {.val {by_}} not found in {.arg y}.")

  x <- tibble::as_tibble(x)
  y <- tibble::as_tibble(y)
  x[["iso3c"]] <- wdj_to_iso3c(x[[bx]], origin = origin_x)
  y[["iso3c"]] <- wdj_to_iso3c(y[[by_]], origin = origin_y)

  join_fun <- switch(type,
                     left = dplyr::left_join,
                     inner = dplyr::inner_join,
                     full = dplyr::full_join)
  join_fun(x, y, by = "iso3c", suffix = suffix, na_matches = "never")
}

#' Join many messy country tables on the ISO spine
#'
#' The many-table generalisation of [country_join()]: reduce-join a list of data
#' frames that each key on country names or codes, reconciling every one to
#' `iso3c` first.
#'
#' @param tables A list of data frames.
#' @param by A single country-column name present in every table, or a character
#'   vector giving the column for each table.
#' @param origin countrycode origin scheme(s) for the key column(s) (default
#'   `"country.name"`; length 1 or one per table).
#' @param type Join type: `"full"` (default), `"left"` or `"inner"`.
#'
#' @return A single tibble joined on `iso3c` (clashing non-key columns get
#'   dplyr's default `.x`/`.y` suffixes).
#' @export
#' @examples
#' a <- data.frame(country = c("Czechia", "South Korea"), gdp = c(1, 2))
#' b <- data.frame(country = c("Czech Republic", "Korea, Rep."), pop = c(10, 51))
#' d <- data.frame(country = c("Czechia", "Korea"), area = c(79, 100))
#' country_join_all(list(a, b, d), by = "country")
country_join_all <- function(tables, by, origin = "country.name",
                             type = c("full", "left", "inner")) {
  type <- match.arg(type)
  if (!is.list(tables) || !length(tables)) {
    wdj_abort("{.arg tables} must be a non-empty list of data frames.")
  }
  n <- length(tables)
  by <- if (length(by) == 1L) rep(by, n) else by
  origin <- if (length(origin) == 1L) rep(origin, n) else origin
  if (length(origin) != n) {
    wdj_abort("{.arg origin} must be length 1 or length {n} (one scheme per table).")
  }
  if (length(by) != n) {
    wdj_abort("{.arg by} must be length 1 or length {n} (one column per table).")
  }

  prepped <- lapply(seq_len(n), function(i) {
    tb <- tibble::as_tibble(tables[[i]])
    if (!by[i] %in% names(tb)) {
      wdj_abort("Column {.val {by[i]}} not found in table {i}.")
    }
    tb[["iso3c"]] <- wdj_to_iso3c(tb[[by[i]]], origin = origin[i])
    tb
  })
  join_fun <- switch(type, left = dplyr::left_join,
                     inner = dplyr::inner_join, full = dplyr::full_join)
  Reduce(function(x, y) join_fun(x, y, by = "iso3c", na_matches = "never"), prepped)
}
