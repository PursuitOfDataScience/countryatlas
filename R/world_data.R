# Core data assembly ------------------------------------------------------------

# Per-country classification (income / region / continent), offline: income
# and region from the bundled, dated country_classifications as of the current
# fiscal year, continent from countrycode. Income and region used to come from
# the installed WDI's WDI_data, so they depended on which WDI release happened
# to be installed -- WDI 2.7.10 disagreed with the World Bank's own API for
# eight countries -- and nothing said which vintage a frame carried. The record
# now says so, through source_info().
country_classification <- function(iso3c, classify) {
  out <- tibble::tibble(iso3c = iso3c)
  at <- rep(classification_now(), length(iso3c))
  info <- list()
  if ("income" %in% classify) {
    inc <- classify_lookup(iso3c, at, "wb_income")
    # An economy the World Bank lists but has not given a group (no GNI
    # estimate) is "Not classified", WDI's own convention; a code it does not
    # list at all stays NA.
    listed <- !is.na(classify_lookup(iso3c, at, "wb_region"))
    inc[is.na(inc) & listed] <- "Not classified"
    out$income <- factor(inc, levels = income_levels())
  }
  if ("region" %in% classify) {
    out$region <- classify_lookup(iso3c, at, "wb_region")
  }
  if ("continent" %in% classify) {
    out$continent <- suppressWarnings(
      countrycode::countrycode(iso3c, "iso3c", "continent", warn = FALSE)
    )
  }
  out <- apply_code_fallback(out)
  vintage <- sprintf("FY%d", fiscal_year(classification_now()))
  cols <- intersect(c("income", "region"), classify)
  if (length(cols)) {
    out <- set_source_info(out, source_info_rows(
      cols, source = "World Bank classification",
      indicator = unname(CLASSIFICATION_SCHEMES[cols]),
      label = c(income = "Income group (GNI per capita, Atlas method)",
                region = "World Bank region")[cols],
      vintage = vintage, licence = "CC BY 4.0",
      citation = "World Bank. World Bank Country and Lending Groups."))
  }
  out
}

#' Map-ready, enriched country tibble
#'
#' The package's headline function, generalised but backward-compatible. Returns
#' a tibble that already stitches together map geometry, World Bank indicators
#' and the countrycode crosswalk, keyed on the ISO spine -- ready to pipe into
#' [world_map()] or `ggplot2`.
#'
#' `world_data(2020)` keeps its original behaviour (polygon backend, GDP per
#' capita). Everything else is opt-in: any indicator(s), a span of years (a
#' panel), an `sf` backend with real projections, and region subsetting.
#'
#' @param year A single year or a range (e.g. `2000:2020`, yielding a panel
#'   keyed on `iso3c` + `year`). Minimum 1960.
#' @param indicator A named character vector of WDI codes. Names drive column
#'   names, e.g. `c(gdp = "NY.GDP.PCAP.KD", pop = "SP.POP.TOTL")`. Defaults to
#'   `c(gdp_per_capita = "NY.GDP.PCAP.KD")`.
#' @param geometry `"polygon"` (default; reproduces the classic output), `"sf"`
#'   (Natural Earth, for `geom_sf()` and real projections) or `"none"`.
#' @param scale Natural Earth resolution for the `sf` backend. `"large"` needs the
#'   non-CRAN `rnaturalearthhires` package; see [world_geometry()]. The other
#'   backends warn if asked for a resolution they cannot serve.
#' @param region Optional subset: a continent, group name, `iso3c` vector or
#'   bounding box. Applied whichever `geometry` is used, including `"none"`. A
#'   bounding box clips the shapes rather than selecting whole countries, and
#'   only the `sf` backend can do that properly -- see [world_geometry()]; with
#'   `geometry = "none"` there is nothing to clip, so a box is refused.
#' @param classify Which classifications to add (any of `"income"`,
#'   `"continent"`, `"region"`).
#' @param projection,recenter Projection, and optional central meridian, for
#'   the `sf` backend (see [world_map()] for the projections available). The
#'   other backends warn if asked, rather than ignoring the request.
#' @param latest For a single-year request: `TRUE` takes each indicator's most
#'   recent non-`NA` value per country, and `"common"` the most recent year in
#'   which *every* requested indicator is present, so arithmetic across them is
#'   consistent. Either way each indicator gains an `<indicator>_year` column
#'   saying which year its value comes from. `FALSE` (default) pins the
#'   requested year.
#' @param cache Whether to use the memoised / on-disk WDI cache.
#' @param language WDI language code (default `"en"`).
#' @param vintage Which release of the World Development Indicators to read:
#'   `NULL` (default) for the current one, or an archived release such as
#'   `"2024-07"` from the World Bank's WDI Database Archives (see
#'   [wdi_vintages()]). An archived release never changes, so its cache
#'   entries never expire. A series the release does not hold warns and names
#'   the nearest releases that do.
#' @param parallel Whether to fetch multiple indicators in parallel. Ignored
#'   when the cache is memory-only (an unwritable `countryatlas.cache_dir`),
#'   because a forked worker's memo dies with it and nothing would be cached.
#' @param overrides Name -> iso3c overrides for geometry matching (default
#'   [country_overrides()]).
#'
#' @return A tibble (polygon backend), `sf` object (sf backend) or country-level
#'   tibble (`geometry = "none"`).
#'
#'   `iso3c` is the stable key; `country` is a *label* and its spelling depends on
#'   where the row came from. A successful fetch carries the World Bank's names
#'   ("Korea, Rep.", "Congo, Dem. Rep."), while the country spine used when the
#'   fetch returns nothing carries the `countrycode` names ("South Korea",
#'   "Congo - Kinshasa") -- as do [convert_country()], [standardize_country()]
#'   and the rest of the package. Match on `iso3c`, and relabel with
#'   `convert_country(iso3c, to = "country")` if you need one consistent set.
#' @export
#' @examples
#' \donttest{
#' # geometry = "polygon", the default, is bundled: nothing to install.
#' world_data(2020)
#'
#' # geometry = "none" returns the country table alone.
#' world_data(2020, indicator = c(life_exp = "SP.DYN.LE00.IN"),
#'            geometry = "none")
#' }
world_data <- function(year,
                       indicator = c(gdp_per_capita = "NY.GDP.PCAP.KD"),
                       geometry = c("polygon", "sf", "none"),
                       scale = c("small", "medium", "large"),
                       region = NULL,
                       classify = c("income", "continent", "region"),
                       projection = "equal_earth",
                       recenter = NULL,
                       latest = FALSE,
                       cache = TRUE,
                       language = "en",
                       parallel = TRUE,
                       overrides = country_overrides(),
                       vintage = NULL) {
  latest <- check_latest(latest)
  check_bool(cache, "cache")
  check_bool(parallel, "parallel")
  # "maps" passes through to attach_geometry(), deprecated on the caller's
  # behalf here.
  if (identical(geometry, "maps")) {
    user_env <- rlang::caller_env()
    deprecate_maps_geometry(user_env)
  } else {
    geometry <- rlang::arg_match(geometry)
  }
  scale <- rlang::arg_match(scale)
  year <- validate_years(year)
  # intersect() silently dropped anything unrecognised, so classify = "incomes"
  # added no classification columns and said nothing. Empty stays valid -- it
  # is how you ask for none.
  if (length(classify)) {
    classify <- rlang::arg_match(classify, c("income", "continent", "region"),
                                 multiple = TRUE)
  }
  check_string(language, "language")

  countries <- country_data(
    year = year, indicator = indicator, latest = latest,
    panel = length(year) > 1L, classify = classify, cache = cache,
    language = language, parallel = parallel, vintage = vintage
  )

  if (geometry == "none") {
    # `region` is documented as a plain "Optional subset", not an sf-backend
    # option -- but it only ever took effect inside attach_geometry(), which
    # this branch skips. So asking for one region with geometry = "none"
    # returned every country in the world, silently and with no hint that the
    # argument had been dropped.
    if (!is.null(region)) {
      iso <- resolve_region_codes(region)
      if (inherits(iso, "wdj_bbox")) {
        wdj_abort(c(
          "A bounding-box {.arg region} needs geometry to clip against.",
          "x" = 'There is nothing to clip when {.code geometry = "none"}.',
          "i" = 'Use {.code geometry = "sf"}, or select whole countries with a
                 continent, a group name or an {.field iso3c} vector.'
        ), class = "countryatlas_bbox_without_geometry")
      }
      if (!is.null(iso)) {
        countries <- countries[!is.na(countries$iso3c) &
                                 countries$iso3c %in% iso, , drop = FALSE]
      }
    }
    # `scale`, `projection` and `recenter` are all documented as sf-backend
    # options; this branch fetches no geometry at all, so none of them can be
    # honoured. They were accepted and dropped without a word.
    warn_scale_ignored(scale)
    warn_projection_ignored(projection, 'geometry = "none"')
    warn_recenter_ignored(recenter, 'geometry = "none"')
    return(countries)
  }

  quiet_maps_deprecation(
    attach_geometry(countries, by = "iso3c", geometry = geometry, scale = scale,
                    region = region, projection = projection, recenter = recenter,
                    overrides = overrides))
}

#' Lightweight one-row-per-country table
#'
#' The analysis counterpart to [world_data()]: no polygons, one tidy row per
#' country (`iso3c`, `iso2c`, `country`, classifications and the requested
#' indicators). This is what you actually `join()` / `mutate()` / `summarise()`
#' / `rank()` on; attach geometry only at draw time with [attach_geometry()].
#'
#' @param year A single year or a range (with `panel = TRUE`).
#' @param indicator A named character vector of WDI codes (or `NULL` for none).
#' @param latest For a single year: `TRUE` takes each indicator's most recent
#'   non-`NA` value per country, `"common"` the most recent year in which every
#'   indicator is present. Both add an `<indicator>_year` column per indicator;
#'   see the section below.
#' @param panel Return a panel keyed on `iso3c` + `year` (implied when `year`
#'   spans multiple years).
#' @param classify Which classifications to add.
#' @param cache Whether to use the WDI cache.
#' @param language WDI language code.
#' @param parallel Whether to fetch indicators in parallel. Ignored when the
#'   cache is memory-only; see [world_data()].
#' @param vintage The release of the World Development Indicators to read;
#'   see [world_data()].
#'
#' @section The most recent value, and which year it is from:
#' With `latest = TRUE` each indicator takes its own most recent value, so one
#' row can hold GDP from 2023 beside population from 2021. That is often what
#' is wanted -- the freshest number for each -- but dividing one by the other
#' mixes years, so every indicator carries an `<indicator>_year` column, and
#' [per_capita()], [deflate()] and [to_ppp()] warn (class
#' `countryatlas_mixed_years`) when the two columns they combine come from
#' different years. `latest = "common"` instead takes, per country, the most
#' recent year in which every requested indicator is present, so the row is
#' internally consistent; a country with no such year gets `NA` throughout.
#'
#' @return A tibble, one row per country (or per country-year for a panel).
#'
#'   `iso3c` is the stable key; `country` is a *label* and its spelling depends on
#'   where the row came from. A successful fetch carries the World Bank's names
#'   ("Korea, Rep.", "Congo, Dem. Rep."), while the country spine used when the
#'   fetch returns nothing carries the `countrycode` names ("South Korea",
#'   "Congo - Kinshasa") -- as do [convert_country()], [standardize_country()]
#'   and the rest of the package. Match on `iso3c`, and relabel with
#'   `convert_country(iso3c, to = "country")` if you need one consistent set.
#' @export
#' @examples
#' \donttest{
#' country_data(2020, c(co2 = "EN.GHG.CO2.MT.CE.AR5"))
#' }
country_data <- function(year,
                         indicator = NULL,
                         latest = FALSE,
                         panel = FALSE,
                         classify = c("income", "continent", "region"),
                         cache = TRUE,
                         language = "en",
                         parallel = TRUE,
                         vintage = NULL) {
  latest <- check_latest(latest)
  check_bool(panel, "panel")
  check_bool(cache, "cache")
  check_bool(parallel, "parallel")
  year <- validate_years(year)
  latest_on <- !isFALSE(latest)
  latest_single <- latest_on && length(year) == 1L
  # `latest` and a multi-year request are mutually exclusive, and so are `latest`
  # and `panel` -- but which one won was silent and, worse, inconsistent: a range
  # overrode `latest`, while a single year had `latest` override `panel`. Say
  # which argument is being dropped rather than returning a shape nobody asked
  # for. The winner is unchanged; only the silence is.
  if (latest_on && length(year) > 1L) {
    wdj_warn(c(
      "{.arg latest} is ignored when {.arg year} spans more than one year.",
      "x" = "Got {length(year)} years, so the full panel is returned.",
      "i" = "Pass a single year to get the most recent non-{.code NA} value
             per country."
    ))
  } else if (latest_single && isTRUE(panel)) {
    wdj_warn(c(
      "{.arg panel} is ignored when {.arg latest} is set.",
      "x" = "The most recent value per country is a single row, not a panel.",
      "i" = "Pass a year range for a panel, or {.code latest = FALSE} to pin
             the requested year."
    ))
    # Honoured here, next to the warning that promises it. It used to be
    # cleared only inside the collapse branch further down, which is gated on
    # nrow(wdi) -- so with indicator = NULL, or after a fetch that came back
    # empty, `panel` stayed TRUE and the frame was crossed with `year` after
    # all: the result carried the very year column the warning said it would
    # not.
    panel <- FALSE
  }
  panel <- isTRUE(panel) || length(year) > 1L
  # intersect() silently dropped anything unrecognised, so classify = "incomes"
  # added no classification columns and said nothing. Empty stays valid -- it
  # is how you ask for none.
  if (length(classify)) {
    classify <- rlang::arg_match(classify, c("income", "continent", "region"),
                                 multiple = TRUE)
  }
  check_string(language, "language")

  start <- min(year)
  end <- max(year)

  wdi <- fetch_wdi(indicator, start = if (latest_single) 1960L else start, end = end,
                   cache = cache, language = language, parallel = parallel,
                   vintage = vintage)
  # The record of where each column came from, re-attached at the end: the
  # collapses and joins below rebuild the frame.
  info <- attr(wdi, "countryatlas_sources")

  # Restrict to requested years and drop World Bank aggregates / non-countries.
  if (nrow(wdi)) {
    wdi <- if (latest_single) dplyr::filter(wdi, .data$year <= !!end) else dplyr::filter(wdi, .data$year %in% !!year)
    wdi <- dplyr::filter(wdi, !is.na(.data$iso3c))
    # Keep only true countries (valid iso3c in the codelist) -> removes
    # "World", "Euro area", regional aggregates.
    wdi <- dplyr::filter(wdi, .data$iso3c %in% wdj_known_iso3c())
  }

  if (latest_single && nrow(wdi)) {
    val_cols <- setdiff(names(wdi), c("iso2c", "iso3c", "country", "year"))
    wdi <- latest_values(wdi, val_cols, common = identical(latest, "common"))
    # Already cleared beside the warning above for the single-year case; kept
    # for the path where `latest = TRUE` collapses without having warned.
    panel <- FALSE
  }

  # Build the country spine. If no indicators were requested, start from the
  # full codelist so the table is still useful.
  if (nrow(wdi) == 0L) {
    cl <- country_codes(c("iso2c"))
    spine <- tibble::tibble(iso3c = cl$iso3c, iso2c = cl$iso2c,
                            country = cl$country)
    if (panel) {
      spine <- tidyr::crossing(spine, year = year)
    }
    base <- spine
  } else {
    if (!panel) {
      # Collapse to one row per country (single requested year).
      wdi <- dplyr::distinct(wdi, .data$iso3c, .keep_all = TRUE)
      wdi$year <- NULL
    } else {
      # One row per country-year (two iso2c codes can map to one iso3c).
      wdi <- dplyr::distinct(wdi, .data$iso3c, .data$year, .keep_all = TRUE)
    }
    base <- wdi
  }

  # Attach classifications (drop pre-existing same-named cols, but keep the key).
  # Use unique codes so a panel's repeated iso3c values don't fan out the join.
  cls <- country_classification(unique(base$iso3c), classify)
  drop <- setdiff(intersect(names(cls), names(base)), "iso3c")
  base[drop] <- NULL
  base <- dplyr::left_join(base, cls, by = "iso3c", na_matches = "never",
                           relationship = "many-to-one")
  info <- dplyr::bind_rows(info, attr(cls, "countryatlas_sources"))

  # Order columns sensibly.
  lead <- intersect(c("iso3c", "iso2c", "country", "year",
                      "continent", "region", "income"), names(base))
  base <- base[, c(lead, setdiff(names(base), lead)), drop = FALSE]
  set_source_info(tibble::as_tibble(base), info)
}

# `latest` is TRUE, FALSE or "common".
check_latest <- function(latest, call = rlang::caller_env()) {
  if (identical(latest, "common")) return("common")
  if (!isTRUE(latest) && !isFALSE(latest)) {
    wdj_abort(c(
      "{.arg latest} must be {.code TRUE}, {.code FALSE} or {.val common}.",
      "x" = "Got {.obj_type_friendly {latest}}."
    ), call = call)
  }
  latest
}

# The most recent value per country, and the year it is from.
#
# Each value column used to take its own last non-NA value and `year` was
# dropped, so France came back with GDP from 2023 beside population from 2021
# and nothing recorded either year -- per_capita() on that row divided across
# years without a word. Every indicator now keeps its year in
# `<indicator>_year`. With `common = TRUE` the row is the most recent year in
# which every indicator is present, so the values share one year.
latest_values <- function(wdi, val_cols, common = FALSE) {
  wdi <- wdi[order(wdi$iso3c, year_sort_key(wdi$year)), , drop = FALSE]
  rows <- split(seq_len(nrow(wdi)), wdi$iso3c)
  last_ok <- function(r, ok) if (any(ok)) r[max(which(ok))] else NA_integer_
  out <- wdi[vapply(rows, function(r) r[length(r)], 1L),
             intersect(c("iso3c", "iso2c", "country"), names(wdi)), drop = FALSE]
  common_row <- if (common) {
    vapply(rows, function(r) {
      last_ok(r, stats::complete.cases(wdi[r, val_cols, drop = FALSE]))
    }, 1L)
  }
  for (v in val_cols) {
    pick <- common_row %||%
      vapply(rows, function(r) last_ok(r, !is.na(wdi[[v]][r])), 1L)
    out[[v]] <- wdi[[v]][pick]
    out[[paste0(v, "_year")]] <- wdi$year[pick]
  }
  tibble::as_tibble(out)
}
