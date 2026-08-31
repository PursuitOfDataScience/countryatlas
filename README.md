
<!-- README.md is generated from README.Rmd. Please edit that file -->

# countryatlas <img src="man/figures/logo.png" align="right" height="130" alt="countryatlas hex logo: an orthographic globe choropleth with population spikes rising off the horizon" />

<!-- badges: start -->

[![CRAN status](https://www.r-pkg.org/badges/version/countryatlas)](https://CRAN.R-project.org/package=countryatlas)
[![R-CMD-check](https://github.com/PursuitOfDataScience/countryatlas/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/PursuitOfDataScience/countryatlas/actions/workflows/R-CMD-check.yaml)
[![Codecov test coverage](https://codecov.io/gh/PursuitOfDataScience/countryatlas/branch/main/graph/badge.svg)](https://app.codecov.io/gh/PursuitOfDataScience/countryatlas)
[![Lifecycle: stable](https://img.shields.io/badge/lifecycle-stable-brightgreen.svg)](https://lifecycle.r-lib.org/articles/stages.html#stable)
<!-- badges: end -->

> **Country data onto honest maps — joined on ISO codes, never on country names.**

Join the World Bank's life-expectancy table to `map_data("world")` by country
name and **42 of 215 countries silently vanish**: nobody spells Czechia,
Côte d'Ivoire or `"Congo, Dem. Rep."` the same way twice. `countryatlas` makes
the ISO code the join key, so nothing goes missing — then draws the map.

<img src="man/figures/README-hook-1.png" alt="Two world choropleths of life expectancy side by side. Joining on country name leaves dozens of countries grey and unfilled; joining with join_world() fills every one of them." width="100%" />

## Install

``` r
install.packages("countryatlas")                            # CRAN
pak::pak("PursuitOfDataScience/countryatlas")               # development
```

The base install is light. Every heavy spatial dependency (`sf`, `cartogram`,
`leaflet`, …) is a `Suggests` you only need for the feature that uses it.

## One call

`world_data()` fetches the indicator, attaches the geometry and keys the whole
thing on `iso3c` — three worlds (`ggplot2` maps, [WDI](https://github.com/vincentarelbundock/WDI), [countrycode](https://github.com/vincentarelbundock/countrycode))
stitched together in one line.

``` r
world_map(world_data(2020), gdp_per_capita, style = "quantile")
```

<img src="man/figures/README-hero-1.png" alt="World choropleth of GDP per capita in 2020, shaded in five quantile bins." width="100%" />

``` r
world_data(2020, c(life_exp = "SP.DYN.LE00.IN")) |>
  glimpse()
#> Rows: 99,338
#> Columns: 12
#> $ long      <dbl> -69.89912, -69.89571, -69.94219, -70.00415, -70.06612, -70.0…
#> $ lat       <dbl> 12.45200, 12.42300, 12.43853, 12.50049, 12.54697, 12.59707, …
#> $ group     <dbl> 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, …
#> $ order     <int> 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 13, 14, 15, 16, 17, 18, 1…
#> $ subregion <chr> NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, …
#> $ iso3c     <chr> "ABW", "ABW", "ABW", "ABW", "ABW", "ABW", "ABW", "ABW", "ABW…
#> $ iso2c     <chr> "AW", "AW", "AW", "AW", "AW", "AW", "AW", "AW", "AW", "AW", …
#> $ country   <chr> "Aruba", "Aruba", "Aruba", "Aruba", "Aruba", "Aruba", "Aruba…
#> $ continent <chr> "Americas", "Americas", "Americas", "Americas", "Americas", …
#> $ region    <chr> "Latin America & Caribbean", "Latin America & Caribbean", "L…
#> $ income    <fct> High income, High income, High income, High income, High inc…
#> $ life_exp  <dbl> 75.406, 75.406, 75.406, 75.406, 75.406, 75.406, 75.406, 75.4…
```

Geometry, codes, classifications and the indicator, in one frame, ready for
`world_map()`.

Drop `geometry` for a plain country table (`country_data()`), ask for a year
range to get a panel, or pass several indicators at once. `wdi_search()` finds
codes offline; `common_indicators` keeps the 20 you actually use.

## Your data, on the map

Point `join_world()` at whatever column holds the country and it standardises,
joins and attaches geometry in one go.

``` r
tibble(
  nation = c("U.S.", "S. Korea", "Czechia", "Kosovo", "Cote d'Ivoire", "Burma"),
  score  = c(10, 8, 6, 4, 7, 5)
) |>
  join_world(nation, warn = FALSE) |>
  world_map(score, title = "Six countries, six spellings, one map")
```

<img src="man/figures/README-join-1.png" alt="World map with six countries shaded by a made-up score, joined from a table that spelled each of them differently." width="100%" />

Two messy tables reconcile against each other the same way:

``` r
a <- tibble(country = c("Czechia", "South Korea"), gdp = c(1, 2))
b <- tibble(nation  = c("Czech Republic", "Korea, Rep."), pop = c(10, 51))
country_join(a, b, country, nation)
#> # A tibble: 2 × 5
#>   country       gdp iso3c nation           pop
#>   <chr>       <dbl> <chr> <chr>          <dbl>
#> 1 Czechia         1 CZE   Czech Republic    10
#> 2 South Korea     2 KOR   Korea, Rep.       51
```

## Nothing goes missing quietly

`check_country_match()` reports before you join — including the entities
`countrycode` resolves *wrongly* rather than not at all.

``` r
check_country_match(c("USA", "Cote d'Ivoire", "USSR", "Wakanda"))
#> # A tibble: 4 × 5
#>   input         iso3c matched historical suggestion
#>   <chr>         <chr> <lgl>   <lgl>      <chr>     
#> 1 USA           USA   TRUE    FALSE      <NA>      
#> 2 Cote d'Ivoire CIV   TRUE    FALSE      <NA>      
#> 3 USSR          RUS   TRUE    TRUE       <NA>      
#> 4 Wakanda       <NA>  FALSE   FALSE      Canada
```

`repair_country_names()` fixes typos, `audit_coverage()` grades a finished
join, and `dissolve_country()` expands a dead state into its successors.

``` r
dissolve_country("Yugoslavia")
#> # A tibble: 7 × 5
#>   input      historical dissolved iso3c country             
#>   <chr>      <chr>          <int> <chr> <chr>               
#> 1 Yugoslavia Yugoslavia      1992 BIH   Bosnia & Herzegovina
#> 2 Yugoslavia Yugoslavia      1992 HRV   Croatia             
#> 3 Yugoslavia Yugoslavia      1992 MKD   North Macedonia     
#> 4 Yugoslavia Yugoslavia      1992 MNE   Montenegro          
#> 5 Yugoslavia Yugoslavia      1992 SRB   Serbia              
#> 6 Yugoslavia Yugoslavia      1992 SVN   Slovenia            
#> 7 Yugoslavia Yugoslavia      1992 XKX   Kosovo
```

## The gallery

Every map below is one function call on the bundled offline snapshot.

<table>
<tr>
<td width="50%"><img src="man/figures/README-g-choropleth.png" alt="Quantile choropleth of GDP per capita"><br><sub><code>world_map(d, gdp_per_capita, style = "quantile")</code></sub></td>
<td width="50%"><img src="man/figures/README-g-categorical.png" alt="Categorical world choropleth, one colour per continent"><br><sub><code>world_map(d, continent, style = "categorical")</code></sub></td>
</tr>
<tr>
<td><img src="man/figures/README-g-bubble.png" alt="Proportional-symbol map of population"><br><sub><code>bubble_map(d, population)</code></sub></td>
<td><img src="man/figures/README-g-spike.png" alt="Spike map of population"><br><sub><code>spike_map(d, population)</code></sub></td>
</tr>
<tr>
<td><img src="man/figures/README-g-cartogram.png" alt="Contiguous cartogram resized by population"><br><sub><code>cartogram_map(d, population)</code></sub></td>
<td><img src="man/figures/README-g-dorling.png" alt="Dorling cartogram of population"><br><sub><code>dorling_map(d, population)</code></sub></td>
</tr>
<tr>
<td><img src="man/figures/README-g-bivariate.png" alt="Bivariate choropleth of GDP per capita against life expectancy"><br><sub><code>bivariate_map(d, gdp_per_capita, life_expectancy)</code></sub></td>
<td><img src="man/figures/README-g-flow.png" alt="World map with great-circle arcs joining pairs of countries, weighted by flow size"><br><sub><code>flow_map(corridors, from, to, people)</code></sub></td>
</tr>
<tr>
<td><img src="man/figures/README-g-globe.png" alt="Orthographic globe shaded by World Bank income group"><br><sub><code>globe_map(d, income, style = "categorical")</code></sub></td>
<td align="center"><img src="man/figures/README-g-spin.gif" width="55%" alt="A globe coloured by continent, spinning through one full rotation"><br><sub><code>spin_globe(d, continent, style = "categorical")</code></sub></td>
</tr>
<tr>
<td colspan="2"><img src="man/figures/README-g-tile.png" alt="Equal-area tile grid, one labelled square per country"><br><sub><code>tile_map(d, gdp_per_capita)</code> — one square per country, so microstates are as visible as Russia</sub></td>
</tr>
<tr>
<td colspan="2"><img src="man/figures/README-g-facet.png" alt="Small-multiple choropleths of life expectancy in 1990, 2005 and 2020"><br><sub><code>facet_map(panel, life_exp, year, style = "quantile")</code> — or <code>animate_world(panel, life_exp)</code> for the moving version</sub></td>
</tr>
</table>

Thirteen projections come along for the ride on the `sf` backend
(`world_map(d, x, projection = "winkel_tripel")`), and `interactive_map()`
hands the same frame to **plotly**, **ggiraph**, **leaflet** or **ggsql** for a
web-ready widget. With `as_ggsql_source()` and `world_query()` the drawing
happens *inside DuckDB* — countryatlas reconciles the countries, [ggsql](https://ggsql.org)
renders them without ggplot2 or `sf` at runtime.

## Beyond the map

``` r
snap <- world_snapshot$countries

# inequality between people, not between country units
gini(snap$gdp_per_capita, weights = snap$population)
#> [1] 0.6094909

# how much of it sits between continents rather than within them
theil(snap$gdp_per_capita, weights = snap$population, groups = snap$continent)
#> # A tibble: 3 × 3
#>   component value share
#>   <chr>     <dbl> <dbl>
#> 1 total     0.678 1    
#> 2 between   0.310 0.458
#> 3 within    0.368 0.542

# who borders whom, and how far apart they are -- no sf required
distance_between("France", "Germany")
#> [1] 802.3524
convert_country(c("Japan", "Brazil"), to = "flag")
#> [1] "🇯🇵" "🇧🇷"
```

|  |  |
|----|----|
| **Assemble** | `world_data()` `country_data()` `world_geometry()` `attach_geometry()` `clear_wdi_cache()` |
| **Join** | `standardize_country()` `join_world()` `country_join()` `country_join_all()` `dissolve_country()` |
| **Diagnose** | `check_country_match()` `repair_country_names()` `audit_coverage()` `country_overrides()` `wdj_overrides()` |
| **Look up** | `convert_country()` `country_codes()` `country_groups()` `in_group()` `wdi_search()` |
| **Compute** | `per_capita()` `share_of_world()` `growth_rate()` `index_to()` `rank_countries()` `aggregate_regions()` `complete_years()` `lag_by_country()` `diff_by_country()` `correlate_indicators()` |
| **Measure spread** | `gini()` `theil()` `beta_convergence()` `sigma_convergence()` `morans_i()` |
| **Locate** | `locate_country()` `neighbors()` `country_borders()` `distance_between()` `simplify_geometry()` |
| **Draw** | `world_map()` `globe_map()` `spin_globe()` `facet_map()` `bubble_map()` `spike_map()` `bivariate_map()` `cartogram_map()` `dorling_map()` `tile_map()` `flow_map()` `animate_world()` `interactive_map()` `geom_country_labels()` `theme_world_map()` |
| **Push to the database** | `as_ggsql_source()` `world_query()` |
| **Bundled data** | `world_snapshot` `country_meta` `common_indicators` `country_groups_tbl` `world_tiles` `historical_codes` |

## Offline by default

`world_snapshot` ships a curated indicator set for one recent year, so every
example, test and vignette in the package runs with the network unplugged.
Live `world_data()` calls are memoised on disk between sessions.

<details>
<summary><b>Which optional package does what</b></summary>

| Needs | For |
|----|----|
| `maps` | the polygon backend: `world_map()`, `bubble_map()`, `spike_map()`, `flow_map()`, `globe_map(backend = "polygon")` (with `mapproj`) |
| `sf` + `rnaturalearth` + `rnaturalearthdata` | real geometry: `world_map(sf)`, `world_geometry(sf)`, `locate_country()`, `country_borders()`, `neighbors()`, `morans_i()` |
| `cartogram` + `sf` | `cartogram_map()`, `dorling_map()` |
| `biscale` + `sf` | `bivariate_map()` |
| `gganimate` + `gifski` or `magick` | `animate_world()`, `spin_globe()` |
| `plotly` / `ggiraph` / `leaflet` / `ggsql` | the four `interactive_map()` engines |
| `duckdb` + `DBI`, or `nanoarrow` | `as_ggsql_source()` |
| `stringdist` | fuzzy matching in `repair_country_names()` and `check_country_match()` |
| `rmapshaper` | the better simplifier behind `simplify_geometry()` |
| `classInt` | `style = "jenks"` |

</details>

## Learn more

[Getting started](https://pursuitofdatascience.github.io/countryatlas/articles/getting-started.html) · [Joining your own data](https://pursuitofdatascience.github.io/countryatlas/articles/joining-your-own-data.html) ·
[Maps with sf & projections](https://pursuitofdatascience.github.io/countryatlas/articles/sf-and-projections.html) · [Beyond the choropleth](https://pursuitofdatascience.github.io/countryatlas/articles/beyond-the-choropleth.html) ·
[countryatlas and ggsql](https://pursuitofdatascience.github.io/countryatlas/articles/countryatlas-and-ggsql.html) · [Full reference](https://pursuitofdatascience.github.io/countryatlas/) · [Changelog](NEWS.md)
