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
    check_string(opt, "countryatlas.cache_dir", allow_empty = TRUE, call = NULL)
    return(opt)
  }
  if (nzchar(Sys.getenv("_R_CHECK_PACKAGE_NAME_"))) {
    return(file.path(tempdir(), "countryatlas-cache"))
  }
  tools::R_user_dir("countryatlas", "cache")
}

# A single, uncached World Bank fetch for one indicator: the current release,
# or an archived one when `vintage` is a release id. Returns a tidy tibble with
# columns iso2c, iso3c, country, year, <name>, carrying the release metadata
# (label, last update, vintage, fetch time) as attributes, which the cache
# stores with it -- so a cached answer still says when it was fetched.
# `.ns` exists to change the cache key: entries written by 3.0.0, which went
# through WDI::WDI(), are never read back as though they were this.
fetch_one_indicator <- function(code, name, start, end, language = "en",
                                vintage = NULL, .ns = "countryatlas-4") {
  raw <- wb_request(indicator = stats::setNames(code, name),
                    start = start, end = end, language = language,
                    vintage = vintage)
  meta <- attributes(raw)[c("wb_label", "wb_lastupdated", "wb_vintage")]
  raw <- tibble::as_tibble(raw)
  # memoise caches whatever the function returns -- and for the World Bank that
  # cache is on disk. A request that came back empty -- a failed download that
  # degraded to nothing, or a series with no observations -- would otherwise
  # be written to disk and read back by every later session instead of
  # retrying: the cache stayed poisoned until someone cleared it by hand. An
  # error is never memoised, so raise one; fetch_one_safe() turns it back into
  # "no data for this indicator".
  if (!nrow(raw)) {
    wdj_abort("The World Bank returned no rows for {.val {code}}.",
              class = "countryatlas_empty_fetch")
  }
  # The API returns iso2c + country + year + the named value column, and the
  # current release iso3c as well.
  if (!"iso3c" %in% names(raw)) {
    # countrycode() is handed raw$iso2c directly, so a response carrying
    # neither key raised its own "sourcevar must be a character or numeric
    # vector" -- which fetch_one_safe() then wrapped as "Could not fetch ...
    # from the World Bank API". That blames the network for a change in the
    # provider's response shape and attaches advice about an argument the
    # caller never passed. adapter_reshape() names this properly for the other
    # providers; so does this now.
    if (!"iso2c" %in% names(raw)) {
      wdj_abort(c(
        "The World Bank response for {.val {code}} carries no country key.",
        "x" = "Expected an {.field iso2c} or {.field iso3c} column; got
               {.val {names(raw)}}.",
        "i" = "That is a change in the provider's response shape, not a
               connectivity problem."
      ), class = "countryatlas_bad_response")
    }
    raw$iso3c <- suppressWarnings(
      countrycode::countrycode(raw$iso2c, "iso2c", "iso3c", warn = FALSE)
    )
  }
  attr(raw, "wb_label") <- meta$wb_label %||% NA_character_
  attr(raw, "wb_lastupdated") <- meta$wb_lastupdated %||% NA_character_
  attr(raw, "wb_vintage") <- meta$wb_vintage %||% wb_vintage_id(vintage) %||%
    NA_character_
  attr(raw, "wb_fetched_at") <- format(Sys.time(), "%Y-%m-%d")
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
wdj_disk_cache <- function(subdir = NULL, permanent = FALSE) {
  dir <- wdj_cache_dir()
  if (length(dir) && nzchar(dir) && !is.null(subdir)) dir <- file.path(dir, subdir)
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
  # cachem::cache_disk(), not memoise::cache_filesystem(): the latter has no
  # expiry and no size cap, so this directory grew without bound for the life
  # of the installation. CRAN's policy allows a package cache under
  # tools::R_user_dir() only "provided that by default sizes are kept as small
  # as possible and the contents are actively managed (including removing
  # outdated material)" -- nothing did either. cache_disk() prunes on write:
  # entries past max_age go, and past max_size the least-recently-used go.
  #
  # Ageing entries out is also correct on the merits. These are World Bank
  # observations, which get revised; a cached 2020 GDP figure fetched two years
  # ago is not the answer the API would give today.
  #
  # cachem is already an unconditional dependency of memoise, so this adds
  # nothing to install.
  # An archived World Bank release never changes, so its entries never go
  # stale; only the size cap applies to them.
  age <- if (isTRUE(permanent)) Inf else
    cache_limit_option("countryatlas.cache_max_age", 30L * 86400L)
  size <- cache_limit_option("countryatlas.cache_max_size", 50L * 1024L^2)
  cache <- tryCatch(
    cachem::cache_disk(dir, max_age = age, max_size = size, evict = "lru",
                       # See WDJ_CACHE_EXT: cachem expires, evicts and resets by
                       # extension, so the extension is what keeps it to our
                       # own files.
                       extension = WDJ_CACHE_EXT,
                       # A pruned entry must not be an error: it just means the
                       # next call re-fetches.
                       missing = cachem::key_missing()),
    error = function(e) NULL
  )
  if (is.null(cache)) return(NULL)
  prune_legacy_cache(dir)
  # 3.0.0 kept the World Bank's entries in the cache root itself. Nothing reads
  # them now -- the key namespace moved with the client -- so they are swept
  # like any other outdated entry, by the shape of their names.
  if (!is.null(subdir)) {
    root <- dirname(dir)
    prune_legacy_cache(root)
    old <- list.files(root, pattern = paste0("^[0-9a-f]{32,128}",
                                             gsub(".", "\\.", WDJ_CACHE_EXT,
                                                  fixed = TRUE), "$"),
                      full.names = TRUE)
    if (length(old)) unlink(old)
  }
  cache
}

# One of the two documented cache limits, validated where it is read, as
# countryatlas.cache_dir and countryatlas.workers already are. Unchecked, a
# bad value went straight to cachem::cache_disk(), whose error the tryCatch
# above turns into "no disk cache" -- so options(countryatlas.cache_max_age =
# "a") or NA switched persistent caching off and reported "Cannot write to the
# cache directory", blaming a directory that was fine. A negative age or size
# was accepted and meant every entry expired or was evicted on write. Inf is
# the natural "no limit" and is allowed.
cache_limit_option <- function(name, default) {
  v <- getOption(name, default)
  if (!is.numeric(v) || length(v) != 1L || is.na(v) || v < 0) {
    wdj_abort(c(
      "{.code options({name})} must be a single non-negative number.",
      "x" = if (is.function(v) || is.environment(v)) "Got {.cls {class(v)[1]}}."
            else "Got {.val {v}}.",
      "i" = "Use {.code Inf} for no limit, or {.code NULL} for the default."
    ), class = "countryatlas_bad_option", call = NULL)
  }
  v
}

# The extension of this package's cache entries. cachem ages out, evicts and
# resets every file in the directory that carries its extension, and the
# directory is the caller's to choose (options(countryatlas.cache_dir = )
# is documented for exactly that), so under the default ".rds" a cache
# pointed at a folder that also held the caller's own .rds files would delete
# those after 30 days, or sooner under the size cap. Nothing else writes this
# extension.
WDJ_CACHE_EXT <- ".countryatlas"

# The files this cache has written, and only those: entries are named by
# memoise's hash (32 hexadecimal digits) plus WDJ_CACHE_EXT, "<hash>.rds" from
# the 3.0.0 development builds that used cachem's default extension, and a
# bare "<hash>" from memoise::cache_filesystem() in 2.0.x; plus the write
# probe. Matching the *shape* of the name is the point: anything else in the
# directory may be the caller's.
wdj_cache_files <- function(dir, legacy_only = FALSE) {
  ext <- gsub(".", "\\.", WDJ_CACHE_EXT, fixed = TRUE)
  pattern <- if (legacy_only) {
    "^[0-9a-f]{32,128}(\\.rds)?$"
  } else {
    paste0("^([0-9a-f]{32,128}(\\.rds|", ext, ")?|\\.countryatlas-write-probe)$")
  }
  files <- list.files(dir, pattern = pattern, all.files = TRUE,
                      full.names = TRUE)
  files[!dir.exists(files)]
}

# Entries from earlier versions, which cachem (keyed on the extension above)
# does not recognise and so would never prune, the "outdated material" CRAN's
# cache policy is about. Swept once per cache construction; they are
# re-fetchable, so losing them costs a download.
#
# By the shape of the name, not "every file that is not ours": this used to
# delete every file in the directory without an .rds extension, which was
# harmless in the package's own R_user_dir() folder and destroyed the caller's
# files in any other: the first cached fetch after pointing
# countryatlas.cache_dir at a project folder deleted every non-.rds file in
# it.
prune_legacy_cache <- function(dir) {
  legacy <- wdj_cache_files(dir, legacy_only = TRUE)
  if (length(legacy)) unlink(legacy)
  invisible(length(legacy))
}

get_fetch_fun <- function(cache = TRUE, vintage = NULL) {
  if (!isTRUE(cache)) return(fetch_one_indicator)
  # Archived releases have a memo, and a directory, of their own: they never
  # change, so they are kept for good, while the current release ages out.
  archive <- !is.null(vintage)
  slot <- if (archive) "fetch_memo_archive" else "fetch_memo"
  # Rebuild when the cache location changes. The memoised fetcher used to be
  # built once and kept for the session, so setting
  # options(countryatlas.cache_dir = ) after the first cached call was silently
  # ignored -- writes kept going to the original directory until something
  # happened to reset this state (clear_wdi_cache() did, by accident). The help
  # page offers that option as the way to relocate the cache and says nothing
  # about having to set it first.
  dir <- wdj_cache_dir()
  if (!identical(.wdj_state$fetch_dir, dir)) {
    .wdj_state$fetch_memo <- NULL
    .wdj_state$fetch_memo_archive <- NULL
  }
  if (is.null(.wdj_state[[slot]])) {
    .wdj_state$fetch_dir <- dir
    cache_obj <- wdj_disk_cache(if (archive) "wdi-archive" else "wdi",
                                permanent = archive)
    if (is.null(cache_obj)) {
      wdj_inform(
        c("!" = "Cannot write to the cache directory {.path {wdj_cache_dir()}}.",
          "i" = "Caching for this session only. See {.fn clear_country_cache}."),
        # Per directory, not per session: the message names a specific path, and
        # the fetcher is now rebuilt whenever the path changes, so a second
        # unwritable location would otherwise go unreported.
        .frequency = "once",
        .frequency_id = paste0("countryatlas-cache-unwritable-", dir)
      )
    }
    # Remembered so fetch_wdi() can tell a fork-safe memo (on disk, shared by
    # every process) from one that only lives in this session's memory.
    if (!archive) .wdj_state$fetch_on_disk <- !is.null(cache_obj)
    .wdj_state[[slot]] <- if (is.null(cache_obj)) {
      memoise::memoise(fetch_one_indicator)
    } else {
      memoise::memoise(fetch_one_indicator, cache = cache_obj)
    }
  }
  .wdj_state[[slot]]
}

#' Clear the World Bank cache (deprecated)
#'
#' @description
#' `r lifecycle::badge("deprecated")`
#'
#' `clear_wdi_cache()` was generalised into [clear_country_cache()] in 3.0.0,
#' which clears any source's cache; `clear_wdi_cache(disk)` is
#' `clear_country_cache("wdi", disk)`. It now says so, and goes in 5.0.0.
#'
#' @param disk Whether to also delete the persistent on-disk cache.
#' @return Invisibly `TRUE`.
#' @keywords internal
#' @export
#' @examples
#' clear_country_cache("wdi")   # instead of clear_wdi_cache()
clear_wdi_cache <- function(disk = FALSE) {
  lifecycle::deprecate_warn("4.0.0", "clear_wdi_cache()",
                            "clear_country_cache()",
                            details = "Write `clear_country_cache(\"wdi\")`.")
  wdi_cache_clear(disk)
}

# Forget the World Bank fetches: the in-session memos for the current and the
# archived releases, and with `disk = TRUE` their files.
wdi_cache_clear <- function(disk = FALSE) {
  check_bool(disk, "disk")
  memo <- .wdj_state$fetch_memo
  # forget() only when the memo lives in memory. On a filesystem-backed memo it
  # is not an in-memory operation at all: memoise's cache_filesystem()$reset()
  # is file.remove(list.files(dir, full.names = TRUE)), so this call -- which
  # the examples label "forget the in-session memo" -- deleted the persistent
  # cache, and every unrelated file that happened to share the directory with
  # it. Dropping the reference below is what "in-session" means here: the next
  # call rebuilds the memo and reads the existing disk entries straight back.
  if (!is.null(memo) && memoise::is.memoised(memo) &&
      !isTRUE(.wdj_state$fetch_on_disk)) {
    memoise::forget(memo)
  }
  .wdj_state$fetch_memo <- NULL
  .wdj_state$fetch_memo_archive <- NULL
  if (isTRUE(disk)) {
    for (sub in c("wdi", "wdi-archive")) clear_cache_dir(sub)
  }
  invisible(TRUE)
}

# Delete one source's cache files -- this cache's own, by the shape of their
# names -- then its directory and the cache root if that leaves them empty.
# This was unlink(dir, recursive = TRUE): with countryatlas.cache_dir set to a
# folder the caller also used, "delete the persistent cache" deleted the
# folder, every file in it and every subdirectory below it.
clear_cache_dir <- function(subdir = NULL) {
  root <- wdj_cache_dir()
  if (!length(root) || !nzchar(root)) return(invisible(FALSE))
  empty <- function(d) !length(list.files(d, all.files = TRUE, no.. = TRUE))
  dirs <- if (is.null(subdir)) root else file.path(root, subdir)
  # The 3.0.0 layout kept the World Bank entries in the root itself; they are
  # this cache's files too, and are cleared with the World Bank's.
  if (identical(subdir, "wdi")) dirs <- c(dirs, root)
  for (dir in dirs) {
    if (dir.exists(dir)) {
      unlink(wdj_cache_files(dir))
      if (!identical(dir, root) && empty(dir)) unlink(dir, recursive = TRUE)
    }
  }
  if (dir.exists(root) && empty(root)) unlink(root, recursive = TRUE)
  invisible(TRUE)
}

# Fetch (possibly many) indicators and merge into one tidy panel keyed on
# iso3c + year. Indicators are fetched in parallel when there is more than one.
fetch_wdi <- function(indicator, start, end, cache = TRUE,
                      language = "en", parallel = TRUE, vintage = NULL) {
  indicator <- normalize_indicator(indicator)
  if (is.null(indicator)) {
    return(tibble::tibble(iso3c = character(), iso2c = character(),
                          country = character(), year = integer()))
  }
  vintage <- wb_vintage_id(vintage)
  fetch_fun <- get_fetch_fun(cache, vintage)
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
                                   start, end, language, vintage),
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
  # What each column is, from where, in which release, fetched when: the
  # record source_info() reads and the maps cite.
  info <- dplyr::bind_rows(lapply(seq_along(parts), function(i) {
    if (is.null(parts[[i]])) return(NULL)
    wb_source_info(names_[i], codes[i], parts[[i]])
  }))
  for (a in c("wb_label", "wb_lastupdated", "wb_vintage", "wb_fetched_at")) {
    attr(out, a) <- NULL
  }
  set_source_info(out, info)
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
fetch_one_captured <- function(fetch_fun, code, name, start, end, language,
                               vintage = NULL) {
  conds <- list()
  value <- withCallingHandlers(
    fetch_one_safe(fetch_fun, code, name, start, end, language, vintage),
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
fetch_one_safe <- function(fetch_fun, code, name, start, end, language,
                           vintage = NULL) {
  tryCatch(
    # The vintage is passed only when there is one, so a fetcher written
    # before releases could be pinned -- a test stub, say -- still fits.
    if (is.null(vintage)) fetch_fun(code, name, start, end, language) else
      fetch_fun(code, name, start, end, language, vintage),
    error = function(e) {
      msg <- conditionMessage(e)
      # A pipeline that must not go on with data missing asked for errors.
      if (inherits(e, "countryatlas_fetch_failed") && fetch_strict()) {
        rlang::cnd_signal(e)
      }
      if (inherits(e, "countryatlas_vintage_missing")) {
        near <- wb_nearest_vintages(vintage, code, start)
        wdj_warn(c(
          "{msg}",
          "i" = if (length(near)) "The nearest releases that hold it are
                 {.val {wb_vintage_label(near)}}." else "{.fn wdi_vintages}
                 lists the releases."
        ), class = "countryatlas_vintage_missing")
      } else if (inherits(e, "countryatlas_empty_fetch")) {
        wdj_warn(c(
          "No data returned for indicator {.val {code}}.",
          "i" = "Either the indicator has no observations for the years asked
                 for, or the download failed. Nothing was cached, so the next
                 call will try again."
        ), class = "countryatlas_no_data")
      } else if (inherits(e, "countryatlas_bad_response")) {
        # Pass the diagnosis through rather than re-labelling it as a failed
        # download: the response arrived, it just did not look like WDI's.
        wdj_warn(c("{msg}",
                   "i" = "Indicator {.val {code}} is skipped."),
                 class = "countryatlas_bad_response")
      } else if (looks_like_cache_read_error(msg) && !is.null(wdj_disk_cache())) {
        # A fallback now rather than the main corrupt-entry path: cachem's
        # cache_disk() treats an unreadable entry as a miss and re-fetches, so
        # a truncated .rds no longer reaches here at all. What can still reach
        # here is a read error cachem does not absorb -- a directory whose
        # permissions change mid-session, a filesystem going read-only -- and
        # blaming the World Bank for those would send the caller off to debug a
        # connection that is fine.
        wdj_warn(c(
          "Could not read indicator {.val {code}} from the on-disk cache.",
          "x" = "{msg}",
          "i" = "The cache entry could not be read. Clearing it is the
                 quickest fix: {.code clear_wdi_cache(disk = TRUE)}."
        ))
      } else {
        wdj_warn(c(
          "Could not fetch indicator {.val {code}} from the World Bank API.",
          "x" = "{msg}"
        ), class = if (inherits(e, "countryatlas_fetch_failed"))
          "countryatlas_fetch_failed")
      }
      NULL
    }
  )
}
