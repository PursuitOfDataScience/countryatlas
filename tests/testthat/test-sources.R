# --- data sources ----------------------------------------------------------------

test_that("the built-in sources are registered at load", {
  s <- country_sources()
  expect_true(all(c("wdi", "owid", "eurostat", "oecd", "comtrade") %in% s$source))
  expect_named(s, c("source", "meta", "key_col", "key_type", "cache",
                    "available", "citation"))
  # Every bundled source reads its key as iso3c; that default is exactly why
  # key_col's second life as a coding scheme went unnoticed.
  expect_true(all(s$key_type == "iso3c"))
  expect_true(s$available[s$source == "wdi"])
})

test_that("a user source round-trips through the contract", {
  register_country_source(
    "test_src",
    fetch = function(indicator, countries = NULL, years = NULL) {
      d <- data.frame(iso3c = c("USA", "FRA", "JPN"), year = 2020L,
                      demo = c(1, 2, 3))
      if (!is.null(countries)) d <- d[d$iso3c %in% countries, ]
      d
    },
    meta = "test", citation = "nobody"
  )
  on.exit(rm("test_src", envir = countryatlas:::the_sources), add = TRUE)
  expect_true("test_src" %in% country_sources()$source)
  out <- fetch_indicator("test_src", "demo")
  expect_equal(nrow(out), 3L)
  expect_true(all(c("iso3c", "year", "demo") %in% names(out)))
  # countries= is forwarded
  expect_equal(nrow(fetch_indicator("test_src", "demo", countries = "USA")), 1L)
})

test_that("the contract is enforced with named errors", {
  skip_slow_on_cran()
  expect_error(fetch_indicator("no_such_source", "x"), "Unknown source")
  expect_error(register_country_source("bad", fetch = 42), "must be a function")
  register_country_source("junk_src", function(...) 42)
  register_country_source("nokey_src", function(...) data.frame(a = 1))
  on.exit({
    rm("junk_src", envir = countryatlas:::the_sources)
    rm("nokey_src", envir = countryatlas:::the_sources)
  }, add = TRUE)
  expect_error(fetch_indicator("junk_src", "x"), "not a data frame")
  expect_error(fetch_indicator("nokey_src", "x"), "no .*iso3c.* column")
})

test_that("add_indicator joins onto an existing frame", {
  register_country_source("add_src", function(indicator, countries = NULL,
                                              years = NULL) {
    data.frame(iso3c = c("USA", "FRA"), year = 2020L, extra = c(10, 20))
  })
  on.exit(rm("add_src", envir = countryatlas:::the_sources), add = TRUE)
  base <- data.frame(iso3c = c("USA", "FRA", "JPN"), v = 1:3)
  out <- add_indicator(base, "add_src", "extra")
  expect_equal(nrow(out), 3L)
  expect_equal(out$extra, c(10, 20, NA))
  expect_error(add_indicator(data.frame(x = 1), "add_src", "extra"), "iso3c")
})

test_that("compare_sources validates before it fetches", {
  expect_error(compare_sources("x", sources = "wdi", year = 2020),
               "at least two")
  expect_error(compare_sources("x", sources = c("wdi", "owid")), "year")
  expect_error(compare_sources(c(wdi = "a"), sources = c("wdi", "owid"),
                               year = 2020), "names no code")
})

test_that("an adapter reports an unreachable provider, not a missing column", {
  # The failure mode this guards: a client that answers a failed download with
  # an empty frame rather than an error.
  expect_error(
    countryatlas:::adapter_reshape(data.frame(entity = character(0)), "x",
                                   "entity", "year"),
    "returned no rows")
})

test_that("clear_country_cache validates the source name", {
  expect_error(clear_country_cache("no_such_source"), "Unknown source")
  expect_true(clear_country_cache())
})

test_that("registering the built-in sources twice does not duplicate them", {
  n1 <- nrow(country_sources())
  countryatlas:::register_builtin_sources()
  expect_equal(nrow(country_sources()), n1)
})

test_that("the source adapters validate `indicator` before doing anything else", {
  skip_slow_on_cran()
  # All four are exported in their own right, so each has to repeat the check
  # fetch_indicator() does at its front door. Before this, fetch_owid(NULL) and
  # its eurostat/oecd siblings returned a silent NULL -- lapply() over an empty
  # vector produces no frames and Reduce() over an empty list is NULL -- while
  # fetch_comtrade() leaked comtradr's "subscript out of bounds". The check runs
  # ahead of need_pkg(), so this test needs none of the four clients installed.
  adapters <- list(owid = fetch_owid, eurostat = fetch_eurostat,
                   oecd = fetch_oecd, comtrade = fetch_comtrade)
  for (nm in names(adapters)) {
    for (bad in list(NULL, character(0), NA, 1L, list("a"))) {
      expect_error(adapters[[nm]](bad), "non-empty character vector",
                   info = paste(nm, deparse(bad)[1]))
    }
  }
  # The front door keeps its own guard.
  expect_error(fetch_indicator("wdi", NULL), "non-empty character vector")
})

test_that("adapter_reshape names a missing column instead of failing on recycling", {
  # entity_col was checked; value_col was not, although fetch_eurostat() passes
  # "values" outright and fetch_oecd() guesses between two spellings. A provider
  # that changed shape produced as.numeric(NULL) -- a zero-length column in a
  # full-length tibble -- and a recycling error several frames away.
  ar <- countryatlas:::adapter_reshape
  raw <- tibble::tibble(geo = c("DE", "FR"), year = c(2020L, 2020L),
                        wrongname = c(1, 2))
  expect_error(ar(raw, "v", entity_col = "geo", year_col = "year",
                  value_col = "values"), "value column")
  expect_error(ar(raw, "v", entity_col = "nope", year_col = "year",
                  value_col = "wrongname"), "entity column")
  ok <- ar(raw, "v", entity_col = "geo", year_col = "year",
           value_col = "wrongname", origin = "eurostat")
  expect_named(ok, c("iso3c", "year", "v"))
  expect_equal(nrow(ok), 2L)
})

test_that("compare_sources summarises each pair on that pair alone", {
  # Every column of the summary is pairwise; n_disagree was not. It read the
  # row-wise `disagrees`, i.e. the spread across *all* sources, so with three
  # or more a pair that agreed exactly was counted as disagreeing whenever some
  # third source was the outlier.
  iso <- c("FRA", "DEU", "ITA", "ESP")
  mk <- function(v) function(indicator, countries = NULL, years = NULL, ...) {
    tibble::tibble(iso3c = iso, year = 2020L, value = v)
  }
  register_country_source("test_a", mk(c(100, 200, 300, 400)))
  register_country_source("test_b", mk(c(100, 200, 300, 400)))
  register_country_source("test_c", mk(rep(999, 4)))
  withr::defer(for (s in c("test_a", "test_b", "test_c"))
    suppressWarnings(rm(list = s, envir = countryatlas:::the_sources)))

  cmp <- compare_sources("x", sources = c("test_a", "test_b", "test_c"),
                         year = 2020)
  s <- attr(cmp, "countryatlas_source_summary")
  ab <- s[s$source_x == "test_a" & s$source_y == "test_b", ]
  expect_equal(ab$n_disagree, 0L)      # identical sources
  expect_equal(ab$correlation, 1)
  expect_equal(s$n_disagree[s$source_y == "test_c"], c(4L, 4L))
  # The row-wise column still reports the spread over all three.
  expect_true(all(cmp$rel_diff > 0))
})

test_that("a constant source gives NA correlation without warning", {
  iso <- c("FRA", "DEU", "ITA", "ESP")
  mk <- function(v) function(indicator, countries = NULL, years = NULL, ...) {
    tibble::tibble(iso3c = iso, year = 2020L, value = v)
  }
  register_country_source("test_v", mk(c(1, 2, 3, 4)))
  register_country_source("test_k", mk(rep(7, 4)))
  withr::defer(for (s in c("test_v", "test_k"))
    suppressWarnings(rm(list = s, envir = countryatlas:::the_sources)))
  expect_no_warning(
    cmp <- compare_sources("x", sources = c("test_v", "test_k"), year = 2020)
  )
  expect_true(is.na(attr(cmp, "countryatlas_source_summary")$correlation))
})

test_that("add_indicator overwrites a clashing column, as its warning says", {
  # warn_overwrite() promised "Overwriting ... rename them first to keep the
  # original values", but the left_join underneath suffixed both sides to
  # `x.x`/`x.y` instead -- so the caller got neither the column they asked for
  # nor the one they had, and the advice described a mechanism that never ran.
  mk <- function(v) function(indicator, countries = NULL, years = NULL, ...) {
    tibble::tibble(iso3c = c("FRA", "DEU"), val = v)
  }
  register_country_source("test_clash", mk(c(99, 98)))
  withr::defer(suppressWarnings(
    rm(list = "test_clash", envir = countryatlas:::the_sources)))

  d <- tibble::tibble(iso3c = c("FRA", "DEU"), val = c(1, 2))
  expect_warning(out <- add_indicator(d, "test_clash", "x"), "Overwriting")
  expect_named(out, c("iso3c", "val"))
  expect_equal(out$val, c(99, 98))
  expect_false(any(grepl("[.](x|y)$", names(out))))

  # No clash: unchanged, and quiet.
  d2 <- tibble::tibble(iso3c = c("FRA", "DEU"), other = c(1, 2))
  expect_no_warning(o2 <- add_indicator(d2, "test_clash", "x"))
  expect_named(o2, c("iso3c", "other", "val"))
})

test_that("compare_sources rejects an unnamed multi-code indicator", {
  skip_slow_on_cran()
  # The named branch's error already told callers to "pass a single unnamed
  # code", but nothing enforced it: an unnamed vector was truncated to its
  # first element and broadcast to every source. For this verb specifically
  # that is the worst possible failure -- it then compares a code against
  # itself and reports the sources as agreeing perfectly.
  iso <- c("FRA", "DEU")
  mk <- function() function(indicator, countries = NULL, years = NULL, ...) {
    tibble::tibble(iso3c = iso, year = 2020L,
                   value = if (identical(indicator[[1]], "A")) c(1, 2) else c(9, 9))
  }
  register_country_source("test_s1", mk())
  register_country_source("test_s2", mk())
  withr::defer(for (s in c("test_s1", "test_s2"))
    suppressWarnings(rm(list = s, envir = countryatlas:::the_sources)))
  src <- c("test_s1", "test_s2")

  expect_error(compare_sources(c("A", "B"), sources = src, year = 2020),
               "must be a single code")
  # The three documented shapes still work.
  expect_equal(nrow(compare_sources("A", sources = src, year = 2020)), 2L)
  named <- compare_sources(c(test_s1 = "A", test_s2 = "B"), sources = src,
                           year = 2020)
  expect_equal(nrow(named), 2L)
  # A named vector really does give each source its own code.
  expect_false(isTRUE(all.equal(named$test_s1, named$test_s2)))
  expect_error(compare_sources(c(test_s1 = "A"), sources = src, year = 2020),
               "names no code")
})

test_that("`years` means the same thing for every source", {
  # It is documented as "a numeric year vector", and adapter_reshape() honours
  # that for the four adapters (year %in% years). The WDI path used min/max as
  # a fetch range and never filtered, so years = c(2000, 2020) asked for two
  # years and got twenty-one -- the same argument meaning different things
  # depending on which source you named.
  withr::local_options(
    countryatlas.cache_dir = file.path(tempdir(), "cc-years"))
  orig <- countryatlas:::fetch_one_indicator
  stub <- function(code, name, start, end, language = "en") {
    yrs <- seq(start, end)
    x <- tibble::tibble(iso2c = "US", iso3c = "USA", country = "US",
                        year = as.integer(yrs))
    x[[name]] <- seq_along(yrs)
    x
  }
  assignInNamespace("fetch_one_indicator", stub, "countryatlas")
  withr::defer(assignInNamespace("fetch_one_indicator", orig, "countryatlas"))

  two <- fetch_indicator("wdi", c(x = "I1"), years = c(2000, 2020))
  expect_equal(nrow(two), 2L)
  expect_setequal(two$year, c(2000L, 2020L))
  # A contiguous request still gets the whole span.
  expect_equal(nrow(fetch_indicator("wdi", c(x = "I1"), years = 2000:2020)), 21L)
  expect_equal(nrow(fetch_indicator("wdi", c(x = "I1"), years = 2005)), 1L)
})

test_that("register_country_source(cache = ) actually memoises", {
  skip_slow_on_cran()
  # `cache` was stored in the registry and reported by country_sources(), but
  # nothing ever read it: the documented per-session memoisation never happened
  # and cache = FALSE was equally inert.
  calls <- 0L
  fetcher <- function(indicator, countries, years, ...) {
    calls <<- calls + 1L
    tibble::tibble(iso3c = c("USA", "FRA"), year = 2020L, value = c(1, 2))
  }
  register_country_source("cachetest", fetch = fetcher, cache = TRUE)
  on.exit(clear_country_cache("cachetest"), add = TRUE)
  fetch_indicator("cachetest", "x")
  fetch_indicator("cachetest", "x")
  expect_equal(calls, 1L)                       # second call served from memo
  fetch_indicator("cachetest", "y")
  expect_equal(calls, 2L)                       # a different key refetches
  fetch_indicator("cachetest", "x", countries = "USA")
  expect_equal(calls, 3L)                       # so does a different subset
  clear_country_cache("cachetest")
  fetch_indicator("cachetest", "x")
  expect_equal(calls, 4L)                       # and clearing forces a refetch

  n2 <- 0L
  register_country_source("cachetest2", cache = FALSE,
    fetch = function(indicator, countries, years, ...) {
      n2 <<- n2 + 1L
      tibble::tibble(iso3c = "USA", year = 2020L, value = 1)
    })
  fetch_indicator("cachetest2", "x")
  fetch_indicator("cachetest2", "x")
  expect_equal(n2, 2L)                          # cache = FALSE stays uncached
})

test_that("adapter_reshape says when no entity resolved to a country", {
  skip_slow_on_cran()
  # The entity column is resolved with suppressWarnings(), deliberately: every
  # OWID/Eurostat response carries aggregate rows ("World", "EU27") that never
  # resolve, so the per-name warning would fire on every call. The cost is that
  # a provider renaming its entities was swallowed with them -- the adapter
  # returned an empty frame in silence, sending the reader to check their own
  # indicator code, while the same function goes to some trouble to explain an
  # empty *input* a few lines earlier.
  ar <- countryatlas:::adapter_reshape

  # Aggregates alongside a real country: still dropped quietly, as intended.
  keep <- ar(data.frame(entity = c("France", "World", "EU27"), year = 2020L,
                        v = 1:3), "v", "entity", "year")
  expect_equal(keep$iso3c, "FRA")

  # Nothing resolving at all is never just aggregates.
  expect_error(ar(data.frame(entity = "Atlantis", year = 2020L, v = 1),
                  "v", "entity", "year"),
               class = "countryatlas_no_entities")
  expect_error(ar(data.frame(entity = "Atlantis", year = 2020L, v = 1),
                  "v", "entity", "year"), "None of the 1 entity")
  expect_error(ar(data.frame(entity = c("Nowhere", "Atlantis"), year = 2020L,
                             v = 1:2), "v", "entity", "year"),
               "None of the 2 entities")
  # The message names what it could not resolve.
  expect_error(ar(data.frame(entity = "Atlantis", year = 2020L, v = 1),
                  "v", "entity", "year"), "Atlantis")

  # An empty result from *filtering* is a different thing and must not be
  # mistaken for it: the entities resolved fine, the year simply excluded them.
  empty <- ar(data.frame(entity = "France", year = 2020L, v = 1),
              "v", "entity", "year", years = 1999L)
  expect_equal(nrow(empty), 0L)
  expect_named(empty, c("iso3c", "year", "v"))
})

test_that("the adapters read a year from whatever shape the provider sends", {
  skip_slow_on_cran()
  # `...` forwards to the client, so the caller controls the time column's
  # type: eurostat's time_format = "num" gives a numeric year, "raw" a
  # character one, the default a Date. Reading each with one assumption failed
  # loudly for eurostat -- format(numeric, "%Y") is base R's opaque "invalid
  # 'trim' argument" -- and *silently wrongly* for OECD, where as.integer() on
  # a Date returned 18262, the day count, as the year, and "2020-Q1" became NA.
  ay <- countryatlas:::read_year
  expect_equal(ay(as.Date(c("2020-01-01", "1999-06-30")), "p"), c(2020L, 1999L))
  expect_equal(ay(c(2020, 1999), "p"), c(2020L, 1999L))
  expect_equal(ay(c("2020", "1999"), "p"), c(2020L, 1999L))
  expect_equal(ay(c("2020-01-01", "2020-Q1", "2020M03"), "p"), rep(2020L, 3))
  # A genuine NA stays NA without comment; there is nothing to report.
  expect_silent(expect_equal(ay(c(2020, NA), "p"), c(2020L, NA)))

  # Unusable values are dropped *and* named, both when they parse to something
  # implausible and when they do not parse at all.
  expect_warning(expect_equal(ay(c(2020, 5), "p"), c(2020L, NA)),
                 class = "countryatlas_bad_year")
  expect_warning(expect_equal(ay(c("2020", "junk"), "p"), c(2020L, NA)),
                 class = "countryatlas_bad_year")
  expect_warning(ay(c("2020", "junk"), "OECD"), "OECD: 1 time value is")
  expect_warning(ay(c("junk", "rubbish"), "OECD"), "2 time values are")

  # End to end through the adapters, on the shapes that used to break.
  sdmx <- function(tt) {
    csv <- paste(c("DATAFLOW,REF_AREA,TIME_PERIOD,OBS_VALUE",
                   sprintf("X:Y(1.0),%s,%s,%d", c("FR", "DE"), tt, 1:2)),
                 collapse = "\n")
    local_fixture_http(list("/data/" = function(u) fixture_response(text = csv)))
    fetch_sdmx("bis", c(x = "BIS,X,1.0"))$year
  }
  expect_equal(sdmx(c("2020", "2020")), c(2020L, 2020L))
  # A quarter is not a year: an SDMX series by quarter has four rows per
  # country-year, which the reader refuses rather than keep one of.
  expect_error(sdmx(c("2020-Q1", "2020-Q1")), class = "countryatlas_sdmx_not_unique")
  skip_if_not_installed("eurostat")
  euro <- function(tp) {
    local_mocked_bindings(
      get_eurostat = function(id, ...) data.frame(
        geo = c("FR", "DE"), TIME_PERIOD = tp, values = c(1, 2)),
      .package = "eurostat")
    fetch_eurostat(c(x = "ID"))$year
  }
  expect_equal(euro(c(2020, 2020)), c(2020L, 2020L))       # was "invalid 'trim'"
  expect_equal(euro(c("2020", "2020")), c(2020L, 2020L))
})

test_that("every source path reads the year the same way", {
  # The bare as.integer() bug reached six sites, not two: all four adapters,
  # adapter_reshape() itself (which fetch_owid reaches without preprocessing),
  # and fetch_indicator() -- the *public extension point*, where the year is
  # whatever a third-party fetch function chose to return.
  ar <- countryatlas:::adapter_reshape

  # adapter_reshape's own year column (the fetch_owid path).
  expect_equal(suppressWarnings(ar(
    data.frame(entity = "France", year = as.Date("2020-06-01"), v = 1),
    "v", "entity", "year"))$year, 2020L)

  # A registered source may return any of these; all must mean 2020.
  shapes <- list(date = as.Date(c("2020-01-01", "2020-01-01")),
                 quarterly = c("2020-Q1", "2020-Q2"),
                 monthly = c("202001", "202002"),
                 integer = c(2020L, 2020L))
  for (nm in names(shapes)) {
    register_country_source(
      "probe_year",
      function(indicator, countries, years, ...) {
        tibble::tibble(iso3c = c("USA", "FRA"), year = shapes[[nm]],
                       value = c(1, 2))
      }, cache = FALSE)
    got <- suppressWarnings(fetch_indicator("probe_year", "x"))
    expect_equal(got$year, c(2020L, 2020L), info = nm)
  }
  clear_country_cache("probe_year")

  # comtradr's `period` is YYYYMM for monthly data, which `...` can select.
  skip_if_not_installed("comtradr")
  ct <- function(per) {
    local_mocked_bindings(
      ct_get_data = function(...) data.frame(
        reporter_iso = c("FRA", "DEU"), period = per,
        primary_value = c(1, 2)), .package = "comtradr")
    fetch_comtrade(c(x = "0101"))$year
  }
  expect_equal(ct(c("202001", "202002")), c(2020L, 2020L))  # was 202001
  expect_equal(ct(as.Date(c("2020-01-01", "2020-01-01"))), c(2020L, 2020L))
  expect_equal(ct(c(2020L, 2020L)), c(2020L, 2020L))
})

test_that("a factor value column is read as numbers, not level indices", {
  # as.numeric() on a factor returns its *level indices*, so a provider value
  # column of factor("10", "20") became 1, 2 -- silently wrong numbers.
  # check_numeric_col() rejects a factor outright with exactly this advice
  # ("as.numeric(as.character(x))") and its comment notes how easily a factor
  # column happens; the adapters take theirs from a third party, so they cannot
  # reject it, but they must not misread it either.
  ar <- countryatlas:::adapter_reshape
  vals <- function(v) suppressWarnings(ar(
    data.frame(entity = c("France", "Germany"), year = 2020L, v = v),
    "v", "entity", "year", value_col = "v"))$v

  expect_equal(vals(c(10, 20)), c(10, 20))
  expect_equal(vals(c("10", "20")), c(10, 20))
  expect_equal(vals(factor(c("10", "20"))), c(10, 20))       # was c(1, 2)
  expect_equal(vals(factor(c("1.5", "2.5"))), c(1.5, 2.5))
  # Levels in a different order than the values must not change the answer --
  # the failure mode that makes the index bug hard to spot.
  expect_equal(vals(factor(c("10", "20"), levels = c("20", "10"))), c(10, 20))
})

test_that("fetch_indicator does not trust a source's key_col claim", {
  skip_slow_on_cran()
  # key_col = "iso3c" is the source's *claim*, not a guarantee, and this is the
  # public extension point. Trusting it let lowercase codes ("usa") through
  # unchanged, kept a factor a factor, and passed numeric UN M49 codes (840)
  # along as numbers -- each producing rows that silently joined to nothing and
  # read as "the provider has no data".
  probe <- function(iso) {
    register_country_source(
      "probe_key", function(indicator, countries, years, ...) {
        tibble::tibble(iso3c = iso, year = 2020L, value = seq_along(iso))
      }, cache = FALSE)
    fetch_indicator("probe_key", "x")
  }
  on.exit(clear_country_cache("probe_key"), add = TRUE)

  # Already-correct codes are untouched and silent.
  expect_silent(good <- probe(c("USA", "FRA")))
  expect_equal(good$iso3c, c("USA", "FRA"))
  # Lowercase and factor keys are standardised rather than passed through.
  expect_silent(expect_equal(probe(c("usa", "fra"))$iso3c, c("USA", "FRA")))
  expect_silent(expect_equal(probe(factor(c("USA", "FRA")))$iso3c,
                             c("USA", "FRA")))
  # Unusable keys become NA *and* are reported, in both numbers.
  expect_warning(m49 <- probe(c(840, 250)), class = "countryatlas_bad_key")
  expect_true(all(is.na(m49$iso3c)))
  expect_warning(probe(c("USA", "ZZZ")), "1 value that is not usable")
  expect_warning(probe(c("YYY", "ZZZ")), "2 values that are not usable")
})

test_that("a source's key column is a column name, not a coding scheme", {
  skip_slow_on_cran()
  # key_col is documented as "the country-key column `fetch` returns" and is
  # used to index that column -- but it was also handed to countrycode as
  # `origin`, so the only registrations that worked were ones whose column
  # happened to be named after a coding scheme. All five builtins use the
  # "iso3c" default, which short-circuits before countrycode ever sees it, so
  # nothing in the package exercised the path.
  register_country_source("kt_named", key_col = "country",
                          key_type = "country.name",
                          fetch = function(indicator, countries = NULL,
                                           years = NULL) {
                            data.frame(country = c("France", "Japan"),
                                       year = 2020L, v = c(1, 2))
                          })
  on.exit(rm("kt_named", envir = countryatlas:::the_sources), add = TRUE)
  expect_silent(got <- fetch_indicator("kt_named", "v"))
  expect_identical(got$iso3c, c("FRA", "JPN"))
  expect_true("key_type" %in% names(country_sources()))

  # A bad scheme fails at registration, where the mistake is, and names
  # `key_type` rather than the internal `origin`.
  err <- tryCatch(register_country_source("kt_bad", key_type = "country",
                                          fetch = function(...) NULL),
                  error = identity)
  expect_s3_class(err, "countryatlas_bad_origin")
  expect_match(cli::ansi_strip(conditionMessage(err)), "key_type",
               fixed = TRUE)

  # Country names left under the default iso3c scheme resolve to nothing, so
  # say which knob fixes it rather than only that the values were unusable.
  register_country_source("kt_misconf", key_col = "country",
                          fetch = function(indicator, countries = NULL,
                                           years = NULL) {
                            data.frame(country = "France", year = 2020L, v = 1)
                          })
  on.exit(rm("kt_misconf", envir = countryatlas:::the_sources), add = TRUE)
  w <- tryCatch(fetch_indicator("kt_misconf", "v"), warning = identity)
  expect_s3_class(w, "countryatlas_bad_key")
  expect_match(cli::ansi_strip(conditionMessage(w)), "country.name",
               fixed = TRUE)
})

test_that("a non-numeric provider response is reported, not silently NA", {
  skip_slow_on_cran()
  # as.numeric() turns non-numeric text into NA without complaint, so a
  # provider answering with "n/a" or ".." handed back a column of pure NA that
  # reads as "no data for these countries" rather than "not numeric".
  # The SDMX reader reads OBS_VALUE as text and names the column outright,
  # so it reaches the coercion.
  oe <- NULL
  local_fixture_http(list(
    "/dataflow/" = function(u) stop("no structure"),
    "/data/" = function(u) fixture_response(text = paste(c(
      "DATAFLOW,REF_AREA,TIME_PERIOD,OBS_VALUE",
      sprintf("X:Y(1.0),%s,2020,%s", c("FRA", "JPN"), oe)), collapse = "\n"))))
  oecd <- function() fetch_oecd(c(x = "OECD.X,DSD_X@DF_X,1.0"))

  oe <- c("1", "2")
  expect_silent(oecd())
  # A value the provider itself reports as missing is already NA, not a parse
  # failure, so it must stay silent.
  oe <- c("", "2")
  expect_silent(oecd())

  oe <- c("1.5", "n/a")
  expect_warning(out <- oecd(), class = "countryatlas_unparsed_values")
  expect_equal(out$x, c(1.5, NA))
  msg <- function(e) cli::ansi_strip(conditionMessage(tryCatch(e,
    warning = identity)))
  expect_match(msg(oecd()), "1 value in the provider's response is",
               fixed = TRUE)
  oe <- c("n/a", "..")
  expect_match(msg(oecd()), "2 values in the provider's response are",
               fixed = TRUE)
})

test_that("the provider adapters report the rows they discard", {
  skip_slow_on_cran()
  # Each adapter ends by keeping one row per country-year -- the contract the
  # joins rely on -- but kept whichever came first and said nothing, so a
  # provider answering with two different values for one country-year handed
  # back an arbitrary one, order-dependently and invisibly.
  ret <- NULL
  local_fixture_http(list(
    ".metadata.json" = function(u) fixture_response(text = "{}"),
    "/grapher/" = function(u) {
      con <- textConnection("csv", "w", local = TRUE)
      utils::write.csv(ret, con, row.names = FALSE)
      close(con)
      fixture_response(text = paste(csv, collapse = "\n"))
    }))
  owid <- function(code, year, v) {
    ret <<- data.frame(entity = code, code = code, year = year, v = v)
    fetch_owid("x")
  }
  expect_silent(owid(c("FRA", "JPN"), 2020L, c(10, 20)))
  expect_warning(out <- owid(c("FRA", "FRA"), 2020L, c(1, 99)),
                 class = "countryatlas_provider_duplicates")
  expect_identical(nrow(out), 1L)
  expect_match(cli::ansi_strip(conditionMessage(tryCatch(
    owid(c("FRA", "FRA"), 2020L, c(1, 99)), warning = identity))),
    "1 duplicate country-year row,", fixed = TRUE)
  expect_match(cli::ansi_strip(conditionMessage(tryCatch(
    owid(c("FRA", "FRA", "JPN", "JPN"), 2020L, c(1, 99, 2, 3)),
    warning = identity))), "2 duplicate country-year rows", fixed = TRUE)
  # A country with two years is a panel, not a duplicate.
  expect_silent(owid(c("FRA", "FRA"), c(2019L, 2020L), c(1, 2)))
})

test_that("a source whose keys collapse warns instead of repeating rows", {
  skip_slow_on_cran()
  # Standardisation merges keys as well as failing on them: "United States"
  # and "USA" both reach USA, and add_indicator()'s left_join then matches
  # twice, so a two-row frame came back with three rows and one country
  # holding two different values -- silently, because dplyr only warns on
  # many-to-many, not one-to-many. join_world() has warned about exactly this
  # since it gained warn_key_collapse(); the source adapters never did.
  register_country_source("kc_dup", key_col = "country",
                          key_type = "country.name",
                          fetch = function(indicator, countries = NULL,
                                           years = NULL) {
                            data.frame(country = c("United States", "USA"),
                                       year = 2020L, v = c(1, 2))
                          })
  on.exit(rm("kc_dup", envir = countryatlas:::the_sources), add = TRUE)
  expect_warning(fetch_indicator("kc_dup", "v"),
                 class = "countryatlas_key_collapse")

  # The source's own key column is not the caller's data. `add_cols` excluded
  # only "iso3c", so a source keyed on any other column handed that raw column
  # over as though it had been requested -- a stray `country` column in a
  # frame that already had iso3c.
  # The collapse check only sees a code reached from more than one raw value.
  # A source returning the same key twice collapses nothing, so it warned about
  # nothing -- while add_indicator()'s join still turned two rows into three.
  mk <- function(iso, v, yr = 2020L) {
    function(indicator, countries = NULL, years = NULL) {
      data.frame(iso3c = iso, year = yr, v = v)
    }
  }
  register_country_source("kc_same", fetch = mk(c("USA", "USA"), c(1, 99)))
  register_country_source("kc_two", fetch = mk(c("USA", "USA", "FRA", "FRA"),
                                               c(1, 99, 2, 3)))
  register_country_source("kc_panel",
                          fetch = function(indicator, countries = NULL,
                                           years = NULL) {
                            data.frame(iso3c = rep(c("USA", "FRA"), each = 2),
                                       year = rep(2019:2020, 2), v = 1:4)
                          })
  on.exit(for (s in c("kc_same", "kc_two", "kc_panel"))
    rm(list = s, envir = countryatlas:::the_sources), add = TRUE)
  expect_warning(fetch_indicator("kc_same", "v"),
                 class = "countryatlas_duplicate_key")
  expect_match(cli::ansi_strip(conditionMessage(tryCatch(
    fetch_indicator("kc_same", "v"), warning = identity))),
    "1 duplicate key row.", fixed = TRUE)
  expect_match(cli::ansi_strip(conditionMessage(tryCatch(
    fetch_indicator("kc_two", "v"), warning = identity))),
    "2 duplicate key rows", fixed = TRUE)
  # A real panel has several years per country and must not be flagged: the
  # key is iso3c *and* year wherever a year column exists.
  expect_silent(fetch_indicator("kc_panel", "v"))

  register_country_source("kc_clean", key_col = "country",
                          key_type = "country.name",
                          fetch = function(indicator, countries = NULL,
                                           years = NULL) {
                            data.frame(country = c("France", "Japan"),
                                       year = 2020L, v = c(1, 2))
                          })
  on.exit(rm("kc_clean", envir = countryatlas:::the_sources), add = TRUE)
  base <- data.frame(iso3c = c("FRA", "JPN"), year = 2020L, gdp = c(5, 6))
  expect_silent(out <- add_indicator(base, "kc_clean", "v"))
  expect_identical(names(out), c("iso3c", "year", "gdp", "v"))
  expect_identical(nrow(out), 2L)
})

test_that("re-registering a source drops its memoised answers", {
  # The cache key hashes indicator, countries and years but not `fetch`, so
  # correcting a broken adapter and registering it again kept serving the
  # broken result -- which is exactly what developing an adapter looks like.
  mk <- function(val) function(indicator, countries = NULL, years = NULL) {
    data.frame(iso3c = "FRA", year = 2020L, v = val)
  }
  register_country_source("memo_src", fetch = mk(1))
  on.exit(rm("memo_src", envir = countryatlas:::the_sources), add = TRUE)
  expect_identical(fetch_indicator("memo_src", "v")$v, 1)
  register_country_source("memo_src", fetch = mk(999))
  expect_identical(fetch_indicator("memo_src", "v")$v, 999)

  # Memoisation itself still works: two calls, one fetch.
  calls <- 0L
  register_country_source("memo_count",
                          fetch = function(indicator, countries = NULL,
                                           years = NULL) {
                            calls <<- calls + 1L
                            data.frame(iso3c = "FRA", year = 2020L, v = calls)
                          })
  on.exit(rm("memo_count", envir = countryatlas:::the_sources), add = TRUE)
  invisible(fetch_indicator("memo_count", "v"))
  invisible(fetch_indicator("memo_count", "v"))
  expect_identical(calls, 1L)
  clear_country_cache("memo_count")
  invisible(fetch_indicator("memo_count", "v"))
  expect_identical(calls, 2L)
})

test_that("a cross-section joined to a multi-year fetch keeps its year", {
  # Dropping the fetch's year column is right for a single-year fetch, where
  # it just broadcasts the value. Done unconditionally it turned a two-row
  # cross-section into six rows -- the same `gdp` three times, against values
  # whose year had just been deleted, so nothing said which year any of them
  # was. The keys never collapse here, so the collapse check cannot see it.
  mk <- function(yrs) function(indicator, countries = NULL, years = NULL) {
    data.frame(iso3c = rep(c("USA", "FRA"), each = length(yrs)),
               year = rep(yrs, 2), v = seq_len(2 * length(yrs)))
  }
  register_country_source("fanout_m3", fetch = mk(2018:2020))
  register_country_source("fanout_m1", fetch = mk(2020L))
  on.exit(for (s in c("fanout_m3", "fanout_m1"))
    rm(list = s, envir = countryatlas:::the_sources), add = TRUE)

  xs <- data.frame(iso3c = c("USA", "FRA"), gdp = c(10, 20))
  w <- tryCatch(add_indicator(xs, "fanout_m3", "v"), warning = identity)
  expect_s3_class(w, "countryatlas_year_fanout")
  out <- suppressWarnings(add_indicator(xs, "fanout_m3", "v"))
  expect_true("year" %in% names(out))
  expect_identical(nrow(out), 6L)
  expect_setequal(unique(out$year), 2018:2020)

  # One year still broadcasts silently, dropping the column as before.
  expect_silent(one <- add_indicator(xs, "fanout_m1", "v"))
  expect_false("year" %in% names(one))
  expect_identical(nrow(one), 2L)

  # A panel joins on iso3c and year, untouched either way.
  pnl <- data.frame(iso3c = rep(c("USA", "FRA"), each = 3),
                    year = rep(2018:2020, 2), gdp = 1:6)
  expect_silent(p3 <- add_indicator(pnl, "fanout_m3", "v"))
  expect_identical(nrow(p3), 6L)
  expect_silent(p1 <- add_indicator(pnl, "fanout_m1", "v"))
  expect_identical(nrow(p1), 6L)
})

test_that("compare_sources drops an unparseable year instead of inventing a row", {
  # read_year() deliberately puts NA in the year column for a time value it
  # could not parse, and d[NA, ] appends a row of all-NA -- a phantom country
  # with no iso3c that then survived the join into the comparison table.
  register_country_source("cs_na_a", fetch = function(indicator,
                                                      countries = NULL,
                                                      years = NULL) {
    data.frame(iso3c = c("USA", "FRA", "JPN"),
               year = c("2020", "2020", "bogus"), cs_na_a = c(10, 20, 30))
  })
  register_country_source("cs_na_b", fetch = function(indicator,
                                                      countries = NULL,
                                                      years = NULL) {
    data.frame(iso3c = c("USA", "FRA"), year = c("2020", "2020"),
               cs_na_b = c(11, 19))
  })
  on.exit(for (s in c("cs_na_a", "cs_na_b"))
    rm(list = s, envir = countryatlas:::the_sources), add = TRUE)

  out <- suppressWarnings(compare_sources(
    c(cs_na_a = "x", cs_na_b = "x"),
    sources = c("cs_na_a", "cs_na_b"), year = 2020))
  expect_identical(sum(is.na(out$iso3c)), 0L)
  expect_setequal(out$iso3c, c("USA", "FRA"))
})

test_that("compare_sources() leaves unresolved keys out of the comparison", {
  skip_slow_on_cran()
  register_country_source("rev_a", function(indicator, countries, years, ...) {
    data.frame(iso3c = c("USA", "FRA", "XXA", "XXB"), year = 2020L,
               v = c(1, 2, 3, 4))
  }, cache = FALSE)
  register_country_source("rev_b", function(indicator, countries, years, ...) {
    data.frame(iso3c = c("USA", "FRA", "XXC"), year = 2020L, v = c(1, 2.5, 9))
  }, cache = FALSE)
  withr::defer(remove_country_source(c("rev_a", "rev_b")))
  msgs <- character(0)
  r <- withCallingHandlers(
    compare_sources("v", sources = c("rev_a", "rev_b"), year = 2020),
    warning = function(w) {
      msgs <<- c(msgs, conditionMessage(w))
      invokeRestart("muffleWarning")
    })
  expect_false(anyNA(r$iso3c))
  expect_setequal(r$iso3c, c("USA", "FRA"))
  s <- attr(r, "countryatlas_source_summary")
  expect_equal(c(s$only_x, s$only_y), c(0L, 0L))
  # Two unresolved rows are not "a duplicate country".
  expect_false(any(grepl("duplicate", msgs)))
})

test_that("compare_sources() refuses a source named twice", {
  expect_error(compare_sources("x", sources = c("wdi", "wdi"), year = 2020),
               "distinct")
})

test_that("compare_sources() survives a year no source covers, and an infinity", {
  register_country_source("pol_a", function(indicator, countries, years, ...) {
    data.frame(iso3c = c("USA", "FRA", "DEU"), year = 2019L, v = c(Inf, 2, 3))
  }, cache = FALSE)
  register_country_source("pol_b", function(indicator, countries, years, ...) {
    data.frame(iso3c = c("USA", "FRA", "DEU"), year = 2019L, v = c(1, 2, 3))
  }, cache = FALSE)
  withr::defer(remove_country_source(c("pol_a", "pol_b")))
  # No row for 2020 anywhere: base R's "subscript out of bounds".
  expect_warning(
    empty <- compare_sources("v", sources = c("pol_a", "pol_b"), year = 2020),
    class = "countryatlas_no_data")
  expect_equal(nrow(empty), 0L)
  expect_named(empty, c("iso3c", "pol_a", "pol_b", "n_sources", "rel_diff",
                        "disagrees"))
  # The infinity made rel_diff NaN, which `disagrees` read as agreement.
  expect_warning(
    r <- compare_sources("v", sources = c("pol_a", "pol_b"), year = 2019),
    class = "countryatlas_infinite_value")
  usa <- r[r$iso3c == "USA", ]
  expect_equal(usa$pol_a, Inf)
  expect_equal(usa$n_sources, 1)
  expect_true(is.na(usa$rel_diff))
  expect_false(usa$disagrees)
  expect_equal(attr(r, "countryatlas_source_summary")$n_both, 2L)
})

test_that("remove_country_source undoes a registration", {
  skip_slow_on_cran()
  # Registering was permanent for the session, so anything that registered a
  # source -- an example, a test, a scratch script -- left country_sources()
  # reporting different rows for the rest of the session, with no way back.
  before <- country_sources()$source
  register_country_source("t_removable", function(indicator, ...) NULL)
  expect_true("t_removable" %in% country_sources()$source)
  expect_identical(remove_country_source("t_removable"), "t_removable")
  expect_false("t_removable" %in% country_sources()$source)
  expect_setequal(country_sources()$source, before)

  # A name that was never registered is reported, not silently ignored.
  expect_warning(remove_country_source("t_never_registered"),
                 "No registered source")

  # The built-ins are what ?fetch_indicator documents, so they stay.
  for (b in c("wdi", "owid", "eurostat", "oecd", "comtrade", "imf", "ilo")) {
    expect_error(remove_country_source(b), "built-in")
  }
  expect_true(all(c("wdi", "owid", "eurostat", "oecd", "comtrade", "imf",
                    "ilo") %in% country_sources()$source))

  # And a bad argument is named rather than reaching exists().
  expect_error(remove_country_source(42), "must be one or more source names")
  expect_error(remove_country_source(character(0)),
               "must be one or more source names")

  # Removing drops the memoised answers too: re-registering the same name must
  # not serve results from the fetch function that was just removed.
  calls <- 0L
  register_country_source("t_memo", function(indicator, countries = NULL,
                                             years = NULL, ...) {
    calls <<- calls + 1L
    tibble::tibble(iso3c = "FRA", year = 2020L, v = 1)
  })
  invisible(fetch_indicator("t_memo", c(v = "v"), years = 2020))
  invisible(fetch_indicator("t_memo", c(v = "v"), years = 2020))
  expect_equal(calls, 1L)                      # memoised
  remove_country_source("t_memo")
  register_country_source("t_memo", function(indicator, countries = NULL,
                                             years = NULL, ...) {
    calls <<- calls + 1L
    tibble::tibble(iso3c = "FRA", year = 2020L, v = 2)
  })
  out <- fetch_indicator("t_memo", c(v = "v"), years = 2020)
  expect_equal(calls, 2L)                      # the new function ran
  expect_equal(out$v, 2)
  remove_country_source("t_memo")
})

test_that("fetch_owid() reads the Chart API, keyed on OWID's ISO codes", {
  # owidR 1.4.2 returns nothing for any slug since OWID changed its API, so
  # the 3.0.0 adapter reported every chart as unreachable.
  seen <- local_fixture_http(list(
    "life-expectancy.csv" = "owid-life-expectancy.csv",
    "life-expectancy.metadata.json" = "owid-life-expectancy.metadata.json"))
  x <- fetch_owid(c(le = "life-expectancy"), years = 2019:2020)
  expect_identical(names(x), c("iso3c", "year", "le"))
  # Kosovo is OWID_KOS; every other OWID_ code, and a region with no code at
  # all, is an aggregate and is dropped.
  expect_true("XKX" %in% x$iso3c)
  expect_false(any(is.na(x$iso3c)))
  expect_false(any(grepl("OWID", x$iso3c)))
  expect_setequal(unique(x$year), 2019:2020)
  info <- source_info(x)
  expect_identical(info$source, "owid")
  expect_identical(info$unit, "years")
  expect_identical(info$label, "Life expectancy")
  expect_match(info$citation, "Our World in Data", fixed = TRUE)
  expect_match(seen$urls[1], "csvType=full&useColumnShortNames=true",
               fixed = TRUE)
  # One column of a chart by name; an unknown one is refused by name.
  one <- fetch_owid("life-expectancy/life_expectancy_0", years = 2020)
  expect_identical(names(one)[3], "life-expectancy/life_expectancy_0")
  expect_error(fetch_owid("life-expectancy/nope"), "life_expectancy_0")
  expect_error(fetch_owid("Not A Slug"), "slug")
  expect_warning(fetch_owid("life-expectancy", years = 2020, extra = 1),
                 class = "countryatlas_dots_unused")
})

test_that("an unreachable OWID degrades, and a missing chart is named", {
  testthat::local_mocked_bindings(
    wdj_http_get = function(url, ...) {
      rlang::abort("HTTP status 404", status = 404L,
                   class = c("countryatlas_fetch_failed", "countryatlas_error"))
    }, .package = "countryatlas")
  expect_error(fetch_owid("no-such-chart"), "has no chart")
  testthat::local_mocked_bindings(
    wdj_http_get = function(url, ...) {
      rlang::abort("timeout", status = NA_integer_,
                   class = c("countryatlas_fetch_failed", "countryatlas_error"))
    }, .package = "countryatlas")
  expect_warning(z <- fetch_owid("life-expectancy"),
                 class = "countryatlas_fetch_failed")
  expect_identical(nrow(z), 0L)
})

test_that("compare_sources() refuses to compare different units", {
  mk <- function(unit) {
    function(indicator, countries = NULL, years = NULL) {
      d <- data.frame(iso3c = c("FRA", "DEU"), year = 2020L,
                      v = c(1, 2))
      names(d)[3] <- names(indicator) %||% indicator
      source_info(d) <- data.frame(column = names(d)[3], unit = unit)
      d
    }
  }
  register_country_source("u_a", mk("constant 2015 US$"))
  register_country_source("u_b", mk("current international $"))
  register_country_source("u_c", mk("constant 2015 US$"))
  withr::defer(remove_country_source(c("u_a", "u_b", "u_c")))
  expect_error(compare_sources("x", sources = c("u_a", "u_b"), year = 2020),
               class = "countryatlas_unit_mismatch")
  ok <- compare_sources("x", sources = c("u_a", "u_b"), year = 2020,
                        allow_unit_mismatch = TRUE)
  s <- attr(ok, "countryatlas_source_summary")
  expect_identical(c(s$unit_x, s$unit_y),
                   c("constant 2015 US$", "current international $"))
  expect_silent(compare_sources("x", sources = c("u_a", "u_c"), year = 2020))
})

test_that("the built-in adapters persist to disk, per source, and clear per source", {
  d <- file.path(tempdir(), paste0("cc-src-", as.integer(stats::runif(1, 1, 1e6))))
  withr::local_options(countryatlas.cache_dir = d)
  withr::defer(unlink(d, recursive = TRUE))
  clear_country_cache("owid")
  seen <- local_fixture_http(list(
    "life-expectancy.csv" = "owid-life-expectancy.csv",
    "life-expectancy.metadata.json" = "owid-life-expectancy.metadata.json"))
  a <- fetch_indicator("owid", "life-expectancy", years = 2020)
  n1 <- length(seen$urls)
  expect_true(dir.exists(file.path(d, "owid")))
  # A new session (no memo) reads the disk, not the network.
  clear_country_cache("owid")             # memo only
  b <- fetch_indicator("owid", "life-expectancy", years = 2020)
  expect_identical(length(seen$urls), n1)
  expect_equal(b, a)
  expect_identical(source_info(b)$source, "owid")
  bystander <- file.path(d, "owid", "mine.txt")
  writeLines("keep", bystander)
  clear_country_cache("owid", disk = TRUE)
  expect_true(file.exists(bystander))
  expect_length(setdiff(list.files(file.path(d, "owid")), "mine.txt"), 0L)
  c2 <- fetch_indicator("owid", "life-expectancy", years = 2020)
  expect_gt(length(seen$urls), n1)
})

test_that("compare_sources() reads the unit a registered fetcher states", {
  # The record was looked up under the source's name, and a registered
  # fetcher states it under its own column name, so two sources in different
  # units were compared without a word.
  mk <- function(v, unit) {
    force(v); force(unit)
    function(indicator, countries = NULL, years = NULL) {
      out <- data.frame(iso3c = c("FRA", "DEU"), year = 2020L, lfp = v)
      source_info(out) <- data.frame(column = "lfp", unit = unit)
      out
    }
  }
  register_country_source("unit_a", mk(c(61, 62), "percent"))
  register_country_source("unit_b", mk(c(0.61, 0.62), "share"))
  withr::defer(remove_country_source(c("unit_a", "unit_b")))
  expect_error(compare_sources("lfp", sources = c("unit_a", "unit_b"), year = 2020),
               class = "countryatlas_unit_mismatch")
  ok <- compare_sources("lfp", sources = c("unit_a", "unit_b"), year = 2020,
                        allow_unit_mismatch = TRUE)
  expect_identical(nrow(ok), 2L)
})
