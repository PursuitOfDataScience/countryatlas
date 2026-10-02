test_that("wdj_http_get() retries what is worth retrying, and only that", {
  # A 502 then a 200: one retry, one wait, and the body comes back.
  calls <- 0L
  waits <- numeric()
  local_mocked_bindings(
    http_attempt = function(url, accept, timeout) {
      calls <<- calls + 1L
      list(status_code = if (calls == 1L) 502L else 200L, url = url,
           headers = raw(0), content = charToRaw("ok"))
    },
    http_sleep = function(s) waits <<- c(waits, s))
  res <- wdj_http_get("https://example.org/x", retries = 3L)
  expect_identical(res$status, 200L)
  expect_identical(rawToChar(res$body), "ok")
  expect_identical(calls, 2L)
  expect_length(waits, 1L)
  expect_lte(waits, 1.5)
})

test_that("a client error is not retried, and a final failure is classed", {
  calls <- 0L
  local_mocked_bindings(
    http_attempt = function(url, accept, timeout) {
      calls <<- calls + 1L
      list(status_code = 404L, url = url, headers = raw(0), content = raw(0))
    },
    http_sleep = function(s) NULL)
  e <- expect_error(wdj_http_get("https://example.org/missing", retries = 3L),
                    class = "countryatlas_fetch_failed")
  expect_identical(calls, 1L)
  expect_identical(e$status, 404L)
  # 403 is retried only when asked: one provider rate-limits that way.
  calls <- 0L
  local_mocked_bindings(
    http_attempt = function(url, accept, timeout) {
      calls <<- calls + 1L
      list(status_code = if (calls < 3L) 403L else 200L, url = url,
           headers = raw(0), content = raw(0))
    },
    http_sleep = function(s) NULL)
  expect_identical(wdj_http_get("https://example.org/x", retry_403 = TRUE)$status,
                   200L)
  expect_identical(calls, 3L)
})

test_that("retries are bounded, back off, and honour Retry-After", {
  calls <- 0L
  waits <- numeric()
  local_mocked_bindings(
    http_attempt = function(url, accept, timeout) {
      calls <<- calls + 1L
      list(status_code = 503L, url = url,
           headers = charToRaw("HTTP/1.1 503\r\nRetry-After: 7\r\n\r\n"),
           content = raw(0))
    },
    http_sleep = function(s) waits <<- c(waits, s))
  expect_error(wdj_http_get("https://example.org/x", retries = 2L),
               "after 3 attempts", class = "countryatlas_fetch_failed")
  expect_identical(calls, 3L)
  expect_equal(waits, c(7, 7))
  # Without Retry-After the waits grow, with jitter, and are capped.
  waits <- numeric()
  local_mocked_bindings(
    http_attempt = function(url, accept, timeout) {
      list(status_code = 500L, url = url, headers = raw(0), content = raw(0))
    },
    http_sleep = function(s) waits <<- c(waits, s))
  set.seed(1)
  expect_error(wdj_http_get("https://example.org/x", retries = 3L),
               class = "countryatlas_fetch_failed")
  expect_length(waits, 3L)
  expect_true(all(waits >= c(0.5, 1, 2) & waits <= c(1.5, 3, 6)))
})

test_that("a dropped connection is retried and a bad certificate is not", {
  calls <- 0L
  local_mocked_bindings(
    http_attempt = function(url, accept, timeout) {
      calls <<- calls + 1L
      if (calls == 1L) return(simpleError("Timeout was reached"))
      list(status_code = 200L, url = url, headers = raw(0), content = raw(0))
    },
    http_sleep = function(s) NULL)
  expect_identical(wdj_http_get("https://example.org/x")$status, 200L)
  expect_identical(calls, 2L)
  calls <- 0L
  local_mocked_bindings(
    http_attempt = function(url, accept, timeout) {
      calls <<- calls + 1L
      simpleError("SSL certificate problem: unable to get local issuer certificate")
    },
    http_sleep = function(s) NULL)
  expect_error(wdj_http_get("https://example.org/x"), "certificate",
               class = "countryatlas_fetch_failed")
  expect_identical(calls, 1L)
})

test_that("the timeout, retry and strict options are validated where read", {
  skip_slow_on_cran()
  for (bad in list(0, -1, "60", NA, c(1, 2))) {
    withr::local_options(countryatlas.timeout = bad)
    expect_error(countryatlas:::http_timeout(), "countryatlas.timeout",
                 class = "countryatlas_bad_option")
  }
  withr::local_options(countryatlas.timeout = NULL)
  expect_identical(countryatlas:::http_timeout(), 60)
  for (bad in list(-1, 1.5, 11, "3", NA)) {
    withr::local_options(countryatlas.retries = bad)
    expect_error(countryatlas:::http_retries(), "countryatlas.retries")
  }
  withr::local_options(countryatlas.retries = 0)
  expect_identical(countryatlas:::http_retries(), 0L)
  withr::local_options(countryatlas.strict = "yes")
  expect_error(countryatlas:::fetch_strict(), "countryatlas.strict")
})

test_that("a failed fetch warns and degrades, or errors under strict", {
  e <- structure(class = c("countryatlas_fetch_failed", "error", "condition"),
                 list(message = "HTTP status 502", call = NULL))
  expect_warning(out <- countryatlas:::fetch_failed(e, "a thing", "empty"),
                 class = "countryatlas_fetch_failed")
  expect_identical(out, "empty")
  withr::local_options(countryatlas.strict = TRUE)
  expect_error(countryatlas:::fetch_failed(e, "a thing", "empty"),
               class = "countryatlas_fetch_failed")
})

test_that("the user agent names the package and its version", {
  ua <- countryatlas:::wdj_user_agent()
  expect_match(ua, paste0("^countryatlas/",
                          as.character(utils::packageVersion("countryatlas"))))
  expect_match(ua, "github.com/PursuitOfDataScience/countryatlas", fixed = TRUE)
})
