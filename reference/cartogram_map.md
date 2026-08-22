# Area-honest cartogram

Resizes countries by `weight` (population, GDP, ...) via the optional
`cartogram` package, defeating the "big empty countries dominate the
eye" bias of world choropleths.

## Usage

``` r
cartogram_map(
  data,
  weight,
  type = c("contiguous", "dorling", "noncontiguous"),
  fill = NULL,
  projection = "equal_earth",
  ...
)
```

## Arguments

- data:

  An `sf` map-ready frame.

- weight:

  The column to resize by (unquoted).

- type:

  `"contiguous"` (default), `"dorling"` or `"noncontiguous"`.

- fill:

  Optional fill column (unquoted); defaults to `weight`.

- projection:

  Projection; an equal-area CRS is recommended. See
  [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md)
  for the projections available.

- ...:

  Passed to the underlying `cartogram::cartogram_*()` function (e.g.
  `itermax`, or `k` for `type = "dorling"` – see
  [`dorling_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/dorling_map.md)).

## Value

A `ggplot` object.

## Examples

``` r
# \donttest{
if (requireNamespace("sf", quietly = TRUE) &&
    requireNamespace("rnaturalearth", quietly = TRUE) &&
    requireNamespace("cartogram", quietly = TRUE)) {
  attach_geometry(countryatlas::world_snapshot$countries, geometry = "sf") |>
    cartogram_map(population, type = "dorling")
}

# }
```
