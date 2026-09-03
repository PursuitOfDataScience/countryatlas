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

![Bubble map: population drawn as proportional circles at country
centroids.](beyond-the-choropleth_files/figure-html/unnamed-chunk-2-1.png)

## Spike maps

The same “totals” job as bubbles, with a different overplotting
trade-off: spikes only grow upward, so dense regions (Europe, the
Caribbean) stay legible.

``` r

spike_map(snap, population)
```

![Spike map: population drawn as vertical spikes rising from country
centroids.](beyond-the-choropleth_files/figure-html/unnamed-chunk-3-1.png)

Both verbs place one symbol per country centroid, and the bundled
centroid table does not cover every code in the codelist. On this
snapshot five countries with population – Hong Kong, Macao, Gibraltar,
the British Virgin Islands and Tuvalu – have no centroid and so no
symbol. Each verb warns and names them, and counts them as missing
rather than shown:

``` r

cov <- attr(suppressWarnings(bubble_map(snap, population)),
            "countryatlas_provenance")$coverage
unlist(cov[c("n_total", "n_shown", "n_missing")])
#>   n_total   n_shown n_missing 
#>       215       210         5
cov$missing_iso3c
#> [1] "GIB" "HKG" "MAC" "TUV" "VGB"
```

## Equal-area tile grids

Give every country the same visual weight so micro-states are visible.
The bundled grid covers 239 countries – see
[`?world_tiles`](https://pursuitofdatascience.github.io/countryatlas/reference/world_tiles.md)
for the ten it omits.

``` r

tile_map(snap, gdp_per_capita)
```

![Equal-area tile grid: one identically sized tile per country, shaded
by GDP per
capita.](beyond-the-choropleth_files/figure-html/unnamed-chunk-5-1.png)

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

![Flow map: great-circle arcs joining four origin-destination country
pairs, width by
volume.](beyond-the-choropleth_files/figure-html/unnamed-chunk-6-1.png)

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

![Small multiples: one GDP per capita choropleth panel per
continent.](beyond-the-choropleth_files/figure-html/unnamed-chunk-7-1.png)

## Labels

Centroid-anchored labels (names, ISO codes or flag emoji), with
`ggrepel` collision avoidance when available. Zoom with
[`coord_quickmap()`](https://ggplot2.tidyverse.org/reference/coord_map.html)
rather than
[`coord_cartesian()`](https://ggplot2.tidyverse.org/reference/coord_cartesian.html)
– both replace the map’s coordinate system, but only the former keeps
the latitude-dependent aspect ratio that stops Europe coming out
stretched sideways.

``` r

mapdf <- attach_geometry(
  dplyr::filter(snap, continent == "Europe"), geometry = "polygon"
)
world_map(mapdf, gdp_per_capita) +
  geom_country_labels(repel = FALSE, size = 2.5) +
  ggplot2::coord_quickmap(xlim = c(-25, 45), ylim = c(34, 72))
```

![Choropleth of Europe with ISO codes labelled at country
centroids.](beyond-the-choropleth_files/figure-html/unnamed-chunk-8-1.png)

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

# The fast flow-based cartogram (Gastner-Seguy-More) — needs `cartogramR`
world_data(2020, c(pop = "SP.POP.TOTL"), geometry = "sf") |>
  cartogram_map(pop, type = "flow")

# Animated choropleth over a year panel — needs `gganimate`
world_data(2000:2020, c(gdp = "NY.GDP.PCAP.KD")) |>
  animate_world(gdp)

# Interactive choropleth — needs `leaflet`, `ggiraph` or `plotly`
world_data(2020) |>
  interactive_map(gdp_per_capita, engine = "plotly")
```

## Value-by-alpha: the cartogram’s non-distorting cousin

A cartogram equalises a denominator by deforming geometry.
[`value_by_alpha_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/value_by_alpha_map.md)
does it by spending opacity instead, so the world stays recognisable:
colour carries the value, opacity carries population, and a rate
computed over a handful of people fades toward the background rather
than shouting.

``` r

mapdf <- attach_geometry(snap, geometry = "polygon")
value_by_alpha_map(mapdf, gdp_per_capita, population)
```

![Value-by-alpha map of GDP per capita weighted by
population.](beyond-the-choropleth_files/figure-html/unnamed-chunk-10-1.png)

It needs no optional packages. The *Honest maps* vignette covers when to
reach for it rather than for
[`cartogram_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/cartogram_map.md).

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
