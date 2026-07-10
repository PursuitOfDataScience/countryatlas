# Performance & caching ---------------------------------------------------------

# The persistent on-disk cache directory for WDI fetches.
wdj_cache_dir <- function() {
  getOption("countryatlas.cache_dir",
            tools::R_user_dir("countryatlas", "cache"))
}

# A single, uncached WDI fetch for one indicator. Returns a tidy tibble with
# columns iso2c, iso3c, country, year, <name>.
fetch_one_indicator <- function(code, name, start, end, language = "en") {
  raw <- WDI::WDI(indicator = stats::setNames(code, name),
                  start = start, end = end,
                  extra = FALSE, language = language)
  raw <- tibble::as_tibble(raw)
  # WDI returns iso2c + country + year + the named value column.
  if (!"iso3c" %in% names(raw)) {
    raw$iso3c <- suppressWarnings(
      countrycode::countrycode(raw$iso2c, "iso2c", "iso3c", warn = FALSE)
    )
  }
  raw
}

# memoise the per-indicator fetch (in-session, plus optional on-disk cache).
# State lives in a mutable environment because package namespace bindings are
# locked once the package is installed/loaded.
.wdj_state <- new.env(parent = emptyenv())

get_fetch_fun <- function(cache = TRUE) {
  if (!isTRUE(cache)) return(fetch_one_indicator)
  if (is.null(.wdj_state$fetch_memo)) {
    cache_obj <- tryCatch(
      memoise::cache_filesystem(wdj_cache_dir()),
      error = function(e) NULL
    )
    .wdj_state$fetch_memo <- if (is.null(cache_obj)) {
      memoise::memoise(fetch_one_indicator)
    } else {
      memoise::memoise(fetch_one_indicator, cache = cache_obj)
    }
  }
  .wdj_state$fetch_memo
}

#' Clear the on-disk / in-memory WDI cache
#'
#' Forget memoised World Bank fetches, both in-session and (optionally) on disk.
#'
#' @param disk Whether to also delete the persistent on-disk cache.
#' @return Invisibly `TRUE`.
#' @export
#' @examples
#' \dontrun{
#' clear_wdi_cache()
#' }
clear_wdi_cache <- function(disk = FALSE) {
  memo <- .wdj_state$fetch_memo
  if (!is.null(memo) && memoise::is.memoised(memo)) {
    memoise::forget(memo)
  }
  .wdj_state$fetch_memo <- NULL
  if (isTRUE(disk)) {
    dir <- wdj_cache_dir()
    if (dir.exists(dir)) unlink(dir, recursive = TRUE)
  }
  invisible(TRUE)
}

# Fetch (possibly many) indicators and merge into one tidy panel keyed on
# iso3c + year. Indicators are fetched in parallel when there is more than one.
fetch_wdi <- function(indicator, start, end, cache = TRUE,
                      language = "en", parallel = TRUE) {
  indicator <- normalize_indicator(indicator)
  if (is.null(indicator)) {
    return(tibble::tibble(iso3c = character(), iso2c = character(),
                          country = character(), year = integer()))
  }
  fetch_fun <- get_fetch_fun(cache)
  codes <- unname(indicator)
  names_ <- names(indicator)

  parts <- wdj_lapply(
    seq_along(indicator),
    function(i) fetch_one_safe(fetch_fun, codes[i], names_[i], start, end, language),
    parallel = parallel
  )

  # Reduce-merge on the shared keys.
  base_keys <- c("iso2c", "iso3c", "country", "year")
  out <- NULL
  for (p in parts) {
    if (is.null(p)) next
    if (is.null(out)) {
      out <- p
    } else {
      val_cols <- setdiff(names(p), base_keys)
      # Two iso2c codes can map to one iso3c, so a key can repeat; the duplicate
      # rows are collapsed downstream (country_data distinct()s on iso3c/year).
      # Declare the relationship so dplyr doesn't warn about it.
      p_keep <- p[, c("iso3c", "year", val_cols, intersect(c("iso2c","country"), names(p))), drop = FALSE]
      out <- dplyr::full_join(out, p_keep, by = c("iso3c", "year"), suffix = c("", ".new"), relationship = "many-to-many")
      if ("iso2c.new" %in% names(out)) { out$iso2c <- dplyr::coalesce(out$iso2c, out$iso2c.new); out[["iso2c.new"]] <- NULL }
      if ("country.new" %in% names(out)) { out$country <- dplyr::coalesce(out$country, out$country.new); out[["country.new"]] <- NULL }
    }
  }
  if (is.null(out)) {
    return(tibble::tibble(iso3c = character(), iso2c = character(),
                          country = character(), year = integer()))
  }
  out
}

# Wrap a fetch so a single indicator failure degrades gracefully.
fetch_one_safe <- function(fetch_fun, code, name, start, end, language) {
  tryCatch(
    fetch_fun(code, name, start, end, language),
    error = function(e) {
      wdj_warn(c(
        "Could not fetch indicator {.val {code}} from the World Bank API.",
        "x" = conditionMessage(e)
      ))
      NULL
    }
  )
}
