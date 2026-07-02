# Changelog

## countryatlas 2.0.0

A major release that wires countryatlas into the database-rendering
world via ‘ggsql’, widens the map vocabulary, and fixes several
correctness issues found by auditing 1.0.0. The version is bumped to
2.0.0 because the bug fixes change the output of
[`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md)
(quantile binning),
[`bubble_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/bubble_map.md)
/
[`flow_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/flow_map.md)
(de-duplicated symbols),
[`geom_country_labels()`](https://pursuitofdatascience.github.io/countryatlas/reference/geom_country_labels.md)
(label placement) and
[`convert_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/convert_country.md)
(override-only entities) — code that depended on the old behaviour may
see different maps or values.

### New: database-side rendering with ggsql

- [`as_ggsql_source()`](https://pursuitofdatascience.github.io/countryatlas/reference/as_ggsql_source.md)
  exports a curated, ISO-reconciled, WDI-joined table (with `sf`
  geometry WKB-encoded) as a [ggsql](https://ggsql.org) source — a
  DuckDB connection, a Parquet file, or a nanoarrow stream. countryatlas
  does the reconciliation ggsql’s static bundled world can’t; ggsql does
  the database push-down and Vega-Lite output countryatlas doesn’t.
- [`world_query()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_query.md)
  emits a `ggsql` spatial query
  (`VISUALISE … DRAW spatial PROJECT TO … SCALE … LABEL …`) — a
  dependency-free string builder.
- `interactive_map(engine = "ggsql")` registers the data and renders the
  map in DuckDB, returning a Vega-Lite widget.
- `ggsql`, `duckdb`, `DBI` and `nanoarrow` are optional `Suggests`. See
  the new *countryatlas and ggsql* vignette.

### New: maps, projections and helpers

- [`globe_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/globe_map.md)
  — an orthographic globe choropleth, with `backend = "sf"` (smoothest
  limb) or `backend = "polygon"` (needs only `maps` + `mapproj`).
- [`spin_globe()`](https://pursuitofdatascience.github.io/countryatlas/reference/spin_globe.md)
  — a rotating-globe animated GIF (one
  [`globe_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/globe_map.md)
  frame per central longitude, assembled with `gifski` or `magick`).
- [`facet_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/facet_map.md)
  — small-multiple choropleths (the static counterpart to
  [`animate_world()`](https://pursuitofdatascience.github.io/countryatlas/reference/animate_world.md)).
- `wdj_crs()` gains eight projections (`mercator`, `winkel_tripel`,
  `eckert4`, `gall_peters`, `orthographic`, `azimuthal_equal_area`,
  `north_polar`, `south_polar`);
  [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md)
  /
  [`world_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_geometry.md)
  accept them all.
- [`locate_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/locate_country.md)
  — point-in-polygon lookup tagging `lon`/`lat` with `iso3c`.
- [`repair_country_names()`](https://pursuitofdatascience.github.io/countryatlas/reference/repair_country_names.md)
  — the “act on it” companion to
  [`check_country_match()`](https://pursuitofdatascience.github.io/countryatlas/reference/check_country_match.md):
  auto-applies confident string-distance fixes.
- [`country_join_all()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_join_all.md)
  — reduce-join many messy country tables on the ISO spine.
- [`growth_rate()`](https://pursuitofdatascience.github.io/countryatlas/reference/growth_rate.md),
  [`index_to()`](https://pursuitofdatascience.github.io/countryatlas/reference/index_to.md),
  [`share_of_world()`](https://pursuitofdatascience.github.io/countryatlas/reference/share_of_world.md)
  — panel analysis helpers.
- [`country_overrides()`](https://pursuitofdatascience.github.io/countryatlas/reference/wdj_overrides.md)
  — preferred name for
  [`wdj_overrides()`](https://pursuitofdatascience.github.io/countryatlas/reference/wdj_overrides.md)
  (kept as an alias) after the rename to countryatlas.
- `country_groups_tbl` gains `Mercosur`, `GCC`, `Nordic` and `Visegrad`.
- [`country_borders()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_borders.md)
  — a tidy adjacency edge list built from polygon topology
  ([`sf::st_touches()`](https://r-spatial.github.io/sf/reference/geos_binary_pred.html)),
  with
  [`neighbors()`](https://pursuitofdatascience.github.io/countryatlas/reference/neighbors.md)
  for a vectorised per-country lookup.
- [`distance_between()`](https://pursuitofdatascience.github.io/countryatlas/reference/distance_between.md)
  — great-circle (haversine) distance between two countries’ centroids;
  needs neither `sf` nor the network.
- [`dorling_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/dorling_map.md)
  — the Dorling cartogram promoted to a first-class verb, with
  `k`/`itermax` tuning;
  [`cartogram_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/cartogram_map.md)
  itself gains `...` passthrough to the underlying
  `cartogram::cartogram_*()` call.

### New: historical entities, inequality and spatial statistics

- `historical_codes` — a curated, dated crosswalk of dissolved entities
  (Soviet Union, Yugoslavia, Czechoslovakia, East Germany, Netherlands
  Antilles, North/South Yemen, pre-2011 Sudan, United Arab Republic,
  Tanganyika/Zanzibar, North/South Vietnam, Serbia and Montenegro) to
  their successor states, with retired ISO codes where they existed.
  Kosovo is included among the Yugoslav successors on a territory basis
  (documented).
- [`dissolve_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/dissolve_country.md)
  — resolve a mixed vector of historical *and* modern names to successor
  `iso3c` rows (one-to-many, dated); modern names pass through as single
  rows, so a whole messy column pipes in unchanged.
- [`check_country_match()`](https://pursuitofdatascience.github.io/countryatlas/reference/check_country_match.md)
  gains a `historical` column. It flags dissolved entities **even when
  countrycode “matches” them** — the headline case is `"USSR"`, which
  countrycode silently resolves to Russia’s `RUS`, so Soviet-era data
  becomes Russian data with no warning.
- [`correlate_indicators()`](https://pursuitofdatascience.github.io/countryatlas/reference/correlate_indicators.md)
  — pairwise indicator correlations on the spine (pearson/spearman,
  pairwise-complete, per-pair `n`), tidy long output.
- [`beta_convergence()`](https://pursuitofdatascience.github.io/countryatlas/reference/beta_convergence.md)
  /
  [`sigma_convergence()`](https://pursuitofdatascience.github.io/countryatlas/reference/sigma_convergence.md)
  — the two standard convergence diagnostics: the
  growth-on-initial-level regression (with implied convergence speed and
  half-life) and per-year cross-country dispersion.
- [`gini()`](https://pursuitofdatascience.github.io/countryatlas/reference/gini.md)
  and
  [`theil()`](https://pursuitofdatascience.github.io/countryatlas/reference/theil.md)
  — inequality across countries, population-weightable;
  [`theil()`](https://pursuitofdatascience.github.io/countryatlas/reference/theil.md)
  decomposes exactly into between/within components when a grouping
  (continent, income) is supplied.
- [`lag_by_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/lag_by_country.md)
  /
  [`diff_by_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/lag_by_country.md)
  — panel lag and difference grouped by `iso3c` and ordered by `year`,
  completing the panel toolkit around
  [`growth_rate()`](https://pursuitofdatascience.github.io/countryatlas/reference/growth_rate.md)
  /
  [`index_to()`](https://pursuitofdatascience.github.io/countryatlas/reference/index_to.md)
  /
  [`complete_years()`](https://pursuitofdatascience.github.io/countryatlas/reference/complete_years.md).
- [`morans_i()`](https://pursuitofdatascience.github.io/countryatlas/reference/morans_i.md)
  — global Moran’s I with a permutation pseudo-p-value, computed on the
  row-standardised
  [`country_borders()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_borders.md)
  adjacency. No `spdep` dependency: the weights come from the package’s
  own curated topology.
- [`spike_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/spike_map.md)
  — triangular spikes at country centroids (height ∝ value), the
  overplotting-resistant cousin of
  [`bubble_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/bubble_map.md);
  needs only `maps`.
- [`convert_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/convert_country.md)
  accepts `to = "name_<lang>"` (`"name_fr"`, `"name_es"`, `"name_zh"`,
  …) for localized country names via countrycode’s CLDR tables.
- `world_map(style = "binned")` legends now show SI-formatted breaks
  (`4M`, not `4e+06`) when `scales` is installed; the continuous scale
  uses the same formatter.

### Bug fixes

- `world_map(style = "quantile"/"jenks")` computed breaks over polygon
  **vertices**, so a country’s geometric complexity biased the quantiles
  and the bins held unequal numbers of countries. Breaks are now
  computed on one value per country.
- `bubble_map(backend = "sf")` placed bubbles in projected metres on a
  degrees base map (off the map). The base map and bubbles now share one
  projected CRS via
  [`coord_sf()`](https://ggplot2.tidyverse.org/reference/ggsf.html).
- Polygon centroids returned more than one row for ten `iso3c` codes
  (overrides map several names — Azores/Madeira → PRT — to one code),
  fanning out joins in
  [`bubble_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/bubble_map.md)
  /
  [`flow_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/flow_map.md).
  Centroids are now one antimeridian-safe row per country (the largest
  piece).
- [`geom_country_labels()`](https://pursuitofdatascience.github.io/countryatlas/reference/geom_country_labels.md)
  placed labels at the bounding-box midpoint over all of a country’s
  pieces, so the US / Fiji / NZ labels drifted into the wrong ocean.
  Labels now sit on each country’s largest piece.
- `projection = "plate_carree"` built an incoherent PROJ string
  (`+proj=longlat … +units=m`); it is now true equirectangular
  (`+proj=eqc`).
- [`convert_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/convert_country.md)
  only applied
  [`wdj_overrides()`](https://pursuitofdatascience.github.io/countryatlas/reference/wdj_overrides.md)
  for `to = "iso3c"`, so override-only entities (e.g. “Canary Islands”,
  “Azores”, “Bonaire”) returned `NA` for every other destination
  (continent, region, iso2c, flag, currency, country name, …). It now
  resolves the override-corrected `iso3c` first and derives every other
  destination from that.
- Kosovo’s `XKX` needed extra care: it has no row at all in
  [`countrycode::codelist`](https://vincentarelbundock.github.io/countrycode/man/codelist.html),
  so deriving destinations purely via the `iso3c` round-trip above is
  `NA` for everything — which would have *regressed*
  `flag`/`region`/`country`, since 1.0.0 already resolved those via
  direct name matching (verified against the actual 1.0.0 code).
  [`convert_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/convert_country.md)
  now recovers from the original name when the `iso3c` round-trip comes
  back empty, and fills `iso2c`/`continent` (which neither path
  classifies) from the same curated fallback
  [`standardize_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/standardize_country.md)
  uses. Net effect versus 1.0.0: zero regressions, plus newly-working
  `continent`/`iso2c` for Kosovo — which also fixes
  `locate_country(..., add = "continent")` for points inside it.
- `interactive_map(..., tooltip = )` was accepted but silently ignored
  by every engine (pre-dating 2.0.0). The `"ggiraph"` and `"leaflet"`
  engines now use the supplied `tooltip` column, defaulting to `fill` as
  before when omitted.
- `world_data(overrides = )` (and `attach_geometry(overrides = )`)
  accepted a custom name -\> iso3c override set but silently ignored it
  (pre-dating 2.0.0) – the geometry backend always matched with the
  default
  [`wdj_overrides()`](https://pursuitofdatascience.github.io/countryatlas/reference/wdj_overrides.md).
  The override set now flows through to both the polygon and `sf`
  matchers, so a custom mapping actually changes which polygons a
  country claims.
- [`repair_country_names()`](https://pursuitofdatascience.github.io/countryatlas/reference/repair_country_names.md)
  no longer records a no-op “repair” when a dissolved entity’s own name
  (e.g. “Yugoslavia”, which exists in the codelist but has no ISO code)
  comes back as its closest suggestion;
  [`dissolve_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/dissolve_country.md)
  is the right tool there and is what the report now points to.

### Housekeeping

- New hex logo, drawn by the package itself (`data-raw/hex_logo.R`): an
  orthographic globe —
  [`globe_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/globe_map.md)’s
  projection — carrying a viridis choropleth of `world_snapshot` GDP per
  capita on Natural Earth geometry joined by
  [`attach_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/attach_geometry.md),
  with
  [`spike_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/spike_map.md)-style
  population spikes rising off the horizon and the binned-legend
  swatches under the wordmark.
- The `gdp_per_capita_2015` compatibility alias (a one-cycle deprecation
  shim from 1.0.0) is now opt-in: set
  `options(countryatlas.gdp_compat = TRUE)` to restore it. The default
  is `FALSE`, so
  [`world_data()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_data.md)
  no longer emits a duplicate column.
- `world_snapshot` refreshed to year **2024** (was 2022) and rebuilt
  with the latest WDI data and curated overrides.
- `country_groups_tbl` membership date bumped to 2026-06-01 (was
  2024-01-01).
- [`?world_snapshot`](https://pursuitofdatascience.github.io/countryatlas/reference/world_snapshot.md)
  was out of sync with the rebuilt data (missing the “Snapshot year:
  2024” note); regenerated.
- Fixed a stray orphaned code fence at the end of the *countryatlas and
  ggsql* vignette that broke its markdown structure.
- README and vignettes now demonstrate every exported function:
  [`wdi_search()`](https://pursuitofdatascience.github.io/countryatlas/reference/wdi_search.md),
  [`country_codes()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_codes.md),
  [`complete_years()`](https://pursuitofdatascience.github.io/countryatlas/reference/complete_years.md),
  [`growth_rate()`](https://pursuitofdatascience.github.io/countryatlas/reference/growth_rate.md)
  /
  [`index_to()`](https://pursuitofdatascience.github.io/countryatlas/reference/index_to.md),
  [`repair_country_names()`](https://pursuitofdatascience.github.io/countryatlas/reference/repair_country_names.md),
  [`country_join_all()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_join_all.md),
  [`locate_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/locate_country.md)
  and
  [`facet_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/facet_map.md)
  gained worked examples, and the vignettes prefer
  [`country_overrides()`](https://pursuitofdatascience.github.io/countryatlas/reference/wdj_overrides.md)
  over the soft-deprecated
  [`wdj_overrides()`](https://pursuitofdatascience.github.io/countryatlas/reference/wdj_overrides.md).
  The README’s rendered output and figures were stale (pre-dating the
  quantile-breaks fix and the `gdp_per_capita_2015` opt-in) and have
  been re-rendered from the 2.0.0 code.

## countryatlas 1.0.0

CRAN release: 2026-06-24

A single, comprehensive release that takes the package from a
one-function proof of concept to a complete toolkit for joining world
data to maps. The spirit is unchanged — *ISO codes as the universal join
key, one call to a map-ready table* — but pushed to its full potential.

### Breaking-ish changes

- [`world_data()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_data.md)
  is generalised but backward-compatible: `world_data(2020)` still
  returns the classic polygon-backed, GDP-per-capita tibble. The only
  visible change is the column name `gdp_per_capita_2015` →
  `gdp_per_capita`. A one-cycle deprecation shim keeps
  `gdp_per_capita_2015` available as an alias (toggle with
  `options(countryatlas.gdp_compat = FALSE)`).
- The 16 regions the previous version silently dropped (Kosovo,
  Micronesia, the Virgin Islands, Saint Martin, Bonaire/Saba/Sint
  Eustatius, the Canary Islands, Madeira/Azores, …) are now **matched**
  via
  \[[`wdj_overrides()`](https://pursuitofdatascience.github.io/countryatlas/reference/wdj_overrides.md)\]
  instead of deleted, so they appear on maps. Diffs of map output will
  show increased coverage.

### New: core data assembly

- [`world_data()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_data.md)
  gains `indicator` (one or many WDI codes; named vectors drive clean
  column names), multi-year **panels**, an `sf` backend
  (`geometry = "sf"`), `region` subsetting, `latest`, projections and
  caching.
- [`country_data()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_data.md)
  — the lightweight, one-row-per-country analysis table.
- [`world_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_geometry.md)
  — projected, region-subset geometry (countries, centroids, coastline,
  borders, graticule, ocean).

### New: the join engine (exposed for *your* data)

- [`standardize_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/standardize_country.md),
  [`join_world()`](https://pursuitofdatascience.github.io/countryatlas/reference/join_world.md),
  [`attach_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/attach_geometry.md),
  [`country_join()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_join.md).

### New: diagnostics

- [`check_country_match()`](https://pursuitofdatascience.github.io/countryatlas/reference/check_country_match.md),
  [`wdj_overrides()`](https://pursuitofdatascience.github.io/countryatlas/reference/wdj_overrides.md),
  [`audit_coverage()`](https://pursuitofdatascience.github.io/countryatlas/reference/audit_coverage.md)
  — never lose a country silently.

### New: reference data & translation

- [`convert_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/convert_country.md)
  (flags, currency, tld, research codes),
  [`country_codes()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_codes.md),
  [`country_groups()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_groups.md)
  /
  [`in_group()`](https://pursuitofdatascience.github.io/countryatlas/reference/in_group.md),
  [`wdi_search()`](https://pursuitofdatascience.github.io/countryatlas/reference/wdi_search.md).
- Bundled datasets: `world_snapshot`, `country_meta`,
  `common_indicators`, `country_groups_tbl`, `world_tiles`.

### New: analysis helpers

- [`per_capita()`](https://pursuitofdatascience.github.io/countryatlas/reference/per_capita.md),
  [`aggregate_regions()`](https://pursuitofdatascience.github.io/countryatlas/reference/aggregate_regions.md),
  [`rank_countries()`](https://pursuitofdatascience.github.io/countryatlas/reference/rank_countries.md),
  [`complete_years()`](https://pursuitofdatascience.github.io/countryatlas/reference/complete_years.md).

### New: visualization

- [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md)
  (continuous / binned / quantile / jenks / categorical),
  [`bubble_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/bubble_map.md),
  [`bivariate_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/bivariate_map.md),
  [`cartogram_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/cartogram_map.md),
  [`tile_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/tile_map.md),
  [`flow_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/flow_map.md),
  [`animate_world()`](https://pursuitofdatascience.github.io/countryatlas/reference/animate_world.md),
  [`interactive_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/interactive_map.md),
  [`geom_country_labels()`](https://pursuitofdatascience.github.io/countryatlas/reference/geom_country_labels.md),
  [`theme_world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/theme_world_map.md).

### Performance & offline

- WDI fetches are memoised with an optional on-disk cache; multiple
  indicators are fetched in parallel
  ([`parallel::mclapply`](https://rdrr.io/r/parallel/mclapply.html))
  where supported. See
  [`clear_wdi_cache()`](https://pursuitofdatascience.github.io/countryatlas/reference/clear_wdi_cache.md).
- The bundled `world_snapshot` lets every example, test and vignette run
  offline and deterministically.

### Engineering

- Namespace hygiene (targeted `@importFrom` instead of blanket
  `@import`).
- Input validation with friendly `cli` / `rlang` errors.
- A `testthat` (3e) suite; network calls are skipped offline and on
  CRAN.
- Vignettes and a `pkgdown` site.
- Refreshed CI: R-CMD-check, test-coverage and pkgdown workflows.
- Heavy spatial dependencies (`sf`, `rnaturalearth`, `cartogram`,
  `biscale`, `geofacet`, `gganimate`, `leaflet`, …) are all in
  `Suggests` and gated by
  [`rlang::check_installed()`](https://rlang.r-lib.org/reference/is_installed.html),
  so the base install stays light.

Group memberships in `country_groups_tbl` are point-in-time as of
2024-01-01.

## countryatlas 0.1.0

- Initial experimental release with a single `world_data(year)`
  function.
