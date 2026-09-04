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

# Is a package installed? Deliberately *not* has_pkg(): requireNamespace() loads
# the namespace and so runs .onLoad, and comtradr's .onLoad creates
# ~/.cache/R/comtradr. That made merely asking "which sources are available?"
# write to the user's home filespace -- reported by R CMD check as a new file in
# another directory, and forbidden by CRAN policy. system.file() answers the
# same question without loading anything. Use this when surveying packages the
# caller is not about to call; use has_pkg() when the next line calls pkg::fun().
pkg_installed <- function(pkg) nzchar(system.file(package = pkg))

# Resolve country identifiers to whichever code system is the join key.
#
# iso3c stays the default everywhere, and goes through wdj_to_iso3c() so it
# keeps the override table and the Kosovo special case. The COW and
# Gleditsch-Ward alternates exist for historical work, where ISO 3166 simply
# does not reach: it was first published in 1974 and never covered colonies.
# Those go straight to countrycode, which maintains the crosswalks.
# Three verbs take column names as strings -- interpolate_missing(value),
# complete_years(value) and audit_coverage(indicator) -- while the nine verbs
# around them take a bare column through tidy eval. Writing the bare column
# that works everywhere else produced base R's "object 'v' not found", naming
# neither the argument nor the string it wanted. Only reached once evaluation
# has already failed, so a legitimate expression is never intercepted; and only
# a bare symbol (or c() of symbols) is claimed, so a real error still surfaces.
abort_bare_column <- function(expr, arg, cnd, call = rlang::caller_env()) {
  bare <- is.symbol(expr) ||
    (is.call(expr) && identical(expr[[1L]], quote(c)) && length(expr) > 1L &&
       all(vapply(as.list(expr)[-1L], is.symbol, logical(1))))
  if (!bare) stop(cnd)
  txt <- vapply(if (is.symbol(expr)) list(expr) else as.list(expr)[-1L],
                as.character, character(1))
  shown <- if (length(txt) == 1L) {
    paste0(arg, ' = "', txt, '"')
  } else {
    paste0(arg, " = c(", paste0('"', txt, '"', collapse = ", "), ")")
  }
  wdj_abort(c(
    "{.arg {arg}} takes column names as strings.",
    "x" = "Got {.code {txt}} unquoted.",
    "i" = "Write {.code {shown}}."
  ), call = call, class = "countryatlas_bare_column")
}

# What a verb hands back after adding columns. as_tibble() was doing double
# duty at these return points: it normalised the class *and* dropped grouping.
# Removing it kept an sf frame alive -- join_world(geometry = "sf") |>
# share_of_world() |> world_map() had died on "`data` has no map geometry"
# because the class was gone while the geometry column remained -- but leaked a
# grouped input straight back out, which test-analysis.R pins against. sf is the
# one class worth carrying through, since the map verbs require it; everything
# else becomes a tibble, as standardize_country()'s test has always required.
wdj_return_frame <- function(data) {
  if (inherits(data, "sf")) dplyr::ungroup(data) else tibble::as_tibble(data)
}

# Reshaping verbs -- tidyr::complete() and the joins -- return a plain tibble
# even when the input was `sf` and the geometry column came through untouched.
# The result then still holds a live `sfc` column, so no data is lost, but the
# class is gone and st_bbox()/geom_sf() refuse it until the caller thinks to
# run st_as_sf() again. Put the class back when the geometry actually survived,
# and leave the frame alone when it did not.
wdj_restore_sf <- function(out, template) {
  if (!inherits(template, "sf") || inherits(out, "sf")) return(out)
  col <- attr(template, "sf_column")
  if (is.null(col) || !col %in% names(out) || !inherits(out[[col]], "sfc")) {
    return(out)
  }
  # Cheap enough to be worth not trusting: a reshape can leave a geometry
  # column whose length no longer matches, and st_as_sf() would abort.
  tryCatch(sf::st_as_sf(out, sf_column_name = col), error = function(e) out)
}

wdj_to_key <- function(x, origin = "country.name", key = "iso3c",
                       custom_match = country_overrides(), side = NULL,
                       warn_unresolved = FALSE) {
  iso <- wdj_to_iso3c(x, origin = origin, custom_match = custom_match)
  # Two different failures, and they need different sentences. This one is "the
  # name is not a country I know" -- reported here rather than by the caller
  # because only here are the two distinguishable: on an alternate key an
  # unresolvable name and a country COW/GW simply has no code for both arrive
  # as NA, and reporting them together told a caller who typed "Freedonia" that
  # it "resolved to iso3c but has no gwn code", which is false.
  if (isTRUE(warn_unresolved)) {
    raw <- as.character(x)
    bad <- unique(raw[is.na(iso) & !is.na(raw)])
    if (length(bad)) {
      where <- if (is.null(side)) "" else sprintf(" in %s", side)
      wdj_warn(c(
        "{length(bad)} value{?s}{where} did not resolve to a country and will
         join to nothing:",
        "*" = "{.val {utils::head(bad, 8)}}",
        "i" = "See {.fn check_country_match} for suggestions."
      ))
    }
  }
  if (identical(key, "iso3c")) return(iso)
  out <- suppressWarnings(
    countrycode::countrycode(iso, "iso3c", key, warn = FALSE))
  # COW/GW cover sovereign states and not dependencies, so a modern dataset
  # loses Hong Kong, Puerto Rico and the rest. Say so once rather than letting
  # the join quietly shrink.
  lost <- sum(!is.na(iso) & is.na(out))
  if (lost) {
    # `side` names which table this refers to. A two-sided join calls this once
    # per side, so without it the user saw the same sentence twice with nothing
    # to distinguish the two.
    where <- if (is.null(side)) "" else sprintf(" in %s", side)
    # `{where}` sits between the count and `ha{?s/ve}`, and cli keys an
    # agreement marker to the most recent *interpolated value* -- a length-1
    # string here -- so however many countries were lost the verb came out
    # singular: "5 countries in `x` resolved to iso3c but has no cowc code."
    # cli::qty() re-keys it to the count explicitly. (Only literal markup such
    # as {.field iso3c} is safe to sit between a count and its agreement.)
    wdj_warn(c(
      "{lost} countr{?y/ies}{where} resolved to {.field iso3c} but
       ha{cli::qty(lost)}{?s/ve} no {.field {key}} code.",
      "i" = "COW and Gleditsch-Ward cover sovereign states, not dependencies
             and territories. They are the right key before 1970 and the wrong
             one after it."
    ))
  }
  out
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
# A repeated header -- what read.csv(check.names = FALSE) gives you for a sheet
# with two `gdp` columns -- makes every by-name reference ambiguous, and the
# frame then goes through a dplyr pipeline that rebuilds it.
# interpolate_missing() already refused it; nothing else did. Ten verbs leaked
# tibble's "Column name `gdp` must not be duplicated. Use `.name_repair` to
# specify repair", which names tibble's internals rather than the caller's
# data, and two -- per_capita() and to_ppp() -- silently computed from
# whichever column `[[` reached first and dropped the other without a word.
# Checked here, where every verb already validates the columns it reads.
check_dup_cols <- function(data, call = rlang::caller_env()) {
  if (!is.data.frame(data)) return(invisible(TRUE))
  dup <- unique(names(data)[duplicated(names(data))])
  if (length(dup)) {
    wdj_abort(c(
      "{.arg data} has {length(dup)} duplicated column name{?s}:",
      "*" = "{.val {dup}}",
      "i" = "Which one to read is ambiguous. Rename or drop the duplicate."
    ), call = call, class = "countryatlas_duplicate_columns")
  }
  invisible(TRUE)
}

check_cols <- function(data, cols, call = rlang::caller_env()) {
  missing <- setdiff(cols, names(data))
  if (length(missing)) {
    wdj_abort("Column{?s} {.val {missing}} not found in {.arg data}.", call = call)
  }
  check_dup_cols(data, call = call)
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
# An engine or backend that cannot honour an argument has to say so rather
# than accept it and draw something else. The polygon backend does this for
# `scale` / `projection` / `recenter`; the alternative engines did not, and
# quietly dropped whole groups of ggplot2-specific arguments.
# `cli::qty()` keys the agreement markers explicitly: {.arg {ignored}} is an
# interpolation, so anything after it would otherwise agree with the wrong
# number.
# Engines that assemble their own plot take `...` and can do nothing with it.
# Report the names the caller actually used, falling back to a position for an
# unnamed one, so the message points at their code rather than at ours.
warn_dots_unused <- function(dots, engine, alternative) {
  if (!length(dots)) return(invisible(NULL))
  nm <- names(dots)
  if (is.null(nm)) nm <- rep("", length(dots))
  nm[!nzchar(nm)] <- paste0("..", seq_along(nm)[!nzchar(nm)])
  warn_engine_ignored(nm, engine, alternative)
}

# A derived column that comes out NA in every row means the verb accomplished
# nothing at all. Each of the verbs that calls this reads neighbouring rows, so
# the usual cause is a cross-section handed to a panel verb: there is no
# earlier year to compare against, and the result looks like a computation that
# ran rather than one with nothing to work on -- the same complaint
# per_capita(), to_ppp() and share_of_world() already answer for an unusable
# denominator.
#
# Requiring the source column to hold something separates "nothing to compute
# from" (worth saying) from "nothing was given" (the caller's own doing, and
# reported elsewhere). `env` is the calling verb's frame, so `needs` can
# interpolate that verb's own arguments; cli would otherwise evaluate it here,
# where they do not exist.
warn_all_na_result <- function(data, val_name, new_col, needs,
                               env = rlang::caller_env()) {
  v <- data[[new_col]]
  if (!length(v) || !all(is.na(v)) || all(is.na(data[[val_name]]))) {
    return(invisible(NULL))
  }
  per <- if ("iso3c" %in% names(data)) max(c(0L, table(data$iso3c))) else NA_integer_
  wdj_warn(c(
    "{.field {new_col}} came out {.val {NA}} for every row.",
    "!" = needs,
    "i" = if (!is.na(per) && per <= 1L) {
      "Each country appears once here, so there is no other row to compare it
       with. {.fn complete_years} builds the missing years if you have them."
    } else {
      "{.field {val_name}} is unchanged; only the derived column is empty."
    }
  ), class = "countryatlas_all_na_result", .envir = env)
  invisible(NULL)
}

warn_engine_ignored <- function(ignored, engine, alternative) {
  if (!length(ignored)) return(invisible(NULL))
  wdj_warn(c(
    "{.val {engine}} does not support {cli::qty(length(ignored))}{?this
     argument/these arguments} and ignores {cli::qty(length(ignored))}{?it/them}:
     {.arg {ignored}}.",
    "i" = "Use {.code {alternative}} for {cli::qty(length(ignored))}{?it/them}."
  ), class = "countryatlas_engine_ignored")
  invisible(NULL)
}

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
# match.arg() reports R's anonymous "'arg' should be one of ..." -- naming
# neither the argument the caller passed nor the function they called. It does
# so *everywhere*, not just in helpers: the message is hard-coded, so calling it
# on a function's own formal reads no better. Exported functions therefore use
# rlang::arg_match(), which reads the choices off the formal and names both.
# check_choice() is the variant for helpers like wdj_crs(), which receive an
# already-extracted value and so must be told the argument name and the call to
# blame -- seventeen exported functions take `projection` and nine take `scale`,
# all routing through two helpers, so fixing it here fixes it everywhere.
check_choice <- function(x, arg, choices, call = rlang::caller_env()) {
  if (length(x) == 1L && is.character(x) && x %in% choices) return(x)
  # A caller that passed nothing gets the documented default, exactly as
  # match.arg() would.
  if (length(x) == length(choices) && identical(as.character(x), as.character(choices))) {
    return(choices[1])
  }
  wdj_abort(c(
    "{.arg {arg}} must be one of {.val {choices}}.",
    "x" = if (length(x) != 1L) "Got {length(x)} values." else "Got {.val {x}}."
  ), call = call)
}

# The four source adapters are exported in their own right, so the validation
# fetch_indicator() does at the front door has to be repeated at each of them.
# Called directly with an empty vector they did no work and said nothing:
# lapply() produced no frames and Reduce() over an empty list returns NULL, so
# fetch_owid(NULL) handed back a silent NULL instead of an error, and
# fetch_comtrade(character(0)) leaked a bare "subscript out of bounds".
# It runs *before* need_pkg() so that a malformed call is reported as one
# whether or not the optional client happens to be installed -- which also
# keeps the test for it from having to be skipped on a machine without them.
check_indicator <- function(indicator, call = rlang::caller_env()) {
  if (!length(indicator) || !is.character(indicator)) {
    wdj_abort("{.arg indicator} must be a non-empty character vector.", call = call)
  }
  invisible(indicator)
}

# `top_n = Inf` is the documented way to say "no limit", so check_number() --
# which rejects non-finite values outright -- cannot validate it. Guarding with
# is.finite() alone was worse: everything is.finite() rejects then skipped
# validation entirely, so top_n = "5" and top_n = NA silently returned every row
# instead of five, and top_n = NULL failed on `if` with R's bare "argument is of
# length zero", naming neither the argument nor the function.
check_top_n <- function(x, arg = "top_n", call = rlang::caller_env()) {
  if (!is.numeric(x) || length(x) != 1L || is.na(x) || x < 1) {
    wdj_abort(c(
      "{.arg {arg}} must be a single number of at least 1, or {.code Inf} for
       no limit.",
      "x" = "Got {.val {x}}."
    ), call = call)
  }
  invisible(x)
}

# One row per country, without collapsing the countries that have no code.
# dplyr::distinct() treats NA as a value, so de-duplicating on iso3c alone folds
# every uncoded row into a single one: audit_coverage() named one unmatched
# country out of four (and divided every na_rate by the wrong n), while
# rate_check() and world_table() quietly returned three rows for a five-row
# input. Coded rows de-duplicate on the code; uncoded ones are not duplicates of
# each other, so they de-duplicate on whatever else identifies them -- which
# still keeps the polygon backend from counting one country once per vertex.
distinct_countries <- function(df, arg = "data") {
  if (!"iso3c" %in% names(df)) return(df)
  # Collapsing to one row per country is for repeated *geometry* rows, not for
  # time: handed a panel it keeps whichever row sorts first and presents that
  # year as the answer, with nothing to say a choice was made. Same class as
  # world_map()'s panel warning, so the verbs built for a panel can muffle it.
  if ("year" %in% names(df)) {
    yrs <- unique(stats::na.omit(df$year))
    if (length(yrs) > 1L) {
      wdj_warn(c(
        "{.arg {arg}} spans {length(yrs)} years, and this verb takes one row
         per country.",
        "x" = "Only the earliest year of each country is used; the rest are
               dropped.",
        "i" = "Filter to the year you mean first."
      ), class = "countryatlas_panel")
    }
  }
  na_rows <- is.na(df$iso3c)
  coded <- df[!na_rows, , drop = FALSE]
  # The warning above promises "only the earliest year of each country is
  # used", but distinct(.keep_all = TRUE) keeps whichever row comes *first in
  # the frame* -- which is the earliest year only if the caller happened to
  # sort by year. Shuffle the same panel and rate_check() returned a different
  # numerator for France, world_map() drew a different year, and nothing said
  # so. Pick the earliest year explicitly, and keep the survivors in their
  # original relative order so nothing downstream sees a reordered frame.
  if ("year" %in% names(coded) && nrow(coded)) {
    # order() on a factor sorts by level index, not by the label, so a factored
    # `year` (read.csv(stringsAsFactors = TRUE), or one factored for plotting)
    # with levels 2002 < 2001 < 2000 would hand back the *latest* year while
    # the warning still said "earliest". Compare years as numbers where they
    # are numbers, and fall back to the labels where they are not.
    yr <- coded$year
    if (is.factor(yr)) yr <- as.character(yr)
    if (is.character(yr)) {
      num <- suppressWarnings(as.numeric(yr))
      if (!all(is.na(num))) yr <- num
    }
    ord <- order(coded$iso3c, yr, na.last = TRUE)
    keep <- ord[!duplicated(coded$iso3c[ord])]
    coded <- coded[sort(keep), , drop = FALSE]
  } else {
    coded <- dplyr::distinct(coded, .data$iso3c, .keep_all = TRUE)
  }
  unc <- df[na_rows, , drop = FALSE]
  ukey <- intersect(c("country", "group"), names(unc))
  if (length(ukey) && nrow(unc)) {
    unc <- dplyr::distinct(unc, .data[[ukey[1]]], .keep_all = TRUE)
  }
  dplyr::bind_rows(coded, unc)
}

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
  # rlang::as_name() on anything that is not a symbol or a string throws its own
  # error -- "Can't convert a double vector to a string", or for `gdp + 1` the
  # even less helpful "Can't convert a call to a string". That names neither the
  # argument nor the function nor what was expected, and it reached the user
  # from all ~66 places this helper is called: every unquoted column argument in
  # the package. `world_map(d, gdp_per_capita + 1)` is a natural thing to try.
  expr <- rlang::quo_get_expr(quo)
  if (!rlang::is_symbol(expr) && !rlang::is_string(expr)) {
    shown <- paste(deparse(expr), collapse = " ")
    # Built as plain strings and interpolated whole: cli does not re-interpolate
    # a substituted value, whereas nesting {arg} inside {.code ...} here mangled
    # the message.
    hint <- if (rlang::is_call(expr, "$") && identical(expr[[2]], quote(.data))) {
      sprintf("Name the column directly: %s = %s.", arg,
              paste(deparse(expr[[3]]), collapse = " "))
    } else if (rlang::is_call(expr)) {
      sprintf(paste("Expressions are not evaluated here. Compute the column",
                    "first -- dplyr::mutate(data, my_col = %s) -- then pass",
                    "%s = my_col."), shown, arg)
    } else {
      sprintf("Pass the column unquoted (%s = my_col) or as a string.", arg)
    }
    wdj_abort(c("{.arg {arg}} must name a column, not {.code {shown}}.",
                "i" = "{hint}"), call = call)
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
  # Clamp to at least one. Every branch above already guarantees it, and then
  # min(workers, n_tasks) undid the guarantee for n_tasks = 0 -- returning a
  # worker count of zero, which is what `mc.cores` refuses. wdj_lapply() happens
  # to short-circuit an empty input before it gets here, so nothing hits it
  # today; the point is that the contract this function documents should not
  # depend on its only caller remembering to.
  as.integer(max(1L, min(workers, n_tasks)))
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
    # "{msg}", not msg: a bullet is a cli template, so a brace in the worker's
    # own message got interpolated. A FUN failing with "bad json {\"a\": 1}"
    # reported "Could not evaluate cli `{}` expression: `\"a\"`" and the real
    # failure was gone. Interpolating the value passes it through verbatim.
    wdj_abort(c("Parallel computation failed.", "x" = "{msg}"))
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

# The European microstates have no polygon in Natural Earth at 110m, so they
# contribute nothing to country_borders() / neighbors() at the default scale.
# Both lists are pinned by a test against scale = "medium", which does have
# them, so a Natural Earth update cannot leave these silently stale.
WDJ_MICROSTATES <- c("AND", "LIE", "MCO", "SMR", "VAT")
WDJ_MICROSTATE_NEIGHBOURS <- list(
  AUT = "LIE", CHE = "LIE", ESP = "AND", FRA = c("AND", "MCO"),
  ITA = c("SMR", "VAT")
)

# "1 country" / "240 countries", for the plain-text captions and print blocks
# that cannot use cli's {?s}. sprintf() alone gave "All 1 countries shown."
countries_noun <- function(n) if (isTRUE(n == 1L)) "country" else "countries"

# A year arrives as a number, a Date, or a string, and the source decides
# which. Providers disagree and `...` forwards to their client, so a caller
# can change it: eurostat's time_format = "num" gives a
# numeric year, "raw" a character one, the default a Date. OECD's Time is
# usually a character year, sometimes "2020-Q1", occasionally a Date. Reading
# each with a single assumption failed either loudly or -- worse -- quietly:
# format(numeric, "%Y") is base R's opaque "invalid 'trim' argument", while
# as.integer() on a Date returned 18262, the day count, as the year. The
# same assumption sat in audit_time_coverage(), where a Date year column
# turned the whole existence audit into nonsense.
read_year <- function(x, source_label) {
  yr <- if (inherits(x, "Date") || inherits(x, "POSIXt")) {
    as.integer(format(x, "%Y"))
  } else {
    # "2020", "2020-01-01", "2020-Q1", "2020M01" and numeric 2020 all lead
    # with the four-digit year.
    suppressWarnings(as.integer(substr(as.character(x), 1L, 4L)))
  }
  # Two ways to be unusable, and both were silent: a value that parsed to
  # something implausible (a Date read as 18262), and one that did not parse at
  # all ("junk" -> NA). Turning a whole column of either into NA without a word
  # leaves a panel with no years and no explanation.
  bad <- (!is.na(yr) & (yr < 1500L | yr > 2200L)) | (!is.na(x) & is.na(yr))
  if (any(bad)) {
    wdj_warn(c(
      "{source_label}: {sum(bad)} time value{?s} {?is/are} not a year and
       {?is/are} dropped.",
      "*" = "{.val {unique(as.character(x)[bad])[1:min(4L, sum(bad))]}}",
      "i" = "Expected a year, a date, or a string starting with one."
    ), class = "countryatlas_bad_year")
    yr[bad] <- NA_integer_
  }
  yr
}

