#' countryatlas: join World Bank data, country codes and maps on the ISO spine
#'
#' `countryatlas` exists to kill one recurring source of pain: country names
#' never line up across data sources. The package makes ISO codes the universal
#' join key and hands you a ready-to-map tibble that stitches together map
#' geometry ([ggplot2::map_data()] or Natural Earth `sf`), World Bank indicators
#' ([WDI::WDI()]) and the [countrycode::countrycode()] crosswalk.
#'
#' The happy path stays one call: [world_data()]. Everything else is opt-in.
#'
#' @section Core data assembly:
#' [world_data()], [country_data()], [world_geometry()], [locate_country()],
#' [country_borders()], [neighbors()], [distance_between()].
#'
#' @section The join engine:
#' [standardize_country()], [join_world()], [attach_geometry()], [country_join()],
#' [country_join_all()], [dissolve_country()].
#'
#' @section Diagnostics:
#' [check_country_match()], [repair_country_names()], [country_overrides()],
#' [audit_coverage()].
#'
#' @section Reference data:
#' [convert_country()], [country_codes()], [country_groups()], [in_group()],
#' [wdi_search()], and the datasets [country_meta], [common_indicators],
#' [country_groups_tbl], [world_snapshot], [world_tiles], [historical_codes].
#'
#' @section Analysis helpers:
#' [per_capita()], [aggregate_regions()], [rank_countries()], [complete_years()],
#' [growth_rate()], [index_to()], [share_of_world()], [lag_by_country()],
#' [diff_by_country()], [correlate_indicators()], [beta_convergence()],
#' [sigma_convergence()], [gini()], [theil()], [morans_i()].
#'
#' @section Visualization:
#' [world_map()], [globe_map()], [spin_globe()], [facet_map()], [bubble_map()],
#' [spike_map()], [bivariate_map()], [cartogram_map()], [dorling_map()],
#' [tile_map()], [flow_map()], [animate_world()], [interactive_map()],
#' [geom_country_labels()], [theme_world_map()], [simplify_geometry()].
#'
#' @section Database rendering (ggsql):
#' [as_ggsql_source()], [world_query()].
#'
#' @section Performance & caching:
#' [clear_wdi_cache()].
#'
#' @section Options:
#' Four options change the package's behaviour. All are unset by default.
#' \describe{
#'   \item{`countryatlas.cache_dir`}{Where the persistent World Bank cache
#'     lives. Defaults to `tools::R_user_dir("countryatlas", "cache")`; set it to
#'     `""` for session-only caching. See [clear_wdi_cache()].}
#'   \item{`countryatlas.workers`}{How many processes fetch indicators in
#'     parallel (only when the cache is on disk -- a memory-only memo cannot
#'     survive a fork). Defaults to one fewer than the available cores, and
#'     to 2 under `R CMD check`, per CRAN policy. Must be a single finite
#'     number; values below one are clamped to one.}
#'   \item{`countryatlas.gdp_compat`}{Set to `TRUE` to restore the
#'     `gdp_per_capita_2015` column that [world_data()] emitted in 1.0.0. A
#'     deprecation shim, off by default, and now warning when used.}
#'   \item{`countryatlas.dispute_policy`}{Which map convention disputed
#'     territories are drawn under: `"none"` (default), `"de_facto"`,
#'     `"de_jure"` or `"neutral"`. Set it with [dispute_policy()] rather than
#'     directly, which also reports what the setting does and does not change.}
#' }
#'
#' @keywords internal
"_PACKAGE"

## usethis namespace: start
#' @importFrom rlang .data %||% :=
#' @importFrom dplyr %>%
## usethis namespace: end
NULL

# Quiet R CMD check for tidy-eval column references and bundled datasets
# referenced by name inside the package.
# Exactly the names R CMD check reports as unbound, and no more. The list had
# grown to 29; emptying it entirely showed only a handful were load-bearing --
# the rest were covered by the `.data$x` / `.data[[x]]` idiom the code uses
# throughout, which needs no declaration at all. A stale entry is not merely
# dead weight: it silences the "no visible binding" NOTE for a *new* bare use of
# the same name, which is the warning that would otherwise catch a typo.
#
# The four bundled datasets used to be declared here too. They are now referred
# to as `countryatlas::country_meta` and so on, because a *bare* reference only
# resolves while the package is attached: under `countryatlas::fn()` alone the
# lazy-data objects are not on the search path, and six exported functions failed
# with "object 'world_tiles' not found". Declaring them here silenced the NOTE
# without fixing that, which is exactly the trap described above.
# Only `year` still needs declaring: it is animate_world()'s default
# `time = year`, an unquoted symbol. Every column reference in the package
# now goes through .data$, which needs no declaration.
utils::globalVariables("year")

# Register the built-in data sources at load, so country_sources() is populated
# without the user having to do anything. Registration is cheap -- it stores a
# function reference, it does not touch the network or load the provider's
# package -- and a source whose backing package is absent simply reports
# `available = FALSE` until it is installed.
.onLoad <- function(libname, pkgname) {
  register_builtin_sources()
  invisible(NULL)
}
