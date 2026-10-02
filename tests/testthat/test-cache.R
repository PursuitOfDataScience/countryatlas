test_that("clear_country_cache(disk = FALSE) does not touch the disk", {
  # memoise's cache_filesystem()$reset() is literally
  # file.remove(list.files(dir, full.names = TRUE)), so forget() on a
  # disk-backed memo was never an in-memory operation: the call the examples
  # label "forget the in-session memo" deleted the persistent cache and every
  # unrelated file sharing that directory. Dropping the memo reference is what
  # "in-session" means; the next call rebuilds it and reads the disk back.
  d <- file.path(tempdir(), paste0("cc-", as.integer(runif(1, 1, 1e6))))
  dir.create(d, showWarnings = FALSE)
  withr::defer(unlink(d, recursive = TRUE))
  withr::local_options(countryatlas.cache_dir = d)

  hits <- 0L
  orig <- countryatlas:::fetch_one_indicator
  stub <- function(code, name, start, end, language = "en") {
    hits <<- hits + 1L
    x <- tibble::tibble(iso2c = "US", iso3c = "USA", country = "US",
                        year = 2000L)
    x[[name]] <- 1
    x
  }
  assignInNamespace("fetch_one_indicator", stub, "countryatlas")
  withr::defer(assignInNamespace("fetch_one_indicator", orig, "countryatlas"))

  invisible(countryatlas:::fetch_wdi(c(x = "I1"), 2000, 2000, parallel = FALSE))
  skip_if(hits == 0L, "disk cache unavailable in this environment")
  bystander <- file.path(d, "unrelated-user-file.txt")
  writeLines("keepme", bystander)
  n_before <- length(list.files(d))

  clear_country_cache("wdi", disk = FALSE)
  expect_true(file.exists(bystander))          # the caller's own file
  expect_equal(length(list.files(d)), n_before)
  # And the entries really are still usable: no second provider call.
  invisible(countryatlas:::fetch_wdi(c(x = "I1"), 2000, 2000, parallel = FALSE))
  expect_equal(hits, 1L)

  # disk = TRUE removes the cache, which is what that argument is for: the
  # cache's own entries, not the caller's file beside them. This used to be
  # unlink(d, recursive = TRUE), and this test asserted the folder was gone,
  # bystander and all.
  clear_country_cache("wdi", disk = TRUE)
  expect_true(file.exists(bystander))
  expect_equal(list.files(d), basename(bystander))
  # Once nothing else is in it, the folder goes too.
  unlink(bystander)
  invisible(countryatlas:::fetch_wdi(c(x = "I1"), 2000, 2000, parallel = FALSE))
  clear_country_cache("wdi", disk = TRUE)
  expect_false(dir.exists(d))
})

test_that("a changed World Bank response shape is named, not called a failure", {
  skip_slow_on_cran()
  # countrycode() is handed raw$iso2c directly, so a response with neither key
  # raised its own "sourcevar must be a character or numeric vector", which the
  # fetch wrapper relabelled "Could not fetch ... from the World Bank API" --
  # blaming the network for a response-shape change.
  skip_if_not_installed("WDI")
  wd <- NULL
  local_mocked_bindings(wb_request = function(...) wd, .package = "countryatlas")
  msg <- function(e) cli::ansi_strip(conditionMessage(tryCatch(e,
    warning = identity)))

  wd <- data.frame(country = c("France", "Japan"), year = 2020L, v = c(1, 2))
  expect_warning(fetch_wdi(c(v = "ZK1"), start = 2020, end = 2020),
                 class = "countryatlas_bad_response")
  m <- msg(fetch_wdi(c(v = "ZK2"), start = 2020, end = 2020))
  expect_match(m, "carries no country key", fixed = TRUE)
  expect_false(grepl("Could not fetch", m, fixed = TRUE))
  expect_false(grepl("sourcevar", m, fixed = TRUE))

  # Either key on its own is fine, and an empty response keeps its own
  # diagnosis -- unique codes throughout, because the fetch is memoised.
  wd <- data.frame(iso2c = c("FR", "JP"), country = c("France", "Japan"),
                   year = 2020L, v = c(1, 2))
  expect_silent(fetch_wdi(c(v = "ZK3"), start = 2020, end = 2020))
  wd <- data.frame(iso3c = c("FRA", "JPN"), country = c("France", "Japan"),
                   year = 2020L, v = c(1, 2))
  expect_silent(fetch_wdi(c(v = "ZK4"), start = 2020, end = 2020))
  wd <- data.frame(iso2c = character(0), country = character(0),
                   year = integer(0), v = numeric(0))
  expect_warning(fetch_wdi(c(v = "ZK5"), start = 2020, end = 2020),
                 class = "countryatlas_no_data")
})

test_that("wdj_cache_dir keeps R CMD check out of the user's file space", {
  # R CMD check runs the \donttest{} examples, which fetch, so an unguarded
  # default left World Bank responses in the checking account's persistent
  # cache. Real use still gets tools::R_user_dir().
  old_opt <- options(countryatlas.cache_dir = NULL)
  old_env <- Sys.getenv("_R_CHECK_PACKAGE_NAME_", unset = NA)
  on.exit({
    options(old_opt)
    if (is.na(old_env)) {
      Sys.unsetenv("_R_CHECK_PACKAGE_NAME_")
    } else {
      Sys.setenv("_R_CHECK_PACKAGE_NAME_" = old_env)
    }
  }, add = TRUE)
  user_dir <- tools::R_user_dir("countryatlas", "cache")

  Sys.setenv("_R_CHECK_PACKAGE_NAME_" = "countryatlas")
  under_check <- countryatlas:::wdj_cache_dir()
  expect_false(identical(under_check, user_dir))
  expect_true(startsWith(under_check, tempdir()))

  Sys.unsetenv("_R_CHECK_PACKAGE_NAME_")
  expect_equal(countryatlas:::wdj_cache_dir(), user_dir)

  # An explicit option wins over both.
  mine <- file.path(tempdir(), "explicit-cache")
  options(countryatlas.cache_dir = mine)
  expect_equal(countryatlas:::wdj_cache_dir(), mine)
  Sys.setenv("_R_CHECK_PACKAGE_NAME_" = "countryatlas")
  expect_equal(countryatlas:::wdj_cache_dir(), mine)
})

test_that("the disk cache never deletes a file it did not write", {
  d <- file.path(tempdir(), paste0("ca-shared-", as.integer(stats::runif(1, 1, 1e6))))
  dir.create(d)
  withr::defer(unlink(d, recursive = TRUE))
  writeLines("mine", file.path(d, "notes.txt"))
  saveRDS(1:3, file.path(d, "analysis.rds"))
  dir.create(file.path(d, "sub"))
  writeLines("x", file.path(d, "sub", "keep.csv"))
  # Entries written by earlier versions, which are pruned.
  writeLines("old", file.path(d, "0123456789abcdef0123456789abcdef"))
  saveRDS(1, file.path(d, "fedcba9876543210fedcba9876543210.rds"))
  withr::local_options(countryatlas.cache_dir = d)
  orig <- countryatlas:::fetch_one_indicator
  stub <- function(code, name, start, end, language = "en") {
    x <- tibble::tibble(iso2c = "US", iso3c = "USA", country = "US",
                        year = 2000L)
    x[[name]] <- 1
    x
  }
  assignInNamespace("fetch_one_indicator", stub, "countryatlas")
  withr::defer(assignInNamespace("fetch_one_indicator", orig, "countryatlas"))
  withr::defer(clear_country_cache("wdi"))
  clear_country_cache("wdi")
  invisible(countryatlas:::fetch_wdi(c(x = "I1"), 2000, 2000, parallel = FALSE))
  mine <- c("analysis.rds", "notes.txt", file.path("sub", "keep.csv"))
  left <- list.files(d, recursive = TRUE)
  expect_true(all(mine %in% left))
  expect_false(any(grepl("^[0-9a-f]{32}(\\.rds)?$", left)))
  expect_true(any(grepl("\\.countryatlas$", left)))
  clear_country_cache("wdi", disk = TRUE)
  # The cache's own entries go; the caller's files, and so the folder, stay.
  expect_setequal(list.files(d, recursive = TRUE), mine)
})

test_that("a bad cache limit option is named, not blamed on the directory", {
  skip_slow_on_cran()
  td <- tempfile("cachelim")
  dir.create(td)
  old <- options(countryatlas.cache_dir = td)
  on.exit({
    unlink(td, recursive = TRUE)
    options(old)
    options(countryatlas.cache_max_age = NULL, countryatlas.cache_max_size = NULL)
    clear_country_cache("wdi")
  }, add = TRUE)
  for (opt in c("countryatlas.cache_max_age", "countryatlas.cache_max_size")) {
    for (bad in list("a", NA, -1, c(1, 2))) {
      do.call(options, stats::setNames(list(bad), opt))
      clear_country_cache("wdi")
      expect_error(countryatlas:::get_fetch_fun(TRUE), opt, fixed = TRUE)
    }
    do.call(options, stats::setNames(list(NULL), opt))
  }
  # Inf is "no limit" and keeps the disk cache.
  options(countryatlas.cache_max_age = Inf)
  clear_country_cache("wdi")
  expect_no_error(countryatlas:::get_fetch_fun(TRUE))
  expect_true(countryatlas:::.wdj_state$fetch_on_disk)
})

test_that("clear_country_cache forgets the memo and can remove the disk cache", {
  expect_true(clear_country_cache("wdi"))
  dir <- file.path(tempdir(), "countryatlas-clear-test")
  dir.create(dir, showWarnings = FALSE)
  old <- options(countryatlas.cache_dir = dir)
  on.exit(options(old), add = TRUE)
  expect_true(dir.exists(dir))
  expect_true(clear_country_cache("wdi", disk = TRUE))
  expect_false(dir.exists(dir))
  # Removing a cache that was never created is a no-op, not an error.
  expect_true(clear_country_cache("wdi", disk = TRUE))
})

test_that("clear_wdi_cache() is deprecated in favour of clear_country_cache()", {
  # It was generalised into clear_country_cache() in 3.0.0 and stayed a
  # silent alias; it now says so, and goes in 5.0.0.
  rlang::local_options(lifecycle_verbosity = "warning")
  expect_warning(out <- clear_wdi_cache(), class = "lifecycle_warning_deprecated")
  expect_true(out)
  expect_match(conditionMessage(tryCatch(clear_wdi_cache(), warning = identity)),
               "clear_country_cache", fixed = TRUE)
})
