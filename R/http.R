# HTTP: one client for every provider ---------------------------------------------
#
# On 2026-10-01 the World Bank answered 502 to WDI's 32,500-row page and
# fetch_indicator("wdi", ...) returned an empty frame after 450 seconds, with
# no option to say "give up sooner". Each provider client had its own idea of
# a timeout and none of them retried, so how long a failing fetch could take
# depended on which package happened to be underneath. Every built-in adapter
# now goes through wdj_http_get(): a per-request timeout, a bounded number of
# retries with exponential backoff and jitter on the failures that are worth
# retrying (429, 5xx, a dropped connection), Retry-After honoured, and one user
# agent. The worst case is documented on ?countryatlas: (retries + 1) requests
# of at most `timeout` seconds each, plus the backoff between them.

# The user agent providers see, so a rate-limited request can be traced back.
wdj_user_agent <- function() {
  sprintf("countryatlas/%s (+https://github.com/PursuitOfDataScience/countryatlas)",
          as.character(utils::packageVersion("countryatlas")))
}

# The three options, validated where they are read, as every other option the
# package reads is.
http_timeout <- function() {
  v <- getOption("countryatlas.timeout", 60)
  if (!is.numeric(v) || length(v) != 1L || is.na(v) || v <= 0) {
    wdj_abort(c(
      "{.code options(countryatlas.timeout)} must be a single positive number
       of seconds.",
      "x" = "Got {.obj_type_friendly {v}}."
    ), class = "countryatlas_bad_option", call = NULL)
  }
  v
}

http_retries <- function() {
  v <- getOption("countryatlas.retries", 3L)
  if (!is.numeric(v) || length(v) != 1L || is.na(v) || v < 0 || v != round(v) ||
      v > 10) {
    wdj_abort(c(
      "{.code options(countryatlas.retries)} must be a whole number from 0 to
       10.",
      "x" = "Got {.obj_type_friendly {v}}."
    ), class = "countryatlas_bad_option", call = NULL)
  }
  as.integer(v)
}

fetch_strict <- function() {
  v <- getOption("countryatlas.strict", FALSE)
  if (!isTRUE(v) && !isFALSE(v)) {
    wdj_abort(c(
      "{.code options(countryatlas.strict)} must be {.code TRUE} or
       {.code FALSE}.",
      "x" = "Got {.obj_type_friendly {v}}."
    ), class = "countryatlas_bad_option", call = NULL)
  }
  v
}

# One attempt, no retrying: the seam the retry tests mock. Returns curl's
# response list, or the curl error as a condition object.
http_attempt <- function(url, accept, timeout) {
  h <- curl::new_handle()
  curl::handle_setopt(h, timeout = timeout,
                      connecttimeout = min(timeout, 30),
                      useragent = wdj_user_agent(), followlocation = TRUE)
  if (!is.null(accept)) curl::handle_setheaders(h, Accept = accept)
  tryCatch(curl::curl_fetch_memory(url, handle = h), error = function(e) e)
}

# Sleeping between attempts, kept apart so a test can count the waits rather
# than sit through them.
http_sleep <- function(seconds) Sys.sleep(seconds)

# The wait the server asked for, in seconds, or NULL. Retry-After is either a
# number of seconds or an HTTP date.
http_retry_after <- function(res) {
  if (!is.list(res) || is.null(res$headers)) return(NULL)
  hdr <- curl::parse_headers_list(res$headers)
  ra <- hdr[["retry-after"]]
  if (is.null(ra) || !nzchar(ra)) return(NULL)
  secs <- suppressWarnings(as.numeric(ra))
  if (is.na(secs)) {
    when <- suppressWarnings(as.POSIXct(strptime(ra, "%a, %d %b %Y %H:%M:%S",
                                                 tz = "GMT")))
    if (is.na(when)) return(NULL)
    secs <- as.numeric(difftime(when, Sys.time(), units = "secs"))
  }
  max(0, secs)
}

# GET a URL with a timeout and bounded retries. Returns list(status, url,
# headers, body) for a 2xx response; anything else after the last attempt is
# an error of class countryatlas_fetch_failed carrying the status. A 4xx other
# than 429 is not retried, unless `retry_403`: asking again will not make a bad
# request good.
wdj_http_get <- function(url, accept = NULL, timeout = http_timeout(),
                         retries = http_retries(), retry_403 = FALSE,
                         call = rlang::caller_env()) {
  attempt <- 0L
  repeat {
    attempt <- attempt + 1L
    res <- http_attempt(url, accept, timeout)
    if (inherits(res, "error")) {
      status <- NA_integer_
      why <- conditionMessage(res)
      # A certificate the client cannot verify will not verify on the next
      # attempt either; retrying it only multiplies the wait. TLS verification
      # is never switched off here: a machine with an outdated CA bundle needs
      # the bundle fixed, not the check removed.
      retry <- !grepl("certificate|SSL peer|self.signed", why, ignore.case = TRUE)
    } else {
      status <- as.integer(res$status_code)
      if (status >= 200L && status < 300L) {
        return(list(status = status, url = res$url %||% url,
                    headers = res$headers, body = res$content))
      }
      why <- sprintf("HTTP status %d", status)
      # `retry_403` is for the provider that rate-limits with 403 rather than
      # 429 (the ILO answers a burst of requests that way and serves the same
      # request a few seconds later).
      retry <- status == 429L || status >= 500L || (retry_403 && status == 403L)
    }
    if (!retry || attempt > retries) {
      tries <- if (attempt > 1L) sprintf(" (after %d attempts)", attempt) else ""
      wdj_abort(c(
        "The request to {.url {url}} failed.",
        "x" = "{why}{tries}.",
        "i" = "Each attempt waits at most {fmt_num(timeout)} s; see
               {.code options(countryatlas.timeout)} and
               {.code options(countryatlas.retries)}."
      ), class = "countryatlas_fetch_failed", call = call, status = status,
      url = url)
    }
    # Exponential backoff with jitter, capped, unless the server said how long.
    wait <- http_retry_after(res) %||%
      (min(30, 2^(attempt - 1L)) * stats::runif(1L, 0.5, 1.5))
    http_sleep(min(wait, 60))
  }
}

# The body as text, decoded as UTF-8 whatever the session's locale.
http_text <- function(res) {
  txt <- rawToChar(res$body)
  Encoding(txt) <- "UTF-8"
  txt
}

http_json <- function(res, ...) {
  jsonlite::fromJSON(http_text(res), ...)
}

# A fetch that failed, handled the way CRAN wants a package to: a warning and
# an empty result, so an example or a pipeline degrades instead of stopping --
# unless options(countryatlas.strict = TRUE), for a pipeline that must not go
# on with data missing, where the failure is an error of the same class.
fetch_failed <- function(e, what, empty, call = rlang::caller_env()) {
  if (fetch_strict()) {
    wdj_abort(c("Could not fetch {what}.", "x" = "{conditionMessage(e)}"),
              class = "countryatlas_fetch_failed", call = call, parent = e)
  }
  wdj_warn(c(
    "Could not fetch {what}.",
    "x" = "{conditionMessage(e)}",
    "i" = "Returning no rows. Set {.code options(countryatlas.strict = TRUE)}
           to make this an error."
  ), class = "countryatlas_fetch_failed")
  empty
}
