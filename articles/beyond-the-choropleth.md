# Beyond the choropleth

“World data on a map” has many honest forms. A choropleth is only the
first. The package offers a full vocabulary; this vignette tours the
ones that run without extra dependencies and points to the rest.

## Proportional-symbol (bubble) maps

For *totals*, a choropleth misleads: large values hide in small
countries. Sized circles at centroids are the right idiom.

``` r

bubble_map(snap, population)
```

![](beyond-the-choropleth_files/figure-html/unnamed-chunk-2-1.png)

## Spike maps

The same “totals” job as bubbles, with a different overplotting
trade-off: spikes only grow upward, so dense regions (Europe, the
Caribbean) stay legible.

``` r

spike_map(snap, population)
```

![](beyond-the-choropleth_files/figure-html/unnamed-chunk-3-1.png)

## Equal-area tile grids

Give every country the same visual weight so micro-states are visible.

``` r

tile_map(snap, gdp_per_capita)
```

![](beyond-the-choropleth_files/figure-html/unnamed-chunk-4-1.png)

## Flow maps

Great-circle arcs between country pairs from an origin–destination
table.

``` r

od <- data.frame(
  from   = c("China", "Germany", "Brazil", "Nigeria"),
  to     = c("United States", "France", "Argentina", "India"),
  weight = c(500, 200, 90, 60)
)
flow_map(od, from, to, weight)
```

![](beyond-the-choropleth_files/figure-html/unnamed-chunk-5-1.png)

## Small multiples

[`facet_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/facet_map.md)
splits one choropleth into per-group panels — the static counterpart to
[`animate_world()`](https://pursuitofdatascience.github.io/countryatlas/reference/animate_world.md),
for print and side-by-side comparison:

``` r

world_poly <- attach_geometry(snap, geometry = "polygon") |>
  dplyr::filter(!is.na(continent))
facet_map(world_poly, gdp_per_capita, continent, style = "quantile", ncol = 3)
```

![](beyond-the-choropleth_files/figure-html/unnamed-chunk-6-1.png)

## Labels

Centroid-anchored labels (names, ISO codes or flag emoji), with
`ggrepel` collision avoidance when available.

``` r

mapdf <- attach_geometry(
  dplyr::filter(snap, continent == "Europe"), geometry = "polygon"
)
world_map(mapdf, gdp_per_capita) +
  geom_country_labels(repel = FALSE, size = 2.5) +
  ggplot2::coord_cartesian(xlim = c(-25, 45), ylim = c(34, 72))
```

![](beyond-the-choropleth_files/figure-html/unnamed-chunk-7-1.png)

## Maps that need optional packages

The remaining displays follow the same one-call pattern but require
optional packages, so they are shown here as code:

``` r

# Bivariate choropleth (two variables at once) — needs `biscale` + `sf`
world_data(2020, c(gdp = "NY.GDP.PCAP.KD", life = "SP.DYN.LE00.IN"),
           geometry = "sf") |>
  bivariate_map(gdp, life)

# Area-honest cartogram — needs `cartogram` + `sf`
world_data(2020, c(pop = "SP.POP.TOTL"), geometry = "sf") |>
  cartogram_map(pop, type = "dorling")

# The same Dorling cartogram as a first-class verb, with its tuning exposed
world_data(2020, c(pop = "SP.POP.TOTL"), geometry = "sf") |>
  dorling_map(pop, k = 4)

# Animated choropleth over a year panel — needs `gganimate`
world_data(2000:2020, c(gdp = "NY.GDP.PCAP.KD")) |>
  animate_world(gdp)

# Interactive choropleth — needs `leaflet`, `ggiraph` or `plotly`
world_data(2020) |>
  interactive_map(gdp_per_capita, engine = "plotly")
```

## Country adjacency and distance

Two lightweight spatial helpers that aren’t choropleths at all.
[`distance_between()`](https://pursuitofdatascience.github.io/countryatlas/reference/distance_between.md)
answers “how far apart” from the bundled `country_meta` centroids — no
`sf` or network required:

``` r

distance_between("France", "Germany")
#> [1] 802.3524
```

[`country_borders()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_borders.md)
/
[`neighbors()`](https://pursuitofdatascience.github.io/countryatlas/reference/neighbors.md)
answer “who borders whom”, built from polygon topology, so they need
`sf`:

``` r

neighbors("France")
#> # A tibble: 8 × 3
#>   iso3c neighbor neighbor_country
#>   <chr> <chr>    <chr>           
#> 1 FRA   SUR      Suriname        
#> 2 FRA   LUX      Luxembourg      
#> 3 FRA   ITA      Italy           
#> 4 FRA   BRA      Brazil          
#> 5 FRA   DEU      Germany         
#> 6 FRA   CHE      Switzerland     
#> 7 FRA   BEL      Belgium         
#> 8 FRA   ESP      Spain
```

Each degrades gracefully: if the optional package is missing you get a
clear, actionable message (and
[`animate_world()`](https://pursuitofdatascience.github.io/countryatlas/reference/animate_world.md)
falls back to a faceted small-multiple).
