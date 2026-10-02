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
carries no centroid for three territories Natural Earth does not draw at
1:50m (Bouvet Island, Gibraltar and the U.S. Minor Outlying Islands);
those inputs return `NA` here. Kosovo, which
[countrycode::codelist](https://rdrr.io/pkg/countrycode/man/codelist.html)
does not carry, has a curated row with a centroid.

## Examples

``` r
distance_between("France", "Germany")
#> [1] 802.3525
distance_between("USA", c("Canada", "Mexico"))
#> [1] 2184.930 1622.586
```
