# Zoom a map without losing its projection

Show part of a map by longitude and latitude limits while keeping the
projection it was drawn in. The 3.0.0 documentation zoomed with
`coord_quickmap(xlim, ylim)`, which on a projected map silently replaces
the projection with an unprojected one.

## Usage

``` r
zoom_map(p, xlim, ylim)
```

## Arguments

- p:

  A map from one of the package's map verbs.

- xlim, ylim:

  Longitude and latitude limits, in degrees, each a pair `c(min, max)`.

## Value

`p` with the view limited, in the same projection.

## See also

[`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md),
[`project_lonlat()`](https://pursuitofdatascience.github.io/countryatlas/reference/project_lonlat.md)

## Examples

``` r
# \donttest{
snap <- countryatlas::world_snapshot$countries
europe <- attach_geometry(snap, geometry = "polygon") |>
  world_map(gdp_per_capita)
zoom_map(europe, xlim = c(-25, 45), ylim = c(34, 72))

# }
```
