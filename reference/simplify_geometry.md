# Simplify (thin) geometry for faster plotting

Reduce the vertex count of an `sf` object via the optional `rmapshaper`
package (falling back to
[`sf::st_simplify()`](https://r-spatial.github.io/sf/reference/geos_unary.html)),
for fast web/plotting.

## Usage

``` r
simplify_geometry(x, keep = 0.05, ...)
```

## Arguments

- x:

  An `sf` object.

- keep:

  Proportion of vertices to keep: greater than 0 and at most 1
  (`keep = 0` would leave nothing to draw and errors). Honoured as a
  proportion only by `rmapshaper`; without it the
  [`sf::st_simplify()`](https://r-spatial.github.io/sf/reference/geos_unary.html)
  fallback can work only from a distance tolerance, so `keep` is
  approximated (scaled to the object's extent) and simplifies less
  aggressively. Install `rmapshaper` for proportional control.

- ...:

  Passed to the underlying simplifier.

## Value

A simplified `sf` object.

## Examples

``` r
# \donttest{
if (requireNamespace("sf", quietly = TRUE) &&
    requireNamespace("rnaturalearth", quietly = TRUE)) {
  world_geometry(geometry = "sf") |> simplify_geometry(keep = 0.1)
}
#> Simple feature collection with 177 features and 3 fields
#> Geometry type: MULTIPOLYGON
#> Dimension:     XY
#> Bounding box:  xmin: -11822650 ymin: -8392928 xmax: 16834490 ymax: 8313194
#> Projected CRS: +proj=eqearth +lon_0=0 +datum=WGS84 +units=m +no_defs
#> First 10 features:
#>    iso3c iso2c        name_long                       geometry
#> 1    FJI    FJ             Fiji MULTIPOLYGON (((16834494 -2...
#> 2    TZA    TZ         Tanzania MULTIPOLYGON (((3749642 -60...
#> 3    ESH    EH   Western Sahara MULTIPOLYGON (((-787363.4 3...
#> 4    CAN    CA           Canada MULTIPOLYGON (((-9909169 64...
#> 5    USA    US    United States MULTIPOLYGON (((-5511945 54...
#> 6    KAZ    KZ       Kazakhstan MULTIPOLYGON (((6717598 518...
#> 7    UZB    UZ       Uzbekistan MULTIPOLYGON (((5942714 517...
#> 8    PNG    PG Papua New Guinea MULTIPOLYGON (((13430098 -1...
#> 9    IDN    ID        Indonesia MULTIPOLYGON (((13430098 -1...
#> 10   ARG    AR        Argentina MULTIPOLYGON (((-5140011 -4...
# }
```
