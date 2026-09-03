# Map the data availability itself

A choropleth of *whether* a value is present, rather than what it is.
The companion to
[`audit_coverage()`](https://pursuitofdatascience.github.io/countryatlas/reference/audit_coverage.md),
which reports the same thing as a table: a world map with a large
well-covered region and a systematically empty one is telling you
something about the indicator that the headline map hides behind a
uniform grey.

## Usage

``` r
coverage_map(data, value, by = NULL, title = NULL, ...)
```

## Arguments

- data:

  A map-ready frame (polygon or `sf`).

- value:

  The column whose availability to map (unquoted).

- by:

  Optional grouping column for a panel: with a `year` column, use
  `by = year` to see coverage change over time.

- title:

  Optional plot title (defaults to a generated one).

- ...:

  Passed to
  [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md).

## Value

A `ggplot` object.

## See also

[`audit_coverage()`](https://pursuitofdatascience.github.io/countryatlas/reference/audit_coverage.md),
[`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md)

## Examples

``` r
# \donttest{
snap <- countryatlas::world_snapshot$countries
if (requireNamespace("maps", quietly = TRUE)) {
  attach_geometry(snap, geometry = "polygon") |>
    coverage_map(gdp_per_capita)
}

# }
```
