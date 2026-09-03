# Time: historical geometry, existence spans and time-aware auditing -------------
#
# 2.0.0 solved the *code* half of history: historical_codes + dissolve_country()
# resolve "USSR" to fifteen successors, and check_country_match() catches
# countrycode silently mapping it to Russia alone. What was missing is the
# *geometry and membership* half -- a 1970 map still drew 2024 borders. This
# module closes that.
#
# The awkward truth this has to confront: the ISO 3166 spine does not reach
# back. ISO 3166 was published in 1974, and colonies never had codes at all, so
# a pre-1970 map cannot be keyed on iso3c. CShapes is keyed on
# Gleditsch-Ward codes, which countrycode already converts, so historical work
# gets a second spine and says so rather than silently matching a fraction of
# the world.

#' A country's existence span, predecessors and successors
#'
#' When did this country exist, and what came before and after it? Reads the
#' bundled [historical_codes] crosswalk in both directions -- so it answers both
#' "what did the USSR become" and "what was Estonia part of".
#'
#' @param x Country names or codes, current or historical (`"USSR"`,
#'   `"Yugoslavia"`, `"Estonia"`, `"DEU"`).
#' @param origin How to read `x` (default `"country.name"`).
#'
#' @return A tibble, one row per input: `input`, `iso3c`, `country`,
#'   `dissolved` (the year it ceased to exist, or `NA` if it still does),
#'   `predecessors` and `successors` (list-columns of `iso3c` codes).
#'
#' @seealso [dissolve_country()], [historical_codes], [audit_time_coverage()]
#' @export
#' @examples
#' country_timeline(c("USSR", "Estonia", "France"))
country_timeline <- function(x, origin = "country.name") {
  if (!length(x)) {
    return(tibble::tibble(input = character(0), iso3c = character(0),
                          country = character(0), dissolved = integer(0),
                          predecessors = list(), successors = list()))
  }
  hc <- countryatlas::historical_codes
  # normalize_historical() only lower-cases; historical_aliases() is what maps
  # "USSR" onto the table's canonical "Soviet Union". Comparing the lower-cased
  # input straight to hc$historical matched nothing, so every historical entity
  # fell through to the modern-country branch and "USSR" came back as Russia --
  # precisely the silent mis-resolution check_country_match() exists to catch.
  canon <- unname(historical_aliases()[normalize_historical(as.character(x))])
  iso <- suppressWarnings(wdj_to_iso3c(x, origin = origin))

  rows <- lapply(seq_along(x), function(i) {
    nm <- canon[i]
    # Is the input itself a dissolved entity?
    as_hist <- if (is.na(nm)) hc[0, ] else hc[hc$historical == nm, ]
    if (nrow(as_hist)) {
      return(tibble::tibble(
        input = as.character(x)[i], iso3c = as_hist$iso3c_hist[1],
        country = as_hist$historical[1], dissolved = as_hist$dissolved[1],
        predecessors = list(character(0)),
        successors = list(sort(unique(as_hist$iso3c)))
      ))
    }
    # Otherwise: a current country, which may have predecessors.
    code <- iso[i]
    preds <- if (!is.na(code)) sort(unique(hc$iso3c_hist[hc$iso3c == code])) else character(0)
    tibble::tibble(
      input = as.character(x)[i], iso3c = code,
      country = if (is.na(code)) NA_character_ else
        suppressWarnings(convert_country(code, from = "iso3c", to = "country",
                                         warn = FALSE)),
      dissolved = NA_integer_,
      predecessors = list(preds), successors = list(character(0))
    )
  })
  dplyr::bind_rows(rows)
}

#' Does the data respect when countries existed?
#'
#' The time-aware counterpart to [audit_coverage()]. A join can succeed and
#' still be wrong about history: South Sudan with 1995 data, Czechoslovakia with
#' 2001 data, the USSR with 2010 data. Those rows survive every check the package
#' had, because the country resolves and the year is a number.
#'
#' @param data A panel with `iso3c` and `year`.
#' @param quiet Suppress the console summary and return the table silently.
#'   (Unlike [audit_coverage()], which returns a printable object and emits
#'   nothing until you print it, this one reports as it goes -- a clean panel is
#'   the common case and worth confirming out loud.)
#'
#' @return A tibble of the offending rows: `iso3c`, `country`, `year`, `issue`
#'   (`"before_existence"` or `"after_dissolution"`) and `existed` (a
#'   human-readable span). Zero rows means the panel is clean.
#'
#' @section What it can and cannot see:
#' Dissolution dates come from [historical_codes], which covers the entities the
#' package curates (USSR, Yugoslavia, Czechoslovakia and the rest). Independence
#' dates come from the same table read in reverse: a successor state is treated
#' as not existing before its predecessor dissolved. Countries with no entry in
#' the crosswalk -- most of the world -- are assumed to have existed throughout,
#' so a clean result means "nothing the crosswalk knows about is wrong", not
#' "every date is right".
#'
#' @seealso [audit_coverage()], [dissolve_country()], [country_timeline()]
#' @export
#' @examples
#' panel <- data.frame(
#'   iso3c = c("SSD", "CZE", "FRA"),
#'   year  = c(1995L, 2001L, 2001L),
#'   gdp   = c(1, 2, 3)
#' )
#' audit_time_coverage(panel)
audit_time_coverage <- function(data, quiet = FALSE) {
  check_bool(quiet, "quiet")
  if (!all(c("iso3c", "year") %in% names(data))) {
    wdj_abort("{.arg data} must have {.field iso3c} and {.field year} columns.")
  }
  hc <- countryatlas::historical_codes
  df <- tibble::as_tibble(sf_drop(data))[, c("iso3c", "year")]
  df <- dplyr::distinct(df[!is.na(df$iso3c) & !is.na(df$year), ])
  if (!nrow(df)) {
    return(tibble::tibble(iso3c = character(0), country = character(0),
                          year = integer(0), issue = character(0),
                          existed = character(0)))
  }
  # read_year(), not as.integer(): a Date year column became a column of day
  # counts (1990-01-01 -> 7305), and the existence audit then flagged rows as
  # "after dissolution" on the strength of it -- silently wrong output from the
  # one verb whose job is catching exactly that kind of mistake.
  df$year <- read_year(df$year, "{.arg data}")

  # A dissolved entity must not carry data after it dissolved.
  dis <- stats::setNames(hc$dissolved[!duplicated(hc$iso3c_hist)],
                         hc$iso3c_hist[!duplicated(hc$iso3c_hist)])
  # A successor state must not carry data before its predecessor dissolved.
  # Where a country succeeds several entities, the earliest date wins.
  born <- tapply(hc$dissolved, hc$iso3c, min)

  df$dissolved_in <- unname(dis[df$iso3c])
  df$born_in <- unname(born[df$iso3c])
  after <- !is.na(df$dissolved_in) & df$year > df$dissolved_in
  before <- !is.na(df$born_in) & df$year < df$born_in

  out <- dplyr::bind_rows(
    tibble::tibble(iso3c = df$iso3c[after], year = df$year[after],
                   issue = "after_dissolution",
                   existed = paste0("until ", df$dissolved_in[after])),
    tibble::tibble(iso3c = df$iso3c[before], year = df$year[before],
                   issue = "before_existence",
                   existed = paste0("from ", df$born_in[before]))
  )
  if (nrow(out)) {
    out$country <- suppressWarnings(
      convert_country(out$iso3c, from = "iso3c", to = "country", warn = FALSE))
    out <- out[, c("iso3c", "country", "year", "issue", "existed")]
    out <- dplyr::arrange(out, .data$iso3c, .data$year)
  } else {
    out <- tibble::tibble(iso3c = character(0), country = character(0),
                          year = integer(0), issue = character(0),
                          existed = character(0))
  }
  if (!quiet) {
    if (nrow(out)) {
      wdj_inform(c(
        "!" = "{nrow(out)} row{?s} fall{?s/} outside the country's existence.",
        "i" = "Inspect the returned table; {.fn dissolve_country} resolves
               historical entities to successors."
      ))
    } else {
      wdj_inform(c("v" = "No rows fall outside a known existence span."))
    }
  }
  out
}

#' Historical country boundaries
#'
#' Country polygons as they were, from CShapes 2.0 (Schvitz et al. 2022), which
#' maps states *and* colonies and dependencies for 1886-2019 with per-polygon
#' validity periods. A 1970 map with 2024 borders is a common and quiet error;
#' this is the fix.
#'
#' @param year The year to draw, or a `Date` for a specific day. CShapes covers
#'   1886-2019.
#' @param dependencies Include colonies and dependencies (default `FALSE`,
#'   matching `cshapes`). For any pre-decolonisation map you almost certainly
#'   want `TRUE` -- most of Africa and Asia is otherwise absent.
#' @param projection Projection to return the geometry in (see [world_map()]),
#'   or `NULL` for unprojected lon/lat.
#'
#' @return An `sf` frame with `gwcode`, `country`, `iso3c` (where one can be
#'   assigned -- see below), `status`, `from`, `to` and geometry.
#'
#' @section The ISO spine does not reach back:
#' ISO 3166 was first published in 1974 and never covered colonies, so a
#' historical map cannot be keyed on `iso3c`. CShapes uses **Gleditsch-Ward**
#' codes, which is why `gwcode` is the key here and `iso3c` is a best-effort
#' extra: it is `NA` for every entity that never had an ISO code (French West
#' Africa, the Gold Coast, the USSR before 1974). Join historical data on
#' `gwcode`, not on `iso3c`, and use [convert_country()]`(to = "gwn")` to get
#' there from a modern code.
#'
#' @references
#' Schvitz, G., Girardin, L., Ruegger, S., Weidmann, N. B., Cederman, L.-E. &
#' Gleditsch, K. S. (2022). Mapping the international system, 1886-2019: The
#' CShapes 2.0 dataset. *Journal of Conflict Resolution* 66(1), 144-161.
#' \doi{10.1177/00220027211013563}
#'
#' @seealso [world_geometry()], [country_timeline()], [world_map()]
#' @export
#' @examples
#' \dontrun{
#' # Africa before decolonisation needs the dependencies
#' historical_geometry(1950, dependencies = TRUE)
#' }
historical_geometry <- function(year, dependencies = FALSE,
                                projection = "equal_earth") {
  need_pkg(c("cshapes", "sf"), "for historical_geometry()")
  check_bool(dependencies, "dependencies")
  # Deliberately not validate_years(): that is scoped to WDI's 1960-onward
  # range, and the whole point here is the century before it.
  when <- if (inherits(year, "Date")) {
    if (length(year) != 1L || is.na(year)) {
      wdj_abort("{.arg year} must be a single non-missing date.")
    }
    year
  } else {
    if (!is.numeric(year) || length(year) != 1L || is.na(year)) {
      wdj_abort(c("{.arg year} must be a single year or {.cls Date}.",
                  "x" = "Got {.val {year}}."))
    }
    as.Date(sprintf("%d-06-30", as.integer(year)))   # mid-year, a stable choice
  }
  span <- c(as.Date("1886-01-01"), as.Date("2019-12-31"))
  if (when < span[1] || when > span[2]) {
    wdj_abort(c(
      "CShapes covers 1886-2019.",
      "x" = "Asked for {.val {format(when, '%Y-%m-%d')}}.",
      "i" = "For the present day use {.fn world_geometry}."
    ))
  }
  g <- cshapes::cshp(date = when, useGW = TRUE, dependencies = dependencies)
  g <- sf::st_as_sf(g)
  names(g)[names(g) == "country_name"] <- "country"
  names(g)[names(g) == "start"] <- "from"
  names(g)[names(g) == "end"] <- "to"
  # Best effort only, and NA for anything that never had an ISO code -- see the
  # section above. This is the join key people reach for by habit, so it is
  # provided, but gwcode is the one that is actually complete.
  g$iso3c <- suppressWarnings(
    countrycode::countrycode(g$gwcode, "gwn", "iso3c", warn = FALSE))
  keep <- intersect(c("gwcode", "country", "iso3c", "status", "owner",
                      "capname", "from", "to"), names(g))
  g <- g[, c(keep, attr(g, "sf_column"))]
  if (!is.null(projection)) {
    g <- quietly_sf(sf::st_transform(g, wdj_crs(projection)))
  }
  g
}
