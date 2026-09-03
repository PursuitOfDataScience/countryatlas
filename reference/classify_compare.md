# The same map under several classifications

Small multiples of one choropleth, drawn once per classification method,
plus the break table and the count of countries in each class. The point
is that the choice is consequential and usually unexamined: Brewer &
Pickle (2002) found quantiles among the best methods for general
choropleth reading and natural breaks (Jenks) below 70% as accurate,
which is the reverse of the common GIS default.

## Usage

``` r
classify_compare(
  data,
  value,
  methods = c("quantile", "jenks", "equal", "pretty"),
  n = 5,
  ncol = NULL,
  ...
)
```

## Arguments

- data:

  A map-ready frame (polygon or `sf`).

- value:

  The value column (unquoted).

- methods:

  Classification styles to compare. Any of `"quantile"`, `"jenks"`,
  `"equal"`, `"pretty"` and `"sd"`. `"jenks"` needs the optional
  `classInt`; without it, it falls back to quantile breaks with a
  warning.

- n:

  Number of classes (default `5`).

- ncol:

  Number of facet columns.

- ...:

  Passed to
  [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md).

## Value

A faceted `ggplot` object, with the per-method break and class-count
table attached as the `"countryatlas_classification"` attribute (and
readable with
[`map_provenance()`](https://pursuitofdatascience.github.io/countryatlas/reference/map_provenance.md)).

## References

Brewer, C. A. & Pickle, L. (2002). Evaluation of methods for classifying
epidemiological data on choropleth maps in series. *Annals of the
Association of American Geographers* 92(4), 662-681.
[doi:10.1111/1467-8306.00310](https://doi.org/10.1111/1467-8306.00310)

## See also

[`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md),
[`map_provenance()`](https://pursuitofdatascience.github.io/countryatlas/reference/map_provenance.md)

## Examples

``` r
# \donttest{
snap <- countryatlas::world_snapshot$countries
if (requireNamespace("maps", quietly = TRUE)) {
  cmp <- attach_geometry(snap, geometry = "polygon") |>
    classify_compare(gdp_per_capita)
  attr(cmp, "countryatlas_classification")
}
#> # A tibble: 20 × 4
#>    method   class                     n   share
#>    <chr>    <chr>                 <int>   <dbl>
#>  1 quantile [268.7,1662]             38 0.201  
#>  2 quantile (1662,4594]              38 0.201  
#>  3 quantile (4594,1.029e+04]         37 0.196  
#>  4 quantile (1.029e+04,2.937e+04]    38 0.201  
#>  5 quantile (2.937e+04,2.472e+05]    38 0.201  
#>  6 jenks    [268.7,1.312e+04]       123 0.651  
#>  7 jenks    (1.312e+04,3.484e+04]    37 0.196  
#>  8 jenks    (3.484e+04,6.771e+04]    23 0.122  
#>  9 jenks    (6.771e+04,1.221e+05]     5 0.0265 
#> 10 jenks    (1.221e+05,2.472e+05]     1 0.00529
#> 11 equal    [268.7,4.965e+04]       173 0.915  
#> 12 equal    (4.965e+04,9.903e+04]    13 0.0688 
#> 13 equal    (9.903e+04,1.484e+05]     2 0.0106 
#> 14 equal    (1.484e+05,1.978e+05]     0 0      
#> 15 equal    (1.978e+05,2.472e+05]     1 0.00529
#> 16 pretty   [0,5e+04]               173 0.915  
#> 17 pretty   (5e+04,1e+05]            13 0.0688 
#> 18 pretty   (1e+05,1.5e+05]           2 0.0106 
#> 19 pretty   (1.5e+05,2e+05]           0 0      
#> 20 pretty   (2e+05,2.5e+05]           1 0.00529
# }
```
