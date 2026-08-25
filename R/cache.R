# Performance & caching ---------------------------------------------------------

# The persistent on-disk cache directory for WDI fetches.
#
# tools::R_user_dir() is the location CRAN sanctions for a package cache, and
# it is what real use gets. `R CMD check` is the exception: it runs the
# \donttest{} examples, which fetch, so an unguarded default would leave World
# Bank responses in the *checking* account's persistent cache -- a check should
# not touch the user's file space at all. Under check the cache therefore lives
# in the session temp directory, which R removes on exit.
# Set options(countryatlas.cache_dir=) to override either way.
wdj_cache_dir <- function() {
  opt <- getOption("countryatlas.cache_dir", NULL)
  if (!is.null(opt)) {
    # A documented option, so a stray value is reachable, and it used to reach
    # dir.exists()/dir.create(): NA, a number and TRUE all gave "invalid
    # filename argument", character(0) gave "argument is of length zero", and a
    # two-element vector gave "the condition has length > 1" -- none of them
    # naming the option. An empty string is still accepted and falls back to
    # session-only caching, as before.
    check_string(opt, "countryatlas.cache_dir", allow_empty = TRUE)
    return(opt)
  }
  if (nzchar(Sys.getenv("_R_CHECK_PACKAGE_NAME_"))) {
    return(file.path(tempdir(), "countryatlas-cache"))
  }
  tools::R_user_dir("countryatlas", "cache")
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

# memoise::cache_filesystem() does not check the directory it is given: it
# constructs happily and then fails at *write* time, deep inside the fetch. With
# an unwritable cache location that surfaced as "Could not fetch indicator ...
# from the World Bank API" and a table of NAs, blaming the API for a local
# permission problem. Establish that the directory is usable up front instead,
# and fall back to the in-session cache when it is not.
wdj_disk_cache <- function() {
  dir <- wdj_cache_dir()
  # An empty path means "no disk cache". Handle it before touching the
  # filesystem: dir.create("") warns and returns FALSE on R 4.4 but *errors*
  # with "zero-length 'path' argument" on R 4.6, so the graceful fallback was
  # version-dependent.
  if (!length(dir) || !nzchar(dir)) return(NULL)
  if (!dir.exists(dir)) {
    created <- tryCatch(
      suppressWarnings(dir.create(dir, recursive = TRUE, showWarnings = FALSE)),
      error = function(e) FALSE
    )
    if (!isTRUE(created) && !dir.exists(dir)) return(NULL)
  }
  probe <- file.path(dir, ".countryatlas-write-probe")
  ok <- isTRUE(tryCatch({
    suppressWarnings(writeLines(character(), probe))
    file.exists(probe)
  }, error = function(e) FALSE, warning = function(w) FALSE))
  if (file.exists(probe)) unlink(probe)
  if (!ok) return(NULL)
  tryCatch(memoise::cache_filesystem(dir), error = function(e) NULL)
}

get_fetch_fun <- function(cache = TRUE) {
  if (!isTRUE(cache)) return(fetch_one_indicator)
  # Rebuild when the cache location changes. The memoised fetcher used to be
  # built once and kept for the session, so setting
  # options(countryatlas.cache_dir = ) after the first cached call was silently
  # ignored -- writes kept going to the original directory until something
  # happened to reset this state (clear_wdi_cache() did, by accident). The help
  # page offers that option as the way to relocate the cache and says nothing
  # about having to set it first.
  dir <- wdj_cache_dir()
  if (!identical(.wdj_state$fetch_dir, dir)) .wdj_state$fetch_memo <- NULL
  if (is.null(.wdj_state$fetch_memo)) {
    .wdj_state$fetch_dir <- dir
    cache_obj <- wdj_disk_cache()
    if (is.null(cache_obj)) {
      wdj_inform(
        c("!" = "Cannot write to the cache directory {.path {wdj_cache_dir()}}.",
          "i" = "Caching for this session only. See {.fn clear_wdi_cache}."),
        # Per directory, not per session: the message names a specific path, and
        # the fetcher is now rebuilt whenever the path changes, so a second
        # unwritable location would otherwise go unreported.
        .frequency = "once",
        .frequency_id = paste0("countryatlas-cache-unwritable-", dir)
      )
    }
    # Remembered so fetch_wdi() can tell a fork-safe memo (on disk, shared by
    # every process) from one that only lives in this session's memory.
    .wdj_state$fetch_on_disk <- !is.null(cache_obj)
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
#' @section Where the cache lives:
#' The persistent cache goes in the standard per-user cache location,
#' `tools::R_user_dir("countryatlas", "cache")`. Point it elsewhere with
#' `options(countryatlas.cache_dir = )`, or skip the disk entirely by passing
#' `cache = FALSE` to [world_data()] / [country_data()]. The directory itself is
#' created the first time a cached fetch is attempted, whether or not the World
#' Bank answers; only a successful fetch leaves a response in it, and reading the
#' bundled [world_snapshot] never goes near it. Under `R CMD check` the whole
#' cache moves to the session temp directory, so a check never writes to the
#' user's file space.
#'
#' @param disk Whether to also delete the persistent on-disk cache.
#' @return Invisibly `TRUE`.
#' @export
#' @examples
#' clear_wdi_cache()              # forget the in-session memo
#' \dontrun{
#' clear_wdi_cache(disk = TRUE)   # also delete the persistent cache
#' }
clear_wdi_cache <- function(disk = FALSE) {
  check_bool(disk, "disk")
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

  # A memory-only memo cannot survive a fork: mclapply() populates it inside the
  # child, which then exits, so nothing is remembered and every call re-fetches
  # every indicator. That combination is reachable whenever the disk cache is
  # unavailable -- an unwritable cache directory, or cache_dir set to "" -- and
  # there the repeated network round-trips cost far more than the one-shot
  # parallel speedup. Fetch serially so the in-session memo actually warms.
  # With cache = FALSE nothing is memoised at all, so forking stays a pure win.
  if (isTRUE(cache) && !isTRUE(.wdj_state$fetch_on_disk)) parallel <- FALSE

  captured <- wdj_lapply(
    seq_along(indicator),
    function(i) fetch_one_captured(fetch_fun, codes[i], names_[i],
                                   start, end, language),
    parallel = parallel
  )
  replay_conditions(captured)
  parts <- lapply(captured, function(x) x$value)

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
      out <- dplyr::full_join(out, p_keep, by = c("iso3c", "year"), suffix = c("", ".new"),
                              relationship = "many-to-many", na_matches = "never")
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

# Does this error come from reading the cache rather than from the network?
# An interrupted write leaves a truncated or empty .rds behind, and memoise
# surfaces readRDS()'s own words -- "unknown input format", "error reading from
# connection" -- from inside the fetch. Blaming the API for that sends the caller
# off to debug their connection, the same misattribution wdj_disk_cache() already
# fixes for an *unwritable* directory; this is the read-side twin.
looks_like_cache_read_error <- function(msg) {
  grepl("unknown input format|error reading from connection|invalid connection|cannot read|truncat",
        msg, ignore.case = TRUE)
}

# Run one fetch, keeping any warning or message it raises instead of letting it
# escape here. parallel::mclapply() returns only a worker's *value*: conditions
# signalled inside a forked child are discarded when that child exits. Every
# per-indicator diagnostic below -- a failed fetch, a corrupt cache entry -- was
# therefore lost in exactly the case that matters, because having more than one
# indicator is what makes fetch_wdi() fork in the first place. A single bad
# indicator dropped its column from the result and said nothing at all. The
# serial path captures too, so both report identically.
fetch_one_captured <- function(fetch_fun, code, name, start, end, language) {
  conds <- list()
  value <- withCallingHandlers(
    fetch_one_safe(fetch_fun, code, name, start, end, language),
    warning = function(w) {
      conds[[length(conds) + 1L]] <<- w
      invokeRestart("muffleWarning")
    },
    message = function(m) {
      conds[[length(conds) + 1L]] <<- m
      invokeRestart("muffleMessage")
    }
  )
  list(value = value, conditions = conds)
}

# Re-signal captured conditions in this process. Duplicates are collapsed: the
# messages name the indicator *code*, so two entries sharing a code (a caller
# may name the same series twice) would otherwise report one problem twice.
replay_conditions <- function(captured) {
  seen <- character()
  for (part in captured) {
    for (cond in part$conditions) {
      key <- paste(class(cond)[[1]], conditionMessage(cond))
      if (key %in% seen) next
      seen <- c(seen, key)
      if (inherits(cond, "warning")) warning(cond) else message(cond)
    }
  }
  invisible(NULL)
}

# Wrap a fetch so a single indicator failure degrades gracefully.
fetch_one_safe <- function(fetch_fun, code, name, start, end, language) {
  tryCatch(
    fetch_fun(code, name, start, end, language),
    error = function(e) {
      msg <- conditionMessage(e)
      if (looks_like_cache_read_error(msg) && !is.null(wdj_disk_cache())) {
        wdj_warn(c(
          "Could not read indicator {.val {code}} from the on-disk cache.",
          "x" = msg,
          "i" = "A cache entry looks corrupt, which an interrupted write can
                 leave behind. It will keep failing until you clear it:
                 {.code clear_wdi_cache(disk = TRUE)}."
        ))
      } else {
        wdj_warn(c(
          "Could not fetch indicator {.val {code}} from the World Bank API.",
          "x" = msg
        ))
      }
      NULL
    }
  )
}
