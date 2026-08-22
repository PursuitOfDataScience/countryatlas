# Animate a choropleth over time

Given a panel from `world_data(2000:2020, ...)`, animate the choropleth
over `year` via the optional `gganimate` package, or fall back to a
faceted small-multiple when it is not installed.

## Usage

``` r
animate_world(data, fill, time = year, projection = "equal_earth", ...)
```

## Arguments

- data:

  A panel map-ready frame (polygon or sf) with a `time` column.

- fill:

  The fill column (unquoted).

- time:

  The time column (unquoted; default `year`).

- projection:

  Projection for the sf backend. See
  [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md)
  for the projections available.

- ...:

  Passed to
  [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md).

## Value

A `gganim` object (if `gganimate` is available) or a faceted `ggplot`.

## Examples

``` r
if (FALSE) { # \dontrun{
world_data(2000:2005, c(gdp = "NY.GDP.PCAP.KD")) |>
  animate_world(gdp)
} # }
```
