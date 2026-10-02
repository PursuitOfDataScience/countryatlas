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
#' @param warn Whether to report inputs that match neither a historical entity
#'   nor a modern country (default `TRUE`), as [dissolve_country()] does.
#'
#' @return A tibble, one row per input: `input`, `iso3c`, `country`,
#'   `dissolved` (the year it ceased to exist, or `NA` if it still does),
#'   `predecessors` and `successors` (list-columns of `iso3c` codes). An input
#'   that resolves to neither spine keeps its `input` and gets `NA` elsewhere;
#'   with `warn = TRUE` it is reported rather than left to be spotted.
#'
#' @section Why the two directions are not mirror images:
#' Both columns hold codes, so an entity ISO never coded cannot appear in
#' either. ISO 3166-3 only records changes from 1974 on, and three entities in
#' [historical_codes] predate it: the United Arab Republic (1961), Tanganyika
#' and Zanzibar (both 1964). Asking about one of those by name works --
#' `country_timeline("Tanganyika")` gives `TZA` as a successor, because the
#' table stores that side as a name -- but the reverse does not:
#' `country_timeline("TZA")` reports no predecessors, since there is no code to
#' report. The other eleven entities carry codes and round-trip in both
#' directions. Naming them instead of coding them would break the column's
#' type; inventing codes for them would be a guess, which this package does
#' not make.
#'
#' @seealso [dissolve_country()], [historical_codes], [audit_time_coverage()]
#' @export
#' @examples
#' country_timeline(c("USSR", "Estonia", "France"))
country_timeline <- function(x, origin = "country.name", warn = TRUE) {
  check_bool(warn, "warn")
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
        suppressWarnings(convert_country(code, origin = "iso3c", to = "country",
                                         warn = FALSE)),
      dissolved = NA_integer_,
      predecessors = list(preds), successors = list(character(0))
    )
  })
  out <- dplyr::bind_rows(rows)
  # wdj_to_iso3c()'s own warning is suppressed above on purpose -- a historical
  # name like "USSR" is *meant* to fail that lookup and be picked up by the
  # branch above -- but that left an input matching *neither* spine reported by
  # nothing at all: the row came back all NA, reading as a country with no
  # recorded history rather than a name nobody recognised. dissolve_country()
  # takes the same input shape and has warned about exactly this all along, so
  # this is its message, down to the {.fn check_country_match} pointer.
  if (isTRUE(warn)) {
    # "Matched neither" has to mean that, not "has no code". Three entities in
    # the table predate ISO 3166-3 and carry no code at all (Tanganyika,
    # Zanzibar and the United Arab Republic), so their rows resolve through
    # the historical branch with `iso3c` NA, and keying on that told the
    # caller that "Tanganyika" matched nothing while handing back its
    # dissolution year and its successor. A missing input is not a name that
    # failed to match either; standardize_country() leaves those unreported.
    hist_hit <- !is.na(canon) & canon %in% hc$historical
    miss <- unique(out$input[is.na(out$iso3c) & !hist_hit & !is.na(out$input)])
    if (length(miss)) {
      wdj_warn(c(
        "{length(miss)} name{?s} matched neither a historical entity nor a
         modern country:",
        "*" = "{.val {miss}}",
        "i" = "See {.fn check_country_match} for close-name suggestions."
      ))
    }
  }
  out
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
#' @return A tibble of the offending rows: `iso3c`, `country`, `year`, `issue`,
#'   `existed` (a human-readable span) and `basis` (where the dates come
#'   from). `issue` is `"before_existence"` or `"after_dissolution"` -- the
#'   country did not exist -- or the milder `"before_independence"`: it
#'   existed, but was not yet (or not then) an independent state. Zero rows
#'   means the panel is clean.
#'
#' @section What it can and cannot see:
#' Dissolution dates come from [historical_codes], which covers the entities the
#' package curates (USSR, Yugoslavia, Czechoslovakia and the rest), and a
#' successor state is treated as not existing before its predecessor
#' dissolved (`basis = "historical_codes"`).
#'
#' Independence comes from Gleditsch & Ward's list of independent states since
#' 1816 (Gleditsch & Ward 1999, through the `states` package), with every spell
#' of independence: Namibia from 1990, Eritrea from 1993, Timor-Leste from
#' 2002, and Estonia from 1918 to 1940 and again from 1991. A year inside an
#' earlier spell also corrects the crosswalk for a state it dates from a later
#' succession (Estonia's interwar years). A year outside
#' every spell is `"before_independence"` (`basis = "gleditsch_ward"`). That
#' is statehood, not data availability -- a colony often reports statistics
#' before independence, and a World Bank series may legitimately start there --
#' so it is a separate, lower-severity issue, for the caller to judge.
#' Territories that are not on the list are assumed to have existed
#' throughout, so a clean result still means "nothing these lists know about
#' is wrong", not "every date is right".
#'
#' @references
#' Gleditsch, K. S. & Ward, M. D. (1999). A revised list of independent states
#' since the congress of Vienna. *International Interactions* 25(4), 393-413.
#' \doi{10.1080/03050629908434958}
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
  # as.character(), because df$iso3c indexes the named lookup vectors below and
  # a FACTOR index selects by the factor's integer CODES, not its labels. A
  # frame from read.csv(stringsAsFactors = TRUE) therefore matched whichever
  # rows of historical_codes happened to sit at those positions: it reported
  # France dissolved in 1993, Italy in 1992 and Germany as existing only from
  # 2010, from the one verb whose job is catching exactly that kind of mistake.
  # Same class as the read_year() note below, on the other key.
  df$iso3c <- as.character(df$iso3c)
  if (!nrow(df)) {
    return(tibble::tibble(iso3c = character(0), country = character(0),
                          year = integer(0), issue = character(0),
                          existed = character(0), basis = character(0)))
  }
  # read_year(), not as.integer(): a Date year column became a column of day
  # counts (1990-01-01 -> 7305), and the existence audit then flagged rows as
  # "after dissolution" on the strength of it -- silently wrong output from the
  # one verb whose job is catching exactly that kind of mistake.
  df$year <- read_year(df$year, "{.arg data}")

  # `historical_codes` conflates two relations and this read every row as the
  # first, so a plain world_data(1960:2020) panel came back with about a hundred
  # confident false alarms from the one verb whose job is catching exactly this
  # class of error: Yemen, Sudan and Vietnam reported "after dissolution" though
  # all three exist, Germany and Egypt reported "before existence" from 1990 and
  # 1961, and Sudan was flagged in *both* directions. The `relation` column
  # distinguishes them.
  #
  # A dissolved entity must not carry data after it dissolved -- but only if it
  # really dissolved. A code that is listed among its own successors continued
  # (with less territory, or under a new government), so it has no end date:
  # `?historical_codes` warns that a code "may since have been inherited by a
  # successor (e.g. YEM)", which is that case exactly.
  ended <- hc[hc$relation == "succession" &
                (is.na(hc$iso3c_hist) | hc$iso3c_hist != hc$iso3c), , drop = FALSE]
  still_here <- unique(hc$iso3c[hc$relation == "continuation"])
  ended <- ended[!is.na(ended$iso3c_hist) & !ended$iso3c_hist %in% still_here, ,
                 drop = FALSE]
  dis <- stats::setNames(ended$dissolved[!duplicated(ended$iso3c_hist)],
                         ended$iso3c_hist[!duplicated(ended$iso3c_hist)])
  born <- successor_born_years(hc)

  df$dissolved_in <- unname(dis[df$iso3c])
  df$born_in <- unname(born[df$iso3c])
  # !is.na(year): read_year() turns a value it cannot read into NA (and warns
  # that it has), and `NA > 1991` is NA, which, used as an index below,
  # produced a row of all-NA columns. A dissolved code carrying one unreadable
  # year therefore reported a phantom "NA, after_dissolution, until NA" row,
  # and the console summary counted it.
  after <- !is.na(df$dissolved_in) & !is.na(df$year) &
    df$year > df$dissolved_in
  before <- !is.na(df$born_in) & !is.na(df$year) & df$year < df$born_in

  # Independence, from the Gleditsch-Ward spells: a year inside no spell, for
  # a country on the list, and not already flagged above. An earlier spell
  # also overrules the crosswalk's "before existence": historical_codes dates
  # Estonia from the Soviet Union's dissolution, and Estonia was an
  # independent state from 1918 to 1940 as well. Only a spell that ended
  # before that date counts: GW's Russia runs through 1991 as the Soviet
  # Union's continuation, which is the view the crosswalk does not take.
  ind <- independence_gaps(df$iso3c, df$year)
  before <- before & !(ind$covered & !is.na(ind$cover_end) &
                         ind$cover_end < df$born_in)
  ind_flag <- ind$flag & !after & !before
  out <- dplyr::bind_rows(
    tibble::tibble(iso3c = df$iso3c[after], year = df$year[after],
                   issue = "after_dissolution",
                   existed = paste0("until ", df$dissolved_in[after]),
                   basis = "historical_codes"),
    tibble::tibble(iso3c = df$iso3c[before], year = df$year[before],
                   issue = "before_existence",
                   existed = paste0("from ", df$born_in[before]),
                   basis = "historical_codes"),
    tibble::tibble(iso3c = df$iso3c[ind_flag], year = df$year[ind_flag],
                   issue = "before_independence",
                   existed = ind$spans[ind_flag], basis = "gleditsch_ward")
  )
  if (nrow(out)) {
    out$country <- suppressWarnings(
      convert_country(out$iso3c, origin = "iso3c", to = "country", warn = FALSE))
    # countrycode has no name for a dissolved entity's code (SUN, YUG, CSK,
    # DDR), so the rows this audit exists to flag came back with `country`
    # NA. historical_codes names them.
    unnamed <- is.na(out$country)
    out$country[unnamed] <- hc$historical[match(out$iso3c[unnamed], hc$iso3c_hist)]
    out <- out[, c("iso3c", "country", "year", "issue", "existed", "basis")]
    out <- dplyr::arrange(out, .data$iso3c, year_sort_key(.data$year))
  } else {
    out <- tibble::tibble(iso3c = character(0), country = character(0),
                          year = integer(0), issue = character(0),
                          existed = character(0), basis = character(0))
  }
  if (!quiet) {
    if (nrow(out)) {
      wdj_inform(c(
        "!" = "{nrow(out)} row{?s} fall{?s/} outside the country's existence
               or independence.",
        "i" = "Inspect the returned table; {.fn dissolve_country} resolves
               historical entities to successors."
      ))
    } else {
      wdj_inform(c("v" = "No rows fall outside a known existence span."))
    }
  }
  out
}

# For each (iso3c, year): is the year outside every Gleditsch-Ward spell of
# independence for a country on the list, and the spans as words. A spell
# covers a year it starts or ends in.
independence_gaps <- function(iso3c, year) {
  ls <- country_lifespans[country_lifespans$basis == "gleditsch_ward", , drop = FALSE]
  y0 <- as.integer(format(ls$from, "%Y"))
  y1 <- as.integer(format(ls$to, "%Y"))
  span_txt <- ifelse(is.na(y0) & is.na(y1), "throughout",
              ifelse(is.na(y1), paste0("from ", y0),
              ifelse(is.na(y0), paste0("until ", y1), paste0(y0, "-", y1))))
  spans <- tapply(span_txt, ls$iso3c, function(z) paste0("independent ", paste(z, collapse = ", ")))
  flag <- logical(length(iso3c))
  covered <- logical(length(iso3c))
  cover_end <- rep(NA_integer_, length(iso3c))
  on_list <- iso3c %in% ls$iso3c & !is.na(year)
  for (cc in unique(iso3c[on_list])) {
    rows <- which(on_list & iso3c == cc)
    k <- ls$iso3c == cc
    sk <- which(k)
    hit <- vapply(year[rows], function(y) {
      j <- sk[(is.na(y0[sk]) | y >= y0[sk]) & (is.na(y1[sk]) | y <= y1[sk])]
      if (length(j)) j[1] else NA_integer_
    }, integer(1))
    flag[rows] <- is.na(hit)
    covered[rows] <- !is.na(hit)
    cover_end[rows] <- y1[hit]
  }
  list(flag = flag, covered = covered, cover_end = cover_end,
       spans = as.vector(unname(spans[iso3c])))
}

# The year each successor state came into existence, by the crosswalk: a
# successor must not carry data (or a code) before its predecessor dissolved --
# but only where it was genuinely created then. A continuation was not, so
# testing it against that year says nothing. Where a country succeeds several
# entities, the earliest date wins. Named by iso3c. Shared by
# audit_time_coverage() and historical_geometry(), which must agree about when
# a country began.
successor_born_years <- function(hc = countryatlas::historical_codes) {
  still_here <- unique(hc$iso3c[hc$relation == "continuation"])
  succ <- hc[hc$relation == "succession", , drop = FALSE]
  succ <- succ[!is.na(succ$iso3c) & !succ$iso3c %in% still_here, , drop = FALSE]
  if (!nrow(succ)) return(stats::setNames(numeric(0), character(0)))
  tapply(succ$dissolved, succ$iso3c, min)
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
#'   assigned -- see below), `status`, `from`, `to` and geometry. Two further
#'   CShapes columns are passed through when the installed version supplies
#'   them, since they answer the questions this verb is usually asked:
#'   * `owner` -- the `gwcode` of the sovereign a dependency belonged to; a
#'     sovereign state carries its own `gwcode` here. This is the column that
#'     makes `dependencies = TRUE` legible: without it a colony and its
#'     metropole are two unrelated rows. `owner != gwcode` picks out the
#'     dependencies.
#'   * `capname` -- the capital's name at that date.
#'
#'   Both were returned but undocumented. Neither is guaranteed: `cshapes`
#'   decides what its own table holds, so check with `names()` rather than
#'   assuming.
#'
#' @section The ISO spine does not reach back:
#' ISO 3166 was first published in 1974 and never covered colonies, so a
#' historical map cannot be keyed on `iso3c`. CShapes uses **Gleditsch-Ward**
#' codes, which is why `gwcode` is the key here and `iso3c` is a best-effort
#' extra, read off the GW code: the modern code of the state that holds it.
#' So it is `NA` for an entity with no modern counterpart (the German
#' Democratic Republic, Czechoslovakia, Yugoslavia, the two Yemens), and also
#' where [historical_codes] says the modern state did not exist yet -- GW give
#' the USSR and Russia one code, but the 1980 polygon is the Soviet Union, so
#' it carries `NA` rather than `"RUS"`. A colony carries the code of the state
#' it became: CShapes names the 1950 Gold Coast "Ghana" and it comes back as
#' `"GHA"`, with `status` saying it was a colony. Join historical data on
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
    # is.finite(), not is.na(): Inf passed, reached as.integer() (NA, with
    # base R's "NAs introduced by coercion to integer range") and then
    # as.Date("NA-06-30"), which failed on "character string is not in a
    # standard unambiguous format".
    if (!is.numeric(year) || length(year) != 1L || !is.finite(year)) {
      wdj_abort(c("{.arg year} must be a single year or {.cls Date}.",
                  "x" = "Got {.val {year}}."))
    }
    # A finite year past integer range (1e10) hit the same as.integer() NA,
    # so clamp it into a range that still fails the coverage check below.
    as.Date(sprintf("%d-06-30",                      # mid-year, a stable choice
                    as.integer(min(max(year, 1L), 9999L))))
  }
  span <- c(as.Date("1886-01-01"), as.Date("2019-12-31"))
  if (when < span[1] || when > span[2]) {
    # The caller's own value, not the clamped date built from it above.
    asked <- if (inherits(year, "Date")) format(when, "%Y-%m-%d") else format(year)
    wdj_abort(c(
      "CShapes covers 1886-2019.",
      "x" = "Asked for {.val {asked}}.",
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
  # A GW code can outlive the state that held it. Gleditsch-Ward give the USSR
  # and Russia one code, 365, so the crosswalk labelled the 1980 Soviet Union
  # "RUS" -- and attach_geometry(year = 1980) painted all fifteen republics
  # with Russia's value, the very anachronism audit_time_coverage() flags as
  # "before_existence", because the package's own historical_codes records
  # Russia as one of fifteen *successors*, born in 1991. Czechoslovakia,
  # Yugoslavia and the GDR already came back NA; a code for a state the
  # crosswalk says did not exist yet goes the same way.
  born <- successor_born_years()
  yr <- as.integer(format(when, "%Y"))
  early <- !is.na(g$iso3c) & g$iso3c %in% names(born)
  early[early] <- yr < born[g$iso3c[early]]
  g$iso3c[early] <- NA_character_
  keep <- intersect(c("gwcode", "country", "iso3c", "status", "owner",
                      "capname", "from", "to"), names(g))
  g <- g[, c(keep, attr(g, "sf_column"))]
  if (!is.null(projection)) {
    g <- quietly_sf(sf::st_transform(g, wdj_crs(projection)))
  }
  g
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
  # A row with no year has no place in the series, so nothing is carried or
  # interpolated into it: sorted last, "locf" filled it from the latest real
  # year and flagged the result as imputed.
  keep <- !is.na(x)
  xn <- suppressWarnings(as.numeric(as.character(x)))
  # Only a year that is present and unreadable disables the span check. A
  # missing one used to as well, silently switching the whole series from
  # "years between observations" back to a row count.
  if (anyNA(xn[!is.na(x)])) xn <- NULL
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
  #
  # Only the cells that were missing. `filled` is the whole series recomputed,
  # and for an observed row that is the observed value, except where the
  # filler cannot place the row at all, as approx() cannot for a row with no
  # year, which came back NA and was written over a value that had been there.
  fill <- keep & na
  out <- y
  out[fill] <- filled[fill]
  out
}
