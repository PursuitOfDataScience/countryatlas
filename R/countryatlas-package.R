#' countryatlas: join World Bank data, country codes and maps on the ISO spine
#'
#' `countryatlas` exists to kill one recurring source of pain: country names
#' never line up across data sources. The package makes ISO codes the universal
#' join key and hands you a ready-to-map tibble that stitches together map
#' geometry (bundled Natural Earth polygons, or Natural Earth `sf`), World Bank indicators
#' ([WDI::WDI()]) and the [countrycode::countrycode()] crosswalk.
#'
#' The happy path stays one call: [world_data()]. Everything else is opt-in.
#'
#' @section Core data assembly:
#' [world_data()], [country_data()], [world_geometry()], [locate_country()],
#' [country_borders()], [neighbors()], [distance_between()].
#'
#' @section Data sources beyond the World Bank:
#' [fetch_indicator()], [add_indicator()], [compare_sources()],
#' [country_sources()], [register_country_source()],
#' [remove_country_source()], and the adapters [fetch_owid()],
#' [fetch_eurostat()], [fetch_oecd()] and [fetch_comtrade()].
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
#' [country_groups_tbl], [country_groups_history], [world_snapshot],
#' [world_tiles], [historical_codes], [disputed_territories].
#'
#' @section Time:
#' [country_timeline()], [audit_time_coverage()], [historical_geometry()].
#'
#' @section Analysis helpers:
#' [per_capita()], [aggregate_regions()], [rank_countries()], [complete_years()],
#' [interpolate_missing()], [growth_rate()], [index_to()], [share_of_world()],
#' [lag_by_country()], [diff_by_country()], [deflate()], [to_ppp()],
#' [rate_check()], [smooth_rates()], [correlate_indicators()],
#' [beta_convergence()], [sigma_convergence()], [convergence_club()], [gini()],
#' [theil()].
#'
#' @section Spatial statistics and networks:
#' [country_weights()], [morans_i()], [local_morans()], [lisa_map()],
#' [gearys_c()], [getis_ord()], [spatial_lag()]; [flow_matrix()],
#' [country_network()], [od_map()].
#'
#' @section Visualization:
#' [world_map()], [globe_map()], [spin_globe()], [facet_map()], [bubble_map()],
#' [spike_map()], [bivariate_map()], [cartogram_map()], [dorling_map()],
#' [gridded_cartogram()], [tile_map()], [flow_map()], [animate_world()],
#' [interactive_map()], [geom_country_labels()], [theme_world_map()],
#' [simplify_geometry()].
#'
#' @section Honest maps:
#' [classify_compare()], [coverage_map()], [value_by_alpha_map()],
#' [projection_info()], [projection_compare()], [projection_distortion()],
#' [tissot_map()], [cartogram_diagnostics()], [map_provenance()],
#' [dispute_policy()], [check_dispute_coverage()].
#'
#' @section Subnational:
#' [standardize_subnational()], [nuts_geometry()], [subnational_map()].
#'
#' @section Reporting:
#' [country_factsheet()], [world_table()].
#'
#' @section Database rendering (ggsql):
#' [as_ggsql_source()], [world_query()].
#'
#' @section Performance & caching:
#' [clear_country_cache()].
#'
#' @section Options:
#' Eight options change the package's behaviour. All are unset by default.
#' \describe{
#'   \item{`countryatlas.cache_dir`}{Where the persistent cache lives, one
#'     directory per source. Defaults to `tools::R_user_dir("countryatlas",
#'     "cache")`; set it to `""` for session-only caching. See
#'     [clear_country_cache()].}
#'   \item{`countryatlas.cache_max_age`}{How long a persistent cache entry
#'     stays usable, in seconds. Defaults to 30 days. World Bank figures are
#'     revised, so an old entry is not merely stale on disk -- it is a
#'     different answer from the one the API would give now. A single
#'     non-negative number; `Inf` for no expiry.}
#'   \item{`countryatlas.cache_max_size`}{The size cap on the persistent
#'     cache, in bytes. Defaults to 50 MB, past which the least-recently-used
#'     entries are dropped. CRAN policy allows a package cache under
#'     `tools::R_user_dir()` only if its contents are actively managed. A single
#'     non-negative number; `Inf` for no cap.}
#'   \item{`countryatlas.workers`}{How many processes fetch indicators in
#'     parallel (only when the cache is on disk -- a memory-only memo cannot
#'     survive a fork). Defaults to one fewer than the available cores, and
#'     to 2 under `R CMD check`, per CRAN policy. Must be a single finite
#'     number; values below one are clamped to one.}
#'   \item{`countryatlas.timeout`}{How long one request to a provider may
#'     take, in seconds. Defaults to 60. Every built-in source goes through the
#'     same client, so a failing fetch is bounded: at most
#'     `countryatlas.retries + 1` requests of this length each, plus the waits
#'     between them.}
#'   \item{`countryatlas.retries`}{How many times a request is retried after a
#'     failure worth retrying (HTTP 429, a 5xx, a dropped connection), with
#'     exponential backoff and jitter, honouring `Retry-After`. Defaults to 3;
#'     a whole number from 0 to 10.}
#'   \item{`countryatlas.strict`}{Set to `TRUE` to make a failed download an
#'     error (class `countryatlas_fetch_failed`) instead of a warning and an
#'     empty result, for a pipeline that must not continue with data missing.
#'     The default, `FALSE`, is what CRAN asks of a package that uses the
#'     network: fail gracefully.}
#'   \item{`countryatlas.dispute_policy`}{Which map convention disputed
#'     territories are drawn under: `"none"` (default), `"de_facto"`,
#'     `"de_jure"` or `"neutral"`. Set it with [dispute_policy()] rather than
#'     directly, which also reports what the setting does and does not change.}
#'   \item{`countryatlas.worldview`}{A Natural Earth point of view the `sf`
#'     backend draws, as the viewing country's ISO code (`"IND"`) or
#'     `"ISO"`; unset by default. Set it with
#'     `dispute_policy(worldview = )`, which validates it; see
#'     [world_geometry()].}
#' }
#'
#' @keywords internal
"_PACKAGE"

## usethis namespace: start
#' @importFrom rlang .data %||% :=
#' @importFrom dplyr %>%
#' @importFrom lifecycle deprecated
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
  # Memoise at load time, not at build time: see the comment on
  # world_polygons() in R/geometry.R.
  world_polygons <<- memoise::memoise(build_world_polygons)
  invisible(NULL)
}
