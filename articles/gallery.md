# Gallery

Every map here is one call on the bundled snapshot, offline. Each
carries its coverage and source in the caption, alt text from
[`map_alt_text()`](https://pursuitofdatascience.github.io/countryatlas/reference/map_alt_text.md),
and a provenance record from
[`map_provenance()`](https://pursuitofdatascience.github.io/countryatlas/reference/map_provenance.md).

## Choropleths

``` r

world_map(poly, gdp_per_capita)
```

![Quantile choropleth of GDP per
capita.](gallery_files/figure-html/unnamed-chunk-2-1.png)

``` r

world_map(poly, gdp_per_capita, breaks = c(-Inf, 1136, 4466, 13846, Inf))
```

![Choropleth with the World Bank income thresholds as fixed
classes.](gallery_files/figure-html/unnamed-chunk-3-1.png)

``` r

world_map(poly, income)
```

![Categorical map of World Bank income
groups.](gallery_files/figure-html/unnamed-chunk-4-1.png)

``` r

world_map(poly, gdp_per_capita, recenter = 150)
```

![World map of GDP per capita centred on the
Pacific.](gallery_files/figure-html/unnamed-chunk-5-1.png)

``` r

set.seed(1)
mix <- transform(snap, farm = runif(nrow(snap), 1, 4),
                 industry = runif(nrow(snap), 2, 6),
                 services = runif(nrow(snap), 4, 9))
ternary_map(attach_geometry(mix), farm, industry, services)
```

![Ternary map of a made-up three-part composition, centred on the
average country.](gallery_files/figure-html/unnamed-chunk-6-1.png)

## Symbols, flows and grids

``` r

bubble_map(snap, population)
```

![Proportional-symbol map of
population.](gallery_files/figure-html/unnamed-chunk-7-1.png)

``` r

spike_map(snap, population)
```

![Spike map of
population.](gallery_files/figure-html/unnamed-chunk-8-1.png)

``` r

corridors <- data.frame(
  from = c("Brazil", "Nigeria", "South Africa", "Kenya", "Indonesia", "Peru"),
  to = c("Portugal", "United Kingdom", "United Kingdom", "United Kingdom",
         "Saudi Arabia", "Spain"),
  people = c(1.4, 2.1, 2.6, 1.7, 1.8, 1.2))
flow_map(corridors, from, to, people)
```

![Great-circle arcs between six pairs of
countries.](gallery_files/figure-html/unnamed-chunk-9-1.png)

``` r

tile_map(snap, gdp_per_capita)
```

![Equal-area tile grid, one square per
country.](gallery_files/figure-html/unnamed-chunk-10-1.png)

``` r

gridded_cartogram(snap, population, cells = 600)
```

![Gridded cartogram: one square per fixed number of
people.](gallery_files/figure-html/unnamed-chunk-11-1.png)

## Honest maps

``` r

value_by_alpha_map(poly, gdp_per_capita, population)
```

![Value-by-alpha map: GDP per capita in colour, population as
opacity.](gallery_files/figure-html/unnamed-chunk-12-1.png)

``` r

coverage_map(poly, co2_per_capita)
```

![Map of which countries report CO2 per
capita.](gallery_files/figure-html/unnamed-chunk-13-1.png)

``` r

classify_compare(poly, gdp_per_capita, ncol = 3)
```

![GDP per capita under six classification
methods.](gallery_files/figure-html/unnamed-chunk-14-1.png)

## Globes and cartograms

``` r

globe_map(sfd, income, lon = 20, lat = 10)
```

![Orthographic globe shaded by income
group.](gallery_files/figure-html/unnamed-chunk-15-1.png)

``` r

dorling_map(sfd, population)
```

![Dorling cartogram of
population.](gallery_files/figure-html/unnamed-chunk-16-1.png)

``` r

if (requireNamespace("biscale", quietly = TRUE)) {
  bivariate_map(sfd, gdp_per_capita, life_expectancy)
}
```

![Bivariate choropleth of GDP per capita against life
expectancy.](gallery_files/figure-html/unnamed-chunk-17-1.png)

## Over time

``` r

set.seed(1)
pan <- expand.grid(iso3c = world_tiles$iso3c, year = 2000:2020,
                   stringsAsFactors = FALSE)
pan$v <- stats::ave(stats::rnorm(nrow(pan)), pan$iso3c, FUN = cumsum)
tile_trend_map(pan, v, label = FALSE)
```

![A sparkline of a made-up series for every country on the tile
grid.](gallery_files/figure-html/unnamed-chunk-18-1.png)
