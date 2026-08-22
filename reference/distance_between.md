# Great-circle distance between two countries

Haversine distance (km) between two countries' centroids – the
lightweight companion to
[`country_borders()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_borders.md)
for "how far apart" rather than "do they touch". Works from the bundled
[country_meta](https://pursuitofdatascience.github.io/countryatlas/reference/country_meta.md)
centroids, so unlike most of the spatial toolkit it needs neither `sf`
nor the network.

## Usage

``` r
distance_between(a, b, origin = "country.name")
```

## Arguments

- a, b:

  Vectors of country names or codes. Either the same length, or one of
  them length 1 to compare one country against many.

- origin:

  How to read `a`/`b` (default `"country.name"`).

## Value

A numeric vector of great-circle distances in kilometres (`NA` for any
country that doesn't resolve to a known centroid).

## Countries without a bundled centroid

[country_meta](https://pursuitofdatascience.github.io/countryatlas/reference/country_meta.md)
carries no centroid for a handful of small or dependent territories
(Bouvet Island, the British Virgin Islands, Gibraltar, Hong Kong, Macao,
Svalbard and Jan Mayen, Tokelau, Tuvalu, the U.S. Minor Outlying Islands
and the Aland Islands), and no row at all for Kosovo, because
[countrycode::codelist](https://rdrr.io/pkg/countrycode/man/codelist.html)
has none. Those inputs return `NA` here even though the geometry
backends do map them – so
[`neighbors()`](https://pursuitofdatascience.github.io/countryatlas/reference/neighbors.md)
and
[`country_borders()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_borders.md)
know about Kosovo while this function does not.

## Examples

``` r
distance_between("France", "Germany")
#> [1] 802.3524
distance_between("USA", c("Canada", "Mexico"))
#> [1] 2184.930 1622.586
```
