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
#'     `country`, the classifications `continent`, `region` and `income`, and
#'     the curated indicators `gdp_per_capita`, `population`,
#'     `life_expectancy` and `co2_per_capita`.}
#'   \item{sf}{`NULL` in the released package -- geometry is not bundled twice.
#'     Attach it on demand with [attach_geometry()]:
#'     `attach_geometry(world_snapshot$countries, geometry = "sf")` pulls the
#'     same Natural Earth 110m polygons from `rnaturalearth`.}
#'   \item{year}{The reference year.}
#' }
#'   `country` carries the World Bank's own names, which differ from the
#'   `countrycode` names used by [country_meta] for 38 countries.
#' @source World Bank via \pkg{WDI}; geometry from Natural Earth via
#'   \pkg{rnaturalearth}. Snapshot year: 2024.
"world_snapshot"

#' Static per-country metadata
#'
#' One row per country with the facts people constantly need and currently
#' scrape together by hand.
#'
#' @format A tibble with one row per country and columns `iso3c`, `iso2c`,
#'   `country`, `continent`, `region`, `un_region`, `income`, `capital`,
#'   `capital_lat`, `capital_lon`, `centroid_lat`, `centroid_lon`, `area_km2`,
#'   `currency`, `tld`, `landlocked`, `flag`.
#'
#'   Assembled from [countrycode::codelist], so Kosovo (`XKX`) has no row --
#'   `countrycode` has none either. The geometry backends and
#'   [convert_country()] do handle it; [distance_between()], which reads its
#'   centroids from here, does not. Ten further territories have a row but no
#'   centroid or area.
#'
#'   `country` therefore carries the English names from `countrycode`
#'   ("South Korea", "Congo - Kinshasa"), which differ from the World Bank's for
#'   38 of the 215 countries in [world_snapshot] ("Korea, Rep.",
#'   "Congo, Dem. Rep."). Each
#'   table is faithful to its own source, so join on `iso3c` and keep whichever
#'   label you want to display -- reconciling the two is what [country_join()]
#'   is for.
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
#' The grid holds one row for each of the 239 countries in [country_meta] that
#' has a bundled centroid; the 10 without one (`ALA`, `BVT`, `GIB`, `HKG`,
#' `MAC`, `SJM`, `TKL`, `TUV`, `UMI`, `VGB` -- see [country_meta]) have no tile
#' and so cannot be drawn by [tile_map()].
#'
#' @format A tibble with columns `iso3c`, `country`, `row`, `col`; one row per
#'   country, with `row`/`col` unique across the grid.
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

#' Dated country-group membership
#'
#' When each country joined -- and where applicable left -- each of twelve
#' international groups. The dated counterpart to [country_groups_tbl], which is
#' a single current snapshot.
#'
#' A snapshot silently misstates any panel that spans an accession: an EU panel
#' over 2015-2020 either includes the United Kingdom throughout or excludes it
#' throughout, and both are wrong. [country_groups()] and [in_group()] read this
#' table when given `as_of`.
#'
#' @format A tibble with `r nrow(countryatlas::country_groups_history)` rows:
#' \describe{
#'   \item{group}{Group name.}
#'   \item{iso3c}{ISO 3166-1 alpha-3 code.}
#'   \item{country}{Country name.}
#'   \item{from}{Date membership took effect.}
#'   \item{to}{Date membership ended, or `NA` for a current member.}
#' }
#'
#' @section Scope, and what is deliberately absent:
#' Twelve groups are dated: EU, EuroZone, NATO, OECD, ASEAN, EFTA, GCC,
#' Mercosur, Nordic, Visegrad, BRICS and G7. **Commonwealth, G20 and OPEC are
#' not**, and that is a decision rather than an omission -- their histories
#' involve suspensions, readmissions and contested dates that would have to be
#' sourced case by case, and a fabricated date is worse than an absent one.
#' `country_groups(as_of =)` warns and falls back to the snapshot for those.
#'
#' Dates are the treaty or accession date where one exists, otherwise 1 January
#' of the accession year. The table is validated at build time against
#' [country_groups_tbl]: the members current today must reproduce the snapshot
#' exactly, for every group covered.
#'
#' @seealso [country_groups()], [in_group()], [country_timeline()]
#' @examples
#' # EFTA is the instructive one: most of its founders left, for the EU
#' subset(country_groups_history, group == "EFTA")
"country_groups_history"

#' Disputed territories
#'
#' Territories whose status is contested, recorded so that a map can say so.
#'
#' **This table records that a dispute exists and who the parties are. It does
#' not adjudicate, rank claims, or imply that any claim is better founded than
#' another.** Where it says "administered by" it means de facto control as
#' reported by the mapping sources the package already uses (Natural Earth), not
#' recognition, legitimacy or endorsement.
#'
#' @format A tibble with `r nrow(countryatlas::disputed_territories)` rows:
#' \describe{
#'   \item{territory}{Common name of the territory.}
#'   \item{iso3c}{ISO 3166-1 alpha-3 code where one exists, else `NA`. Most
#'     disputed territories have none, which is why they cannot appear in an
#'     `iso3c`-keyed dataset at all.}
#'   \item{administered_by}{The party in de facto control, or `NA` where none
#'     is. An ISO 3166-1 alpha-3 code where that party has one -- see the note
#'     on codes below.}
#'   \item{claimed_by}{Semicolon-separated claimants, coded as for
#'     `administered_by`.}
#'   \item{status}{One of `"un_member"`, `"un_observer"`,
#'     `"partially_recognised"`, `"administered"` or `"claimed"`.}
#'   \item{note}{One sentence of context, including why the row is here.}
#' }
#'
#' @section The codes in `administered_by` and `claimed_by`:
#' Mostly ISO 3166-1 alpha-3, so they join the `iso3c` spine directly -- but not
#' entirely, and the exceptions are the point of the table. Six parties here are
#' entities ISO assigns no code to, and they are written with a mnemonic
#' placeholder instead: `ABK` (Abkhazia), `CYP-N` (Northern Cyprus), `OST`
#' (South Ossetia), `PMR` (Transnistria), `SAH` (the Sahrawi Arab Democratic
#' Republic) and `SOL` (Somaliland).
#'
#' Five of them -- `ABK`, `CYP-N`, `OST`, `PMR` and `SOL` -- appear in
#' `administered_by` for the like-named territory, which has no ISO code of its
#' own: the entity administers itself and ISO codes neither. `SAH` is the
#' exception and worth knowing about: it appears only as a *claimant*, of
#' Western Sahara, which ISO does code (`ESH`) and which `MAR` administers.
#'
#' None of the six are ISO codes, so none will resolve through
#' [convert_country()] or any other `iso3c` lookup. Filter them out with
#' `%in% country_codes()$iso3c` if you need a strictly ISO-keyed column.
#'
#' @section Scope:
#' A documented subset, not the roughly 188 disputed areas the EU's
#' data-visualisation guidance counts. The selection criterion is mechanical and
#' checkable: territories that appear as a distinct unit or a contested boundary
#' in Natural Earth at 1:110m or 1:50m, **and** have an ISO 3166-1 code, a
#' widely-used user-assigned code, or a standard "disputed" label in ISO, UN M49
#' or World Bank practice. That criterion requires nobody to judge the merits.
#'
#' @seealso [dispute_policy()], [check_dispute_coverage()], [world_map()]
#' @examples
#' disputed_territories[, c("territory", "iso3c", "status")]
"disputed_territories"
