# The forking path. fetch_wdi(parallel = TRUE) is the default for a
# multi-indicator request, so wdj_lapply()'s mclapply branch runs on the
# package's busiest code path -- and had no coverage, because every other test
# either used one indicator or passed parallel = FALSE.

test_that("wdj_workers respects the option, the work size and CRAN's cap", {
  wk <- countryatlas:::wdj_workers
  withr_opt <- options(countryatlas.workers = 3)
  expect_equal(wk(100), 3L)
  expect_equal(wk(2), 2L)              # never more workers than tasks
  options(countryatlas.workers = 0)
  expect_gte(wk(10), 1L)               # never below one
  options(withr_opt)

  # CRAN policy: at most two cores under R CMD check.
  old_env <- Sys.getenv("_R_CHECK_LIMIT_CORES_", unset = NA)
  old_opt <- options(countryatlas.workers = NULL)
  on.exit({
    if (is.na(old_env)) Sys.unsetenv("_R_CHECK_LIMIT_CORES_")
    else Sys.setenv("_R_CHECK_LIMIT_CORES_" = old_env)
    options(old_opt)
  }, add = TRUE)
  Sys.setenv("_R_CHECK_LIMIT_CORES_" = "TRUE")
  expect_equal(wk(100), 2L)

  # --as-cran sets the variable to "TRUE" only when it is not already set, so
  # the value that arrives is whatever the check flavour exported. R's own
  # parser reads all of these as true; matching the literal "TRUE" let them
  # through and the fetch forked detectCores() - 1 workers during a check.
  for (v in c("true", "True", "T", "1", "yes", "YES")) {
    Sys.setenv("_R_CHECK_LIMIT_CORES_" = v)
    expect_equal(wk(100), 2L, info = v)
  }
  # "warn" asks R to report core use rather than cap it; limiting is still the
  # safe reading, and it is what keeps the check quiet.
  Sys.setenv("_R_CHECK_LIMIT_CORES_" = "warn")
  expect_equal(wk(100), 2L)

  # An explicit false is a deliberate opt-out and must be honoured.
  for (v in c("false", "FALSE", "F", "0", "no")) {
    Sys.setenv("_R_CHECK_LIMIT_CORES_" = v)
    expect_gt(wk(100), 0L)
    expect_false(countryatlas:::check_limits_cores(), info = v)
  }
})

test_that("wdj_lapply gives the same answer forked as serial", {
  wl <- countryatlas:::wdj_lapply
  expect_identical(wl(1:6, function(i) i^2, parallel = TRUE),
                   wl(1:6, function(i) i^2, parallel = FALSE))
  # Forking must not reorder results.
  expect_identical(unlist(wl(1:8, function(i) i, parallel = TRUE)), 1:8)
  # `...` reaches the workers.
  expect_identical(unlist(wl(1:3, function(i, k) i * k, k = 10, parallel = TRUE)),
                   c(10, 20, 30))
  expect_identical(wl(list(), identity), list())
  # One task, or one worker, takes the serial path.
  expect_identical(wl(1, function(i) i * 2, parallel = TRUE), list(2))
  expect_identical(wl(1:4, function(i) i, parallel = TRUE, workers = 1),
                   as.list(1:4))
})

test_that("an error inside a fork is surfaced, not swallowed", {
  # mclapply returns a try-error object per failed element rather than raising,
  # so without the check the failure would pass silently downstream.
  wl <- countryatlas:::wdj_lapply
  err <- tryCatch(
    suppressWarnings(wl(1:4, function(i) if (i == 3) stop("boom-3") else i,
                        parallel = TRUE)),
    error = function(e) e
  )
  expect_s3_class(err, "countryatlas_error")
  expect_match(conditionMessage(err), "Parallel computation failed", fixed = TRUE)
  expect_match(conditionMessage(err), "boom-3", fixed = TRUE)
})

test_that("a parallel multi-indicator fetch matches the serial one", {
  fake_wdi <- function(indicator, start, end, extra = FALSE, language = "en", ...) {
    nm <- names(indicator)[1]
    yrs <- start:end
    d <- expand.grid(iso2c = c("US", "CN", "FR"), year = yrs,
                     stringsAsFactors = FALSE)
    d$country <- c(US = "United States", CN = "China", FR = "France")[d$iso2c]
    d[[nm]] <- c(US = 100, CN = 50, FR = 70)[d$iso2c] * (d$year - min(yrs) + 1)
    d
  }
  testthat::local_mocked_bindings(WDI = fake_wdi, .package = "WDI")
  args <- list(c(gdp = "A", pop = "B", co2 = "C"), start = 2018, end = 2020,
               cache = FALSE)
  par <- do.call(countryatlas:::fetch_wdi, c(args, list(parallel = TRUE)))
  ser <- do.call(countryatlas:::fetch_wdi, c(args, list(parallel = FALSE)))
  expect_identical(par, ser)
  expect_true(all(c("gdp", "pop", "co2") %in% names(par)))
})

test_that("a failing indicator inside a fork loses only that indicator", {
  fake_wdi <- function(indicator, start, end, ...) {
    nm <- names(indicator)[1]
    if (nm == "pop") stop("fork-boom")
    d <- data.frame(iso2c = c("US", "FR"), country = c("United States", "France"),
                    year = c(2020L, 2020L))
    d[[nm]] <- c(1, 2)
    d
  }
  testthat::local_mocked_bindings(WDI = fake_wdi, .package = "WDI")
  out <- suppressWarnings(
    countryatlas:::fetch_wdi(c(gdp = "A", pop = "B", co2 = "C"),
                             start = 2020, end = 2020, cache = FALSE,
                             parallel = TRUE)
  )
  expect_true(all(c("gdp", "co2") %in% names(out)))
  expect_false("pop" %in% names(out))
})

# options(countryatlas.workers) is advertised in NEWS, so a bad value is
# reachable -- and it used to reach mclapply(mc.cores = NA). "abc", NA and Inf
# all became NA workers and surfaced as "missing value where TRUE/FALSE needed"
# from deep inside the fetch; c(2, 4) silently took the larger of the two.

test_that("the workers option accepts what it always accepted", {
  for (v in list(4, 1L, "2", 2.7, 8L)) {
    old <- options(countryatlas.workers = v)
    w <- countryatlas:::wdj_workers(10)
    options(old)
    expect_type(w, "integer")
    expect_length(w, 1L)
    expect_gte(w, 1L)
  }
  # A fractional value truncates, as it did before.
  old <- options(countryatlas.workers = 2.7)
  expect_equal(countryatlas:::wdj_workers(10), 2L)
  options(old)
  # A string naming a number still works.
  old <- options(countryatlas.workers = "3")
  expect_equal(countryatlas:::wdj_workers(10), 3L)
  options(old)
  # And a number below one is clamped, as the existing contract requires.
  for (v in c(0, -3)) {
    old <- options(countryatlas.workers = v)
    expect_equal(countryatlas:::wdj_workers(10), 1L)
    options(old)
  }
})

test_that("a bad workers option names the option instead of failing later", {
  # 0 and -3 are deliberately NOT here: they were always clamped to one, which
  # is the documented contract, and they never produced the NA that broke
  # mclapply. Only values that cannot yield a count at all are rejected.
  for (v in list("abc", NA, NA_integer_, Inf, -Inf, c(2, 4),
                 character(0), numeric(0))) {
    old <- options(countryatlas.workers = v)
    expect_error(suppressWarnings(countryatlas:::wdj_workers(10)),
                 "countryatlas.workers")
    expect_error(suppressWarnings(countryatlas:::wdj_workers(10)),
                 class = "countryatlas_error")
    # And the parallel helper surfaces it rather than dying in mclapply.
    expect_error(suppressWarnings(
      countryatlas:::wdj_lapply(1:3, function(i) i * 2)), "countryatlas.workers")
    options(old)
  }
})

test_that("unset, the worker count is still derived safely", {
  old <- options(countryatlas.workers = NULL)
  on.exit(options(old), add = TRUE)
  w <- countryatlas:::wdj_workers(10)
  expect_type(w, "integer")
  expect_gte(w, 1L)
  expect_lte(w, 10L)                       # never more than the work
  expect_equal(countryatlas:::wdj_workers(1), 1L)
  # detectCores() may return NA; that path must still yield a usable count.
  # _R_CHECK_LIMIT_CORES_ is set during R CMD check and short-circuits to two
  # cores before detectCores() is consulted, so clear it for this one check --
  # otherwise the test passes locally and fails under check.
  old_env <- Sys.getenv("_R_CHECK_LIMIT_CORES_", unset = NA)
  Sys.unsetenv("_R_CHECK_LIMIT_CORES_")
  on.exit(if (!is.na(old_env)) Sys.setenv("_R_CHECK_LIMIT_CORES_" = old_env),
          add = TRUE)
  local_mocked_bindings(detectCores = function(...) NA_integer_,
                        .package = "parallel")
  expect_equal(countryatlas:::wdj_workers(10), 1L)
})
