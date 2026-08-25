# countryatlas — next release planning (target: 2.0.0)

Working document. Scope: (A) integrate **ggsql 0.4.1**, (B) brainstorm new
features/functions, (C) **fix bugs found in 1.0.0** (the important part), and
(D) housekeeping/deprecations.

## Status (branch `v2.0.0-dev`, now merged to `main`)

The `v2.0.0-dev` branch has been **merged into `main`** (fast-forward).
**2.0.0 was accepted and published on CRAN on 2026-08-25.** It then failed one
test on the two r-devel Fedora flavours (latin1 locale, `test-standardize.R`),
so 2.0.1 is the patch release fixing that -- see `NEWS.md` and
`cran-comments.md`. Everything below is the 2.0.0 planning record, kept for the
design notes; it is not a description of unreleased work.

**Implemented in 2.0.0** (see `NEWS.md`): ggsql bridge (`as_ggsql_source()`,
`world_query()`, `interactive_map(engine = "ggsql")`); all eight bug fixes in §3;
projection expansion + `globe_map()` + `spin_globe()` + `facet_map()`;
`locate_country()`, `repair_country_names()`, `country_join_all()`,
`growth_rate()`, `index_to()`, `share_of_world()`, `country_overrides()`; and
four new country groups (Mercosur, GCC, Nordic, Visegrád). Non-plotting tests
pass; the viridis-based plotting tests run on CI (a `viridisLite`
illegal-instruction crash on the dev node prevents running them locally).

**Deferred to a later cycle** (need live-API testing or data curation, so not
shipped blind): external data-source adapters — §2.1 (OWID / Eurostat / V-Dem);
the historical / dissolved-entity crosswalk — §2.2; subnational `admin1`
geometry — §2.3; the disputed-territory de-facto/de-jure policy — §2.6; and a
`world_snapshot` year refresh (needs the World Bank API at build time).

**Still open for 2.0.0** — additional features worth building *before* this
release ships are collected in the new **§2.7** below; the rest of this document
is the original plan, kept for reference.

**Second wave (implemented)** — a further pass over §2.2/§2.5/§2.7 picked out
everything that is self-contained, offline-testable and high-value for the
research audience, now shipped in 2.0.0 (see §2.8 for the itemised list and
design notes): the historical / dissolved-entity crosswalk (`historical_codes`
+ `dissolve_country()`, closing the §2.2 gap and the "USSR silently matches
Russia" trap), `correlate_indicators()`, `beta_convergence()` /
`sigma_convergence()`, `gini()` / `theil()` (population-weightable, with a
between/within decomposition), `lag_by_country()` / `diff_by_country()`,
`morans_i()` (spatial autocorrelation with *no* `spdep` dependency — it reuses
the shipped `country_borders()` adjacency), `spike_map()`, multilingual
`convert_country(to = "name_<lang>")`, and SI-formatted binned legends. Still
deferred (unchanged reasoning): §2.1 external adapters, §2.3 `admin1`
geometry / `cache_geometry()`, §2.6 point-in-time membership and the
disputed-territory policy, the ggsql render-engine broadening, the Shiny
module, and the animation/WebGL extras.

---

## 0. Carryover TODO (original note)

For the next release, we need to think about adding ggsql 0.4.1 to the package.
For details, refer to
<https://opensource.posit.co/blog/2026-06-23_ggsql_0_4_1/>.

---

## 1. Headline theme — make countryatlas the *data layer* for ggsql

### What ggsql is (so the integration is grounded)

`ggsql` is a CRAN package from posit-dev: *"A grammar of graphics for SQL."* It
lets you describe a plot **inside a SQL query** (clauses `VISUALISE` / `FROM` /
`DRAW` / `SCALE` / `PROJECT` / `FACET` / `LABEL` / `PLACE` / `MAPPING`,
`SETTING`), and executes the whole pipeline as optimised SQL on a backend
(DuckDB / SQLite today), returning a **Vega-Lite** widget. The R package is a
thin binding over a Rust engine; it ships a **knitr engine** (```` ```{ggsql} ````
chunks) and Shiny integration, takes data in via **nanoarrow** (so it can read
an R data frame or a live DBI/DuckDB connection), and has **no ggplot2/sf
runtime dependency**. Imports: cli, htmltools, htmlwidgets, jsonlite, knitr,
nanoarrow, R6, rlang, yaml; Suggests: V8, rsvg, quarto, shiny.

### Why 0.4.1 specifically matters to us

0.4.1 adds **spatial plotting** and it overlaps our entire reason for being:

- `DRAW spatial` — a spatial layer that maps a **`geometry` aesthetic** encoded
  as **WKB** (Well-Known Binary); auto-detects the geometry column, or
  `MAPPING <col> AS geometry`.
- a bundled **`ggsql:world`** dataset — Natural Earth 110m polygons + country
  names + ISO codes + continent/subregion + income group + population/GDP.
- **`PROJECT TO <projection>`** — ~21 named projections (orthographic, etc.).
- in-layer **aggregation** (compute per-bin/per-group in SQL).

`ggsql:world` is, essentially, a static, un-curated version of what
`world_data()` produces. That is the integration thesis: **countryatlas already
does the hard part ggsql's static table can't — the ISO-spine reconciliation,
the `wdj_overrides()` repairs, the WDI join, the curated reference data — and
ggsql does the part we don't — database push-down, no-runtime, web-ready
Vega-Lite output.** Wire them together rather than compete.

### Proposed surface (all gated behind `Suggests`)

1. **`as_ggsql_source(data, con = NULL, name = "countryatlas_world", format = c("duckdb","parquet","arrow"))`**
   Export a countryatlas spatial table (override-corrected geometry + WDI
   indicators + ISO spine) as a ggsql-ready source: register an **Arrow**/
   nanoarrow table, write a **DuckDB** table, or a **Parquet** file, with
   geometry **WKB-encoded** (`sf::st_as_binary(x, EWKB = FALSE)`). This is the
   killer combo — users run `DRAW spatial` against *their* curated, WDI-joined
   data instead of the static `ggsql:world`.

2. **`world_query(fill, ..., source = "countryatlas_world", style, projection, title)`**
   A **query emitter**: take roughly the same arguments as `world_map()` and
   return a ggsql query string, e.g.

   ```
   VISUALISE gdp_per_capita AS fill
   FROM countryatlas_world
   DRAW spatial
   PROJECT TO equal_earth
   SCALE fill TO viridis VIA log10
   LABEL title => 'GDP per capita, 2022'
   ```

   Pure string builder (zero deps); pairs with (3) for one-call rendering.

3. **`ggsql_map(data, fill, ..., render = TRUE)`** (or `world_map(..., engine = "ggsql")`)
   Convenience: `as_ggsql_source()` + `world_query()` + hand off to
   `ggsql::ggsql()` / the knitr engine when `render = TRUE`. Returns the
   Vega-Lite widget. Decision to make: **separate verb vs. `engine=` arg on the
   existing `world_map()`/`interactive_map()`** (recommend a new
   `interactive_map(engine = "ggsql")` — it slots beside the existing
   plotly/ggiraph/leaflet engines and keeps the spatial-WKB path in one place).

4. **WKB helper** — `attach_geometry(..., format = "wkb")` or a small
   `geometry_to_wkb()` so the sf backend can emit the column ggsql needs.

5. **Vignette + Quarto recipe** — *"countryatlas → ggsql"*: prep a DuckDB table
   with countryatlas, chart it in a ```` ```{ggsql} ```` chunk; show the
   push-down win (only aggregates leave the warehouse).

6. **Deps**: add `ggsql`, `duckdb`, `DBI`, `nanoarrow` to **Suggests**, gated by
   `rlang::check_installed()` — consistent with the "heavy deps stay optional"
   philosophy already in place for sf/leaflet/etc.

Open question for the author: do we want ggsql as a **render engine**
(countryatlas owns the spec, ggsql draws it) or only as an **export target**
(we hand off a clean source and let users write their own SQL)? Recommend
shipping the export target + query emitter first (low risk, high value), and
the render engine as a follow-up once the ggsql spatial API stabilises (it's
0.4.x / pre-1.0).

---

## 2. New features & functions (brainstorm, prioritised)

### 2.1 Data sources beyond WDI  ★ high value
The package is built on the ISO spine but only fetches the **World Bank**. The
spine makes adding sources cheap. Proposed pluggable fetchers, all returning the
same `iso3c`(+`year`) tidy shape so they drop straight into `country_join()`:
- `add_indicator(data, source = c("owid","eurostat","oecd","undata","penn"), ...)`
  or per-source `fetch_owid()`, `fetch_eurostat()`, `fetch_vdem()`.
- Our World in Data and V-Dem are especially natural (we already expose V-Dem /
  COW / Polity codes via `convert_country()`).

### 2.2 Join & reconciliation  ★ high value
- **`repair_country_names(x, threshold = 0.1)`** — promote `check_country_match()`
  from *suggest* to *auto-apply* high-confidence string-distance fixes, with a
  report of what it changed. The missing "act on it" half of the diagnostic.
- **Historical / dissolved entities** — a curated crosswalk so "USSR",
  "Yugoslavia", "Czechoslovakia", "Sudan (pre-2011)" resolve to successor
  states (one→many, dated). `check_country_match("Yugoslavia")` already flags
  this gap; ship the table, e.g. `historical_codes` + `dissolve_country()`.
- **`country_join_all(list_of_tables, by = ...)`** — reduce-join many messy
  tables on the ISO spine in one call.

### 2.3 Geometry & projections
- **Expand the projection set** to match ggsql (~21). Current `wdj_crs()` offers
  5; add Winkel Tripel, Eckert IV, Gall–Peters, azimuthal/**orthographic**
  (globe), polar. Enables a `globe_map()`. *(Also fixes the `plate_carree` bug —
  see §3.4.)*
- **Subnational geometry** — `world_geometry(level = "admin1")` via
  `rnaturalearth::ne_states()` for state/province maps on the same spine.
- **`locate_country(lon, lat)`** — point-in-polygon tagging of arbitrary
  coordinates to `iso3c` (handy for joining point data to the map).
- **`cache_geometry(scale)`** — pre-download/persist NE geometry (parallels the
  existing WDI on-disk cache) so the sf backend has an offline story too.

### 2.4 Visualization
- **`globe_map()`** (orthographic) once the projection lands.
- **`facet_map()`** — small-multiple choropleths (one panel per group/year)
  without hand-rolling `facet_wrap()`.
- **Hex/`statebins`-style** standalone, and `cartogram_map(type = "dorling")`
  promoted to a first-class `dorling_map()`.
- **Palette polish** — colourblind-safe sequential/diverging presets;
  comma/SI-formatted binned legends (binned currently shows raw breaks).

### 2.5 Analysis helpers
- `growth_rate()` / `cagr()`, `index_to(base_year = ..., to = 100)` (rebase a
  series), `share_of_world()`, panel `lag()`/`diff()` helpers.
- `correlate_indicators()` for quick cross-indicator scatter/▢ on the spine.

### 2.6 Reference data
- More groups in `country_groups_tbl`: African Union, Mercosur, GCC, Arab
  League, SADC, Nordic Council, Visegrád (V4), D-10.
- **Point-in-time versions** of membership (current table is a single snapshot
  as of 2024-01-01) — e.g. EU pre/post-Brexit — so panel joins are honest.
- A documented **disputed-territory policy** (Taiwan, W. Sahara, Palestine,
  Kosovo): a `de_facto`/`de_jure` option rather than silent backend defaults.

### 2.7 Additional features to add for 2.0.0 (new brainstorm)

Beyond §2.1–2.6, the following are fresh candidates worth building into the
2.0.0 release. They all hang off the existing ISO spine + sf/WDI plumbing, so
each is self-contained. Tagged ★ high value / ◐ medium / ◦ nice-to-have.

**More sources & richer joins**
- ◐ **Currency / real-terms helpers** — `deflate()` (constant vs current prices
  via a GDP-deflator/CPI series) and `to_ppp()` / `to_usd()`. Country economic
  data is almost always wanted in real or PPP terms; doing it on the spine kills
  a whole class of silent unit mistakes.
- ◐ **Population-weighted aggregation** — a `weight = ` / `weighted = TRUE` path
  on `aggregate_regions()` so regional means/medians weight by population or GDP
  instead of by country count.
- ◦ **Multilingual country names** — `convert_country(to = "name_fr"/"name_es"/…)`
  via countrycode's language tables, for localized labels and joining
  non-English source data.

**Geometry & spatial structure**
- ★ **Country adjacency / borders graph** — `country_borders()` returning a tidy
  neighbour list (and/or an `igraph`), with `neighbors("FRA")` and
  `distance_between(a, b)`. Unlocks contiguity analysis and "no two neighbours
  share a colour" map niceties.
- ◐ **Spatial autocorrelation** — Moran's I / LISA on the world spine using the
  adjacency above (gated `spdep` Suggests); a common ask for choropleth users.
- ◐ **Multiple Natural Earth scales** — expose `scale = c("110m","50m","10m")`
  consistently across `world_geometry()` and the maps, persisted by
  `cache_geometry()`.
- ◦ **Inset maps** — an `inset = TRUE` helper breaking out small/dense regions
  (Europe, the Caribbean, Pacific SIDS) so they're actually legible.

**Visualization**
- ★ **`dorling_map()`** — promote the Dorling cartogram to a first-class verb;
  add contiguous / non-contiguous cartograms with sane defaults (extends §2.4).
- ★ **`bivariate_legend()`** — finish the `bivariate_map()` story with a
  standalone legend, more palettes, and binning controls.
- ◐ **`spike_map()`** and a `statebins`-style standalone tile map beyond the
  US-oriented `tile_map()`.
- ◐ **Animated transitions** — `animate_world(transition = "tween")` between
  years (gganimate), and **`spin_globe()` → MP4** output (not just GIF).
- ◦ **Interactive WebGL globe** — an `rgl`/`three.js` globe complementing the
  static `globe_map()` / `spin_globe()`.

**Analysis helpers**
- ★ **`correlate_indicators()`** — quick cross-indicator correlation/scatter on
  the spine (listed in §2.5 but not yet shipped).
- ◐ **Convergence diagnostics** — `beta_convergence()` / `sigma_convergence()`,
  pairing naturally with the shipped `growth_rate()` / `index_to()`.
- ◐ **Inequality measures** — `gini()`, `theil()`, and a between/within
  decomposition across countries (population-weighted).
- ◐ **Panel utilities** — `build_panel()`, `lag_by_country()`,
  `diff_by_country()`, and `interpolate_missing()` (linear/LOCF) so panels join
  cleanly across patchy source coverage.

**ggsql, Shiny & reporting**
- ◐ **Broaden the ggsql render engine** — extend `world_query()` /
  `interactive_map(engine = "ggsql")` from spatial choropleths to bubble/binned
  layers and more `SCALE`/`FACET` verbs as the ggsql spatial API stabilises.
- ◐ **Shiny module** — `worldMapInput()` / `worldMapServer()` so a reconciled
  choropleth drops into an app in two lines (ggplot / leaflet / ggsql engine).
- ◦ **`gt` / report helpers** — `country_factsheet()` and a `gt`-formatted
  `world_table()` for one-country or top-N summaries.

### 2.8 Second wave for 2.0.0 (implemented — design notes)

A concrete, shippable cut of the remaining §2.2/§2.5/§2.7 candidates, chosen by
three filters: (a) hangs off the existing ISO spine / adjacency / panel
plumbing with **zero new hard dependencies**, (b) fully testable offline
(bundled snapshot or synthetic panels — no live API at test time), and (c)
directly useful to the research community (comparative development, inequality
and spatial econometrics are the three most common uses of exactly this data).

**Join & reconciliation (closes the §2.2 gap)**
- **`historical_codes`** (bundled dataset) — a curated crosswalk of dissolved
  entities to their successor states, one row per (entity, successor):
  Soviet Union → 15, SFR Yugoslavia → 7 (incl. XKX, territory-based),
  Serbia and Montenegro, Czechoslovakia, East Germany, Netherlands Antilles,
  North/South Yemen, Sudan (pre-2011) → SDN+SSD, United Arab Republic,
  Tanganyika/Zanzibar, North/South Vietnam. Retired ISO codes (`SUN`, `YUG`,
  `CSK`, `DDR`, `ANT`, `SCG`, `YMD`) are carried where they existed.
- **`dissolve_country(x)`** — resolve a mixed vector of historical *and*
  modern names to successor `iso3c` rows (one→many, dated). Modern names pass
  through as single rows, so a whole messy column can be piped in unchanged.
- **`check_country_match()` gains a `historical` column** — flags dissolved
  entities *even when countrycode "matches" them*: the killer case is
  `"USSR"`, which countrycode silently resolves to `RUS` (measured), so Soviet-
  era data quietly becomes Russian data. The flag catches Yugoslavia (NA) and
  USSR (false-positive RUS) alike and points at `dissolve_country()`.

**Analysis helpers (ships the §2.5/§2.7 spine)**
- **`correlate_indicators(data, ...)`** — pairwise correlation of indicator
  columns on the spine (pearson/spearman, pairwise-complete, per-pair `n`),
  tidy long output sorted by |r|.
- **`beta_convergence(data, value)`** — the growth-regression convergence
  test (average log growth on log initial level), returning `beta`, inference,
  implied convergence `speed` and `half_life` in one row.
- **`sigma_convergence(data, value)`** — cross-country dispersion per year
  (sd of logs, or CV), the "is the distribution actually narrowing" companion.
- **`gini(x, weights = )`** and **`theil(x, weights = , groups = )`** —
  inequality across countries, population-weightable; `theil()` decomposes
  between/within groups (continents, income groups) when `groups` is given.
- **`lag_by_country()` / `diff_by_country()`** — panel lag/difference done
  right (grouped by `iso3c`, ordered by `year`), completing the set with
  `growth_rate()` / `index_to()` / `complete_years()`.

**Spatial statistics (the §2.7 ask, minus the spdep dependency)**
- **`morans_i(data, value)`** — global Moran's I with a permutation
  pseudo-p-value, computed on the row-standardised `country_borders()`
  adjacency. No `spdep`: at 200 countries the dense-matrix arithmetic is
  trivial, and reusing our own adjacency keeps the weights consistent with
  the maps. (LISA / local Moran's stays deferred; it wants map integration.)

**Visualization polish**
- **`spike_map(data, height)`** — the classic "population spikes" display:
  triangular spikes at country centroids, height ∝ value. Uses the same
  polygon centroids as `bubble_map()`; needs only `maps`.
- **Formatted binned legends** — `world_map(style = "binned")` now labels
  breaks with SI-formatted numbers (`4M`, not `4e+06`) when `scales` is
  installed, closing the §2.4 "raw breaks" note.

**Reference data**
- **Multilingual names** — `convert_country(to = "name_fr" / "name_es" /
  "name_de" / ...)` maps any `name_<lang>` to countrycode's CLDR tables
  (`cldr.name.<lang>`, 555 columns available), for localized labels and
  joining non-English sources.

---

## 3. Bugs found in 1.0.0 (fix in 2.0.0)

Found by static review and then **reproduced on R 4.4.1** (`maps` +
`countrycode`; `sf`/`WDI` weren't installed, so the two sf-only items are
static-analysis only). Ordered by impact. Evidence is quoted inline.

### 3.1 ★★★ `world_map()` quantile/jenks breaks are vertex-weighted, not country-weighted
`R/visualization.R:92-100` (with `compute_breaks()` at `:33-45`).
**Confirmed (R 4.4.1).**

For the **polygon backend**, `data` is one row *per boundary vertex*, so
`vals <- data[[fill_name]]` repeats each country's value once per vertex
(tens to thousands of times). `compute_breaks(vals, "quantile"/"jenks", n_bins)`
therefore computes quantiles over **vertices**, weighting each country by its
geometric complexity. A jagged country (Canada, Norway, Indonesia, the UK with
its islands) dominates the breakpoints; the "quantile" map no longer has roughly
equal countries per colour — the central promise of a quantile choropleth.
(`sf` backend is one row per country, so it's unaffected; `binned` is range-based
so also unaffected. `interactive_map()`/`animate_world()` inherit the bug via
`world_map()`.)

**Evidence:** with `map_data("world")` (vertex counts range 6 … 11,573 — Canada
alone is 11,573 vertices), a 5-bin quantile choropleth on a synthetic skewed
indicator put **62 / 60 / 28 / 69 / 32** countries in the five colour bins;
country-weighted breaks put **51 / 50 / 50 / 50 / 50**. The "equal countries per
colour" guarantee is broken.

**Fix:** compute breaks on one value per country, then cut the full vector:
```r
key  <- if ("iso3c" %in% names(data)) "iso3c" else "group"
uvals <- dplyr::distinct(data, .data[[key]], .keep_all = TRUE)[[fill_name]]
br <- compute_breaks(uvals, style, n_bins)
data[[".wdj_bin"]] <- cut(vals, br, include.lowest = TRUE, dig.lab = 4)
```

### 3.2 ★★★ `bubble_map(backend = "sf")` plots bubbles in projected metres on a degrees map
`R/visualization.R:187-211`. High confidence (static — `sf` not installed here,
but the code path is unambiguous).

When `backend = "sf"`, centroids come from
`world_geometry("centroids", geometry = "sf", projection = ...)` → coordinates in
**projected metres** (e.g. ±1.7e7). But the base layer is always
`geom_polygon(world_geometry("countries", geometry = "polygon"), aes(long, lat))`
+ `coord_quickmap()` — i.e. **degrees** (±180). The bubbles render far outside
the map. So the `backend = "sf"` and `projection` arguments are effectively
broken (the polygon path "works" only because it ignores `projection` entirely
and stays in degrees).

**Fix:** draw the base map in the same space as the centroids — either use the
sf base map with `coord_sf()` when `backend = "sf"`, or compute centroids in
lon/lat and let `coord_sf(crs = ...)` do the projection.

### 3.3 ★★ Duplicate polygon centroids fan out `bubble_map()` and `flow_map()`
`R/geometry.R:219-227` (`polygon_centroids()`), consumed at
`R/visualization.R:193` and `:361-372`. **Confirmed (R 4.4.1):**
`world_geometry("centroids", geometry = "polygon")` returns **>1 row for 10
iso3c codes** — BES and PRT have **3** each (Bonaire/Saba/Sint Eustatius;
Portugal/Azores/Madeira), ATG/ESP/IND/KNA/SGS/SHN/TTO/VCT have 2. A 1-row table
of `c("PRT","ESP")` joined to these centroids becomes **3** and **2** rows.

`polygon_centroids()` does `group_by(iso3c, region)` where `region` is the
*map_data country-name* column. Because `wdj_overrides()` deliberately maps
several names to one ISO code (Azores+Madeira→PRT, Canary Islands→ESP,
Bonaire+Saba+Sint Eustatius→BES, …), the result has **multiple centroid rows per
`iso3c`**. Downstream `left_join(data, cent, by = "iso3c")` then **fans out**:
`bubble_map()` draws several full-size bubbles for those countries (each
encoding the whole national total), and `flow_map()` draws duplicate arcs.

**Fix:** return one centroid per `iso3c` (e.g. the largest-ring centroid, as
`data-raw/build_datasets.R:129-143` already computes — or just reuse
`country_meta`'s `centroid_lon/lat`), and/or `distinct(iso3c)` before the join.

### 3.4 ★★ `plate_carree` builds an incoherent PROJ string
`R/geometry.R:11-19`. **Confirmed (R 4.4.1):** `wdj_crs("plate_carree")` returns
`+proj=longlat +lon_0=0 +datum=WGS84 +units=m +no_defs` — a **geographic** CRS
(degrees) tagged with metres. `st_transform()` to this just *un*-projects, and
`+lon_0=` recentering doesn't behave like a real plate carrée. Plate carrée is
equirectangular = `+proj=eqc`.

**Fix:** `plate_carree = "+proj=eqc +lat_ts=0"` (and let the shared `+units=m`
apply correctly). Roll this in with the projection expansion in §2.3.

### 3.5 ★★ `geom_country_labels()` centroid breaks for antimeridian/multi-part countries
`R/visualization.R:551-564`. **Confirmed (R 4.4.1)** — worse than expected.

Labels are placed at `mean(range(long))`, `mean(range(lat))` over **all** of a
country's vertices, so any country crossing the antimeridian lands its label in
the wrong ocean. Measured bounding-box centroids:
**USA → lon 0.8** (Alaska's Aleutians cross 180°, dragging it into the Atlantic
off Africa), **Fiji → lon 0.2**, **New Zealand → lon 0.8**. (`data-raw` already
uses a better largest-ring centroid; the runtime path doesn't.) Same root cause
as the crude centroid in 3.3.

**Fix:** reuse `country_meta` centroids or the largest-polygon approach; share
one centroid implementation across `polygon_centroids()`, the labels layer, and
`bubble_map()`/`flow_map()`.

### 3.6 ◦ Dead no-op in `aggregate_regions()`
`R/analysis.R:81-83` (confirmed by inspection):
```r
if (length(by) > 1L) { if ("year" %in% names(data)) by <- by }  # by <- by does nothing
```
Harmless but confusing — remove. Low confidence it was meant to do something;
the `missing_by` check below already validates grouping columns.

### 3.7 ◦ `convert_country()` overrides only apply when `to == "iso3c"`
`R/reference.R:56-66` (gate at `:61`). **Confirmed (R 4.4.1).**

The override gate sets `custom_match` only for `to == "iso3c"`, so override-only
entities (names `countrycode` doesn't recognise natively) return `NA` for every
*derived* destination. Measured:
`convert_country("Canary Islands", to = "iso3c")` → **ESP**, but
`convert_country("Canary Islands", to = "continent")` → **NA** (same for
`"Azores"` → PRT / NA). `standardize_country()` gets both right (**Europe**)
because it routes through `iso3c` first. (Note: many names *are* recognised
natively — `convert_country("Kosovo", to = "flag")` works — so the gate only
bites for override-only names, which is exactly why it's easy to miss.)

**Fix:** resolve to `iso3c` (with overrides) first, then convert `iso3c →
dest`.

### 3.8 ◦ Naming drift after the `worlddatajoin → countryatlas` rename
The user-facing **`wdj_overrides()`** export and the `wdj_coverage` S3 class
still carry the old prefix; internals are a mix of `wdj_*` and `countryatlas_*`.
Not a bug, but a polish item: add a `country_overrides()` alias (+ keep
`wdj_overrides()` as a soft-deprecated alias) so the public API matches the name.

---

## 4. Housekeeping / deprecations

- **Resolve the `gdp_per_capita_2015` shim** (`R/world_data.R:104-109`). 1.0.0
  promised a *one-cycle* alias; 2.0.0 is that cycle — drop it (or flip the
  default and warn). The `next_release` note that triggered this review.
- **Refresh `world_snapshot`** — `data-raw/build_datasets.R:18` pins
  `SNAPSHOT_YEAR <- 2022L`; bump to the latest year with good WDI coverage and
  rebuild the bundled `.rda`s.
- **Bump the membership date** if any group changed since 2024-01-01, and note
  it in `NEWS.md`.
- Add the new optional deps to `Suggests` and a single "Optional features" table
  in the README so the ggsql/duckdb path is discoverable.

---

## 5. Suggested cut for 2.0.0 (recommendation)

1. **All of §3** (bug fixes) — these are correctness issues in core/visual paths.
2. **ggsql export target + `world_query()` emitter** (§1.1–1.2, 1.4) + vignette.
3. **Projection expansion + `globe_map()`** (§2.3/2.4) — small, high-visibility.
4. **One or two §2.7 additions** that are self-contained and high-visibility —
   `dorling_map()` and/or `country_borders()` are the strongest candidates.
5. Defer the broader data-source adapters (§2.1) and historical crosswalk (§2.2)
   to a later cycle unless there's appetite; they're larger and want their own
   design.

---

## References

- ggsql 0.4.1 (spatial) — <https://opensource.posit.co/blog/2026-06-23_ggsql_0_4_1/>
- ggsql alpha announcement — <https://opensource.posit.co/blog/2026-04-20_ggsql_alpha_release/>
- ggsql source — <https://github.com/posit-dev/ggsql>
- ggsql on CRAN — <https://cran.r-project.org/web/packages/ggsql/index.html>
- ggsql syntax reference — <https://ggsql.org/syntax/>
- Our World in Data API — <https://docs.owid.io/>
- V-Dem dataset — <https://www.v-dem.net/data/the-v-dem-dataset/>
- Natural Earth subnational (`rnaturalearth::ne_states()`) — <https://www.naturalearthdata.com/>
