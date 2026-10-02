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
tile_map(data, fill, label = TRUE, footnote = "auto")
```

## Arguments

- data:

  A country-level frame with `iso3c` and the `fill` column.

- fill:

  The fill column (unquoted).

- label:

  Whether to draw ISO codes on the tiles (default `TRUE`).

- footnote:

  The caption, as in
  [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md):
  `"auto"` (default) states the coverage and source, a string is used as
  given, `FALSE` adds nothing.

## Value

A `ggplot` object.

## Details

Every tile in the layout is drawn, taking the scale's `na.value` fill
where `data` has no row for it. The converse also holds and is quieter:
`data` rows keyed on one of the 3 countries with no tile are dropped
without a warning (see
[world_tiles](https://pursuitofdatascience.github.io/countryatlas/reference/world_tiles.md)
for which).

## Backend

Drawn on the bundled equal-area tile grid
([world_tiles](https://pursuitofdatascience.github.io/countryatlas/reference/world_tiles.md)),
one square per country; no geometry backend is involved.

## Examples

``` r
# \donttest{
tile_map(countryatlas::world_snapshot$countries, gdp_per_capita)

# }
```
