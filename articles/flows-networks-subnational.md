# Flows, networks and subnational data

Origin-destination data – trade, migration, remittances – keys on two
countries per row.
[`flow_matrix()`](https://pursuitofdatascience.github.io/countryatlas/reference/flow_matrix.md)
and
[`country_network()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_network.md)
reconcile both ends on the ISO spine;
[`flow_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/flow_map.md)
and
[`od_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/od_map.md)
draw them.

``` r

od <- data.frame(from = c("China", "China", "Germany", "United States"),
                 to = c("United States", "Japan", "France", "Mexico"),
                 value = c(500, 200, 80, 300))
flow_matrix(od, from, to, value)
#>     CHN DEU FRA JPN MEX USA
#> CHN   0   0   0 200   0 500
#> DEU   0   0  80   0   0   0
#> FRA   0   0   0   0   0   0
#> JPN   0   0   0   0   0   0
#> MEX   0   0   0   0   0   0
#> USA   0   0   0   0 300   0
```

``` r

flow_map(od, from, to, value)
```

![Great-circle arcs between four pairs of
countries.](flows-networks-subnational_files/figure-html/unnamed-chunk-3-1.png)

``` r

od_map(od, from, to, value, origins = 2)
```

![One small map per origin, shading each destination by
flow.](flows-networks-subnational_files/figure-html/unnamed-chunk-4-1.png)

Below the country,
[`standardize_subnational()`](https://pursuitofdatascience.github.io/countryatlas/reference/standardize_subnational.md),
[`nuts_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/nuts_geometry.md)
and
[`subnational_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/subnational_map.md)
do the same for regions (NUTS in Europe, ISO 3166-2 elsewhere); see
their help pages.
