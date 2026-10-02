# Static per-country metadata

One row per country with the facts people constantly need and currently
scrape together by hand.

## Usage

``` r
country_meta
```

## Format

A tibble with one row per country and columns `iso3c`, `iso2c`,
`country`, `continent`, `region`, `un_region`, `income`, `capital`,
`capital_lat`, `capital_lon`, `centroid_lat`, `centroid_lon`,
`area_km2`, `currency`, `tld`, `landlocked`, `flag`.

Assembled from
[countrycode::codelist](https://rdrr.io/pkg/countrycode/man/codelist.html),
plus a curated row for Kosovo (`XKX`), which `countrycode` does not
carry, so
[`distance_between()`](https://pursuitofdatascience.github.io/countryatlas/reference/distance_between.md)
and the k-nearest-neighbour weights can use it. Centroids and areas come
from the bundled Natural Earth 1:50m polygons, the ones the polygon
backend draws, with each country's holes taken out; territories drawn as
part of their country (French Guiana, Svalbard) take theirs from Natural
Earth's map units. Three territories have a row but no centroid or area,
because Natural Earth does not draw them at 1:50m: Bouvet Island,
Gibraltar and the U.S. Minor Outlying Islands.

`income` and `region` are the World Bank's for the current fiscal year
(the `"classification"` attribute names it, `"FY2027"`), from
[country_classifications](https://pursuitofdatascience.github.io/countryatlas/reference/country_classifications.md),
so they agree with what
[`world_data()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_data.md)
returns; `region` falls back to `countrycode`'s where the World Bank
lists no region.

`country` therefore carries the English names from `countrycode` ("South
Korea", "Congo - Kinshasa"), which differ from the World Bank's for 39
of the 216 countries in
[world_snapshot](https://pursuitofdatascience.github.io/countryatlas/reference/world_snapshot.md)
("Korea, Rep.", "Congo, Dem. Rep."). Each table is faithful to its own
source, so join on `iso3c` and keep whichever label you want to display
– reconciling the two is what
[`country_join()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_join.md)
is for.

## Source

Assembled from countrycode, WDI metadata (capitals), the World Bank's
classifications and Natural Earth geometry.
