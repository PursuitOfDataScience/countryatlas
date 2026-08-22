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
# `version` is forwarded to check_installed() for the cases where merely having
# the package is not enough.
need_pkg <- function(pkg, reason = NULL, version = NULL,
                     call = rlang::caller_env()) {
  rlang::check_installed(pkg, reason = reason, version = version, call = call)
  invisible(TRUE)
}

has_pkg <- function(pkg) {
  isTRUE(requireNamespace(pkg, quietly = TRUE))
}

# Every iso3c the package recognises: countrycode's own set plus Kosovo's
# user-assigned XKX, which has no codelist row at all. One definition, so the
# name-matcher, the World Bank aggregate filter and region resolution can't
# drift apart on what counts as a country.
wdj_known_iso3c <- function() {
  c(unique(stats::na.omit(countrycode::codelist$iso3c)), "XKX")
}

# Validate that columns exist before they are handed to ggplot2 / vctrs, which
# would otherwise report a bare "object 'x' not found" from deep inside a layer.
# The non-panel counterpart of check_panel_cols() in R/analysis.R.
check_cols <- function(data, cols, call = rlang::caller_env()) {
  missing <- setdiff(cols, names(data))
  if (length(missing)) {
    wdj_abort("Column{?s} {.val {missing}} not found in {.arg data}.", call = call)
  }
  invisible(TRUE)
}

# Validate a scalar numeric argument. Without this, a typo or an NA reached base
# R and dependency internals unchecked and surfaced as "missing value where
# TRUE/FALSE needed", classInt's "n less than 2", or a PROJ error about lat_0 --
# none of which name the argument that was wrong.
check_number <- function(x, arg, lo = -Inf, hi = Inf,
                         call = rlang::caller_env()) {
  if (!is.numeric(x) || length(x) != 1L || !is.finite(x)) {
    wdj_abort(
      "{.arg {arg}} must be a single finite number, not {.val {x}}.",
      call = call
    )
  }
  if (x < lo || x > hi) {
    wdj_abort(c(
      "{.arg {arg}} must be between {lo} and {hi}.",
      "x" = "Got {.val {x}}."
    ), call = call)
  }
  invisible(x)
}

# world_map()/globe_map() handed `palette` and the label strings straight to
# viridisLite and ggplot2. A length-2 `palette` reached a bare switch() and came
# back as base R's "EXPR must be a length 1 vector"; a numeric one was accepted
# without a word; and a length-2 `title`/`legend` was accepted too, after which
# ggplot2 drew both strings over each other. (Only `na_label` truncates to its
# first element, and that is by design -- there is one NA key.) world_query()
# validates the two of these four it takes, `palette` and `title`, so this closes
# the gap between the two entry points. Labels are length-checked but not
# type-checked -- ggplot2 renders `title = 2024` happily and rejecting that would
# be gratuitous -- whereas `palette` is documented as a *name*, so it has to be a
# single string.
check_label_args <- function(palette = NULL, title = NULL, legend = NULL,
                             na_label = NULL, call = rlang::caller_env()) {
  if (!is.null(palette)) check_string(palette, "palette", call = call)
  check_len1 <- function(x, arg) {
    if (is.null(x)) return(invisible(NULL))
    # A length-1 NA is the documented "leave the default formatter alone".
    if (length(x) != 1L) {
      wdj_abort(c(
        "{.arg {arg}} must be a single value.",
        "x" = "Got {length(x)} value{?s}.",
        "i" = "It labels one key, so only the first would have been used."
      ), call = call)
    }
    invisible(NULL)
  }
  check_len1(title, "title")
  check_len1(legend, "legend")
  # `na_label` is deliberately tolerant: discrete_na_labels() takes its first
  # element, because there is only one NA key to label, and a length-1 NA means
  # "leave the default formatter alone". Erroring here would break that contract
  # (and a test pins it), so say what is happening instead of doing it silently.
  if (!is.null(na_label) && length(na_label) > 1L) {
    wdj_warn(c(
      "{.arg na_label} has {length(na_label)} values but labels one key.",
      "i" = "Using {.val {as.character(na_label)[[1]]}}; the rest are ignored."
    ), call = call)
  }
  invisible(NULL)
}

# sf/s2/GEOS internals emit diagnostic notices that are noise here -- e.g.
# sf_use_s2()'s "Spherical geometry (s2) switched on/off" and st_intersection()/
# st_touches()'s "although coordinates are longitude/latitude, ... assumes that
# they are planar". Silence them two ways, because they arrive two ways: most are
# ordinary message() conditions, which have to be muffled or they escape to the
# caller's handlers even with the stream redirected; a few GDAL/GEOS diagnostics
# are written straight to stderr from C and are only caught by the sink. No
# countryatlas code emits its own messages inside these blocks, so muffling all
# of them here cannot swallow anything the user asked for.
quietly_sf <- function(expr) {
  con <- textConnection("wdj_sf_sink_buf", "w", local = TRUE)
  sink(con, type = "message")
  on.exit({
    sink(type = "message")
    close(con)
  }, add = TRUE)
  withCallingHandlers(expr, message = function(m) invokeRestart("muffleMessage"))
}

# Is this an R CMD check that caps core use? CRAN policy allows a check at most
# two cores, and R signals the cap through _R_CHECK_LIMIT_CORES_.
#
# `--as-cran` sets that to "TRUE" -- but only when it is not already set, so
# what actually arrives is whatever the check flavour or CI exported, and R's
# own parser for these variables (utils:::str2logical) reads "true", "True",
# "T", "1", "yes", "Yes" and "YES" as true as well. Testing for the literal
# string "TRUE" let every one of those through, and the fetch then forked
# detectCores() - 1 workers in the middle of a check.
#
# So invert the test: anything set that does not explicitly parse as *false*
# means "limit". That is the safe direction -- over-limiting costs a little
# parallelism in one check, under-limiting breaks a CRAN policy -- and it also
# covers "warn", where R reports core use rather than capping it.
check_limits_cores <- function() {
  val <- Sys.getenv("_R_CHECK_LIMIT_CORES_", "")
  nzchar(val) && !(ascii_lower(trimws(val)) %in% c("false", "f", "0", "no"))
}

# Decide how many workers to use. Honours options(countryatlas.workers=) and
# falls back to all-but-one available core, capped at the work size.
# Scalar-string validator, the character counterpart of check_number(). The
# string builders sprintf() their arguments, and sprintf() vectorises silently:
# a length-2 value duplicated a whole query clause, a length-0 one made the
# clause vanish, and NA became the literal text "NA".
check_string <- function(x, arg, allow_empty = FALSE,
                         call = rlang::caller_env()) {
  if (!is.character(x) || length(x) != 1L || is.na(x)) {
    wdj_abort(c(
      "{.arg {arg}} must be a single string.",
      "x" = if (length(x) != 1L) "Got {length(x)} value{?s}." else "Got {.val {x}}."
    ), call = call)
  }
  if (!allow_empty && !nzchar(x)) {
    wdj_abort("{.arg {arg}} must not be an empty string.", call = call)
  }
  invisible(x)
}

# Scalar-logical validator. The bare `if (borders)` sites turned a bad value
# into one of four opaque base R errors ("missing value where TRUE/FALSE
# needed", "argument is of length zero", "the condition has length > 1",
# "argument is not interpretable as logical"), and the isTRUE() sites were
# quieter but worse: any non-TRUE value became FALSE, so `desc = "yes"` sorted
# ascending and `na.rm = "yes"` kept the NAs. Strict about type, as rlang is.
check_bool <- function(x, arg, call = rlang::caller_env()) {
  if (!is.logical(x) || length(x) != 1L || is.na(x)) {
    wdj_abort(c(
      "{.arg {arg}} must be {.code TRUE} or {.code FALSE}.",
      "x" = if (length(x) != 1L) "Got {length(x)} value{?s}." else "Got {.val {x}}."
    ), call = call)
  }
  invisible(x)
}

# Length validator for a vector that must line up with another. These were
# recycled with rep_len(), which accepts any length silently: gini(1:10,
# weights = c(1, 2)) returned 0.2902 -- a plausible number computed from an
# alternating 1,2 pattern -- instead of erroring.
check_along <- function(x, n, arg, along = "x", call = rlang::caller_env()) {
  if (length(x) != 1L && length(x) != n) {
    wdj_abort(c(
      "{.arg {arg}} must be length 1 or length {n}, to match {.arg {along}}.",
      "x" = "Got {length(x)} value{?s}."
    ), call = call)
  }
  invisible(x)
}

# rlang::as_name() on a missing argument raises `argument "x" is missing, with
# no default`, naming rlang's own parameter rather than the caller's -- useless
# to someone who simply forgot an argument. Name the real one instead.
quo_arg_name <- function(quo, arg, call = rlang::caller_env()) {
  if (rlang::quo_is_missing(quo)) {
    wdj_abort("{.arg {arg}} is required.", call = call)
  }
  rlang::as_name(quo)
}

# A number destined for a machine-readable string must not depend on the user's
# options(). options(OutDec = ",") -- normal in comma-decimal locales -- turned a
# PROJ string into "+lat_0=12,5", which PROJ rejects, and the resulting invalid
# CRS surfaced only later as sf's opaque "crs not found: is it missing?".
# options(scipen) can likewise render 100 as "1e+02". formatC() with an explicit
# decimal.mark is immune to both.
fmt_num <- function(x) {
  formatC(x, format = "f", digits = 10, drop0trailing = TRUE,
          decimal.mark = ".", big.mark = "")
}

# Two third-party routines mis-handle numbers under the user's formatting
# options, and both are reachable through this package: rmapshaper serialises
# `keep` for V8, which rejects the "0,1" that options(OutDec = ",") produces,
# and sf::st_graticule() overflows the node stack under a negative scipen.
# A negative scipen breaks far more than that, but not through anything this
# package does: `st_crs(paste0("EPSG:", 4326))` becomes "EPSG:4.326e+03" and a
# bare `ggplot(sf_obj) + geom_sf()` fails with "crs not found" on its own, as
# does `scale_colour_viridis_c()` with "Unknown white reference". Verified with
# countryatlas not even loaded, so there is nothing here to guard -- fmt_num()
# already immunises every PROJ string the package itself builds.
# Both are upstream bugs, but a comma-decimal locale is ordinary, so normalise
# the two options for the duration of such a call and restore them straight
# after. `expr` is a promise, so it is evaluated inside the changed options.
with_c_numbers <- function(expr) {
  old <- options(OutDec = ".", scipen = 0)
  on.exit(options(old), add = TRUE)
  force(expr)
}

# Arithmetic on a non-numeric value column gave either a column of NAs behind
# base R's "'/' not meaningful for factors" or an opaque error from inside dplyr
# -- gini() managed "missing value where TRUE/FALSE needed". A factor value
# column is easy to end up with (read.csv() on a column holding one stray
# non-numeric entry), so name the column and its type.
check_numeric_col <- function(data, col, call = rlang::caller_env()) {
  x <- data[[col]]
  if (!is.numeric(x)) {
    wdj_abort(c(
      "Column {.val {col}} must be numeric.",
      "x" = "It is {.obj_type_friendly {x}}.",
      "i" = "Convert it first, e.g. {.code as.numeric(as.character(x))}."
    ), call = call)
  }
  invisible(x)
}

# Does this frame carry map geometry rather than one row per country? The
# polygon backend expands 249 countries into ~99,000 vertex rows, so a row-wise
# aggregate over it multiplies every country by its vertex count. Verbs that
# genuinely take one row per country de-duplicate on iso3c instead; this is for
# the ones that cannot, because repeated rows are also legitimate there (a
# panel).
has_map_geometry <- function(data) {
  is_sf(data) || all(c("long", "lat", "group") %in% names(data))
}

# Mid-range of a longitude vector, tolerating a country that crosses the
# antimeridian. mean(range(x)) is fine until the points sit either side of 180,
# where it returns roughly the antipode -- measured against the largest-piece
# centroid, Fiji was 177.8 degrees out (0.2 vs 178.0), New Zealand 169.6 and
# even the USA 96.6, its Aleutian tail dragging the mid-range to the Gulf of
# Guinea. Re-expressing in [0, 360) before averaging cuts those to 0.2, 6.9 and
# 31.4. It is an approximation, not the largest-piece rule: with no piece
# boundaries there is no way to tell a country straddling the line from one
# encircling the pole, so Antarctica moves from 0 to 180 -- equally arbitrary
# for a polar ring. Keep the `group` column and polygon_centroids() does it
# properly.
antimeridian_centre <- function(long) {
  long <- long[!is.na(long)]
  if (!length(long)) return(NA_real_)
  span <- diff(range(long))
  if (!is.finite(span) || span <= 180) return(mean(range(long)))
  shifted <- ifelse(long < 0, long + 360, long)
  ctr <- mean(range(shifted))
  if (ctr > 180) ctr - 360 else ctr
}

# The verbs that add a fixed-name column used to replace one the caller already
# had, in silence: a user's own `rank`, `percentile` or `<value>_share` column
# simply vanished. Warn rather than error -- re-running a verb on its own output
# is legitimate (and idempotent), it just should not be invisible.
warn_overwrite <- function(data, cols) {
  hit <- intersect(cols, names(data))
  if (length(hit)) {
    # cli takes the pluralisation quantity from the last number *before* the
    # marker, so {length(hit)} has to lead -- without it the warning itself
    # failed with "Cannot pluralize without a quantity".
    wdj_warn(c(
      "Overwriting {length(hit)} existing column{?s} in {.arg data}: {.val {hit}}.",
      "i" = "Rename them first to keep the original values."
    ))
  }
  invisible(data)
}

# Strip the polygon backend's positional columns, so a frame that has already
# been through attach_geometry() can be reduced to country level and re-attached
# to a *different* backend. Only the four positional columns go: `region` /
# `subregion` may well be the caller's own.
drop_map_geometry <- function(data) {
  data <- tibble::as_tibble(data)
  data[, setdiff(names(data), c("long", "lat", "group", "order")), drop = FALSE]
}

# Require map geometry, with one message wherever it is needed. Forgetting
# attach_geometry() is the easiest mistake in the package -- the other plotting
# verbs do not need it -- and without this it surfaced only when the plot was
# printed, as ggplot2's "Problem while computing aesthetics ... `.data$long`".
check_map_geometry <- function(data, call = rlang::caller_env()) {
  if (!has_map_geometry(data)) {
    wdj_abort(c(
      "{.arg data} has no map geometry.",
      "x" = "Expected {.field long}, {.field lat} and {.field group} columns, or an sf frame.",
      "i" = "Attach it first: {.code attach_geometry(data)}, or use
             {.fn join_world} on a frame keyed by country name."
    ), call = call)
  }
  invisible(TRUE)
}
# ASCII-only case folding. toupper()/tolower() follow LC_CTYPE, and in Turkish,
# Azeri and Crimean Tatar locales "i" and "I" are not each other's case pair:
# toupper("idn") is "IDN" in C but "\u0130DN" (dotted capital I) there, and
# tolower("ISO3C") is "iso3c" in C but "\u0131so3c" (dotless i) there. Every
# caller below folds an *identifier* -- an ISO 3166 code, a data frame column
# name, an alias key written as an ASCII literal in this source -- so the
# comparison target is ASCII by construction and the locale has no business in
# it. Left alone deliberately: the fuzzy matchers in diagnostics.R fold both
# sides at run time, so they stay self-consistent whatever the locale.
#
# Note this only makes *our* folding locale-proof. countrycode's country-name
# regexes are themselves locale-sensitive -- countrycode("Ireland") is NA under
# tr_TR -- which no amount of care here can repair.
ascii_upper <- function(x) {
  chartr("abcdefghijklmnopqrstuvwxyz", "ABCDEFGHIJKLMNOPQRSTUVWXYZ", x)
}

ascii_lower <- function(x) {
  chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz", x)
}


wdj_workers <- function(n_tasks = Inf) {
  opt <- getOption("countryatlas.workers", NULL)
  if (!is.null(opt)) {
    # The option is advertised in NEWS, so a bad value is reachable, and it used
    # to reach mclapply(mc.cores = NA): "abc", NA and Inf all became NA workers
    # and surfaced as "missing value where TRUE/FALSE needed" from deep inside
    # the fetch, while c(2, 4) silently took the larger. A string that names a
    # number still works, as it always did.
    n <- suppressWarnings(as.numeric(opt))
    if (length(n) != 1L || !is.finite(n)) {
      wdj_abort(c(
        "{.code options(countryatlas.workers)} must be a single finite number.",
        "x" = if (length(n) != 1L) "Got {length(n)} values."
              else "Got {.val {opt}}."
      ))
    }
    # A number below one is still clamped rather than rejected: that never
    # caused the failure above, and the existing contract is only that the
    # count never drops below one.
    workers <- max(1L, as.integer(n))
  } else if (check_limits_cores()) {
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
