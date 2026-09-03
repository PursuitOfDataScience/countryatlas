# The join engine: user-facing joins -------------------------------------------

# Heuristic: find the most likely country column in a data frame.
detect_country_col <- function(data, call = rlang::caller_env()) {
  nms <- names(data)
  candidates <- c("country", "country_name", "countryname", "nation", "name",
                  "iso3c", "iso2c", "iso_a3", "iso", "region", "geo")
  # Some names say which scheme the column holds. Without this, a column named
  # `iso3c` was found by name and then read as a country *name*, so
  # join_world(tibble(iso3c = c("FRA", "JPN"))) -- the most natural call there
  # is -- warned and returned all NA. The guess is verified before it is used,
  # so a misnamed column still falls back to the default scheme.
  scheme_for <- c(iso3c = "iso3c", iso_a3 = "iso3c", iso = "iso3c",
                  iso2c = "iso2c")
  resolves <- function(col, org) {
    hits <- wdj_to_iso3c(as.character(col), origin = org)
    length(hits) && mean(!is.na(hits)) > 0.5
  }
  for (cand in candidates) {
    m <- nms[ascii_lower(nms) == cand]
    if (length(m)) {
      org <- unname(scheme_for[cand])
      if (!is.na(org) && resolves(data[[m[1]]], org)) {
        return(structure(m[1], origin = org))
      }
      return(m[1])
    }
  }
  # Otherwise the first character/factor column that mostly resolves to a
  # country. Both schemes have to be tried: countrycode's country.name regex
  # does not match most alpha-3 codes ("FRA" and "JPN" fail, "USA" happens to
  # match), so testing names alone rejected a column of the very codes this
  # function converts *to* -- unless it happened to be named `iso3c`.
  for (nm in nms) {
    col <- data[[nm]]
    if (is.character(col) || is.factor(col)) {
      col <- as.character(col)
      for (org in c("country.name", "iso3c")) {
        iso <- wdj_to_iso3c(col, origin = org)
        # Carry the scheme that worked back to the caller: detecting an alpha-3
        # column and then reading it as a country *name* matched nothing, which
        # is a worse outcome than not detecting it at all.
        if (mean(!is.na(iso)) > 0.5) return(structure(nm, origin = org))
      }
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
#' @param scale Natural Earth resolution for the `sf` backend. `"large"` needs the
#'   non-CRAN `rnaturalearthhires` package; see [world_geometry()].
#' @param region Optional region subset (see [world_geometry()]). Applied
#'   whichever `geometry` is used, including `"none"`; with `"none"` there is
#'   nothing to clip, so a bounding box is refused rather than ignored.
#' @param projection,recenter Projection, and optional central meridian, for
#'   the `sf` backend (see [world_map()] for the projections available).
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
  check_bool(warn, "warn")
  geometry <- rlang::arg_match(geometry)
  col_q <- rlang::enquo(country_col)
  if (rlang::quo_is_null(col_q) || rlang::quo_is_missing(col_q)) {
    col_name <- detect_country_col(data)
    # Only when the caller left `origin` at its default: an explicit origin is
    # an instruction, not a hint.
    detected <- attr(col_name, "origin")
    if (missing(origin) && !is.null(detected)) origin <- detected
    col_name <- as.character(col_name)
  } else {
    col_name <- quo_arg_name(col_q, "country_col")
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
  if (geometry == "none") {
    # Identical to the world_data() case: this branch returned before any of
    # the geometry arguments were applied, and `region` is documented as a
    # plain "region subset" rather than an sf-backend option -- so asking for
    # one region with geometry = "none" handed back every row.
    if (!is.null(region)) {
      iso <- resolve_region(region)
      if (inherits(iso, "wdj_bbox")) {
        wdj_abort(c(
          "A bounding-box {.arg region} needs geometry to clip against.",
          "x" = 'There is nothing to clip when {.code geometry = "none"}.',
          "i" = 'Use {.code geometry = "sf"}, or select whole countries with a
                 continent, a group name or an {.field iso3c} vector.'
        ), class = "countryatlas_bbox_without_geometry")
      }
      if (!is.null(iso)) {
        std <- std[!is.na(std$iso3c) & std$iso3c %in% iso, , drop = FALSE]
      }
    }
    warn_scale_ignored(scale)
    warn_projection_ignored(projection, 'geometry = "none"')
    warn_recenter_ignored(recenter, 'geometry = "none"')
    return(std)
  }
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
#' @param key Which code system to join on. `"iso3c"` (default) is the
#'   package's spine and the right choice for anything contemporary.
#'   `"cowc"`/`"cown"` (Correlates of War) and `"gwn"` (Gleditsch-Ward) are the
#'   alternate spines historical work needs -- see the section below.
#' @param warn Whether to report values that resolve to no country (default
#'   `TRUE`). They join to nothing, so a silent reconciliation failure is the
#'   one thing this verb exists to prevent. Each side is reported separately.
#' @section Joining historical data: the second spine:
#' ISO 3166 was first published in 1974 and never covered colonies, so `iso3c`
#' cannot key anything before about 1970. Correlates of War and Gleditsch-Ward
#' codes can, they run back to the nineteenth century, and
#' [historical_geometry()] is keyed on `gwn`. Setting `key` switches the join
#' onto one of those:
#' ```r
#' country_join(a, b, country, nation, key = "gwn")
#' ```
#' The trade-off is real and worth stating: COW/GW codes cover states ISO never
#' did, but they omit the dependencies and non-sovereign territories ISO does
#' cover, so a modern dataset joined on `gwn` loses Hong Kong, Puerto Rico and
#' the rest -- which the join warns about. Use `iso3c` unless you are working
#' before 1970.
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
                         suffix = c(".x", ".y"),
                         key = c("iso3c", "cowc", "cown", "gwn"),
                         warn = TRUE) {
  type <- rlang::arg_match(type)
  key <- rlang::arg_match(key)
  check_bool(warn, "warn")
  bx <- quo_arg_name(rlang::enquo(by_x), "by_x")
  by_ <- quo_arg_name(rlang::enquo(by_y), "by_y")
  if (!bx %in% names(x)) wdj_abort("Column {.val {bx}} not found in {.arg x}.")
  if (!by_ %in% names(y)) wdj_abort("Column {.val {by_}} not found in {.arg y}.")

  x <- tibble::as_tibble(x)
  y <- tibble::as_tibble(y)
  x[[key]] <- wdj_to_key(x[[bx]], origin = origin_x, key = key, side = "`x`",
                         warn_unresolved = warn)
  y[[key]] <- wdj_to_key(y[[by_]], origin = origin_y, key = key, side = "`y`",
                         warn_unresolved = warn)

  if (warn) {
    warn_key_collapse(x[[bx]], x[[key]], "`x`", bx, key)
    warn_key_collapse(y[[by_]], y[[key]], "`y`", by_, key)
  }
  join_fun <- switch(type,
                     left = dplyr::left_join,
                     inner = dplyr::inner_join,
                     full = dplyr::full_join)
  join_fun(x, y, by = key, suffix = suffix, na_matches = "never")
}

# Standardisation can map two distinct inputs onto one code -- "France" and
# "FRANCE ", or "Congo" and "Congo-Kinshasa" -- and the join then silently
# multiplies the other side's rows. dplyr does not warn: with unique keys on one
# side that is an ordinary one-to-many, not the many-to-many it flags. So the
# user sees a frame that looks fine, in which one country is counted twice.
# Only the *collapse* is worth reporting: duplicates already present in the
# input are the caller's own, and a country-by-year panel is a legitimate
# one-to-many.
warn_key_collapse <- function(orig, key, side, by_name, key_name,
                              hint = "Aggregate or de-duplicate {side} first if
                                      one row per country was intended; pass
                                      {.code warn = FALSE} to silence this.") {
  # Returns the codes it reported, so a caller running a second, broader
  # duplicate check does not say the same thing twice: a collapsed key is by
  # definition also a repeated one.
  ok <- !is.na(key)
  if (!any(ok)) return(invisible(character(0)))
  orig <- as.character(orig)[ok]
  key <- key[ok]
  dup_keys <- unique(key[duplicated(key)])
  # Keep only the codes reached from more than one distinct input value.
  collapsed <- dup_keys[vapply(dup_keys, function(k)
    length(unique(orig[key == k])) > 1L, NA)]
  if (!length(collapsed)) return(invisible(character(0)))
  shown <- utils::head(collapsed, 5)
  detail <- vapply(shown, function(k) {
    paste0(k, " <- ", paste(unique(orig[key == k]), collapse = ", "))
  }, character(1))
  # Both agreements sit directly after the count with nothing interpolated
  # between: cli keys {?s} to the most recent numeric interpolation, and naming
  # the column first gave "2 iso3c value in `y` is reached".
  wdj_warn(c(
    "{.field {key_name}} in {side}: {length(collapsed)} value{?s} {?is/are}
     reached from more than one {.field {by_name}}, so the join repeats rows.",
    "*" = "{.val {detail}}",
    "i" = hint
  ), class = "countryatlas_key_collapse")
  invisible(collapsed)
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
#' @param key Which code system to join on, as in [country_join()]: `"iso3c"`
#'   (default), or `"cowc"`/`"cown"`/`"gwn"` for historical work that predates
#'   ISO 3166. Each table reports separately on the countries the alternate key
#'   cannot carry.
#' @param warn Whether to report values that resolve to no country (default
#'   `TRUE`), per table, as [country_join()] does per side.
#'
#' @return A single tibble joined on `key` (clashing non-key columns get
#'   dplyr's default `.x`/`.y` suffixes).
#' @export
#' @examples
#' a <- data.frame(country = c("Czechia", "South Korea"), gdp = c(1, 2))
#' b <- data.frame(country = c("Czech Republic", "Korea, Rep."), pop = c(10, 51))
#' d <- data.frame(country = c("Czechia", "Korea"), area = c(79, 100))
#' country_join_all(list(a, b, d), by = "country")
country_join_all <- function(tables, by, origin = "country.name",
                             type = c("full", "left", "inner"),
                             key = c("iso3c", "cowc", "cown", "gwn"),
                             warn = TRUE) {
  type <- rlang::arg_match(type)
  key <- rlang::arg_match(key)
  check_bool(warn, "warn")
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
    tb[[key]] <- wdj_to_key(tb[[by[i]]], origin = origin[i], key = key,
                            side = sprintf("table %d", i),
                            warn_unresolved = warn)
    # Same collapse hazard as country_join(), once per table.
    if (warn) {
      warn_key_collapse(tb[[by[i]]], tb[[key]], sprintf("table %d", i),
                        by[i], key)
    }
    tb
  })
  join_fun <- switch(type, left = dplyr::left_join,
                     inner = dplyr::inner_join, full = dplyr::full_join)
  Reduce(function(x, y) join_fun(x, y, by = key, na_matches = "never"), prepped)
}
