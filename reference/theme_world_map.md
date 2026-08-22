# A clean theme for world maps

Strips axes, panel grid and background so the map is the focus. Applied
by every plotting function in the package except
[`bivariate_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/bivariate_map.md),
which uses
[`biscale::bi_theme()`](https://chris-prener.github.io/biscale/reference/bi_theme.html)
so the map matches its own legend, and exported here for reuse on plots
you build yourself.

## Usage

``` r
theme_world_map(base_size = 12, base_family = "")
```

## Arguments

- base_size:

  Base font size.

- base_family:

  Base font family.

## Value

A `ggplot2` theme object.

## Examples

``` r
library(ggplot2)
ggplot() + theme_world_map()
```
