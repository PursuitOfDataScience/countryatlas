# countryatlas: join World Bank data, country codes and maps on the ISO spine

`countryatlas` exists to kill one recurring source of pain: country
names never line up across data sources. The package makes ISO codes the
universal join key and hands you a ready-to-map tibble that stitches
together map geometry
([`ggplot2::map_data()`](https://ggplot2.tidyverse.org/reference/map_data.html)
or Natural Earth `sf`), World Bank indicators
([`WDI::WDI()`](https://rdrr.io/pkg/WDI/man/WDI.html)) and the
[`countrycode::countrycode()`](https://rdrr.io/pkg/countrycode/man/countrycode.html)
crosswalk.

## Details

The happy path stays one call:
[`world_data()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_data.md).
Everything else is opt-in.

## Core data assembly

[`world_data()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_data.md),
[`country_data()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_data.md),
[`world_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_geometry.md),
[`locate_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/locate_country.md),
[`country_borders()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_borders.md),
[`neighbors()`](https://pursuitofdatascience.github.io/countryatlas/reference/neighbors.md),
[`distance_between()`](https://pursuitofdatascience.github.io/countryatlas/reference/distance_between.md).

## The join engine

[`standardize_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/standardize_country.md),
[`join_world()`](https://pursuitofdatascience.github.io/countryatlas/reference/join_world.md),
[`attach_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/attach_geometry.md),
[`country_join()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_join.md),
[`country_join_all()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_join_all.md),
[`dissolve_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/dissolve_country.md).

## Diagnostics

[`check_country_match()`](https://pursuitofdatascience.github.io/countryatlas/reference/check_country_match.md),
[`repair_country_names()`](https://pursuitofdatascience.github.io/countryatlas/reference/repair_country_names.md),
[`country_overrides()`](https://pursuitofdatascience.github.io/countryatlas/reference/wdj_overrides.md),
[`audit_coverage()`](https://pursuitofdatascience.github.io/countryatlas/reference/audit_coverage.md).

## Reference data

[`convert_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/convert_country.md),
[`country_codes()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_codes.md),
[`country_groups()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_groups.md),
[`in_group()`](https://pursuitofdatascience.github.io/countryatlas/reference/in_group.md),
[`wdi_search()`](https://pursuitofdatascience.github.io/countryatlas/reference/wdi_search.md),
and the datasets
[country_meta](https://pursuitofdatascience.github.io/countryatlas/reference/country_meta.md),
[common_indicators](https://pursuitofdatascience.github.io/countryatlas/reference/common_indicators.md),
[country_groups_tbl](https://pursuitofdatascience.github.io/countryatlas/reference/country_groups_tbl.md),
[world_snapshot](https://pursuitofdatascience.github.io/countryatlas/reference/world_snapshot.md),
[world_tiles](https://pursuitofdatascience.github.io/countryatlas/reference/world_tiles.md),
[historical_codes](https://pursuitofdatascience.github.io/countryatlas/reference/historical_codes.md).

## Analysis helpers

[`per_capita()`](https://pursuitofdatascience.github.io/countryatlas/reference/per_capita.md),
[`aggregate_regions()`](https://pursuitofdatascience.github.io/countryatlas/reference/aggregate_regions.md),
[`rank_countries()`](https://pursuitofdatascience.github.io/countryatlas/reference/rank_countries.md),
[`complete_years()`](https://pursuitofdatascience.github.io/countryatlas/reference/complete_years.md),
[`growth_rate()`](https://pursuitofdatascience.github.io/countryatlas/reference/growth_rate.md),
[`index_to()`](https://pursuitofdatascience.github.io/countryatlas/reference/index_to.md),
[`share_of_world()`](https://pursuitofdatascience.github.io/countryatlas/reference/share_of_world.md),
[`lag_by_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/lag_by_country.md),
[`diff_by_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/lag_by_country.md),
[`correlate_indicators()`](https://pursuitofdatascience.github.io/countryatlas/reference/correlate_indicators.md),
[`beta_convergence()`](https://pursuitofdatascience.github.io/countryatlas/reference/beta_convergence.md),
[`sigma_convergence()`](https://pursuitofdatascience.github.io/countryatlas/reference/sigma_convergence.md),
[`gini()`](https://pursuitofdatascience.github.io/countryatlas/reference/gini.md),
[`theil()`](https://pursuitofdatascience.github.io/countryatlas/reference/theil.md),
[`morans_i()`](https://pursuitofdatascience.github.io/countryatlas/reference/morans_i.md).

## Visualization

[`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md),
[`globe_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/globe_map.md),
[`spin_globe()`](https://pursuitofdatascience.github.io/countryatlas/reference/spin_globe.md),
[`facet_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/facet_map.md),
[`bubble_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/bubble_map.md),
[`spike_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/spike_map.md),
[`bivariate_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/bivariate_map.md),
[`cartogram_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/cartogram_map.md),
[`dorling_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/dorling_map.md),
[`tile_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/tile_map.md),
[`flow_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/flow_map.md),
[`animate_world()`](https://pursuitofdatascience.github.io/countryatlas/reference/animate_world.md),
[`interactive_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/interactive_map.md),
[`geom_country_labels()`](https://pursuitofdatascience.github.io/countryatlas/reference/geom_country_labels.md),
[`theme_world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/theme_world_map.md),
[`simplify_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/simplify_geometry.md).

## Database rendering (ggsql)

[`as_ggsql_source()`](https://pursuitofdatascience.github.io/countryatlas/reference/as_ggsql_source.md),
[`world_query()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_query.md).

## Performance & caching

[`clear_wdi_cache()`](https://pursuitofdatascience.github.io/countryatlas/reference/clear_wdi_cache.md).

## Options

Four options change the package's behaviour. All are unset by default.

- `countryatlas.cache_dir`:

  Where the persistent World Bank cache lives. Defaults to
  `tools::R_user_dir("countryatlas", "cache")`; set it to `""` for
  session-only caching. See
  [`clear_wdi_cache()`](https://pursuitofdatascience.github.io/countryatlas/reference/clear_wdi_cache.md).

- `countryatlas.workers`:

  How many processes fetch indicators in parallel (only when the cache
  is on disk – a memory-only memo cannot survive a fork). Defaults to
  one fewer than the available cores, and to 2 under `R CMD check`, per
  CRAN policy. Must be a single finite number; values below one are
  clamped to one.

- `countryatlas.gdp_compat`:

  Set to `TRUE` to restore the `gdp_per_capita_2015` column that
  [`world_data()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_data.md)
  emitted in 1.0.0. A deprecation shim, off by default, and now warning
  when used.

- `countryatlas.dispute_policy`:

  Which map convention disputed territories are drawn under: `"none"`
  (default), `"de_facto"`, `"de_jure"` or `"neutral"`. Set it with
  [`dispute_policy()`](https://pursuitofdatascience.github.io/countryatlas/reference/dispute_policy.md)
  rather than directly, which also reports what the setting does and
  does not change.

## See also

Useful links:

- <https://pursuitofdatascience.github.io/countryatlas/>

- <https://github.com/PursuitOfDataScience/countryatlas>

- Report bugs at
  <https://github.com/PursuitOfDataScience/countryatlas/issues>

## Author

**Maintainer**: Youzhi Yu <yuyouzhi666@icloud.com>
