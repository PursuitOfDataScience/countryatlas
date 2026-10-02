# Small-multiple choropleths

Facet a choropleth into small multiples (one panel per group or per
year) – the static counterpart to
[`animate_world()`](https://pursuitofdatascience.github.io/countryatlas/reference/animate_world.md),
for print and side-by-side comparison. Builds a
[`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md)
and facets it on `facet`.

## Usage

``` r
facet_map(
  data,
  fill,
  facet,
  ncol = NULL,
  breaks_by = c("pooled", "panel"),
  ...
)
```

## Arguments

- data:

  A map-ready frame (polygon or sf) containing the `facet` column.

- fill:

  The fill column (unquoted).

- facet:

  The faceting column (unquoted; e.g. `year` or `continent`).

- ncol:

  Number of facet columns (passed to
  [`ggplot2::facet_wrap()`](https://ggplot2.tidyverse.org/reference/facet_wrap.html)).

- breaks_by:

  `"pooled"` (default) classifies every panel together, with one set of
  breaks, so the same colour means the same value in every panel and the
  panels can be compared. `"panel"` classifies each panel on its own
  values – each country's class within its own year – and the legend
  says so; colours are then comparable as ranks, not as values.

- ...:

  Passed to
  [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md)
  (e.g. `style`, `projection`).

## Value

A faceted `ggplot` object.

## Backend

Either backend, as
[`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md):
the frame decides, and both draw in `projection` (Equal Earth by
default).

## Examples

``` r
# \donttest{
snap <- countryatlas::world_snapshot$countries
mapdf <- attach_geometry(snap, geometry = "polygon")
facet_map(mapdf, gdp_per_capita, continent, style = "quantile")

# }
```
