# SDMX: one reader for the statistical agencies --------------------------------------
#
# fetch_oecd() went through the OECD package, whose client still targets
# OECD.Stat -- offline since 2024-07-01, so the adapter could not return a row.
# The replacement services speak SDMX, and SDMX-CSV is a standard that
# utils::read.csv() parses, so one reader serves the OECD, the IMF, the ILO,
# Eurostat, the ECB, the BIS and UNICEF with no client package at all. Each
# provider is a row of a table: where its REST service lives, what to ask for
# to get CSV, and which dimension holds the country.

sdmx_providers <- function() {
  tibble::tribble(
    ~provider,  ~base,                                                   ~accept,                                       ~country_dim, ~origin,    ~structure, ~retry_403,
    "oecd",     "https://sdmx.oecd.org/public/rest",                     "application/vnd.sdmx.data+csv;version=1.0.0", "REF_AREA",   "iso3c",    "sdmx21",   FALSE,
    "imf",      "https://api.imf.org/external/sdmx/2.1",                 "application/vnd.sdmx.data+csv;version=1.0.0", "COUNTRY",    "iso3c",    "imf30",    FALSE,
    "ilo",      "https://sdmx.ilo.org/rest",                             "application/vnd.sdmx.data+csv;version=1.0.0", "REF_AREA",   "iso3c",    "sdmx21",   TRUE,
    "eurostat", "https://ec.europa.eu/eurostat/api/dissemination/sdmx/2.1", "application/vnd.sdmx.data+csv;version=1.0.0", "geo",   "eurostat", NA,         FALSE,
    "ecb",      "https://data-api.ecb.europa.eu/service",                "text/csv",                                    "REF_AREA",   "iso2c",    NA,         FALSE,
    "bis",      "https://stats.bis.org/api/v1",                          "application/vnd.sdmx.data+csv;version=1.0.0", "REF_AREA",   "iso2c",    NA,         FALSE,
    "unicef",   "https://sdmx.data.unicef.org/ws/public/sdmxapi/rest",   "application/vnd.sdmx.data+csv;version=1.0.0", "REF_AREA",   "iso3c",    NA,         FALSE
  )
}

# "AGENCY,ID,VERSION", "AGENCY,ID" or "ID", as SDMX writes a dataflow.
sdmx_flow <- function(flow, call = rlang::caller_env()) {
  parts <- strsplit(flow, ",", fixed = TRUE)[[1]]
  parts <- trimws(parts)
  if (!length(parts) || length(parts) > 3L || any(!nzchar(parts)) ||
      any(grepl("[/?&#\\s]", parts, perl = TRUE))) {
    wdj_abort(c(
      "{.arg flow} must be an SDMX dataflow: {.val AGENCY,ID,VERSION},
       {.val AGENCY,ID} or {.val ID}.",
      "x" = "Got {.val {flow}}.",
      "i" = 'For example {.val OECD.SDD.NAD,DSD_NAAG@DF_NAAG_I,1.0}.'
    ), call = call)
  }
  list(agency = if (length(parts) >= 2L) parts[1] else NA_character_,
       id = parts[if (length(parts) >= 2L) 2L else 1L],
       version = if (length(parts) == 3L) parts[3] else NA_character_,
       ref = paste(parts, collapse = ","))
}

# The dimension ids of a dataflow, in key order, or NULL where the provider
# offers no structure the reader can parse. Asked once per flow per session.
sdmx_dimensions <- function(prov, fl) {
  if (is.na(prov$structure) || is.na(fl$agency)) return(NULL)
  memo_key <- paste(prov$provider, fl$ref)
  hit <- .wdj_state$sdmx_dims[[memo_key]]
  if (!is.null(hit)) return(hit)
  url <- switch(
    prov$structure,
    sdmx21 = sprintf("%s/dataflow/%s/%s/%s?references=datastructure", prov$base,
                     fl$agency, fl$id, if (is.na(fl$version)) "latest" else fl$version),
    imf30 = sprintf("https://api.imf.org/external/sdmx/3.0/structure/dataflow/%s/%s/%s?references=datastructure",
                    fl$agency, fl$id, if (is.na(fl$version)) "+" else fl$version))
  accept <- if (identical(prov$structure, "imf30")) "application/json" else
    "application/vnd.sdmx.structure+json;version=1.0"
  dims <- tryCatch({
    js <- http_json(wdj_http_get(url, accept = accept,
                                 retry_403 = isTRUE(prov$retry_403)),
                    simplifyVector = TRUE)
    d <- js$data$dataStructures$dataStructureComponents$dimensionList$dimensions[[1]]
    d <- d[order(d$position), , drop = FALSE]
    as.character(d$id)
  }, error = function(e) NULL)
  if (!is.null(dims)) {
    if (is.null(.wdj_state$sdmx_dims)) .wdj_state$sdmx_dims <- list()
    .wdj_state$sdmx_dims[[memo_key]] <- dims
  }
  dims
}

# Put `countries` into the country slot of `key`. Without a structure to say
# where that slot is, the key is left as given and the countries are filtered
# after the download instead.
sdmx_key <- function(key, dims, prov, countries, call = rlang::caller_env()) {
  if (is.null(dims)) return(list(key = key %||% "all", server_side = FALSE))
  # strsplit() drops trailing empty fields, and "A..B1GQ.." is five of them:
  # split with a sentinel appended, then drop the sentinel.
  parts <- if (is.null(key) || identical(key, "all")) rep("", length(dims)) else {
    p <- strsplit(paste0(key, ".x"), ".", fixed = TRUE)[[1]]
    p[-length(p)]
  }
  if (length(parts) != length(dims)) {
    wdj_abort(c(
      "{.arg key} has {length(parts)} part{?s}; this dataflow has
       {length(dims)} dimension{?s}.",
      "i" = "In order: {.field {dims}}. Leave a part empty for all values."
    ), call = call)
  }
  pos <- match(prov$country_dim, dims)
  if (!is.null(countries) && !is.na(pos)) {
    if (nzchar(parts[pos])) {
      wdj_abort(c(
        "{.arg countries} and the {.field {prov$country_dim}} part of {.arg key}
         both name countries.",
        "i" = "Leave that part of {.arg key} empty and pass {.arg countries}."
      ), call = call)
    }
    parts[pos] <- paste(sdmx_country_codes(countries, prov$origin), collapse = "+")
  }
  list(key = paste(parts, collapse = "."), server_side = !is.na(pos))
}

# ISO codes in the provider's own spelling.
sdmx_country_codes <- function(iso3, origin) {
  if (identical(origin, "iso3c")) return(iso3)
  out <- suppressWarnings(countrycode::countrycode(iso3, "iso3c", origin,
                                                   warn = FALSE))
  out[!is.na(out)]
}

#' Read any SDMX statistics service
#'
#' One reader for the statistical agencies that publish through SDMX, the
#' standard for statistical data exchange: the OECD, the IMF, the ILO,
#' Eurostat, the European Central Bank, the BIS and UNICEF, or any other SDMX
#' REST service by URL. It asks for SDMX-CSV, which needs no client package,
#' and returns the result on the ISO spine. [fetch_oecd()] is this with
#' `provider = "oecd"`, and the `"imf"` and `"ilo"` sources of
#' [fetch_indicator()] go through it too.
#'
#' @param provider One of `"oecd"`, `"imf"`, `"ilo"`, `"eurostat"`, `"ecb"`,
#'   `"bis"` or `"unicef"`, or the base URL of an SDMX 2.1 REST service.
#' @param flow The dataflow, as SDMX writes one: `"AGENCY,ID,VERSION"`
#'   (`"OECD.SDD.NAD,DSD_NAAG@DF_NAAG_I,1.0"`), `"AGENCY,ID"` or `"ID"`. Name it
#'   to name the value column (default `value`).
#' @param key The SDMX key: one code (or several joined by `+`) per dimension,
#'   separated by dots, empty for all values -- `"A..B1GQ_R_GR.."`. `NULL`
#'   (default) asks for every series.
#' @param countries Optional `iso3c` vector. Where the provider publishes the
#'   dataflow's structure (the OECD, the IMF and the ILO), the codes go into
#'   the country position of `key`, so the filter is applied by the server;
#'   elsewhere they are applied after the download.
#' @param years Optional numeric year vector, sent as `startPeriod` and
#'   `endPeriod`.
#' @param ... Unused; named so a call written for another adapter says what
#'   it passed.
#'
#' @return A tibble of `iso3c`, `year` and the value column, with a
#'   [source_info()] record (the unit and its power of ten, from
#'   `UNIT_MEASURE` and `UNIT_MULT` where the provider sends them). The
#'   provider's aggregates (`"OECD"`, `"EA20"`) are not countries and are
#'   dropped.
#'
#' @section One row per country-year:
#' The package keys on country and year, so every other dimension has to be
#' pinned. When a dimension still varies -- several measures, both sexes, or
#' quarterly periods -- a country-year has several rows, and keeping the
#' first would be a silent choice; the reader aborts instead and names the
#' dimensions that vary, so the key can be narrowed. A failed request is a
#' warning and no rows, unless `options(countryatlas.strict = TRUE)`.
#'
#' @seealso [fetch_oecd()], [fetch_indicator()], [register_country_source()]
#' @export
#' @examples
#' \donttest{
#' # Real GDP growth for three countries, filtered by the OECD's server:
#' fetch_sdmx("oecd", c(gdp_growth = "OECD.SDD.NAD,DSD_NAAG@DF_NAAG_I,1.0"),
#'            key = "A..B1GQ_R_GR..", countries = c("FRA", "DEU", "JPN"),
#'            years = 2020:2023)
#' }
fetch_sdmx <- function(provider, flow, key = NULL, countries = NULL,
                       years = NULL, ...) {
  warn_adapter_dots(rlang::list2(...), "fetch_sdmx")
  check_string(provider, "provider")
  check_string(flow, "flow")
  if (!is.null(key)) check_string(key, "key")
  tab <- sdmx_providers()
  prov <- if (provider %in% tab$provider) {
    as.list(tab[tab$provider == provider, ])
  } else if (grepl("^https?://", provider)) {
    list(provider = provider, base = sub("/+$", "", provider),
         accept = "application/vnd.sdmx.data+csv;version=1.0.0",
         country_dim = NA_character_, origin = "iso3c", structure = NA_character_,
         retry_403 = FALSE)
  } else {
    wdj_abort(c(
      "Unknown SDMX provider {.val {provider}}.",
      "i" = "Use one of {.val {tab$provider}}, or the base URL of an SDMX 2.1
             REST service."
    ))
  }
  fl <- sdmx_flow(flow)
  if (!is.null(countries)) {
    countries <- unique(stats::na.omit(wdj_to_iso3c(countries, origin = "iso3c")))
  }
  if (!is.null(years)) years <- validate_years(years, lo = 1500L)
  out_name <- names(flow) %||% "value"
  empty <- tibble::tibble(iso3c = character(), year = integer(),
                          !!out_name := numeric())
  dims <- sdmx_dimensions(prov, fl)
  k <- sdmx_key(key, dims, prov, countries)
  url <- sprintf("%s/data/%s/%s", prov$base, fl$ref, k$key)
  q <- c(if (!is.null(years)) c(startPeriod = min(years), endPeriod = max(years)),
         if (identical(provider, "oecd")) c(format = "csvfilewithlabels"))
  if (length(q)) url <- paste0(url, "?", paste(names(q), q, sep = "=", collapse = "&"))
  res <- tryCatch(wdj_http_get(url, accept = if (identical(provider, "oecd")) NULL else prov$accept,
                               retry_403 = isTRUE(prov$retry_403)),
                  countryatlas_fetch_failed = function(e) e)
  if (inherits(res, "condition")) {
    # A 404 from an SDMX service is "no data for this query", not an outage.
    if (identical(res$status, 404L)) {
      wdj_warn(c(
        "{.val {provider}} has no data for {.val {fl$ref}} with key
         {.val {k$key}}.",
        "i" = "Check the dataflow and the key against the provider's data
               explorer."
      ), class = "countryatlas_no_data")
      return(empty)
    }
    return(fetch_failed(res, sprintf("%s from %s", fl$ref, provider), empty))
  }
  raw <- sdmx_read_csv(http_text(res))
  if (!nrow(raw)) {
    wdj_warn("{.val {provider}} returned no observations for {.val {fl$ref}}.",
             class = "countryatlas_no_data")
    return(empty)
  }
  cdim <- prov$country_dim
  if (is.na(cdim)) {
    cdim <- intersect(c("REF_AREA", "COUNTRY", "geo", "GEO"), names(raw))[1]
  }
  if (is.na(cdim) || !cdim %in% names(raw) || !"TIME_PERIOD" %in% names(raw) ||
      !"OBS_VALUE" %in% names(raw)) {
    wdj_abort(c(
      "The response is not the SDMX-CSV this reader understands.",
      "i" = "Columns were {.val {utils::head(names(raw), 12)}}."
    ), class = "countryatlas_bad_response")
  }
  sdmx_check_unique(raw, cdim, dims, provider)
  raw$year <- read_year(raw$TIME_PERIOD, sprintf("SDMX (%s)", provider))
  out <- adapter_reshape(raw, out_name, entity_col = cdim, year_col = "year",
                         value_col = "OBS_VALUE",
                         countries = if (!k$server_side) countries,
                         years = years, origin = prov$origin)
  set_source_info(out, sdmx_source_info(raw, out_name, provider, fl, k$key))
}

# SDMX-CSV, read as text so codes such as "001" or "NA" (Namibia) survive.
# csvfilewithlabels puts each code column's label in the column after it,
# headed by the dimension's name; those are kept under "<code>_label".
sdmx_read_csv <- function(txt) {
  raw <- utils::read.csv(text = txt, check.names = FALSE, colClasses = "character",
                         na.strings = "", encoding = "UTF-8")
  nm <- names(raw)
  is_code <- grepl("^[A-Za-z][A-Za-z0-9_@]*$", nm) & !grepl(" ", nm)
  lab <- which(!is_code & c(FALSE, is_code[-length(is_code)]))
  if (length(lab)) {
    names(raw)[lab] <- paste0(nm[lab - 1L], "_label")
    raw <- raw[, !duplicated(names(raw)), drop = FALSE]
  }
  tibble::as_tibble(raw)
}

# Every dimension but the country and the period has to be pinned, or a
# country-year has several rows.
sdmx_check_unique <- function(raw, cdim, dims, provider, call = rlang::caller_env()) {
  dim_cols <- if (!is.null(dims)) intersect(dims, names(raw)) else {
    setdiff(names(raw)[grepl("^[A-Z][A-Z0-9_]*$", names(raw))],
            c("DATAFLOW", "STRUCTURE", "STRUCTURE_ID", "ACTION", "OBS_VALUE",
              "OBS_STATUS", "OBS_FLAG", "CONF_STATUS", "UNIT_MULT", "DECIMALS",
              "UNIT_MEASURE", "UNIT", "SCALE", "TIME_FORMAT"))
  }
  dim_cols <- setdiff(dim_cols, c(cdim, "TIME_PERIOD"))
  varying <- dim_cols[vapply(dim_cols, function(d) {
    length(unique(raw[[d]])) > 1L
  }, logical(1))]
  periods <- unique(raw$TIME_PERIOD)
  sub_annual <- any(!grepl("^[0-9]{4}$", periods[!is.na(periods)]))
  if (length(varying) || sub_annual) {
    wdj_abort(c(
      "The response holds several series for one country-year.",
      "x" = if (length(varying)) "These dimensions vary: {.field {varying}}."
            else "The periods are not years ({.val {utils::head(periods, 2)}}).",
      "i" = "Pin {cli::qty(max(1, length(varying)))}{?it/them} in {.arg key}
             (one code per dimension, separated by dots), so each country-year
             has one value."
    ), class = "countryatlas_sdmx_not_unique", call = call)
  }
  invisible(TRUE)
}

sdmx_source_info <- function(raw, column, provider, fl, key) {
  first <- function(nm) {
    if (!nm %in% names(raw)) return(NA_character_)
    v <- unique(stats::na.omit(raw[[nm]]))
    if (length(v) == 1L) v else NA_character_
  }
  unit <- first("UNIT_MEASURE_label")
  if (is.na(unit)) unit <- first("UNIT_MEASURE")
  if (is.na(unit)) unit <- first("UNIT")
  mult <- suppressWarnings(as.integer(first("UNIT_MULT") %|% first("SCALE")))
  if (!is.na(unit) && !is.na(mult) && mult != 0L) {
    unit <- sprintf("%s, x10^%d", unit, mult)
  }
  updated <- first("UPDATE_DATE")
  if (!is.na(updated)) updated <- substr(updated, 1, 10)
  source_info_rows(
    column, source = provider, indicator = paste0(fl$ref, "/", key),
    label = first("STRUCTURE_NAME"), unit = unit, provider_updated = updated,
    fetched_at = format(Sys.Date()),
    licence = switch(provider, ilo = "CC BY 4.0", eurostat = "CC BY 4.0",
                     unicef = "CC BY 4.0", NA_character_),
    citation = sprintf("%s, dataflow %s.", source_display(provider), fl$ref))
}

# The first argument unless it is NA.
`%|%` <- function(a, b) if (length(a) && !is.na(a)) a else b
