# countryatlas

> **Country data onto honest maps — joined on ISO codes, never on
> country names.**

Join the World Bank’s life-expectancy table to `map_data("world")` by
country name and **42 of 215 countries silently vanish**: nobody spells
Czechia, Côte d’Ivoire or `"Congo, Dem. Rep."` the same way twice.
`countryatlas` makes the ISO code the join key, so nothing goes missing
— then draws the map.

![Two world choropleths of life expectancy side by side. Joining on
country name leaves dozens of countries grey and unfilled; joining with
join_world() fills every one of
them.](reference/figures/README-hook-1.png)

## Install

``` r

install.packages("countryatlas")                            # CRAN
pak::pak("PursuitOfDataScience/countryatlas")               # development
```

The base install is light. Every heavy spatial dependency (`sf`,
`cartogram`, `leaflet`, …) is a `Suggests` you only need for the feature
that uses it.

## One call

[`world_data()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_data.md)
fetches the indicator, attaches the geometry and keys the whole thing on
`iso3c` — three worlds (`ggplot2` maps,
[WDI](https://github.com/vincentarelbundock/WDI),
[countrycode](https://github.com/vincentarelbundock/countrycode))
stitched together in one line.

``` r

world_map(world_data(2020), gdp_per_capita, style = "quantile")
```

![World choropleth of GDP per capita in 2020, shaded in five quantile
bins.](reference/figures/README-hero-1.png)

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

Geometry, codes, classifications and the indicator, in one frame, ready
for
[`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md).

Drop `geometry` for a plain country table
([`country_data()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_data.md)),
ask for a year range to get a panel, or pass several indicators at once.
[`wdi_search()`](https://pursuitofdatascience.github.io/countryatlas/reference/wdi_search.md)
finds codes offline; `common_indicators` keeps the 20 you actually use.

## Your data, on the map

Point
[`join_world()`](https://pursuitofdatascience.github.io/countryatlas/reference/join_world.md)
at whatever column holds the country and it standardises, joins and
attaches geometry in one go.

``` r

tibble(
  nation = c("U.S.", "S. Korea", "Czechia", "Kosovo", "Cote d'Ivoire", "Burma"),
  score  = c(10, 8, 6, 4, 7, 5)
) |>
  join_world(nation, warn = FALSE) |>
  world_map(score, title = "Six countries, six spellings, one map")
```

![World map with six countries shaded by a made-up score, joined from a
table that spelled each of them
differently.](reference/figures/README-join-1.png)

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

[`check_country_match()`](https://pursuitofdatascience.github.io/countryatlas/reference/check_country_match.md)
reports before you join — including the entities `countrycode` resolves
*wrongly* rather than not at all.

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

[`repair_country_names()`](https://pursuitofdatascience.github.io/countryatlas/reference/repair_country_names.md)
fixes typos,
[`audit_coverage()`](https://pursuitofdatascience.github.io/countryatlas/reference/audit_coverage.md)
grades a finished join, and
[`dissolve_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/dissolve_country.md)
expands a dead state into its successors.

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

[TABLE]

[`interactive_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/interactive_map.md)
hands the same frame to **plotly**, **ggiraph**, **leaflet** or
**ggsql** for a web-ready widget. With
[`as_ggsql_source()`](https://pursuitofdatascience.github.io/countryatlas/reference/as_ggsql_source.md)
and
[`world_query()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_query.md)
the drawing happens *inside DuckDB* — countryatlas reconciles the
countries, [ggsql](https://ggsql.org) renders them without ggplot2 or
`sf` at runtime.

## Honest by construction

“Honest maps” is in the package description, so the package has to earn
it. Four ways a world map misleads, the verb for each — and one more
that makes the map admit what it did.

**Your classification is doing the talking.** Equal-interval breaks put
92% of countries in one class here; quantiles spread them evenly. Same
data, same palette, opposite conclusions.

![The same GDP choropleth under quantile, Jenks, equal-interval and
pretty breaks; the last two are almost entirely one
colour](reference/figures/README-h-classify.png)

``` r

p <- classify_compare(poly, gdp_per_capita)
attr(p, "countryatlas_classification") |> filter(method %in% c("quantile", "equal"))
#> # A tibble: 10 × 4
#>    method   class                     n   share
#>    <chr>    <chr>                 <int>   <dbl>
#>  1 quantile [268.7,1662]             38 0.201  
#>  2 quantile (1662,4594]              38 0.201  
#>  3 quantile (4594,1.029e+04]         37 0.196  
#>  4 quantile (1.029e+04,2.937e+04]    38 0.201  
#>  5 quantile (2.937e+04,2.472e+05]    38 0.201  
#>  6 equal    [268.7,4.965e+04]       173 0.915  
#>  7 equal    (4.965e+04,9.903e+04]    13 0.0688 
#>  8 equal    (9.903e+04,1.484e+05]     2 0.0106 
#>  9 equal    (1.484e+05,1.978e+05]     0 0      
#> 10 equal    (1.978e+05,2.472e+05]     1 0.00529
```

**Your projection is doing the talking too.** Tissot’s indicatrix puts
circles of equal ground radius on the map: whatever the projection does
to them, it is doing to your data.

[TABLE]

**Grey means “no data”, but it reads as “low”.** Hatch the gaps so
nobody mistakes them for a value, or map availability itself.

[TABLE]

**A rate over eleven thousand people should not shout as loudly as one
over a billion.** Value-by-alpha spends opacity on the denominator, so
small-population countries recede — the cartogram’s answer to the same
problem, without distorting the geometry.

![Value-by-alpha map: GDP per capita in colour, population as opacity,
over a dark background](reference/figures/README-h-alpha.png)

``` r

value_by_alpha_map(d, gdp_per_capita, population)
```

**And the map should say what it is.** `footnote = "auto"` writes the
coverage line;
[`map_provenance()`](https://pursuitofdatascience.github.io/countryatlas/reference/map_provenance.md)
answers the questions a reviewer asks first.

``` r

world_map(poly, gdp_per_capita, style = "quantile",
          na_style = "hatched", footnote = "auto") |>
  map_provenance()
#> 
#> ── countryatlas map provenance
#> package: countryatlas 3.0.0 (snapshot 2024)
#> fill: gdp_per_capita
#> geometry: polygon backend, coord_quickmap
#> classification: quantile, 5 bins
#> missing data: hatched
#> coverage: 189 countries shown, 51 missing
#> breaks: 268.7 | 1662 | 4594 | 10290 | 29370 | 247200
```

## Other sources, other years, other levels

The ISO spine is not only the World Bank’s, and not only 2024’s.

[TABLE]

**Membership is a function of time**, and a snapshot quietly misstates
any panel that spans an accession:

``` r

c(`2016` = in_group("United Kingdom", "EU", as_of = 2016),
  `2021` = in_group("United Kingdom", "EU", as_of = 2021))
#>  2016  2021 
#>  TRUE FALSE
```

**Islands have no land border**, so the default contiguity weights drop
a quarter of the world from a “global” Moran’s I.
[`country_weights()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_weights.md)
fixes it, and the result says how many it dropped either way:

``` r

snap <- world_snapshot$countries
cols <- c("i", "n", "n_excluded")
rbind(
  cbind(scheme = "contiguity",
        morans_i(snap, gdp_per_capita, n_perm = 0)[cols]),
  cbind(scheme = "knn",
        morans_i(snap, gdp_per_capita, n_perm = 0,
                 weights = country_weights("knn", k = 5))[cols])
)
#>       scheme         i   n n_excluded
#> 1 contiguity 0.6073182 142         49
#> 2        knn 0.4720522 189          2
```

**Any provider, one shape.**
[`register_country_source()`](https://pursuitofdatascience.github.io/countryatlas/reference/register_country_source.md)
takes a fetch function and a name;
[`fetch_indicator()`](https://pursuitofdatascience.github.io/countryatlas/reference/fetch_indicator.md)
and
[`compare_sources()`](https://pursuitofdatascience.github.io/countryatlas/reference/compare_sources.md)
do the rest — including telling you where two providers disagree.

``` r

country_sources()[, c("source", "meta")]
#> # A tibble: 5 × 2
#>   source   meta                                                          
#>   <chr>    <chr>                                                         
#> 1 comtrade UN Comtrade bilateral trade (via comtradr); needs an API token
#> 2 eurostat Eurostat (via eurostat); European coverage only               
#> 3 oecd     OECD statistics (via OECD)                                    
#> 4 owid     Our World in Data (via owidR)                                 
#> 5 wdi      World Bank World Development Indicators (via WDI)
```

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
| **Assemble** | [`world_data()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_data.md) [`country_data()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_data.md) [`world_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_geometry.md) [`attach_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/attach_geometry.md) [`clear_country_cache()`](https://pursuitofdatascience.github.io/countryatlas/reference/clear_country_cache.md) |
| **Other sources** | [`register_country_source()`](https://pursuitofdatascience.github.io/countryatlas/reference/register_country_source.md) [`country_sources()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_sources.md) [`fetch_indicator()`](https://pursuitofdatascience.github.io/countryatlas/reference/fetch_indicator.md) [`add_indicator()`](https://pursuitofdatascience.github.io/countryatlas/reference/add_indicator.md) [`compare_sources()`](https://pursuitofdatascience.github.io/countryatlas/reference/compare_sources.md) [`fetch_owid()`](https://pursuitofdatascience.github.io/countryatlas/reference/source_adapters.md) [`fetch_eurostat()`](https://pursuitofdatascience.github.io/countryatlas/reference/source_adapters.md) [`fetch_oecd()`](https://pursuitofdatascience.github.io/countryatlas/reference/source_adapters.md) [`fetch_comtrade()`](https://pursuitofdatascience.github.io/countryatlas/reference/source_adapters.md) |
| **Join** | [`standardize_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/standardize_country.md) [`join_world()`](https://pursuitofdatascience.github.io/countryatlas/reference/join_world.md) [`country_join()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_join.md) [`country_join_all()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_join_all.md) [`dissolve_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/dissolve_country.md) [`standardize_subnational()`](https://pursuitofdatascience.github.io/countryatlas/reference/standardize_subnational.md) |
| **Diagnose** | [`check_country_match()`](https://pursuitofdatascience.github.io/countryatlas/reference/check_country_match.md) [`repair_country_names()`](https://pursuitofdatascience.github.io/countryatlas/reference/repair_country_names.md) [`audit_coverage()`](https://pursuitofdatascience.github.io/countryatlas/reference/audit_coverage.md) [`audit_time_coverage()`](https://pursuitofdatascience.github.io/countryatlas/reference/audit_time_coverage.md) [`rate_check()`](https://pursuitofdatascience.github.io/countryatlas/reference/rate_check.md) [`check_dispute_coverage()`](https://pursuitofdatascience.github.io/countryatlas/reference/check_dispute_coverage.md) [`country_overrides()`](https://pursuitofdatascience.github.io/countryatlas/reference/wdj_overrides.md) |
| **Look up** | [`convert_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/convert_country.md) [`country_codes()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_codes.md) [`country_groups()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_groups.md) [`in_group()`](https://pursuitofdatascience.github.io/countryatlas/reference/in_group.md) [`wdi_search()`](https://pursuitofdatascience.github.io/countryatlas/reference/wdi_search.md) |
| **Compute** | [`per_capita()`](https://pursuitofdatascience.github.io/countryatlas/reference/per_capita.md) [`share_of_world()`](https://pursuitofdatascience.github.io/countryatlas/reference/share_of_world.md) [`growth_rate()`](https://pursuitofdatascience.github.io/countryatlas/reference/growth_rate.md) [`index_to()`](https://pursuitofdatascience.github.io/countryatlas/reference/index_to.md) [`rank_countries()`](https://pursuitofdatascience.github.io/countryatlas/reference/rank_countries.md) [`aggregate_regions()`](https://pursuitofdatascience.github.io/countryatlas/reference/aggregate_regions.md) [`complete_years()`](https://pursuitofdatascience.github.io/countryatlas/reference/complete_years.md) [`lag_by_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/lag_by_country.md) [`diff_by_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/lag_by_country.md) [`correlate_indicators()`](https://pursuitofdatascience.github.io/countryatlas/reference/correlate_indicators.md) [`deflate()`](https://pursuitofdatascience.github.io/countryatlas/reference/deflate.md) [`to_ppp()`](https://pursuitofdatascience.github.io/countryatlas/reference/to_ppp.md) [`smooth_rates()`](https://pursuitofdatascience.github.io/countryatlas/reference/smooth_rates.md) [`interpolate_missing()`](https://pursuitofdatascience.github.io/countryatlas/reference/interpolate_missing.md) |
| **Measure spread** | [`gini()`](https://pursuitofdatascience.github.io/countryatlas/reference/gini.md) [`theil()`](https://pursuitofdatascience.github.io/countryatlas/reference/theil.md) [`beta_convergence()`](https://pursuitofdatascience.github.io/countryatlas/reference/beta_convergence.md) [`sigma_convergence()`](https://pursuitofdatascience.github.io/countryatlas/reference/sigma_convergence.md) [`convergence_club()`](https://pursuitofdatascience.github.io/countryatlas/reference/convergence_club.md) |
| **Spatial statistics** | [`country_weights()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_weights.md) [`morans_i()`](https://pursuitofdatascience.github.io/countryatlas/reference/morans_i.md) [`local_morans()`](https://pursuitofdatascience.github.io/countryatlas/reference/local_morans.md) [`lisa_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/lisa_map.md) [`gearys_c()`](https://pursuitofdatascience.github.io/countryatlas/reference/gearys_c.md) [`getis_ord()`](https://pursuitofdatascience.github.io/countryatlas/reference/getis_ord.md) [`spatial_lag()`](https://pursuitofdatascience.github.io/countryatlas/reference/spatial_lag.md) |
| **Locate** | [`locate_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/locate_country.md) [`neighbors()`](https://pursuitofdatascience.github.io/countryatlas/reference/neighbors.md) [`country_borders()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_borders.md) [`distance_between()`](https://pursuitofdatascience.github.io/countryatlas/reference/distance_between.md) [`simplify_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/simplify_geometry.md) [`nuts_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/nuts_geometry.md) |
| **Travel in time** | [`historical_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/historical_geometry.md) [`country_timeline()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_timeline.md) `country_groups(as_of=)` `in_group(as_of=)` |
| **Relate** | [`flow_matrix()`](https://pursuitofdatascience.github.io/countryatlas/reference/flow_matrix.md) [`country_network()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_network.md) [`od_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/od_map.md) |
| **Draw** | [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md) [`globe_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/globe_map.md) [`spin_globe()`](https://pursuitofdatascience.github.io/countryatlas/reference/spin_globe.md) [`facet_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/facet_map.md) [`bubble_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/bubble_map.md) [`spike_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/spike_map.md) [`bivariate_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/bivariate_map.md) [`cartogram_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/cartogram_map.md) [`dorling_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/dorling_map.md) [`value_by_alpha_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/value_by_alpha_map.md) [`tile_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/tile_map.md) [`flow_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/flow_map.md) [`animate_world()`](https://pursuitofdatascience.github.io/countryatlas/reference/animate_world.md) [`interactive_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/interactive_map.md) [`gridded_cartogram()`](https://pursuitofdatascience.github.io/countryatlas/reference/gridded_cartogram.md) [`subnational_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/subnational_map.md) [`geom_country_labels()`](https://pursuitofdatascience.github.io/countryatlas/reference/geom_country_labels.md) [`theme_world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/theme_world_map.md) |
| **Keep honest** | [`classify_compare()`](https://pursuitofdatascience.github.io/countryatlas/reference/classify_compare.md) [`coverage_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/coverage_map.md) [`projection_info()`](https://pursuitofdatascience.github.io/countryatlas/reference/projection_info.md) [`projection_compare()`](https://pursuitofdatascience.github.io/countryatlas/reference/projection_compare.md) [`projection_distortion()`](https://pursuitofdatascience.github.io/countryatlas/reference/projection_distortion.md) [`tissot_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/tissot_map.md) [`cartogram_diagnostics()`](https://pursuitofdatascience.github.io/countryatlas/reference/cartogram_diagnostics.md) [`map_provenance()`](https://pursuitofdatascience.github.io/countryatlas/reference/map_provenance.md) [`dispute_policy()`](https://pursuitofdatascience.github.io/countryatlas/reference/dispute_policy.md) |
| **Report** | [`country_factsheet()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_factsheet.md) [`world_table()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_table.md) |
| **Push to the database** | [`as_ggsql_source()`](https://pursuitofdatascience.github.io/countryatlas/reference/as_ggsql_source.md) [`world_query()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_query.md) |
| **Bundled data** | `world_snapshot` `country_meta` `common_indicators` `country_groups_tbl` `country_groups_history` `disputed_territories` `world_tiles` `historical_codes` |

## Offline by default

`world_snapshot` ships a curated indicator set for one recent year, so
every example, test and vignette in the package runs with the network
unplugged. Live
[`world_data()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_data.md)
calls are memoised on disk between sessions.

**Which optional package does what**

| Needs | For |
|----|----|
| `maps` | the polygon backend: [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md), [`bubble_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/bubble_map.md), [`spike_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/spike_map.md), [`flow_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/flow_map.md), `globe_map(backend = "polygon")` (with `mapproj`) |
| `sf` + `rnaturalearth` + `rnaturalearthdata` | real geometry: `world_map(sf)`, `world_geometry(sf)`, [`locate_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/locate_country.md), [`country_borders()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_borders.md), [`neighbors()`](https://pursuitofdatascience.github.io/countryatlas/reference/neighbors.md), [`morans_i()`](https://pursuitofdatascience.github.io/countryatlas/reference/morans_i.md) |
| `cartogram` + `sf` | [`cartogram_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/cartogram_map.md), [`dorling_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/dorling_map.md) |
| `biscale` + `sf` | [`bivariate_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/bivariate_map.md) |
| `gganimate` + `gifski` or `magick` | [`animate_world()`](https://pursuitofdatascience.github.io/countryatlas/reference/animate_world.md), [`spin_globe()`](https://pursuitofdatascience.github.io/countryatlas/reference/spin_globe.md) |
| `cartogramR` | `cartogram_map(type = "flow")`, the fast Gastner-Seguy-More algorithm |
| `cshapes` | [`historical_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/historical_geometry.md) and `attach_geometry(year=)` |
| `owidR` / `eurostat` / `OECD` / `comtradr` | the four built-in `fetch_*()` source adapters |
| `mapgl` | `interactive_map(engine = "mapgl")`, `globe_map(interactive = TRUE)` |
| `tmap` | `world_map(engine = "tmap")` |
| `giscoR` / `regions` | [`nuts_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/nuts_geometry.md), [`standardize_subnational()`](https://pursuitofdatascience.github.io/countryatlas/reference/standardize_subnational.md) |
| `gt` | [`world_table()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_table.md) |
| `ggpattern` | `world_map(na_style = "hatched")` |
| `plotly` / `ggiraph` / `leaflet` / `ggsql` | the four [`interactive_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/interactive_map.md) engines |
| `duckdb` + `DBI`, or `nanoarrow` | [`as_ggsql_source()`](https://pursuitofdatascience.github.io/countryatlas/reference/as_ggsql_source.md) |
| `stringdist` | fuzzy matching in [`repair_country_names()`](https://pursuitofdatascience.github.io/countryatlas/reference/repair_country_names.md) and [`check_country_match()`](https://pursuitofdatascience.github.io/countryatlas/reference/check_country_match.md) |
| `rmapshaper` | the better simplifier behind [`simplify_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/simplify_geometry.md) |
| `classInt` | `style = "jenks"` |

## Learn more

[Getting
started](https://pursuitofdatascience.github.io/countryatlas/articles/getting-started.html)
· [Joining your own
data](https://pursuitofdatascience.github.io/countryatlas/articles/joining-your-own-data.html)
· [Maps with sf &
projections](https://pursuitofdatascience.github.io/countryatlas/articles/sf-and-projections.html)
· [Beyond the
choropleth](https://pursuitofdatascience.github.io/countryatlas/articles/beyond-the-choropleth.html)
· [countryatlas and
ggsql](https://pursuitofdatascience.github.io/countryatlas/articles/countryatlas-and-ggsql.html)
· [Full reference](https://pursuitofdatascience.github.io/countryatlas/)
·
[Changelog](https://pursuitofdatascience.github.io/countryatlas/NEWS.md)
