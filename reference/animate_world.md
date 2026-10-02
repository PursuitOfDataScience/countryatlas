# Animate a choropleth over time

Given a panel from `world_data(2000:2020, ...)`, animate the choropleth
over `year` via the optional `gganimate` package, or fall back to a
faceted small-multiple when it is not installed.

## Usage

``` r
animate_world(
  data,
  fill,
  time = year,
  projection = "equal_earth",
  breaks_by = c("pooled", "panel"),
  ...
)
```

## Arguments

- data:

  A panel map-ready frame (polygon or sf) with a `time` column.

- fill:

  The fill column (unquoted).

- time:

  The time column (unquoted; default `year`).

- projection:

  Projection; see
  [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md)
  for the projections available.

- breaks_by:

  `"pooled"` (default) classifies every panel together, with one set of
  breaks, so the same colour means the same value in every panel and the
  panels can be compared. `"panel"` classifies each panel on its own
  values – each country's class within its own year – and the legend
  says so; colours are then comparable as ranks, not as values.

- ...:

  Passed to
  [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md).

## Value

A `gganim` object (if `gganimate` is available) or a faceted `ggplot`.

## Backend

Either backend, as
[`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md):
the frame decides, and both draw in `projection` (Equal Earth by
default).

## Examples

``` r
if (FALSE) { # \dontrun{
world_data(2000:2005, c(gdp = "NY.GDP.PCAP.KD")) |>
  animate_world(gdp)
} # }
```
