# Static per-country metadata

One row per country with the facts people constantly need and currently
scrape together by hand.

## Usage

``` r
country_meta
```

## Format

A tibble with one row per country and columns including `iso3c`,
`iso2c`, `country`, `continent`, `region`, `un_region`, `capital`,
`capital_lat`, `capital_lon`, `centroid_lat`, `centroid_lon`,
`area_km2`, `currency`, `tld`, `landlocked`, `flag`.

Assembled from
[countrycode::codelist](https://rdrr.io/pkg/countrycode/man/codelist.html),
so Kosovo (`XKX`) has no row – `countrycode` has none either. The
geometry backends and
[`convert_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/convert_country.md)
do handle it;
[`distance_between()`](https://pursuitofdatascience.github.io/countryatlas/reference/distance_between.md),
which reads its centroids from here, does not. Ten further territories
have a row but no centroid or area.

`country` therefore carries the English names from `countrycode` ("South
Korea", "Congo - Kinshasa"), which differ from the World Bank's for 38
of the 215 countries in
[world_snapshot](https://pursuitofdatascience.github.io/countryatlas/reference/world_snapshot.md)
("Korea, Rep.", "Congo, Dem. Rep."). Each table is faithful to its own
source, so join on `iso3c` and keep whichever label you want to display
– reconciling the two is what
[`country_join()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_join.md)
is for.

## Source

Assembled from countrycode, WDI metadata and Natural Earth geometry.
