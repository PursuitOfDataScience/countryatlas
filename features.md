# countryatlas — Future Features

> ## Status: fully implemented in 3.0.0
>
> **Every wave in §17 is built.** This document is now a record of the
> design reasoning rather than a plan. 45 new exports and two new
> datasets landed in 3.0.0; see NEWS.md for the release notes and the
> per-function help for the details.
>
> | Wave | Status |
> |----|----|
> | 1 — correctness, honesty, small wins | **Done.** The ggsql guard was already in 2.0.1. Everything else shipped, plus [`tissot_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/tissot_map.md) and [`projection_distortion()`](https://pursuitofdatascience.github.io/countryatlas/reference/projection_distortion.md). |
> | 2 — the data-source contract | **Done.** [`register_country_source()`](https://pursuitofdatascience.github.io/countryatlas/reference/register_country_source.md), [`country_sources()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_sources.md), [`fetch_indicator()`](https://pursuitofdatascience.github.io/countryatlas/reference/fetch_indicator.md), [`add_indicator()`](https://pursuitofdatascience.github.io/countryatlas/reference/add_indicator.md), [`compare_sources()`](https://pursuitofdatascience.github.io/countryatlas/reference/compare_sources.md), all four adapters, and [`clear_country_cache()`](https://pursuitofdatascience.github.io/countryatlas/reference/clear_country_cache.md). |
> | 3 — time | **Done.** `country_groups_history` + `as_of`, [`country_timeline()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_timeline.md), [`audit_time_coverage()`](https://pursuitofdatascience.github.io/countryatlas/reference/audit_time_coverage.md), [`historical_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/historical_geometry.md) on CShapes, and the COW/GW second spine via `country_join(key =)`. |
> | 4 — honesty, continued | **Done.** `disputed_territories` + [`dispute_policy()`](https://pursuitofdatascience.github.io/countryatlas/reference/dispute_policy.md) + [`check_dispute_coverage()`](https://pursuitofdatascience.github.io/countryatlas/reference/check_dispute_coverage.md) + `world_map(disputes =)`; [`rate_check()`](https://pursuitofdatascience.github.io/countryatlas/reference/rate_check.md), [`smooth_rates()`](https://pursuitofdatascience.github.io/countryatlas/reference/smooth_rates.md), [`interpolate_missing()`](https://pursuitofdatascience.github.io/countryatlas/reference/interpolate_missing.md); the VSUP via `world_map(uncertainty =)`; [`deflate()`](https://pursuitofdatascience.github.io/countryatlas/reference/deflate.md), [`to_ppp()`](https://pursuitofdatascience.github.io/countryatlas/reference/to_ppp.md), [`convergence_club()`](https://pursuitofdatascience.github.io/countryatlas/reference/convergence_club.md). |
> | 5 — reach | **Done.** [`country_weights()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_weights.md) and the full LISA/Geary/Getis-Ord/spatial-lag set; [`flow_matrix()`](https://pursuitofdatascience.github.io/countryatlas/reference/flow_matrix.md), [`country_network()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_network.md), [`od_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/od_map.md); `mapgl` interactivity and the interactive globe; [`country_factsheet()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_factsheet.md), [`world_table()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_table.md). |
> | 6 — subnational | **Done.** [`standardize_subnational()`](https://pursuitofdatascience.github.io/countryatlas/reference/standardize_subnational.md), [`nuts_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/nuts_geometry.md), [`subnational_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/subnational_map.md), scoped to ISO 3166-2 and NUTS. |
>
> ### The §18 open questions, as decided
>
> 1.  **Second spine for historical work?** Yes.
>     `country_join(key = "gwn"/"cowc"/"cown")`, and it warns about the
>     dependencies COW/GW cannot carry.
> 2.  **`tmap` as a backend?** Yes, as `world_map(engine = "tmap")` — a
>     door, not a second front door. The package stays ggplot2-native.
> 3.  **Equal Earth as default?** It already was. Now documented and
>     recommended explicitly, with the citation, and
>     [`projection_distortion()`](https://pursuitofdatascience.github.io/countryatlas/reference/projection_distortion.md)
>     lets anyone verify the claim.
> 4.  **`Suggests` vs registration for sources?** Both: registration is
>     the mechanism, four adapters ship for discoverability.
> 5.  **How much dispute curation?** A documented subset of 22, with a
>     mechanical inclusion criterion that requires nobody to judge the
>     merits, and an explicit statement that the table does not
>     adjudicate.
> 6.  **Do we ever impute?** Yes, and the `.imputed` flag is
>     non-optional.
>     [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md)
>     reads it and notes it in the caption.
> 7.  **Snapshot cadence?** Unchanged; still 2024, still the thing that
>     makes every example offline.
> 8.  **Is
>     [`check_country_match()`](https://pursuitofdatascience.github.io/countryatlas/reference/check_country_match.md)
>     still the best matcher?** Not benchmarked against `countries`
>     1.2.4. The one item here that remains genuinely open.
>
> ### What was deliberately *not* built
>
> The “explicitly not planned” list in §17 still stands: no general GIS
> layer, no reimplemented projections or cartogram algorithms, no
> bundled large or restrictively-licensed geometry, no admin2, no Shiny
> dependency, and no position on any territorial dispute.
>
> Five bugs were also found by auditing 2.0.1 alongside this work — none
> of them predicted by this document. It is good at naming absent
> features and poor at naming broken ones.

*A research- and CRAN-grounded feature catalogue for the releases after
2.0.0. This is a **design and literature document**, not a changelog and
not a commitment. §2 surveys the cartographic/statistical literature and
the R data ecosystem, with **CRAN availability verified against the live
CRAN index** (July 2026); §3–§16 turn that into concrete, API-level
proposals; §17 prioritises. No package code is changed by this
document.*

**Relationship to `next_release.md`.** That file is the 2.0.0 planning
ledger: the ggsql bridge, the 2.0.0 bug audit (§3 there), the two
implemented waves, and five items explicitly **deferred** for wanting
live-API testing or data curation — external data-source adapters, the
historical/dissolved-entity crosswalk (partly shipped as
`historical_codes`/[`dissolve_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/dissolve_country.md)),
subnational `admin1` geometry, the disputed-territory de-facto/de-jure
policy, and a `world_snapshot` refresh. This file is the idea space
behind and beyond that. Items already named there are marked
**\[ledger\]**, and for those the new content is the *research
grounding* and a design that removes the reason they were deferred.

> **Two verified findings to act on before anything else.**
>
> 1.  **The ggsql bridge targets a version CRAN does not have.**
>     `R/ggsql.R` documents itself against ggsql’s “`DRAW spatial`,
>     0.4.1+”, but the version published on CRAN is **ggsql 0.3.3**. A
>     CRAN user who installs the suggested `ggsql` therefore gets a
>     package that may not understand the emitted queries.
>     [`as_ggsql_source()`](https://pursuitofdatascience.github.io/countryatlas/reference/as_ggsql_source.md)
>     /
>     [`world_query()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_query.md)
>     / `interactive_map(engine = "ggsql")` should carry an explicit
>     `packageVersion("ggsql") >= "0.4.1"` guard with an actionable
>     message, and the vignette should state the requirement. (See §12.)
> 2.  **`cshapes` 2.0 is on CRAN.** The deferred historical work (§2.2
>     of the ledger) assumed hand-curation was the only route. CShapes
>     2.0 (Schvitz et al., *JCR* 2022) ships historical country
>     *geometry* for 1886–2019 including colonies and dependencies, with
>     COW/GW codes — which turns “historical crosswalk” into “historical
>     **maps**”, a much bigger feature than the one that was deferred.
>     (See §4.)

------------------------------------------------------------------------

## Contents

1.  [Where the package stands
    today](#id_1-where-the-package-stands-today)
2.  [The survey: literature and
    ecosystem](#id_2-the-survey-literature-and-ecosystem)
3.  [Theme A — Data sources beyond the World
    Bank](#id_3-theme-a--data-sources-beyond-the-world-bank)
4.  [Theme B — Time: historical states, boundaries and
    memberships](#id_4-theme-b--time-historical-states-boundaries-and-memberships)
5.  [Theme C — Honest maps I: projection and
    area](#id_5-theme-c--honest-maps-i-projection-and-area)
6.  [Theme D — Honest maps II: classification, rates and the
    small-number
    problem](#id_6-theme-d--honest-maps-ii-classification-rates-and-the-small-number-problem)
7.  [Theme E — Honest maps III: uncertainty and
    missingness](#id_7-theme-e--honest-maps-iii-uncertainty-and-missingness)
8.  [Theme F — Cartograms and area-equalising
    alternatives](#id_8-theme-f--cartograms-and-area-equalising-alternatives)
9.  [Theme G — Disputed territories, sovereignty and
    status](#id_9-theme-g--disputed-territories-sovereignty-and-status)
10. [Theme H — Subnational
    geography](#id_10-theme-h--subnational-geography)
11. [Theme I — Spatial statistics done
    properly](#id_11-theme-i--spatial-statistics-done-properly)
12. [Theme J — Flows, networks and relational
    data](#id_12-theme-j--flows-networks-and-relational-data)
13. [Theme K — Renderers, interactivity and the ggsql
    bridge](#id_13-theme-k--renderers-interactivity-and-the-ggsql-bridge)
14. [Theme L — Reporting, provenance and
    reproducibility](#id_14-theme-l--reporting-provenance-and-reproducibility)
15. [Theme M — Analysis helpers: the comparative-development
    toolkit](#id_15-theme-m--analysis-helpers)
16. [Theme N — Architecture, performance,
    infrastructure](#id_16-theme-n--architecture-performance-infrastructure)
17. [Prioritisation](#id_17-prioritisation)
18. [Open questions and decisions
    needed](#id_18-open-questions-and-decisions-needed)
19. [References](#id_19-references)

------------------------------------------------------------------------

## 1. Where the package stands today

2.0.0 exports 60 functions and six bundled datasets across five jobs:

| Job | Exports |
|----|----|
| Join on the ISO spine | [`join_world()`](https://pursuitofdatascience.github.io/countryatlas/reference/join_world.md), [`country_join()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_join.md), [`country_join_all()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_join_all.md), [`attach_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/attach_geometry.md), [`standardize_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/standardize_country.md), [`convert_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/convert_country.md), [`check_country_match()`](https://pursuitofdatascience.github.io/countryatlas/reference/check_country_match.md), [`repair_country_names()`](https://pursuitofdatascience.github.io/countryatlas/reference/repair_country_names.md), [`locate_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/locate_country.md), [`dissolve_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/dissolve_country.md), [`country_overrides()`](https://pursuitofdatascience.github.io/countryatlas/reference/wdj_overrides.md), [`audit_coverage()`](https://pursuitofdatascience.github.io/countryatlas/reference/audit_coverage.md) |
| Fetch / reference | [`country_data()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_data.md), [`world_data()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_data.md), [`wdi_search()`](https://pursuitofdatascience.github.io/countryatlas/reference/wdi_search.md), [`common_indicators()`](https://pursuitofdatascience.github.io/countryatlas/reference/common_indicators.md), `country_meta`, [`country_codes()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_codes.md), [`country_groups()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_groups.md), [`in_group()`](https://pursuitofdatascience.github.io/countryatlas/reference/in_group.md), `historical_codes`, [`clear_wdi_cache()`](https://pursuitofdatascience.github.io/countryatlas/reference/clear_wdi_cache.md), `world_snapshot` |
| Geometry | [`world_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_geometry.md), [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md), [`country_borders()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_borders.md), [`neighbors()`](https://pursuitofdatascience.github.io/countryatlas/reference/neighbors.md), [`distance_between()`](https://pursuitofdatascience.github.io/countryatlas/reference/distance_between.md), [`simplify_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/simplify_geometry.md), `world_tiles` |
| Maps | [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md), [`bubble_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/bubble_map.md), [`bivariate_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/bivariate_map.md), [`cartogram_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/cartogram_map.md), [`dorling_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/dorling_map.md), [`tile_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/tile_map.md), [`spike_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/spike_map.md), [`flow_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/flow_map.md), [`globe_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/globe_map.md), [`spin_globe()`](https://pursuitofdatascience.github.io/countryatlas/reference/spin_globe.md), [`facet_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/facet_map.md), [`animate_world()`](https://pursuitofdatascience.github.io/countryatlas/reference/animate_world.md), [`interactive_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/interactive_map.md), [`geom_country_labels()`](https://pursuitofdatascience.github.io/countryatlas/reference/geom_country_labels.md), [`theme_world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/theme_world_map.md) |
| Analysis | [`per_capita()`](https://pursuitofdatascience.github.io/countryatlas/reference/per_capita.md), [`aggregate_regions()`](https://pursuitofdatascience.github.io/countryatlas/reference/aggregate_regions.md), [`rank_countries()`](https://pursuitofdatascience.github.io/countryatlas/reference/rank_countries.md), [`growth_rate()`](https://pursuitofdatascience.github.io/countryatlas/reference/growth_rate.md), [`index_to()`](https://pursuitofdatascience.github.io/countryatlas/reference/index_to.md), [`share_of_world()`](https://pursuitofdatascience.github.io/countryatlas/reference/share_of_world.md), [`complete_years()`](https://pursuitofdatascience.github.io/countryatlas/reference/complete_years.md), [`lag_by_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/lag_by_country.md), [`diff_by_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/lag_by_country.md), [`correlate_indicators()`](https://pursuitofdatascience.github.io/countryatlas/reference/correlate_indicators.md), [`beta_convergence()`](https://pursuitofdatascience.github.io/countryatlas/reference/beta_convergence.md), [`sigma_convergence()`](https://pursuitofdatascience.github.io/countryatlas/reference/sigma_convergence.md), [`gini()`](https://pursuitofdatascience.github.io/countryatlas/reference/gini.md), [`theil()`](https://pursuitofdatascience.github.io/countryatlas/reference/theil.md), [`morans_i()`](https://pursuitofdatascience.github.io/countryatlas/reference/morans_i.md) |
| Database | [`as_ggsql_source()`](https://pursuitofdatascience.github.io/countryatlas/reference/as_ggsql_source.md), [`world_query()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_query.md) |

**Design commitments to preserve.** ISO codes are the universal join
key; heavy spatial dependencies (`sf`, `cartogram`, `leaflet`, …) stay
in `Suggests`; a bundled `world_snapshot` (2024) lets every example,
test and vignette run offline; `maps`-based polygons are the
zero-dependency default with `sf` as the opt-in upgrade.

**Where the gaps are now.** The 2.0.0 cycle closed the *map vocabulary*
gap and the *panel-helpers* gap. What remains, and what this document is
organised around, is: **one data source** (§3), **no time dimension for
geography or membership** (§4), **honesty features the package’s own
tagline promises but does not yet deliver** (§5–§9), **no subnational
level** (§10), and **spatial statistics that silently drop every
island** (§11).

------------------------------------------------------------------------

## 2. The survey: literature and ecosystem

### 2.1 Cartographic and statistical literature

| Finding | Source | Feature |
|----|----|----|
| **Equal-area world projections are a solved problem with a modern default.** Equal Earth is equal-area, Robinson-like in appearance, cheap to evaluate, and in PROJ as `eqearth` | Šavrič, Patterson & Jenny (2019), *IJGIS* 33(3) | §5 |
| **Classification method materially changes what readers conclude.** A 56-subject study over nine mortality-map series found **quantiles** and minimum-boundary-error best for general choropleth reading; **natural breaks (Jenks)** and hybrid equal-interval were \<70% as accurate | Brewer & Pickle (2002), *Annals of the AAG* | §6 |
| **Rates over small denominators visually dominate maps.** The “small-number problem”: a 3-person country’s rate outshouts a 300-million-person country’s | Roth, Woodruff & Johnson (2010), *Cartographic Journal* | §6, §8 |
| **Value-by-alpha equalises the basemap without distorting geometry** — a bivariate technique where alpha encodes the equalising variable; the direct alternative to a cartogram | Roth, Woodruff & Johnson (2010) | §8 |
| **Bivariate uncertainty maps are hard to read; VSUPs are measurably better.** Value-Suppressing Uncertainty Palettes allocate more of the colour range where uncertainty is low, and crowdsourced evaluation showed readers weight uncertainty more heavily | Correll, Moritz & Heer (2018), *CHI* | §7 |
| **Contiguous cartograms are now fast.** The flow-based algorithm computes cartograms in seconds where diffusion-based methods took minutes | Gastner, Seguy & More (2018), *PNAS* 115 | §8 |
| **Every world map takes a political position.** Natural Earth documents an explicit **de facto** policy with de jure claim lines in an auxiliary layer; the EU data-visualisation guide notes ~188 disputed areas and that official publications must reflect an official position | Natural Earth disputed-boundaries policy; EU data-viz guide | §9 |
| **Historical state boundaries are an available dataset, not a research project.** CShapes 2.0 maps states *and colonies/dependencies* 1886–2019 with per-polygon validity periods, status, capital, and COW/GW codes | Schvitz et al. (2022), *JCR* 66(1): 144–161 | §4 |
| **Country-name reconciliation is a recognised methodological problem** with an established solution and a standard citation | Arel-Bundock, Enevoldsen & Yetman (2018), *JOSS* — `countrycode` | §3, §14 |

### 2.2 R ecosystem — CRAN-verified (July 2026)

**Data clients that could feed the spine** (all live on CRAN): `owidR`
1.4.2 (Our World in Data), `eurostat` 4.0.0, `OECD` 0.2.5, `wbwdi` 1.0.4
and `worldbank` 0.9.1 and `wbstats` 1.1 (alternative World Bank clients
to the `WDI` 2.7.10 we depend on), `comtradr` 1.0.5 (UN trade), `rdhs`
0.8.1 (DHS surveys), `acledR` 1.0.1 (conflict events), `ipumsr` 0.10.0,
`fredr` 2.1.0, `gapminder` 1.0.1. **Not on CRAN:** `vdemdata`, `imfr`,
WID clients — these are exactly the case for a registration mechanism
rather than a `Suggests` entry (§3).

**Geography** (all live): `cshapes` **2.0** (historical boundaries),
`rnaturalearth` 1.2.0, `giscoR` 1.1.1 (Eurostat/GISCO, NUTS), `geodata`
0.6-9 (GADM et al.), `regions` 0.1.8 (subnational code reconciliation,
NUTS vintages), `states` 0.3.3 (COW/GW state-system membership over
time), `sf` 1.1-2, `s2` 1.1.11, `terra`, `stars`, `rmapshaper` 0.6.1.

**Cartography and rendering** (all live): `cartogram` 0.3.0 (Dorling /
Dougenik / non-contiguous), **`cartogramR` 1.5-1** (the fast flow-based
Gastner–Seguy–More algorithm — *not currently used*), `classInt` 0.4-11,
`biscale` 1.1.0, `ggpattern` 1.3.1, `tmap` 4.4-1, `mapsf` 1.2.1,
**`mapgl` 0.5.0** (MapLibre/Mapbox GL — a modern WebGL alternative to
`leaflet`), `leaflet` 2.2.3, `ggiraph`, `plotly`, `gganimate`,
`patchwork`, `ggspatial`.

**Spatial statistics** (all live): `spdep` 1.4-2, `sfdep` 0.2.5 (tidy
interface), `rgeoda` 0.1.1 (GeoDa: LISA variants, spatial clustering).

**Country-name tooling:** `countrycode` 1.8.0 (our dependency),
`ISOcodes` 2026.03.28, `countries` 1.2.4 (a newer fuzzy-matching
alternative worth benchmarking
[`check_country_match()`](https://pursuitofdatascience.github.io/countryatlas/reference/check_country_match.md)/[`repair_country_names()`](https://pursuitofdatascience.github.io/countryatlas/reference/repair_country_names.md)
against).

**`ggsql` is at 0.3.3 on CRAN** — see the finding at the top of this
document.

### 2.3 What the survey implies

1.  **The “one source” limitation is the biggest gap, and it is cheap to
    close** *if* we build an adapter contract rather than N bespoke
    fetchers (§3).
2.  **`cshapes` turns the deferred historical work into a headline
    feature** (§4).
3.  **The package’s tagline — “getting country data onto *honest* maps”
    — currently means “equal-area projections are available”.** The
    literature says honesty is also classification (§6), denominators
    (§6, §8), uncertainty (§7), missingness (§7) and sovereignty (§9).
    These are the features that would make the tagline true, and no R
    package offers them as a coherent set.
4.  **Two CRAN packages we should already be using are absent**:
    `cartogramR` (fast contiguous cartograms) and `mapgl` (modern
    interactivity).
5.  **[`morans_i()`](https://pursuitofdatascience.github.io/countryatlas/reference/morans_i.md)’s
    island exclusion is a documented choice, not a bug — but it is a
    consequential one**, dropping Japan, the UK, Indonesia, Australia,
    Madagascar, New Zealand, the Philippines and every small island
    state from any spatial-autocorrelation analysis. Alternative weight
    schemes fix it (§11).

------------------------------------------------------------------------

## 3. Theme A — Data sources beyond the World Bank **\[ledger §2.1, deferred\]**

**Problem.** The ISO spine is source-agnostic by design, but only `WDI`
is wired. The ledger deferred this for wanting live-API testing — a real
concern, and the design below is what removes it.

**Features.**

``` r

# 1. the adapter contract — the thing that makes everything else cheap
register_country_source(name, fetch, meta = NULL, citation = NULL,
                        key_col = "iso3c", cache = TRUE)
country_sources()          # registry: name, provider, coverage, citation, live?

# 2. one verb, many sources; all return the same iso3c[/year] tidy shape
fetch_indicator(source, indicator, countries = NULL, years = NULL)
add_indicator(data, source, indicator, ...)     # fetch + country_join in one step

# 3. built-in adapters for CRAN-available providers
fetch_owid(...)        # owidR
fetch_eurostat(...)    # eurostat  (+ giscoR for NUTS geometry, §10)
fetch_oecd(...)        # OECD
fetch_comtrade(...)    # comtradr  (feeds §12 flow maps)

# 4. cross-source reconciliation, which is where the real value is
compare_sources(indicator, sources = c("wdi", "owid"), year)
#> per-country values side by side, correlation, coverage overlap, disagreements
```

**Design notes.**

- **Build the contract first, the adapters second.**
  [`register_country_source()`](https://pursuitofdatascience.github.io/countryatlas/reference/register_country_source.md)
  means users reach `vdemdata`, `imfr` or a WID client — none of which
  are on CRAN — without the package depending on them, and it means a
  proprietary or internal source is a first-class citizen. This is the
  same architectural move that keeps `Suggests` from exploding.
- **Live-API testing was the blocker; here is the answer.** Every
  adapter is `Suggests`-gated and every test runs against a **recorded
  fixture**, not the network: ship small recorded responses in
  `tests/testthat/fixtures/`, test the *parsing and reshaping* offline,
  and mark the one live-connectivity test `skip_on_cran()` +
  `skip_if_offline()`. This is standard practice and it entirely removes
  the reason for deferral.
- **[`compare_sources()`](https://pursuitofdatascience.github.io/countryatlas/reference/compare_sources.md)
  is the differentiating feature, not the fetchers.** Anyone can call
  `owidR`. What nobody does is tell you that OWID’s and the World Bank’s
  GDP-per-capita disagree for 14 countries because of different
  vintages, PPP bases or territorial definitions. On the ISO spine that
  comparison is one join, and it is exactly the kind of quiet error the
  package exists to prevent.
- **Metadata harmonisation is required, not optional.** Units, currency
  base year, PPP vs market rates, and vintage must travel with the
  values — a joined table with `gdp_pc` from two sources in two units is
  worse than no join. Extend `common_indicators` into a source-aware
  catalogue with `unit`, `base_year`, `source`, `vintage`.
- **Do not reimplement any client.** Delegate to
  `owidR`/`eurostat`/`OECD`; our job is the spine, the reshape, the
  cache and the reconciliation.
- The existing `memoise` + on-disk WDI cache generalises: one cache
  layer keyed on `(source, indicator, countries, years)` with
  [`clear_wdi_cache()`](https://pursuitofdatascience.github.io/countryatlas/reference/clear_wdi_cache.md)
  becoming `clear_country_cache(source = NULL)` (keeping the old name as
  an alias).

**Deps** `Suggests: owidR`, `eurostat`, `OECD`, `comtradr`. **Effort** M
for the contract, S per adapter, M for
[`compare_sources()`](https://pursuitofdatascience.github.io/countryatlas/reference/compare_sources.md).
**Risk** low once the fixture-testing policy is fixed.

------------------------------------------------------------------------

## 4. Theme B — Time: historical states, boundaries and memberships **\[ledger §2.2/§2.6, partly deferred\]**

**Problem.** `historical_codes` +
[`dissolve_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/dissolve_country.md)
(shipped in 2.0.0) solve the *code* half: “USSR” resolves to 15
successors, and the `historical` flag in
[`check_country_match()`](https://pursuitofdatascience.github.io/countryatlas/reference/check_country_match.md)
catches countrycode silently mapping USSR → RUS. What is missing is the
*geometry and membership* half: a 1970 map still draws 2024 borders, and
`country_groups_tbl` is a single 2024-01-01 snapshot, so an EU panel
spanning 2015–2020 silently includes the UK throughout or excludes it
throughout — either way, wrongly.

**Features.**

``` r

# historical geometry, from CShapes 2.0
world_geometry(year = 1970)             # borders as they were
world_map(data, year = 1970)            # a historically correct choropleth
historical_geometry(year, source = "cshapes")
country_timeline("DEU")                 # existence spans, predecessors, successors

# point-in-time membership
in_group(x, "eu", as_of = 2016)         # UK in; as_of = 2021 -> out
country_groups("eu", as_of = 1995)
country_groups_history                  # bundled: group, iso3c, from, to, source

# panel-aware joins
country_join(data, geometry = "as_of_year")   # join each year to its own borders
audit_time_coverage(data)               # entities existing outside their span
```

**Design notes.**

- **`cshapes` 2.0 is the unlock.** It provides polygons with validity
  periods, political status, capital, and COW/GW identifiers for
  1886–2019 — including colonies and dependencies, which is what makes
  pre-1960 maps possible at all. Wire it as a `Suggests`-gated geometry
  backend alongside `maps` and `rnaturalearth`. Cite Schvitz et
  al. (2022).
- **The `iso3c` spine breaks before ~1970 and we must say so.** ISO 3166
  did not exist for most of CShapes’ span; colonies never had ISO codes.
  So historical work needs a **second spine**: COW/Gleditsch–Ward codes,
  which `countrycode` already converts and `states` 0.3.3 tracks over
  time. Proposal: `iso3c` remains the default key, `cowcode`/`gwcode`
  become supported alternate keys on
  [`country_join()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_join.md),
  and historical verbs *require* one — with a clear error, not a silent
  partial match. This is the single most important design decision in
  this theme.
- **`country_groups_history` is small, high-value curation** and should
  be built even if `cshapes` is never wired: EU accessions and Brexit,
  eurozone, OECD, NATO, WTO, Mercosur, GCC, ASEAN, AU/OAU. Every one is
  a documented date. The `as_of` argument then makes panel joins honest
  instead of approximately right. Keep the current snapshot behaviour as
  the default (`as_of = NULL`) so nothing breaks.
- **[`audit_time_coverage()`](https://pursuitofdatascience.github.io/countryatlas/reference/audit_time_coverage.md)
  is the diagnostic analogue of
  [`audit_coverage()`](https://pursuitofdatascience.github.io/countryatlas/reference/audit_coverage.md)**:
  it catches “South Sudan has 1995 data” and “Czechoslovakia has 2001
  data”, which are the errors that survive a successful join.
- Interaction with §9: sovereignty status is time-varying too
  (Timor-Leste 2002, Montenegro 2006, South Sudan 2011, Kosovo
  2008-and-contested).

**Deps** `Suggests: cshapes`, `states`. **Effort** M
(`country_groups_history`, `as_of`), L (historical geometry + the COW/GW
spine). **Risk** medium — the alternate-key work touches the join core,
so it needs its own test suite.

------------------------------------------------------------------------

## 5. Theme C — Honest maps I: projection and area

**Problem.** 2.0.0 expanded the projection set and added
[`globe_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/globe_map.md).
What it does not do is help the user *choose*, or show them what their
choice costs. “Area-honest maps” is in the package description; a
distortion diagnostic would make it demonstrable.

**Features.**

``` r

projection_info(crs)          # family, equal-area? conformal? compromise?, PROJ string
projection_compare(data, value, projections = c("robinson", "equal_earth",
                                                "winkel_tripel", "mercator"))
#> small multiples of the same choropleth under each projection

projection_distortion(crs, measure = c("areal", "angular", "max_scale"))
#> a grid of distortion values -> plottable surface
tissot_map(crs, spacing = 30)   # Tissot indicatrix ellipses on the graticule

world_map(..., projection = "equal_earth")   # documented recommended default
```

**Design notes.**

- **Equal Earth deserves to be the documented recommendation** for
  thematic world maps: it is equal-area (so a choropleth’s ink is
  proportional to ground area), looks close to Robinson, and is a
  one-word PROJ setting (`+proj=eqearth`). Šavrič, Patterson &
  Jenny (2019) is the citation. Do *not* silently change the current
  default — recommend it loudly in docs and
  [`theme_world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/theme_world_map.md)’s
  help, and consider flipping the default at the next major version with
  a NEWS note.
- **[`tissot_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/tissot_map.md)
  is the teaching feature.** Distortion ellipses are the standard
  cartographic device for showing what a projection does, they are
  computable from a PROJ transform of small circles, and no R package
  offers them as a one-liner. It makes the package’s honesty claim
  visible rather than asserted.
- **[`projection_compare()`](https://pursuitofdatascience.github.io/countryatlas/reference/projection_compare.md)
  is nearly free** —
  [`facet_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/facet_map.md)
  already does small multiples; this varies the CRS instead of the data.
  High teaching value, low effort.
- Keep the antimeridian discipline the 2.0.0 audit established (the
  `plate_carree` PROJ-string fix, the multi-part centroid fix): every
  new projection needs an antimeridian test and a
  `st_wrap_dateline()`/`s2` story, and Pacific-centred maps
  (`world_map(center = 150)`) are a natural extension that must be
  tested rather than assumed.
- Interrupted/orange-peel projections and polar projections round out
  the set; both are just PROJ strings plus careful graticule handling.

**Deps** `Suggests: sf`. **Effort** S (`projection_info`,
`projection_compare`), M (`projection_distortion`, `tissot_map`).
**Risk** low.

------------------------------------------------------------------------

## 6. Theme D — Honest maps II: classification, rates and the small-number problem

**Problem.** The 2.0.0 audit already found and fixed a real
classification bug (quantile/Jenks breaks were vertex-weighted rather
than country-weighted — a genuine wrong-answer defect). That fix makes
the *computation* correct; the *choice* is still unguided, and the
perception literature says the choice changes conclusions.

**Features.**

``` r

classify_compare(data, value, methods = c("quantile", "jenks", "equal",
                                          "pretty", "sd", "headtails"),
                 n = 5)
#> the same map under each classification, plus a break table and
#> a class-balance summary (how many countries per class)

world_map(..., style = "quantile", classification_report = TRUE)
#> attaches breaks + method + n + the count per class to the plot object

rate_check(data, numerator, denominator, min_denominator = NULL)
#> flags rates computed over tiny denominators (the small-number problem)
smooth_rates(data, numerator, denominator, method = c("eb", "none"))
#> empirical-Bayes shrinkage toward the global rate for small denominators
```

**Design notes.**

- **State the evidence, don’t just offer options.** Brewer & Pickle’s
  56-subject study found quantiles best and Jenks materially worse for
  general choropleth reading — a result that contradicts the common GIS
  default. The docs should say this plainly, with the citation, and
  [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md)’s
  help should explain *when* Jenks is nonetheless right (strongly
  clustered distributions where quantiles would split a natural group).
- **`classification_report = TRUE` is a small honesty feature with real
  teeth**: a map whose top class contains one country and whose bottom
  contains ninety is a misleading map, and the count-per-class table
  says so immediately.
- **[`rate_check()`](https://pursuitofdatascience.github.io/countryatlas/reference/rate_check.md)/[`smooth_rates()`](https://pursuitofdatascience.github.io/countryatlas/reference/smooth_rates.md)
  address the problem Roth et al. named.** Country-level data has this
  in an extreme form: Tuvalu (~11k people) and China sit in the same
  choropleth, and any per-capita or per-100k rate lets the smallest
  denominators dominate the colour scale. Empirical-Bayes shrinkage is
  standard in disease mapping, is a dozen lines of code, and is a
  defensible alternative to silently plotting noise.
  [`per_capita()`](https://pursuitofdatascience.github.io/countryatlas/reference/per_capita.md)
  (shipped) is where users hit this, so cross-reference it from there.
- Pair with §8: value-by-alpha and cartograms are the *visual* answers
  to the same problem; shrinkage is the *statistical* one. Documenting
  all three together, with guidance on which to use when, would be a
  genuinely useful vignette (“Rates, denominators and honest
  choropleths”).

**Deps** `Suggests: classInt` (already). **Effort** M. **Risk** low.

------------------------------------------------------------------------

## 7. Theme E — Honest maps III: uncertainty and missingness

**Problem.** WDI data is patchy and partly modelled, and
[`audit_coverage()`](https://pursuitofdatascience.github.io/countryatlas/reference/audit_coverage.md)
reports coverage as a table — but the *map* shows a confident colour for
a modelled estimate and an ambiguous grey for a missing value. Neither
is honest, and the second is actively confusing (grey reads as “low” to
many readers).

**Features.**

``` r

world_map(data, value, uncertainty = se, palette = "vsup")
#> Value-Suppressing Uncertainty Palette: colour range narrows as uncertainty
#> rises, with the matching 2-D legend

world_map(..., na_style = c("grey", "hatched", "outline", "omit"),
          na_label = "No data")
coverage_map(data, value)          # map of data availability itself
world_map(..., footnote = "auto")  # auto-generated "n = 174 of 195; missing: …"
```

**Design notes.**

- **VSUPs are the right primitive and are implementable in ggplot2.**
  Correll, Moritz & Heer’s construction is a discretised 2-D palette
  (value × uncertainty) where the value range contracts as uncertainty
  grows; their crowdsourced study found readers weighted uncertainty
  more heavily than with an ordinary bivariate map. The package already
  ships
  [`bivariate_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/bivariate_map.md) +
  `biscale`, so the machinery for 2-D legends exists — a VSUP is a
  differently-constructed 2-D palette plus a differently-shaped
  (trapezoidal) legend. This would be the first VSUP implementation in R
  that I am aware of, which makes it both a distinctive feature and a
  natural talking point for the package.
- **Hatched NA via `ggpattern` is the small, high-impact version.** Grey
  is ambiguous; diagonal hatching is unmistakably “no data” and survives
  greyscale printing. `Suggests: ggpattern` is already available.
- **`footnote = "auto"` is unglamorous and important.** Most published
  choropleths do not say how many countries are missing. Generating that
  string from the data means the map cannot quietly overstate its
  coverage.
- Where does uncertainty *come from*? Mostly the user (a standard error
  column, a model output). But two package-native sources exist and are
  worth exposing: WDI’s own footnote/estimate flags where the API
  provides them, and interpolation done by a future
  [`interpolate_missing()`](https://pursuitofdatascience.github.io/countryatlas/reference/interpolate_missing.md)
  (ledger §2.7) — anything the package imputes must be flagged as
  imputed, not returned as data. Make that a hard rule.

**Deps** `Suggests: ggpattern`, `biscale` (already). **Effort** M
(`na_style`, `coverage_map`, footnotes), L (VSUP + legend). **Risk**
medium on the VSUP legend (custom guide construction in ggplot2 is
fiddly), low otherwise.

------------------------------------------------------------------------

## 8. Theme F — Cartograms and area-equalising alternatives

**Problem.**
[`cartogram_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/cartogram_map.md)
and
[`dorling_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/dorling_map.md)
ship, built on `cartogram` (Dougenik/Dorling/non-contiguous). The fast
modern algorithm and the non-distorting alternative are both missing.

**Features.**

``` r

cartogram_map(data, value, type = c("contiguous", "dorling", "ncont", "flow"))
#> "flow" = cartogramR's Gastner-Seguy-More implementation (seconds, not minutes)

value_by_alpha_map(data, value, equalize = population, palette = ...)
#> Roth/Woodruff/Johnson: alpha encodes the equalising variable, geometry intact

gridded_cartogram(data, value, cells = 1000)   # "one square per N people"
cartogram_diagnostics(cg)   # area error, shape distortion, convergence
```

**Design notes.**

- **`cartogramR` should be added and is a strict improvement** for
  contiguous cartograms: the flow-based algorithm (Gastner, Seguy &
  More, *PNAS* 2018) is the current state of the art and orders of
  magnitude faster than diffusion-based approaches. Keep `cartogram` for
  Dorling/non-contiguous, add `cartogramR` for contiguous, and let
  `type =` route.
- **[`value_by_alpha_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/value_by_alpha_map.md)
  is the conceptually important one.** It solves the small-number
  problem (§6) *without* distorting geometry, which is the main
  complaint against cartograms — Roth et al. designed it precisely as
  that alternative. It is also easy: a
  [`bivariate_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/bivariate_map.md)
  variant where one channel is alpha over a neutral background. High
  value-to-effort ratio, and it pairs with §6’s
  [`rate_check()`](https://pursuitofdatascience.github.io/countryatlas/reference/rate_check.md)
  in the same vignette.
- **[`cartogram_diagnostics()`](https://pursuitofdatascience.github.io/countryatlas/reference/cartogram_diagnostics.md)
  matters because cartograms fail quietly.** An under-converged
  cartogram looks plausible while still misrepresenting areas; reporting
  the residual area error per country makes that visible. Same spirit as
  §6’s classification report.
- Colour and legend defaults deserve an audit here too: cartogram +
  rainbow is a common and bad combination, and the package’s palette
  presets should be the documented path.

**Deps** `Suggests: cartogramR`. **Effort** S (`flow` routing,
`value_by_alpha_map`), M (gridded, diagnostics). **Risk** low.

------------------------------------------------------------------------

## 9. Theme G — Disputed territories, sovereignty and status **\[ledger §2.6, deferred\]**

**Problem.** The ledger deferred this as needing “data curation”. It is
the most consequential deferral in the file: right now the answer to
“does this map show Taiwan as part of China? is Kosovo a country? where
is the Kashmir line?” is *whatever the backend happened to do*, and it
is invisible to the user. For a package whose thesis is honest maps, an
undocumented political default is the sharpest inconsistency.

**Features.**

``` r

disputed_territories        # bundled: territory, claimants, iso3c candidates,
                            # de facto controller, recognition count, source
country_meta$status         # sovereign | dependency | disputed | breakaway | dissolved

world_map(..., disputes = c("de_facto", "de_jure", "hatched", "omit", "separate"))
#> "hatched"  = drawn with a pattern and excluded from the colour scale
#> "separate" = de jure claim lines drawn as an auxiliary layer (Natural Earth style)

dispute_policy()            # print the policy this build applies, with citations
check_dispute_coverage(data)  # which disputed entities your data does/doesn't have
```

**Design notes.**

- **Adopt and document Natural Earth’s approach rather than inventing
  one.** Natural Earth draws de facto boundaries by default and supplies
  de jure claim lines as a separate layer. That is a defensible,
  published, citable policy; the package’s contribution is to make it
  **explicit, switchable and visible** —
  [`dispute_policy()`](https://pursuitofdatascience.github.io/countryatlas/reference/dispute_policy.md)
  printing “this map uses de facto boundaries from Natural Earth 5.x;
  Western Sahara shown separately; Taiwan coded TWN” is the honest
  artefact.
- **`hatched` is the option most users actually want** and no R mapping
  package offers it: a territory that is present in the geometry but
  excluded from the colour scale and drawn with a pattern, so the map
  neither erases it nor fabricates a value for it. `ggpattern` (§7)
  makes it easy.
- **`disputed_territories` is small, tractable curation** — Taiwan,
  Kosovo, Palestine, Western Sahara, Northern Cyprus, Crimea,
  Abkhazia/South Ossetia, Transnistria, Somaliland, Kashmir/Aksai Chin,
  Nagorno-Karabakh, the Elemi Triangle. Roughly a dozen rows with
  sources. The ~188 figure in the EU guide is the full universe; a
  curated, documented, clearly-scoped subset is more useful than an
  exhaustive one, provided the scope is stated.
- **The package must not take a side; it must make the side the user
  takes visible.** Frame every option as a *choice with consequences*,
  note that official publications may be constrained (per the EU guide),
  never editorialise in the docs, and default to the status quo so no
  existing map changes silently.
- `status` in `country_meta` is separately useful:
  [`audit_coverage()`](https://pursuitofdatascience.github.io/countryatlas/reference/audit_coverage.md)
  and
  [`check_country_match()`](https://pursuitofdatascience.github.io/countryatlas/reference/check_country_match.md)
  can then explain “this is a dependency, not a sovereign state, which
  is why WDI has no row for it” — a frequent and currently mysterious
  failure.

**Deps** `Suggests: ggpattern`. **Effort** M (curation + plumbing).
**Risk** **this is the highest-sensitivity feature in the document.**
The mitigation is mechanical: no defaults change, every claim is
sourced, the policy is printable, and the docs describe rather than
advocate.

------------------------------------------------------------------------

## 10. Theme H — Subnational geography **\[ledger §2.3, deferred\]**

**Problem.** The spine stops at the country. Users with regional data
(EU NUTS, US states, Indian states, Brazilian municipalities) have
nowhere to go, and the reconciliation problem is *worse* one level down:
subnational codes get renumbered between vintages.

**Features.**

``` r

world_geometry(level = "admin1", countries = "BRA")
subnational_map(data, value, level = "admin1", country = "BRA")
standardize_subnational(x, country, level = "admin1")   # -> ISO 3166-2
nuts_geometry(level = 2, year = 2021)                   # giscoR
subnational_meta                                        # ISO 3166-2 reference
```

**Design notes.**

- **The ISO 3166-2 spine is the honest generalisation** of what the
  package already does, and it is the right key: it is the same *kind*
  of standard, with the same *kind* of reconciliation problem.
- **`regions` 0.1.8 exists for exactly the vintage problem** (NUTS 2013
  vs 2016 vs 2021 recoding) and should be delegated to rather than
  reimplemented. Pair with `giscoR` for EU geometry and `geodata`/GADM
  for the rest.
- **Scope discipline is essential.** “Subnational for the whole world”
  is a data project without an end. Proposal: support (a) ISO 3166-2
  codes as a reconciliation target everywhere, (b) admin1 geometry via
  [`rnaturalearth::ne_states()`](https://docs.ropensci.org/rnaturalearth/reference/ne_states.html)
  for any country, (c) NUTS as a first-class special case via `giscoR`.
  Explicitly do not attempt admin2+, and say so.
- Licensing needs checking per source (GADM’s terms are notably
  restrictive for redistribution — delegate to `geodata`, never bundle).
- Everything here is `Suggests`-gated and none of it can be bundled, so
  the offline-example discipline needs a story: a tiny synthetic admin1
  fixture for tests, and `\donttest{}` for the real examples.

**Deps** `Suggests: giscoR`, `regions`, `geodata`, `rnaturalearth`
(already). **Effort** L. **Risk** medium — mostly scope creep; the
mitigation is the explicit boundary above.

------------------------------------------------------------------------

## 11. Theme I — Spatial statistics done properly

**Problem.**
[`morans_i()`](https://pursuitofdatascience.github.io/countryatlas/reference/morans_i.md)
works and its behaviour is documented — but its single hard-wired weight
scheme (land-border contiguity, row-standardised) **excludes every
country without a land border in the data**. That is Japan, the UK,
Australia, Indonesia, Madagascar, New Zealand, the Philippines, Iceland,
Cuba, Sri Lanka and every small island state. For a *global* analysis
that is a large and non-random omission, and it is invisible in the
returned `n`.

**Features.**

``` r

country_weights(type = c("contiguity", "knn", "distance", "custom"),
                k = 5, cutoff_km = NULL, scale = "small")
#> a reusable weights object; islands get neighbours under knn/distance

morans_i(data, value, weights = country_weights("knn", k = 5))
morans_i(data, value)   # unchanged default, plus n_excluded + a note

local_morans(data, value, weights = ...)     # LISA + cluster categories
lisa_map(data, value, weights = ...)         # the HH/LL/HL/LH cluster map
gearys_c(...); getis_ord(...)
spatial_lag(data, value, weights = ...)      # neighbour-average as a column
```

**Design notes.**

- **Report the exclusion, always.** Whatever the default,
  [`morans_i()`](https://pursuitofdatascience.github.io/countryatlas/reference/morans_i.md)
  should return `n_excluded` and name the excluded countries (or the
  first few) so a user cannot publish a “global” Moran’s I that quietly
  omitted 40 countries. This is a small change with real correctness
  value and it does not alter any computation.
- **[`country_weights()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_weights.md)
  is the right abstraction** and it generalises beyond autocorrelation:
  `k`-nearest by centroid (islands get neighbours), distance-band, and —
  distinctively for this package — **non-geographic weights**: trade
  volume (`comtradr`, §3/§12), migration flows, colonial or language
  ties. “Countries near each other in *trade* space” is often the
  relevant adjacency for economic questions, and having the same API for
  it is a genuinely novel offering.
- **LISA was deferred for wanting map integration — and the map
  integration now exists.**
  [`lisa_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/lisa_map.md)
  is
  [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md)
  with a categorical HH/LL/HL/LH fill and a significance mask; the
  deferral reason has expired.
- Delegate where sensible: `sfdep` gives tidy LISA output, `rgeoda`
  gives the GeoDa variants. Keep the dependency-free dense path for the
  default 200×200 case (it is genuinely trivial at that size) and gate
  the rest.
- Cite Anselin (1995) for LISA and Moran (1950); add both to the
  citation set so
  [`morans_i()`](https://pursuitofdatascience.github.io/countryatlas/reference/morans_i.md)/[`local_morans()`](https://pursuitofdatascience.github.io/countryatlas/reference/local_morans.md)
  are properly attributed.

**Deps** `Suggests: sfdep` or `spdep` (optional). **Effort** M. **Risk**
low.

------------------------------------------------------------------------

## 12. Theme J — Flows, networks and relational data

**Problem.**
[`flow_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/flow_map.md)
draws flows the user supplies. The package has no way to *get* flow
data, and no relational vocabulary beyond
[`country_borders()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_borders.md).

**Features.**

``` r

fetch_comtrade(...)                    # trade flows on the ISO spine (§3)
flow_map(..., geodesic = TRUE)         # great-circle arcs, antimeridian-safe
flow_matrix(data, origin, destination, value)     # tidy <-> OD matrix
od_map(data, ...)                      # origin-destination small multiples
country_network(data, ...)             # igraph/tidygraph on the spine
flow_map(..., bundle = TRUE)           # edge bundling for dense flows
```

**Design notes.**

- **Straight-line flows on a projected world map are wrong** in the same
  way Mercator area is wrong: the shortest path between Tokyo and Los
  Angeles is not a straight line on Robinson. `geodesic = TRUE` (via
  `s2`/[`sf::st_segmentize`](https://r-spatial.github.io/sf/reference/geos_unary.html))
  should arguably become the default — it is the “honest maps” principle
  applied to lines. The 2.0.0 audit already fixed the analogous bug for
  bubbles (projected metres on a degrees map), so the pattern is
  established.
- **OD maps** (Wood, Dykes & Slingsby) are the standard answer to “my
  flow map is spaghetti”, and small-multiple machinery already exists in
  [`facet_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/facet_map.md).
- [`country_network()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_network.md)
  returning `igraph`/`tidygraph` (Suggests) makes the adjacency and
  trade graphs available to the whole network-analysis ecosystem for
  free — centrality, communities, shortest paths between countries.
- Trade data is large; the §3 cache layer is a prerequisite, not an
  optional extra.

**Deps** `Suggests: comtradr`, `igraph`/`tidygraph`, `s2`. **Effort** M.
**Risk** low.

------------------------------------------------------------------------

## 13. Theme K — Renderers, interactivity and the ggsql bridge

**Features.**

``` r

# 1. fix the version mismatch (see the finding at the top)
as_ggsql_source(...)   # guarded: requires ggsql >= 0.4.1, clear error otherwise

# 2. broaden the ggsql surface as its spatial API stabilises
world_query(..., layer = c("choropleth", "bubble", "binned"), facet = , scale = )

# 3. a modern interactive engine
interactive_map(data, value, engine = c("leaflet", "ggiraph", "plotly",
                                        "ggsql", "mapgl"))
globe_map(..., interactive = TRUE)     # WebGL globe via mapgl

# 4. tmap as an alternative static/interactive backend
world_map(..., engine = "tmap")
```

**Design notes.**

- **The version guard is not optional.** Right now a CRAN user
  installing the suggested `ggsql` gets 0.3.3 against a bridge
  documented for 0.4.1+. Guard with
  [`packageVersion()`](https://rdrr.io/r/utils/packageDescription.html),
  say exactly what is needed and where to get it, and add a
  `skip_if_not_installed("ggsql", "0.4.1")` to the tests. Re-check at
  each release; when CRAN catches up, the guard becomes a no-op.
- **`mapgl` is the interactive upgrade worth making.** MapLibre/Mapbox
  GL gives vector tiles, smooth zoom, real 3D and a genuine interactive
  globe — the last of which turns
  [`globe_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/globe_map.md)/[`spin_globe()`](https://pursuitofdatascience.github.io/countryatlas/reference/spin_globe.md)
  from a static novelty into a usable tool. `leaflet` stays for
  compatibility and simplicity.
- **Consider whether `tmap` should be a backend rather than a
  competitor.** `tmap` 4.x is mature, handles legends and layouts well,
  and supports static + interactive from one specification. An
  `engine = "tmap"` path would reduce the amount of rendering the
  package maintains. Counter-argument: the package’s identity is
  ggplot2-native. Worth an explicit decision (§18) rather than drifting.
- `geoarrow`/`arrow` are on CRAN and would make the ggsql/DuckDB path
  faster and the geometry cache cheaper (§16).

**Deps** `Suggests: mapgl`, possibly `tmap`, `geoarrow`. **Effort** S
(guard), M (mapgl, ggsql breadth), L (tmap backend). **Risk** low,
except the tmap decision, which is strategic.

------------------------------------------------------------------------

## 14. Theme L — Reporting, provenance and reproducibility **\[ledger §2.7\]**

**Problem.** A countryatlas map is the end of an analysis and the start
of a question: *which* WDI vintage, *which* geometry, *which*
projection, *which* dispute policy, *how many* countries? None of that
travels with the output.

**Features.**

``` r

country_factsheet("BRA", indicators = NULL)     # one-country summary
world_table(data, top_n = 20, engine = "gt")    # publication-ready table
map_provenance(plot_or_data)
#> countryatlas version, WDI/source vintage + fetch date, snapshot year,
#> geometry backend + Natural Earth scale, projection, dispute policy,
#> classification method + breaks, n countries, n missing
world_map(..., caption = "auto")                # provenance as a plot caption
```

**Design notes.**

- **[`map_provenance()`](https://pursuitofdatascience.github.io/countryatlas/reference/map_provenance.md)
  is the reproducibility feature and it is nearly free**: every input it
  reports is already known at plot time. Printed into a caption or a
  methods section it answers the questions a reviewer asks first, and it
  is a natural pairing with the §6 classification report and the §7
  coverage footnote.
- `inst/CITATION` should credit the package **and** `countrycode`
  (Arel-Bundock et al. 2018), the World Bank, Natural Earth, and — once
  wired — CShapes (Schvitz et al. 2022). Users are obliged to cite the
  data; making `citation("countryatlas")` produce the full set is a
  service and good attribution hygiene.
- [`country_factsheet()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_factsheet.md)/[`world_table()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_table.md)
  are the “last mile” for the non-map audience and lean on `gt`
  (Suggests) with a plain-tibble fallback.
- **Accessibility pass**, worth doing once across all map verbs: verify
  the palette presets under the three common colour-vision deficiencies
  (`colorspace` can simulate), ensure NA is distinguishable without
  colour (§7 hatching), check text contrast in
  [`theme_world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/theme_world_map.md),
  and add alt text to every vignette figure.

**Deps** `Suggests: gt`, `colorspace`. **Effort** M. **Risk** low.

------------------------------------------------------------------------

## 15. Theme M — Analysis helpers

The comparative-development toolkit shipped in 2.0.0
([`growth_rate()`](https://pursuitofdatascience.github.io/countryatlas/reference/growth_rate.md),
[`index_to()`](https://pursuitofdatascience.github.io/countryatlas/reference/index_to.md),
[`share_of_world()`](https://pursuitofdatascience.github.io/countryatlas/reference/share_of_world.md),
[`beta_convergence()`](https://pursuitofdatascience.github.io/countryatlas/reference/beta_convergence.md),
[`sigma_convergence()`](https://pursuitofdatascience.github.io/countryatlas/reference/sigma_convergence.md),
[`gini()`](https://pursuitofdatascience.github.io/countryatlas/reference/gini.md),
[`theil()`](https://pursuitofdatascience.github.io/countryatlas/reference/theil.md),
[`lag_by_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/lag_by_country.md),
[`diff_by_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/lag_by_country.md),
[`correlate_indicators()`](https://pursuitofdatascience.github.io/countryatlas/reference/correlate_indicators.md))
covers most of what the literature routinely needs. The remaining gaps
are the ones that prevent *silent unit errors* — the same class of
mistake the ISO spine exists to prevent, one level up:

``` r

deflate(data, value, base_year, deflator = "gdp")   # constant vs current prices
to_ppp(data, value, year); to_usd(data, value, from_currency)
aggregate_regions(data, value, weight = population) # population-weighted roll-ups
interpolate_missing(data, value, method = c("linear", "locf"), max_gap = 2)
convergence_club(data, value)                       # club convergence / grouping
```

**Design notes.**

- **[`deflate()`](https://pursuitofdatascience.github.io/countryatlas/reference/deflate.md)/[`to_ppp()`](https://pursuitofdatascience.github.io/countryatlas/reference/to_ppp.md)
  are the highest-value items here.** Comparing nominal GDP across
  years, or market-rate GDP across countries, is a mistake that produces
  plausible-looking wrong answers — exactly the failure mode the package
  was built to eliminate for country names. The deflator/PPP series come
  from WDI, so this is a join plus arithmetic plus very careful
  documentation of which convention was applied.
- **Population-weighted aggregation is a correctness issue, not a
  nicety.** An unweighted regional mean says “the average *country* in
  Sub-Saharan Africa”, which is almost never the intended quantity;
  users read it as “the average *person*”.
  [`aggregate_regions()`](https://pursuitofdatascience.github.io/countryatlas/reference/aggregate_regions.md)
  should gain `weight =` and its help should spell out the distinction.
  Note that
  [`gini()`](https://pursuitofdatascience.github.io/countryatlas/reference/gini.md)/[`theil()`](https://pursuitofdatascience.github.io/countryatlas/reference/theil.md)
  already support weights — the inconsistency is worth closing.
- **Anything imputed must be flagged.**
  [`interpolate_missing()`](https://pursuitofdatascience.github.io/countryatlas/reference/interpolate_missing.md)
  must add an `.imputed` logical column, and §7’s uncertainty/NA
  machinery must treat imputed values differently from observed ones.
  Silently interpolating into a map is the single easiest way for this
  package to mislead someone.

**Deps** none. **Effort** M. **Risk** low.

------------------------------------------------------------------------

## 16. Theme N — Architecture, performance, infrastructure

- **One cache layer, many sources.** Generalise the memoised WDI cache
  into a provider-agnostic cache keyed on
  `(source, indicator, countries, years)` with a version stamp, plus
  `cache_geometry(scale)` (ledger §2.3) so the `sf` backend has an
  offline story too. Parquet/`arrow` is the natural on-disk format and
  both are on CRAN.
- **Bundled snapshot policy.** `world_snapshot` is at 2024 and is what
  makes every example and test run offline — the single most valuable
  piece of infrastructure in the package. Formalise it: a `data-raw/`
  refresh script (it exists), a documented cadence, a CI job that
  *checks* the snapshot still builds against the live API without
  committing the result, and a stated guarantee that examples never
  touch the network.
- **Geometry performance.**
  [`simplify_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/simplify_geometry.md)
  exists; add scale-aware defaults (110m for world thematic maps,
  50m/10m on request), cache simplified results, and consider `s2`-based
  area/centroid computation so “area-honest” claims are geodesically
  true rather than projection-dependent.
- **Benchmark
  [`check_country_match()`](https://pursuitofdatascience.github.io/countryatlas/reference/check_country_match.md)/[`repair_country_names()`](https://pursuitofdatascience.github.io/countryatlas/reference/repair_country_names.md)
  against `countries` 1.2.4**, a newer CRAN package attacking the same
  fuzzy-matching problem. Either we are better (say so, with a
  reproducible comparison in `data-raw/`), or we should delegate. Both
  outcomes are wins; not knowing is the only bad option.
- **Testing.** `vdiffr` snapshots for the map verbs (there are now ~14
  of them and no visual regression net — and the 2.0.0 audit found three
  separate *visual* correctness bugs, which is exactly what snapshots
  catch); a `covr` badge (`codecov.yml` is present); a scheduled CI job
  that installs all `Suggests` and runs the live-API tests so upstream
  breakage surfaces here rather than on CRAN; `skip_if_offline()`
  discipline everywhere.
- **`Suggests` weight.** Already 26 packages; this document would add
  ~12 more (`owidR`, `eurostat`, `OECD`, `comtradr`, `cshapes`,
  `states`, `giscoR`, `regions`, `geodata`, `cartogramR`, `mapgl`,
  `sfdep`). That is heavy but defensible for a package whose whole
  design is “light core, optional everything” — provided (a) §3’s
  registration mechanism absorbs the long tail of data sources instead
  of `Suggests` doing it, and (b) the README gains the single “Optional
  features” table the ledger already promised.
- **Deprecations.** The `gdp_per_capita_2015` shim and the `wdj_*`
  naming holdovers (`wdj_overrides`) are the visible residue of the
  `worlddatajoin` → `countryatlas` rename; finish the cycle.

------------------------------------------------------------------------

## 17. Prioritisation

**Wave 1 — correctness, honesty and small wins.** Highest value per unit
of effort; nothing here needs new data curation. 1. **ggsql version
guard** (§13) — a live mismatch between the shipped bridge and CRAN’s
ggsql. 2.
**[`morans_i()`](https://pursuitofdatascience.github.io/countryatlas/reference/morans_i.md)
reports `n_excluded`** (§11) — a silent-omission fix. 3.
**`na_style = "hatched"` +
[`coverage_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/coverage_map.md) +
`footnote = "auto"`** (§7). 4. **`classification_report` +
[`classify_compare()`](https://pursuitofdatascience.github.io/countryatlas/reference/classify_compare.md)**
(§6), with the Brewer & Pickle evidence in the docs. 5.
**[`value_by_alpha_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/value_by_alpha_map.md)**
and **`cartogramR` as `type = "flow"`** (§8). 6.
**[`projection_compare()`](https://pursuitofdatascience.github.io/countryatlas/reference/projection_compare.md) +
[`projection_info()`](https://pursuitofdatascience.github.io/countryatlas/reference/projection_info.md)**,
and Equal Earth documented as the recommendation (§5). 7.
[`map_provenance()`](https://pursuitofdatascience.github.io/countryatlas/reference/map_provenance.md) +
`inst/CITATION` (§14); `vdiffr` snapshots for the map verbs (§16).

**Wave 2 — the data-source contract.**
[`register_country_source()`](https://pursuitofdatascience.github.io/countryatlas/reference/register_country_source.md) +
[`fetch_indicator()`](https://pursuitofdatascience.github.io/countryatlas/reference/fetch_indicator.md)/[`add_indicator()`](https://pursuitofdatascience.github.io/countryatlas/reference/add_indicator.md) +
the OWID/Eurostat/OECD adapters +
[`compare_sources()`](https://pursuitofdatascience.github.io/countryatlas/reference/compare_sources.md) +
the generalised cache, with recorded-fixture tests (§3, §16). This is
the deferral that has been open longest and the design above removes its
blocker.

**Wave 3 — time.** `country_groups_history` + `as_of` (§4, small and
entirely offline), then
[`audit_time_coverage()`](https://pursuitofdatascience.github.io/countryatlas/reference/audit_time_coverage.md),
then the COW/GW alternate spine and `cshapes` historical geometry (§4).
The last is the biggest single new capability in this document.

**Wave 4 — honesty, continued.** `disputed_territories` + `status` +
`world_map(disputes =)` +
[`dispute_policy()`](https://pursuitofdatascience.github.io/countryatlas/reference/dispute_policy.md)
(§9);
[`rate_check()`](https://pursuitofdatascience.github.io/countryatlas/reference/rate_check.md)/
[`smooth_rates()`](https://pursuitofdatascience.github.io/countryatlas/reference/smooth_rates.md)
(§6); VSUP palettes and legend (§7);
[`deflate()`](https://pursuitofdatascience.github.io/countryatlas/reference/deflate.md)/[`to_ppp()`](https://pursuitofdatascience.github.io/countryatlas/reference/to_ppp.md)
and weighted
[`aggregate_regions()`](https://pursuitofdatascience.github.io/countryatlas/reference/aggregate_regions.md)
(§15); the accessibility pass (§14).

**Wave 5 — reach.**
[`country_weights()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_weights.md) +
LISA/[`lisa_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/lisa_map.md) +
non-geographic weights (§11); geodesic flows, OD maps,
[`country_network()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_network.md),
Comtrade (§12); `mapgl` interactive globe (§13);
[`country_factsheet()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_factsheet.md)/[`world_table()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_table.md)
(§14).

**Wave 6 — subnational.** ISO 3166-2 reconciliation, admin1 geometry,
NUTS via `giscoR`/`regions` (§10). Last because it is the largest scope
risk and benefits from Waves 2–3’s caching and time machinery.

**Explicitly not planned.** Becoming a general GIS package (`sf`/`terra`
own that); implementing projections, cartogram algorithms or
spatial-statistics engines from scratch; bundling any large geometry or
restrictively-licensed data (GADM); admin2 and below; a Shiny app as a
hard dependency; taking a position on any territorial dispute.

------------------------------------------------------------------------

## 18. Open questions and decisions needed

1.  **Does the historical work get a second spine?** COW/Gleditsch–Ward
    codes are required for pre-1970 and for colonies; ISO 3166 cannot
    express them. Adding an alternate key to
    [`country_join()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_join.md)
    is the right move but touches the join core. Decide before building
    §4.
2.  **`tmap` as a backend, or stay ggplot2-only?** (§13.) Strategic: it
    would cut rendering maintenance but dilute the package’s identity.
    Leaning ggplot2-only, with `mapgl` for interactivity.
3.  **Should Equal Earth become the default projection?** It is the
    honest choice and would change every existing map. Proposal:
    document and recommend now, flip at the next major version with a
    prominent NEWS entry.
4.  **`Suggests` versus registration for data sources.** (§3, §16.)
    Registration scales and reaches non-CRAN sources; `Suggests` is more
    discoverable. Leaning: registration as the mechanism, three or four
    built-in adapters for discoverability.
5.  **How much dispute curation, and reviewed by whom?** (§9.) A dozen
    documented rows or the full ~188? Leaning: a documented,
    explicitly-scoped subset with sources — and the scope statement
    matters more than the row count.
6.  **Do we ever impute?** (§7, §15.) If
    [`interpolate_missing()`](https://pursuitofdatascience.github.io/countryatlas/reference/interpolate_missing.md)
    ships, the `.imputed` flag must be non-optional and the map verbs
    must honour it. If we cannot guarantee that, do not ship it.
7.  **Snapshot cadence and size.** Refreshing `world_snapshot` yearly
    keeps examples current but churns the `.rda` and the package size.
    Yearly at release time, or only when coverage materially improves?
8.  **Is
    [`check_country_match()`](https://pursuitofdatascience.github.io/countryatlas/reference/check_country_match.md)
    still the best available matcher?** (§16.) Benchmark against
    `countries` 1.2.4 and act on the result either way.

------------------------------------------------------------------------

## 19. References

**Projections and cartography**

- Šavrič B, Patterson T, Jenny B (2019). The Equal Earth map projection.
  *International Journal of Geographical Information Science* 33(3):
  454–465. <https://doi.org/10.1080/13658816.2018.1504949> · PROJ
  implementation
  <https://proj.org/en/stable/operations/projections/eqearth.html> ·
  <https://equal-earth.com/equal-earth-projection.html>
- Natural Earth — Disputed boundaries policy (de facto default, de jure
  claim lines as an auxiliary layer).
  <https://www.naturalearthdata.com/about/disputed-boundaries-policy/> ·
  Admin 0 breakaway/disputed areas
  <https://www.naturalearthdata.com/downloads/50m-cultural-vectors/50m-admin-0-breakaway-disputed-areas/>
- European Commission, *Data Visualisation Guide* — Disputed
  territories.
  <https://data.europa.eu/apps/data-visualisation-guide/disputed-territories>

**Choropleth classification, rates and perception**

- Brewer CA, Pickle L (2002). Evaluation of Methods for Classifying
  Epidemiological Data on Choropleth Maps in Series. *Annals of the
  Association of American Geographers* 92(4): 662–681.
- Roth RE, Woodruff AW, Johnson ZF (2010). Value-by-alpha Maps: An
  Alternative Technique to the Cartogram. *The Cartographic Journal*
  47(2): 130–140. <https://doi.org/10.1179/000870409X12488753453372> ·
  <https://pmc.ncbi.nlm.nih.gov/articles/PMC3173776/>
- Harrower M, Brewer CA (2003). ColorBrewer.org: An Online Tool for
  Selecting Colour Schemes for Maps. *The Cartographic Journal* 40(1):
  27–37.

**Uncertainty visualization**

- Correll M, Moritz D, Heer J (2018). Value-Suppressing Uncertainty
  Palettes. *CHI 2018*. <https://doi.org/10.1145/3173574.3174216> ·
  <https://idl.uw.edu/papers/uncertainty-palettes> · reference
  implementation <https://uwdata.github.io/vsup/>

**Cartograms**

- Gastner MT, Seguy V, More P (2018). Fast flow-based algorithm for
  creating density-equalizing map projections. *PNAS* 115(10):
  E2156–E2164. <https://doi.org/10.1073/pnas.1712674115> · `cartogramR`
  <https://cran.r-project.org/package=cartogramR>
- Gastner MT, Newman MEJ (2004). Diffusion-based method for producing
  density-equalizing maps. *PNAS* 101(20): 7499–7504.
- Dorling D (1996). *Area Cartograms: Their Use and Creation*. CATMOG
  59.

**Historical states and boundaries**

- Schvitz G, Girardin L, Rüegger S, Weidmann NB, Cederman L-E, Gleditsch
  KS (2022). Mapping the International System, 1886–2019: The CShapes
  2.0 Dataset. *Journal of Conflict Resolution* 66(1): 144–161.
  <https://doi.org/10.1177/00220027211013563> · data
  <https://icr.ethz.ch/data/cshapes/> · R package
  <https://cran.r-project.org/package=cshapes>
- Gleditsch KS, Ward MD (1999). A revised list of independent states
  since the Congress of Vienna. *International Interactions*. — the GW
  code system; R package `states`
  <https://cran.r-project.org/package=states>

**Country codes and reconciliation**

- Arel-Bundock V, Enevoldsen N, Yetman CJ (2018). countrycode: An R
  package to convert country names and country codes. *Journal of Open
  Source Software* 3(28): 848. <https://doi.org/10.21105/joss.00848>
- ISO 3166 (country and subdivision codes); `ISOcodes`
  <https://cran.r-project.org/package=ISOcodes>; `countries`
  <https://cran.r-project.org/package=countries>

**Spatial statistics**

- Moran PAP (1950). Notes on continuous stochastic phenomena.
  *Biometrika* 37(1/2): 17–23.
- Anselin L (1995). Local Indicators of Spatial Association — LISA.
  *Geographical Analysis* 27(2): 93–115.
- `spdep` <https://cran.r-project.org/package=spdep> · `sfdep`
  <https://cran.r-project.org/package=sfdep> · `rgeoda`
  <https://cran.r-project.org/package=rgeoda>

**Flow and OD mapping**

- Wood J, Dykes J, Slingsby A (2010). Visualisation of Origins,
  Destinations and Flows with OD Maps. *The Cartographic Journal* 47(2):
  117–129.

**Data sources**

- World Bank World Development Indicators — `WDI`
  <https://cran.r-project.org/package=WDI>, `wbwdi`, `worldbank`,
  `wbstats`
- Our World in Data — <https://docs.owid.io/> · `owidR`
  <https://cran.r-project.org/package=owidR>
- Eurostat — `eurostat` <https://cran.r-project.org/package=eurostat> ·
  GISCO geometry `giscoR` <https://cran.r-project.org/package=giscoR>
- OECD — `OECD` <https://cran.r-project.org/package=OECD>
- UN Comtrade — `comtradr` <https://cran.r-project.org/package=comtradr>
- V-Dem — <https://www.v-dem.net/data/the-v-dem-dataset/> (R client not
  on CRAN)
- Natural Earth — <https://www.naturalearthdata.com/> · `rnaturalearth`
- GADM via `geodata` <https://cran.r-project.org/package=geodata>
- Subnational code vintages — `regions`
  <https://cran.r-project.org/package=regions>

**ggsql**

- ggsql on CRAN (**0.3.3** as of this survey)
  <https://cran.r-project.org/package=ggsql> · syntax
  <https://ggsql.org/syntax/> · source
  <https://github.com/posit-dev/ggsql> · 0.4.1 spatial release notes
  <https://opensource.posit.co/blog/2026-06-23_ggsql_0_4_1/>
