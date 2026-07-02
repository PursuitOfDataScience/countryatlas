# Map-ready, enriched country tibble

The package's headline function, generalised but backward-compatible.
Returns a tibble that already stitches together map geometry, World Bank
indicators and the countrycode crosswalk, keyed on the ISO spine – ready
to pipe into
[`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md)
or `ggplot2`.

## Usage

``` r
world_data(
  year,
  indicator = c(gdp_per_capita = "NY.GDP.PCAP.KD"),
  geometry = c("polygon", "sf", "none"),
  scale = c("small", "medium", "large"),
  region = NULL,
  classify = c("income", "continent", "region"),
  projection = "equal_earth",
  recenter = NULL,
  latest = FALSE,
  cache = TRUE,
  language = "en",
  parallel = TRUE,
  overrides = wdj_overrides()
)
```

## Arguments

- year:

  A single year or a range (e.g. `2000:2020`, yielding a panel keyed on
  `iso3c` + `year`). Minimum 1960.

- indicator:

  A named character vector of WDI codes. Names drive column names, e.g.
  `c(gdp = "NY.GDP.PCAP.KD", pop = "SP.POP.TOTL")`. Defaults to
  `c(gdp_per_capita = "NY.GDP.PCAP.KD")`.

- geometry:

  `"polygon"` (default; reproduces the classic output), `"sf"` (Natural
  Earth, for
  [`geom_sf()`](https://ggplot2.tidyverse.org/reference/ggsf.html) and
  real projections) or `"none"`.

- scale:

  Natural Earth resolution for the `sf` backend.

- region:

  Optional subset: a continent, group name, `iso3c` vector or bounding
  box.

- classify:

  Which classifications to add (any of `"income"`, `"continent"`,
  `"region"`).

- projection, recenter:

  Projection options for the `sf` backend.

- latest:

  If `TRUE`, use the most recent non-`NA` value per country for a
  single-year request.

- cache:

  Whether to use the memoised / on-disk WDI cache.

- language:

  WDI language code (default `"en"`).

- parallel:

  Whether to fetch multiple indicators in parallel.

- overrides:

  Name -\> iso3c overrides for geometry matching (default
  [`wdj_overrides()`](https://pursuitofdatascience.github.io/countryatlas/reference/wdj_overrides.md)).

## Value

A tibble (polygon backend), `sf` object (sf backend) or country-level
tibble (`geometry = "none"`).

## Details

`world_data(2020)` keeps its original behaviour (polygon backend, GDP
per capita). Everything else is opt-in: any indicator(s), a span of
years (a panel), an `sf` backend with real projections, and region
subsetting.

## Examples

``` r
# \donttest{
world_data(2020)
#> # A tibble: 99,338 × 12
#>     long   lat group order subregion iso3c iso2c country continent region income
#>    <dbl> <dbl> <dbl> <int> <chr>     <chr> <chr> <chr>   <chr>     <chr>  <fct> 
#>  1 -69.9  12.5     1     1 NA        ABW   AW    Aruba   Americas  Latin… High …
#>  2 -69.9  12.4     1     2 NA        ABW   AW    Aruba   Americas  Latin… High …
#>  3 -69.9  12.4     1     3 NA        ABW   AW    Aruba   Americas  Latin… High …
#>  4 -70.0  12.5     1     4 NA        ABW   AW    Aruba   Americas  Latin… High …
#>  5 -70.1  12.5     1     5 NA        ABW   AW    Aruba   Americas  Latin… High …
#>  6 -70.1  12.6     1     6 NA        ABW   AW    Aruba   Americas  Latin… High …
#>  7 -70.0  12.6     1     7 NA        ABW   AW    Aruba   Americas  Latin… High …
#>  8 -70.0  12.6     1     8 NA        ABW   AW    Aruba   Americas  Latin… High …
#>  9 -69.9  12.5     1     9 NA        ABW   AW    Aruba   Americas  Latin… High …
#> 10 -69.9  12.5     1    10 NA        ABW   AW    Aruba   Americas  Latin… High …
#> # ℹ 99,328 more rows
#> # ℹ 1 more variable: gdp_per_capita <dbl>
world_data(2020, indicator = c(life_exp = "SP.DYN.LE00.IN"),
           geometry = "none")
#> Warning: URL 'https://api.worldbank.org/v2/en/country/all/indicator/SP.DYN.LE00.IN?format=json&date=2020:2020&per_page=32500&page=2': Timeout of 60 seconds was reached
#> # A tibble: 216 × 7
#>    iso3c iso2c country             continent region              income life_exp
#>    <chr> <chr> <chr>               <chr>     <chr>               <fct>     <dbl>
#>  1 AFG   AF    Afghanistan         Asia      Middle East, North… Low i…     61.5
#>  2 ALB   AL    Albania             Europe    Europe & Central A… Upper…     77.8
#>  3 DZA   DZ    Algeria             Africa    Middle East, North… Upper…     73.3
#>  4 ASM   AS    American Samoa      Oceania   East Asia & Pacific High …     72.7
#>  5 AND   AD    Andorra             Europe    Europe & Central A… High …     79.4
#>  6 AGO   AO    Angola              Africa    Sub-Saharan Africa  Lower…     63.1
#>  7 ATG   AG    Antigua and Barbuda Americas  Latin America & Ca… High …     77.2
#>  8 ARG   AR    Argentina           Americas  Latin America & Ca… Upper…     75.9
#>  9 ARM   AM    Armenia             Asia      Europe & Central A… Upper…     73.4
#> 10 ABW   AW    Aruba               Americas  Latin America & Ca… High …     75.4
#> # ℹ 206 more rows
# }
```
