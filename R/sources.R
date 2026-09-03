# Data sources beyond the World Bank ---------------------------------------------
#
# The ISO spine is source-agnostic by design, but until now only WDI was wired.
# The fix is a contract, not N bespoke fetchers: register_country_source() lets
# any provider -- including the several that are not on CRAN, and any internal or
# proprietary feed -- become a first-class source without the package depending
# on it. Four built-in adapters ship for discoverability.
#
# The differentiating verb is compare_sources(). Anyone can call owidR. What
# nobody does is tell you that OWID and the World Bank disagree about GDP per
# capita for fourteen countries because of different vintages, PPP bases or
# territorial definitions. On the ISO spine that comparison is one join, and it
# is exactly the class of quiet error this package exists to prevent.

# The registry. An environment rather than a list so registration from a user's
# .Rprofile or another package persists for the session.
the_sources <- new.env(parent = emptyenv())

#' Register a data source on the country spine
#'
#' Teach `countryatlas` where to get indicators from. A source is a name plus a
#' `fetch` function; once registered it works with [fetch_indicator()],
#' [add_indicator()] and [compare_sources()] exactly like the built-in ones.
#'
#' This is deliberately a registry rather than more `Suggests`. It means a
#' provider with no CRAN package -- V-Dem, the IMF, the World Inequality
#' Database -- is reachable without this package depending on anything, and it
#' means an internal or proprietary feed is a first-class citizen.
#'
#' @param name Short source name, used everywhere else (e.g. `"wdi"`).
#' @param fetch A function `(indicator, countries, years)` returning a tidy data
#'   frame. See the contract below.
#' @param meta Optional one-line description of the provider.
#' @param citation Optional citation string; surfaced by [country_sources()] so
#'   users can credit the data.
#' @param key_col The country-key column `fetch` returns (default `"iso3c"`).
#'   A column *name*, not a coding scheme.
#' @param key_type How to read that column: any [countrycode::countrycode()]
#'   origin scheme (default `"iso3c"`). Set it to `"country.name"` for a source
#'   keyed on country names.
#' @param cache Whether results should be memoised for the session
#'   (default `TRUE`).
#'
#' @return Invisibly, the source name.
#'
#' @section The fetch contract:
#' `fetch(indicator, countries, years)` must return a data frame with:
#' * a country key column (named `key_col`, holding `key_type` values --
#'   normally an `iso3c` column of `iso3c` codes),
#' * a `year` column (integer) *if* the data is a panel,
#' * one column per requested indicator, named after the indicator, and
#' * one row per key -- `iso3c` for a cross-section, `iso3c` and `year` for a
#'   panel.
#'
#' The key has to be unique because [add_indicator()] joins on it: a repeated
#' key multiplies the caller's rows, so it is reported rather than joined in
#' silence. Aggregate before returning if the provider serves several rows per
#' country-year.
#'
#' `countries` is a character vector of `iso3c` codes or `NULL` for all;
#' `years` is a numeric vector or `NULL` for the provider's default. Returning
#' extra columns is fine -- they travel through. Anything the provider cannot
#' serve should come back as `NA`, not as a missing row, wherever that is
#' cheap to arrange.
#'
#' @seealso [country_sources()], [fetch_indicator()], [compare_sources()]
#' @export
#' @examples
#' # A trivial in-memory source
#' register_country_source(
#'   "demo",
#'   fetch = function(indicator, countries = NULL, years = NULL) {
#'     data.frame(iso3c = c("USA", "FRA"), year = 2020L, demo_value = c(1, 2))
#'   },
#'   meta = "A toy source for the examples"
#' )
#' country_sources()
#' fetch_indicator("demo", "demo_value")
#'
#' # A source keyed on country names rather than codes: `key_col` says which
#' # column holds the key, `key_type` says how to read it.
#' register_country_source(
#'   "demo_named",
#'   fetch = function(indicator, countries = NULL, years = NULL) {
#'     data.frame(country = c("United States", "Japan"), year = 2020L,
#'                demo_value = c(3, 4))
#'   },
#'   key_col = "country", key_type = "country.name",
#'   meta = "A toy name-keyed source"
#' )
#' fetch_indicator("demo_named", "demo_value")
register_country_source <- function(name, fetch, meta = NULL, citation = NULL,
                                    key_col = "iso3c", key_type = "iso3c",
                                    cache = TRUE) {
  check_string(name, "name")
  check_string(key_col, "key_col")
  check_string(key_type, "key_type")
  check_bool(cache, "cache")
  if (!is.function(fetch)) {
    wdj_abort(c("{.arg fetch} must be a function.",
                "x" = "Got {.cls {class(fetch)[1]}}.",
                "i" = "See the {.strong fetch contract} in
                       {.help countryatlas::register_country_source}."))
  }
  if (!is.null(meta)) check_string(meta, "meta")
  if (!is.null(citation)) check_string(citation, "citation")
  # Fail where the mistake was made. Left to fetch time, a bad scheme surfaced
  # only once a request had already been paid for, and pointed at
  # fetch_indicator() rather than at this call.
  wdj_to_iso3c("France", origin = key_type, call = rlang::caller_env(),
               arg = "key_type")
  # Re-registering a name replaces the source, so its memoised answers describe
  # a fetch function that no longer exists. The cache key hashes the indicator,
  # countries and years but not `fetch`, so correcting a broken adapter and
  # registering it again kept serving the broken result -- which is precisely
  # what someone developing an adapter does, over and over, in one session.
  drop_source_memo(name)
  assign(name, list(name = name, fetch = fetch, meta = meta,
                    citation = citation, key_col = key_col,
                    key_type = key_type, cache = cache),
         envir = the_sources)
  invisible(name)
}

#' The registered data sources
#'
#' What [fetch_indicator()] can reach, whether each one's backing package is
#' actually installed, and how to cite it.
#'
#' @return A tibble: `source`, `meta`, `key_col`, `key_type`, `cache`,
#'   `available` (is the
#'   backing package installed?) and `citation`.
#' @seealso [register_country_source()], [fetch_indicator()]
#' @export
#' @examples
#' country_sources()
country_sources <- function() {
  nms <- sort(ls(the_sources))
  if (!length(nms)) {
    return(tibble::tibble(source = character(0), meta = character(0),
                          key_col = character(0), key_type = character(0),
                          cache = logical(0),
                          available = logical(0), citation = character(0)))
  }
  rows <- lapply(nms, function(n) {
    s <- get(n, envir = the_sources)
    tibble::tibble(
      source = s$name, meta = s$meta %||% NA_character_, key_col = s$key_col,
      key_type = s$key_type %||% "iso3c",
      cache = s$cache, available = source_available(s$name),
      citation = s$citation %||% NA_character_
    )
  })
  dplyr::bind_rows(rows)
}

# Is the backing package for a built-in source installed? A user-registered
# source has no package to check, so it is always available.
#
# pkg_installed() rather than has_pkg(): country_sources() reports on every
# source at once and calls none of them, so loading five namespaces to answer a
# question about installation is both wasteful and -- for comtradr, which
# creates a cache directory in .onLoad -- a write to the user's home filespace.
source_available <- function(name) {
  pkg <- switch(name, wdi = "WDI", owid = "owidR", eurostat = "eurostat",
                oecd = "OECD", comtrade = "comtradr", NULL)
  if (is.null(pkg)) TRUE else pkg_installed(pkg)
}

get_source <- function(source, call = rlang::caller_env()) {
  check_string(source, "source", call = call)
  if (!exists(source, envir = the_sources, inherits = FALSE)) {
    known <- sort(ls(the_sources))
    wdj_abort(c(
      "Unknown source {.val {source}}.",
      "i" = "Registered: {.val {known}}.",
      "*" = "Add your own with {.fn register_country_source}."
    ), call = call)
  }
  get(source, envir = the_sources)
}

#' Fetch an indicator from any registered source
#'
#' One verb, many providers. Whatever the source, the result comes back on the
#' ISO spine: `iso3c`, `year` where the data is a panel, and one column per
#' indicator.
#'
#' @param source A registered source name (see [country_sources()]).
#' @param indicator Indicator code(s). Name the vector to rename the columns,
#'   as in [world_data()]: `c(gdp = "NY.GDP.PCAP.KD")`.
#' @param countries Optional `iso3c` vector; `NULL` (default) for all.
#' @param years Optional numeric year vector; `NULL` for the provider's default.
#' @param ... Passed to the source's own `fetch` function.
#'
#' @return A tibble keyed on `iso3c` (and `year`, for a panel).
#' @seealso [add_indicator()], [compare_sources()], [country_sources()]
#' @export
#' @examples
#' \dontrun{
#' fetch_indicator("wdi", c(gdp = "NY.GDP.PCAP.KD"), years = 2020)
#' fetch_indicator("owid", "life_expectancy", years = 2020)
#' }
fetch_indicator <- function(source, indicator, countries = NULL, years = NULL,
                            ...) {
  s <- get_source(source)
  check_indicator(indicator)
  if (!is.null(countries)) {
    countries <- wdj_to_iso3c(countries, origin = "iso3c")
    countries <- unique(stats::na.omit(countries))
  }
  if (!is.null(years)) years <- validate_years(years)

  # `cache` was stored in the registry and reported by country_sources(), but
  # nothing ever read it -- the documented "results should be memoised for the
  # session" simply did not happen, in either direction. Memoise here, keyed on
  # everything that can change the answer.
  # The source name stays in plaintext so clear_country_cache(source = ) can
  # drop just that source's entries without unhashing anything.
  key <- if (isTRUE(s$cache)) {
    paste0(source, "\r", rlang::hash(list(indicator, countries, years, list(...))))
  } else NULL
  hit <- if (is.null(key)) NULL else .wdj_state$source_memo[[key]]
  out <- if (!is.null(hit)) hit else {
    s$fetch(indicator = indicator, countries = countries, years = years, ...)
  }
  if (!is.data.frame(out)) {
    wdj_abort(c(
      "Source {.val {source}} returned {.cls {class(out)[1]}}, not a data frame.",
      "i" = "See the {.strong fetch contract} in
             {.help countryatlas::register_country_source}."
    ))
  }
  out <- tibble::as_tibble(out)
  if (!s$key_col %in% names(out)) {
    wdj_abort(c(
      "Source {.val {source}} returned no {.field {s$key_col}} column.",
      "i" = "Columns were {.val {names(out)}}."
    ))
  }
  # Standardise even when the source declares key_type = "iso3c": that is the
  # source's claim, not a guarantee, and this is the public extension point.
  # Trusting it let lowercase codes ("usa") through unchanged, kept a factor a
  # factor, and passed numeric UN M49 codes (840) along as numbers -- each
  # producing a frame that silently matched nothing downstream. wdj_to_iso3c()
  # is a no-op on codes that are already right.
  raw_key <- out[[s$key_col]]
  # origin = key_type, not key_col. key_col is a column *name*, and feeding it
  # to countrycode as a coding scheme meant the only registrations that worked
  # were the ones whose column happened to be named after a scheme: all five
  # builtins use the "iso3c" default, which short-circuits before countrycode,
  # so nothing here ever exercised it, and the first source registered with
  # key_col = "country" died inside countrycode() on an `origin` the caller
  # never passed.
  out$iso3c <- wdj_to_iso3c(raw_key, origin = s$key_type %||% "iso3c")
  # Standardisation can also *merge* keys: "United States" and "USA" both reach
  # USA, and add_indicator() then joins that twice, so a caller's two-row frame
  # came back with three rows and one country holding two different values --
  # silently, because dplyr only warns on many-to-many, not one-to-many.
  # join_world() has warned about exactly this since it gained
  # warn_key_collapse(); the source adapters never did.
  collapsed <- warn_key_collapse(
    raw_key, out$iso3c, sprintf("source %s", encodeString(source, quote = '"')),
    s$key_col, "iso3c",
    hint = "Aggregate the source's rows to one per country, or the join in
            {.fn add_indicator} will repeat them."
  )
  # warn_key_collapse() above only sees a code reached from *more than one*
  # raw value -- that is what it is for. A source that simply returns the same
  # key twice collapses nothing, so it said nothing, and add_indicator()'s join
  # fanned the caller's frame out anyway: two rows in, three out, one country
  # holding two different values. Check the standardised key itself, which
  # catches both shapes.
  # Skip whatever the collapse check just reported: a collapsed key is also a
  # repeated one, so counting it here as well warned twice about one problem.
  key_cols <- c("iso3c", if ("year" %in% names(out)) "year")
  countable <- !is.na(out$iso3c) & !(out$iso3c %in% collapsed)
  n_dup <- sum(duplicated(out[countable, key_cols, drop = FALSE]))
  if (n_dup) {
    wdj_warn(c(
      "Source {.val {source}} returned {n_dup} duplicate key row{?s}.",
      "*" = "Keyed on {.field {key_cols}}.",
      "i" = "Aggregate the source's rows to one per key, or the join in
             {.fn add_indicator} will repeat them."
    ), class = "countryatlas_duplicate_key")
  }
  unresolved <- unique(as.character(raw_key)[is.na(out$iso3c) & !is.na(raw_key)])
  if (length(unresolved)) {
    # Silent NA keys are the failure this whole function exists to prevent: the
    # rows survive, join to nothing, and read as "the provider has no data".
    wdj_warn(c(
      "Source {.val {source}} returned {length(unresolved)} value{?s} that
       {?is/are} not usable as {.field {s$key_col}}.",
      "*" = "{.val {utils::head(unresolved, 6)}}",
      "i" = "Those rows carry {.val NA} for {.field iso3c} and will not join.",
      if (identical(s$key_type %||% "iso3c", "iso3c")) {
        c("i" = "This source is registered as {.code key_type = \"iso3c\"}. If
                 {.field {s$key_col}} holds country names, register it with
                 {.code key_type = \"country.name\"}.")
      }
    ), class = "countryatlas_bad_key")
  }
  # read_year(), not as.integer(): this is the public extension point, so
  # the year is whatever a third-party fetch function returned. as.integer()
  # read a Date as its day count and a "2020-Q1" as NA, both without comment.
  if ("year" %in% names(out)) out$year <- read_year(out$year, "Source {.val {source}}")
  # Only a non-empty answer is worth remembering: an empty one is as likely to
  # be a failed request as a real "no observations", and it is cheap to retry.
  if (!is.null(key) && is.null(hit) && nrow(out)) {
    if (is.null(.wdj_state$source_memo)) .wdj_state$source_memo <- list()
    .wdj_state$source_memo[[key]] <- out
  }
  out
}

#' Fetch an indicator and join it to your data
#'
#' [fetch_indicator()] plus [country_join()] in one step: pull an indicator from
#' any registered source and attach it to a frame you already have, matched on
#' the ISO spine (and on `year` too, when both sides are panels).
#'
#' @param data A frame with `iso3c` (or a country column [join_world()] would
#'   recognise).
#' @param source,indicator,countries,years,... Passed to [fetch_indicator()].
#'   `countries` defaults to the codes already in `data`, so only what you need
#'   is fetched.
#'
#' @return `data` with the indicator column(s) added.
#' @seealso [fetch_indicator()], [country_join()]
#' @export
#' @examples
#' \dontrun{
#' world_snapshot$countries |>
#'   add_indicator("wdi", c(unemployment = "SL.UEM.TOTL.ZS"), years = 2020)
#' }
add_indicator <- function(data, source, indicator, countries = NULL,
                          years = NULL, ...) {
  if (!"iso3c" %in% names(data)) {
    wdj_abort(c(
      "{.arg data} must contain an {.field iso3c} column.",
      "i" = "Standardise first with {.fn standardize_country} or {.fn join_world}."
    ))
  }
  countries <- countries %||% unique(stats::na.omit(data$iso3c))
  new <- fetch_indicator(source, indicator, countries = countries,
                         years = years, ...)
  carry_year <- FALSE
  by <- if (all(c("year", "iso3c") %in% names(data)) && "year" %in% names(new)) {
    c("iso3c", "year")
  } else {
    # A panel joined to a single-year fetch would fan out; drop the fetch's year
    # column instead so the value is broadcast, which is what the caller means.
    # But only when there really is one year. Dropping it unconditionally meant
    # a cross-section joined to a three-year fetch came back with three rows
    # per country -- the same `gdp` repeated against values whose year had just
    # been deleted, so nothing said which year any of them was. The keys never
    # collapse here, so the collapse check cannot see it either.
    if ("year" %in% names(new)) {
      yrs <- unique(stats::na.omit(new$year))
      if (length(yrs) <= 1L) new$year <- NULL else carry_year <- TRUE
    }
    "iso3c"
  }
  # Drop the source's own key column too. The setdiff named only "iso3c", so a
  # source keyed on any other column handed that raw column to the caller as
  # though it were requested data -- a stray `country` column appearing in a
  # frame that already had iso3c. Invisible while every builtin used the
  # "iso3c" default.
  key_col <- tryCatch(get_source(source)$key_col, error = function(e) NULL)
  add_cols <- setdiff(names(new),
                      c(by, "iso3c", if (!carry_year) "year", key_col))
  if (carry_year) {
    wdj_warn(c(
      "Source {.val {source}} returned {length(yrs)} years and {.arg data} has
       no {.field year} column, so {.arg data} gains a row per year.",
      "i" = "Pass {.arg years} to ask for one year, or add a {.field year}
             column to {.arg data} to join on it."
    ), class = "countryatlas_year_fanout")
  }
  warn_overwrite(data, add_cols)
  # Actually overwrite, which is what that warning promises. left_join() instead
  # suffixes both sides to `x.x` and `x.y`, so a caller whose frame already held
  # the indicator name got neither the column they asked for nor the one they
  # had -- and were advised to "rename them first to keep the original values"
  # by a message describing a mechanism that was not running.
  clash <- intersect(add_cols, names(data))
  if (length(clash)) {
    data <- data[, setdiff(names(data), clash), drop = FALSE]
  }
  out <- dplyr::left_join(data, new[, unique(c(by, add_cols)), drop = FALSE],
                          by = by, na_matches = "never")
  # A key that is not standardised matches nothing, so the indicator arrives as
  # a column of pure NA -- which reads as "the provider has no data" rather than
  # "the join failed". Only worth saying when the fetch itself returned rows.
  if (nrow(new) && length(add_cols) &&
      !any(vapply(add_cols, function(cl) any(!is.na(out[[cl]])), logical(1)))) {
    wdj_warn(c(
      "{.arg source} returned {nrow(new)} row{?s}, none of which joined to
       {.arg data}.",
      "x" = "{length(add_cols)} added column{?s} came back entirely
             {.val {NA}}: {.val {add_cols}}.",
      "i" = "Check that {.field iso3c} is standardised;
             {.fn standardize_country} normalises case and whitespace."
    ))
  }
  out
}

#' Do two sources agree?
#'
#' Fetch the same indicator from several providers and put the answers side by
#' side. Sources disagree more often than people expect -- different vintages,
#' PPP bases, territorial definitions, revision schedules -- and on the ISO spine
#' the comparison is one join. This is the verb that turns "I used OWID" into "I
#' used OWID, and here is where it differs from the World Bank".
#'
#' @param indicator Either one indicator code used for every source, or a named
#'   character vector giving each source its own code:
#'   `c(wdi = "NY.GDP.PCAP.KD", owid = "gdp_per_capita")`.
#' @param sources Source names to compare (default `c("wdi", "owid")`).
#' @param year A single year.
#' @param countries Optional `iso3c` subset.
#' @param tolerance Relative difference above which a country counts as a
#'   disagreement (default `0.05`, i.e. 5%).
#'
#' @return A tibble with one row per country: the value from each source,
#'   `n_sources` (how many reported it), `rel_diff` (max relative spread) and
#'   `disagrees`. The correlation, coverage and disagreement summary is attached
#'   as the `"countryatlas_source_summary"` attribute.
#'
#' @seealso [fetch_indicator()], [country_sources()]
#' @export
#' @examples
#' \dontrun{
#' cmp <- compare_sources(c(wdi = "NY.GDP.PCAP.KD", owid = "gdp_per_capita"),
#'                        sources = c("wdi", "owid"), year = 2020)
#' attr(cmp, "countryatlas_source_summary")
#' }
compare_sources <- function(indicator, sources = c("wdi", "owid"), year,
                            countries = NULL, tolerance = 0.05) {
  if (missing(year)) wdj_abort("{.arg year} is required.")
  year <- validate_years(year)
  if (length(year) != 1L) {
    wdj_abort("{.arg year} must be a single year; got {length(year)}.")
  }
  check_number(tolerance, "tolerance", lo = 0)
  if (length(sources) < 2L) {
    wdj_abort("{.arg sources} must name at least two sources to compare.")
  }
  codes <- if (!is.null(names(indicator))) {
    missing_src <- setdiff(sources, names(indicator))
    if (length(missing_src)) {
      wdj_abort(c("{.arg indicator} names no code for {.val {missing_src}}.",
                  "i" = "Give every source a code, or pass a single unnamed code."))
    }
    indicator[sources]
  } else {
    # The named branch above already tells callers to "pass a single unnamed
    # code", but nothing enforced it: an unnamed vector was silently truncated
    # to its first element and broadcast to every source. That is the worst
    # possible failure for this verb -- it then compares a code against itself
    # and reports the sources as agreeing perfectly.
    if (length(indicator) != 1L) {
      wdj_abort(c(
        "An unnamed {.arg indicator} must be a single code, used for every
         source.",
        "x" = "Got {length(indicator)}: {.val {indicator}}.",
        "i" = "To give each source its own code, name them:
               {.code c({sources[1]} = \"...\", {sources[2]} = \"...\")}."
      ))
    }
    stats::setNames(rep(indicator[1], length(sources)), sources)
  }

  vals <- lapply(sources, function(s) {
    d <- fetch_indicator(s, stats::setNames(codes[[s]], s), countries = countries,
                         years = year)
    # !is.na() first: read_year() deliberately puts NA in this column for a
    # time value it could not parse, and d[NA, ] appends a row of all-NA --
    # a phantom country with no iso3c that then survived the join into the
    # comparison table.
    if ("year" %in% names(d)) d <- d[!is.na(d$year) & d$year == year, ]
    keep <- intersect(c("iso3c", s), names(d))
    if (!s %in% keep) {
      # A source that renamed the column: take the first non-key numeric one.
      num <- names(d)[vapply(d, is.numeric, logical(1))]
      num <- setdiff(num, c("year"))
      if (!length(num)) wdj_abort("Source {.val {s}} returned no numeric column.")
      d[[s]] <- d[[num[1]]]
    }
    dplyr::distinct(d[, c("iso3c", s)], .data$iso3c, .keep_all = TRUE)
  })
  out <- Reduce(function(a, b) dplyr::full_join(a, b, by = "iso3c",
                                         na_matches = "never"), vals)

  mat <- as.matrix(out[, sources, drop = FALSE])
  out$n_sources <- rowSums(!is.na(mat))
  rng <- t(apply(mat, 1, function(r) {
    r <- r[!is.na(r)]
    if (length(r) < 2L) return(c(NA_real_, NA_real_))
    c(min(r), max(r))
  }))
  denom <- pmax(abs(rng[, 1]), abs(rng[, 2]))
  out$rel_diff <- ifelse(denom > 0, (rng[, 2] - rng[, 1]) / denom, 0)
  out$rel_diff[out$n_sources < 2L] <- NA_real_
  out$disagrees <- !is.na(out$rel_diff) & out$rel_diff > tolerance
  out <- dplyr::arrange(out, dplyr::desc(.data$rel_diff))

  pairs <- utils::combn(sources, 2, simplify = FALSE)
  summ <- dplyr::bind_rows(lapply(pairs, function(pp) {
    a <- out[[pp[1]]]; b <- out[[pp[2]]]
    ok <- !is.na(a) & !is.na(b)
    # Pairwise, like every other column in this table. It used to read the
    # row-wise `out$disagrees`, which is the spread across *all* sources: with
    # three or more, a pair that agreed exactly was still counted as disagreeing
    # whenever some third source was the outlier. For two values the global
    # formula reduces to |a - b| / max(|a|, |b|), so the two agree when they
    # should.
    denom_p <- pmax(abs(a), abs(b))
    d <- ifelse(ok & denom_p > 0, abs(a - b) / denom_p, 0)
    tibble::tibble(
      source_x = pp[1], source_y = pp[2], n_both = sum(ok),
      only_x = sum(!is.na(a) & is.na(b)), only_y = sum(is.na(a) & !is.na(b)),
      # A source that reports one value for every country has zero variance, so
      # cor() returns NA *and* warns. The NA is the right answer; the warning is
      # internal noise about a legitimate input, so decide it explicitly.
      correlation = if (sum(ok) > 2L && stats::sd(a[ok]) > 0 && stats::sd(b[ok]) > 0) {
        stats::cor(a[ok], b[ok])
      } else NA_real_,
      n_disagree = sum(ok & d > tolerance, na.rm = TRUE)
    )
  }))
  attr(out, "countryatlas_source_summary") <- summ
  out
}

# --- built-in adapters ----------------------------------------------------------
#
# Every one of these is a thin reshape onto the spine. We do not reimplement any
# client: the provider's own package does the HTTP and the parsing, and our job
# is the iso3c key, the column naming and the cache.

#' Built-in source adapters
#'
#' Thin wrappers that put a provider's data on the ISO spine. Each is
#' `Suggests`-gated on that provider's own client package -- `countryatlas` does
#' not reimplement any of them. All four are registered as sources, so the usual
#' route is [fetch_indicator()]`("owid", ...)` rather than calling these
#' directly; they are exported because calling them directly is sometimes what
#' you want.
#'
#' @param indicator Indicator code(s), optionally named to rename the output
#'   columns.
#' @param countries Optional `iso3c` vector.
#' @param years Optional numeric year vector.
#' @param ... Passed to the underlying client.
#'
#' @return A tibble on the ISO spine: `iso3c`, `year` and one column per
#'   indicator.
#'
#' @section Which provider needs what:
#' | Adapter | Needs | Notes |
#' | --- | --- | --- |
#' | `fetch_owid()` | `owidR` | Our World in Data; `indicator` is an OWID chart slug |
#' | `fetch_eurostat()` | `eurostat` | European coverage only; geo codes are harmonised to `iso3c` |
#' | `fetch_oecd()` | `OECD` | `indicator` is a dataset id; OECD's own filters go through `...` |
#' | `fetch_comtrade()` | `comtradr` | UN trade flows; needs an API token (see `comtradr::set_primary_comtrade_key()`) |
#'
#' @name source_adapters
#' @seealso [fetch_indicator()], [register_country_source()], [compare_sources()]
#' @examples
#' \dontrun{
#' fetch_owid("life-expectancy", years = 2020)
#' fetch_eurostat("demo_pjan", years = 2020)
#' }
NULL

#' @rdname source_adapters
#' @export
fetch_owid <- function(indicator, countries = NULL, years = NULL, ...) {
  check_indicator(indicator)
  need_pkg("owidR", "for fetch_owid()")
  nms <- names(indicator) %||% indicator
  frames <- lapply(seq_along(indicator), function(i) {
    got <- owidR::owid(indicator[[i]], ...)
    # owidR does not error when it cannot reach the site: it prints "site may be
    # down" and hands back a one-row blank data.table carrying the class
    # `owid.no.connection`. Left alone that surfaced downstream as "no numeric
    # value column found", which sends the reader hunting for the wrong problem.
    if (inherits(got, "owid.no.connection")) {
      wdj_abort(c(
        "Our World in Data could not be reached.",
        "x" = "{.pkg owidR} returned an empty result for {.val {indicator[[i]]}}.",
        "i" = "This is a connectivity or chart-slug problem, not a data problem.
               Check the slug at {.url https://ourworldindata.org/charts}."
      ))
    }
    adapter_reshape(tibble::as_tibble(got), nms[[i]], entity_col = "entity",
                    year_col = "year", countries = countries, years = years)
  })
  Reduce(function(a, b) dplyr::full_join(a, b, by = c("iso3c", "year"),
                                         na_matches = "never"), frames)
}

#' @rdname source_adapters
#' @export
fetch_eurostat <- function(indicator, countries = NULL, years = NULL, ...) {
  check_indicator(indicator)
  need_pkg("eurostat", "for fetch_eurostat()")
  nms <- names(indicator) %||% indicator
  frames <- lapply(seq_along(indicator), function(i) {
    raw <- tibble::as_tibble(eurostat::get_eurostat(indicator[[i]], ...))
    if ("TIME_PERIOD" %in% names(raw)) {
      raw$year <- read_year(raw$TIME_PERIOD, "Eurostat")
    }
    if ("time" %in% names(raw) && !"year" %in% names(raw)) {
      raw$year <- read_year(raw$time, "Eurostat")
    }
    adapter_reshape(raw, nms[[i]], entity_col = "geo", year_col = "year",
                    value_col = "values", countries = countries, years = years,
                    origin = "eurostat")
  })
  Reduce(function(a, b) dplyr::full_join(a, b, by = c("iso3c", "year"),
                                         na_matches = "never"), frames)
}

#' @rdname source_adapters
#' @export
fetch_oecd <- function(indicator, countries = NULL, years = NULL, ...) {
  check_indicator(indicator)
  need_pkg("OECD", "for fetch_oecd()")
  nms <- names(indicator) %||% indicator
  frames <- lapply(seq_along(indicator), function(i) {
    raw <- tibble::as_tibble(OECD::get_dataset(indicator[[i]], ...))
    if ("Time" %in% names(raw)) raw$year <- read_year(raw$Time, "OECD")
    if ("TIME_PERIOD" %in% names(raw) && !"year" %in% names(raw)) {
      raw$year <- read_year(raw$TIME_PERIOD, "OECD")
    }
    ent <- if ("LOCATION" %in% names(raw)) "LOCATION" else "REF_AREA"
    adapter_reshape(raw, nms[[i]], entity_col = ent, year_col = "year",
                    value_col = if ("ObsValue" %in% names(raw)) "ObsValue" else "obsValue",
                    countries = countries, years = years, origin = "iso3c")
  })
  Reduce(function(a, b) dplyr::full_join(a, b, by = c("iso3c", "year"),
                                         na_matches = "never"), frames)
}

#' @rdname source_adapters
#' @export
fetch_comtrade <- function(indicator, countries = NULL, years = NULL, ...) {
  check_indicator(indicator)
  need_pkg("comtradr", "for fetch_comtrade()")
  # One request per commodity, like the other three adapters. This used to read
  # indicator[[1]] and nothing else, so a two-commodity call quietly returned
  # one column -- against the documented "one column per indicator", and without
  # saying that the rest had been dropped.
  nms <- names(indicator) %||% indicator
  frames <- lapply(seq_along(indicator), function(i) {
    raw <- tibble::as_tibble(comtradr::ct_get_data(
      commodity_code = indicator[[i]],
      reporter = countries %||% "all_countries",
      start_date = if (!is.null(years)) min(years) else NULL,
      end_date = if (!is.null(years)) max(years) else NULL,
      ...
    ))
    ent <- intersect(c("reporter_iso", "reporterISO", "reporter_code"), names(raw))[1]
    val <- intersect(c("primary_value", "primaryValue", "trade_value"), names(raw))[1]
    yr <- intersect(c("period", "ref_year", "refYear"), names(raw))[1]
    # `yr` belongs in this guard alongside the other two: left out, a response
    # with no recognisable year column reached raw[[NA]] and failed with a bare
    # "subscript out of bounds" instead of naming the real problem.
    if (is.na(ent) || is.na(val) || is.na(yr)) {
      wdj_abort(c("comtradr returned an unexpected shape.",
                  "i" = "Columns were {.val {names(raw)}}."))
    }
    # read_year(), like the other two adapters: comtradr's `period` is a
    # bare year for annual data but YYYYMM for monthly, which `...` can select
    # via frequency = "monthly". as.integer() turned "202001" into the year
    # 202001, and a Date into 18262 -- both silently.
    raw$year <- read_year(raw[[yr]], "Comtrade")
    adapter_reshape(raw, nms[[i]], entity_col = ent, year_col = "year",
                    value_col = val, countries = countries, years = years,
                    origin = "iso3c")
  })
  Reduce(function(a, b) dplyr::full_join(a, b, by = c("iso3c", "year"),
                                         na_matches = "never"), frames)
}

# Common reshape for the adapters: resolve the provider's entity column to
# iso3c, pick the value column, subset, and name the result after the indicator.
adapter_reshape <- function(raw, out_name, entity_col, year_col,
                            value_col = NULL, countries = NULL, years = NULL,
                            origin = "country.name") {
  # Some clients answer a failed request with an empty frame and a message
  # rather than an error -- owidR returns a blank data.table and prints "site
  # may be down" -- which then surfaced here as the baffling "no numeric value
  # column found". Name the real problem.
  if (!nrow(raw)) {
    wdj_abort(c(
      "The provider returned no rows.",
      "i" = "This usually means the request did not reach the service, or the
             indicator code is wrong. Some clients report a failed download as
             an empty result rather than an error.",
      "*" = "Check connectivity and the indicator code, then retry."
    ))
  }
  if (!entity_col %in% names(raw)) {
    wdj_abort(c("Expected an entity column {.field {entity_col}}.",
                "i" = "Columns were {.val {names(raw)}}."))
  }
  value_col <- value_col %||% {
    num <- names(raw)[vapply(raw, is.numeric, logical(1))]
    num <- setdiff(num, year_col)
    if (!length(num)) wdj_abort("No numeric value column found in the response.")
    num[1]
  }
  # The auto-detected branch above can only name a column that exists, but
  # callers also pass value_col outright -- fetch_eurostat() hard-codes
  # "values", fetch_oecd() guesses between "ObsValue" and "obsValue". When the
  # provider changed shape, raw[[value_col]] was NULL and as.numeric(NULL) put a
  # zero-length column into a full-length tibble, failing several frames later
  # with a recycling error that named neither the provider nor the column.
  if (!value_col %in% names(raw)) {
    wdj_abort(c("Expected a value column {.field {value_col}}.",
                "i" = "Columns were {.val {names(raw)}}."))
  }
  # suppressWarnings deliberately: every OWID/Eurostat response carries
  # aggregate rows ("World", "EU27", "High-income countries") that are not
  # countries and never resolve, so wdj_to_iso3c()'s per-name warning would
  # fire on essentially every call. The cost is that a genuine typo or a
  # provider renaming its entities is swallowed with them -- which is fine
  # while *some* rows survive and the caller can see what came back, but not
  # when none do. That case is caught below.
  iso <- suppressWarnings(wdj_to_iso3c(raw[[entity_col]], origin = origin))
  out <- tibble::tibble(iso3c = iso,
                        year = if (year_col %in% names(raw)) {
                          read_year(raw[[year_col]], "The provider")
                        } else NA_integer_)
  # as.character() first for a factor: as.numeric() on one returns its *level
  # indices*, so a value column of factor("10", "20") became 1, 2 -- silently
  # wrong numbers from the provider. check_numeric_col() rejects a factor
  # outright with exactly this advice ("as.numeric(as.character(x))"), and its
  # comment notes how easily a factor column happens; the same care belongs
  # here, where the column comes from a third party rather than the caller.
  val <- raw[[value_col]]
  if (is.factor(val)) val <- as.character(val)
  num <- suppressWarnings(as.numeric(val))
  # as.numeric() turns text that is not a number into NA without complaint, so
  # a provider answering with "n/a" or ".." -- or renaming a column so the
  # value column now holds a label -- handed back a column of pure NA. That
  # reads as "the provider has no data for these countries", which is a very
  # different thing from "the response was not numeric". Count what the
  # coercion destroyed; a value the provider itself reported as missing is
  # already NA before this and is not counted.
  lost <- sum(!is.na(val) & is.na(num))
  if (lost > 0L) {
    bad <- unique(as.character(val)[!is.na(val) & is.na(num)])
    wdj_warn(c(
      "{lost} value{?s} in the provider's response {?is/are} not numeric and
       {?was/were} dropped.",
      "*" = "{.field {value_col}}: {.val {utils::head(bad, 4)}}",
      "i" = "They arrive as {.val NA}, which is indistinguishable from data the
             provider does not have."
    ), class = "countryatlas_unparsed_values")
  }
  out[[out_name]] <- num
  # Provider aggregates ("EU27", "World") have no iso3c and are not countries.
  unresolved <- unique(as.character(raw[[entity_col]])[is.na(iso)])
  out <- out[!is.na(out$iso3c), ]
  # Nothing resolved at all is never just aggregates: the entity column is the
  # wrong column, or the provider has renamed its entities. Returning an empty
  # frame in silence sent the reader looking at their own indicator code, while
  # the function goes to some trouble to explain an empty *input* a few lines
  # above.
  if (!nrow(out)) {
    wdj_abort(c(
      "None of the {length(unresolved)} entit{?y/ies} in
       {.field {entity_col}} resolved to a country.",
      "*" = "{.val {utils::head(unresolved, 6)}}",
      "i" = "Either {.field {entity_col}} is not the entity column, or the
             provider has changed how it names them. Pass {.arg origin} if they
             are codes rather than names."
    ), class = "countryatlas_no_entities")
  }
  if (!is.null(countries)) out <- out[out$iso3c %in% countries, ]
  if (!is.null(years)) out <- out[is.na(out$year) | out$year %in% years, ]
  # One row per country-year is the contract downstream joins rely on, so the
  # rest have to go -- but going in silence meant a provider answering with two
  # different values for one country-year handed back whichever sorted first,
  # order-dependently, and said nothing. Every other place this package drops
  # rows reports the count; this is the response of a third party, which is
  # more reason to, not less.
  before <- nrow(out)
  out <- dplyr::distinct(out, .data$iso3c, .data$year, .keep_all = TRUE)
  n_drop <- before - nrow(out)
  if (n_drop > 0L) {
    wdj_warn(c(
      "The provider returned {n_drop} duplicate country-year row{?s}, now
       dropped.",
      "i" = "The first row of each country-year is kept, so the rest of the
             response is discarded. Aggregate upstream if the duplicates carry
             meaning."
    ), class = "countryatlas_provider_duplicates")
  }
  out
}

# The WDI adapter, which is the one that already existed -- expressed through the
# same contract so it is not a special case.
fetch_wdi_source <- function(indicator, countries = NULL, years = NULL, ...) {
  years <- years %||% (as.integer(format(Sys.Date(), "%Y")) - 1L)
  out <- fetch_wdi(normalize_indicator(indicator), start = min(years),
                   end = max(years), ...)
  if (!is.null(countries)) out <- out[out$iso3c %in% countries, ]
  # min/max is right for the *request* -- the API takes a contiguous range --
  # but `years` is documented as a year vector, and the four other adapters
  # honour it as one (adapter_reshape filters on `year %in% years`). Without
  # the same filter here, years = c(2000, 2020) asked for two years and got
  # twenty-one, so the same argument meant different things depending on which
  # source you named.
  if ("year" %in% names(out)) {
    out <- out[is.na(out$year) | out$year %in% years, , drop = FALSE]
  }
  out
}

# Registered at load so the built-ins are present without the user doing
# anything. .onLoad lives in countryatlas-package.R and calls this.
# Drop a source's memoised answers. Keys are "<source>\r<hash>", the source
# name kept in plaintext exactly so it can be matched here.
drop_source_memo <- function(source) {
  memo <- .wdj_state$source_memo
  if (length(memo)) {
    .wdj_state$source_memo <-
      memo[names(memo)[!startsWith(names(memo), paste0(source, "\r"))]]
  }
  invisible(NULL)
}

register_builtin_sources <- function() {
  register_country_source(
    "wdi", fetch_wdi_source,
    meta = "World Bank World Development Indicators (via WDI)",
    citation = "World Bank. World Development Indicators."
  )
  register_country_source(
    "owid", fetch_owid,
    meta = "Our World in Data (via owidR)",
    citation = "Our World in Data. https://ourworldindata.org"
  )
  register_country_source(
    "eurostat", fetch_eurostat,
    meta = "Eurostat (via eurostat); European coverage only",
    citation = "Eurostat. https://ec.europa.eu/eurostat"
  )
  register_country_source(
    "oecd", fetch_oecd,
    meta = "OECD statistics (via OECD)",
    citation = "OECD. https://data.oecd.org"
  )
  register_country_source(
    "comtrade", fetch_comtrade,
    meta = "UN Comtrade bilateral trade (via comtradr); needs an API token",
    citation = "United Nations. UN Comtrade Database."
  )
  invisible(NULL)
}

#' Clear the cached downloads
#'
#' Empties the memoised in-session cache and, optionally, the on-disk one.
#'
#' @param source Which source's cache to clear, or `NULL` (default) for all.
#'   Only the World Bank cache is currently persisted to disk; other sources are
#'   memoised per session.
#' @param disk Also delete the on-disk cache (default `FALSE`).
#'
#' @return Invisibly `TRUE`.
#' @seealso [country_sources()], [fetch_indicator()]
#' @export
#' @examples
#' clear_country_cache()
clear_country_cache <- function(source = NULL, disk = FALSE) {
  check_bool(disk, "disk")
  if (!is.null(source)) get_source(source)          # validate the name
  # Registered sources memoise into .wdj_state$source_memo, under keys whose
  # first component is the source name; drop this source's entries, or all.
  if (is.null(source)) {
    .wdj_state$source_memo <- list()
  } else {
    drop_source_memo(source)
  }
  if (is.null(source) || identical(source, "wdi")) {
    return(invisible(clear_wdi_cache(disk = disk)))
  }
  invisible(TRUE)
}
