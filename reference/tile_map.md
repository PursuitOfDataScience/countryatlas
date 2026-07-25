# Equal-area world tile grid

A statebins-style equal-area tile grid of the world (one square per
country) so tiny states are actually visible. Uses the bundled
[world_tiles](https://pursuitofdatascience.github.io/countryatlas/reference/world_tiles.md)
layout. For small multiples of a tile grid, facet the result as you
would any other `ggplot` (or see
[`facet_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/facet_map.md)
for the choropleth equivalent).

## Usage

``` r
tile_map(data, fill, label = TRUE)
```

## Arguments

- data:

  A country-level frame with `iso3c` and the `fill` column.

- fill:

  The fill column (unquoted).

- label:

  Whether to draw ISO codes on the tiles (default `TRUE`).

## Value

A `ggplot` object.

## Examples

``` r
# \donttest{
tile_map(countryatlas::world_snapshot$countries, gdp_per_capita)

# }
```
