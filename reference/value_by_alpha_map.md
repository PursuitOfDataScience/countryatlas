# Value-by-alpha: equalise a rate by its denominator

A choropleth where colour carries the value and **opacity** carries an
equalising variable (usually population), over a neutral background. It
is the answer to the small-number problem – a rate computed over eleven
thousand people shouts as loudly as one computed over a billion – and
unlike a cartogram it solves it **without distorting geometry**, which
is the main objection to cartograms. Roth, Woodruff & Johnson (2010)
introduced it for exactly this purpose.

## Usage

``` r
value_by_alpha_map(
  data,
  value,
  equalize,
  style = c("quantile", "continuous", "binned", "jenks"),
  palette = NULL,
  n_bins = 5,
  alpha_range = c(0.15, 1),
  transform = c("rank", "log10", "identity"),
  background = "grey20",
  title = NULL,
  legend = NULL,
  projection = "equal_earth"
)
```

## Arguments

- data:

  A map-ready frame (polygon or `sf`).

- value:

  The value column, carried by colour (unquoted).

- equalize:

  The equalising column, carried by opacity (unquoted) – population,
  total counts, or whatever denominator the rate was built on.

- style:

  Classification for the colour channel (as
  [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md)).

- palette:

  Optional viridis palette name.

- n_bins:

  Number of colour bins for the binned styles.

- alpha_range:

  Minimum and maximum opacity (default `c(0.15, 1)`).

- transform:

  Transform applied to `equalize` before it is mapped to opacity:
  `"rank"` (default, robust to the extreme skew of population),
  `"log10"` or `"identity"`.

- background:

  Colour behind the countries, which shows through where opacity is low
  (default a dark neutral).

- title, legend:

  Optional plot title and legend title.

- projection:

  Projection for the `sf` backend.

## Value

A `ggplot` object.

## References

Roth, R. E., Woodruff, A. W. & Johnson, Z. F. (2010). Value-by-alpha
maps: an alternative technique to the cartogram. *The Cartographic
Journal* 47(2), 130-140.
[doi:10.1179/000870409X12488753453372](https://doi.org/10.1179/000870409X12488753453372)

## See also

[`cartogram_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/cartogram_map.md)
and
[`dorling_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/dorling_map.md)
(the geometry-distorting answers to the same problem),
[`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md)

## Examples

``` r
# \donttest{
snap <- countryatlas::world_snapshot$countries
if (requireNamespace("maps", quietly = TRUE)) {
  attach_geometry(snap, geometry = "polygon") |>
    value_by_alpha_map(gdp_per_capita, population)
}

# }
```
