# Internal utilities -----------------------------------------------------------

# Friendly abort/warn wrappers built on cli so messages are consistent.
# `.envir` is forwarded so cli `{}` interpolation resolves variables in the
# *caller's* environment, not inside these wrappers.
wdj_abort <- function(message, ..., call = rlang::caller_env(), class = NULL,
                      .envir = rlang::caller_env()) {
  cli::cli_abort(message, ..., call = call, .envir = .envir,
                 class = c(class, "countryatlas_error"))
}

wdj_warn <- function(message, ..., class = NULL, .envir = rlang::caller_env()) {
  cli::cli_warn(message, ..., .envir = .envir,
                class = c(class, "countryatlas_warning"))
}

wdj_inform <- function(message, ..., .envir = rlang::caller_env()) {
  cli::cli_inform(message, ..., .envir = .envir)
}

# Gate an optional (Suggests) dependency. Used everywhere a heavy backend is
# touched so the base install stays light and the error is actionable.
need_pkg <- function(pkg, reason = NULL, call = rlang::caller_env()) {
  rlang::check_installed(pkg, reason = reason, call = call)
  invisible(TRUE)
}

has_pkg <- function(pkg) {
  isTRUE(requireNamespace(pkg, quietly = TRUE))
}

# Some sf/s2/GEOS internals print diagnostic notices straight to stderr
# (e.g. sf_use_s2()'s "Spherical geometry switched on/off", or st_touches()'s
# own validity-repair fallback) that bypass R's message() condition system
# entirely, so suppressMessages() can't catch them. Redirect the message
# stream for the duration of expr instead.
quietly_sf <- function(expr) {
  con <- textConnection("wdj_sf_sink_buf", "w", local = TRUE)
  sink(con, type = "message")
  on.exit({
    sink(type = "message")
    close(con)
  }, add = TRUE)
  force(expr)
}

# Decide how many workers to use. Honours options(countryatlas.workers=) and
# falls back to all-but-one available core, capped at the work size.
wdj_workers <- function(n_tasks = Inf) {
  opt <- getOption("countryatlas.workers", NULL)
  if (!is.null(opt)) {
    workers <- max(1L, as.integer(opt))
  } else if (identical(Sys.getenv("_R_CHECK_LIMIT_CORES_"), "TRUE")) {
    # CRAN policy: never use more than two cores under R CMD check.
    workers <- 2L
  } else {
    cores <- tryCatch(parallel::detectCores(), error = function(e) 1L)
    if (is.na(cores) || cores < 1L) cores <- 1L
    workers <- max(1L, cores - 1L)
  }
  as.integer(min(workers, n_tasks))
}

# Parallel-or-serial lapply. Uses forking (parallel::mclapply) on Unix-alikes
# when it is worth it; falls back to a plain lapply everywhere else (Windows,
# single task, or when the user opts out). Keeps results in order and surfaces
# per-element errors instead of swallowing them.
wdj_lapply <- function(X, FUN, ..., parallel = TRUE, workers = NULL) {
  FUN <- match.fun(FUN)
  n <- length(X)
  if (n == 0L) return(list())

  use_parallel <- isTRUE(parallel) &&
    n > 1L &&
    .Platform$OS.type != "windows" &&
    has_pkg("parallel")

  if (!use_parallel) {
    return(lapply(X, FUN, ...))
  }

  if (is.null(workers)) workers <- wdj_workers(n)
  if (workers <= 1L) {
    return(lapply(X, FUN, ...))
  }

  res <- parallel::mclapply(X, FUN, ..., mc.cores = workers,
                            mc.preschedule = FALSE)
  errs <- vapply(res, inherits, logical(1), what = "try-error")
  if (any(errs)) {
    msg <- conditionMessage(attr(res[[which(errs)[1]]], "condition"))
    wdj_abort(c("Parallel computation failed.", "x" = msg))
  }
  res
}

# Validate a year (scalar or vector / range). World Bank data starts in 1960.
validate_years <- function(year, call = rlang::caller_env()) {
  if (missing(year) || is.null(year)) {
    wdj_abort("{.arg year} is required.", call = call)
  }
  if (!is.numeric(year)) {
    wdj_abort("{.arg year} must be numeric, not {.cls {class(year)}}.", call = call)
  }
  year <- as.integer(round(year))
  if (anyNA(year)) {
    wdj_abort("{.arg year} must not contain missing values.", call = call)
  }
  this_year <- as.integer(format(Sys.Date(), "%Y"))
  if (any(year < 1960L) || any(year > this_year)) {
    wdj_abort(c(
      "{.arg year} must be between 1960 and {this_year}.",
      "x" = "Got {.val {range(year)}}."
    ), call = call)
  }
  sort(unique(year))
}

# Normalise the `indicator` argument into a named character vector of WDI codes.
# Accepts an unnamed vector (codes used as names too) or a named one.
normalize_indicator <- function(indicator) {
  if (is.null(indicator) || length(indicator) == 0L) return(NULL)
  nms <- names(indicator)                 # capture before as.character() drops them
  indicator <- as.character(indicator)
  if (is.null(nms)) nms <- rep("", length(indicator))
  blank <- !nzchar(nms)
  # For unnamed entries, fall back to a cleaned-up version of the code.
  nms[blank] <- make.names(indicator[blank])
  stats::setNames(indicator, nms)
}

# The income factor ordering used throughout the package.
income_levels <- function() {
  c("Not classified", "Low income", "Lower middle income",
    "Upper middle income", "High income")
}

# Standardise the assorted WDI income spellings to the canonical levels.
clean_income <- function(x) {
  x <- as.character(x)
  x[x %in% c("Not Classified", "Not classified", "NA", "Aggregates")] <- "Not classified"
  factor(x, levels = income_levels())
}
