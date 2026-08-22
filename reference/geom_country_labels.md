# Centroid-anchored country labels

A `ggplot2` layer that places labels (names, ISO codes or flag emoji) at
country centroids, with optional `ggrepel` collision avoidance. Designed
for the polygon backend produced by
[`world_data()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_data.md)
/
[`join_world()`](https://pursuitofdatascience.github.io/countryatlas/reference/join_world.md):
it reads the `long`, `lat` and `group` columns, so it errors on an `sf`
frame and points at
[`ggplot2::geom_sf_text()`](https://ggplot2.tidyverse.org/reference/ggsf.html)
instead. Placement is exact only while `group` is present – that is what
identifies each country's separate pieces, and the label goes on the
largest one.

## Usage

``` r
geom_country_labels(mapping = NULL, repel = TRUE, flag = FALSE, size = 3, ...)
```

## Arguments

- mapping:

  Aesthetic mapping; defaults to `aes(label = iso3c)`.

- repel:

  Use `ggrepel` to avoid overlaps (default `TRUE`). Falls back to plain
  labels, with a one-time note, when `ggrepel` is not installed.

- flag:

  If `TRUE`, label with flag emoji instead of the mapped label.

- size:

  Label text size.

- ...:

  Passed to the underlying text geom.

## Value

A `ggplot2` layer.

## Examples

``` r
# \donttest{
library(ggplot2)
snap <- countryatlas::world_snapshot$countries
if (requireNamespace("maps", quietly = TRUE)) {
  mapdf <- attach_geometry(snap, geometry = "polygon")
  world_map(mapdf, gdp_per_capita) + geom_country_labels()
}

# }
```
