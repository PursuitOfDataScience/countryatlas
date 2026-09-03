# Everything the package knows about one country

A single-country summary drawn from the bundled reference data and, if
you ask, live indicators: codes, geography, groups, neighbours and any
dissolution history.

## Usage

``` r
country_factsheet(x, indicators = NULL, origin = "country.name")
```

## Arguments

- x:

  One country name or code.

- indicators:

  Optional indicator codes to fetch (named, as in
  [`world_data()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_data.md)).
  Needs the network. `NULL` (default) uses the bundled
  [world_snapshot](https://pursuitofdatascience.github.io/countryatlas/reference/world_snapshot.md)
  and stays offline.

- origin:

  How to read `x` (default `"country.name"`).

## Value

A `countryatlas_factsheet` object – a list of tibbles (`identity`,
`geography`, `groups`, `neighbours`, `indicators`) that prints as a
formatted block.

## See also

[country_meta](https://pursuitofdatascience.github.io/countryatlas/reference/country_meta.md),
[`country_groups()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_groups.md),
[`neighbors()`](https://pursuitofdatascience.github.io/countryatlas/reference/neighbors.md),
[`world_table()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_table.md)

## Examples

``` r
country_factsheet("Brazil")
#> 
#> ── Brazil (BRA) ──
#> 
#> iso3c: BRA
#> iso2c: BR
#> country: Brazil
#> continent: Americas
#> region: Latin America & Caribbean
#> capital: Brasilia
#> currency: BRL
#> flag: 🇧🇷
#> tld: .br
#> 
#> ── Geography 
#> area_km2: 8499361
#> centroid_lon: -54.4
#> centroid_lat: -14.24
#> landlocked: FALSE
#> 
#> ── Groups 
#> BRICS, G20, Mercosur
#> 
#> ── Land neighbours (10) 
#> Uruguay, Peru, Colombia, Venezuela, Guyana, Suriname, France, Paraguay,
#> Argentina, Bolivia
#> 
#> ── Indicators 
#> gdp_per_capita: 9566.7
#> population: 212000000
#> life_expectancy: 76.023
#> co2_per_capita: 2.3183
```
