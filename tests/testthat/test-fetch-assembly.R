# The World Bank fetch and assembly path. It needs the network, so it had no
# coverage at all -- yet it holds the least obvious logic in the package: the
# multi-indicator reduce-merge, the `latest` collapse, and the duplicate-key
# case where two iso2c codes map to one iso3c.
#
# Two things matter for mocking it:
#   * mock WDI::WDI, not fetch_one_indicator() -- the latter is what derives
#     iso3c from iso2c, so replacing it would skip the code under test;
#   * pass cache = FALSE, or the on-disk memoise cache serves a previous real
#     fetch and the mock is never consulted.

wdi_calls <- NULL

fake_wdi <- function(indicator, start, end, extra = FALSE, language = "en", ...) {
  wdi_calls[[length(wdi_calls) + 1L]] <<- c(name = names(indicator)[1],
                                            start = start, end = end)
  nm <- names(indicator)[1]
  yrs <- start:end
  d <- expand.grid(iso2c = c("US", "CN", "FR"), year = yrs,
                   stringsAsFactors = FALSE)
  d$country <- c(US = "United States", CN = "China", FR = "France")[d$iso2c]
  d[[nm]] <- c(US = 100, CN = 50, FR = 70)[d$iso2c] * (d$year - min(yrs) + 1)
  # Latest year missing for China, to exercise the "most recent non-NA" rule.
  d[[nm]][d$iso2c == "CN" & d$year == max(yrs)] <- NA
  d
}

test_that("fetch_wdi derives iso3c and merges several indicators", {
  wdi_calls <<- NULL
  testthat::local_mocked_bindings(WDI = fake_wdi, .package = "WDI")
  one <- countryatlas:::fetch_wdi(c(gdp = "A"), start = 2018, end = 2020,
                                  cache = FALSE)
  expect_true(all(c("iso3c", "gdp") %in% names(one)))
  expect_false(anyNA(one$iso3c))          # derived from iso2c
  expect_equal(nrow(one), 9L)

  multi <- countryatlas:::fetch_wdi(c(gdp = "A", pop = "B", co2 = "C"),
                                    start = 2018, end = 2020, cache = FALSE,
                                    parallel = FALSE)
  expect_true(all(c("gdp", "pop", "co2") %in% names(multi)))
  expect_equal(nrow(multi), 9L)           # still one row per country-year
  # The reduce-merge coalesces the shared keys rather than suffixing them.
  expect_false(any(grepl("\\.new$", names(multi))))
  expect_equal(sum(names(multi) == "iso2c"), 1L)
  expect_equal(sum(names(multi) == "country"), 1L)
  # Values line up across indicators for the same country-year.
  row <- multi[multi$iso3c == "USA" & multi$year == 2019, ]
  expect_equal(nrow(row), 1L)
  expect_equal(c(row$gdp, row$pop, row$co2), c(200, 200, 200))
})

test_that("one failing indicator does not take the others down", {
  testthat::local_mocked_bindings(
    WDI = function(indicator, ...) {
      if (names(indicator)[1] == "pop") stop("boom") else fake_wdi(indicator, ...)
    },
    .package = "WDI"
  )
  out <- suppressWarnings(
    countryatlas:::fetch_wdi(c(gdp = "A", pop = "B", co2 = "C"),
                             start = 2018, end = 2020, cache = FALSE,
                             parallel = FALSE)
  )
  expect_true(all(c("gdp", "co2") %in% names(out)))
  expect_false("pop" %in% names(out))
  expect_warning(
    countryatlas:::fetch_wdi(c(pop = "B"), start = 2018, end = 2020,
                             cache = FALSE, parallel = FALSE),
    class = "countryatlas_warning"
  )
})

test_that("country_data(latest = TRUE) takes the most recent non-NA value", {
  wdi_calls <<- NULL
  testthat::local_mocked_bindings(WDI = fake_wdi, .package = "WDI")
  lat <- country_data(2020, c(gdp = "A"), latest = TRUE, cache = FALSE)
  # Documented as "the most recent non-NA value", so the window opens at 1960
  # rather than at the requested year.
  expect_equal(unname(wdi_calls[[1]][["start"]]), "1960")
  expect_equal(unname(wdi_calls[[1]][["end"]]), "2020")
  expect_equal(nrow(lat), 3L)
  expect_equal(anyDuplicated(lat$iso3c), 0L)
  expect_false("year" %in% names(lat))    # collapsed, so not a panel
  expect_equal(lat$gdp[lat$iso3c == "USA"], 100 * 61)   # its latest year
  # China's latest year is NA, so it falls back to the year before.
  expect_equal(lat$gdp[lat$iso3c == "CHN"], 50 * 60)
  expect_true(all(c("continent", "region", "income") %in% names(lat)))
})

test_that("country_data returns a keyed panel for a year range", {
  wdi_calls <<- NULL
  testthat::local_mocked_bindings(WDI = fake_wdi, .package = "WDI")
  pan <- country_data(2018:2020, c(gdp = "A"), cache = FALSE)
  expect_equal(nrow(pan), 9L)
  expect_equal(anyDuplicated(pan[, c("iso3c", "year")]), 0L)
  expect_equal(names(pan)[1:4], c("iso3c", "iso2c", "country", "year"))
  expect_equal(unname(wdi_calls[[1]][["start"]]), "2018")
})

test_that("two iso2c codes mapping to one iso3c collapse to a single row", {
  # France has both FR and the retired FX; the merge declares a many-to-many
  # relationship and country_data() is what de-duplicates.
  testthat::local_mocked_bindings(
    WDI = function(indicator, ...) {
      nm <- names(indicator)[1]
      d <- data.frame(iso2c = c("FR", "FX"),
                      country = c("France", "France (metropolitan)"),
                      year = c(2020L, 2020L))
      d[[nm]] <- c(1, 2)
      d
    },
    .package = "WDI"
  )
  out <- country_data(2020, c(v = "X"), cache = FALSE)
  expect_lte(sum(out$iso3c == "FRA", na.rm = TRUE), 1L)
})

test_that("cache = TRUE short-circuits a repeated fetch", {
  wdi_calls <<- NULL
  testthat::local_mocked_bindings(WDI = fake_wdi, .package = "WDI")
  old <- options(countryatlas.cache_dir = file.path(tempdir(), "ca-cache-test"))
  on.exit({ clear_wdi_cache(disk = TRUE); options(old) }, add = TRUE)
  clear_wdi_cache()
  a <- country_data(2019:2020, c(g = "X"), cache = TRUE)
  n_after_first <- length(wdi_calls)
  b <- country_data(2019:2020, c(g = "X"), cache = TRUE)
  expect_equal(length(wdi_calls), n_after_first)   # served from the cache
  expect_identical(a, b)
})

test_that("country_data with no indicator returns the full country spine", {
  sp <- country_data(2020, indicator = NULL)
  expect_gt(nrow(sp), 200L)
  expect_true(all(c("iso3c", "iso2c", "country") %in% names(sp)))
  expect_false("year" %in% names(sp))
  panel <- country_data(2019:2020, indicator = NULL, panel = TRUE)
  expect_equal(nrow(panel), 2L * nrow(sp))
})

# CRAN runs \donttest{} examples with --run-donttest, and policy is explicit
# that an example must not fail because an internet resource is unavailable.
# ?world_data and ?country_data have \donttest{} examples that do call the World
# Bank, so their offline behaviour is load-bearing: a failed fetch must warn and
# return a frame, not error. wdi_search() is the one that cannot do that, which
# is why its example is \dontrun{} rather than \donttest{}.

test_that("the fetching examples degrade instead of failing offline", {
  boom <- function(...) stop("Could not resolve host: api.worldbank.org")
  local_mocked_bindings(WDI = boom, .package = "WDI")

  expect_warning(wd <- world_data(2020, geometry = "none", cache = FALSE),
                 "Could not fetch")
  expect_s3_class(wd, "data.frame")
  expect_gt(nrow(wd), 0L)              # country metadata still comes back
  expect_true("iso3c" %in% names(wd))

  expect_warning(cd <- country_data(2020, c(co2 = "EN.GHG.CO2.MT.CE.AR5"),
                                    cache = FALSE),
                 "Could not fetch")
  expect_gt(nrow(cd), 0L)
  expect_true("iso3c" %in% names(cd))
})

test_that("wdi_search needs no connection", {
  # WDI::WDIsearch() reads the indicator list bundled with WDI rather than
  # calling the API, so this works offline -- confirmed by running it behind a
  # blackhole proxy, under which world_data() degrades but this does not. No
  # mock here on purpose: mocking WDIsearch() to throw would only prove that we
  # propagate an error, not whether one actually occurs.
  skip_if_not_installed("WDI")
  res <- wdi_search("renewable energy")
  expect_s3_class(res, "data.frame")
  expect_gt(nrow(res), 0L)
  expect_true(all(c("indicator", "name") %in% names(res)))
  # The vignette makes this claim in an unguarded chunk, so it has to hold.
  expect_gt(nrow(wdi_search("CO2 emissions")), 0L)
})

# memoise::cache_filesystem() does not validate the directory it is handed: it
# constructs fine and fails at *write* time, deep inside the fetch. With an
# unusable cache location country_data(cache = TRUE) therefore reported
# "Could not fetch indicator ... from the World Bank API" and returned a table
# of NAs -- blaming the API for a local permission problem. The existing
# tryCatch() around cache_filesystem() never fired, because constructing it
# never errored.

test_that("an unusable cache directory is detected up front", {
  # A path that is a regular file can never become a directory, on any OS --
  # unlike chmod, which does not restrict on Windows.
  f <- tempfile("countryatlas-not-a-dir")
  writeLines("x", f)
  on.exit(unlink(f), add = TRUE)
  old <- options(countryatlas.cache_dir = f)
  on.exit(options(old), add = TRUE)
  expect_null(countryatlas:::wdj_disk_cache())

  # A usable directory is created on demand, and the write probe is cleaned up.
  d <- file.path(tempdir(), "countryatlas-cache-probe-test")
  unlink(d, recursive = TRUE)
  options(countryatlas.cache_dir = d)
  expect_false(is.null(countryatlas:::wdj_disk_cache()))
  expect_true(dir.exists(d))
  expect_false(file.exists(file.path(d, ".countryatlas-write-probe")))
  unlink(d, recursive = TRUE)
})

test_that("a directory that exists but is not writable is also detected", {
  # The file-as-directory case above never reaches the write probe: dir.create()
  # fails first. This is the case the probe exists for -- a read-only HOME, the
  # scenario that produced the bug -- so it needs its own test.
  skip_on_os("windows")                       # chmod does not restrict there
  skip_if(unname(Sys.info()["effective_user"]) == "root",
          "root can write to a mode-500 directory")
  d <- file.path(tempdir(), "countryatlas-unwritable-cache")
  unlink(d, recursive = TRUE)
  dir.create(d, recursive = TRUE)
  Sys.chmod(d, "500")
  on.exit({ Sys.chmod(d, "700"); unlink(d, recursive = TRUE) }, add = TRUE)
  skip_if(file.access(d, 2) == 0, "filesystem ignores the mode change")

  old <- options(countryatlas.cache_dir = d)
  on.exit(options(old), add = TRUE)
  expect_true(dir.exists(d))                  # it exists...
  expect_null(countryatlas:::wdj_disk_cache()) # ...but is still rejected
})

test_that("an unusable cache does not turn a good fetch into NAs", {
  st <- countryatlas:::.wdj_state
  old_memo <- st$fetch_memo
  f <- tempfile("countryatlas-not-a-dir")
  writeLines("x", f)
  old <- options(countryatlas.cache_dir = f)
  on.exit({ st$fetch_memo <- old_memo; options(old); unlink(f) }, add = TRUE)

  local_mocked_bindings(
    WDI = function(indicator, ...) {
      data.frame(iso2c = c("US", "FR"), country = c("United States", "France"),
                 year = 2020L, pop = c(331e6, 67e6))
    },
    .package = "WDI")

  st$fetch_memo <- NULL
  out <- suppressMessages(country_data(2020, c(pop = "SP.POP.TOTL"),
                                       cache = TRUE))
  # The values must survive: before the fix `pop` was entirely NA.
  expect_true("pop" %in% names(out))
  expect_gt(sum(!is.na(out$pop)), 0L)
  expect_true(all(c("USA", "FRA") %in% out$iso3c[!is.na(out$pop)]))
})

# options(countryatlas.cache_dir) is documented in ?clear_wdi_cache, so a stray
# value is reachable -- and it used to reach dir.exists()/dir.create(): NA, a
# number and TRUE all gave "invalid filename argument", character(0) gave
# "argument is of length zero", and a two-element vector gave "the condition has
# length > 1". None named the option.

test_that("a bad cache_dir option names the option", {
  for (v in list(NA, NA_character_, character(0), 42, TRUE,
                 c("/tmp/a", "/tmp/b"))) {
    old <- options(countryatlas.cache_dir = v)
    expect_error(countryatlas:::wdj_cache_dir(), "countryatlas.cache_dir")
    expect_error(countryatlas:::wdj_cache_dir(), class = "countryatlas_error")
    # And the disk-cache path surfaces it rather than failing in dir.create().
    expect_error(countryatlas:::wdj_disk_cache(), "countryatlas.cache_dir")
    options(old)
  }
})

test_that("a usable cache_dir option still works, and empty still falls back", {
  d <- file.path(tempdir(), "ca-opt-ok")
  unlink(d, recursive = TRUE)
  old <- options(countryatlas.cache_dir = d)
  on.exit({ options(old); unlink(d, recursive = TRUE) }, add = TRUE)
  expect_equal(countryatlas:::wdj_cache_dir(), d)
  expect_false(is.null(countryatlas:::wdj_disk_cache()))
  # An empty string is accepted and degrades to session-only caching, as before.
  options(countryatlas.cache_dir = "")
  expect_equal(countryatlas:::wdj_cache_dir(), "")
  expect_null(countryatlas:::wdj_disk_cache())
  # Unset, the default location is used.
  options(countryatlas.cache_dir = NULL)
  expect_true(nzchar(countryatlas:::wdj_cache_dir()))
})

test_that("the country label's provenance is what ?world_data says", {
  # Same call, two different labels: a successful fetch carries the World Bank's
  # names, while the offline spine carries countrycode's. That is unavoidable --
  # the WB names only exist in the response -- but it means `country` is not a
  # stable key across a run that degrades, so both help pages say so and point
  # at iso3c. Everything else in the package uses countrycode naming.
  fake <- function(country, indicator, start, end, extra = FALSE, ...) {
    out <- data.frame(iso2c = c("KR", "CD"), year = end, stringsAsFactors = FALSE)
    out$country <- c("Korea, Rep.", "Congo, Dem. Rep.")
    # See fake_wdi() above: the real WDI names the value column after
    # names(indicator), so a mock must too.
    nm <- names(indicator)[1]
    out[[if (is.null(nm) || !nzchar(nm)) indicator[[1]] else nm]] <- c(1, 2)
    out
  }
  testthat::with_mocked_bindings(.package = "WDI", WDI = fake, {
    got <- country_data(2020, "NY.GDP.PCAP.CD", cache = FALSE, parallel = FALSE)
    expect_identical(got$country[got$iso3c == "KOR"], "Korea, Rep.")
    expect_identical(got$country[got$iso3c == "COD"], "Congo, Dem. Rep.")
  })
  # With nothing fetched, the spine supplies the label -- countrycode's.
  testthat::with_mocked_bindings(.package = "WDI",
                                 WDI = function(...) stop("offline"), {
    spine <- suppressWarnings(
      world_data(2020, "NY.GDP.PCAP.CD", geometry = "none", cache = FALSE,
                 parallel = FALSE))
    expect_identical(spine$country[spine$iso3c == "KOR"], "South Korea")
    expect_identical(spine$country[spine$iso3c == "COD"], "Congo - Kinshasa")
  })
  # And the rest of the API agrees with the spine, not the fetch.
  expect_identical(convert_country(c("KOR", "COD"), to = "country",
                                   from = "iso3c"),
                   c("South Korea", "Congo - Kinshasa"))
  sc <- standardize_country(tibble::tibble(x = c("KOR", "COD")), "x",
                            origin = "iso3c", add = c("iso3c", "country"))
  expect_identical(sc$country, c("South Korea", "Congo - Kinshasa"))
})

test_that("the cache directory is honoured when it changes mid-session", {
  # The memoised fetcher used to be built once per session, so setting
  # options(countryatlas.cache_dir = ) after the first cached call was silently
  # ignored: writes kept landing in the original directory. ?clear_wdi_cache
  # offers that option as the way to relocate the cache and says nothing about
  # having to set it before the first fetch. It only ever took effect because
  # clear_wdi_cache() happened to reset the state.
  a <- file.path(tempfile("cache_a"), "c")
  b <- file.path(tempfile("cache_b"), "c")
  dir.create(a, recursive = TRUE)
  dir.create(b, recursive = TRUE)
  old <- options(countryatlas.cache_dir = a)
  on.exit({
    clear_wdi_cache(disk = TRUE)
    options(old)
  }, add = TRUE)
  n <- function(d) length(list.files(d, recursive = TRUE))

  testthat::with_mocked_bindings(.package = "WDI", WDI = fake_wdi, {
    invisible(country_data(2020, "SP.POP.TOTL", parallel = FALSE))
    expect_gt(n(a), 0L)
    expect_identical(n(b), 0L)

    options(countryatlas.cache_dir = b)
    was_a <- n(a)
    invisible(country_data(2021, "SP.POP.TOTL", parallel = FALSE))
    expect_gt(n(b), 0L)          # the new location is used...
    expect_identical(n(a), was_a)  # ...and the old one is left alone

    options(countryatlas.cache_dir = a)
    invisible(country_data(2022, "SP.POP.TOTL", parallel = FALSE))
    expect_gt(n(a), was_a)       # switching back resumes there
  })
})

test_that("a corrupt cache entry is named as such, not blamed on the API", {
  # An interrupted write leaves a truncated or empty .rds, and memoise surfaces
  # readRDS()'s own "unknown input format" from inside the fetch. Reporting that
  # as "Could not fetch ... from the World Bank API" sends the caller off to
  # debug a connection that is fine -- the same misattribution wdj_disk_cache()
  # already fixes for an unwritable directory. Worse, the bad entry stays put, so
  # every later call degrades identically until the cache is cleared.
  corrupt_with <- function(f) writeLines("not an rds", f)
  warn_of <- function(corrupt) {
    d <- file.path(tempfile("cache"), "c")
    dir.create(d, recursive = TRUE)
    old <- options(countryatlas.cache_dir = d)
    on.exit(options(old), add = TRUE)
    msg <- NA_character_
    testthat::with_mocked_bindings(.package = "WDI", WDI = fake_wdi, {
      invisible(country_data(2020, "SP.POP.TOTL", parallel = FALSE))
      corrupt(list.files(d, recursive = TRUE, full.names = TRUE))
      withCallingHandlers(
        invisible(country_data(2020, "SP.POP.TOTL", parallel = FALSE)),
        warning = function(w) {
          msg <<- conditionMessage(w)
          invokeRestart("muffleWarning")
        })
    })
    msg
  }

  for (shape in list(corrupt_with, function(f) file.create(f))) {
    m <- warn_of(shape)
    expect_match(m, "on-disk cache")
    expect_match(m, "clear_wdi_cache", fixed = TRUE)
    expect_false(grepl("World Bank API", m, fixed = TRUE))
  }

  # A genuine network failure must still blame the network.
  d <- file.path(tempfile("cache"), "c")
  dir.create(d, recursive = TRUE)
  old <- options(countryatlas.cache_dir = d)
  on.exit(options(old), add = TRUE)
  testthat::with_mocked_bindings(.package = "WDI",
                                 WDI = function(...) stop("Could not resolve host"), {
    expect_warning(country_data(2020, "SP.POP.TOTL", parallel = FALSE),
                   "World Bank API")
  })
})

test_that("an unwritable cache is reported once per directory, not per session", {
  # The notice names a specific path, so its .frequency_id has to include that
  # path. With a constant id a second unwritable location went unreported --
  # reachable only since the fetcher started rebuilding when the directory
  # changes, so this is the sibling of that fix rather than an old bug.
  unwritable <- function() {
    p <- tempfile("bad")
    file.create(p)          # a *file* where a directory is expected
    file.path(p, "sub")
  }
  a <- unwritable()
  b <- unwritable()
  old <- options(countryatlas.cache_dir = a)
  on.exit(options(old), add = TRUE)

  seen <- 0L
  testthat::with_mocked_bindings(.package = "WDI", WDI = fake_wdi, {
    withCallingHandlers({
      invisible(country_data(2020, "SP.POP.TOTL", parallel = FALSE))
      options(countryatlas.cache_dir = b)
      invisible(country_data(2021, "SP.POP.TOTL", parallel = FALSE))
      options(countryatlas.cache_dir = a)          # back to the first
      invisible(country_data(2022, "SP.POP.TOTL", parallel = FALSE))
    }, message = function(m) {
      seen <<- seen + 1L
      invokeRestart("muffleMessage")
    })
  })
  # One for each distinct directory; returning to the first stays quiet.
  expect_identical(seen, 2L)
})

test_that("a memory-only memo is not thrown away by forking", {
  # The in-session memo lives in this process. mclapply() forks, so a memo
  # populated by a worker dies with that worker and the next call re-fetches
  # everything -- caching silently never works. Only reachable when the disk
  # cache is unavailable, because a disk memo is shared by every process.
  skip_on_os("windows")                 # no forking, so nothing to lose
  skip_if_not_installed("parallel")

  # Count fetches in a way that survives a fork: a variable would be
  # incremented in the child and lost, which is the very bug under test.
  tally <- tempfile("tally")
  on.exit(unlink(tally), add = TRUE)
  counting_wdi <- function(indicator, start, end, extra = FALSE,
                           language = "en", ...) {
    cat("x", file = tally, append = TRUE)
    fake_wdi(indicator, start, end, extra = extra, language = language, ...)
  }
  n_fetches <- function() {
    if (!file.exists(tally)) return(0L)
    nchar(paste(readLines(tally, warn = FALSE), collapse = ""))
  }

  # A *file* where a directory is expected: dir.create(recursive = TRUE) makes
  # any merely-absent parent, so only this makes the location truly unusable.
  parent <- tempfile("nodir")
  file.create(parent)
  bad <- file.path(parent, "sub")
  on.exit(unlink(parent), add = TRUE)
  old <- options(countryatlas.cache_dir = bad)
  on.exit(options(old), add = TRUE)
  .wdj_state$fetch_memo <- NULL                # force a rebuild
  on.exit(.wdj_state$fetch_memo <- NULL, add = TRUE)
  ind <- c(pop = "SP.POP.TOTL", gdp = "NY.GDP.MKTP.CD")

  suppressMessages(testthat::with_mocked_bindings(
    .package = "WDI", WDI = counting_wdi, {
      invisible(country_data(2020, ind, parallel = TRUE))
      first <- n_fetches()
      invisible(country_data(2020, ind, parallel = TRUE))
      second <- n_fetches() - first
      expect_identical(first, 2L)
      expect_identical(second, 0L)   # served from the memo, not re-fetched
    }
  ))
})

test_that("a writable cache still fetches indicators in parallel", {
  # The guard above must not cost parallelism on the normal path.
  skip_on_os("windows")
  skip_if_not_installed("parallel")
  skip_if(wdj_workers(2) <= 1L, "single core")

  tally <- tempfile("pids")
  dir <- file.path(tempfile("cache"), "c")
  dir.create(dir, recursive = TRUE)
  old <- options(countryatlas.cache_dir = dir)
  on.exit({
    options(old)
    unlink(c(tally, dirname(dir)), recursive = TRUE)
    .wdj_state$fetch_memo <- NULL
  }, add = TRUE)
  .wdj_state$fetch_memo <- NULL

  pid_wdi <- function(indicator, start, end, extra = FALSE,
                      language = "en", ...) {
    cat(Sys.getpid(), "\n", file = tally, append = TRUE, sep = "")
    fake_wdi(indicator, start, end, extra = extra, language = language, ...)
  }
  suppressMessages(testthat::with_mocked_bindings(
    .package = "WDI", WDI = pid_wdi, {
      invisible(country_data(
        2020, c(pop = "SP.POP.TOTL", gdp = "NY.GDP.MKTP.CD"), parallel = TRUE
      ))
    }
  ))
  pids <- readLines(tally, warn = FALSE)
  expect_length(pids, 2L)
  expect_false(all(pids == as.character(Sys.getpid())))   # ran in children
})

test_that("a failed indicator still warns when indicators are fetched in parallel", {
  # mclapply() brings back a worker's value but not its conditions, so the
  # warning fetch_one_safe() raises used to vanish whenever fetching forked --
  # which is whenever there is more than one indicator, i.e. the default. The
  # column was dropped from the result and nothing was said.
  skip_on_os("windows")
  skip_if_not_installed("parallel")
  skip_if(wdj_workers(2) <= 1L, "single core")

  flaky <- function(indicator, start, end, extra = FALSE, language = "en", ...) {
    if (identical(unname(indicator)[1], "BAD.CODE")) {
      stop("Could not resolve host: api.worldbank.org")
    }
    fake_wdi(indicator, start, end, extra = extra, language = language, ...)
  }
  dir <- file.path(tempfile("cache"), "c")
  dir.create(dir, recursive = TRUE)
  old <- options(countryatlas.cache_dir = dir)
  on.exit({
    options(old)
    unlink(dirname(dir), recursive = TRUE)
    .wdj_state$fetch_memo <- NULL
  }, add = TRUE)
  .wdj_state$fetch_memo <- NULL

  suppressMessages(testthat::with_mocked_bindings(.package = "WDI", WDI = flaky, {
    expect_warning(
      out <- country_data(2020, c(bad = "BAD.CODE", gdp = "NY.GDP.MKTP.CD"),
                          parallel = TRUE),
      "BAD\\.CODE"
    )
    # Degrading gracefully is still the contract: the good indicator survives.
    expect_true("gdp" %in% names(out))
    expect_false("bad" %in% names(out))
  }))
})

test_that("one problem is reported once even when two entries share a code", {
  # The warning names the indicator code, so a caller who lists the same series
  # under two names would otherwise be told about it twice.
  flaky <- function(indicator, start, end, extra = FALSE, language = "en", ...) {
    stop("Could not resolve host: api.worldbank.org")
  }
  .wdj_state$fetch_memo <- NULL
  on.exit(.wdj_state$fetch_memo <- NULL, add = TRUE)

  seen <- character()
  suppressMessages(testthat::with_mocked_bindings(.package = "WDI", WDI = flaky, {
    withCallingHandlers(
      invisible(country_data(2020, c(a = "SP.POP.TOTL", b = "SP.POP.TOTL"),
                             cache = FALSE, parallel = FALSE)),
      warning = function(w) {
        seen <<- c(seen, conditionMessage(w))
        invokeRestart("muffleWarning")
      }
    )
  }))
  expect_length(seen, 1L)
})
