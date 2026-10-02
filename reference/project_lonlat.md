# Project longitude and latitude onto a countryatlas map

The transform the polygon backend uses when `sf` cannot be loaded: a
spherical Equal Earth (Savric, Patterson & Jenny 2019) on the authalic
sphere, written out in base R so the default map is equal-area on any
installation. Use it to place your own points, labels or paths on such a
map, which is drawn in metres rather than degrees. Where `sf` loads,
maps are drawn with
[`ggplot2::coord_sf()`](https://ggplot2.tidyverse.org/reference/ggsf.html)
instead and take layers in longitude and latitude directly, so there is
nothing to convert.

## Usage

``` r
project_lonlat(lon, lat, projection = "equal_earth", recenter = NULL)
```

## Arguments

- lon, lat:

  Numeric vectors of longitude and latitude, in degrees.

- projection:

  `"equal_earth"` (default), computed here. Any other projection the
  package knows (see
  [`projection_info()`](https://pursuitofdatascience.github.io/countryatlas/reference/projection_info.md))
  is computed by PROJ through `sf`, which must then be loadable.

- recenter:

  Optional central meridian, as in
  [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md).

## Value

A tibble of `x` and `y`, in metres, one row per point; `NA` where a
coordinate is missing.

## References

Savric, B., Patterson, T. & Jenny, B. (2019). The Equal Earth map
projection. *International Journal of Geographical Information Science*
33(3), 454-465.
[doi:10.1080/13658816.2018.1504949](https://doi.org/10.1080/13658816.2018.1504949)

## See also

[`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md),
[`zoom_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/zoom_map.md)

## Examples

``` r
project_lonlat(c(2.35, -74.0), c(48.85, 40.7))   # Paris, New York
#> # A tibble: 2 × 2
#>           x        y
#>       <dbl>    <dbl>
#> 1   187424. 5882067.
#> 2 -6255450. 5012972.
```
