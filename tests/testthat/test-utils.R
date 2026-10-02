test_that("check_choice accepts the documented default and rejects the rest", {
  skip_slow_on_cran()
  ch <- c("a", "b", "c")
  # A caller that passed nothing hands the whole default vector through, exactly
  # as match.arg() would, and must get the first element.
  expect_equal(countryatlas:::check_choice(ch, "x", ch), "a")
  expect_equal(countryatlas:::check_choice("b", "x", ch), "b")
  expect_error(countryatlas:::check_choice("z", "x", ch), "`x` must be one of")
  expect_error(countryatlas:::check_choice(c("a", "b"), "x", ch), "Got 2 values")
  expect_error(countryatlas:::check_choice(42, "x", ch), "`x` must be one of")
  expect_error(countryatlas:::check_choice(NULL, "x", ch), "`x` must be one of")
  # The defaults every caller relies on still resolve.
  expect_match(countryatlas:::wdj_crs(), "+proj=eqearth", fixed = TRUE)
  expect_identical(countryatlas:::ne_scale(), 110L)
})

test_that("wdj_workers honours the contract it documents", {
  skip_slow_on_cran()
  w <- countryatlas:::wdj_workers
  # Every branch guarantees at least one worker, then min(workers, n_tasks)
  # undid it for zero tasks -- returning 0, which is exactly what `mc.cores`
  # refuses. wdj_lapply() short-circuits an empty input before it gets here, so
  # nothing hit it; the contract should not depend on the only caller
  # remembering to guard.
  expect_true(all(vapply(0:20, function(i) w(i) >= 1L, logical(1))))
  expect_true(all(vapply(1:20, function(i) w(i) <= i, logical(1))))
  old <- getOption("countryatlas.workers")
  withr::defer(options(countryatlas.workers = old))
  options(countryatlas.workers = 1)
  expect_equal(w(100), 1L)
})

test_that("wdj_lapply agrees with lapply and preserves order", {
  skip_slow_on_cran()
  f <- function(i) i^2
  expect_identical(countryatlas:::wdj_lapply(1:6, f, parallel = TRUE),
                   countryatlas:::wdj_lapply(1:6, f, parallel = FALSE))
  expect_identical(unlist(countryatlas:::wdj_lapply(1:6, f, parallel = TRUE)),
                   (1:6)^2)
  expect_identical(countryatlas:::wdj_lapply(integer(0), f), list())
})

test_that("every override maps to a code the package recognises", {
  ov <- country_overrides()
  expect_true(all(unname(ov) %in% countryatlas:::wdj_known_iso3c()))
  # And the overrides reach every entry point, not just one.
  probe <- names(ov)[1:6]
  expect_false(anyNA(standardize_country(data.frame(country = probe),
                                         country)$iso3c))
  expect_false(anyNA(convert_country(probe, to = "iso3c")))
  expect_identical(standardize_country(data.frame(country = probe), country)$iso3c,
                   unname(convert_country(probe, to = "iso3c")))
})

test_that("the COW/GW key warning agrees with its own count", {
  skip_slow_on_cran()
  # `where` sat between the count and `ha{?s/ve}`, so cli keyed the agreement
  # to a length-1 string and every plural read "5 countries ... has".
  msg <- function(n, side) {
    iso <- c("HKG", "PRI", "MAC", "GRL", "ABW")[seq_len(n)]
    w <- tryCatch(
      countryatlas:::wdj_to_key(iso, origin = "iso3c", key = "cowc",
                                side = side),
      warning = function(x) {
        cli::ansi_strip(paste(conditionMessage(x), collapse = " "))
      })
    gsub("[[:space:]]+", " ", w)
  }
  expect_match(msg(1, NULL), "1 country resolved", fixed = TRUE)
  expect_match(msg(1, NULL), "has no cowc code", fixed = TRUE)
  expect_match(msg(3, NULL), "3 countries resolved", fixed = TRUE)
  expect_match(msg(3, NULL), "have no cowc code", fixed = TRUE)
  # `side` still distinguishes the two halves of a two-sided join, inline --
  # the wording another test pins.
  expect_match(msg(3, "`x`"), "in `x`", fixed = TRUE)
  expect_match(msg(3, "`x`"), "have no cowc code", fixed = TRUE)
  expect_false(grepl("in `x`", msg(3, NULL), fixed = TRUE))
})

test_that("a brace in borrowed text does not replace the message", {
  skip_slow_on_cran()
  # A cli bullet is a template, so text borrowed from somewhere else -- a
  # worker's error, a cache read failure, countrycode's own complaint -- had
  # its braces interpolated. A FUN failing with `bad json {"a": 1}` reported
  # "Could not evaluate cli `{}` expression" and the real failure was gone,
  # which is the worst possible time to lose it.
  # suppressWarnings() around the call, not the assertion: mclapply() emits its
  # own "2 function calls resulted in an error" alongside, which is not what
  # this test is about and would otherwise show up as an uncaught warning.
  err <- tryCatch(
    suppressWarnings(wdj_lapply(1:2, function(i) stop('bad json {"a": 1}'))),
    error = identity)
  expect_match(cli::ansi_strip(conditionMessage(err)), 'bad json {"a": 1}',
               fixed = TRUE)
  expect_false(grepl("Could not evaluate cli",
                     cli::ansi_strip(conditionMessage(err))))

  # Same for the origin error's fallback, used when countrycode's message
  # cannot be parsed for the scheme list.
  e2 <- tryCatch(
    abort_bad_origin("zz", simpleError("weird {brace} message"),
                     rlang::current_env()),
    error = identity)
  expect_match(cli::ansi_strip(conditionMessage(e2)), "weird {brace} message",
               fixed = TRUE)
})

test_that("wdj_known_iso3c is the single source of truth for country codes", {
  known <- countryatlas:::wdj_known_iso3c()
  expect_true("XKX" %in% known)          # Kosovo has no codelist row
  expect_true(all(c("USA", "FRA", "JPN") %in% known))
  expect_false(anyNA(known))
  expect_equal(anyDuplicated(known), 0L)
  # The name matcher and region resolution must agree with it.
  expect_false(anyNA(countryatlas:::wdj_to_iso3c(known, origin = "iso3c")))
  expect_true(is.na(countryatlas:::wdj_to_iso3c("ZZZ", origin = "iso3c")))
})

test_that("quietly_sf swallows console output but returns the value", {
  # Most sf/s2 diagnostics are ordinary message() conditions; a few GDAL/GEOS
  # ones are written straight to stderr from C. quietly_sf() has to stop both,
  # so it muffles the conditions *and* redirects the stream.
  skip_if(sink.number(type = "message") != 2L,
          "a message sink is already active")
  f <- tempfile()
  con <- file(f, "w")
  sink(con, type = "message")
  got <- tryCatch(countryatlas:::quietly_sf({ message("noise"); 42 }),
                  finally = { sink(type = "message"); close(con) })
  expect_equal(got, 42)
  expect_length(readLines(f, warn = FALSE), 0L)

  # The condition must not escape to the caller's handlers either.
  seen <- 0L
  withCallingHandlers(
    expect_equal(countryatlas:::quietly_sf({ message("noise"); 7 }), 7),
    message = function(m) {
      seen <<- seen + 1L
      invokeRestart("muffleMessage")
    }
  )
  expect_identical(seen, 0L)
})

# Numbers that cross into a machine-readable string must not depend on the
# user's formatting options. options(OutDec = ",") is ordinary in comma-decimal
# locales and turned every PROJ string into "+lat_0=12,5", which PROJ rejects --
# surfacing as sf's opaque "crs not found: is it missing?", i.e. no projected
# map at all. options(scipen = -9) rendered EPSG 4326 as "4.326e+03" (an NA
# CRS, later "st_crs(x) == st_crs(y) is not TRUE") and Natural Earth's scale 110
# as "1.1e+02" ("'countries1.1e+02' is not an exported object").

test_that("fmt_num ignores OutDec and scipen", {
  f <- countryatlas:::fmt_num
  vals <- c(0, 20, -90, 48.9, 100, 12.5, -0.5, 359.9)
  want <- f(vals)
  old <- options(OutDec = ",", scipen = -9)
  on.exit(options(old), add = TRUE)
  expect_identical(f(vals), want)
  expect_false(any(grepl(",", want, fixed = TRUE)))
  expect_false(any(grepl("e", want, fixed = TRUE)))
})

test_that("with_c_numbers restores the caller's options", {
  old <- suppressWarnings(options(OutDec = ",", scipen = -9))
  on.exit(options(old), add = TRUE)
  stored_scipen <- getOption("scipen")
  seen <- countryatlas:::with_c_numbers(
    c(dec = getOption("OutDec"), sci = as.character(getOption("scipen"))))
  expect_equal(unname(seen[["dec"]]), ".")      # normalised inside
  expect_equal(unname(seen[["sci"]]), "0")
  expect_equal(getOption("OutDec"), ",")        # and put back after
  # Compare against what R actually stored, not the literal passed in: R >= 4.6
  # clamps scipen to -9 and warns, so a hard-coded expectation fails there while
  # the restore itself is faithful.
  expect_equal(getOption("scipen"), stored_scipen)
  # Restored even when the wrapped call fails.
  expect_error(countryatlas:::with_c_numbers(stop("boom")), "boom")
  expect_equal(getOption("OutDec"), ",")
})

test_that("options(countryatlas.workers) is validated", {
  skip_slow_on_cran()
  # A bad value used to reach mclapply(mc.cores = NA) and surface as "missing
  # value where TRUE/FALSE needed" from deep inside the fetch.
  # Base R option save/restore rather than the withr helper: withr is not a
  # declared dependency, and a namespaced call to it from a test trips R CMD
  # check's "'::' import not declared" warning even though testthat pulls it in.
  with_workers <- function(value, code) {
    old <- options(countryatlas.workers = value)
    on.exit(options(old), add = TRUE)
    force(code)
  }
  for (bad in list("many", NA, c(1, 2), Inf)) {
    with_workers(bad, expect_error(countryatlas:::wdj_workers(8),
                                   "single finite number",
                                   info = paste(deparse(bad), collapse = "")))
  }
  # Valid values, including a numeric string, which has always been accepted.
  for (v in list(1, 4, "2")) {
    with_workers(v, expect_identical(countryatlas:::wdj_workers(8), as.integer(v)))
  }
  # Below one is clamped rather than rejected -- the documented contract.
  with_workers(0, expect_identical(countryatlas:::wdj_workers(8), 1L))
  with_workers(-2, expect_identical(countryatlas:::wdj_workers(8), 1L))
  # n_tasks still caps the result.
  with_workers(8, expect_identical(countryatlas:::wdj_workers(3), 3L))
  # And the option is restored afterwards.
  expect_null(getOption("countryatlas.workers"))
})

test_that("a character year is refused before a year-keyed join", {
  skip_slow_on_cran()
  fake <- function(indicator, start, end, cache = TRUE, language = "en",
                   parallel = TRUE) {
    x <- tibble::tibble(iso2c = c("US", "CN"), iso3c = c("USA", "CHN"),
                        country = c("US", "CN"), year = 2020L)
    x[[names(indicator)]] <- c(331e6, 1402e6)
    x
  }
  local_mocked_bindings(fetch_wdi = fake, .package = "countryatlas")
  d <- data.frame(iso3c = c("USA", "CHN"), year = c("2020", "2020"),
                  co2 = c(5e6, 1e7))
  # The join's own error was dplyr's "Can't join `x$year` with `y$year`".
  expect_error(per_capita(d, co2), "must be numeric",
               class = "countryatlas_error")
  expect_error(to_ppp(d, co2), "must be numeric", class = "countryatlas_error")
  # A factor of the caller's own needs no join and still takes such a year.
  d$ppp <- c(1, 4)
  expect_equal(to_ppp(d, co2, factor = ppp)$co2_ppp, c(5e6, 2.5e6))
  register_country_source("rev_year", function(indicator, countries, years, ...) {
    data.frame(iso3c = c("USA", "CHN"), year = 2020L, zz = c(1, 2))
  }, cache = FALSE)
  withr::defer(remove_country_source("rev_year"))
  expect_error(add_indicator(d, "rev_year", "zz"), "must be numeric",
               class = "countryatlas_error")
  d$year <- 2020L
  expect_equal(add_indicator(d, "rev_year", "zz")$zz, c(1, 2))
})

test_that("an error raised inside a verb's own handler names the verb", {
  skip_slow_on_cran()
  snap <- countryatlas::world_snapshot$countries
  # Raised from a tryCatch() handler or an lapply() function written inline in
  # the verb, these were headed "Error in `value[[3L]]()`" or "Error in `FUN()`".
  header <- function(expr) {
    e <- tryCatch(expr, error = identity)
    expect_s3_class(e, "countryatlas_error")
    as.character(conditionCall(e)[[1]])
  }
  expect_equal(header(complete_years(snap, value = gdp_per_capita)),
               "complete_years")
  expect_equal(header(audit_coverage(snap, gdp_per_capita)), "audit_coverage")
  expect_equal(header(country_join_all(list(snap, snap), by = "nope")),
               "country_join_all")
  expect_equal(header(correlate_indicators(snap, nope, gdp_per_capita)),
               "correlate_indicators")
  expect_equal(header(geom_country_labels(data = snap)), "geom_country_labels")
  register_country_source("polish_down", function(indicator, countries, years, ...) {
    stop("provider is down")
  }, cache = FALSE)
  withr::defer(remove_country_source("polish_down"))
  expect_equal(header(fetch_indicator("polish_down", "x")), "fetch_indicator")
})

test_that("an error raised by an internal helper names the verb called", {
  skip_slow_on_cran()
  snap <- countryatlas::world_snapshot$countries
  header <- function(expr) {
    e <- tryCatch(expr, error = identity)
    expect_s3_class(e, "countryatlas_error")
    as.character(conditionCall(e)[[1]])
  }
  # Each was headed with the helper's own name: weights_custom(),
  # weights_knn(), wdj_to_iso3c(), build_overrides(), get_world_sf(),
  # resolve_footnote(), compute_breaks().
  expect_equal(header(country_weights(type = "custom")), "country_weights")
  expect_equal(header(country_weights(type = "knn", k = 0)), "country_weights")
  expect_equal(header(neighbors("France", origin = c("a", "b"))), "neighbors")
  expect_equal(header(convert_country("France", custom_match = 1)),
               "convert_country")
  expect_equal(header(country_overrides(1)), "country_overrides")
  x <- data.frame(country = "France", a = 1)
  expect_equal(header(country_join(x, x, country, country, origin_x = 1)),
               "country_join")
  # ...and the argument the caller wrote, not the helper's own `origin`.
  expect_error(country_join(x, x, country, country, origin_y = 1), "origin_y")
  # The polygon backend needs `maps`, which refuses before `region` is read.
  expect_equal(header(world_geometry(region = NA)), "world_geometry")
  poly <- suppressWarnings(attach_geometry(snap))
  expect_equal(header(world_map(poly, gdp_per_capita, footnote = 1)), "world_map")
  expect_equal(header(value_by_alpha_map(poly, gdp_per_capita, population,
                                         n_bins = 1)),
               "value_by_alpha_map")
  skip_if_no_sf_geometry()
  expect_equal(header(country_borders(scale = "huge")), "country_borders")
})

test_that("a bad option is reported without blaming an internal helper", {
  e <- tryCatch(
    withr::with_options(list(countryatlas.cache_max_age = -1),
                        countryatlas:::wdj_disk_cache()),
    error = identity)
  expect_s3_class(e, "countryatlas_bad_option")
  expect_null(conditionCall(e))
})
