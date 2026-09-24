# Skip a test when the World Bank API is unreachable (and always on CRAN), so
# the suite is deterministic and offline-safe.
skip_if_offline_wb <- function() {
  testthat::skip_on_cran()
  ok <- tryCatch({
    con <- url("https://api.worldbank.org/v2/country?format=json&per_page=1")
    on.exit(close(con))
    length(readLines(con, n = 1, warn = FALSE)) > 0
  }, error = function(e) FALSE)
  if (!isTRUE(ok)) testthat::skip("World Bank API not reachable")
}

# Skip (rather than fail) when a World Bank fetch came back empty despite the
# reachability probe passing. The live multi-indicator fetch can still flake
# transiently (timeouts, rate limits, a forked worker dying), which must
# degrade to a skip, not a red suite -- consistent with CRAN's policy that
# tests do not fail on unavailable internet resources.
skip_if_wdi_empty <- function(data, cols) {
  ok <- all(cols %in% names(data)) &&
    all(vapply(cols, function(cl) any(!is.na(data[[cl]])), logical(1)))
  if (!isTRUE(ok)) testthat::skip("World Bank fetch returned no data")
}

# A live fetch that degrades after the reachability probe above has passed
# (a timeout, a rate limit) warns by design, because that is the package's
# contract for a failed download, and then comes back empty, at which point
# skip_if_wdi_empty() skips. Those warnings belong to the network rather than
# to the code under test, yet they reached the suite's summary as three
# "Timeout of 60 seconds was reached" entries on a slow day. Turn them into
# the skip they precede.
wdi_live <- function(expr) {
  failed <- FALSE
  out <- withCallingHandlers(expr, warning = function(w) {
    if (inherits(w, "countryatlas_no_data") ||
        grepl("Could not fetch|Timeout|timed out|cannot open URL|resolve host",
              conditionMessage(w))) {
      failed <<- TRUE
      invokeRestart("muffleWarning")
    }
  })
  if (failed) testthat::skip("World Bank fetch failed in this run")
  out
}
