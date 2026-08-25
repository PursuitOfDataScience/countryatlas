# Changelog

## countryatlas 2.0.1

A patch release. The only behaviour change is to a test and to where an
optional DuckDB connection keeps its state; nothing in the package’s own
API moves.

### CRAN check failures

- `test-standardize.R`’s de-accenting test failed on CRAN’s two r-devel
  Fedora flavours, which run in a latin1 locale. The test asserted that
  outside a UTF-8 locale `iconv(x, to = "ASCII//TRANSLIT")` cannot
  produce a resolvable spelling – generalising from `LC_CTYPE=C`, which
  is the case
  [`?country_overrides`](https://pursuitofdatascience.github.io/countryatlas/reference/wdj_overrides.md)
  actually documents. That is not what glibc does: the `\u00e7` escape
  makes the input UTF-8 *marked* in every locale, so `iconv` reads it as
  UTF-8 and only the target charmap matters. Latin-1 has transliteration
  data and still yields `"Curacao"`; only `C`/POSIX, which has none,
  degrades to `NA` or `"Cura?ao"`. The test now asserts the invariant
  that holds in every locale – de-accenting may or may not resolve, but
  it never resolves to a *different* country – and passes under `C`,
  latin1, latin9 and UTF-8.

### Housekeeping

- `as_ggsql_source(format = "duckdb")` now opens its connection with
  `duckdb(shared_home = FALSE)` where the installed duckdb supports it
  (1.4 and later). By default duckdb keeps downloaded extensions and
  secrets in `~/.duckdb`, which a throwaway in-memory table has no
  business creating in the user’s home; `R CMD check` also reports a new
  `~/.duckdb` among “new files in some other directories”.
- The test suite no longer writes into the checking account’s file
  space. Rendering one `girafe()` widget – which
  `interactive_map(engine = "ggiraph")` does, and which no 1.0.0 test
  did – makes `gdtools` copy 90 Liberation font files into
  `tools::R_user_dir("gdtools", "data")`. `R CMD check` snapshots that
  tree and reports anything new, which is the NOTE CRAN raised against
  1.0.0 for our own WDI cache (fixed separately, in `wdj_cache_dir()`).
  A new `tests/testthat/setup-user-dirs.R` points the R user directories
  at the session temp directory before any test runs, so the widget
  still renders, just somewhere disposable.
- [`?clear_wdi_cache`](https://pursuitofdatascience.github.io/countryatlas/reference/clear_wdi_cache.md)
  claimed nothing was written until a World Bank fetch succeeded, so an
  offline session “never creates” the cache directory. The directory is
  in fact created the first time a *cached* fetch is attempted, because
  that is when the location has to be proved writable – a failed fetch
  leaves it behind empty. The help page now describes what happens.

## countryatlas 2.0.0

CRAN release: 2026-08-25

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

- [`bivariate_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/bivariate_map.md)
  errored on every call (“the condition has length \> 1”, pre-dating
  2.0.0). The two fill columns were injected into
  [`biscale::bi_class()`](https://chris-prener.github.io/biscale/reference/bi_class.html)
  with `!!rlang::sym()`, but `bi_class()` reads them with
  `as.character(substitute(...))` rather than tidy eval, so the
  injection deparsed into a multi-element vector inside `biscale`. The
  happy path is now covered by a test (the old one only checked that the
  function errors cleanly when `sf` is *absent*).
- [`as_ggsql_source()`](https://pursuitofdatascience.github.io/countryatlas/reference/as_ggsql_source.md)
  and `interactive_map(engine = "ggsql")` errored on any `sf` input –
  the whole point of the ggsql bridge.
  [`sf::st_as_binary()`](https://r-spatial.github.io/sf/reference/st_as_binary.html)
  returns a classed `WKB` object, which `tibble` rejects (“all columns
  must be vectors”); the geometry column is now the plain list of raw
  vectors that `nanoarrow` encodes as binary and `DBI` writes as a
  `BLOB`.
- `projection = "winkel_tripel"` errored on every render – one of the
  eight projections this release adds. The CRS built fine and the
  geometry projected fine, but
  [`ggplot2::coord_sf()`](https://ggplot2.tidyverse.org/reference/ggsf.html)’s
  graticule collapses to a degenerate single-point segment under PROJ’s
  Winkel Tripel, which GEOS rejects (“point array must contain 0 or \>1
  elements”). The graticule is now skipped for that projection only;
  \[theme_world_map()\] blanks `panel.grid` anyway, so nothing visible
  changes. All 13 projections are now covered by a full-render test.
- `world_geometry("coastline", geometry = "sf")` errored with a GEOS
  `TopologyException` in every projection except `"plate_carree"`: a
  couple of Natural Earth rings are self-intersecting and
  [`sf::st_union()`](https://r-spatial.github.io/sf/reference/geos_combine.html)
  (unlike the spatial predicates) refuses them. The geometry is repaired
  before the union.
- `world_geometry(region = c(xmin, ymin, xmax, ymax))` – and
  [`world_data()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_data.md)
  /
  [`attach_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/attach_geometry.md)
  with a bounding-box `region` – errored on the `sf` backend (“Loop 0 is
  not valid”), because
  [`sf::st_crop()`](https://r-spatial.github.io/sf/reference/st_crop.html)
  runs under the strict S2 engine on unprojected geometry. It now clips
  with the GEOS planar predicate, as
  [`country_borders()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_borders.md)
  /
  [`locate_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/locate_country.md)
  already did.
- [`convert_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/convert_country.md)’s
  `warn` argument was documented but silently ignored (every internal
  `countrycode()` call is wrapped in
  [`suppressWarnings()`](https://rdrr.io/r/base/warning.html), because
  countrycode also warns on intermediate hops that
  [`convert_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/convert_country.md)
  goes on to recover). It now reports inputs that match no country, like
  [`standardize_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/standardize_country.md)
  does. A recognised country whose destination value is genuinely
  missing still returns `NA` quietly.
- [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md)
  /
  [`globe_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/globe_map.md)’s
  `na_label` was accepted and silently ignored. The `"quantile"`,
  `"jenks"` and `"categorical"` legends now label their missing-data key
  with it (the continuous and binned colourbars have no `NA` key to
  name, which the documentation now says).
- Kosovo’s `XKX` resolves for `country` and `flag` from
  `from = "iso3c"`, not just from its name. It has no row at all in
  [`countrycode::codelist`](https://rdrr.io/pkg/countrycode/man/codelist.html),
  so everything derived from the code was `NA` – which surfaced as
  [`country_borders()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_borders.md)
  /
  [`neighbors()`](https://pursuitofdatascience.github.io/countryatlas/reference/neighbors.md)
  returning `NA` names for Kosovo’s four land borders,
  `locate_country(add = "country")` returning `NA` for points inside it,
  and `standardize_country(add = c("country", "flag"))` doing the same.
  The curated fallback table now carries the name and flag too.
- [`per_capita()`](https://pursuitofdatascience.github.io/countryatlas/reference/per_capita.md)
  without an explicit `pop` column died with an opaque `vctrs` error
  (“Can’t subset columns that don’t exist: `.wdj_pop`”) when the World
  Bank population fetch failed or timed out – `fetch_wdi()` deliberately
  degrades to a keys-only tibble in that case. It now reports the failed
  fetch and points at the `pop` argument.
- [`theil()`](https://pursuitofdatascience.github.io/countryatlas/reference/theil.md)
  returns `NA` shares (not `NaN`) for a perfectly equal distribution,
  where the total is `0` and the shares are undefined – matching how
  [`gini()`](https://pursuitofdatascience.github.io/countryatlas/reference/gini.md)
  and
  [`share_of_world()`](https://pursuitofdatascience.github.io/countryatlas/reference/share_of_world.md)
  treat a zero denominator.
- [`country_join()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_join.md)
  /
  [`country_join_all()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_join_all.md)
  no longer cross-join rows whose `iso3c` is `NA`: unmatched countries
  used to collapse to a single `NA` key and fan out into a Cartesian
  product. The joins now pass `na_matches = "never"`
  ([\#4](https://github.com/PursuitOfDataScience/countryatlas/issues/4)).
- [`country_join_all()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_join_all.md)
  validates the length of `origin` (must be 1 or one per table) instead
  of failing with a cryptic “missing value where TRUE/FALSE needed”
  error
  ([\#16](https://github.com/PursuitOfDataScience/countryatlas/issues/16)).
- [`join_world()`](https://pursuitofdatascience.github.io/countryatlas/reference/join_world.md)’s
  auto-detection (`detect_country_col()`) honours the candidate priority
  order instead of picking the first column by data-frame position, so a
  `region` column no longer shadows a real `country` column
  ([\#6](https://github.com/PursuitOfDataScience/countryatlas/issues/6)).
- `standardize_country(add = ...)` accepts any raw `countrycode`
  destination (e.g. `"iso3n"`) again instead of erroring with “subscript
  out of bounds”
  ([\#5](https://github.com/PursuitOfDataScience/countryatlas/issues/5)).
- `standardize_country(origin = "iso3c")` now validates codes: strings
  that are not real ISO 3166-1 alpha-3 codes become `NA` (and are
  flagged by `warn`) rather than passing through uppercased and
  unchecked
  ([\#12](https://github.com/PursuitOfDataScience/countryatlas/issues/12)).
- `country_data(latest = TRUE)` / `world_data(latest = TRUE)` for a
  single year now returns each country’s most recent non-`NA` value: the
  fetch window is widened so an earlier observation can actually be
  found
  ([\#7](https://github.com/PursuitOfDataScience/countryatlas/issues/7)).
- `fetch_wdi()` keeps `iso2c` / `country` for a country that appears
  only in a non-first indicator (they are coalesced across indicators)
  instead of leaving them `NA`
  ([\#8](https://github.com/PursuitOfDataScience/countryatlas/issues/8)).
- [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md)
  /
  [`globe_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/globe_map.md)
  with `style = "quantile"` / `"jenks"` no longer error on a constant,
  single-country, or all-`NA` value column; degenerate breaks now fall
  back to a single bin
  ([\#9](https://github.com/PursuitOfDataScience/countryatlas/issues/9)).
- [`flow_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/flow_map.md)
  returns the base map (instead of erroring) when no origin-destination
  pair resolves to a centroid
  ([\#10](https://github.com/PursuitOfDataScience/countryatlas/issues/10)).
- `aggregate_regions(fun = "min"/"max")` returns `NA` for an all-`NA`
  group instead of `Inf` / `-Inf`
  ([\#11](https://github.com/PursuitOfDataScience/countryatlas/issues/11)).
- [`share_of_world()`](https://pursuitofdatascience.github.io/countryatlas/reference/share_of_world.md)
  returns `NA` (not `NaN`/`Inf`) when the (per-year) total is zero or
  non-finite
  ([\#13](https://github.com/PursuitOfDataScience/countryatlas/issues/13)).
- [`gini()`](https://pursuitofdatascience.github.io/countryatlas/reference/gini.md)
  returns `NA` with a warning for negative input rather than a value
  outside the documented `[0, 1]` range
  ([\#14](https://github.com/PursuitOfDataScience/countryatlas/issues/14)).
- [`spike_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/spike_map.md)
  no longer produces `NaN` spike coordinates when every height is zero
  ([\#15](https://github.com/PursuitOfDataScience/countryatlas/issues/15)).
- [`world_query()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_query.md)
  honours `transform` even when `palette = NULL`, emitting a standalone
  `SCALE fill VIA <transform>` clause
  ([\#17](https://github.com/PursuitOfDataScience/countryatlas/issues/17)).
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
  [`countrycode::codelist`](https://rdrr.io/pkg/countrycode/man/codelist.html),
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
- A mistyped column name is now reported by countryatlas rather than
  leaking out of `ggplot2` as a bare “object ‘x’ not found” from inside
  a layer, or out of `vctrs` as a subscript error.
  [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md),
  [`globe_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/globe_map.md),
  [`facet_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/facet_map.md),
  [`tile_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/tile_map.md),
  [`bubble_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/bubble_map.md)
  (both `size` and `color`),
  [`spike_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/spike_map.md),
  [`flow_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/flow_map.md)
  (`from`, `to` and `weight`),
  [`interactive_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/interactive_map.md)
  (`fill` and `tooltip`) and
  [`morans_i()`](https://pursuitofdatascience.github.io/countryatlas/reference/morans_i.md)
  all validate up front, matching the message
  [`per_capita()`](https://pursuitofdatascience.github.io/countryatlas/reference/per_capita.md)
  /
  [`rank_countries()`](https://pursuitofdatascience.github.io/countryatlas/reference/rank_countries.md)
  /
  [`bivariate_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/bivariate_map.md)
  already gave.
  [`morans_i()`](https://pursuitofdatascience.github.io/countryatlas/reference/morans_i.md)
  in particular used to blame the geometry (“not enough bordering
  countries with data”) for a column that simply wasn’t there.
- `audit_coverage(indicator = )` silently reported `n_missing = 0` and
  `na_rate = NaN` for a column name that isn’t in `data`; it now errors.
- [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md)
  /
  [`globe_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/globe_map.md)
  errored (“‘length = 2’ in coercion to ‘logical(1)’”) when `na_label`
  was longer than one element. The first element is used to label the
  single `NA` key, and a `NULL` / `NA` label still leaves the default
  formatter alone.
- [`per_capita()`](https://pursuitofdatascience.github.io/countryatlas/reference/per_capita.md)
  sent `start = Inf` to the World Bank when `data` had a `year` column
  that was entirely `NA`; it now falls back to last year, as it already
  did for a frame with no `year` column at all. Its degraded-fetch guard
  also covers the join keys now, so a partial population fetch produces
  the actionable “pass a population column” error rather than a raw
  `vctrs` subscript error.
- [`theil()`](https://pursuitofdatascience.github.io/countryatlas/reference/theil.md)
  returned `NaN` when every weight was zero; it now returns `NA`,
  matching
  [`gini()`](https://pursuitofdatascience.github.io/countryatlas/reference/gini.md).
- [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md)
  /
  [`globe_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/globe_map.md)
  with `style = "categorical"` and a numeric `fill` column let `ggplot2`
  raise “Continuous value supplied to a discrete scale” at *build* time,
  naming neither the column nor the style. They now error at the call,
  name the column, and point at `"quantile"` / `"jenks"` / `"binned"`.
- [`bivariate_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/bivariate_map.md)
  no longer leaks `biscale`’s “var has missing values, omitted in
  finding classes” warning, which fired on essentially every call
  because real indicators always have gaps (the classes were valid
  either way). Any other `biscale` warning still passes through.
- A `region` given as lowercase `iso3c` codes silently lost countries.
  Falling through to name matching resolved some codes by accident
  (countrycode’s country-name regex is case-insensitive, so `"usa"`
  matched) but not others (`"can"` did not), so
  `region = c("usa", "can")` subset to the USA alone. Codes are now
  recognised in any case, matching what
  `standardize_country(origin = "iso3c")` already accepted; an
  all-uppercase unknown code is still taken at face value rather than
  reinterpreted as a country name.
- [`country_codes()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_codes.md)
  silently dropped a column name it did not recognise, so a typo
  returned a table quietly missing that column; it now errors and lists
  the available shortcuts.
- Every `sf`-backed call printed three or more lines of `sf` internals
  to the console – `"Spherical geometry (s2) switched off"`,
  `st_intersection`’s
  `"although coordinates are longitude/latitude ... assumes that they are planar"`,
  and the matching `"switched on"`. The source was
  [`sf::st_break_antimeridian()`](https://r-spatial.github.io/sf/reference/st_break_antimeridian.html),
  which toggles the s2 engine and runs an intersection internally, and
  which sits on the path of *every* `sf` call: a plain
  `attach_geometry(geometry = "sf")` emitted them, as did
  [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md),
  [`world_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_geometry.md),
  [`country_borders()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_borders.md),
  [`neighbors()`](https://pursuitofdatascience.github.io/countryatlas/reference/neighbors.md),
  [`morans_i()`](https://pursuitofdatascience.github.io/countryatlas/reference/morans_i.md),
  [`locate_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/locate_country.md)
  and
  [`simplify_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/simplify_geometry.md).
  It is now wrapped in the same `quietly_sf()` helper the other `sf`
  calls already used, so those paths are silent. (The notices bypass R’s
  condition system, so
  [`suppressMessages()`](https://rdrr.io/r/base/message.html) could not
  have caught them.)
- [`cartogram_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/cartogram_map.md)
  /
  [`dorling_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/dorling_map.md)
  never validated their `weight` or `fill` column, the one place the
  rest of the package’s existence checks were missed. A bad `weight`
  reached `cartogram` as `"missing value where TRUE/FALSE needed"` (or,
  for the Dorling variant, a warning about
  [`max()`](https://rdrr.io/r/base/Extremes.html) and then a wrong
  picture), and a bad `fill` was not caught at all.
- [`index_to()`](https://pursuitofdatascience.github.io/countryatlas/reference/index_to.md)
  likewise never checked its value column, so a typo produced a `dplyr`
  error from inside
  [`mutate()`](https://dplyr.tidyverse.org/reference/mutate.html);
  `base_year` and `to` are validated too.
- Scalar arguments are validated, so a typo or an `NA` names the
  argument instead of surfacing as
  `"missing value where TRUE/FALSE needed"`, `classInt`’s
  `"n less than 2"`, or a `PROJ` complaint about `lat_0`. Covers
  `n_bins`
  ([`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md)
  /
  [`globe_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/globe_map.md),
  on the binned path as well as the quantile/jenks one),
  `lon`/`lat`/`recenter`/`lat0`
  ([`globe_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/globe_map.md)
  on **both** backends – the polygon one goes to
  [`coord_map()`](https://ggplot2.tidyverse.org/reference/coord_map.html)
  and previously accepted a nonsense orientation silently), `n`
  ([`flow_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/flow_map.md)),
  `max_height` / `width` / `alpha`
  ([`spike_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/spike_map.md)),
  `max_size` / `alpha`
  ([`bubble_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/bubble_map.md)),
  `keep`
  ([`simplify_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/simplify_geometry.md)),
  `threshold`
  ([`repair_country_names()`](https://pursuitofdatascience.github.io/countryatlas/reference/repair_country_names.md)),
  `n_perm`
  ([`morans_i()`](https://pursuitofdatascience.github.io/countryatlas/reference/morans_i.md)),
  and `n_frames` / `fps` / `width` / `height`
  ([`spin_globe()`](https://pursuitofdatascience.github.io/countryatlas/reference/spin_globe.md)).
- Two of those scalar arguments were not merely reported badly – they
  drew the wrong thing in silence. A negative `max_height` drew
  [`spike_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/spike_map.md)’s
  spikes upside down, and `globe_map(lat = )` beyond +/-90 built a CRS
  `PROJ` rejects, which only surfaced later as
  [`coord_sf()`](https://ggplot2.tidyverse.org/reference/ggsf.html)’s
  `"crs not found: is it missing?"`.
- `geom_country_labels(repel = TRUE)` silently drew plain labels when
  `ggrepel` was not installed – the one degraded optional backend the
  package did not announce, where `classInt`, `gganimate` and
  `rmapshaper` all report theirs. It now says so once per session (the
  argument defaults to `TRUE`, so reporting on every call would be
  noise), and stays quiet when `repel = FALSE` was asked for.
- The number of bins no longer depends on whether `classInt` is
  installed. For a fractional `n_bins`, `classInt` truncated internally
  while the base-quantile fallback passed the fraction to
  `seq(length.out = )` and produced one break more, so the same call
  binned differently in different environments. `n_bins` is now
  truncated to a whole number of bins before either backend sees it.
- `simplify_geometry(keep = 0)` errored under `rmapshaper` but was
  silently accepted by the
  [`sf::st_simplify()`](https://r-spatial.github.io/sf/reference/geos_unary.html)
  fallback, so the same call behaved differently depending on which
  optional package the caller had installed. A proportion of zero keeps
  no vertices, and both paths now reject it.
- Count arguments are bounded above as well as below. The scalar checks
  required a finite number, but several call sites then coerce with
  [`as.integer()`](https://rdrr.io/r/base/integer.html), which returns
  `NA` past `2^31-1` – so `n_perm = 1e10` or `n_bins = 1e10` produced
  “NAs introduced by coercion” or, worse, “missing value where
  TRUE/FALSE needed”. `n_bins`, `n`
  ([`flow_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/flow_map.md),
  [`lag_by_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/lag_by_country.md),
  [`diff_by_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/lag_by_country.md)),
  `n_perm` and `n_frames` now name the range.
  [`morans_i()`](https://pursuitofdatascience.github.io/countryatlas/reference/morans_i.md)
  also dropped a `max(0L, ...)` clamp that the validation had made
  unreachable.
- [`lag_by_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/lag_by_country.md)
  /
  [`diff_by_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/lag_by_country.md)
  clamped `n <= 0` up to `1`, so a lag of `0` quietly returned a lag of
  `1`; it now errors.
- `complete_years(value = )` silently ignored a column name that wasn’t
  in `data` under the default `method = "none"`, while erroring from
  [`all_of()`](https://tidyselect.r-lib.org/reference/all_of.html) for
  `"locf"` / `"linear"`; it now errors consistently.
- `interactive_map(engine = "ggsql")` now gates on `ggsql` \>= 0.4.1
  rather than mere presence. `DRAW spatial` – the clause
  [`world_query()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_query.md)
  emits – arrived in the ggsql *engine* at 0.4.0, while the ggsql R
  package is still 0.3.3, which accepted the call and then failed inside
  its own SQL front end on a clause it did not know. The gate now
  refuses with an actionable message instead.
  [`?world_query`](https://pursuitofdatascience.github.io/countryatlas/reference/world_query.md)
  records that the clause has shipped in the engine but not yet in the R
  bindings, and that `PROJECT TO` additionally needs a spatial backend
  (for DuckDB, its `spatial` extension);
  [`world_query()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_query.md)
  itself remains a dependency-free string builder.
- `R CMD check` no longer writes to the checking user’s persistent
  cache. The `\donttest{}` examples fetch from the World Bank, so the
  memoised on-disk cache was being populated under
  [`tools::R_user_dir()`](https://rdrr.io/r/tools/userdir.html) during a
  check; under check it now lives in the session temp directory instead.
  Normal use is unchanged, and `options(countryatlas.cache_dir = )`
  still overrides both.
  [`?clear_wdi_cache`](https://pursuitofdatascience.github.io/countryatlas/reference/clear_wdi_cache.md)
  now documents where the cache lives and how to disable it.
- An unmatched country in your data could be drawn as a real country.
  dplyr joins default to `na_matches = "na"`, so an `NA` ISO code
  matched another `NA` ISO code – and Natural Earth carries Somaliland
  as a polygon with no ISO code. Any row whose country failed to resolve
  therefore joined onto Somaliland’s geometry and was plotted there;
  with two or more unmatched rows the join also fanned out many-to-many,
  duplicating that polygon once per row so the visible fill was
  whichever happened to be drawn last. Affected
  `attach_geometry(geometry = "sf")` (and so
  [`join_world()`](https://pursuitofdatascience.github.io/countryatlas/reference/join_world.md)
  and
  [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md)
  downstream of it) and `bubble_map(backend = "sf")`. All country-keyed
  joins in the package now pass `na_matches = "never"`, which
  [`country_join()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_join.md)
  and
  [`country_join_all()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_join_all.md)
  already did; the keyless polygon is still drawn, now correctly as a
  no-data feature. A test asserts the invariant across the whole
  namespace so a new join cannot reintroduce it.
- [`world_query()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_query.md)
  emitted a silently malformed query for any argument that was not a
  single string. [`sprintf()`](https://rdrr.io/r/base/sprintf.html)
  vectorises, so `projection = c("a", "b")` produced two `PROJECT TO`
  clauses, `source = character(0)` deleted the `FROM` line entirely, and
  `title = NA` became the literal text `'NA'` – each of which surfaced
  only later, as a parse error inside ggsql’s SQL front end.
  [`world_query()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_query.md)
  and
  [`as_ggsql_source()`](https://pursuitofdatascience.github.io/countryatlas/reference/as_ggsql_source.md)
  now validate their string arguments up front and name the offending
  one. `NULL` still omits an optional clause, and an empty `title` is
  still allowed.
- `as_ggsql_source(format = "parquet")` built its `COPY ... TO '<path>'`
  statement by string interpolation, so a path containing an apostrophe
  – legal in a filename – closed the SQL literal early and broke the
  statement. The path is now quoted with
  [`DBI::dbQuoteString()`](https://dbi.r-dbi.org/reference/dbQuoteString.html),
  matching the `dbQuoteIdentifier()` treatment the table name already
  had.
- `suffix = character(0)` made the whole computation vanish. `suffix` is
  [`paste0()`](https://rdrr.io/r/base/paste.html)-ed onto the value
  column’s name, and dplyr’s `"{character(0)}" :=` is a silent no-op –
  so `growth_rate(x, g, suffix = character(0))` returned `x` unchanged,
  with no growth column and no error. `suffix = NA` produced a column
  named `gNA`, and `suffix = ""` overwrote the source column in place.
  [`per_capita()`](https://pursuitofdatascience.github.io/countryatlas/reference/per_capita.md),
  [`growth_rate()`](https://pursuitofdatascience.github.io/countryatlas/reference/growth_rate.md),
  [`index_to()`](https://pursuitofdatascience.github.io/countryatlas/reference/index_to.md),
  [`share_of_world()`](https://pursuitofdatascience.github.io/countryatlas/reference/share_of_world.md),
  [`lag_by_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/lag_by_country.md)
  and
  [`diff_by_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/lag_by_country.md)
  now require a single non-empty string
  ([`lag_by_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/lag_by_country.md)/[`diff_by_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/lag_by_country.md)
  still accept `NULL` for the default suffix).
- Several arguments produced an error that named nothing rather than the
  argument at fault:
  - `convert_country(to = c("country", "continent"))` – a plausible
    attempt at two destinations – raised “the condition has length \>
    1”, and a zero-length `to` or `from` raised “argument is of length
    zero”.
  - `origin` did the same across every function that resolves country
    names. It is now validated once in the shared internal, so
    [`standardize_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/standardize_country.md),
    [`country_join()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_join.md),
    [`country_join_all()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_join_all.md),
    [`join_world()`](https://pursuitofdatascience.github.io/countryatlas/reference/join_world.md),
    [`flow_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/flow_map.md),
    [`neighbors()`](https://pursuitofdatascience.github.io/countryatlas/reference/neighbors.md),
    [`distance_between()`](https://pursuitofdatascience.github.io/countryatlas/reference/distance_between.md),
    [`in_group()`](https://pursuitofdatascience.github.io/countryatlas/reference/in_group.md),
    [`repair_country_names()`](https://pursuitofdatascience.github.io/countryatlas/reference/repair_country_names.md)
    and
    [`check_country_match()`](https://pursuitofdatascience.github.io/countryatlas/reference/check_country_match.md)
    are all covered.
  - `attach_geometry(by = character(0))` raised “argument is of length
    zero”.
  - `aggregate_regions(by = character(0))` raised nothing at all: it
    grouped by no columns and silently collapsed the world into a single
    row. `by` remains documented as plural, so multiple grouping columns
    still work.
- Logical arguments are validated too, closing the same gap in two
  forms. The `borders` argument of
  [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md)
  and
  [`globe_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/globe_map.md)
  fed a bare `if ()`, so a bad value raised one of four opaque base R
  errors (“missing value where TRUE/FALSE needed”, “argument is of
  length zero”, “the condition has length \> 1”, “argument is not
  interpretable as logical”) – none naming `borders`. Elsewhere the
  value went through [`isTRUE()`](https://rdrr.io/r/base/Logic.html),
  which never errors but silently turns anything that is not `TRUE` into
  `FALSE`, so the caller got the opposite of what they asked:
  `rank_countries(x, v, desc = "yes")` ranked ascending, putting the
  *lowest* value at rank 1, and `gini(x, na.rm = "yes")` kept the `NA`s
  and returned `NA`. All 23 logical arguments across the package now
  require `TRUE` or `FALSE` and name themselves when they do not get it.
- [`gini()`](https://pursuitofdatascience.github.io/countryatlas/reference/gini.md)
  and
  [`theil()`](https://pursuitofdatascience.github.io/countryatlas/reference/theil.md)
  returned a wrong number for a wrong-length `weights` vector. Both
  recycled it with [`rep_len()`](https://rdrr.io/r/base/rep.html), which
  accepts any length silently, so `gini(1:10, weights = c(1, 2))`
  returned `0.2902` – computed from an alternating 1,2 pattern – where
  the correctly-weighted answer is `0.3`. Someone weighting by
  population and mistakenly passing a vector of the wrong length got a
  plausible figure and no indication anything was wrong. `weights` (and
  [`theil()`](https://pursuitofdatascience.github.io/countryatlas/reference/theil.md)’s
  `groups`) must now be length 1 or the length of `x`, and `weights`
  must be numeric.
  [`complete_years()`](https://pursuitofdatascience.github.io/countryatlas/reference/complete_years.md)
  likewise rejects a `years` vector that is non-numeric, empty, or
  contains `NA`, all of which it previously coerced to `NA` behind base
  R’s warning.
- Omitting a required argument now names it. Every affected function
  resolved its column argument with
  [`rlang::as_name()`](https://rlang.r-lib.org/reference/as_name.html),
  which raises `argument "x" is missing, with no default` for a missing
  value – naming rlang’s own parameter, and none of these functions has
  an argument called `x`.
  [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md),
  [`tile_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/tile_map.md),
  [`facet_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/facet_map.md),
  [`spike_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/spike_map.md),
  [`bubble_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/bubble_map.md),
  [`globe_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/globe_map.md),
  [`interactive_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/interactive_map.md),
  [`rank_countries()`](https://pursuitofdatascience.github.io/countryatlas/reference/rank_countries.md),
  [`growth_rate()`](https://pursuitofdatascience.github.io/countryatlas/reference/growth_rate.md),
  [`per_capita()`](https://pursuitofdatascience.github.io/countryatlas/reference/per_capita.md),
  [`aggregate_regions()`](https://pursuitofdatascience.github.io/countryatlas/reference/aggregate_regions.md),
  [`index_to()`](https://pursuitofdatascience.github.io/countryatlas/reference/index_to.md),
  [`share_of_world()`](https://pursuitofdatascience.github.io/countryatlas/reference/share_of_world.md),
  [`lag_by_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/lag_by_country.md),
  [`diff_by_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/lag_by_country.md),
  [`beta_convergence()`](https://pursuitofdatascience.github.io/countryatlas/reference/beta_convergence.md),
  [`sigma_convergence()`](https://pursuitofdatascience.github.io/countryatlas/reference/sigma_convergence.md),
  [`morans_i()`](https://pursuitofdatascience.github.io/countryatlas/reference/morans_i.md),
  [`world_query()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_query.md),
  [`country_join()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_join.md),
  [`bivariate_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/bivariate_map.md),
  [`cartogram_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/cartogram_map.md)
  and
  [`flow_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/flow_map.md)
  now report e.g. `` `fill` is required. `` Optional tidy-eval arguments
  are unaffected.
- [`distance_between()`](https://pursuitofdatascience.github.io/countryatlas/reference/distance_between.md)
  paired the wrong countries when `a` and `b` had mismatched lengths. It
  combined them through vectorised arithmetic, so R’s recycling applied:
  2 countries against 3 returned `a[1]`-`b[1]`, `a[2]`-`b[2]` and
  `a[1]`-`b[3]`, behind only base R’s “longer object length is not a
  multiple” warning, and 2 against 4 recycled cleanly with no warning at
  all. Equal lengths, or a length-1 side for one-against-many, are now
  required – the same rule
  [`locate_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/locate_country.md)
  has always enforced for `lon`/`lat`.
- Three documented contracts did not match their code:
  [`?locate_country`](https://pursuitofdatascience.github.io/countryatlas/reference/locate_country.md)
  said `lon`/`lat` were “recycled together” when the function has always
  required equal lengths, and
  [`?gini`](https://pursuitofdatascience.github.io/countryatlas/reference/gini.md)
  /
  [`?theil`](https://pursuitofdatascience.github.io/countryatlas/reference/theil.md)
  promised that `weights` was “recycled against `x` the usual R way”,
  which is precisely the behaviour removed above. All three now describe
  what the functions do.
  [`locate_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/locate_country.md)’s
  length error also read “or an `points` sf object”.
- Offline safety is now covered by tests rather than assumed. Checks run
  `\donttest{}` examples and rebuild vignettes, and CRAN policy does not
  allow either to fail for want of a network connection.
  [`world_data()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_data.md)
  and
  [`country_data()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_data.md)
  degrade a failed fetch to a warning and a metadata-only frame, and
  [`wdi_search()`](https://pursuitofdatascience.github.io/countryatlas/reference/wdi_search.md)
  reads `WDI`’s bundled indicator list rather than the API; all three
  are now asserted, so a change that made any of them require a
  connection would break the suite.
- An unwritable cache directory silently cost you your data.
  [`memoise::cache_filesystem()`](https://memoise.r-lib.org/reference/cache_filesystem.html)
  does not validate the directory it is given: it constructs
  successfully and only fails when something is *written*, which happens
  deep inside the fetch. So with a read-only or otherwise unusable cache
  location, `country_data(cache = TRUE)` reported
  `Could not fetch indicator "..." from the World Bank API` and returned
  the country spine with every indicator `NA` – blaming the API for a
  local permission problem, while the same call with `cache = FALSE`
  returned the data perfectly. (The
  [`tryCatch()`](https://rdrr.io/r/base/conditions.html) that was meant
  to fall back never fired, because constructing the cache never
  errored.) The directory is now checked before use, with a fallback to
  session-only caching and a one-time message naming the real cause.
- Projected maps failed outright under `options(OutDec = ",")` – the
  ordinary setting in comma-decimal locales. The PROJ strings are built
  by pasting numbers, so `recenter = 48.9` became `+lon_0=48,9`, which
  PROJ rejects; the invalid CRS then surfaced as sf’s opaque “crs not
  found: is it missing?”. Every number destined for a machine-readable
  string is now formatted with an explicit decimal mark.
- Two more of the same kind, triggered by `options(scipen = -10)`, which
  formats a *double* in scientific notation: `sf::st_crs(4326)` became
  `EPSG:4.326e+03` and yielded an `NA` CRS (surfacing later as
  `st_crs(x) == st_crs(y) is not TRUE` from
  [`locate_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/locate_country.md)),
  and Natural Earth’s scale `110` became `1.1e+02`, so
  `world_geometry(geometry = "sf")` failed with
  `'countries1.1e+02' is not an exported object`. Every EPSG code and
  Natural Earth scale is now an integer literal, which `scipen` does not
  affect.
- [`simplify_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/simplify_geometry.md)
  and `world_geometry("graticule")` are insulated from two upstream bugs
  of the same family, both reproducible without this package:
  `rmapshaper` serialises `keep` for V8, which rejects the `0,1` that
  `options(OutDec = ",")` produces, and
  [`sf::st_graticule()`](https://r-spatial.github.io/sf/reference/st_graticule.html)
  overflows the node stack under `options(scipen = -10)`. Both calls now
  run with those two options normalised, and the caller’s settings are
  restored immediately afterwards.
- [`rank_countries()`](https://pursuitofdatascience.github.io/countryatlas/reference/rank_countries.md)
  silently ranked within groups when handed a grouped frame. Its
  [`mutate()`](https://dplyr.tidyverse.org/reference/mutate.html)
  honoured the caller’s
  [`group_by()`](https://dplyr.tidyverse.org/reference/group_by.html),
  so the same data ranked `4, 1, 3, 2` ungrouped and `2, 1, 2, 1` after
  an incidental `group_by(region)` upstream in the pipe – with
  `within = NULL` in both cases, which documents a global ranking.
  `rank`, `percentile` and `z_score` were all affected. `within` is now
  the only thing that sets the ranking scope, matching every other
  function here, which imposes its own grouping rather than inheriting
  the caller’s. A test asserts that a grouped input changes no answer,
  and that nothing leaks grouping into its return value.
- A non-numeric value column now errors by name instead of producing
  nonsense. A factor column is easy to acquire –
  [`read.csv()`](https://rdrr.io/r/utils/read.table.html) on a column
  with one stray non-numeric entry gives you one – and arithmetic on it
  failed four different ways:
  [`growth_rate()`](https://pursuitofdatascience.github.io/countryatlas/reference/growth_rate.md)
  and
  [`per_capita()`](https://pursuitofdatascience.github.io/countryatlas/reference/per_capita.md)
  returned a column of `NA`s behind base R’s “‘/’ not meaningful for
  factors”;
  [`share_of_world()`](https://pursuitofdatascience.github.io/countryatlas/reference/share_of_world.md),
  [`rank_countries()`](https://pursuitofdatascience.github.io/countryatlas/reference/rank_countries.md)
  and
  [`aggregate_regions()`](https://pursuitofdatascience.github.io/countryatlas/reference/aggregate_regions.md)
  raised an opaque error from inside
  [`dplyr::mutate()`](https://dplyr.tidyverse.org/reference/mutate.html);
  [`gini()`](https://pursuitofdatascience.github.io/countryatlas/reference/gini.md)
  managed “missing value where TRUE/FALSE needed”; and
  [`morans_i()`](https://pursuitofdatascience.github.io/countryatlas/reference/morans_i.md)
  quietly returned a plausible-looking statistic. These, plus
  [`index_to()`](https://pursuitofdatascience.github.io/countryatlas/reference/index_to.md),
  [`diff_by_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/lag_by_country.md),
  [`beta_convergence()`](https://pursuitofdatascience.github.io/countryatlas/reference/beta_convergence.md),
  [`sigma_convergence()`](https://pursuitofdatascience.github.io/countryatlas/reference/sigma_convergence.md)
  and
  [`theil()`](https://pursuitofdatascience.github.io/countryatlas/reference/theil.md),
  now name the column and its actual type.
  [`lag_by_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/lag_by_country.md)
  is deliberately unchanged: it does no arithmetic, so lagging a factor
  or character column remains legitimate.
- [`aggregate_regions()`](https://pursuitofdatascience.github.io/countryatlas/reference/aggregate_regions.md)
  reported a figure for groups it had no data for. Values are dropped
  before aggregating, so a group whose every value is missing had
  nothing left – and each base function got that wrong differently:
  `"sum"` returned `0`, `"mean"` and `"weighted_mean"` `NaN`, and
  `"min"`/`"max"` `-Inf`/`Inf` plus a warning. “This region’s total is
  0” is a claim, not an absence, which matters in a package built around
  honest missing-data handling. All six now return `NA`, as
  `"min"`/`"max"` were already meant to; groups that do have data are
  unaffected, and a partially-missing group still aggregates the values
  it has.
  [`?aggregate_regions`](https://pursuitofdatascience.github.io/countryatlas/reference/aggregate_regions.md)
  documents this.
- [`complete_years()`](https://pursuitofdatascience.github.io/countryatlas/reference/complete_years.md)
  failed on a zero-row panel, where every other panel helper returns
  zero rows. With no `years` it reached
  `seq(min(numeric(0)), max(numeric(0)))` and died on base R’s “‘from’
  must be a finite number”; with `years` supplied it died on tidyr’s
  “Can’t recycle `year` (size 3) to size 0”. Neither message names
  anything the caller did. It now returns the empty frame, columns
  intact, for all three `method` values – while still reporting a bad
  `years` or `value` argument.
- [`bivariate_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/bivariate_map.md)
  and
  [`cartogram_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/cartogram_map.md)
  (and so
  [`dorling_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/dorling_map.md))
  failed inside their optional dependency when no row carried the values
  they need. This is easier to hit than it sounds:
  [`attach_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/attach_geometry.md)
  joins geometry-on-the-left, so a frame with nothing in it arrives at
  the plotting verb as full-length columns of `NA`. `biscale` then
  indexed `sVar[1:(length(sVar) - 1)]`, which becomes `1:-1`, and
  reported “only 0’s may be mixed with negative subscripts”; `cartogram`
  compared `NA` in `if (meanSizeError < maxSizeError)` and reported
  “missing value where TRUE/FALSE needed”. Neither mentions the data.
  Both now say which columns are empty, as
  [`spike_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/spike_map.md)
  already did, and both reject a non-numeric column by name.
  Partly-missing columns still draw from the rows that do have values.
- [`gini()`](https://pursuitofdatascience.github.io/countryatlas/reference/gini.md)
  could kill the R session. It computed the weighted mean absolute
  difference with [`outer()`](https://rdrr.io/r/base/outer.html), an
  n-by-n matrix – fine for the ~200 countries it is written for, but it
  is exported and accepts any numeric vector. A geometry-joined column
  is 99,338 rows, needing about 79 GB, and the process was killed
  outright: no error, no message, no result. The kernel is now the
  sorted cumulative form, O(n log n) in time and O(n) in memory, which
  agrees with the pairwise definition to floating-point noise (verified
  across ties, zero weights, single values and 340 random cases) and
  handles a million values in well under a second. Every documented
  figure is unchanged.
- [`aggregate_regions()`](https://pursuitofdatascience.github.io/countryatlas/reference/aggregate_regions.md)
  silently multiplied its answer when given a frame with map geometry
  attached. The polygon backend expands each country into hundreds of
  vertex rows, so a row-wise total counts it once per vertex: for the
  bundled snapshot a regional total of 497,265 came out as 280,951,373.
  It is reachable directly off `world_data(geometry = "polygon")`. It
  cannot de-duplicate on `iso3c`, since `by = c("region", "year")`
  roll-ups legitimately repeat a country, so it now warns and says what
  to do instead. Country-level tables and panels are unaffected.
- [`?audit_coverage`](https://pursuitofdatascience.github.io/countryatlas/reference/audit_coverage.md)
  described the raw list it returns without mentioning that the object
  is classed and has a [`print()`](https://rdrr.io/r/base/print.html)
  method, so what you actually see at the console is a formatted report
  rather than the list. Both are now documented.
- `world_geometry("ocean")` drew nothing at all, in every projection.
  Under the S2 engine – sf’s default since 1.0, so everywhere –
  `st_as_sfc(st_bbox(-180, -90, 180, 90))` collapses to a two-point,
  zero-area polygon, and the collapse is invisible because `st_bbox()`
  reports the stored extent instead of recomputing it from the (empty)
  coordinates. The rectangle is now built by constructing the ring
  explicitly, which S2 never gets to reinterpret, and its edges are
  densified so a curved projection has points to bend: the layer comes
  out at Earth’s true surface area (5.1e14 m2) and covers 98-100% of the
  countries layer across all nine world projections.
  `st_break_antimeridian()` is no longer applied here at all – with
  `lon_0 = 0` it cut the outline at +/-180, its own edges, taking it
  down to two thirds of the globe and, under Mollweide, to nothing.
- Where an ocean background cannot be drawn,
  [`world_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_geometry.md)
  now says so instead of returning an invisible layer: the four
  hemispheric projections (`"orthographic"`, `"azimuthal_equal_area"`,
  `"north_polar"`, `"south_polar"`) show half the globe, and a
  whole-globe rectangle cannot be recentred without covering only part
  of the map.
- `world_geometry("coastline")` and `world_geometry("ocean")` returned a
  bare `sfc` rather than the `sf` object
  [`?world_geometry`](https://pursuitofdatascience.github.io/countryatlas/reference/world_geometry.md)
  promises (and that the other four `what` values deliver), so dplyr
  verbs failed on exactly those two. Both are now `sf`; the geometry is
  unchanged.
- [`?world_geometry`](https://pursuitofdatascience.github.io/countryatlas/reference/world_geometry.md)’s
  `@return` was a single line naming no columns. It now lists what each
  `what` returns, and warns that the sf backend’s
  `centroid_lon`/`centroid_lat` are in the object’s own CRS – projected
  metres, not degrees, so `centroid_lon` for France is `174097`, not
  `2.1`. Use `country_meta$centroid_lon` for degrees.
- [`sf::st_coordinates()`](https://r-spatial.github.io/sf/reference/st_coordinates.html)
  failed on `world_geometry("countries", geometry = "sf")`, in every
  projection including the default. Natural Earth supplies 177 uniform
  `MULTIPOLYGON`s, but `st_break_antimeridian()` runs an
  `st_intersection()` internally that collapses a single-part
  `MULTIPOLYGON` to a `POLYGON`, leaving 148 `POLYGON` + 29
  `MULTIPOLYGON` – an `sfc_GEOMETRY` column, which `st_coordinates()`
  does not support. Extracting vertices from the package’s own geometry,
  an ordinary thing to want, therefore errored with “not implemented for
  objects of class sfc_GEOMETRY”. The column is cast back to
  `MULTIPOLYGON`, which is a type change only: row count, codes and land
  area are unchanged.
  [`?world_geometry`](https://pursuitofdatascience.github.io/countryatlas/reference/world_geometry.md)
  also now notes that a hemispheric projection returns empty geometries
  for the far side, where the same `st_coordinates()` limitation applies
  for a different and correct reason.
- [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md)
  accepted a frame with no geometry, returned a `ggplot` object without
  complaint, and then failed only when the plot was printed – with
  ggplot2’s “Problem while computing aesthetics … Caused by error in
  `.data$long`”, which names nothing the caller did. It validated the
  `fill` column but never the `long`/`lat`/`group` columns the polygon
  path needs. Forgetting
  [`attach_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/attach_geometry.md)
  is the easiest mistake to make here, and it is easy precisely because
  the other plotting verbs do not need it:
  [`tile_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/tile_map.md),
  [`bubble_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/bubble_map.md),
  [`spike_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/spike_map.md)
  and
  [`globe_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/globe_map.md)
  all take a country-level frame, so `world_map(snap, gdp)` looks like
  it should work too. It now says so at the call, and names the fix.
  [`facet_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/facet_map.md)
  delegates to
  [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md)
  and is covered by the same check; the four country-level verbs are
  deliberately unchanged, and a test pins that asymmetry.
- `interactive_map(engine = "ggiraph")` reported a missing geometry
  differently from the other engines. It assembles its own `ggplot`
  rather than calling
  [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md),
  so it bypassed that check and failed at render time on `.data$long`,
  while `engine = "plotly"` named the problem properly. Both now give
  the same message.
  [`?interactive_map`](https://pursuitofdatascience.github.io/countryatlas/reference/interactive_map.md)
  also documents that the `"leaflet"` engine attaches geometry itself if
  handed a country-level table, which the others do not.
- The numeric fill styles now require a numeric column.
  `style = "continuous"` and `"binned"` reached ggplot2 and failed only
  when the plot was printed (“Discrete value supplied to a continuous
  scale”, “Binned scales only support continuous data”), neither naming
  the column; `"quantile"` and `"jenks"` did not fail at all – the break
  computation returns early on a non-numeric column, so the fill fell
  through to the discrete scale and drew a plausible map whose legend
  claimed quantile bins it had never computed. The reverse direction,
  `style = "categorical"` on a numeric column, was already guarded, so
  this closes the pair.
  [`animate_world()`](https://pursuitofdatascience.github.io/countryatlas/reference/animate_world.md)
  and
  [`facet_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/facet_map.md)
  inherit it.
- [`attach_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/attach_geometry.md)
  no longer warns when given a panel. Joining one row per country-year
  against polygon vertices is legitimately many-to-many – it is what
  [`animate_world()`](https://pursuitofdatascience.github.io/countryatlas/reference/animate_world.md)
  and
  [`facet_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/facet_map.md)
  are for – so dplyr’s “unexpected many-to-many relationship” warning
  was noise. The relationship is now declared, as the cache merge
  already did.
- [`?repair_country_names`](https://pursuitofdatascience.github.io/countryatlas/reference/repair_country_names.md)
  now says which way the `stringdist` fallback errs. The `threshold`
  argument already noted that the metric changes when `stringdist` is
  absent (Jaro-Winkler versus a length-normalised edit distance); it now
  adds that the fallback is the more conservative of the two, repairing
  a subset of what Jaro-Winkler would – mainly missing transposed
  letters, as in “Frnace” – and never choosing a different country.
  Measured over 120 single-typo names: 98 repaired with `stringdist`, 77
  without, none repaired that `stringdist` did not, and no wrong repairs
  either way. A test now holds the package to that.
- [`simplify_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/simplify_geometry.md)
  undid the geometry-type fix above. Both simplifiers collapse a
  single-part `MULTIPOLYGON` to a `POLYGON`, so a homogeneous input came
  back as a mixed `sfc_GEOMETRY` column and
  [`sf::st_coordinates()`](https://r-spatial.github.io/sf/reference/st_coordinates.html)
  failed on the result – the same defect as
  `world_geometry("countries")`, restored one step downstream. The
  output is cast back; row count and geometry are unchanged.
- [`simplify_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/simplify_geometry.md)’s
  `keep` argument now means roughly the same thing with and without
  `rmapshaper`. The
  [`sf::st_simplify()`](https://r-spatial.github.io/sf/reference/geos_unary.html)
  fallback was given a fixed `dTolerance` of `(1 - keep) * 10000`,
  i.e. metres whatever the coordinate system: 9 km on a projected frame,
  which barely simplified anything (79% of vertices kept at
  `keep = 0.1`), and 9000 *degrees* on a lon/lat frame, which is
  meaningless and only survivable because `preserveTopology` keeps a
  husk. The tolerance is now scaled to the object’s own extent, so the
  fallback behaves the same on either coordinate system and responds
  monotonically to `keep`.
  [`?simplify_geometry`](https://pursuitofdatascience.github.io/countryatlas/reference/simplify_geometry.md)
  says that only `rmapshaper` honours `keep` as a true proportion.
- [`gini()`](https://pursuitofdatascience.github.io/countryatlas/reference/gini.md)’s
  negative-value warning said `Returning "NA"`, which reads as the
  two-character string rather than the missing value. It now renders as
  `NA`, matching the same correction already made elsewhere.
- The test suite no longer fails on R \>= 4.6. Several tests set
  `options(scipen = -10)` to exercise the scientific-notation bugs fixed
  above, but R 4.6 clamps `scipen` to a minimum of -9 and warns
  (“invalid ‘scipen’ -10, used -9”), so an exact round-trip assertion
  failed and three warnings were raised – an `ERROR` under `R CMD check`
  on current R, even though the package code itself was correct. The
  tests now use -9 and compare against the value R actually stored.
- The
  [`wdj_overrides()`](https://pursuitofdatascience.github.io/countryatlas/reference/wdj_overrides.md)
  soft-deprecation notice told the wrong people. It lived in the shared
  function body, so in an interactive session it fired for
  [`country_overrides()`](https://pursuitofdatascience.github.io/countryatlas/reference/wdj_overrides.md)
  – the very replacement it recommends – and for every public function
  that takes the override table as a default argument
  ([`standardize_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/standardize_country.md),
  [`convert_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/convert_country.md),
  [`attach_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/attach_geometry.md),
  [`check_country_match()`](https://pursuitofdatascience.github.io/countryatlas/reference/check_country_match.md),
  [`repair_country_names()`](https://pursuitofdatascience.github.io/countryatlas/reference/repair_country_names.md),
  [`world_data()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_data.md)
  and the geometry backends). Callers were advised to stop using a
  function they had never written, and the advice was unactionable. The
  notice now fires only for a direct call to
  [`wdj_overrides()`](https://pursuitofdatascience.github.io/countryatlas/reference/wdj_overrides.md);
  the table itself is unchanged. The documented default is now
  [`country_overrides()`](https://pursuitofdatascience.github.io/countryatlas/reference/wdj_overrides.md),
  so
  [`?attach_geometry`](https://pursuitofdatascience.github.io/countryatlas/reference/attach_geometry.md)
  and friends name a function the reader can actually look up.
- [`?country_borders`](https://pursuitofdatascience.github.io/countryatlas/reference/country_borders.md)’s
  whole-world example runs again. It was wrapped in `\dontrun{}` on the
  grounds that the whole-world adjacency is expensive, but it takes
  about a quarter of a second from a cold session – only 2.7 times the
  `region = "Europe"` subset that already ran live. CRAN discourages
  `\dontrun{}` for code that can be executed, so it is now a guarded
  `\donttest{}` and is actually exercised by the check. That leaves six
  `\dontrun{}` topics, each genuinely unrunnable: a live World Bank
  fetch, an HTML widget, a DuckDB connection, a 60-frame GIF, and a call
  that deletes files.
- [`?country_overrides`](https://pursuitofdatascience.github.io/countryatlas/reference/wdj_overrides.md)’s
  advice for accented names in a non-UTF-8 locale did not work in that
  locale. It offered de-accenting with
  `iconv(x, to = "ASCII//TRANSLIT")` as an alternative to running under
  UTF-8, but `//TRANSLIT` is itself locale-dependent: under `LC_CTYPE=C`
  it returns `NA`, or replaces each accent with `?` when given an
  explicit `from = "UTF-8"`, so nothing resolves either way. The section
  now says de-accenting has to happen while still in a UTF-8 locale, and
  that the ASCII spellings the override table carries are what work
  everywhere.
- A bad `options(countryatlas.workers)` reached `mclapply()`. The option
  is advertised in this file, so a stray value is reachable: `"abc"`,
  `NA` and `Inf` all became `NA` workers and surfaced as “missing value
  where TRUE/FALSE needed” from deep inside a parallel fetch, while
  `c(2, 4)` silently used the larger of the two. It is now checked, and
  the message names the option. Values below one are still clamped to
  one, as before – that path was never the problem.
- A bad `options(countryatlas.cache_dir)` did the same thing one layer
  down. The option is documented in
  [`?clear_wdi_cache`](https://pursuitofdatascience.github.io/countryatlas/reference/clear_wdi_cache.md),
  and a stray value reached
  [`dir.exists()`](https://rdrr.io/r/base/files2.html)/[`dir.create()`](https://rdrr.io/r/base/files2.html):
  `NA`, a number and `TRUE` each gave “invalid filename argument”,
  `character(0)` gave “argument is of length zero”, and a two-element
  vector gave “the condition has length \> 1”. It is now checked and the
  message names the option. An empty string is still accepted and still
  degrades to session-only caching; `NA_character_`, which used to
  degrade silently, now errors like the other bad values.
- An empty cache directory failed on R 4.6 but not on R 4.4.
  `dir.create("")` warns and returns `FALSE` on R 4.4, so the fallback
  to session-only caching worked; on R 4.6 it *errors* with “zero-length
  ‘path’ argument”, which escaped the surrounding
  [`suppressWarnings()`](https://rdrr.io/r/base/warning.html) and
  propagated. An empty path is now recognised as “no disk cache” before
  the filesystem is touched, so the behaviour is the same on every R
  version.
- [`?theil`](https://pursuitofdatascience.github.io/countryatlas/reference/theil.md)
  now says that a row with a missing *group* is dropped along with rows
  whose value is missing, so the decomposition’s `total` is computed
  over the grouped subset and can differ from the ungrouped `theil(x)`.
  On the bundled snapshot that difference is entirely Puerto Rico, which
  has no `region`.
  [`theil()`](https://pursuitofdatascience.github.io/countryatlas/reference/theil.md)
  also gains numeric anchors on the bundled data, which
  [`gini()`](https://pursuitofdatascience.github.io/countryatlas/reference/gini.md)
  already had.
- Every `sf`-backed verb leaked `sf`’s internal chatter as
  [`message()`](https://rdrr.io/r/base/message.html) conditions. The
  console was already clean, but silencing it by redirecting the message
  *stream* leaves the conditions themselves travelling to whatever
  handler the caller installed, so
  [`purrr::quietly()`](https://purrr.tidyverse.org/reference/quietly.html),
  [`testthat::expect_silent()`](https://testthat.r-lib.org/reference/expect_silent.html)
  or a plain
  [`withCallingHandlers()`](https://rdrr.io/r/base/conditions.html)
  around
  [`attach_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/attach_geometry.md),
  [`neighbors()`](https://pursuitofdatascience.github.io/countryatlas/reference/neighbors.md),
  [`country_borders()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_borders.md),
  [`locate_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/locate_country.md)
  or
  [`morans_i()`](https://pursuitofdatascience.github.io/countryatlas/reference/morans_i.md)
  still saw three to nine “Spherical geometry (s2) switched off” /
  “assumes that they are planar” notices. They are now muffled as well
  as redirected. (The comment claiming these notices bypass R’s
  condition system was simply wrong – they are ordinary
  [`message()`](https://rdrr.io/r/base/message.html)s, and only a few
  GDAL diagnostics need the stream redirect.)
- [`?world_geometry`](https://pursuitofdatascience.github.io/countryatlas/reference/world_geometry.md)
  called all four azimuthal projections “hemispheric” and said the far
  side comes back as empty geometries. That is true of `"orthographic"`
  alone; `"azimuthal_equal_area"`, `"north_polar"` and `"south_polar"`
  are Lambert equal-area and image the *whole* globe, with the far side
  stretched around the rim and nothing dropped. The page now
  distinguishes them and points at `region` for a genuine polar view,
  and the error `"ocean"` raises in those projections no longer gives
  “it shows one hemisphere” as the reason.
- [`?world_geometry`](https://pursuitofdatascience.github.io/countryatlas/reference/world_geometry.md)
  now documents the Natural Earth features that have no ISO code and so
  come back with `iso3c` `NA` – Somaliland at every scale, plus the
  Indian Ocean Territories and Ashmore and Cartier Islands from
  `"medium"` on.
- [`?theme_world_map`](https://pursuitofdatascience.github.io/countryatlas/reference/theme_world_map.md)
  said the theme is used by *all* the package’s plotting functions.
  [`bivariate_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/bivariate_map.md)
  is the exception – it applies
  [`biscale::bi_theme()`](https://chris-prener.github.io/biscale/reference/bi_theme.html)
  so the map matches biscale’s own legend, and its axis titles, panel
  grid and background differ as a result. The page now names the
  exception.
- [`?simplify_geometry`](https://pursuitofdatascience.github.io/countryatlas/reference/simplify_geometry.md)
  documented `keep` as a proportion “(0-1)”, but `keep = 0` is rejected
  on both simplifier paths (it would leave nothing to draw). The range
  now reads “greater than 0 and at most 1”.
- `complete_years(value = )` fabricated data in the columns it was *not*
  given. A numeric column left out of `value` was classified as a static
  attribute and carry-filled, so naming **fewer** columns invented
  **more** figures – and even `method = "none"`, which exists to
  complete the grid and fill nothing, produced a carried-forward value
  for the missing year. Measure columns are now excluded from the
  attribute carry whether or not they are named; an unnamed one stays
  `NA` in the rows `complete()` adds. `value = NULL` behaves exactly as
  before.
- [`aggregate_regions()`](https://pursuitofdatascience.github.io/countryatlas/reference/aggregate_regions.md)
  silently ignored `weight` for every `fun` except `"weighted_mean"`,
  returning the unweighted figure – on European GDP per capita, 38,323
  where the population-weighted answer is 29,896. Passing `weight` with
  any other `fun` now errors, mirroring the existing abort when
  `fun = "weighted_mean"` is given no weight.
- [`flow_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/flow_map.md)
  dropped a flow whose endpoint it could not resolve without a word, and
  when nothing resolved it returned a bare world map with no arc layer
  at all. It now warns, naming the values it could not place and
  pointing at `origin` – feeding it `iso3c` codes while `origin` still
  defaults to `"country.name"` is the usual cause, and it drew a blank
  map.
- [`?in_group`](https://pursuitofdatascience.github.io/countryatlas/reference/in_group.md)
  now says that a value `origin` cannot resolve answers `FALSE`,
  indistinguishable from a country that is genuinely outside the group,
  and points at
  [`check_country_match()`](https://pursuitofdatascience.github.io/countryatlas/reference/check_country_match.md)
  for telling the two apart.
- [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md)
  /
  [`globe_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/globe_map.md)
  passed `palette`, `title`, `legend` and `na_label` to `viridisLite`
  and `ggplot2` unchecked, so a mistake came back in their vocabulary
  rather than the package’s: `palette = c("magma", "viridis")` reached a
  bare [`switch()`](https://rdrr.io/r/base/switch.html) and reported
  “EXPR must be a length 1 vector”, and a numeric `palette` was accepted
  without a word. A length-2 `title` or `legend` was accepted too, and
  `ggplot2` then drew both strings on top of each other. All four are
  now checked;
  [`world_query()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_query.md)
  already validated the two of them it takes (`palette` and `title`).
  `na_label` keeps its documented tolerance – there is one `NA` key, so
  the first element wins and a length-1 `NA` still means “leave the
  default formatter alone” – but it now says so instead of doing it
  silently. A number is still a perfectly good *label*.
- [`country_data()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_data.md)
  /
  [`world_data()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_data.md)
  resolved a conflict between `latest` and the shape arguments silently,
  and with opposite precedence depending on the year: a multi-year
  `year` overrode `latest = TRUE`, while a single year had
  `latest = TRUE` override `panel = TRUE`. The winner is unchanged –
  both were already the documented behaviour – but the call now warns,
  naming the argument being dropped, instead of returning a shape nobody
  asked for.
- `locate_country(tolerance_km = )` was unvalidated, and a character
  value did not merely give an opaque message – it produced a **wrong
  answer**. R compares `dkm <= tolerance_km` as strings when the
  tolerance is character, and `"2650" <= "a"` is `TRUE`, so every
  unmatched point snapped to its nearest country however far away it
  was: a mid-Pacific point came back as Fiji, where the documented
  behaviour is that open ocean stays `NA`. Now checked, before the `sf`
  gate.
- Three more scalars the validation sweep had missed now name themselves
  instead of failing in a dependency’s vocabulary:
  `correlate_indicators(min_n = )` (an `NA` gave “missing value where
  TRUE/FALSE needed”, a length-2 value “the condition has length \> 1”),
  and `dorling_map(k = )` / `dorling_map(itermax = )` (which reported
  `cartogram`’s “all sizes are missing and/or non-positive” and an
  assertion naming its internal `maxiter`).
- `interactive_map(engine = "ggsql")` reported a missing `ggsql` \>=
  0.4.1 for a frame that simply had no geometry – sending the caller
  after a package that has not shipped in the R bindings at all, only to
  meet the real error afterwards. The `sf` check now runs ahead of the
  package gates.
  [`spin_globe()`](https://pursuitofdatascience.github.io/countryatlas/reference/spin_globe.md)
  had the same inversion for its `fill` column: its scalars were moved
  ahead of the animation gate in an earlier pass, but the column check
  was not, so a mistyped column still asked for `gifski`.
- [`join_world()`](https://pursuitofdatascience.github.io/countryatlas/reference/join_world.md)
  could not read a column of ISO codes without being told to. Its
  fallback detector tried each character column with
  `origin = "country.name"`, which does not match most alpha-3 codes, so
  a column of them was rejected outright – and a column *named* `iso3c`
  was found by name but still read as country names, so
  `join_world(tibble(iso3c = c("FRA", "JPN")))` warned that nothing
  matched and returned all `NA`. Detection now tries the code schemes as
  well and carries the one that worked through to the conversion, so
  `iso3c`, `iso_a3`, `iso2c` and an unrecognised name like `code` all
  resolve. An explicit `origin` still wins, and a column whose name
  implies a scheme is only read that way if the scheme actually resolves
  it.
- A bounding-box `region` on the **polygon** backend only filters
  vertices; it cannot clip a polygon, so a country crossing the edge
  keeps a truncated ring that
  [`geom_polygon()`](https://ggplot2.tidyverse.org/reference/geom_polygon.html)
  closes with a straight chord (France loses 202 of 605 vertices and the
  two ends sit 15 degrees apart). Nothing in the returned tibble showed
  it, and the vignette presented the box as clipping the shapes. It now
  warns and points at `geometry = "sf"`, where the clip is a real
  [`sf::st_crop()`](https://r-spatial.github.io/sf/reference/st_crop.html);
  [`?world_geometry`](https://pursuitofdatascience.github.io/countryatlas/reference/world_geometry.md)
  and the vignette say which is which.
- [`attach_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/attach_geometry.md)
  on a frame that already had geometry multiplied the rows instead of
  refusing. The join is by country, and a polygon frame holds one row
  per *vertex*, so re-attaching joins a country’s vertices against
  themselves: the bundled snapshot went from 99,338 rows to
  **310,977,360**. The call declares `relationship = "many-to-many"` –
  correctly, since one country really does have many vertices – which
  switches off dplyr’s own guard against exactly this. It now errors,
  and says to pass the country-level table.
- [`share_of_world()`](https://pursuitofdatascience.github.io/countryatlas/reference/share_of_world.md)
  on a grouped frame with no `year` column returned a share of the
  **group**, not of the world:
  [`sum()`](https://rdrr.io/r/base/sum.html) inside
  [`mutate()`](https://dplyr.tidyverse.org/reference/mutate.html) is per
  group, so a frame grouped by continent came back with a column that
  summed to 5 instead of 1, under a name and a help page that both say
  “world”. A panel was already safe by accident, because the function
  regroups by `year` and that replaces the caller’s groups. It now
  ignores the grouping in both cases, and says so where it would have
  mattered.
- The verbs that add a column now say when they replace one the caller
  already had.
  [`rank_countries()`](https://pursuitofdatascience.github.io/countryatlas/reference/rank_countries.md)
  overwrote `rank`, `percentile` and `z_score`, and
  [`per_capita()`](https://pursuitofdatascience.github.io/countryatlas/reference/per_capita.md),
  [`share_of_world()`](https://pursuitofdatascience.github.io/countryatlas/reference/share_of_world.md),
  [`growth_rate()`](https://pursuitofdatascience.github.io/countryatlas/reference/growth_rate.md),
  [`index_to()`](https://pursuitofdatascience.github.io/countryatlas/reference/index_to.md),
  [`lag_by_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/lag_by_country.md)
  and
  [`diff_by_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/lag_by_country.md)
  overwrote their target column, all in silence – a user’s own `rank`
  column simply vanished. It is a warning, not an error, because
  re-running a verb on its own output is legitimate.
  [`standardize_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/standardize_country.md)
  is deliberately exempt: `add` names the columns literally, so
  replacing an existing `continent` is what was asked for.
- [`geom_country_labels()`](https://pursuitofdatascience.github.io/countryatlas/reference/geom_country_labels.md)
  on an `sf` map failed with `rlang`’s internal “Column `long` not found
  in `.data`”. The layer reads the polygon backend’s `long`/`lat`
  columns, and its own
  [`aes()`](https://ggplot2.tidyverse.org/reference/aes.html) was
  evaluated against the sf frame before the guard inside could run. It
  now errors with its own message and points at
  `ggplot2::geom_sf_text(aes(label = iso3c))`, which is documented on
  the help page too.
- [`geom_country_labels()`](https://pursuitofdatascience.github.io/countryatlas/reference/geom_country_labels.md)
  put every country that crosses the antimeridian on the far side of the
  planet when the frame had no `group` column. `group` is what
  identifies a country’s separate pieces, and the label belongs on the
  largest; without it the fallback averaged the raw longitude range, so
  measured against the largest-piece centroid Fiji was 177.8 degrees
  out, New Zealand 169.6, and even the USA 96.6 – its Aleutian tail
  dragging the mid-range to the Gulf of Guinea. Averaging in wrapped
  coordinates cuts those to 0.2, 6.9 and 31.4. It remains an
  approximation, and the help page now says that placement is exact only
  while `group` is present.

### Housekeeping

- [`gini()`](https://pursuitofdatascience.github.io/countryatlas/reference/gini.md)
  and
  [`theil()`](https://pursuitofdatascience.github.io/countryatlas/reference/theil.md)
  returned a silent `NaN` when the input contained an infinity. `Inf` is
  not `NA`, so it passed `na.rm` and (for Theil) the non-positive
  filter, then made the mean infinite and every share `Inf/Inf`. Every
  other verb propagates an infinity visibly – `Inf` in, `Inf` out, which
  the caller can see – but an inequality index has no such value to
  report, so both now warn and return `NA`, as they already did for a
  zero total weight. Infinite `weights` are caught too. `NaN` is still
  treated as `NA` and dropped.

- [`?theil`](https://pursuitofdatascience.github.io/countryatlas/reference/theil.md)
  promised a tibble whenever `groups` is supplied, but every degenerate
  path – nothing left after `na.rm`, a zero total weight, an infinity –
  returns a single `NA` instead. The help page now says so.

- `dorling_map(k = 0)` passed validation and then failed inside
  `cartogram` with “all sizes are missing and/or non-positive”.
  `check_number()`’s bounds are inclusive, so `lo = 0` admitted a value
  the next layer cannot use – the same hole the integer ceilings were
  added to close, at the other end of the range. It is now rejected with
  a message naming `k`; anything above zero still works.

- [`?countryatlas`](https://pursuitofdatascience.github.io/countryatlas/reference/countryatlas-package.md)
  gains an **Options** section. Two of the three options the package
  reads – `countryatlas.workers` and `countryatlas.gdp_compat` – were
  described only in this changelog, which is not reference
  documentation, so a reader of the help pages had no way to find them.
  (`wdj_workers()`’s own comment noted that the option was “advertised
  in NEWS”, which is how a bad value became reachable.) All three are
  now documented where they are looked for, and a test fails if a future
  option is read without being listed.

- The test suite runs in a quarter of the time (`R CMD check`’s test
  phase went from 389s to 92s). One block asked
  [`neighbors()`](https://pursuitofdatascience.github.io/countryatlas/reference/neighbors.md)
  for each country in turn and then again for each of that country’s
  neighbours, to confirm the reverse edge – and
  [`neighbors()`](https://pursuitofdatascience.github.io/countryatlas/reference/neighbors.md)
  recomputes the whole world’s
  [`sf::st_touches()`](https://r-spatial.github.io/sf/reference/geos_binary_pred.html)
  adjacency on every call, so that was ~465 rebuilds and 292 seconds,
  four fifths of the suite.
  [`neighbors()`](https://pursuitofdatascience.github.io/countryatlas/reference/neighbors.md)
  is vectorised, so one call does the same work. The same properties are
  asserted (irreflexive, no repeated pair, every edge symmetric), and a
  failure now names the offending countries rather than only counting
  them.

- [`?neighbors`](https://pursuitofdatascience.github.io/countryatlas/reference/neighbors.md)
  now says to pass a vector rather than loop, since that cost is
  invisible from the outside: every call rebuilds the whole world’s
  adjacency, so asking about one country costs the same as asking about
  all of them, and adding countries to a single call only adds the
  filtering. Measured here, one country takes about as long as 153 of
  them, which makes a loop over them roughly two orders of magnitude
  more work. The note names
  [`country_borders()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_borders.md)
  as where the cost comes from. A test pins the fact the advice rests on
  – one
  [`country_borders()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_borders.md)
  call per
  [`neighbors()`](https://pursuitofdatascience.github.io/countryatlas/reference/neighbors.md)
  call, whatever the length of `x`.

- [`?attach_geometry`](https://pursuitofdatascience.github.io/countryatlas/reference/attach_geometry.md)
  claimed that Gibraltar, Hong Kong, Macao, Tuvalu and the British
  Virgin Islands have geometry in “no backend at any scale”. Only
  Gibraltar does not: the other four are carried by the `sf` backend at
  `scale = "medium"`, which is the very fix the preceding sentence
  recommends for microstates. It was the *no-tile* list from
  [`?world_tiles`](https://pursuitofdatascience.github.io/countryatlas/reference/world_tiles.md)
  – coincidentally the same five names – pasted into a paragraph about
  geometry. Corrected, and the section’s coverage counts (215 snapshot
  countries; 210, 169 and 214 carried) are now pinned by a test, so an
  upstream Natural Earth change surfaces as a failure rather than as
  silently wrong advice.

- `as_ggsql_source(format = "parquet")` wrote into the **working
  directory** when no `path` was given: the default was the bare
  relative path `"<name>.parquet"`. CRAN policy is that a package writes
  nowhere but the session’s temporary directory unless the caller says
  otherwise. The default is now a file of that name under
  [`tempdir()`](https://rdrr.io/r/base/tempfile.html), and since the
  function returns the path the workflow is unchanged; an explicit
  `path` still writes exactly where you point it.
  [`spin_globe()`](https://pursuitofdatascience.github.io/countryatlas/reference/spin_globe.md)
  already defaulted to
  [`tempfile()`](https://rdrr.io/r/base/tempfile.html), and no other
  export writes at all.

- [`?country_meta`](https://pursuitofdatascience.github.io/countryatlas/reference/country_meta.md)
  and
  [`?world_snapshot`](https://pursuitofdatascience.github.io/countryatlas/reference/world_snapshot.md)
  now say that their `country` columns disagree, and why. `country_meta`
  carries `countrycode`’s English names and `world_snapshot` the World
  Bank’s, so 38 of the 215 shared countries are labelled differently
  (“South Korea” against “Korea, Rep.”). Each table is faithful to its
  own source and neither is wrong, but joining the two on `iso3c` leaves
  you holding two `country` columns with nothing to explain the
  difference – the very reconciliation
  [`country_join()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_join.md)
  advertises, using the same example. The count is pinned by a test,
  along with the referential consistency of all five code columns
  against `country_meta`.

- [`?world_data`](https://pursuitofdatascience.github.io/countryatlas/reference/world_data.md)
  and
  [`?country_data`](https://pursuitofdatascience.github.io/countryatlas/reference/country_data.md)
  now say where the `country` label comes from, because the same call
  produces two different spellings: a successful fetch carries the World
  Bank’s names (“Korea, Rep.”), while the country spine used when the
  fetch returns nothing carries the `countrycode` names (“South Korea”)
  – as does every other function in the package. Nothing can reconcile
  that offline, since the World Bank spelling only exists in the
  response, so both pages now point at `iso3c` as the stable key and at
  `convert_country(iso3c, to = "country")` for one consistent set of
  labels.

- [`utils::globalVariables()`](https://rdrr.io/r/utils/globalVariables.html)
  declared 29 names where 7 are needed. Emptying it and reading what
  `R CMD check` actually reports showed the rest were covered by the
  `.data$x` idiom the code uses throughout, which needs no declaration
  at all; three of them (`subregion`, `NY.GDP.PCAP.KD`,
  `gdp_per_capita_2015`) never appeared as bare symbols anywhere, only
  in a comment or as string literals. A stale entry is worse than
  clutter: it silences the “no visible binding” NOTE for a *new* bare
  use of the same name, which is the warning that would otherwise catch
  a typo. A test now fails if a declared name is not a real bare symbol
  in `R/`.

- Six exported functions failed when the package was loaded but not
  attached –
  [`countryatlas::dissolve_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/dissolve_country.md),
  [`distance_between()`](https://pursuitofdatascience.github.io/countryatlas/reference/distance_between.md),
  [`country_groups()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_groups.md),
  [`in_group()`](https://pursuitofdatascience.github.io/countryatlas/reference/in_group.md),
  [`tile_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/tile_map.md)
  and `world_geometry(region = <group name>)` all died with “object
  ‘historical_codes’ not found” or similar. They referred to the bundled
  datasets by bare name, and a bare name resolves only while the package
  is on the search path: under `countryatlas::fn()` in a script with no
  [`library()`](https://rdrr.io/r/base/library.html) call, the lazy-data
  objects are not reachable. They are now `countryatlas::`-qualified.
  Every test in the suite attaches the package, so nothing caught this;
  a static check now fails if a bare reference reappears.

- [`per_capita()`](https://pursuitofdatascience.github.io/countryatlas/reference/per_capita.md)
  failed when the caller’s frame already had a column named `.wdj_pop`,
  the internal name used for the fetched population. The join suffixed
  both sides to `.wdj_pop.x` / `.wdj_pop.y`, so the column the division
  reads came back `NULL` and base R reported “replacement has 0 rows,
  data has 2”. Any pre-existing column of that name is now dropped
  before the join. Only the branch that fetches population was affected
  – passing `pop` explicitly never touched it.

- Two verbs leaked someone else’s message on an empty frame.
  [`facet_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/facet_map.md)
  gave `ggplot2`’s “Faceting variables must have at least one value”,
  which names neither the argument nor the package; it now says the
  frame has no rows to facet, and notes that the other map verbs draw an
  empty panel instead.
  [`geom_country_labels()`](https://pursuitofdatascience.github.io/countryatlas/reference/geom_country_labels.md)
  ran the centroid summary over nothing, where
  [`range()`](https://rdrr.io/r/base/range.html) warns twice and `dplyr`
  adds a deprecation note on top – it now returns early, silent as it is
  on a full frame. Every other plotting verb already handled a zero-row
  frame cleanly, either drawing an empty panel or naming the reason it
  cannot.

- [`?attach_geometry`](https://pursuitofdatascience.github.io/countryatlas/reference/attach_geometry.md)
  now says that geometry is attached once **per row**, not once per
  country. A panel wants exactly that – one row per country-year, each
  carrying the shape – but a frame that repeats a country by accident
  draws it more than once, and only the last one painted is visible.
  dplyr’s own many-to-many warning is suppressed by the relationship the
  join declares, so nothing signals it.

- [`?country_data`](https://pursuitofdatascience.github.io/countryatlas/reference/country_data.md)’s
  example quoted a **retired** World Bank indicator. The bank replaced
  the `EN.ATM.CO2E.*` carbon series with the AR5 greenhouse-gas series,
  and the bundled `common_indicators` table had already been updated,
  but the example still asked for `EN.ATM.CO2E.KT` – so anyone copying
  it got a warning and an all-`NA` column. It now uses
  `EN.GHG.CO2.MT.CE.AR5`, which returns data. `R CMD check` reports
  examples “OK” without failing on the warning, so nothing surfaced
  this; a test now checks every indicator code quoted in `R/`, `man/` or
  the vignettes against the bundled table.

- `country_groups_tbl` was out of date by two years in four places,
  while carrying an `as_of` stamp of 2026-06-01 that claimed otherwise.
  **Sweden was missing from NATO** (acceded 7 March 2024; Finland had
  been added, so the table had been maintained to 2023 and no further),
  **Angola was still in OPEC** (left 1 January 2024), **BRICS still held
  only its original five** (Egypt, Ethiopia, Iran and the UAE joined in
  January 2024, Indonesia in January 2025), and **The Gambia was missing
  from the Commonwealth** (rejoined 2018). Corrected, so the counts are
  now NATO 32, OPEC 12, BRICS 10 and Commonwealth 56. Saudi Arabia is
  deliberately still absent from BRICS: it was invited in the 2024 round
  but has never confirmed accession. `in_group("Sweden", "NATO")`
  returned `FALSE` before this.

- `options(countryatlas.cache_dir = )` was ignored once a cached fetch
  had happened. The memoised fetcher was built on first use and kept for
  the rest of the session, so relocating the cache afterwards silently
  kept writing to the original directory – and
  [`?clear_wdi_cache`](https://pursuitofdatascience.github.io/countryatlas/reference/clear_wdi_cache.md)
  offers that option as the way to relocate the cache without saying it
  has to be set first. It only ever took effect because
  [`clear_wdi_cache()`](https://pursuitofdatascience.github.io/countryatlas/reference/clear_wdi_cache.md)
  happened to reset the state. The fetcher is now rebuilt when the
  directory changes, and the “cannot write to the cache directory”
  notice is once per *directory* rather than once per session, so a
  second unwritable location is not swallowed.

- A corrupt cache entry was reported as a World Bank outage. An
  interrupted write leaves a truncated or empty `.rds`, and
  [`readRDS()`](https://rdrr.io/r/base/readRDS.html)’s “unknown input
  format” surfaced under “Could not fetch indicator … from the World
  Bank API”, sending the caller off to debug a connection that was fine
  – the same misattribution already fixed for an unwritable cache
  *directory*, now fixed on the read side. The warning names the cache
  and gives the recovery command, which matters because the bad entry
  persists: every later call degrades to the country spine until
  `clear_wdi_cache(disk = TRUE)` is run. A genuine network failure still
  blames the network.

- When the cache directory was unwritable, caching stopped working
  altogether instead of falling back to the session. The in-memory memo
  that stands in for the disk cache lives in one process, but multiple
  indicators are fetched with
  [`parallel::mclapply()`](https://rdrr.io/r/parallel/mclapply.html), so
  each worker warmed a memo and then exited with it: every call
  re-fetched every indicator, hitting the World Bank API again and again
  with nothing to show for it. Fetching is now serial when the memo is
  memory-only – the repeated round-trips cost far more than the one-shot
  parallel speedup – and unchanged when the disk cache is available,
  since a disk memo is shared by every worker.

- A failed indicator was dropped from the result without a word,
  whenever more than one indicator was requested. `fetch_one_safe()`
  degrades gracefully and warns – “Could not fetch indicator … from the
  World Bank API”, or the corrupt-cache variant – but it runs inside
  [`parallel::mclapply()`](https://rdrr.io/r/parallel/mclapply.html),
  which brings back a worker’s *value* and discards the conditions it
  signalled. Since having several indicators is exactly what makes the
  fetch fork, and `parallel = TRUE` is the default, the common case was
  the silent one: a column simply missing from the table with no
  explanation. A single indicator, which never forks, warned correctly –
  which is why this went unnoticed. Conditions are now carried back and
  re-signalled in the calling process, on the serial path too so both
  report identically, and one problem is reported once even if two
  entries name the same series.

- Country lookups silently returned `NA` in Turkish, Azeri and Crimean
  Tatar locales. [`toupper()`](https://rdrr.io/r/base/chartr.html) and
  [`tolower()`](https://rdrr.io/r/base/chartr.html) follow `LC_CTYPE`,
  and in those locales `i` and `I` are not a case pair: `toupper("idn")`
  returns a *dotted* capital I, not `"IDN"`, and `tolower("ISO3C")`
  returns a *dotless* i. Five places folded an ASCII identifier that way
  and then compared it against plain ASCII, so every ISO code containing
  an `i` (IDN, IND, IRL, IRN, ISL, ISR, ITA, BIH, CIV, FIN, …) failed to
  resolve. The failures were quiet and the blast radius uneven:
  `world_geometry(region = c("ind", "chn"))` returned Ivory Coast,
  Indonesia, Isle of Man and India – one unfoldable element made the
  whole vector fall through to *name* matching, which then matched on
  substrings; `dissolve_country("SOUTH VIETNAM")` stopped finding its
  alias; and
  [`join_world()`](https://pursuitofdatascience.github.io/countryatlas/reference/join_world.md)
  on a frame with `ISO3C` and `geo` columns picked `geo`, joining on the
  wrong column entirely. Identifier folding is now done with an explicit
  ASCII table (`ascii_upper()` / `ascii_lower()`) and does not consult
  the locale.

  This fixes countryatlas’s own folding, which covers every path keyed
  on an ISO code, a column name or an alias. It cannot fix matching on a
  country *name*: that goes through `countrycode`, whose regexes are
  themselves locale-sensitive
  (`countrycode("Ireland", "country.name", "iso3c")` is `NA` under
  `tr_TR`). So a user with `LC_COLLATE=tr_TR` still sees name-keyed gaps
  – notably the polygon backend, which labels its geometry by joining
  region *names* to codes, so `world_geometry(region = "IND")` comes
  back with 21 rows of Siachen Glacier instead of India. Working around
  that would mean forcing the C locale around every `countrycode` call,
  which risks mangling accented names for everyone else; it is left for
  upstream.

- The two-core cap that CRAN policy requires of a check was applied only
  when `_R_CHECK_LIMIT_CORES_` held the exact string `"TRUE"`.
  `R CMD check --as-cran` does set it to that – but only when it is not
  already set, so the value that actually arrives is whatever the check
  flavour or CI exported, and R’s own parser for these variables reads
  `"true"`, `"True"`, `"T"`, `"1"`, `"yes"`, `"Yes"` and `"YES"` as true
  as well. Under any of those spellings the cap did not apply and a
  multi-indicator fetch forked `detectCores() - 1` workers in the middle
  of a check. The test is now inverted: a value that is set and does not
  explicitly parse as false means “limit”, which also covers `"warn"`.
  An explicit `"false"`, `"F"`, `"0"` or `"no"` is still honoured as a
  deliberate opt-out.

- [`?world_data`](https://pursuitofdatascience.github.io/countryatlas/reference/world_data.md)’s
  example called `world_data(2020)` unconditionally, and the default
  `geometry = "polygon"` backend comes from the suggested `maps`
  package. `R CMD check` runs `\donttest{}` blocks, so on a check
  flavour configured without suggested packages – CRAN runs one – that
  example failed with “The package "maps" is required for the polygon
  geometry backend”, taking the whole examples step down with it.
  Writing R Extensions requires code that uses a suggested package to be
  conditional, examples included; the call is now guarded with
  [`requireNamespace("maps")`](https://github.com/adeckmyn/maps). The
  second call in the block passes `geometry = "none"` and needs nothing
  beyond the hard dependencies, so it is left to run unconditionally.

- The `beyond-the-choropleth` vignette failed to build wherever
  `rnaturalearth` was absent. Its chunk guard was
  `has_sf <- requireNamespace("sf")`, but the sf geometry backend gates
  on three packages – `sf`, `rnaturalearth` and `rnaturalearthdata` – so
  on a machine with sf but without the Natural Earth data the guarded
  chunk evaluated to `TRUE`, ran, and stopped `R CMD build` with “The
  packages "rnaturalearth" and "rnaturalearthdata" are required for the
  sf geometry backend”. The other two vignettes already tested for
  `rnaturalearth`; all three now test for the same trio the code itself
  gates on. Three tests had the same incomplete guard and errored rather
  than skipping in that configuration; they now share a
  `skip_if_no_sf_geometry()` helper.

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

- `.Rbuildignore` now excludes the session-local `.claude/` directory,
  which `git` ignores but `R CMD build` does not, so it was shipping in
  the tarball and tripping `R CMD check`’s “hidden files and
  directories” NOTE.

- Comments in `R/overrides.R` are ASCII-only, so no source file carries
  non-ASCII characters outside a deliberate `\U` escape.

- [`?world_snapshot`](https://pursuitofdatascience.github.io/countryatlas/reference/world_snapshot.md)
  no longer splits a code span across two source lines, which had left
  the checked-in `.Rd` disagreeing with what `roxygen2` regenerates.

- [`beta_convergence()`](https://pursuitofdatascience.github.io/countryatlas/reference/beta_convergence.md)
  failed with a bare `"subscript out of bounds"` when the initial levels
  had no spread across countries. A constant predictor makes
  [`lm()`](https://rdrr.io/r/stats/lm.html) return an `NA` coefficient,
  which [`summary()`](https://rdrr.io/r/base/summary.html) then drops
  entirely, so the lookup for it fell off the end. It now says that the
  initial levels have no spread and why that matters.

- The forking path is now tested. `fetch_wdi(parallel = TRUE)` is the
  default for a multi-indicator request, so `wdj_lapply()`’s `mclapply`
  branch runs on one of the package’s busiest code paths, yet no test
  reached it – every other test used a single indicator or passed
  `parallel = FALSE`. Confirmed: a parallel fetch is identical to the
  serial one, forking preserves order, `...` reaches the workers,
  `wdj_workers()` honours `options(countryatlas.workers)` and CRAN’s
  two-core limit, and an error inside a fork is surfaced rather than
  left as a `try-error` for downstream code to trip over.

- The World Bank fetch and assembly path is now tested offline. It needs
  the network, so it had no coverage at all despite holding the least
  obvious logic in the package: `fetch_wdi()`’s multi-indicator
  reduce-merge (shared keys are coalesced rather than suffixed, and
  values stay aligned per country-year), its degradation when one
  indicator of several fails, `country_data(latest = TRUE)`’s “most
  recent non-NA” collapse (which opens the window at 1960 and skips a
  missing latest year), the panel key, the duplicate-key case where two
  `iso2c` codes map to one `iso3c`, and that `cache = TRUE` really
  short-circuits a repeated fetch. No defects were found; the tests pin
  the behaviour.

- [`spin_globe()`](https://pursuitofdatascience.github.io/countryatlas/reference/spin_globe.md)
  validates `n_frames` / `fps` / `width` / `height` / `lat` before
  gating on `gifski` / `magick`, matching how
  [`globe_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/globe_map.md)
  orders the two: a bad argument is the caller’s bug and the message
  should not depend on which optional packages happen to be installed.

- [`tile_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/tile_map.md)
  phrased the missing-`iso3c` error differently from the three other
  verbs performing the identical check; all four now read the same.

- Half the examples that were marked `\dontrun{}` now actually run: it
  covered 14 of the 55 documented topics and now covers 7. Nine verbs
  gained executable examples –
  [`locate_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/locate_country.md),
  [`country_borders()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_borders.md),
  [`neighbors()`](https://pursuitofdatascience.github.io/countryatlas/reference/neighbors.md),
  [`morans_i()`](https://pursuitofdatascience.github.io/countryatlas/reference/morans_i.md),
  [`simplify_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/simplify_geometry.md),
  [`bivariate_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/bivariate_map.md),
  [`cartogram_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/cartogram_map.md),
  [`dorling_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/dorling_map.md)
  and the polygon-backend
  [`globe_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/globe_map.md)
  – having been unrunnable only because their examples made a live World
  Bank fetch. Driven by the bundled `world_snapshot` instead, and
  guarded with
  [`requireNamespace()`](https://rdrr.io/r/base/ns-load.html), they are
  `\donttest{}` examples that execute in under half a second each. The
  safe form of
  [`clear_wdi_cache()`](https://pursuitofdatascience.github.io/countryatlas/reference/clear_wdi_cache.md)
  is now a live example too. `\dontrun{}` remains only where the code
  genuinely cannot run in a check (a network fetch, an HTML widget, a
  written GIF, `ggsql` \>= 0.4.1, or deleting files).

- The tests guarding this release’s fixes were verified by mutation:
  each fix was reverted in a scratch copy and the suite had to fail. 35
  mutations, all now detected – but four were not at first, and each
  pointed at a real gap:

  - [`is.na()`](https://rdrr.io/r/base/NA.html) is `TRUE` for `NaN` as
    well, so the checks on
    [`theil()`](https://pursuitofdatascience.github.io/countryatlas/reference/theil.md)’s
    zero-weight result and its shares at perfect equality passed whether
    the value was the fixed `NA` or the `NaN` the bug produced. Both now
    assert the exact value.
  - Nothing verified that quantile breaks are computed on one value per
    country rather than per polygon vertex – the fix that forced this
    major version bump. Removing the de-duplication, or flipping the
    flag that controls it on either
    [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md)
    or
    [`globe_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/globe_map.md)’s
    polygon backend, broke no test. There are now checks on the helper,
    on both call sites, and on the property that matters: roughly equal
    numbers of *countries* per colour.
  - `interactive_map(tooltip = )` was unprotected: the existing tests
    assert the returned object’s class, which passes whether the
    argument is honoured or silently dropped – exactly the pre-2.0.0
    bug. Both the `"ggiraph"` and `"leaflet"` engines are now checked on
    the column they are actually handed.

- Degenerate-but-valid input is now covered by tests: perfect equality
  ([`gini()`](https://pursuitofdatascience.github.io/countryatlas/reference/gini.md)
  /
  [`theil()`](https://pursuitofdatascience.github.io/countryatlas/reference/theil.md)
  return `0`, not `NaN`), zero-variance columns (`NaN` z-scores and `NA`
  correlations rather than errors), duplicate `(iso3c, year)` panel
  rows, poles and antipodal great circles, collinear rings, all-`NA` and
  all-zero fill columns, and single-country frames.

- [`?distance_between`](https://pursuitofdatascience.github.io/countryatlas/reference/distance_between.md)
  and
  [`?country_meta`](https://pursuitofdatascience.github.io/countryatlas/reference/country_meta.md)
  now state which countries have no bundled centroid. `country_meta` is
  assembled from
  [`countrycode::codelist`](https://rdrr.io/pkg/countrycode/man/codelist.html),
  which has no Kosovo row, so `distance_between("Kosovo", "Serbia")` is
  `NA` even though `neighbors("Kosovo")` and
  [`country_borders()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_borders.md)
  know about it – and ten small or dependent territories have a row but
  no centroid. The `@return` already said `NA` was possible; it did not
  say which countries, and the asymmetry with the geometry backends was
  surprising.

- The same double-counting affected three more places, all gated on the
  presence of a `group` column – which polygon frames have and `sf`
  frames do not:

  - [`correlate_indicators()`](https://pursuitofdatascience.github.io/countryatlas/reference/correlate_indicators.md)
    reported `n` and `r` over geometry rows rather than countries. That
    column exists precisely so a correlation computed on a few countries
    cannot masquerade as a world fact, so an inflated `n` defeated the
    point.
  - [`audit_coverage()`](https://pursuitofdatascience.github.io/countryatlas/reference/audit_coverage.md)
    reported the wrong country count and a wrong `NA` rate for every
    indicator.
  - `bubble_map(backend = "sf")` drew two bubbles for a divided country,
    where the polygon path already guaranteed one per country. All three
    now reduce whenever an `iso3c` column is present.

- Quantile and jenks breaks on the `sf` backend double-counted divided
  countries. The de-duplication added in this release skipped the `sf`
  path on the assumption that Natural Earth is one row per country, but
  it is not: Cyprus occupies two rows sharing one `iso3c` at 110m, as do
  Cyprus and India at 50m. Breaking on the raw column shifted the cut
  points enough to move real countries into the wrong bin – Saudi Arabia
  and Libya changed colour in the bundled snapshot at `n_bins = 5`. Both
  backends now de-duplicate on the key, so “one value per country” holds
  exactly rather than nearly.

- `convert_country(x, to = "calling_code")` returned alpha-3 country
  codes instead of telephone calling codes – `"FRA"` where `33` was
  meant. The shortcut was mapped to `countrycode`’s `genc3c` column,
  which is an ISO-style three-letter code, not a dialling prefix; it now
  maps to the `telephone` column, so France gives `33`, the USA `1` and
  Japan `81`. A source comment claimed the limitation was “documented as
  best-effort”, but
  [`?convert_country`](https://pursuitofdatascience.github.io/countryatlas/reference/convert_country.md)
  never mentioned `calling_code` at all; the shortcut is now listed
  there.

- The `Description` field – the text CRAN renders on the package page –
  advertised nine map idioms while the package ships eleven:
  [`spike_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/spike_map.md)
  and
  [`facet_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/facet_map.md)
  (small multiples) were missing from the vocabulary list, and the
  analysis-helper examples predated this release’s inequality and
  convergence statistics. Every idiom it names now corresponds to an
  exported verb.

- [`?countryatlas`](https://pursuitofdatascience.github.io/countryatlas/reference/countryatlas-package.md)
  listed
  [`morans_i()`](https://pursuitofdatascience.github.io/countryatlas/reference/morans_i.md)
  under “Core data assembly” while `_pkgdown.yml` listed it under
  “Analysis helpers”, so the two navigational indexes described the same
  function as two different kinds of thing. It is a spatial statistic,
  so it now sits with
  [`gini()`](https://pursuitofdatascience.github.io/countryatlas/reference/gini.md),
  [`theil()`](https://pursuitofdatascience.github.io/countryatlas/reference/theil.md)
  and the convergence measures on both surfaces.

- The `@seealso` cross-references are reciprocal. All three the package
  had pointed one way only: a reader of
  [`?gini`](https://pursuitofdatascience.github.io/countryatlas/reference/gini.md)
  was sent to
  [`theil()`](https://pursuitofdatascience.github.io/countryatlas/reference/theil.md)
  but a reader of
  [`?theil`](https://pursuitofdatascience.github.io/countryatlas/reference/theil.md)
  was sent nowhere, and likewise for
  [`beta_convergence()`](https://pursuitofdatascience.github.io/countryatlas/reference/beta_convergence.md)/[`sigma_convergence()`](https://pursuitofdatascience.github.io/countryatlas/reference/sigma_convergence.md)
  and
  [`dissolve_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/dissolve_country.md)/[`check_country_match()`](https://pursuitofdatascience.github.io/countryatlas/reference/check_country_match.md).
  [`?theil`](https://pursuitofdatascience.github.io/countryatlas/reference/theil.md)
  did not link to
  [`gini()`](https://pursuitofdatascience.github.io/countryatlas/reference/gini.md)
  at all – it named Gini in prose without a cross-reference. The four
  related diagnostics
  ([`check_country_match()`](https://pursuitofdatascience.github.io/countryatlas/reference/check_country_match.md),
  [`repair_country_names()`](https://pursuitofdatascience.github.io/countryatlas/reference/repair_country_names.md),
  [`dissolve_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/dissolve_country.md),
  plus `historical_codes`) now all reference each other.

- Every page taking a `projection` argument now says where the valid
  values are. Only
  [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md)
  enumerated the 13 projections and only
  [`world_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_geometry.md)
  pointed at it; the other eight entries said no more than “Projection.”
  ([`bivariate_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/bivariate_map.md))
  or “Projection options for the `sf` backend”, leaving a reader with
  nothing to go on. Relatedly, the three pages that document
  `projection` and `recenter` together described only the projection, so
  `recenter`’s meaning – a central meridian – was missing from
  [`world_data()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_data.md),
  [`join_world()`](https://pursuitofdatascience.github.io/countryatlas/reference/join_world.md)
  and
  [`attach_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/attach_geometry.md).

- The `rnaturalearthhires` requirement is now documented on every page
  that takes a `scale` argument, not just
  [`?world_geometry`](https://pursuitofdatascience.github.io/countryatlas/reference/world_geometry.md).
  Seven topics –
  [`world_data()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_data.md),
  [`join_world()`](https://pursuitofdatascience.github.io/countryatlas/reference/join_world.md),
  [`attach_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/attach_geometry.md),
  [`locate_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/locate_country.md),
  [`country_borders()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_borders.md),
  [`neighbors()`](https://pursuitofdatascience.github.io/countryatlas/reference/neighbors.md)
  and
  [`morans_i()`](https://pursuitofdatascience.github.io/countryatlas/reference/morans_i.md)
  – described `scale` without mentioning that `"large"` is unobtainable
  from CRAN, so a reader of any of those pages met the gate with no
  warning.

- `scale = "large"` was offered as a plain option but needs the
  `rnaturalearthhires` package, which is not on CRAN and is not in
  `Suggests`. Left ungated, `rnaturalearth` responded by trying to
  install it into the user’s library from a non-CRAN repository and then
  failing obscurely. It is now gated with a message naming the package
  and the repository to get it from, and pointing at `scale = "medium"`
  (50m) as the option that needs nothing extra.
  [`?world_geometry`](https://pursuitofdatascience.github.io/countryatlas/reference/world_geometry.md)
  documents the requirement, and the *sf & projections* vignette no
  longer demonstrates the scale most readers cannot run.

- [`?country_borders`](https://pursuitofdatascience.github.io/countryatlas/reference/country_borders.md)
  recommended a graph recipe that produced nonsense.
  `igraph::graph_from_data_frame()` treats the *first two* columns as
  the edge endpoints, and
  [`country_borders()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_borders.md)
  returns `iso3c_a`, `country_a`, `iso3c_b`, `country_b` – so columns 1
  and 2 are both endpoint *A*, and passing the whole tibble built edges
  from each country’s code to its own name (56 vertices instead of 37
  for Europe, every French edge running `FRA` to `"France"`). The
  documented call now passes only the two code columns.

- [`?neighbors`](https://pursuitofdatascience.github.io/countryatlas/reference/neighbors.md)
  and
  [`?country_borders`](https://pursuitofdatascience.github.io/countryatlas/reference/country_borders.md)
  now warn that `igraph` also exports a
  [`neighbors()`](https://pursuitofdatascience.github.io/countryatlas/reference/neighbors.md)
  – taking a graph and a vertex rather than country names – so whichever
  package is attached later wins.
  [`?country_borders`](https://pursuitofdatascience.github.io/countryatlas/reference/country_borders.md)
  recommends `igraph` for turning the adjacency into a graph, which
  walks users straight into the clash, so both pages now say to qualify
  the call as
  [`countryatlas::neighbors()`](https://pursuitofdatascience.github.io/countryatlas/reference/neighbors.md).
  It is the only collision between this package’s exports and any of
  `dplyr`, `ggplot2`, `tidyr`, `tibble`, `sf`, `maps`, `WDI`,
  `countrycode`, `scales`, `leaflet`, `plotly`, `igraph`, `raster`,
  `terra`, `purrr`, `stringr`, `forcats`, `readr` or the base packages.

- [`?country_overrides`](https://pursuitofdatascience.github.io/countryatlas/reference/wdj_overrides.md)
  now documents why every name in the override table is plain ASCII:
  ASCII spellings match in any locale, whereas accented spellings rely
  on `countrycode`’s own matching and resolve to `NA` under a non-UTF-8
  locale (`LC_CTYPE=C`). The note points at
  `iconv(x, to = "ASCII//TRANSLIT")` for input that may carry accents.

- The test suite is now green under CRAN’s `noSuggests` configuration
  (`_R_CHECK_DEPENDS_ONLY_=true`), which runs with every optional
  package absent. Four tests called `globe_map(backend = "polygon")` or
  [`morans_i()`](https://pursuitofdatascience.github.io/countryatlas/reference/morans_i.md)
  without guarding on `mapproj` / `sf`, so they errored on the
  dependency gate instead of exercising what they were written to check.

- The quantile/jenks binning that
  [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md)
  and both
  [`globe_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/globe_map.md)
  backends perform lived as three near-copies kept in step by hand; it
  is now one internal helper. Verified behaviour-preserving by comparing
  the rendered fill of every style x `n_bins` x backend combination
  before and after (50 fingerprints, ~2.6M values, all identical).

- Documented `\value` claims are now asserted as executable contracts,
  so Rd prose cannot drift from the code in silence. The 36 exports
  whose `\value` makes a specific structural promise – named columns, a
  single row, an attached `"model"` object, a length matching the input
  – are covered; the rest return a `ggplot`, a layer or a widget and are
  checked by their own tests. Every claim audited was already accurate;
  the tests keep it that way.

- The four exports that had no test call site at all –
  [`wdi_search()`](https://pursuitofdatascience.github.io/countryatlas/reference/wdi_search.md),
  [`clear_wdi_cache()`](https://pursuitofdatascience.github.io/countryatlas/reference/clear_wdi_cache.md),
  [`animate_world()`](https://pursuitofdatascience.github.io/countryatlas/reference/animate_world.md)
  and
  [`cartogram_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/cartogram_map.md)
  – are covered, including `cartogram_map(type = "contiguous")` (the
  default type, previously never exercised) and
  [`wdi_search()`](https://pursuitofdatascience.github.io/countryatlas/reference/wdi_search.md)’s
  zero-match and single-match paths.

- The README’s “optional features at a glance” table is corrected
  against what the code actually gates on:
  [`spin_globe()`](https://pursuitofdatascience.github.io/countryatlas/reference/spin_globe.md)
  was listed as needing only `maps` + `mapproj` when it also
  hard-requires `gifski` or `magick`; the `ggsql` row overstated the
  requirements of
  [`as_ggsql_source()`](https://pursuitofdatascience.github.io/countryatlas/reference/as_ggsql_source.md)
  (which never needs `ggsql`) and understated the version
  `interactive_map(engine = "ggsql")` needs; and
  [`locate_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/locate_country.md),
  [`flow_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/flow_map.md)
  and
  [`bubble_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/bubble_map.md)
  were missing.

- The *countryatlas and ggsql* vignette said `DRAW spatial` “was added
  in 0.4.1” as plain fact; it now says that version is newer than what
  CRAN ships, which is why the query-executing chunks are shown but not
  evaluated.

- The package-level overview
  ([`?countryatlas`](https://pursuitofdatascience.github.io/countryatlas/reference/countryatlas-package.md))
  was missing
  [`simplify_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/simplify_geometry.md)
  and
  [`clear_wdi_cache()`](https://pursuitofdatascience.github.io/countryatlas/reference/clear_wdi_cache.md)
  from its section list, though `_pkgdown.yml` had both.

- The set of ISO codes the package treats as countries was computed in
  two places (name matching and the World Bank aggregate filter); it now
  comes from one internal helper, which region resolution uses as well,
  so the three callers cannot drift apart.

- New offline test suites pin the things a structural test cannot:
  closed-form anchors for the hand-rolled numerical kernels (haversine
  distance, spherical polygon area, great-circle interpolation,
  Gini/Theil, sigma and beta convergence, Moran’s I against an
  independently built weights matrix) and internal-consistency checks on
  every bundled dataset (no duplicate or unknown `iso3c`, coordinates in
  range, one country per `world_tiles` cell, `historical_codes` in step
  with its alias table, and `country_meta` centroids still agreeing with
  `polygon_centroids()`).

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

- `geofacet` is dropped from `Suggests`: no code ever used it, and
  [`?tile_map`](https://pursuitofdatascience.github.io/countryatlas/reference/tile_map.md)
  / the README claimed a `geofacet`-backed small-multiples feature that
  did not exist. Facet a
  [`tile_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/tile_map.md)
  like any other `ggplot`, or use
  [`facet_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/facet_map.md)
  for choropleth small multiples.

- The README’s figures are shipped in the tarball again, so the images
  on the CRAN package page resolve. `.Rbuildignore` excluded the
  generated `.png`s but not the (much larger) `.gif`, which left six of
  the seven images broken.

- [`?world_snapshot`](https://pursuitofdatascience.github.io/countryatlas/reference/world_snapshot.md)’s
  `@format` said “two elements” while listing three, and advertised an
  `sf` element that is `NULL` in the released package. It now documents
  what actually ships and points at
  [`attach_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/attach_geometry.md)
  for geometry.

- [`?attach_geometry`](https://pursuitofdatascience.github.io/countryatlas/reference/attach_geometry.md)
  documents which countries each geometry backend actually carries. Rows
  with no matching geometry are dropped silently, and the `sf` backend’s
  `scale` changes *which* countries exist rather than only how detailed
  they are: of the 215 countries in `world_snapshot`, the default
  `scale = "small"` (110m) maps 169 and `scale = "medium"` maps 214.
  Five territories (Gibraltar, Hong Kong, Macao, Tuvalu, the British
  Virgin Islands) are in no backend at any scale.

- [`?world_tiles`](https://pursuitofdatascience.github.io/countryatlas/reference/world_tiles.md)
  and
  [`?tile_map`](https://pursuitofdatascience.github.io/countryatlas/reference/tile_map.md)
  said “one square per country” without saying how many. The grid is the
  239 `country_meta` rows that have a bundled centroid, so the 10
  without one have no tile and
  [`tile_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/tile_map.md)
  silently drops `data` rows keyed on them. Both are now documented, and
  a test pins the grid to that definition.

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
