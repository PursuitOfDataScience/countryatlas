# Replaying recorded provider responses.
#
# The adapters reach the network through one function, wdj_http_get(), so a
# test replaces that function and serves the recorded responses in
# tests/testthat/fixtures/ (see data-raw/record_fixtures.R). A request no route
# matches is an error, not a degraded fetch: a test must never pass because a
# call it did not expect quietly returned nothing.
fixture_path <- function(name) testthat::test_path("fixtures", name)

fixture_response <- function(name = NULL, status = 200L, text = NULL, url = "") {
  body <- if (!is.null(text)) charToRaw(enc2utf8(text)) else
    readBin(fixture_path(name), "raw", file.size(fixture_path(name)))
  list(status = as.integer(status), url = url, headers = raw(0), body = body)
}

# `routes`: a named list, URL fragment -> fixture file name, or a function of
# the URL returning a response. Requests are recorded in the returned
# environment's `urls`.
local_fixture_http <- function(routes, .env = parent.frame()) {
  seen <- new.env()
  seen$urls <- character()
  testthat::local_mocked_bindings(
    wdj_http_get = function(url, accept = NULL, ...) {
      seen$urls <- c(seen$urls, url)
      for (p in names(routes)) {
        if (grepl(p, url, fixed = TRUE)) {
          r <- routes[[p]]
          return(if (is.function(r)) r(url) else fixture_response(r, url = url))
        }
      }
      stop("no recorded response for ", url, call. = FALSE)
    },
    .package = "countryatlas", .env = .env)
  seen
}
