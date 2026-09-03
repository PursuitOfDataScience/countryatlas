# Did the cartogram actually converge?

Cartograms fail quietly. An under-converged one looks entirely plausible
while still misrepresenting the areas it exists to make honest. This
reports the residual error per country, so the failure is visible.

## Usage

``` r
cartogram_diagnostics(x, weight = NULL)
```

## Arguments

- x:

  A `ggplot` from
  [`cartogram_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/cartogram_map.md)
  or
  [`dorling_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/dorling_map.md),
  or the `sf` frame the cartogram was computed from.

- weight:

  The weight column (unquoted). Required when `x` is a plain `sf` frame;
  read from the plot otherwise.

## Value

A tibble of `iso3c`, `target_share` (the country's share of the weight),
`actual_share` (its share of the cartogram's area) and `area_error` (the
relative difference). The summary – mean absolute error, worst country –
is attached as the `"countryatlas_cartogram"` attribute.

## What counts as converged

A perfect cartogram has `area_error` of 0 everywhere. In practice a mean
absolute error under a few percent is good and under 10% is usually
acceptable; a systematically large error, or one concentrated in the
small countries, means the algorithm stopped early. Raise `itermax` and
try again.

## See also

[`cartogram_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/cartogram_map.md),
[`dorling_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/dorling_map.md),
[`gridded_cartogram()`](https://pursuitofdatascience.github.io/countryatlas/reference/gridded_cartogram.md)

## Examples

``` r
# \donttest{
if (requireNamespace("sf", quietly = TRUE) &&
    requireNamespace("cartogram", quietly = TRUE) &&
    requireNamespace("rnaturalearth", quietly = TRUE)) {
  sfd <- attach_geometry(countryatlas::world_snapshot$countries,
                         geometry = "sf")
  cg <- cartogram_map(sfd, population)
  cartogram_diagnostics(cg)
}
#> # A tibble: 170 × 4
#>    iso3c target_share actual_share area_error
#>    <chr>        <dbl>        <dbl>      <dbl>
#>  1 GRL     0.00000702    0.00262      371.   
#>  2 BTN     0.0000978     0.000509       4.20 
#>  3 RUS     0.0177        0.0496         1.80 
#>  4 GUY     0.000103      0.000257       1.50 
#>  5 ISL     0.0000477     0.000101       1.11 
#>  6 NOR     0.000688      0.00144        1.10 
#>  7 NZL     0.000653      0.00133        1.03 
#>  8 CAN     0.00510       0.0103         1.03 
#>  9 LAO     0.000960      0.00177        0.844
#> 10 BHS     0.0000496     0.0000905      0.825
#> # ℹ 160 more rows
# }
```
