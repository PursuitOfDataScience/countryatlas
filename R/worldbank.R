# World Bank: data through the package's own client -------------------------------
#
# WDI::WDI() asks the API for one 32,500-row page, which is the request that
# answered 502 on 2026-10-01; it has no timeout or retry option; and it cannot
# address the WDI Database Archives (API source 57), so no figure could be
# pinned to the release it came from. World Bank *data* therefore comes through
# wdj_http_get() here, a few thousand rows a page, current and archived alike,
# and the response's `lastupdated` date is kept for the provenance it feeds.
# WDI stays in Imports for wdi_search() and its bundled catalogue.

WB_API <- "https://api.worldbank.org/v2"
WB_PER_PAGE <- 5000L

# A few countries carry pre-ISO World Bank codes in the archived releases. The
# current API speaks ISO 3166-1 alpha-3 throughout.
WB_LEGACY_ISO3 <- c(ADO = "AND", ZAR = "COD", TMP = "TLS", ROM = "ROU",
                    KSV = "XKX", WBG = "PSE")

# Read a vintage the way people write one -- "2024-07", "202407", 202407 or
# "2024 Jul" -- into the API's YYYYMM id. NULL is the current release.
wb_vintage_id <- function(vintage, call = rlang::caller_env()) {
  if (is.null(vintage)) return(NULL)
  if (length(vintage) != 1L || is.na(vintage) ||
      !(is.character(vintage) || is.numeric(vintage))) {
    wdj_abort(c(
      "{.arg vintage} must be one World Bank release, such as {.val 2024-07}.",
      "x" = "Got {.obj_type_friendly {vintage}}.",
      "i" = "{.fn wdi_vintages} lists the releases the archive holds."
    ), call = call)
  }
  v <- trimws(as.character(vintage))
  if (grepl("^[0-9]{4}-[0-9]{2}$", v)) v <- sub("-", "", v)
  if (grepl("^[0-9]{4} [A-Za-z]{3}$", v)) {
    m <- match(ascii_lower(substr(v, 6, 8)), ascii_lower(month.abb))
    if (!is.na(m)) v <- sprintf("%s%02d", substr(v, 1, 4), m)
  }
  if (!grepl("^[0-9]{6}$", v) || !as.integer(substr(v, 5, 6)) %in% 1:12) {
    wdj_abort(c(
      "{.arg vintage} must name a release as {.val YYYY-MM} or {.val YYYYMM}.",
      "x" = "Got {.val {as.character(vintage)}}.",
      "i" = "{.fn wdi_vintages} lists the releases the archive holds."
    ), call = call)
  }
  v
}

# "202407" -> "2024-07", the form the package reports.
wb_vintage_label <- function(id) {
  ifelse(is.na(id), NA_character_,
         paste0(substr(id, 1, 4), "-", substr(id, 5, 6)))
}

# One indicator, every country, `start` to `end`, from the current release
# (vintage NULL) or an archived one. Returns the frame WDI::WDI() returned --
# iso2c, country, the value named after the indicator, year, iso3c -- with the
# indicator's label, the release's last-update date and the vintage as
# attributes. This is the seam the fetch tests mock.
wb_request <- function(indicator, start, end, language = "en", vintage = NULL,
                       ...) {
  code <- unname(indicator)[1]
  name <- names(indicator)[1] %||% code
  if (is.null(vintage)) {
    wb_request_current(code, name, start, end, language)
  } else {
    wb_request_archive(code, name, start, end, vintage)
  }
}

# Every page of a current-release query.
wb_request_current <- function(code, name, start, end, language = "en") {
  page <- 1L
  rows <- list()
  meta <- NULL
  label <- NA_character_
  repeat {
    url <- sprintf(
      "%s/%s/country/all/indicator/%s?format=json&date=%d:%d&per_page=%d&page=%d",
      WB_API, utils::URLencode(language, reserved = TRUE),
      utils::URLencode(code, reserved = TRUE), as.integer(start),
      as.integer(end), WB_PER_PAGE, page)
    res <- wdj_http_get(url, accept = "application/json")
    js <- wb_parse_json(res, code)
    meta <- js$meta
    d <- js$data
    if (is.data.frame(d) && nrow(d)) {
      iso3 <- as.character(d$countryiso3code)
      iso3[!nzchar(iso3)] <- NA_character_
      rows[[length(rows) + 1L]] <- tibble::tibble(
        iso2c = as.character(d$country$id),
        country = as.character(d$country$value),
        !!name := suppressWarnings(as.numeric(d$value)),
        year = suppressWarnings(as.integer(d$date)), iso3c = iso3)
      if (is.na(label)) label <- as.character(d$indicator$value[1])
    }
    if (is.null(meta$pages) || page >= as.integer(meta$pages)) break
    page <- page + 1L
  }
  out <- if (length(rows)) dplyr::bind_rows(rows) else {
    tibble::tibble(iso2c = character(), country = character(),
                   !!name := numeric(), year = integer(), iso3c = character())
  }
  structure(out, wb_label = label,
            wb_lastupdated = meta$lastupdated %||% NA_character_,
            wb_vintage = NA_character_)
}

# Every page of an archived-release query. The archive (API source 57) speaks a
# different dialect: years are listed one by one ("YR2015;YR2016"; a range is
# refused) and a series the release does not hold answers with an XML error
# even when JSON was asked for.
wb_request_archive <- function(code, name, start, end, vintage) {
  id <- wb_vintage_id(vintage)
  years <- paste0("YR", seq(as.integer(start), as.integer(end)), collapse = ";")
  page <- 1L
  rows <- list()
  meta <- NULL
  repeat {
    url <- sprintf(
      "%s/sources/57/country/all/series/%s/version/%s/time/%s?format=json&per_page=%d&page=%d",
      WB_API, utils::URLencode(code, reserved = TRUE), id, years, WB_PER_PAGE,
      page)
    res <- wdj_http_get(url, accept = "application/json")
    txt <- http_text(res)
    if (grepl("^\\s*(\ufeff)?<", txt)) {
      if (grepl("not found|not valid", txt, ignore.case = TRUE)) {
        span <- if (start == end) start else paste0(start, "-", end)
        wdj_abort(c(
          "Release {.val {wb_vintage_label(id)}} of the World Development
           Indicators does not hold {.val {code}} for {span}.",
          "i" = "Availability varies by series and release."
        ), class = c("countryatlas_vintage_missing", "countryatlas_empty_fetch"),
        code = code, vintage = id)
      }
      wdj_abort("The World Bank archive answered with something other than
                 JSON for {.val {code}}.", class = "countryatlas_bad_response")
    }
    js <- jsonlite::fromJSON(txt, simplifyVector = TRUE)
    meta <- js
    dat <- js$source$data
    if (!is.null(dat) && NROW(dat)) rows[[length(rows) + 1L]] <- dat
    if (is.null(js$pages) || page >= as.integer(js$pages)) break
    page <- page + 1L
  }
  if (!length(rows)) {
    out <- tibble::tibble(iso2c = character(), country = character(),
                          !!name := numeric(), year = integer(),
                          iso3c = character())
    label <- NA_character_
  } else {
    d <- do.call(rbind, rows)
    pick <- function(concept, what) {
      vapply(d$variable, function(v) {
        x <- v[[what]][v$concept == concept]
        if (length(x)) as.character(x[1]) else NA_character_
      }, character(1))
    }
    raw_iso <- pick("Country", "id")
    iso3 <- ifelse(raw_iso %in% names(WB_LEGACY_ISO3),
                   unname(WB_LEGACY_ISO3[raw_iso]), raw_iso)
    out <- tibble::tibble(
      iso2c = suppressWarnings(countrycode::countrycode(iso3, "iso3c", "iso2c",
                                                        warn = FALSE)),
      country = pick("Country", "value"),
      !!name := suppressWarnings(as.numeric(d$value)),
      year = suppressWarnings(as.integer(pick("Time", "value"))),
      iso3c = iso3)
    # A legacy code and its ISO successor can both appear in one release
    # (ADO and AND for Andorra); keep the row that was already ISO.
    legacy <- raw_iso %in% names(WB_LEGACY_ISO3)
    out <- out[order(legacy), , drop = FALSE]
    out <- out[!duplicated(out[, c("iso3c", "year")]) | is.na(out$iso3c), ,
               drop = FALSE]
    label <- pick("Series", "value")[1]
  }
  structure(out, wb_label = label,
            wb_lastupdated = meta$lastupdated %||% NA_character_,
            wb_vintage = id)
}

# The current API's JSON: a two-element array of page metadata and rows, or a
# one-element array carrying an error message for a code it does not know.
wb_parse_json <- function(res, code) {
  js <- jsonlite::fromJSON(http_text(res), simplifyVector = TRUE)
  # The error form simplifies to a one-row data frame with a `message` column.
  if (is.data.frame(js) && "message" %in% names(js)) {
    msg <- js$message[[1]]
    txt <- paste(unlist(msg$value %||% msg), collapse = " ")
    wdj_abort(c(
      "The World Bank does not recognise {.val {code}}.",
      "x" = "{txt}"
    ), class = "countryatlas_empty_fetch")
  }
  if (!is.list(js) || length(js) < 2L) {
    wdj_abort("The World Bank answered with an unexpected shape for
               {.val {code}}.", class = "countryatlas_bad_response")
  }
  list(meta = js[[1]], data = js[[2]])
}

#' The World Development Indicators releases the archive holds
#'
#' Every release in the World Bank's WDI Database Archives (API source 57),
#' oldest first, so a figure can be pinned to the release it came from with
#' `vintage =` in [fetch_indicator()], [country_data()] and [world_data()].
#' The list is fetched once a day per session.
#'
#' @return A tibble of `vintage` (`"2024-07"`), `id` (the API's `"202407"`) and
#'   `label` (the API's own, `"2024 Jul"`). On a failed request, a warning and
#'   no rows, unless `options(countryatlas.strict = TRUE)`.
#' @seealso [compare_vintages()]
#' @export
#' @examples
#' \donttest{
#' tail(wdi_vintages())
#' }
wdi_vintages <- function() {
  memo <- .wdj_state$wdi_vintages
  if (!is.null(memo) && difftime(Sys.time(), memo$at, units = "days") < 1) {
    return(memo$value)
  }
  empty <- tibble::tibble(vintage = character(), id = character(),
                          label = character())
  out <- tryCatch({
    res <- wdj_http_get(sprintf("%s/sources/57/version?format=json&per_page=1000",
                                WB_API), accept = "application/json")
    js <- jsonlite::fromJSON(http_text(res), simplifyVector = TRUE)
    var <- js$source$concept[[1]]$variable[[1]]
    tb <- tibble::tibble(vintage = wb_vintage_label(var$id),
                         id = as.character(var$id), label = as.character(var$value))
    tb[order(tb$id), , drop = FALSE]
  }, countryatlas_fetch_failed = function(e) {
    fetch_failed(e, "the list of World Bank releases", empty)
  })
  if (nrow(out)) .wdj_state$wdi_vintages <- list(at = Sys.time(), value = out)
  out
}

# The releases nearest `id` that do hold `code` for `year`, for a "this
# release does not hold that series" message: availability varies by series
# and release, so the neighbours in the list are only candidates. Each is
# probed with a one-row request, nearest first, and the search stops after
# `n` hits or `max_probes` requests, so the message costs a bounded few
# hundred milliseconds.
wb_nearest_vintages <- function(id, code = NULL, year = NULL, n = 3L,
                                max_probes = 8L) {
  v <- tryCatch(suppressWarnings(wdi_vintages()), error = function(e) NULL)
  if (is.null(v) || !nrow(v) || is.null(id)) return(character())
  ids <- v$id[order(abs(as.numeric(v$id) - as.numeric(id)))]
  ids <- ids[ids != id]
  if (is.null(code) || is.null(year)) return(utils::head(ids, n))
  hits <- character()
  for (cand in utils::head(ids, max_probes)) {
    url <- sprintf(
      "%s/sources/57/country/all/series/%s/version/%s/time/YR%d?format=json&per_page=1",
      WB_API, utils::URLencode(code, reserved = TRUE), cand, as.integer(year))
    res <- tryCatch(wdj_http_get(url, accept = "application/json", retries = 0L),
                    error = function(e) NULL)
    if (!is.null(res) && !grepl("^\\s*(\ufeff)?<", http_text(res))) {
      hits <- c(hits, cand)
      if (length(hits) >= n) break
    }
  }
  hits
}

#' How much did a World Bank series change between releases?
#'
#' The same indicator, the same year, from several releases of the World
#' Development Indicators side by side. Revisions between releases of one
#' database are large enough to change cross-country results (Johnson, Larson,
#' Papageorgiou & Subramanian 2013 show this for growth rates), and they are
#' easy to miss because a figure looks the same whichever release it came
#' from. This makes the check one call.
#'
#' @param indicator One WDI indicator code, optionally named.
#' @param vintages Two or more releases, as in [wdi_vintages()]
#'   (`"2019-07"`), or `"current"` for the live release.
#' @param year The year to compare. `NULL` (default) uses the most recent year
#'   every release has values for.
#' @param countries Optional `iso3c` vector to restrict the comparison to.
#'
#' @return A tibble, one row per country and release: `iso3c`, `country`,
#'   `vintage`, `value`, and the `revision` and `rel_revision` from the first
#'   release listed. A summary per release -- the number of countries in both,
#'   the median absolute and absolute relative revision, and the shares of
#'   countries revised by more than 1% and 10% -- is attached as the
#'   `"countryatlas_revisions"` attribute.
#'
#' @section Units change between releases too:
#' A series can be rebased between releases -- GDP in constant 2010 US$ in one,
#' constant 2015 US$ in the next -- and then every country is "revised" by the
#' change of base. The series label of each release is compared, and a change
#' of unit warns (class `countryatlas_unit_mismatch`).
#'
#' @references
#' Johnson, S., Larson, W., Papageorgiou, C. & Subramanian, A. (2013). Is newer
#' better? Penn World Table revisions and their impact on growth estimates.
#' *Journal of Monetary Economics* 60(2), 255-274.
#' \doi{10.1016/j.jmoneco.2012.10.022}
#' @seealso [wdi_vintages()], [compare_sources()]
#' @export
#' @examples
#' \donttest{
#' compare_vintages("SP.POP.TOTL", c("2019-07", "current"), year = 2015)
#' }
compare_vintages <- function(indicator, vintages, year = NULL,
                             countries = NULL) {
  check_indicator(indicator)
  if (length(indicator) != 1L) {
    wdj_abort("{.arg indicator} must be a single code.")
  }
  if (!is.character(vintages) || length(vintages) < 2L || anyNA(vintages) ||
      anyDuplicated(vintages)) {
    wdj_abort(c(
      "{.arg vintages} must name at least two distinct releases.",
      "i" = 'Write them as {.val 2019-07}, or {.val current} for the live
             release; {.fn wdi_vintages} lists them.'
    ))
  }
  ids <- lapply(vintages, function(v) if (identical(v, "current")) NULL else
    wb_vintage_id(v))
  labels <- vapply(seq_along(vintages), function(i) {
    if (is.null(ids[[i]])) "current" else wb_vintage_label(ids[[i]])
  }, character(1))
  if (!is.null(year)) {
    year <- validate_years(year)
    if (length(year) != 1L) wdj_abort("{.arg year} must be a single year.")
  }
  if (!is.null(countries)) {
    countries <- unique(stats::na.omit(wdj_to_iso3c(countries, origin = "iso3c")))
  }
  code <- unname(indicator)
  span <- if (is.null(year)) c(1960L, as.integer(format(Sys.Date(), "%Y"))) else
    c(year, year)
  got <- lapply(seq_along(vintages), function(i) {
    d <- tryCatch(
      fetch_one_indicator(code, ".wdj_v", span[1], span[2], vintage = ids[[i]]),
      countryatlas_vintage_missing = function(e) {
        near <- wb_nearest_vintages(e$vintage, code, span[1])
        wdj_warn(c(
          "Release {.val {labels[i]}} does not hold {.val {code}}.",
          "i" = if (length(near)) "The nearest releases are
                 {.val {wb_vintage_label(near)}}."
        ), class = "countryatlas_vintage_missing")
        NULL
      },
      countryatlas_fetch_failed = function(e) {
        fetch_failed(e, sprintf("release %s of %s", labels[i], code), NULL)
      })
    if (is.null(d)) return(NULL)
    d <- d[!is.na(d$iso3c) & d$iso3c %in% wdj_known_iso3c() & !is.na(d$.wdj_v), ]
    if (!is.null(countries)) d <- d[d$iso3c %in% countries, ]
    list(data = d, label = attr(d, "wb_label"))
  })
  ok <- !vapply(got, is.null, logical(1))
  if (sum(ok) < 2L) {
    wdj_warn("Fewer than two releases returned data, so there is nothing to
              compare.", class = "countryatlas_no_data")
    return(tibble::tibble(iso3c = character(), country = character(),
                          vintage = character(), value = numeric(),
                          revision = numeric(), rel_revision = numeric()))
  }
  got <- got[ok]; labels <- labels[ok]
  units <- vapply(got, function(g) indicator_unit(g$label), character(1))
  if (length(unique(stats::na.omit(units))) > 1L) {
    wdj_warn(c(
      "{.val {code}} changes unit between releases, so part of every revision
       is the change of unit.",
      "*" = "{.val {paste0(labels, ': ', units)}}"
    ), class = "countryatlas_unit_mismatch")
  }
  if (is.null(year)) {
    yrs <- Reduce(intersect, lapply(got, function(g) unique(g$data$year)))
    if (!length(yrs)) {
      wdj_warn("The releases share no year with data.", class = "countryatlas_no_data")
      yrs <- NA_integer_
    }
    year <- max(yrs)
  }
  long <- dplyr::bind_rows(lapply(seq_along(got), function(i) {
    d <- got[[i]]$data
    d <- d[!is.na(d$year) & d$year == year, , drop = FALSE]
    d <- d[!duplicated(d$iso3c), , drop = FALSE]
    tibble::tibble(iso3c = d$iso3c, country = d$country, vintage = labels[i],
                   value = d$.wdj_v)
  }))
  base <- long[long$vintage == labels[1], c("iso3c", "value")]
  long$revision <- long$value - base$value[match(long$iso3c, base$iso3c)]
  long$rel_revision <- long$revision /
    abs(base$value[match(long$iso3c, base$iso3c)])
  long$rel_revision[!is.finite(long$rel_revision)] <- NA_real_
  long$vintage <- factor(long$vintage, levels = labels)
  long <- long[order(long$iso3c, long$vintage), , drop = FALSE]
  summ <- dplyr::bind_rows(lapply(labels[-1], function(v) {
    r <- long[long$vintage == v & !is.na(long$revision), , drop = FALSE]
    tibble::tibble(
      from = labels[1], to = v, year = year, n = nrow(r),
      median_abs_revision = if (nrow(r)) stats::median(abs(r$revision)) else NA_real_,
      median_abs_rel_revision = if (nrow(r)) stats::median(abs(r$rel_revision), na.rm = TRUE) else NA_real_,
      share_revised_1pct = if (nrow(r)) mean(abs(r$rel_revision) > 0.01, na.rm = TRUE) else NA_real_,
      share_revised_10pct = if (nrow(r)) mean(abs(r$rel_revision) > 0.10, na.rm = TRUE) else NA_real_)
  }))
  long$vintage <- as.character(long$vintage)
  attr(long, "countryatlas_revisions") <- summ
  long
}

# The unit a World Bank label states, which is its last parenthesised clause:
# "GDP per capita (constant 2015 US$)" -> "constant 2015 US$". NA when the
# label states none, as "Population, total" does.
indicator_unit <- function(label) {
  if (is.null(label) || !length(label) || is.na(label)) return(NA_character_)
  m <- regmatches(label, regexpr("\\(([^()]*)\\)\\s*$", label))
  if (!length(m)) return(NA_character_)
  gsub("^\\(|\\)\\s*$", "", m)
}

# The source_info() row for one fetched World Bank column. The current
# release is named by the month of its last update ("2026-07"), an archived
# one by its own id.
wb_source_info <- function(column, code, part) {
  lab <- attr(part, "wb_label") %||% NA_character_
  upd <- attr(part, "wb_lastupdated") %||% NA_character_
  vin <- attr(part, "wb_vintage") %||% NA_character_
  vintage <- if (!is.na(vin)) wb_vintage_label(vin) else
    if (!is.na(upd)) substr(upd, 1, 7) else NA_character_
  source_info_rows(
    column, source = "wdi", indicator = code, label = lab,
    unit = indicator_unit(lab), provider_updated = upd,
    fetched_at = attr(part, "wb_fetched_at") %||% NA_character_,
    vintage = vintage, licence = "CC BY 4.0",
    citation = paste0("World Bank. World Development Indicators",
                      if (!is.na(vintage)) paste0(", release ", vintage), "."))
}
