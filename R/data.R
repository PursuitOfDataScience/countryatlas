# Bundled datasets --------------------------------------------------------------

#' Offline snapshot of world data
#'
#' A small, lazy-loaded, one-row-per-country snapshot of a curated indicator
#' set for one recent year. It lets every example, test and vignette run
#' offline and deterministically, without the World Bank API.
#'
#' @format A list with three elements:
#' \describe{
#'   \item{countries}{A tibble, one row per country, with `iso3c`, `iso2c`,
#'     `country`, classifications and curated indicators
#'     (`gdp_per_capita`, `population`, `life_expectancy`, `co2_per_capita`).}
#'   \item{sf}{`NULL` in the released package -- geometry is not bundled twice.
#'     Attach it on demand with [attach_geometry()]`(world_snapshot$countries,`
#'     `geometry = "sf")`, which pulls the same Natural Earth 110m polygons
#'     from `rnaturalearth`.}
#'   \item{year}{The reference year.}
#' }
#' @source World Bank via \pkg{WDI}; geometry from Natural Earth via
#'   \pkg{rnaturalearth}. Snapshot year: 2024.
"world_snapshot"

#' Static per-country metadata
#'
#' One row per country with the facts people constantly need and currently
#' scrape together by hand.
#'
#' @format A tibble with one row per country and columns including `iso3c`,
#'   `iso2c`, `country`, `continent`, `region`, `un_region`, `capital`,
#'   `capital_lat`, `capital_lon`, `centroid_lat`, `centroid_lon`, `area_km2`,
#'   `currency`, `tld`, `landlocked`, `flag`.
#' @source Assembled from \pkg{countrycode}, \pkg{WDI} metadata and Natural
#'   Earth geometry.
"country_meta"

#' Curated indicator catalogue
#'
#' A friendly-name to WDI-code lookup so `indicator = common_indicators$population`
#' beats memorising `"SP.POP.TOTL"`.
#'
#' @format A tibble with columns `name` (friendly name), `code` (WDI indicator
#'   code) and `description`.
#' @source World Bank indicator catalogue.
"common_indicators"

#' Country-group membership (point-in-time)
#'
#' A curated, dated membership table for the common country groups.
#'
#' @format A tibble with columns `group`, `iso3c`, `country`.
#' @source Curated from official membership lists (point-in-time; see the
#'   package `NEWS` for the reference date).
"country_groups_tbl"

#' Equal-area world tile-grid layout
#'
#' A statebins-style equal-area tile layout: one square per country, positioned
#' on a `row`/`col` grid derived from country centroids. Used by [tile_map()].
#'
#' @format A tibble with columns `iso3c`, `country`, `row`, `col`.
#' @source Derived from Natural Earth country centroids.
"world_tiles"

#' Historical / dissolved entities and their successor states
#'
#' A curated crosswalk from dissolved entities (Soviet Union, Yugoslavia,
#' Czechoslovakia, ...) to the modern states that succeeded them -- one row per
#' (entity, successor) pair, dated, so historical panels can be brought onto
#' the modern ISO spine honestly instead of being silently dropped (or worse:
#' `countrycode` resolves `"USSR"` to Russia alone). Consumed by
#' [dissolve_country()] and flagged by [check_country_match()].
#'
#' Kosovo (`XKX`) is included among the Yugoslavia and Serbia-and-Montenegro
#' successors on a *territory* basis (its territory was part of both); filter
#' it out if your analysis follows strict UN-membership succession.
#'
#' @format A tibble with one row per (entity, successor):
#' \describe{
#'   \item{historical}{Canonical name of the dissolved entity.}
#'   \item{iso3c_hist}{The alpha-3 code the entity held at dissolution, where
#'     one existed (`SUN`, `YUG`, `CSK`, `DDR`, `ANT`, `SCG`, `YMD`, ...); it
#'     may since have been inherited by a successor (e.g. `YEM`).}
#'   \item{dissolved}{Year the entity ceased to exist.}
#'   \item{iso3c, country}{The successor state.}
#' }
#' @source Curated from ISO 3166-3 and the historical record.
"historical_codes"
