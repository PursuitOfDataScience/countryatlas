# Dorling cartogram (first-class verb)

Non-overlapping proportional circles sized by `weight`, positioned to
stay as close as possible to each country's true location – arguably the
most legible cartogram variant, since a microstate's circle is exactly
as visible as a giant country's. A first-class verb for
[`cartogram_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/cartogram_map.md)`(type = "dorling")`
that surfaces the Dorling-specific tuning knobs.

## Usage

``` r
dorling_map(
  data,
  weight,
  fill = NULL,
  k = 5,
  itermax = 1000,
  projection = "equal_earth"
)
```

## Arguments

- data:

  An `sf` map-ready frame.

- weight:

  The column controlling circle size (unquoted).

- fill:

  Optional fill column (unquoted); defaults to `weight`.

- k:

  Share of the bounding box filled by the largest circle (default `5`;
  passed to
  [`cartogram::cartogram_dorling()`](https://rdrr.io/pkg/cartogram/man/cartogram_dorling.html)).

- itermax:

  Maximum iterations of the circle-repulsion algorithm (default `1000`;
  raise it if circles still overlap in the result).

- projection:

  Projection; an equal-area CRS is recommended. See
  [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md)
  for the projections available.

## Value

A `ggplot` object.

## Examples

``` r
# \donttest{
if (requireNamespace("sf", quietly = TRUE) &&
    requireNamespace("rnaturalearth", quietly = TRUE) &&
    requireNamespace("cartogram", quietly = TRUE)) {
  attach_geometry(countryatlas::world_snapshot$countries, geometry = "sf") |>
    dorling_map(population)
}

# }
```
