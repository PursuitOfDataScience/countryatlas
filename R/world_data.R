# Core data assembly ------------------------------------------------------------

# Per-country classification (income / region / continent) assembled offline
# from WDI's bundled country metadata plus countrycode.
country_classification <- function(iso3c, classify) {
  out <- tibble::tibble(iso3c = iso3c)
  meta <- tryCatch(tibble::as_tibble(WDI::WDI_data$country),
                   error = function(e) NULL)
  if ("income" %in% classify) {
    if (!is.null(meta)) {
      lk <- meta[, c("iso3c", "income")]
      out <- dplyr::left_join(out, lk, by = "iso3c", na_matches = "never")
      out$income <- clean_income(out$income)
    } else {
      out$income <- factor(NA, levels = income_levels())
    }
  }
  if ("region" %in% classify) {
    if (!is.null(meta) && "region" %in% names(meta)) {
      lk <- meta[, c("iso3c", "region")]
      names(lk)[2] <- "region"
      out <- dplyr::left_join(out, lk, by = "iso3c", na_matches = "never")
    } else {
      out$region <- suppressWarnings(
        countrycode::countrycode(iso3c, "iso3c", "region", warn = FALSE)
      )
    }
  }
  if ("continent" %in% classify) {
    out$continent <- suppressWarnings(
      countrycode::countrycode(iso3c, "iso3c", "continent", warn = FALSE)
    )
  }
  out <- apply_code_fallback(out)
  # Drop the helper iso3c if caller binds separately.
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
#'   non-CRAN `rnaturalearthhires` package; see [world_geometry()].
#' @param region Optional subset: a continent, group name, `iso3c` vector or
#'   bounding box. A bounding box clips the shapes rather than selecting whole
#'   countries, and only the `sf` backend can do that properly -- see
#'   [world_geometry()].
#' @param classify Which classifications to add (any of `"income"`,
#'   `"continent"`, `"region"`).
#' @param projection,recenter Projection, and optional central meridian, for
#'   the `sf` backend (see [world_map()] for the projections available).
#' @param latest If `TRUE`, use the most recent non-`NA` value per country for a
#'   single-year request.
#' @param cache Whether to use the memoised / on-disk WDI cache.
#' @param language WDI language code (default `"en"`).
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
#' # geometry = "polygon", the default, comes from the suggested `maps`
#' # package, so guard the call: an example may not assume a Suggests is
#' # installed (R CMD check runs \donttest{} blocks, and CRAN has a
#' # check flavour with no suggested packages at all).
#' if (requireNamespace("maps", quietly = TRUE)) {
#'   world_data(2020)
#' }
#'
#' # geometry = "none" needs nothing beyond the hard dependencies.
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
                       overrides = country_overrides()) {
  check_bool(latest, "latest")
  check_bool(cache, "cache")
  check_bool(parallel, "parallel")
  geometry <- match.arg(geometry)
  scale <- match.arg(scale)
  year <- validate_years(year)
  classify <- intersect(classify, c("income", "continent", "region"))

  countries <- country_data(
    year = year, indicator = indicator, latest = latest,
    panel = length(year) > 1L, classify = classify, cache = cache,
    language = language, parallel = parallel
  )

  # Legacy alias: keep gdp_per_capita_2015 readable for one cycle.
  if ("gdp_per_capita" %in% names(countries) &&
      !"gdp_per_capita_2015" %in% names(countries) &&
      isTRUE(getOption("countryatlas.gdp_compat", FALSE))) {
    countries$gdp_per_capita_2015 <- countries$gdp_per_capita
  }

  if (geometry == "none") {
    return(countries)
  }

  attach_geometry(countries, by = "iso3c", geometry = geometry, scale = scale,
                  region = region, projection = projection, recenter = recenter,
                  overrides = overrides)
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
#' @param latest Use the most recent non-`NA` value per country (single year).
#' @param panel Return a panel keyed on `iso3c` + `year` (implied when `year`
#'   spans multiple years).
#' @param classify Which classifications to add.
#' @param cache Whether to use the WDI cache.
#' @param language WDI language code.
#' @param parallel Whether to fetch indicators in parallel. Ignored when the
#'   cache is memory-only; see [world_data()].
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
                         parallel = TRUE) {
  check_bool(latest, "latest")
  check_bool(panel, "panel")
  check_bool(cache, "cache")
  check_bool(parallel, "parallel")
  year <- validate_years(year)
  latest_single <- isTRUE(latest) && length(year) == 1L
  # `latest` and a multi-year request are mutually exclusive, and so are `latest`
  # and `panel` -- but which one won was silent and, worse, inconsistent: a range
  # overrode `latest`, while a single year had `latest` override `panel`. Say
  # which argument is being dropped rather than returning a shape nobody asked
  # for. The winner is unchanged; only the silence is.
  if (isTRUE(latest) && length(year) > 1L) {
    wdj_warn(c(
      "{.arg latest} is ignored when {.arg year} spans more than one year.",
      "x" = "Got {length(year)} years, so the full panel is returned.",
      "i" = "Pass a single year to get the most recent non-{.code NA} value
             per country."
    ))
  } else if (latest_single && isTRUE(panel)) {
    wdj_warn(c(
      "{.arg panel} is ignored when {.code latest = TRUE}.",
      "x" = "The most recent value per country is a single row, not a panel.",
      "i" = "Pass a year range for a panel, or {.code latest = FALSE} to pin
             the requested year."
    ))
  }
  panel <- isTRUE(panel) || length(year) > 1L
  classify <- intersect(classify, c("income", "continent", "region"))

  start <- min(year)
  end <- max(year)

  wdi <- fetch_wdi(indicator, start = if (latest_single) 1960L else start, end = end,
                   cache = cache, language = language, parallel = parallel)

  # Restrict to requested years and drop World Bank aggregates / non-countries.
  if (nrow(wdi)) {
    wdi <- if (latest_single) dplyr::filter(wdi, .data$year <= !!end) else dplyr::filter(wdi, .data$year %in% !!year)
    wdi <- dplyr::filter(wdi, !is.na(.data$iso3c))
    # Keep only true countries (valid iso3c in the codelist) -> removes
    # "World", "Euro area", regional aggregates.
    wdi <- dplyr::filter(wdi, .data$iso3c %in% wdj_known_iso3c())
  }

  if (isTRUE(latest) && length(year) == 1L && nrow(wdi)) {
    val_cols <- setdiff(names(wdi), c("iso2c", "iso3c", "country", "year"))
    wdi <- wdi %>%
      dplyr::group_by(.data$iso3c) %>%
      dplyr::arrange(.data$year, .by_group = TRUE) %>%
      dplyr::summarise(
        dplyr::across(dplyr::all_of(c("iso2c", "country")), dplyr::last),
        dplyr::across(dplyr::all_of(val_cols),
                      ~ dplyr::last(stats::na.omit(.x)) %||% NA),
        .groups = "drop"
      )
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
  base <- dplyr::left_join(base, cls, by = "iso3c", na_matches = "never")

  # Order columns sensibly.
  lead <- intersect(c("iso3c", "iso2c", "country", "year",
                      "continent", "region", "income"), names(base))
  base <- base[, c(lead, setdiff(names(base), lead)), drop = FALSE]
  tibble::as_tibble(base)
}
