# Two-variable bivariate choropleth

A 2-D bivariate choropleth with a built-in 2-D legend (via the optional
`biscale` package), e.g. GDP per capita x life expectancy in one map.

## Usage

``` r
bivariate_map(
  data,
  fill_x,
  fill_y,
  palette = "GrPink",
  dim = 3,
  projection = "equal_earth",
  footnote = "auto"
)
```

## Arguments

- data:

  An `sf` map-ready frame (use `geometry = "sf"`).

- fill_x, fill_y:

  The two value columns (unquoted).

- palette:

  A `biscale` palette name (default `"GrPink"`).

- dim:

  Bivariate dimension: classes per variable, 2, 3 (default) or 4. A 4 x
  4 map needs a palette that has one, such as `"GrPink2"`.

- projection:

  Projection; see
  [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md)
  for the ones available.

- footnote:

  The caption, as in
  [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md):
  `"auto"` (default) states the coverage and source, a string is used as
  given, `FALSE` adds nothing.

## Value

A `ggplot` object (the map; combine with
[`biscale::bi_legend()`](https://chris-prener.github.io/biscale/reference/bi_legend.html)
for a standalone legend).

## Backend

The `sf` backend only, since `biscale` classes an `sf` frame; drawn in
`projection` (Equal Earth by default).

## Examples

``` r
# \donttest{
if (requireNamespace("sf", quietly = TRUE) &&
    requireNamespace("rnaturalearth", quietly = TRUE) &&
    requireNamespace("biscale", quietly = TRUE)) {
  attach_geometry(countryatlas::world_snapshot$countries, geometry = "sf") |>
    bivariate_map(gdp_per_capita, life_expectancy)
}

# }
```
