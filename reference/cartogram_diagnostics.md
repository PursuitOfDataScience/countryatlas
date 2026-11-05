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
  # One continent keeps the example quick; the world takes 20 seconds.
  africa <- subset(countryatlas::world_snapshot$countries,
                   continent == "Africa")
  cg <- cartogram_map(attach_geometry(africa, geometry = "sf"), population)
  cartogram_diagnostics(cg)
}
#> # A tibble: 49 × 4
#>    iso3c target_share actual_share area_error
#>    <chr>        <dbl>        <dbl>      <dbl>
#>  1 NAM        0.00201      0.00332     0.653 
#>  2 RWA        0.00945      0.00386    -0.591 
#>  3 BDI        0.00931      0.00431    -0.537 
#>  4 CAF        0.00353      0.00454     0.286 
#>  5 LBY        0.00489      0.00616     0.259 
#>  6 COG        0.00420      0.00510     0.216 
#>  7 TGO        0.00557      0.00643     0.154 
#>  8 MRT        0.00343      0.00375     0.0959
#>  9 ERI        0.00234      0.00252     0.0775
#> 10 NGA        0.154        0.145      -0.0620
#> # ℹ 39 more rows
# }
```
