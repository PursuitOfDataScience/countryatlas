# Reference data & code translation ---------------------------------------------

# Friendly shortcut -> countrycode destination scheme.
convert_dest_map <- function() {
  c(
    iso3c        = "iso3c",
    iso2c        = "iso2c",
    iso3n        = "iso3n",
    country      = "country.name.en",
    country.name = "country.name.en",
    name         = "country.name.en",
    continent    = "continent",
    region       = "region",
    region23     = "region23",
    un_region    = "un.region.name",
    flag         = "unicode.symbol",
    currency     = "iso4217c",
    tld          = "cctld",
    calling_code = "telephone",
    cown         = "cown",
    cowc         = "cowc",
    p4n          = "p4n",
    p5n          = "p5n",
    gwn          = "gwn",
    vdem         = "vdem",
    imf          = "imf",
    fao          = "fao",
    fips         = "fips",
    gaul         = "gaul",
    wb           = "wb",
    un           = "un"
  )
}

#' Friendly country-code conversion
#'
#' A discoverable wrapper around [countrycode::countrycode()] exposing the full
#' set of schemes with first-class shortcuts for the high-value ones: flag
#' emoji, currency, top-level domain, continent/region and research codes
#' (Correlates of War, Polity, Gleditsch-Ward, V-Dem, IMF, FAO, FIPS, GAUL).
#'
#' @param x A vector of country names or codes.
#' @param to Destination scheme. A shortcut (`"iso3c"`, `"flag"`, `"currency"`,
#'   `"tld"`, `"continent"`, `"region"`, `"calling_code"`, `"cown"`, ...), a
#'   localized name
#'   `"name_<lang>"` (`"name_fr"`, `"name_es"`, `"name_zh"`, ... -- any
#'   language in countrycode's CLDR tables), or any raw countrycode
#'   destination.
#' @param from Origin scheme (default `"country.name"`).
#' @param custom_match Optional overrides (default [country_overrides()]).
#' @param warn Whether to warn about inputs that match no country (default
#'   `TRUE`). A recognised country whose destination value is genuinely
#'   missing -- countrycode has no currency for Kosovo -- returns `NA`
#'   without warning.
#'
#' @return A vector of converted codes.
#' @export
#' @examples
#' convert_country(c("Japan", "Brazil"), to = "flag")
#' convert_country("Germany", to = "currency")
#' convert_country(c("USA", "France"), to = "continent")
#' convert_country(c("Germany", "United States"), to = "name_fr")
convert_country <- function(x, to = "iso3c", from = "country.name",
                            custom_match = country_overrides(), warn = TRUE) {
  check_bool(warn, "warn")
  check_string(to, "to")
  check_string(from, "from")
  m <- convert_dest_map()
  dest <- if (to %in% names(m)) {
    m[[to]]
  } else if (grepl("^name_[a-z]{2,3}(_[a-z]+)?$", to)) {
    # Localized names: name_fr -> cldr.name.fr (countrycode's CLDR tables).
    sub("^name_", "cldr.name.", to)
  } else {
    to
  }
  # `to` reached countrycode as `destination` with only check_string() behind
  # it, so a typo produced "The `destination` argument must be a string ... one
  # of the column names in the conversion directory (by default: `codelist`)"
  # -- an argument and a directory the caller never mentioned. Check it here,
  # against the mapped value, so shortcuts and name_xx still pass.
  dest_ok <- tryCatch(names(countrycode::codelist), error = function(e) NULL)
  if (length(dest_ok) && !dest %in% dest_ok) abort_bad_destination(to, "to")
  # When reading names or iso3c, resolve to the override-corrected iso3c first
  # and then convert iso3c -> destination, so curated entities (Kosovo, Canary
  # Islands, ...) resolve for EVERY destination, not just iso3c.
  if (from %in% c("country.name", "iso3c")) {
    iso <- wdj_to_iso3c(x, origin = from, custom_match = custom_match)
    # Report inputs that resolve to no country at all. A recognised country
    # whose *destination* value is genuinely missing (countrycode has no
    # currency for Kosovo) is a data gap, not a matching failure, so it does
    # not warn -- otherwise sparse destinations like `cown` would cry wolf.
    warn_unmatched_input(x, iso, warn)
    if (identical(dest, "iso3c")) return(iso)
    out <- suppressWarnings(
      countrycode::countrycode(iso, origin = "iso3c", destination = dest, warn = FALSE)
    )
    # A handful of user-assigned codes (Kosovo's XKX) have NO row at all in
    # countrycode::codelist, so the iso3c round-trip above is NA for every
    # destination -- even ones (flag, name, region) that countrycode's own
    # country.name matching resolves directly. Recover those from the
    # original name rather than lose information the iso3c hop doesn't have.
    if (identical(from, "country.name")) {
      miss <- is.na(out)
      if (any(miss)) {
        out[miss] <- suppressWarnings(
          countrycode::countrycode(x[miss], origin = "country.name",
                                   destination = dest, warn = FALSE)
        )
      }
    }
    # Codes with no codelist row at all (XKX) are still NA here -- and from
    # `iso3c` there is no name to recover from. Apply the same curated
    # fallback standardize_country() uses, so convert_country(),
    # locate_country() and country_borders() all agree with it.
    out <- apply_fallback_dest(iso, out, dest)
    return(out)
  }
  # Any scheme other than country.name/iso3c skips the iso3c hop above, so
  # this is the one countrycode call `from` reaches directly -- and it was the
  # one place the guard in wdj_to_iso3c() could not cover. A bad `from` blamed
  # `origin`, which is not an argument of this function.
  out <- tryCatch(
    suppressWarnings(
      countrycode::countrycode(x, origin = from, destination = dest,
                               warn = FALSE)
    ),
    error = function(e) {
      if (grepl("`origin`", conditionMessage(e), fixed = TRUE)) {
        abort_bad_origin(from, e, rlang::caller_env(), "from")
      }
      stop(e)
    }
  )
  # No intermediate iso3c here, so the single hop is the match.
  warn_unmatched_input(x, out, warn)
  out
}

# countrycode destination -> the column of wdj_code_fallback() that fills it.
fallback_dest_col <- function(dest) {
  switch(dest,
         iso2c = "iso2c", continent = "continent", region = "region",
         country.name.en = "country", unicode.symbol = "flag",
         NULL)
}

# Fill a converted vector from the curated fallback table where the iso3c
# round-trip left it NA.
apply_fallback_dest <- function(iso, out, dest) {
  col <- fallback_dest_col(dest)
  if (is.null(col)) return(out)
  apply_code_fallback(tibble::tibble(iso3c = iso, "{col}" := out))[[col]]
}

# `warn = TRUE` has to warn from here: countrycode's own warning is suppressed
# throughout, because it also fires on intermediate hops that
# convert_country() goes on to recover.
warn_unmatched_input <- function(x, matched, warn) {
  if (!isTRUE(warn)) return(invisible(NULL))
  x <- as.character(x)
  miss <- unique(x[!is.na(x) & nzchar(x) & is.na(matched)])
  if (!length(miss)) return(invisible(NULL))
  wdj_warn(c(
    "{length(miss)} value{?s} could not be matched to a country:",
    "*" = "{.val {miss}}",
    "i" = "Use {.fn check_country_match} to inspect, or pass {.arg custom_match}."
  ))
  invisible(NULL)
}

#' The countrycode codelist as a tidy tibble
#'
#' The whole [countrycode::codelist] reshaped into a tidy, pipeable lookup you
#' can `filter()` / `join()` directly -- one row per country.
#'
#' @param codes Optional character vector of column names to keep (in addition
#'   to `iso3c`). If `NULL`, a useful default subset is returned.
#'
#' @return A tibble, one row per country.
#' @export
#' @examples
#' country_codes()
#' country_codes(c("iso2c", "continent", "currency"))
country_codes <- function(codes = NULL) {
  # `codes` names columns as strings; a bare `codes = iso3c` died on base R's
  # "object 'iso3c' not found".
  codes_expr <- substitute(codes)
  codes <- tryCatch(force(codes), error = function(e) {
    abort_bare_column(codes_expr, "codes", e)
  })
  cl <- tibble::as_tibble(countrycode::codelist)
  # Friendly name -> raw codelist column, with the inverse for renaming output.
  raw_of <- c(country = "country.name.en", iso3c = "iso3c", iso2c = "iso2c",
              iso3n = "iso3n", continent = "continent", region = "region",
              region23 = "region23", un_region = "un.region.name",
              currency = "iso4217c", tld = "cctld", flag = "unicode.symbol")
  default <- c("country", "iso3c", "iso2c", "iso3n", "continent", "region",
               "region23", "currency", "tld", "flag")
  friendly <- if (is.null(codes)) default else unique(c("country", "iso3c", codes))
  # Allow either friendly names or raw codelist column names.
  raw <- vapply(friendly, function(f) {
    if (f %in% names(raw_of)) raw_of[[f]] else f
  }, character(1))
  inv <- stats::setNames(names(raw_of), raw_of)
  # A name that is neither a friendly shortcut nor a real codelist column used
  # to be dropped in silence, so a typo ("curency") returned a table quietly
  # missing that column.
  unknown <- names(raw)[!raw %in% names(cl)]
  if (length(unknown)) {
    wdj_abort(c(
      "Unknown column{?s}: {.val {unknown}}.",
      "i" = "Use a shortcut ({.val {names(raw_of)}}) or a {.code countrycode::codelist} column name."
    ))
  }
  keep <- raw
  out <- cl[, unname(keep), drop = FALSE]
  # Rename raw columns back to friendly names where we know them.
  names(out) <- vapply(names(out), function(nm) {
    if (nm %in% names(inv)) inv[[nm]] else nm
  }, character(1))
  dplyr::filter(out, !is.na(.data$iso3c))
}

#' Country-group membership
#'
#' Answers the constant question "is this country in the EU / OECD / G7 / G20 /
#' BRICS / ...?" from a curated membership table. By default that is the current
#' snapshot ([country_groups_tbl]); pass `as_of` to ask the question of a
#' particular date, which is what a panel needs.
#'
#' @param group One or more group names: any of `"EU"`, `"OECD"`, `"G7"`,
#'   `"G20"`, `"BRICS"`, `"ASEAN"`, `"EFTA"`, `"Commonwealth"`, `"OPEC"`,
#'   `"EuroZone"`, `"NATO"`, `"Mercosur"`, `"GCC"`, `"Nordic"`, `"Visegrad"`.
#'   If `NULL`, the whole table is returned.
#' @param as_of A date (or a year) at which to evaluate membership. `NULL`
#'   (default) uses the current snapshot. **A bare year means 1 January of that
#'   year**, not "at some point during it": `as_of = 2013` is 2013-01-01, so
#'   Croatia -- which joined the EU on 2013-07-01 -- is not yet a member. Pass a
#'   `"YYYY-MM-DD"` string or a `Date` when the month matters. See the section
#'   below.
#'
#' @return A tibble of `group`, `iso3c`, `country`; with `as_of`, also `from`
#'   and `to`.
#'
#' @section Membership changes, and which groups are dated:
#' A snapshot silently misstates any panel that spans an accession. An EU panel
#' over 2015-2020 either includes the United Kingdom throughout or excludes it
#' throughout, and both are wrong:
#' ```r
#' "GBR" %in% country_groups("EU", as_of = 2016)$iso3c   # TRUE
#' "GBR" %in% country_groups("EU", as_of = 2021)$iso3c   # FALSE
#' ```
#' [country_groups_history] carries dated membership for twelve groups: EU,
#' EuroZone, NATO, OECD, ASEAN, EFTA, GCC, Mercosur, Nordic, Visegrad, BRICS and
#' G7. Commonwealth, G20 and OPEC are **not** dated -- their histories involve
#' suspensions, readmissions and contested dates that would have to be sourced
#' case by case, and a fabricated date is worse than an absent one. Asking for
#' `as_of` on those warns and falls back to the snapshot.
#'
#' @seealso [in_group()], [country_groups_history], [country_timeline()]
#' @export
#' @examples
#' country_groups("EU")
#' country_groups(c("G7", "BRICS"))
#' # the UK was a member in 2016 and not in 2021
#' nrow(country_groups("EU", as_of = 2016))
#' nrow(country_groups("EU", as_of = 2021))
country_groups <- function(group = NULL, as_of = NULL) {
  tbl <- countryatlas::country_groups_tbl
  valid <- unique(tbl$group)
  if (!is.null(group)) {
    bad <- setdiff(group, valid)
    if (length(bad)) {
      wdj_abort(c(
        "Unknown group{?s}: {.val {bad}}.",
        "i" = "Available groups: {.val {valid}}."
      ))
    }
  }
  if (is.null(as_of)) {
    if (is.null(group)) return(tbl)
    grp <- group
    return(dplyr::filter(tbl, .data$group %in% grp))
  }

  when <- as_of_date(as_of)
  hist <- countryatlas::country_groups_history
  want <- group %||% valid
  dated <- intersect(want, unique(hist$group))
  undated <- setdiff(want, dated)
  if (length(undated)) {
    wdj_warn(c(
      "No dated membership for {.val {undated}}; using the current snapshot.",
      "i" = "See {.help countryatlas::country_groups_history} for which groups
             are dated and why the others are not."
    ))
  }
  out <- dplyr::filter(
    hist, .data$group %in% dated, .data$from <= when,
    is.na(.data$to) | .data$to > when
  )
  if (length(undated)) {
    snap <- dplyr::filter(tbl, .data$group %in% undated)
    snap$from <- as.Date(NA); snap$to <- as.Date(NA)
    out <- dplyr::bind_rows(out, snap)
  }
  dplyr::arrange(out, .data$group, .data$iso3c)
}

# Accept a Date, a year number, or a parseable date string. A bare year means
# "as at 1 January", which is the convention every annual panel already uses.
as_of_date <- function(as_of, call = rlang::caller_env()) {
  if (inherits(as_of, "Date")) {
    if (length(as_of) != 1L || is.na(as_of)) {
      wdj_abort("{.arg as_of} must be a single non-missing date.", call = call)
    }
    return(as_of)
  }
  if (is.numeric(as_of) && length(as_of) == 1L && !is.na(as_of) &&
      as_of == round(as_of) && as_of > 1000 && as_of < 3000) {
    return(as.Date(sprintf("%d-01-01", as.integer(as_of))))
  }
  if (is.character(as_of) && length(as_of) == 1L) {
    # as.Date() *errors* on an unparseable string ("character string is not in a
    # standard unambiguous format") rather than returning NA, so the guard below
    # never ran and the caller got base R's message instead of ours.
    d <- tryCatch(as.Date(as_of), error = function(e) NA)
    if (!is.na(d)) return(d)
  }
  wdj_abort(c(
    "{.arg as_of} must be a {.cls Date}, a four-digit year, or a
     {.val YYYY-MM-DD} string.",
    "x" = "Got {.val {as_of}}."
  ), call = call)
}

#' Is a country in a group?
#'
#' A vectorised membership predicate built on [country_groups()].
#'
#' @param x A vector of country names or codes.
#' @param group A single group name (see [country_groups()]).
#' @param origin How to read `x` (default `"country.name"`).
#' @param as_of A date or year at which to evaluate membership; `NULL` (default)
#'   uses the current snapshot. A bare year means 1 January of that year, so use
#'   a `"YYYY-MM-DD"` string when an accession or exit falls mid-year. See
#'   [country_groups()].
#'
#' @return A logical vector the same length as `x`. A value `origin` cannot
#'   resolve to an ISO code answers `FALSE` -- the same as a country that is
#'   genuinely outside the group -- so run [check_country_match()] first if you
#'   need to tell "not a member" from "not recognised".
#' @seealso [country_groups()], [country_groups_history]
#' @export
#' @examples
#' in_group(c("France", "United States", "Japan"), "EU")
#' # membership is a function of time
#' in_group("United Kingdom", "EU", as_of = 2016)
#' in_group("United Kingdom", "EU", as_of = 2021)
in_group <- function(x, group, origin = "country.name", as_of = NULL) {
  if (length(group) != 1L) wdj_abort("{.arg group} must be a single group name.")
  iso <- wdj_to_iso3c(x, origin = origin)
  members <- country_groups(group, as_of = as_of)$iso3c
  iso %in% members
}

#' Search World Bank indicators
#'
#' A tidy, pipeable wrapper on [WDI::WDIsearch()] for discovering indicator
#' codes.
#'
#' @param pattern A regular expression to search indicator names/codes for.
#' @param field Which field to search: `"name"` (default) or `"indicator"`.
#' @param cache Optional cached `WDIcache()` object; if `NULL`, WDI's bundled
#'   cache is used (no network).
#'
#' @return A tibble of matching `indicator` codes and `name`s.
#' @export
#' @examples
#' \donttest{
#' # Searches WDI's bundled indicator list, so this needs no connection.
#' wdi_search("CO2 emissions")
#' }
wdi_search <- function(pattern, field = c("name", "indicator"), cache = NULL) {
  field <- rlang::arg_match(field)
  # `field` was the only argument checked. A non-string `pattern` went straight
  # into the regex and matched *something*: wdi_search(1) returned 10,125 rows
  # and wdi_search(NA) the whole 29,495-row catalogue, both silently, while an
  # empty one leaked base R's "invalid 'pattern' argument".
  check_string(pattern, "pattern")
  # `cache` is a WDIcache() object, so a logical or a string reached WDI and
  # failed on "$ operator is invalid for atomic vectors".
  if (!is.null(cache) && !is.list(cache)) {
    wdj_abort(c(
      "{.arg cache} must be a {.fn WDI::WDIcache} object, or {.code NULL}.",
      "x" = "Got {.cls {class(cache)[1]}}.",
      "i" = "{.code NULL} uses the cache bundled with {.pkg WDI}, offline."
    ))
  }
  res <- WDI::WDIsearch(string = pattern, field = field, short = TRUE,
                        cache = cache)
  if (is.null(dim(res))) {
    res <- matrix(res, ncol = 2, dimnames = list(NULL, c("indicator", "name")))
  }
  tibble::as_tibble(res)
}
