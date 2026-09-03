# Measure what a projection distorts

The numeric companion to
[`tissot_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/tissot_map.md):
distortion sampled on a grid, so it can be summarised, compared or
mapped rather than eyeballed. Computed by projecting a small circle at
each grid point and measuring what happens to it, which is the
definition rather than an approximation of it.

## Usage

``` r
projection_distortion(
  projection = "equal_earth",
  measure = c("areal", "angular", "max_scale"),
  spacing = 10,
  max_lat = 85
)
```

## Arguments

- projection:

  Projection to measure (see
  [`projection_info()`](https://pursuitofdatascience.github.io/countryatlas/reference/projection_info.md)).

- measure:

  `"areal"` (default; projected area divided by true ground area, so 1
  is undistorted), `"angular"` (maximum angular deformation in degrees,
  0 for a conformal projection) or `"max_scale"` (the larger principal
  scale factor).

- spacing:

  Grid spacing in degrees (default `10`).

- max_lat:

  Absolute latitude limit (default `85`).

## Value

A tibble of `lon`, `lat` and `distortion`, with the area-weighted mean
and the range attached as the `"countryatlas_distortion"` attribute.

## Reading the numbers

An equal-area projection has `"areal"` distortion of 1 everywhere – that
is what equal-area *means*, and it is worth checking rather than
trusting. A conformal projection has `"angular"` distortion of 0
everywhere and unbounded areal distortion. A compromise projection is
bad at both by a little, everywhere, which is the trade it makes.

## See also

[`tissot_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/tissot_map.md),
[`projection_info()`](https://pursuitofdatascience.github.io/countryatlas/reference/projection_info.md),
[`projection_compare()`](https://pursuitofdatascience.github.io/countryatlas/reference/projection_compare.md)

## Examples

``` r
# \donttest{
if (requireNamespace("sf", quietly = TRUE)) {
  d <- projection_distortion("mercator", measure = "areal")
  attr(d, "countryatlas_distortion")
}
#> # A tibble: 1 × 5
#>   projection measure  mean   min   max
#>   <chr>      <chr>   <dbl> <dbl> <dbl>
#> 1 mercator   areal    4.40  1.00  132.
# }
```
