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
  methods = c("quantile", "jenks", "fisher", "headtails", "equal", "pretty"),
  n_bins = 5,
  ncol = NULL,
  ...,
  n = deprecated()
)
```

## Arguments

- data:

  A map-ready frame (polygon or `sf`).

- value:

  The value column (unquoted).

- methods:

  Classification styles to compare. Any of `"quantile"`, `"jenks"`,
  `"fisher"`, `"headtails"`, `"equal"`, `"pretty"` and `"sd"`, with the
  breaks
  [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md)
  would draw for each. `"jenks"` and `"fisher"` need the optional
  `classInt`; without it they fall back to quantile breaks with a
  warning.

- n_bins:

  Number of classes (default `5`), as the map verbs call it;
  `"headtails"` and `"pretty"` choose their own.

- ncol:

  Number of facet columns.

- ...:

  Passed to
  [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md).

- n:

  **\[deprecated\]** Use `n_bins`.

## Value

A faceted `ggplot` object, with the per-method break and class-count
table attached as the `"countryatlas_classification"` attribute (and
readable with
[`map_provenance()`](https://pursuitofdatascience.github.io/countryatlas/reference/map_provenance.md)).
Each method's rows also carry three measures of fit: `gvf`, the goodness
of variance fit, and `tai`, the tabular accuracy index (both Jenks &
Caspall 1971; 1 is a perfect fit), and `max_class_share`, the share of
countries in the fullest class.

## No number picks a classification

GVF and TAI measure how homogeneous the classes are, which is what
natural breaks optimise; they rate a map that puts most countries in one
class highly, and they say nothing about how well readers read the map.
They are reported to inform the choice, never to rank the methods:
Brewer & Pickle's finding that quantiles read best stands beside them,
and `max_class_share` flags the map whose fullest class swallows the
rest.

## References

Brewer, C. A. & Pickle, L. (2002). Evaluation of methods for classifying
epidemiological data on choropleth maps in series. *Annals of the
Association of American Geographers* 92(4), 662-681.
[doi:10.1111/1467-8306.00310](https://doi.org/10.1111/1467-8306.00310)

Jenks, G. F. & Caspall, F. C. (1971). Error on choroplethic maps:
definition, measurement, reduction. *Annals of the Association of
American Geographers* 61(2), 217-244.
[doi:10.1111/j.1467-8306.1971.tb00779.x](https://doi.org/10.1111/j.1467-8306.1971.tb00779.x)

Jiang, B. (2013). Head/tail breaks: a new classification scheme for data
with a heavy-tailed distribution. *The Professional Geographer* 65(3),
482-494.
[doi:10.1080/00330124.2012.700499](https://doi.org/10.1080/00330124.2012.700499)

## See also

[`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md),
[`map_provenance()`](https://pursuitofdatascience.github.io/countryatlas/reference/map_provenance.md)

## Examples

``` r
# \donttest{
snap <- countryatlas::world_snapshot$countries
cmp <- attach_geometry(snap, geometry = "polygon") |>
  classify_compare(gdp_per_capita)
attr(cmp, "countryatlas_classification")
#> # A tibble: 30 × 7
#>    method   class              n   share   gvf   tai max_class_share
#>    <chr>    <chr>          <int>   <dbl> <dbl> <dbl>           <dbl>
#>  1 quantile 269 to 1.68K      40 0.201   0.626 0.672           0.201
#>  2 quantile 1.68K to 4.65K    40 0.201   0.626 0.672           0.201
#>  3 quantile 4.65K to 10.3K    39 0.196   0.626 0.672           0.201
#>  4 quantile 10.3K to 30.1K    40 0.201   0.626 0.672           0.201
#>  5 quantile 30.1K to 247K     40 0.201   0.626 0.672           0.201
#>  6 jenks    269 to 13.1K     129 0.648   0.958 0.756           0.648
#>  7 jenks    13.1K to 34.8K    38 0.191   0.958 0.756           0.648
#>  8 jenks    34.8K to 68.1K    25 0.126   0.958 0.756           0.648
#>  9 jenks    68.1K to 117K      6 0.0302  0.958 0.756           0.648
#> 10 jenks    117K to 247K       1 0.00503 0.958 0.756           0.648
#> # ℹ 20 more rows
# }
```
