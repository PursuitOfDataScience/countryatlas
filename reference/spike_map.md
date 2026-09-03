# Spike map (heights at country centroids)

The classic "population spikes" display: a triangular spike at each
country centroid whose height encodes the value. Like
[`bubble_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/bubble_map.md)
it is the honest idiom for *totals*, with a different visual trade-off:
spikes overplot less in dense regions (Europe, the Caribbean) because
they only grow upward. Uses the polygon backend, so it needs only
`maps`.

## Usage

``` r
spike_map(
  data,
  height,
  max_height = 20,
  width = 1.6,
  color = "#B2182B",
  alpha = 0.65
)
```

## Arguments

- data:

  A country-level frame with `iso3c` and the `height` column.

- height:

  The column controlling spike height (unquoted).

- max_height:

  Height of the tallest spike, in degrees of latitude (default `20`).

- width:

  Base width of each spike, in degrees of longitude (default `1.6`).

- color:

  Spike colour (default a warm red).

- alpha:

  Spike fill transparency.

## Value

A `ggplot` object.

## Examples

``` r
# \donttest{
if (requireNamespace("maps", quietly = TRUE)) {
  spike_map(countryatlas::world_snapshot$countries, population)
}
#> Warning: population: 5 countries are not drawn -- no bundled centroid.
#> • "GIB", "HKG", "MAC", "TUV", and "VGB"
#> ℹ They are counted as missing in the caption and in `map_provenance()`.

# }
```
