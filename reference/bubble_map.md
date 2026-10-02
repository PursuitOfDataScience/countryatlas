# Proportional-symbol (bubble) map

Plots sized circles at country centroids – the right idiom for *totals*
(population, total emissions, total GDP), which a choropleth
misrepresents because big values hide in small countries and vice versa.

## Usage

``` r
bubble_map(
  data,
  size,
  color = NULL,
  projection = "equal_earth",
  backend = c("polygon", "sf"),
  max_size = 18,
  alpha = 0.7,
  footnote = "auto"
)
```

## Arguments

- data:

  A country-level frame with `iso3c` and the `size` column.

- size:

  The column controlling bubble size (unquoted).

- color:

  Optional column controlling bubble colour (unquoted).

- projection:

  Projection for the base map (sf path). See
  [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md)
  for the projections available.

- backend:

  `"polygon"` (default) or `"sf"` for the base map.

- max_size:

  Largest bubble size.

- alpha:

  Bubble transparency.

- footnote:

  The caption: `"auto"` (default) states the coverage and source, a
  string is used as given, `FALSE` adds nothing. See
  [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md).

## Value

A `ggplot` object.

## Examples

``` r
# \donttest{
snap <- countryatlas::world_snapshot$countries
bubble_map(snap, population)
#> Warning: population: 1 country is not drawn -- no bundled centroid.
#> • "GIB"
#> ℹ They are counted as missing in the caption and in `map_provenance()`.

# }
```
